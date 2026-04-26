import Foundation

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let rawText: String
    let optimizedText: String?
    let timestamp: Date
    let sttEngine: String
    let duration: TimeInterval

    var displayText: String {
        optimizedText ?? rawText
    }
}

final class HistoryManager {

    static let shared = HistoryManager()
    private init() {}

    private let maxRecords = 500
    private var records: [TranscriptionRecord] = []
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayIt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    var allRecords: [TranscriptionRecord] {
        loadIfNeeded()
        return records
    }

    func addRecord(rawText: String, optimizedText: String?, sttEngine: String) {
        loadIfNeeded()
        let record = TranscriptionRecord(
            id: UUID(),
            rawText: rawText,
            optimizedText: optimizedText,
            timestamp: Date(),
            sttEngine: sttEngine,
            duration: 0
        )
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        save()
    }

    func deleteRecord(id: UUID) {
        loadIfNeeded()
        records.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        records = []
        save()
    }

    private var loaded = false

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
