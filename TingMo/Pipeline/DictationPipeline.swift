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

    /// Language tag passed to the engine (ISO code). Read from the shared
    /// `LanguagePreference` so settings changes propagate immediately.
    var language: String {
        languagePreference.current
    }

    private let registry: EngineRegistry
    private let languagePreference: LanguagePreference
    private let capture = AudioCapture()

    init(registry: EngineRegistry, languagePreference: LanguagePreference) {
        self.registry = registry
        self.languagePreference = languagePreference
    }

    /// Begin capturing audio. Fast — engine load/download is NOT done here.
    /// - Parameter preferredDeviceUID: Optional input device UID. When nil,
    ///   the system default input is used.
    func start(preferredDeviceUID: String? = nil) throws {
        guard state == .idle else { throw PipelineError.alreadyRunning }

        guard let engine = registry.activeEngine else {
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

        guard let engine = registry.activeEngine else {
            await finish(error: PipelineError.notReady(reason: "No active engine."))
            return
        }

        do {
            if engine is WhisperKitEngine {
                try await registry.loadActiveEngine()
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
            try await TextInjector.shared.inject(normalized)
            await finish(error: nil)
        } catch {
            NSLog("[TingMo] transcription error: \(error)")
            await finish(error: error)
        }
    }

    private func finish(error: Error?) async {
        lastError = error
        state = .idle
    }
}
