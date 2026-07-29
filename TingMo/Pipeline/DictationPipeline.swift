import AppKit
import Foundation
import Observation

/// High-level dictation coordinator: capture audio → transcribe → translate → inject text.
///
/// State machine:
///   idle → preparing (asynchronous media check/pause)
///   preparing → recording (after capture starts)
///   recording → transcribing (on stop)
///   transcribing → idle (after injection, media cleanup, or error)
@Observable
@MainActor
final class DictationPipeline {
    private static let maximumRecordingDuration: Duration = .seconds(30 * 60)

    enum State: Equatable {
        case idle
        case preparing
        case recording
        case transcribing
    }

    enum PipelineError: Error, LocalizedError {
        case notReady(reason: String)
        case modelPreparing(name: String)
        case modelPreparationFailed(name: String, reason: String)
        case alreadyRunning
        case notRunning
        case noSpeech
        case deviceUnavailable

        var errorDescription: String? {
            switch self {
            case .notReady(let reason): reason
            case .modelPreparing(let name):
                "Preparing '\(name)'… Try again shortly."
            case .modelPreparationFailed(let name, let reason):
                "Speech model '\(name)' failed to prepare: \(reason). Retrying now."
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

    private let registry: EngineRegistry
    private let languagePreference: LanguagePreference
    private let presetStore: ConfigPresetStore
    private let llmInstanceStore: LLMInstanceStore
    private let contextSettings: ContextSettingsStore
    private let correctionService = LLMCorrectionService()
    private let capture = AudioCapture()
    private let mediaGuard = MediaPlaybackGuard()
    private let ocrCollector = ScreenshotOCRCollector()
    private let basicCollector = BasicContextCollector()
    private var storedOCRText: String?
    private var ocrTask: Task<Void, Never>?
    private var storedContextSnapshot: [LLMContextItem] = []
    private var storedTargetPID: pid_t?
    private var storedTargetAppName: String?
    private var mediaSessionID: UUID?
    private var startTask: Task<Void, Never>?
    private var recordingTimeoutTask: Task<Void, Never>?
    private var mediaCleanupTask: Task<Void, Never>?

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

    /// Begin a recording session. Engine validation is synchronous; media
    /// inspection/pause and microphone startup continue asynchronously while
    /// state is `.preparing`.
    func start(preferredDeviceUID: String? = nil) throws {
        guard state == .idle else { throw PipelineError.alreadyRunning }
        lastError = nil

        guard let engine = currentSpeechEngine() else {
            throw PipelineError.notReady(reason: "No speech engine selected.")
        }
        if engine is any DownloadableEngine {
            switch registry.preparationState(for: engine.info.id) {
            case .ready:
                break
            case .notDownloaded:
                throw PipelineError.notReady(
                    reason: "Model '\(engine.info.name)' has not been downloaded yet."
                )
            case .unloaded:
                registry.prepareEngine(engine.info.id)
                throw PipelineError.modelPreparing(name: engine.info.name)
            case .preparing:
                throw PipelineError.modelPreparing(name: engine.info.name)
            case .failed(let reason):
                registry.prepareEngine(engine.info.id, downloadIfNeeded: true)
                throw PipelineError.modelPreparationFailed(
                    name: engine.info.name,
                    reason: reason
                )
            }
        } else if !engine.info.isReady {
            throw PipelineError.notReady(reason: "Speech engine '\(engine.info.name)' is not ready.")
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let targetPID = frontmost?.processIdentifier
        let targetAppName = frontmost?.localizedName
        storedTargetPID = targetPID
        storedTargetAppName = targetAppName
        storedContextSnapshot = basicCollector.collect(
            targetPID: targetPID,
            targetAppName: targetAppName
        )

        let sessionID = UUID()
        mediaSessionID = sessionID
        state = .preparing
        startTask = Task { [weak self] in
            await self?.prepareCapture(
                sessionID: sessionID,
                preferredDeviceUID: preferredDeviceUID,
                targetPID: targetPID
            )
        }
    }

    private func prepareCapture(
        sessionID: UUID,
        preferredDeviceUID: String?,
        targetPID: pid_t?
    ) async {
        let mediaResult = await mediaGuard.beginSession(id: sessionID)

        guard !Task.isCancelled,
              state == .preparing,
              mediaSessionID == sessionID
        else {
            await mediaGuard.cancelSession(id: sessionID)
            return
        }

        if mediaResult == .unverified {
            NSLog("[TingMo] MediaRemote state unavailable; recording continues without a media command")
        }

        do {
            try capture.start(preferredDeviceUID: preferredDeviceUID)
            startTask = nil
            state = .recording
            scheduleRecordingTimeout()

            if contextSettings.screenshotOCREnabled {
                storedOCRText = nil
                ocrTask = Task { [weak self, targetPID] in
                    guard let self else { return }
                    let result = await self.ocrCollector.captureAndRecognize(targetPID: targetPID)
                    if !Task.isCancelled {
                        self.storedOCRText = result
                    }
                }
            }
        } catch {
            await mediaGuard.cancelSession(id: sessionID)
            guard mediaSessionID == sessionID else { return }
            startTask = nil
            mediaSessionID = nil
            clearStoredContext()
            lastError = PipelineError.deviceUnavailable
            state = .idle
        }
    }

    /// Stop capture, transcribe, and inject the result.
    /// Fire-and-forget: returns immediately; the pipeline moves to transcribing
    /// then back to idle asynchronously.
    func stopAndTranscribe() {
        guard state == .recording else { return }
        cancelRecordingTimeout()

        let sessionID = mediaSessionID
        mediaSessionID = nil

        let audioURL: URL
        do {
            audioURL = try capture.stop()
        } catch {
            state = .transcribing
            scheduleMediaCleanup(sessionID: sessionID, cancelled: false)
            Task { [weak self] in
                await self?.finish(error: error)
            }
            return
        }

        // The microphone is closed before playback can resume. Media cleanup
        // and transcription then proceed concurrently without blocking UI.
        state = .transcribing
        scheduleMediaCleanup(sessionID: sessionID, cancelled: false)

        Task { [weak self] in
            guard let self else { return }
            await self.runTranscription(audioURL: audioURL)
        }
    }

    /// Cancel a pending or active recording without transcribing.
    func cancel() {
        switch state {
        case .preparing:
            cancelPendingStart()
        case .recording:
            cancelRecordingTimeout()
            ocrTask?.cancel()
            ocrTask = nil
            storedOCRText = nil
            capture.cancel()

            let sessionID = mediaSessionID
            mediaSessionID = nil
            state = .transcribing
            scheduleMediaCleanup(sessionID: sessionID, cancelled: true)
            Task { [weak self] in
                guard let self else { return }
                self.clearStoredContext()
                await self.finish(error: nil)
            }
        case .transcribing, .idle:
            break
        }
    }

    private func cancelPendingStart() {
        guard let sessionID = mediaSessionID else {
            state = .idle
            return
        }

        startTask?.cancel()
        startTask = nil
        Task { [weak self] in
            guard let self else { return }
            await self.mediaGuard.cancelSession(id: sessionID)
            guard self.state == .preparing,
                  self.mediaSessionID == sessionID
            else { return }

            self.mediaSessionID = nil
            self.clearStoredContext()
            self.state = .idle
        }
    }

    private func scheduleRecordingTimeout() {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.maximumRecordingDuration)
            } catch {
                return
            }

            guard let self, self.state == .recording else { return }
            self.recordingTimeoutTask = nil
            NSLog("[TingMo] Maximum recording duration reached; stopping after 30 minutes")
            self.stopAndTranscribe()
        }
    }

