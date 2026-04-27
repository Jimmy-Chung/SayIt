import Foundation

struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    var phrase: String       // 正确的词
    var replacements: [String] // 常见误识形式

    init(id: UUID = UUID(), phrase: String, replacements: [String] = []) {
        self.id = id
        self.phrase = phrase
        self.replacements = replacements
    }
}

final class UserDictionary {

    static let shared = UserDictionary()
    private init() {}

    private var entries: [DictionaryEntry] = []
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayIt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    private var loaded = false

    var allEntries: [DictionaryEntry] {
        loadIfNeeded()
        return entries
    }

    /// 构建用于 whisper.cpp initial_prompt 的词汇提示（拼接所有自定义词汇）
    var whisperPromptSuffix: String {
        loadIfNeeded()
        guard !entries.isEmpty else { return "" }
        return " " + entries.map(\.phrase).joined(separator: " ")
    }

    /// 构建 LLM 优化用的词典提示，指导模型按用户习惯修正转写
    var dictionaryPrompt: String {
        loadIfNeeded()
        let pairs = entries.flatMap { entry in
            entry.replacements.map { wrong in "'\(wrong)'→'\(entry.phrase)'" }
        }
        guard !pairs.isEmpty else { return "" }
        return "\n\n## 用户词典（ASR 修正）\n以下是用户积累的语音识别修正对，遇到左侧的误识词必须替换为右侧的正确词：\n" + pairs.joined(separator: "、")
    }

    func addEntry(phrase: String, replacements: [String] = []) {
        loadIfNeeded()
        let entry = DictionaryEntry(phrase: phrase, replacements: replacements)
        entries.append(entry)
        save()
    }

    /// 自动学习修正词对：若 correct 已存在则追加 wrong 到 replacements，否则新建条目
    func addCorrection(wrong: String, correct: String) {
        loadIfNeeded()
        // 已存在相同的误识形式则跳过
        if entries.contains(where: { $0.replacements.contains(wrong) && $0.phrase == correct }) { return }
        // correct 已有条目，追加误识形式
        if let idx = entries.firstIndex(where: { $0.phrase == correct }) {
            entries[idx].replacements.append(wrong)
        } else {
            entries.append(DictionaryEntry(phrase: correct, replacements: [wrong]))
        }
        save()
        dbg("[UserDictionary] 自动学习: '\(wrong)' → '\(correct)'")
    }

    func deleteEntry(id: UUID) {
        loadIfNeeded()
        entries.removeAll { $0.id == id }
        save()
    }

    func replaceAll(_ entries: [DictionaryEntry]) {
        self.entries = entries
        save()
    }

    /// 对文本做后处理替换（将误识形式替换为正确词汇）
    func correct(_ text: String) -> String {
        loadIfNeeded()
        var result = text
        for entry in entries {
            for wrong in entry.replacements {
                result = result.replacingOccurrences(of: wrong, with: entry.phrase)
            }
        }
        return result
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
