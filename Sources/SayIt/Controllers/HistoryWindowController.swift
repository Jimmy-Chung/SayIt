import AppKit
import SwiftUI

class HistoryWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = HistoryView()
            let hosting = NSHostingView(rootView: view)
            hosting.wantsLayer = true

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "转写历史"
            w.contentView = hosting
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
