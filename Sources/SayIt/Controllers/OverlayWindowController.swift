import AppKit
import SwiftUI

class OverlayWindowController {
    private var panel: NSPanel?
    let viewModel = OverlayViewModel()
    private var micNotificationTimer: Timer?
    private var networkWarningTimer: Timer?
    private var lastSavedOrigin: CGPoint?

    // 词典通知面板
    private var dictPanel: NSPanel?
    private var dictTimer: Timer?

    // MARK: - Public API

    private var currentPanelSize: CGSize {
        let base: CGFloat = viewModel.showPartialText ? 124 : 38
        let micExtra: CGFloat = viewModel.micNotificationText != nil ? 30 : 0
        let networkExtra: CGFloat = viewModel.networkWarningText != nil ? 30 : 0
        return CGSize(width: 420, height: base + micExtra + networkExtra)
    }

    private func resolveOrigin(for size: CGSize) -> CGPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let mode = OverlayPosition.current

        switch mode {
        case .bottomCenter:
            return CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + screenFrame.height * 0.12)
        case .nearCursor:
            let mouse = NSEvent.mouseLocation
            var x = mouse.x - size.width / 2
            var y = mouse.y + 20
            // 限制在屏幕内
            x = max(screenFrame.minX, min(x, screenFrame.maxX - size.width))
            y = max(screenFrame.minY, min(y, screenFrame.maxY - size.height))
            return CGPoint(x: x, y: y)
        case .lastPosition:
            if let saved = lastSavedOrigin {
                return saved
            }
            // 从 UserDefaults 恢复
            let keyX = "overlayPositionX"
            let keyY = "overlayPositionY"
            if UD.object(forKey: keyX) != nil, UD.object(forKey: keyY) != nil {
                let x = UD.double(forKey: keyX)
                let y = UD.double(forKey: keyY)
                return CGPoint(x: x, y: y)
            }
            // 首次使用，回退到底部居中
            return CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + screenFrame.height * 0.12)
        }
    }

    private var UD: UserDefaults { UserDefaults.standard }

    func show() {
        viewModel.resetAudio()

        let size = currentPanelSize
        let origin = resolveOrigin(for: size)

        if panel == nil {
            createPanel(size: size, origin: origin)
        } else {
            panel?.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel?.orderFront(nil)

        scheduleMicNotificationDismiss()
    }

    func hide() {
        // 保存当前位置（用于 lastPosition 模式）
        if let frame = panel?.frame {
            lastSavedOrigin = frame.origin
            UD.set(frame.origin.x, forKey: "overlayPositionX")
            UD.set(frame.origin.y, forKey: "overlayPositionY")
        }
        micNotificationTimer?.invalidate()
        micNotificationTimer = nil
        networkWarningTimer?.invalidate()
        networkWarningTimer = nil
        panel?.orderOut(nil)
        viewModel.resetAudio()
        viewModel.partialText = ""
        viewModel.isThinking = false
        viewModel.micNotificationText = nil
        viewModel.networkWarningText = nil
    }

    func dismissMicNotification() {
        viewModel.micNotificationText = nil
        micNotificationTimer?.invalidate()
        micNotificationTimer = nil
        updatePanelFrame()
    }

    private func scheduleMicNotificationDismiss() {
        micNotificationTimer?.invalidate()
        guard viewModel.micNotificationText != nil else { return }
        micNotificationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismissMicNotification()
        }
    }

    private func updatePanelFrame() {
        guard let panel = panel else { return }
        let newSize = currentPanelSize
        var frame = panel.frame
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        panel.setFrame(frame, display: true)
    }

    func showNetworkWarning(_ text: String = "网络异常，请稍后重试") {
        viewModel.networkWarningText = text
        updatePanelFrame()
        scheduleNetworkWarningDismiss()
    }

    private func dismissNetworkWarning() {
        viewModel.networkWarningText = nil
        networkWarningTimer?.invalidate()
        networkWarningTimer = nil
        updatePanelFrame()
    }

    private func scheduleNetworkWarningDismiss() {
        networkWarningTimer?.invalidate()
        guard viewModel.networkWarningText != nil else { return }
        networkWarningTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismissNetworkWarning()
        }
    }

    // MARK: - Dictionary Notification

    func showDictionaryNotification(wrong: String, correct: String) {
        dictTimer?.invalidate()
        dictTimer = nil

        let text = "\(wrong) → \(correct)  已添加到词典"
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.9)
        label.sizeToFit()

        let padding: CGFloat = 20
        let size = CGSize(width: label.frame.width + padding * 2, height: 28)

        // 位置：overlay 最后位置附近，或屏幕底部居中
        let origin: CGPoint
        if let saved = lastSavedOrigin {
            origin = CGPoint(x: saved.x + (420 - size.width) / 2, y: saved.y)
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            origin = CGPoint(x: screenFrame.midX - size.width / 2,
                             y: screenFrame.minY + screenFrame.height * 0.12)
        }

        if dictPanel == nil {
            let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.cornerRadius = 14
            container.layer?.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 30/255, alpha: 0.75).cgColor

            let capsule = NSView(frame: container.bounds.insetBy(dx: 1, dy: 1))
            capsule.wantsLayer = true
            capsule.layer?.cornerRadius = 13
            capsule.layer?.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 30/255, alpha: 0.7).cgColor
            container.addSubview(capsule)

            label.frame = NSRect(x: padding, y: (size.height - label.frame.height) / 2,
                                 width: label.frame.width, height: label.frame.height)
            container.addSubview(label)

            p.contentView = container
            dictPanel = p
        } else {
            dictPanel?.setFrame(NSRect(origin: origin, size: size), display: true)
            // 更新文字
            if let container = dictPanel?.contentView,
               let oldLabel = container.subviews.compactMap({ $0 as? NSTextField }).first {
                oldLabel.stringValue = text
                oldLabel.sizeToFit()
                oldLabel.frame = NSRect(x: padding, y: (size.height - oldLabel.frame.height) / 2,
                                         width: oldLabel.frame.width, height: oldLabel.frame.height)
            }
        }

        dictPanel?.orderFront(nil)
        dbg("[Overlay] 显示词典通知: \(text)")

        dictTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.dictPanel?.orderOut(nil)
        }
    }

    // MARK: - Panel Setup

    private func createPanel(size: CGSize, origin: CGPoint) {
        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true

        let hv = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        hv.wantsLayer = true
        hv.layer?.backgroundColor = .clear
        p.contentView = hv

        panel = p
    }
}