    private func cancelRecordingTimeout() {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil
    }

    private func scheduleMediaCleanup(sessionID: UUID?, cancelled: Bool) {
        guard let sessionID else {
            mediaCleanupTask = nil
            return
        }

        mediaCleanupTask = Task { [mediaGuard] in
            if cancelled {
                await mediaGuard.cancelSession(id: sessionID)
            } else {
                await mediaGuard.endSession(id: sessionID)
            }
        }
    }

    private func clearStoredContext() {
        storedOCRText = nil
        storedContextSnapshot = []
        storedTargetPID = nil
        storedTargetAppName = nil
    }

    /// Current live audio peak, 0.0–1.0. Useful for the status indicator.
    var audioLevel: Float {
        capture.audioLevel
    }

    /// UID of the input device the active capture is bound to, if any.
    var activeDeviceUID: String? {
        capture.activeDeviceUID
    }

    // MARK: - Transcription

    private func runTranscription(audioURL: URL) async {
        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard let engine = currentSpeechEngine() else {
            await finish(error: PipelineError.notReady(reason: "No active engine."))
            return
        }

        do {
            if let downloadable = engine as? any DownloadableEngine {
                try await downloadable.loadModel()
            }

            // Pass empty language for auto-detect (multi-language input)
            let stream = try await engine.transcribe(audioURL: audioURL, language: "")

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

            let finalText = await translateIfNeeded(normalized)
            let correctionResult = await correctIfNeeded(finalText)
            try TextInjector.shared.inject(correctionResult.text)
            await finish(error: correctionResult.warning)
        } catch {
            NSLog("[TingMo] transcription error: \(error)")
            await finish(error: error)
        }
    }

