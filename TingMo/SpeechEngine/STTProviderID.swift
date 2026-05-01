import Foundation

/// Supported speech-to-text providers.
enum STTProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case groq
    case openai
    case deepgram
    case assemblyai
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: "Groq"
        case .openai: "OpenAI"
        case .deepgram: "Deepgram"
        case .assemblyai: "AssemblyAI"
        case .google: "Google"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq: "whisper-large-v3-turbo"
        case .openai: "whisper-1"
        case .deepgram: "nova-2"
        case .assemblyai: "best"
        case .google: "latest_long"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .groq: "https://api.groq.com/openai/v1"
        case .openai: "https://api.openai.com/v1"
        case .deepgram: "https://api.deepgram.com/v1"
        case .assemblyai: "https://api.assemblyai.com/v2"
        case .google: "https://speech.googleapis.com/v1"
        }
    }

    var keychainService: String {
        switch self {
        case .groq: "tingmo.stt.groq"
        case .openai: "tingmo.stt.openai"
        case .deepgram: "tingmo.stt.deepgram"
        case .assemblyai: "tingmo.stt.assemblyai"
        case .google: "tingmo.stt.google"
        }
    }
}
