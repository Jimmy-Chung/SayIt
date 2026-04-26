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

    func addEntry(phrase: String, replacements: [String] = []) {
        loadIfNeeded()
        let entry = DictionaryEntry(phrase: phrase, replacements: replacements)
        entries.append(entry)
        save()
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
