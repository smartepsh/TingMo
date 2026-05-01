import Foundation

struct LLMCorrectionService {
    func correct(transcript: String, context: [LLMContextItem], config: LLMConfig) async throws -> String {
        guard config.enabled else { return transcript }

        let request = LLMCorrectionRequest(
            transcript: transcript,
            context: context,
            config: config
        )

        let response: LLMCorrectionResponse
        switch config.provider.wireFormat {
        case .openai:
            response = try await OpenAICompatibleLLMProvider().correct(request)
        case .anthropic:
            response = try await AnthropicLLMProvider().correct(request)
        }

        let corrected = response.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return corrected.isEmpty ? transcript : corrected
    }
}
