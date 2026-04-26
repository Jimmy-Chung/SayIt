import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SayIt 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        let toolbar = NSToolbar()
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 32/255, green: 32/255, blue: 40/255, alpha: 1.0)

        let hosting = NSHostingView(rootView: SettingsView())
        hosting.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 600))
        container.wantsLayer = true
        hosting.frame = container.bounds
        container.addSubview(hosting)

        window.contentView = container
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
