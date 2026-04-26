import Foundation

final class VoiceCommandProcessor {

    static let shared = VoiceCommandProcessor()

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "voiceCommands") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voiceCommands") }
    }

    private struct Command {
        let triggers: [String]
        let replacement: String
        let isLiteral: Bool // true = 直接替换, false = 删除前一词
    }

    private let commands: [Command] = [
        // 换行
        Command(triggers: ["换行", "新行", "回车", "new line", "newline"], replacement: "\n", isLiteral: true),
        // 中文标点
        Command(triggers: ["句号"], replacement: "。", isLiteral: true),
        Command(triggers: ["逗号"], replacement: "，", isLiteral: true),
        Command(triggers: ["问号"], replacement: "？", isLiteral: true),
        Command(triggers: ["感叹号", "叹号"], replacement: "！", isLiteral: true),
        Command(triggers: ["顿号"], replacement: "、", isLiteral: true),
        Command(triggers: ["冒号"], replacement: "：", isLiteral: true),
        Command(triggers: ["分号"], replacement: "；", isLiteral: true),
        Command(triggers: ["左引号", "上引号"], replacement: "\u{201C}", isLiteral: true),
        Command(triggers: ["右引号", "下引号"], replacement: "\u{201D}", isLiteral: true),
        Command(triggers: ["省略号"], replacement: "……", isLiteral: true),
        Command(triggers: ["破折号"], replacement: "——", isLiteral: true),
        Command(triggers: ["制表符", "Tab"], replacement: "\t", isLiteral: true),
        // 英文标点
        Command(triggers: ["period"], replacement: ".", isLiteral: true),
        Command(triggers: ["comma"], replacement: ",", isLiteral: true),
        Command(triggers: ["question mark"], replacement: "?", isLiteral: true),
        Command(triggers: ["exclamation mark"], replacement: "!", isLiteral: true),
        Command(triggers: ["colon"], replacement: ":", isLiteral: true),
        Command(triggers: ["semicolon"], replacement: ";", isLiteral: true),
        // 删除
        Command(triggers: ["删除", "delete", "backspace"], replacement: "", isLiteral: false),
    ]

    func process(_ text: String) -> String {
        guard isEnabled else { return text }

        var result = text

        for cmd in commands {
            for trigger in cmd.triggers {
                if cmd.isLiteral {
                    result = replaceTrigger(trigger, in: result, with: cmd.replacement)
                } else {
                    result = deletePrecedingWord(trigger, in: result)
                }
            }
        }

        return result
    }

    /// 替换触发词为对应符号，处理中文（无空格分词）和英文（有空格）
    private func replaceTrigger(_ trigger: String, in text: String, with replacement: String) -> String {
        // 中文触发词直接全局替换（中文文本没有空格分隔）
        // 英文触发词需要边界检查
        let isEnglish = trigger.allSatisfy { $0.isASCII && $0.isLetter }

        if isEnglish {
            // 用 \b 边界匹配英文触发词
            guard let regex = try? NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: trigger) + "\\b",
                options: [.caseInsensitive]
            ) else { return text }
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        } else {
            // 中文直接替换
            return text.replacingOccurrences(of: trigger, with: replacement)
        }
    }

    /// 删除触发词前面的一个词/字符
    private func deletePrecedingWord(_ trigger: String, in text: String) -> String {
        guard let range = text.range(of: trigger) else { return text }

        let beforeTrigger = text[text.startIndex..<range.lowerBound]
        let afterTrigger = text[range.upperBound...]

        guard !beforeTrigger.isEmpty else {
            return String(afterTrigger)
        }

        // 找到前一个"词"的边界
        // 对于中文：删除前一个字符
        // 对于英文：删除前一个空格分隔的词
        let trimmed = beforeTrigger
        let lastChar = trimmed.last!

        if lastChar.isWhitespace {
            // 如果触发词前是空格，删除空格和它前面的词
            let withoutTrailingSpace = trimmed.dropLast()
            if let lastSpace = withoutTrailingSpace.lastIndex(of: " ") {
                return String(text[text.startIndex...lastSpace]) + String(afterTrigger)
            } else {
                return String(afterTrigger)
            }
        } else {
            // 删除前一个字符（适用于中文）
            let cutIndex = trimmed.index(before: trimmed.endIndex)
            return String(text[text.startIndex..<cutIndex]) + String(afterTrigger)
        }
    }
}
