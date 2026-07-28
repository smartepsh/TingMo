import Foundation

extension SherpaOnnxModelDescriptor {
    /// Non-autoregressive Paraformer model for Mandarin and mixed Chinese/English.
    static let paraformerZh = SherpaOnnxModelDescriptor(
        engineID: "paraformer-zh",
        repoID: "csukuangfj/sherpa-onnx-paraformer-zh-2024-03-09",
        folderName: "paraformer-zh",
        engineName: "Paraformer (中/英)",
        modelDisplayName: "Paraformer zh",
        languages: ["zh", "en"],
        languageDisplayName: "中文 / English",
        modelSize: "227 MB",
        files: [
            SherpaOnnxModelFile("model.int8.onnx", reportsProgress: true),
            SherpaOnnxModelFile("tokens.txt"),
        ]
    ) { folder in
        let paraformer = sherpaOnnxOfflineParaformerModelConfig(
            model: folder.appendingPathComponent("model.int8.onnx").path
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: folder.appendingPathComponent("tokens.txt").path,
            paraformer: paraformer,
            numThreads: 2,
            provider: "cpu",
            debug: 0
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        return sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )
    }
}

/// Convenience wrapper used by model-specific tests and direct call sites.
final class ParaformerEngine: SherpaOnnxEngine, @unchecked Sendable {
    static let engineID = SherpaOnnxModelDescriptor.paraformerZh.engineID
    static let languages = SherpaOnnxModelDescriptor.paraformerZh.languages
    static let repoID = SherpaOnnxModelDescriptor.paraformerZh.repoID

    static var modelFolder: URL { SherpaOnnxModelDescriptor.paraformerZh.modelFolder }
    static var modelPath: URL {
        SherpaOnnxModelDescriptor.paraformerZh.fileURL("model.int8.onnx")
    }
    static var tokensPath: URL {
        SherpaOnnxModelDescriptor.paraformerZh.fileURL("tokens.txt")
    }
    static var isModelInstalled: Bool {
        SherpaOnnxModelDescriptor.paraformerZh.isModelInstalled
    }

    init() {
        super.init(descriptor: .paraformerZh)
    }
}
