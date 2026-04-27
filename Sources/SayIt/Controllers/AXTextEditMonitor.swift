import Cocoa
import ApplicationServices

private func axEditObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ userData: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        AXTextEditMonitor.shared.handleValueChanged()
    }
}

/// 监听粘贴后目标文本框的编辑，自动学习用户的修正词对到词典
final class AXTextEditMonitor {

    static let shared = AXTextEditMonitor()

    private var originalText: String?
    private var monitoredElement: AXUIElement?
    private var observer: AXObserver?
    private var debounceTimer: Timer?
    private var monitoringTimeout: Timer?

    private let monitorTimeout: TimeInterval = 30.0
    private let debounceDelay: TimeInterval = 3.0
    private let maxCorrectionLength = 20

    private init() {}

    // MARK: - Public

    func startMonitoring(originalText: String) {
        stopMonitoring()

        guard AXIsProcessTrusted() else {
            dbg("[AXEditMonitor] 无辅助功能权限，跳过监听")
            return
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier

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

        var observer: AXObserver?
        let observerErr = AXObserverCreate(pid, axEditObserverCallback, &observer)
        guard observerErr == .success, let observer = observer else {
            dbg("[AXEditMonitor] 创建 AXObserver 失败: \(observerErr.rawValue)")
            self.monitoredElement = nil
            self.originalText = nil
            return
        }

        self.observer = observer
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        monitoringTimeout = Timer.scheduledTimer(withTimeInterval: monitorTimeout, repeats: false) { [weak self] _ in
            dbg("[AXEditMonitor] 监听超时，结束监听")
            self?.finalizeMonitoring(currentText: nil)
        }

        dbg("[AXEditMonitor] 开始监听，原始文本: \(originalText.prefix(50))")
    }

    func stopMonitoring() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        monitoringTimeout?.invalidate()
        monitoringTimeout = nil

        if let observer = observer, let element = monitoredElement {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        observer = nil
        monitoredElement = nil
        originalText = nil
    }

    // MARK: - Internal (called from AX callback on main thread)

    func handleValueChanged() {
        guard let element = monitoredElement else { return }

        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard err == .success, let newValue = value as? String else { return }

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            self?.finalizeMonitoring(currentText: newValue)
        }
    }

    // MARK: - Private

    private func finalizeMonitoring(currentText: String?) {
        let original = originalText
        stopMonitoring()

        guard let original = original, let current = currentText else { return }
        guard !current.isEmpty, current != original else { return }

        let similarity = textSimilarity(original, current)
        guard similarity > 0.5 else {
            dbg("[AXEditMonitor] 文本变化过大（相似度: \(String(format: "%.0f%%", similarity * 100))），跳过")
            return
        }

        let corrections = extractCorrections(original: original, modified: current)
        for (wrong, correct) in corrections {
            dbg("[AXEditMonitor] 检测到修正: '\(wrong)' → '\(correct)'")
            UserDictionary.shared.addCorrection(wrong: wrong, correct: correct)
        }
    }

    private func textSimilarity(_ a: String, _ b: String) -> Double {
        let aSet = Set(a)
        let bSet = Set(b)
        let common = aSet.intersection(bSet).count
        let total = max(aSet.count, bSet.count)
        return total > 0 ? Double(common) / Double(total) : 1.0
    }

    /// 通过前后缀对齐提取字符级修正片段
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
              wrongSegment != correctSegment,
              wrongSegment.count <= maxCorrectionLength, correctSegment.count <= maxCorrectionLength else {
            return []
        }

        return [(wrong: wrongSegment, correct: correctSegment)]
    }
}
