import AppKit

enum AppContext: String, CaseIterable, Identifiable {
    case email
    case messaging
    case code
    case document
    case note
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .email:     return "邮件"
        case .messaging: return "聊天"
        case .code:      return "代码"
        case .document:  return "文档"
        case .note:      return "笔记"
        case .general:   return "通用"
        }
    }

    var llmPromptSuffix: String {
        switch self {
        case .email:
            return "\n\n补充规则：用户正在撰写邮件。使用专业正式的语气，保留称呼和落款结构。避免口语化表达。"
        case .messaging:
            return "\n\n补充规则：用户正在聊天应用中输入。保持简洁随意，适合即时通讯的短句风格。不要添加问候语或结束语。"
        case .code:
            return "\n\n补充规则：用户正在代码编辑器中输入。严格保留技术术语原文，不要翻译。代码标识符用反引号包裹。保持技术精确性。"
        case .document:
            return "\n\n补充规则：用户正在编辑正式文档。使用规范的书面语，结构清晰，适合文档阅读。"
        case .note:
            return "\n\n补充规则：用户正在记笔记。保持简洁，保留要点结构，适合快速回顾。"
        case .general:
            return ""
        }
    }
}

final class ContextProvider {

    static let shared = ContextProvider()
    private init() {}

    private static let appMapping: [String: AppContext] = [
        // 邮件
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.spark.mail-app": .email,
        "com.airmailapp.mac": .email,
        // 聊天
        "com.tinyspeck.slackmacgap": .messaging,
        "com.hnc.Discord": .messaging,
        "com.tencent.xinWeChat": .messaging,
        "com.apple.iChat": .messaging,
        "org.telegram.desktop": .messaging,
        "com.readdle.Telegram": .messaging,
        "com.microsoft.teams": .messaging,
        // 代码
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.microsoft.VSCodeInsiders": .code,
        "com.googlecode.iterm2": .code,
        "com.apple.Terminal": .code,
        "dev.warp.Warp-Stable": .code,
        "com.github.wez.wezterm": .code,
        // 文档
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
        "com.google.Chrome": .document, // 可能是 Google Docs
        "com.microsoft.edgemac": .document,
        // 笔记
        "com.apple.Notes": .note,
        "notion.id": .note,
        "bear.id": .note,
    ]

    func detect() -> AppContext {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return .general
        }
        return ContextProvider.appMapping[bundleId] ?? .general
    }
}
