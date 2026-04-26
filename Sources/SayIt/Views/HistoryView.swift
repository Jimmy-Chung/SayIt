import SwiftUI

struct HistoryView: View {
    @State private var records: [TranscriptionRecord] = HistoryManager.shared.allRecords
    @State private var searchText = ""

    private var filteredRecords: [TranscriptionRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.displayText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索转写记录", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "暂无转写记录" : "未找到匹配记录")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRecords) { record in
                    HistoryRow(record: record) {
                        copyAndPaste(record.displayText)
                    } onCopy: {
                        copyToClipboard(record.displayText)
                    } onDelete: {
                        HistoryManager.shared.deleteRecord(id: record.id)
                        records = HistoryManager.shared.allRecords
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func copyAndPaste(_ text: String) {
        copyToClipboard(text)
        // 模拟 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKeyCode: CGKeyCode = 9
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

struct HistoryRow: View {
    let record: TranscriptionRecord
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: record.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayText)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(record.sttEngine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 4) {
                Button(action: onPaste) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("复制并粘贴")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("复制到剪贴板")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.vertical, 4)
    }
}
