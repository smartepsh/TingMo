import Foundation
import Observation

/// High-level dictation coordinator: capture audio → transcribe → inject text.
///
/// State machine:
///   idle → recording (on start)
///   recording → transcribing (on stop)
///   transcribing → idle (after injection or error)
@Observable
@MainActor
final class DictationPipeline {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    enum PipelineError: Error, LocalizedError {
        case notReady(reason: String)
        case alreadyRunning
        case notRunning
        case noSpeech
        case deviceUnavailable

        var errorDescription: String? {
            switch self {
            case .notReady(let reason): reason
            case .alreadyRunning: "Dictation is already running."
            case .notRunning: "Dictation is not running."
            case .noSpeech: "No speech detected."
            case .deviceUnavailable: "Microphone unavailable."
            }
        }
    }

    private(set) var state: State = .idle
    /// Last error surfaced by the pipeline, cleared on next start.
    var lastError: Error?

    /// Language tag passed to the engine (ISO code). Read from the active preset.
    var language: String {
        presetStore.defaultPreset.languageCode
    }

    private let registry: EngineRegistry
    private let languagePreference: LanguagePreference
    private let presetStore: ConfigPresetStore
    private let llmInstanceStore: LLMInstanceStore
    private let contextSettings: ContextSettingsStore
    private let correctionService = LLMCorrectionService()
    private let capture = AudioCapture()

    init(
        registry: EngineRegistry,
        languagePreference: LanguagePreference,
        presetStore: ConfigPresetStore,
        llmInstanceStore: LLMInstanceStore,
        contextSettings: ContextSettingsStore
    ) {
        self.registry = registry
        self.languagePreference = languagePreference
        self.presetStore = presetStore
        self.llmInstanceStore = llmInstanceStore
        self.contextSettings = contextSettings
    }

    /// Begin capturing audio. Fast — engine load/download is NOT done here.
    /// - Parameter preferredDeviceUID: Optional input device UID. When nil,
    ///   the system default input is used.
    func start(preferredDeviceUID: String? = nil) throws {
        guard state == .idle else { throw PipelineError.alreadyRunning }

        guard let engine = currentSpeechEngine() else {
            throw PipelineError.notReady(reason: "No speech engine selected.")
        }
        guard engine.info.isReady else {
            throw PipelineError.notReady(reason: "Model '\(engine.info.name)' not downloaded yet.")
        }

        lastError = nil

        do {
            try capture.start(preferredDeviceUID: preferredDeviceUID)
            state = .recording
        } catch {
            // Normalize any capture failure to a user-facing error.
            let surfaced = PipelineError.deviceUnavailable
            lastError = surfaced
            throw surfaced
        }
    }

    /// Stop capture, transcribe, and inject the result.
    /// Fire-and-forget: returns immediately; the pipeline moves to transcribing
    /// then back to idle asynchronously.
    func stopAndTranscribe() {
        guard state == .recording else { return }

        let audioURL: URL
        do {
            audioURL = try capture.stop()
        } catch {
            lastError = error
            state = .idle
            return
        }

        state = .transcribing

        Task { [weak self] in
            guard let self else { return }
            await self.runTranscription(audioURL: audioURL)
        }
    }

    /// Cancel a recording without transcribing.
    func cancel() {
        switch state {
        case .recording:
            capture.cancel()
            state = .idle
        case .transcribing, .idle:
            break
        }
    }

    /// Current live audio peak, 0.0–1.0. Useful for the status indicator.
    var audioLevel: Float {
        capture.audioLevel
    }

    // MARK: - Transcription

    private func runTranscription(audioURL: URL) async {
        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard let engine = currentSpeechEngine() else {
            await finish(error: PipelineError.notReady(reason: "No active engine."))
            return
        }

        do {
            if let whisper = engine as? WhisperKitEngine {
                try await whisper.loadModel()
            }

            let stream = try await engine.transcribe(audioURL: audioURL, language: language)

            var collected = ""
            for await result in stream {
                switch result {
                case .partial(let s), .final(let s): collected = s
                }
            }

            let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            // Whisper's blank sentinel or an empty result means we heard no
            // speech; treat it as a surfaced error rather than silent success.
            let normalized = trimmed.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                await finish(error: PipelineError.noSpeech)
                return
            }

            let correctionResult = await correctIfNeeded(normalized)
            try await TextInjector.shared.inject(correctionResult.text)
            await finish(error: correctionResult.warning)
        } catch {
            NSLog("[TingMo] transcription error: \(error)")
            await finish(error: error)
        }
    }

    private func correctIfNeeded(_ transcript: String) async -> (text: String, warning: Error?) {
        let preset = presetStore.defaultPreset
        guard preset.correctionEnabled else { return (transcript, nil) }
        guard let llmConfig = llmInstanceStore.llmConfig(for: preset) else {
            return (transcript, PipelineError.notReady(reason: "No LLM correction instance selected."))
        }

        do {
            let context = ContextAggregator(settings: contextSettings).collect()
            if contextSettings.debugLoggingEnabled {
                ContextDebugLogger.log(context)
            }
            let corrected = try await correctionService.correct(
                transcript: transcript,
                context: context,
                config: llmConfig
            )
            return (corrected, nil)
        } catch {
            NSLog("[TingMo] LLM correction failed, falling back to raw transcript: \(error)")
            return (transcript, error)
        }
    }

    private func finish(error: Error?) async {
        lastError = error
        state = .idle
    }

    private func currentSpeechEngine() -> (any SpeechEngine)? {
        registry.engine(id: presetStore.defaultPreset.speechEngineID)
    }
}
