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
        guard state == .idle else {
            NSLog("[TingMo][Pipeline] start aborted — already running (state=\(state))")
            throw PipelineError.alreadyRunning
        }

        guard let engine = registry.activeEngine else {
            NSLog("[TingMo][Pipeline] start aborted — no active engine")
            throw PipelineError.notReady(reason: "No speech engine selected.")
        }
        guard engine.info.isReady else {
            NSLog("[TingMo][Pipeline] start aborted — engine '\(engine.info.id)' not ready")
            throw PipelineError.notReady(reason: "Model '\(engine.info.name)' not downloaded yet.")
        }

        lastError = nil
        NSLog("[TingMo][Pipeline] start engine=\(engine.info.id) language='\(language)' deviceUID=\(preferredDeviceUID ?? "default")")

        do {
            try capture.start(preferredDeviceUID: preferredDeviceUID)
            state = .recording
            NSLog("[TingMo][Pipeline] state → recording")
        } catch {
            NSLog("[TingMo][Pipeline] capture.start FAILED error=\(error)")
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
        guard state == .recording else {
            NSLog("[TingMo][Pipeline] stopAndTranscribe ignored — state=\(state)")
            return
        }

        let audioURL: URL
        do {
            audioURL = try capture.stop()
        } catch {
            NSLog("[TingMo][Pipeline] capture.stop FAILED error=\(error)")
            lastError = error
            state = .idle
            return
        }

        let audioSize = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        NSLog("[TingMo][Pipeline] state → transcribing (audio=\(audioURL.lastPathComponent) size=\(audioSize))")
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
            NSLog("[TingMo][Pipeline] cancel — dropping capture, state → idle")
            capture.cancel()
            state = .idle
        case .transcribing, .idle:
            NSLog("[TingMo][Pipeline] cancel ignored (state=\(state))")
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
            NSLog("[TingMo][Pipeline] runTranscription aborted — no active engine")
            await finish(error: PipelineError.notReady(reason: "No active engine."))
            return
        }

        NSLog("[TingMo][Pipeline] runTranscription engine=\(engine.info.id) language='\(language)'")
        let clock = ContinuousClock()
        let startTime = clock.now

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
            NSLog("[TingMo][Pipeline] transcription complete elapsed=\(clock.now - startTime) chars=\(normalized.count)")
            if normalized.isEmpty {
                NSLog("[TingMo][Pipeline] no speech detected — surfacing .noSpeech")
                await finish(error: PipelineError.noSpeech)
                return
            }
            try await TextInjector.shared.inject(normalized)
            NSLog("[TingMo][Pipeline] inject success")
            await finish(error: nil)
        } catch {
            NSLog("[TingMo][Pipeline] runTranscription FAILED elapsed=\(clock.now - startTime) error=\(error)")
            await finish(error: error)
        }
    }

    private func finish(error: Error?) async {
        NSLog("[TingMo][Pipeline] state → idle (error=\(error.map { "\($0)" } ?? "none"))")
        lastError = error
        state = .idle
    }
}
