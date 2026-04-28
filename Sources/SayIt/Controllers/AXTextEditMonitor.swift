import Cocoa
import ApplicationServices

/// 监听粘贴后目标文本框的编辑，自动学习用户的修正词对到词典
/// 使用轮询方式读取目标元素值，不依赖 AXObserver 通知（兼容性更好）
final class AXTextEditMonitor {

    static let shared = AXTextEditMonitor()

    var onCorrection: ((String, String) -> Void)?

    private var originalText: String?
    private var monitoredElement: AXUIElement?
    private var pollTimer: Timer?
    private var timeoutTimer: Timer?
    private var lastSeenText: String?
    private var stableCount: Int = 0

    // 原文在文档中的字符偏移量
    private var pasteOffset: Int?

    private let monitorTimeout: TimeInterval = 30.0
    private let pollInterval: TimeInterval = 1.0
    private let stableThreshold = 3  // 连续 3 次读取相同（3s）视为稳定
    private let maxCorrectionLength = 20

    private init() {}

    // MARK: - Public

    func startMonitoring(originalText: String, targetPID: pid_t? = nil) {
        dbg("[AXEditMonitor] startMonitoring 被调用")
        stopMonitoring()

        guard AXIsProcessTrusted() else {
            dbg("[AXEditMonitor] 无辅助功能权限，跳过监听")
            return
        }

        let pid: pid_t
        if let targetPID = targetPID {
            pid = targetPID
            let appName = NSRunningApplication(processIdentifier: targetPID)?.localizedName ?? "unknown"
            dbg("[AXEditMonitor] 使用录音时保存的 PID: \(targetPID) (\(appName))")
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
            pid = frontApp.processIdentifier
            dbg("[AXEditMonitor] 使用当前前台应用 PID: \(pid) (\(frontApp.localizedName ?? "unknown"))")
        }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard err == .success else {
            dbg("[AXEditMonitor] 无法获取焦点元素: \(err.rawValue)")
            return
        }

        let element = focusedElement as! AXUIElement

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
        guard let roleStr = role as? String, textRoles.contains(roleStr) else {
            dbg("[AXEditMonitor] 焦点元素不是文本框: \(role as? String ?? "unknown")")
            return
        }

        self.originalText = originalText
        self.monitoredElement = element
        self.lastSeenText = nil
        self.stableCount = 0

        // 读取初始值，记录原文在文档中的位置
        var initialValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &initialValue) == .success,
           let text = initialValue as? String {
            self.lastSeenText = text
            dbg("[AXEditMonitor] 初始值: \(text.prefix(80))")
            if let range = text.range(of: originalText) {
                pasteOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                dbg("[AXEditMonitor] 原文位置: offset=\(pasteOffset!)，文档长度: \(text.count)")
            } else {
                dbg("[AXEditMonitor] 未在文档中找到原文（可能粘贴未完成）")
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: monitorTimeout, repeats: false) { [weak self] _ in
            dbg("[AXEditMonitor] 监听超时，结束监听")
            self?.stopMonitoring()
        }

        dbg("[AXEditMonitor] 开始轮询监听，原始文本: \(originalText.prefix(50))")
    }

    // MARK: - Stop

    func stopMonitoring() {
        // 中断前保存尚未完成的编辑
        if let original = originalText, let lastText = lastSeenText {
            tryExtractCorrection(original: original, fullText: lastText)
        }

        pollTimer?.invalidate()
        pollTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        monitoredElement = nil
        originalText = nil
        lastSeenText = nil
        stableCount = 0
        pasteOffset = nil
    }

    // MARK: - Private

    /// 从文档全文中提取粘贴区域的当前文本
    private func extractCurrentRegion(from fullText: String) -> String? {
        guard let original = originalText else { return nil }

        // 先精确查找原文
        if let range = fullText.range(of: original) {
            return String(fullText[range])
        }

        // 原文已被修改，通过偏移量定位
        guard let offset = pasteOffset else { return nil }

        // 在偏移量附近提取一段文本（允许长度变化 ±20）
        let lenDiff = fullText.count - (lastSeenText?.count ?? fullText.count)
        let extractLen = original.count + max(abs(lenDiff), 20)
        let startIdx = fullText.index(fullText.startIndex, offsetBy: offset, limitedBy: fullText.endIndex) ?? fullText.startIndex
        let endOffset = min(offset + extractLen, fullText.count)
        let endIdx = fullText.index(fullText.startIndex, offsetBy: endOffset, limitedBy: fullText.endIndex) ?? fullText.endIndex
        return String(fullText[startIdx..<endIdx])
    }