    // MARK: - Translation

    private func translateIfNeeded(_ transcript: String) async -> String {
        let outputLanguage = presetStore.defaultPreset.outputLanguage

        // No translation if output is "raw" or empty
        guard outputLanguage != ConfigPreset.rawOutputLanguage, !outputLanguage.isEmpty else {
            return transcript
        }

        // Check if LLM is available for translation
        guard let llmConfig = llmInstanceStore.llmConfig(for: presetStore.defaultPreset) else {
            NSLog("[TingMo] No LLM configured for translation, returning raw transcript")
            return transcript
        }

        do {
            let targetLanguageName = LanguagePreference.displayName(for: outputLanguage)
            let translationPrompt = """
            Translate the following text to \(targetLanguageName).
            Preserve the original meaning and tone. Output ONLY the translated text, nothing else.

            Text to translate:
            \(transcript)
            """

            let translationConfig = LLMConfig(
                enabled: true,
                provider: llmConfig.provider,
                endpoint: llmConfig.endpoint,
                model: llmConfig.model,
                systemPrompt: translationPrompt,
                temperature: 0.3,
                keychainService: llmConfig.keychainService
            )

            let translated = try await correctionService.correct(
                transcript: transcript,
                context: [],
                config: translationConfig
            )
            return translated
        } catch {
            NSLog("[TingMo] Translation failed, falling back to raw transcript: \(error)")
            return transcript
        }
    }

    // MARK: - Correction

    private func correctIfNeeded(_ transcript: String) async -> (text: String, warning: Error?) {
        let preset = presetStore.defaultPreset
        // `llmInstanceID` is the single source of truth for whether correction
        // runs; the menu's first item clears it. (`ConfigPreset.correctionEnabled`
        // exists in the stored model but is never read or surfaced in the UI.)
        guard preset.llmInstanceID != nil else { return (transcript, nil) }
        guard let llmConfig = llmInstanceStore.llmConfig(for: preset) else {
            return (transcript, PipelineError.notReady(reason: "No LLM correction instance selected."))
        }

        do {
            var context = ContextAggregator(settings: contextSettings, skipOCR: true).collect(
                snapshot: storedContextSnapshot,
                targetPID: storedTargetPID,
                targetAppName: storedTargetAppName
            )

            if let ocrText = storedOCRText {
                let priority = ContextDefaults.source(for: .screenshotOCR)?.priority ?? 60
                context.append(LLMContextItem(kind: .screenshotOCR, text: ocrText, priority: priority))
                storedOCRText = nil
            }
            #if DEBUG
            ContextDebugLogger.log(context, budget: contextSettings.maxTotalCharacters)
            #endif
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
        // Media teardown is not awaited: `endSession` makes a Now Playing query
        // that costs a ~170 ms perl round-trip and is allowed up to 2 s, all of
        // it after the text has already been injected. Awaiting it kept the
        // pipeline out of `.idle` for that whole window, so a hotkey press right
        // after the text appeared was dropped and recording seemed unresponsive.
        //
        // Letting it run on is safe: `MediaPlaybackGuard` serializes on its own
        // queue and ignores a session that is no longer active, so a late
        // teardown cannot disturb a session started in the meantime.
        mediaCleanupTask = nil
        // The OCR task is awaited by value, not cancelled — its result feeds
        // correction context mid-transcription. Release the handle here, the
        // single exit point for every path, so it does not outlive the session.
        ocrTask = nil
        storedOCRText = nil
        lastError = error
        state = .idle
    }

    private func currentSpeechEngine() -> (any SpeechEngine)? {
        registry.engine(id: presetStore.defaultPreset.speechEngineID)
    }
}
