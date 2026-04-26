import AppKit

class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private weak var delegate: AppDelegate?
    private var historyWindowController: HistoryWindowController?

    init(delegate: AppDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        setupIcon()
        setupMenu()
        statusItem.menu = menu
    }

    private func setupIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "SayIt")
        button.image?.isTemplate = true
        button.toolTip = "SayIt"
    }

    private func setupMenu() {
        let header = NSMenuItem(title: "SayIt", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // 语言子菜单
        let langMenu = NSMenu(title: "语言")
        for lang in SpeechLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(switchLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            if lang == SpeechLanguage.current {
                item.state = .on
            }
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        let history = NSMenuItem(title: "转写历史...", action: #selector(openHistory), keyEquivalent: "h")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 SayIt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func openSettings() {
        delegate?.openSettings()
    }

    @objc private func openHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.show()
    }

    @objc private func switchLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: "speechLanguage")
        // 更新菜单勾选状态
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.representedObject as? String) == raw ? .on : .off
            }
        }
    }

    func setRecordingState(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = recording ? "mic.circle.fill" : "mic.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SayIt")
        button.image?.isTemplate = true
    }
}
