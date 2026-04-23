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

        var errorDescription: String? {
            switch self {
            case .notReady(let reason): reason
            case .alreadyRunning: "Dictation is already running."
            case .notRunning: "Dictation is not running."
            }
        }
    }

    private(set) var state: State = .idle
    /// Last error surfaced by the pipeline, cleared on next start.
    var lastError: Error?

    /// Language tag passed to the engine (ISO code). Empty string means
    /// let the engine auto-detect — M1 default until config presets exist.
    var language: String = ""

    private let registry: EngineRegistry
    private let capture = AudioCapture()

    init(registry: EngineRegistry) {
        self.registry = registry
    }

    /// Begin capturing audio. Fast — engine load/download is NOT done here.
    func start() throws {
        guard state == .idle else { throw PipelineError.alreadyRunning }

        guard let engine = registry.activeEngine else {
            throw PipelineError.notReady(reason: "No speech engine selected.")
        }
        guard engine.info.isReady else {
            throw PipelineError.notReady(reason: "Model '\(engine.info.name)' not downloaded yet.")
        }

        lastError = nil

        do {
            try capture.start()
            state = .recording
        } catch {
            lastError = error
            throw error
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

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        NSLog("[TingMo] transcription start: audioURL=\(audioURL.lastPathComponent) size=\(fileSize)B")

        guard let engine = registry.activeEngine else {
            NSLog("[TingMo] no active engine")
            await finish(error: PipelineError.notReady(reason: "No active engine."))
            return
        }

        do {
            if let whisper = engine as? WhisperKitEngine {
                NSLog("[TingMo] loading WhisperKit model…")
                try await whisper.loadModel()
                NSLog("[TingMo] WhisperKit loaded")
            }

            NSLog("[TingMo] calling engine.transcribe lang=\(language)")
            let stream = try await engine.transcribe(audioURL: audioURL, language: language)

            var collected = ""
            for await result in stream {
                switch result {
                case .partial(let s): collected = s; NSLog("[TingMo] partial: \(s)")
                case .final(let s): collected = s; NSLog("[TingMo] final: \(s)")
                }
            }

            let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[TingMo] transcription done; chars=\(trimmed.count); text=\(trimmed)")
            if !trimmed.isEmpty {
                try await TextInjector.shared.inject(trimmed)
                NSLog("[TingMo] inject OK")
            } else {
                NSLog("[TingMo] empty transcription; nothing to inject")
            }
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
