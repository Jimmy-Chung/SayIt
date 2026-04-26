import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case none     = "none"
    case deepseek = "deepseek"
    case gemini   = "gemini"
    case minimax  = "minimax"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:     return "不使用"
        case .deepseek: return "DeepSeek"
        case .gemini:   return "Gemini"
        case .minimax:  return "MiniMax"
        }
    }

    var apiKeyStorageKey: String {
        switch self {
        case .none:     return ""
        case .deepseek: return "deepseekApiKey"
        case .gemini:   return "geminiApiKey"
        case .minimax:  return "minimaxApiKey"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .none:     return ""
        case .deepseek: return "sk-..."
        case .gemini:   return "AIza..."
        case .minimax:  return "eyJ..."
        }
    }
}
