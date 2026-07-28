import Foundation

extension SherpaOnnxModelDescriptor {
    /// Stock SenseVoiceSmall exported by sherpa-onnx.
    ///
    /// This tag is deliberately pinned. The similarly named 2025-09-09 model
    /// is an ASLP-lab WSYue Cantonese fine-tune, not a newer general-purpose
    /// SenseVoice weight, and regresses Mandarin, Japanese and Korean. The 2026
    /// SenseVoiceSmall-GGUF release is a new llama.cpp/ggml packaging of the
    /// same 2024 source weights and is not loadable by sherpa-onnx. Do not bump
    /// this repo based on its date without benchmarking all five languages.
    static let senseVoice = SherpaOnnxModelDescriptor(
        engineID: "sensevoice",
        repoID: "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
        folderName: "sensevoice",
        engineName: "SenseVoice (中/粤/英/日/韩)",
        modelDisplayName: "SenseVoice Small",
        languages: ["zh", "yue", "en", "ja", "ko"],
        languageDisplayName: "中文 / 粤语 / English / 日本語 / 한국어",
        modelSize: "226 MB",
        files: [
            SherpaOnnxModelFile("model.int8.onnx", reportsProgress: true),
            SherpaOnnxModelFile("tokens.txt"),
        ]
    ) { folder in
        // An empty language lets SenseVoice auto-detect across all five
        // supported languages. ITN preserves the existing punctuation and
        // number-normalization behavior.
        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: folder.appendingPathComponent("model.int8.onnx").path,
            language: "",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: folder.appendingPathComponent("tokens.txt").path,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            senseVoice: senseVoice
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        return sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )
    }
}

/// Compatibility wrapper for existing SenseVoice call sites and tests.
final class SenseVoiceEngine: SherpaOnnxEngine, @unchecked Sendable {
    static let engineID = SherpaOnnxModelDescriptor.senseVoice.engineID
    static let languages = SherpaOnnxModelDescriptor.senseVoice.languages
    static let repoID = SherpaOnnxModelDescriptor.senseVoice.repoID

    static var modelFolder: URL { SherpaOnnxModelDescriptor.senseVoice.modelFolder }
    static var modelPath: URL {
        SherpaOnnxModelDescriptor.senseVoice.fileURL("model.int8.onnx")
    }
    static var tokensPath: URL {
        SherpaOnnxModelDescriptor.senseVoice.fileURL("tokens.txt")
    }
    static var isModelInstalled: Bool {
        SherpaOnnxModelDescriptor.senseVoice.isModelInstalled
    }

    init() {
        super.init(descriptor: .senseVoice)
    }
}
