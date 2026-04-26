import AppKit
import Carbon

/// 全局快捷键管理器
/// - 监听单个修饰键轻按（按下后快速松开，中间没有按其他键）来切换录音
/// - 录音中按 Esc 取消（通过 Carbon RegisterEventHotKey 拦截）
///
/// 使用 CGEventTap + NSEvent monitors 双重监听，共享同一个状态机。
/// 先收到事件的机制触发 toggle，后到的因 previousModifiers 已更新而自动忽略。
/// 附带 watchdog 定时器，定期检查并恢复可能被系统禁用的 CGEventTap。
class HotkeyManager {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    var onRecordingCancel: (() -> Void)?
    var onThinkingCancel: (() -> Void)?

    private(set) var isRecording = false

    // CGEventTap（底层，可能被系统超时禁用）
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // NSEvent monitors（AppKit 层，生命周期由系统托管）
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    // Watchdog：定期检查 CGEventTap 健康状态
    private var watchdogTimer: Timer?

    // Carbon（Esc 拦截）
    private var carbonHandler: EventHandlerRef?
    private var escHotkeyRef: EventHotKeyRef?
    private let escHotkeyID = EventHotKeyID(signature: OSType(0x5654_5950), id: 2)

    // 修饰键轻按检测状态（CGEventTap 与 NSEvent monitors 共用）
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var modifierDownTime: CFAbsoluteTime = 0
    private var otherKeyPressed = false
    private var modifierPending = false

    /// 轻按判定的最大时长（秒）
    private let tapThreshold: CFAbsoluteTime = 0.4

    init() {
        installCarbonHandler()
        setupEventTap()
        setupNSEventMonitors()
        startWatchdog()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: .hotkeyChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        tearDown()
    }

    @objc private func hotkeySettingsChanged() {
        modifierPending = false
        previousModifiers = []
        dbg("[HotkeyManager] 触发键已更新: \(TriggerKey.current.displayName)")
    }

    /// 外部取消/停止录音时调用，重置内部状态使快捷键不至于错位
    func resetRecordingState() {
        if isRecording {
            isRecording = false
            unregisterEscHotkey()
            dbg("[HotkeyManager] resetRecordingState: 已重置")
        }
    }

    /// 录音结束但进入 LLM 优化阶段，保持 ESC 可用
    func finishRecording() {
        if isRecording {
            isRecording = false
            dbg("[HotkeyManager] finishRecording: 录音结束，保持 ESC 热键供优化阶段取消")
        }
    }

    /// 清理 ESC 热键（优化完成后调用）
    func cleanupEsc() {
        unregisterEscHotkey()
    }

    // MARK: - CGEventTap

    private func setupEventTap() {
        tearDownEventTap()

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                mgr.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            dbg("[HotkeyManager] CGEventTap 创建失败，仅依赖 NSEvent monitors")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        dbg("[HotkeyManager] CGEventTap 已启动")
    }

    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                dbg("[HotkeyManager] CGEventTap 被系统禁用，已重新启用")
            }
            return
        }

        if type == .flagsChanged {
            // CGEventFlags 与 NSEvent.ModifierFlags 标准修饰键的 bit 位相同，可直接转换
            let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            handleFlagsChanged(modifiers: nsFlags)
        } else if type == .keyDown {
            otherKeyPressed = true
        }
    }

    // MARK: - NSEvent Monitors

    private func setupNSEventMonitors() {
        // 监听其他 app 的修饰键变化
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(modifiers: event.modifierFlags)
        }
        // 监听本 app 窗口内的修饰键变化
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(modifiers: event.modifierFlags)
            return event
        }
        // 检测按键（用于判断是否在修饰键按住期间按了其他键）
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.otherKeyPressed = true
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.otherKeyPressed = true
            return event
        }
        dbg("[HotkeyManager] NSEvent monitors 已启动, 触发键: \(TriggerKey.current.displayName)")
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkEventTapHealth()
        }
    }

    private var lastTapWasDisabled = false

    private func checkEventTapHealth() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !lastTapWasDisabled {
                    dbg("[HotkeyManager] Watchdog: CGEventTap 被禁用，已重新启用")
                }
                lastTapWasDisabled = true
            } else {
                lastTapWasDisabled = false
            }
        } else {
            dbg("[HotkeyManager] Watchdog: CGEventTap 不存在，重建中...")
            setupEventTap()
        }
    }

    // MARK: - 共享状态机

    private func handleFlagsChanged(modifiers: NSEvent.ModifierFlags) {
        let target = TriggerKey.current.flag
        let wasDown = previousModifiers.contains(target)
        let isDown = modifiers.contains(target)
        previousModifiers = modifiers

        if !wasDown && isDown {
            // 目标修饰键刚按下
            modifierPending = true
            modifierDownTime = CFAbsoluteTimeGetCurrent()
            otherKeyPressed = false
        } else if wasDown && !isDown && modifierPending {
            // 目标修饰键刚松开
            modifierPending = false
            let elapsed = CFAbsoluteTimeGetCurrent() - modifierDownTime
            if !otherKeyPressed && elapsed < tapThreshold {
                handleToggle()
            }
        }
    }

    // MARK: - Toggle

    private func handleToggle() {
        dbg("[HotkeyManager] handleToggle: isRecording=\(isRecording)")
        if isRecording {
            isRecording = false
            unregisterEscHotkey()
            onRecordingStop?()
        } else {
            isRecording = true
            registerEscHotkey()
            onRecordingStart?()
        }
    }

    // MARK: - Teardown

    private func tearDown() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil

        tearDownEventTap()

        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil

        unregisterEscHotkey()
    }

    // MARK: - Carbon Handler (Esc 拦截)

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData = userData, let event = event else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonEvent(event)
            },
            1,
            &eventType,
            selfPtr,
            &carbonHandler
        )
    }

    private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr else { return OSStatus(eventNotHandledErr) }

        if hotkeyID.signature == escHotkeyID.signature && hotkeyID.id == escHotkeyID.id {
            unregisterEscHotkey()
            if isRecording {
                dbg("[HotkeyManager] Esc 按下，取消录音")
                isRecording = false
                onRecordingCancel?()
            } else {
                dbg("[HotkeyManager] Esc 按下，取消优化")
                onThinkingCancel?()
            }
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

    // MARK: - Esc Register / Unregister

    private func registerEscHotkey() {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), 0, escHotkeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr { escHotkeyRef = ref }
    }

    private func unregisterEscHotkey() {
        if let ref = escHotkeyRef {
            UnregisterEventHotKey(ref)
            escHotkeyRef = nil
        }
    }
}
