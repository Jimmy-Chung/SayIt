import Foundation

struct UserRule: Codable, Identifiable {
    let id: UUID
    let rule: String
    let example: String
    let createdAt: Date

    init(id: UUID = UUID(), rule: String, example: String, createdAt: Date = Date()) {
        self.id = id
        self.rule = rule
        self.example = example
        self.createdAt = createdAt
    }
}

final class UserRulesManager {

    static let shared = UserRulesManager()
    private init() {}

    private var rules: [UserRule] = []
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayIt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_rules.json")
    }()

    private var loaded = false

    var allRules: [UserRule] {
        loadIfNeeded()
        return rules
    }

    /// 返回可注入 LLM prompt 的规则文本（最高优先级，放在 prompt 末尾）
    var rulesPrompt: String {
        loadIfNeeded()
        guard !rules.isEmpty else { return "" }
        let lines = rules.map { "- \($0.rule)" }.joined(separator: "\n")
        return "\n\n## 用户个性化偏好（最高优先级，覆盖以上所有规则）\n\(lines)"
    }

    func addRule(rule: String, example: String) {
        loadIfNeeded()
        rules.append(UserRule(rule: rule, example: example))
        save()
    }

    func addRules(_ newRules: [(rule: String, example: String)]) {
        loadIfNeeded()
        for r in newRules {
            rules.append(UserRule(rule: r.rule, example: r.example))
        }
        save()
    }

    func removeRule(id: UUID) {
        loadIfNeeded()
        rules.removeAll { $0.id == id }
        save()
    }

    func removeAllRules() {
        rules.removeAll()
        save()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UserRule].self, from: data) else { return }
        rules = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
