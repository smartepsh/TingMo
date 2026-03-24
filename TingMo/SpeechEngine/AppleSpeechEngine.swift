import Foundation
import Speech

/// Apple Speech Framework engine — zero-download, real-time streaming.
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    static let engineID = "apple-speech"

    let info: EngineInfo

    init() {
        self.info = EngineInfo(
            id: Self.engineID,
            name: "Apple Speech",
            type: .local,
            supportedLanguages: Self.supportedLanguages,
            supportsStreaming: true,
            modelSize: nil,
            isReady: true
        )
    }

    func transcribe(audioURL: URL, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechEngineError.unsupportedLanguage(language)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return AsyncStream { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    continuation.yield(.final(result.bestTranscription.formattedString))
                    continuation.finish()
                } else if let error {
                    continuation.yield(.final(""))
                    continuation.finish()
                    _ = error // logged externally
                }
            }
        }
    }

    func startStreaming(language: String) async throws -> (stream: AsyncStream<TranscriptionResult>, stop: @Sendable () -> Void) {
        guard supportsLanguage(language) else { throw SpeechEngineError.unsupportedLanguage(language) }

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechEngineError.unsupportedLanguage(language)
        }

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        try audioEngine.start()

        let taskHolder = UncheckedSendable<SFSpeechRecognitionTask?>(value: nil)
        let engineHolder = UncheckedSendable<AVAudioEngine?>(value: audioEngine)

        let stream = AsyncStream<TranscriptionResult> { continuation in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    if result.isFinal {
                        continuation.yield(.final(result.bestTranscription.formattedString))
                        continuation.finish()
                    } else {
                        continuation.yield(.partial(result.bestTranscription.formattedString))
                    }
                } else if error != nil {
                    continuation.finish()
                }
            }
            taskHolder.setValue(task)
        }

        let stop: @Sendable () -> Void = {
            taskHolder.value?.finish()
            engineHolder.value?.inputNode.removeTap(onBus: 0)
            engineHolder.value?.stop()
            request.endAudio()
        }

        return (stream, stop)
    }

    private static var supportedLanguages: [String] {
        SFSpeechRecognizer.supportedLocales().map(\.identifier)
    }
}

private final class UncheckedSendable<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
    func setValue(_ newValue: T) { value = newValue }
}
