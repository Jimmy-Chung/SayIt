import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case none     = "none"
    case deepseek = "deepseek"
    case gemini   = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:     return "不使用"
        case .deepseek: return "DeepSeek"
        case .gemini:   return "Gemini"
        }
    }

    var apiKeyStorageKey: String {
        switch self {
        case .none:     return ""
        case .deepseek: return "deepseekApiKey"
        case .gemini:   return "geminiApiKey"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .none:     return ""
        case .deepseek: return "sk-..."
        case .gemini:   return "AIza..."
        }
    }
}