    /// 尝试从全文中提取修正并保存
    private func tryExtractCorrection(original: String, fullText: String) {
        dbg("[AXEditMonitor] tryExtractCorrection: original='\(original.prefix(30))', fullText长度=\(fullText.count)")
        guard let currentRegion = extractCurrentRegion(from: fullText) else {
            dbg("[AXEditMonitor] extractCurrentRegion 返回 nil")
            return
        }
        dbg("[AXEditMonitor] currentRegion='\(currentRegion.prefix(50))', 与原文相同=\(currentRegion == original), 空=\(currentRegion.isEmpty)")
        guard currentRegion != original, !currentRegion.isEmpty else { return }

        let similarity = textSimilarity(original, currentRegion)
        dbg("[AXEditMonitor] 相似度: \(String(format: "%.0f%%", similarity * 100))")
        guard similarity >= 0.3 else {
            dbg("[AXEditMonitor] 文本变化过大，跳过")
            return
        }

        let corrections = extractCorrections(original: original, modified: currentRegion)
        dbg("[AXEditMonitor] 提取到 \(corrections.count) 个修正")
        for (wrong, correct) in corrections {
            dbg("[AXEditMonitor] 保存修正: '\(wrong)' → '\(correct)'")
            UserDictionary.shared.addCorrection(wrong: wrong, correct: correct)
            onCorrection?(wrong, correct)
        }
    }

    private func poll() {
        guard let element = monitoredElement else {
            stopMonitoring()
            return
        }

        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard err == .success, let currentText = value as? String else {
            return
        }

        // 文本与上次相同，累加稳定计数
        if currentText == lastSeenText {
            stableCount += 1
            if stableCount >= stableThreshold, let original = originalText {
                // 检查粘贴区域是否被修改
                if extractCurrentRegion(from: currentText) != original {
                    dbg("[AXEditMonitor] 文本稳定 \(stableCount)s，粘贴区域已变更")
                    stopMonitoring()
                }
            }
            return
        }

        // 文本变化，重置稳定计数
        dbg("[AXEditMonitor] 检测到文本变化: \(currentText.prefix(50))")
        lastSeenText = currentText
        stableCount = 1
    }

    private func textSimilarity(_ a: String, _ b: String) -> Double {
        let aSet = Set(a)
        let bSet = Set(b)
        let common = aSet.intersection(bSet).count
        let total = max(aSet.count, bSet.count)
        return total > 0 ? Double(common) / Double(total) : 1.0
    }

    /// 通过前后缀对齐提取修正片段，再用 CJK 字符作为分隔拆分为词级修正
    private func extractCorrections(original: String, modified: String) -> [(wrong: String, correct: String)] {
        let origChars = Array(original)
        let modChars = Array(modified)

        // Find common prefix
        var prefix = 0
        while prefix < origChars.count && prefix < modChars.count && origChars[prefix] == modChars[prefix] {
            prefix += 1
        }

        // Find common suffix (don't overlap with prefix)
        var suffix = 0
        while suffix < (origChars.count - prefix) && suffix < (modChars.count - prefix)
              && origChars[origChars.count - 1 - suffix] == modChars[modChars.count - 1 - suffix] {
            suffix += 1
        }

        let wrongEnd = origChars.count - suffix
        let correctEnd = modChars.count - suffix

        guard prefix < wrongEnd || prefix < correctEnd else { return [] }

        let wrongSegment = String(origChars[prefix..<wrongEnd])
        let correctSegment = String(modChars[prefix..<correctEnd])

        guard !wrongSegment.isEmpty, !correctSegment.isEmpty,
              wrongSegment != correctSegment else { return [] }

        // 尝试按 CJK/非CJK 分词，拆分为多个独立修正
        if let splitResults = splitByCJK(wrong: wrongSegment, correct: correctSegment) {
            return splitResults
        }

        // 回退：作为单个修正
        guard wrongSegment.count <= maxCorrectionLength, correctSegment.count <= maxCorrectionLength else {
            return []
        }
        return [(wrong: wrongSegment, correct: correctSegment)]
    }

    /// 按 CJK 字符边界分词，逐段对比提取词级修正
    private func splitByCJK(wrong: String, correct: String) -> [(wrong: String, correct: String)]? {
        let wrongTokens = tokenizeByCJK(wrong)
        let correctTokens = tokenizeByCJK(correct)
        guard wrongTokens.count == correctTokens.count, wrongTokens.count > 1 else { return nil }

        var results: [(wrong: String, correct: String)] = []
        for (wt, ct) in zip(wrongTokens, correctTokens) {
            if wt != ct {
                let trimmedW = wt.trimmingCharacters(in: .whitespaces)
                let trimmedC = ct.trimmingCharacters(in: .whitespaces)
                guard !trimmedW.isEmpty, !trimmedC.isEmpty,
                      trimmedW.count <= maxCorrectionLength, trimmedC.count <= maxCorrectionLength else { continue }
                results.append((wrong: trimmedW, correct: trimmedC))
            }
        }
        return results.isEmpty ? nil : results
    }

    /// 将字符串按 CJK/非CJK 交替分词
    private func tokenizeByCJK(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var wasCJK = false

        for char in s {
            let isCJK = char.unicodeScalars.contains { sc in
                let v = sc.value
                return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) ||
                       (0x3000...0x303F).contains(v) || (0x2E80...0x2EFF).contains(v) ||
                       (0xF900...0xFAFF).contains(v)
            }
            if isCJK != wasCJK && !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            wasCJK = isCJK
            current.append(char)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
