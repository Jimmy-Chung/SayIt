import Foundation
import AppKit

struct Snippet: Codable, Identifiable {
    let id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

final class SnippetManager {

    static let shared = SnippetManager()
    private init() {}

    private var snippets: [Snippet] = []
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayIt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    private var loaded = false

    var allSnippets: [Snippet] {
        loadIfNeeded()
        return snippets
    }

    func addSnippet(trigger: String, expansion: String) {
        loadIfNeeded()
        snippets.append(Snippet(trigger: trigger, expansion: expansion))
        save()
    }

    func deleteSnippet(id: UUID) {
        loadIfNeeded()
        snippets.removeAll { $0.id == id }
        save()
    }

    func replaceAll(_ snippets: [Snippet]) {
        self.snippets = snippets
        save()
    }

    /// 检查文本是否匹配某个 snippet 触发词，返回展开后的文本
    /// 如果整段文本（去掉首尾空白）与触发词足够相似（编辑距离 ≤ 1），则展开
    func process(_ text: String) -> String {
        loadIfNeeded()
        guard !snippets.isEmpty else { return text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for snippet in snippets {
            if trimmed == snippet.trigger {
                return expand(snippet.expansion)
            }
            // 模糊匹配：允许 1 个字符的差异
            if levenshtein(trimmed, snippet.trigger) <= 1 {
                return expand(snippet.expansion)
            }
        }
        return text
    }

    /// 展开模板占位符
    private func expand(_ template: String) -> String {
        var result = template
        // {{clipboard}} → 当前剪贴板内容
        if result.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }
        // {{date}} → 当前日期
        if result.contains("{{date}}") {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            result = result.replacingOccurrences(of: "{{date}}", with: f.string(from: Date()))
        }
        // {{time}} → 当前时间
        if result.contains("{{time}}") {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            result = result.replacingOccurrences(of: "{{time}}", with: f.string(from: Date()))
        }
        return result
    }

    /// Levenshtein 编辑距离
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count

        if aLen == 0 { return bLen }
        if bLen == 0 { return aLen }

        var d = [[Int]](repeating: [Int](repeating: 0, count: bLen + 1), count: aLen + 1)

        for i in 0...aLen { d[i][0] = i }
        for j in 0...bLen { d[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            }
        }
        return d[aLen][bLen]
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else { return }
        snippets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
