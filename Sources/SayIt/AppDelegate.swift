import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController?
    var overlayWindowController: OverlayWindowController?
    var audioRecorder: AudioRecorder?
    var settingsWindowController: SettingsWindowController?
    private var hotkeyManager: HotkeyManager?
    private var streamingTimer: Timer?
    private var deepgramStreamer: DeepgramStreamer?
    private var pendingRawText: String?
    private var isOfflineMode = false

    private var sttEngineType: String {
        UserDefaults.standard.string(forKey: "sttEngine") ?? "local"
    }

    private var isDeepgramEngine: Bool {
        let key = UserDefaults.standard.string(forKey: "deepgramApiKey") ?? ""
        return sttEngineType == "deepgram" && !key.isEmpty
    }

    private var isOpenAIWhisperEngine: Bool {
        let key = UserDefaults.standard.string(forKey: "openaiWhisperApiKey") ?? ""
        return sttEngineType == "openai_whisper" && !key.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMenu()

        audioRecorder = AudioRecorder()
        overlayWindowController = OverlayWindowController()
        statusBarController = StatusBarController(delegate: self)

        // 音量数据 → 声纹动画
        audioRecorder?.onAudioLevel = { [weak self] level in
            self?.overlayWindowController?.viewModel.updateAudioLevel(level)
        }

        setupHotkey()
        requestMicrophonePermission()
        requestAccessibilityPermission()
        prepareSTTEngine()
        NetworkMonitor.shared.start()
    }

    /// 为 accessory app 注册 Edit 菜单，使文本框支持 ⌘C/⌘V/⌘X/⌘A
    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Undo",       action: Selector(("undo:")),             keyEquivalent: "z")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - STT Engine

    private func prepareSTTEngine() {
        // 始终预加载 Whisper（作为 fallback）
        WhisperTranscriber.shared.prepare { ok in
            if !ok {
                dbg("[Whisper] 模型未找到，请将 ggml-base.bin 添加到 App Bundle")
            } else {
                dbg("[Whisper] 模型加载成功")
            }
        }
        // Deepgram 无需预加载，只要 Key 存在即可
    }

    // MARK: - Microphone Permission

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    DispatchQueue.main.async { self.showMicrophoneAlert() }
                }
            }
        default:
            DispatchQueue.main.async { self.showMicrophoneAlert() }
        }
    }

    private func showMicrophoneAlert() {
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "请前往 系统设置 > 隐私与安全性 > 麦克风，授权 SayIt 使用麦克风。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        dbg("[App] 辅助功能权限: \(trusted ? "已授权" : "未授权，已弹出系统提示")")
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let manager = HotkeyManager()
        manager.onRecordingStart = { [weak self] in self?.handleRecordingStart() }
        manager.onRecordingStop = { [weak self] in self?.handleRecordingStop() }
        manager.onRecordingCancel = { [weak self] in self?.handleRecordingCancel() }
        hotkeyManager = manager
    }

    // MARK: - Recording

    func handleRecordingStart() {
        dbg("[App] handleRecordingStart 被调用")
        SoundManager.shared.playStart()
        statusBarController?.setRecordingState(true)

        overlayWindowController?.viewModel.onCancel = { [weak self] in
            self?.handleRecordingCancel()
        }
        overlayWindowController?.viewModel.onConfirm = { [weak self] in
            self?.handleRecordingStop()
        }

        overlayWindowController?.viewModel.partialText = ""
        overlayWindowController?.viewModel.showPartialText = !isOpenAIWhisperEngine

        // 检测麦克风设备切换
        let currentDevice = AudioRecorder.currentInputDeviceName()
        let lastDevice = UserDefaults.standard.string(forKey: "lastUsedMicDevice")
        if let currentDevice = currentDevice {
            if let lastDevice = lastDevice, currentDevice != lastDevice {
                overlayWindowController?.viewModel.micNotificationText = currentDevice
            }
            UserDefaults.standard.set(currentDevice, forKey: "lastUsedMicDevice")
        }

        overlayWindowController?.show()

        // 云端 STT 引擎：检测网络
        let needsNetworkForSTT = isDeepgramEngine || isOpenAIWhisperEngine
        isOfflineMode = false
        if needsNetworkForSTT && !NetworkMonitor.shared.isConnected {
            isOfflineMode = true
            dbg("[App] 无网络连接，使用离线语音识别")
            overlayWindowController?.showNetworkWarning("当前无网络")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.overlayWindowController?.showNetworkWarning("使用离线语音模型识别")
            }
        }

        if needsNetworkForSTT && !isOfflineMode {
            if isDeepgramEngine {
                // 云端 Deepgram：WebSocket 流式
                dbg("[App] 使用 Deepgram 云端流式 STT")
                let streamer = DeepgramStreamer()
                self.deepgramStreamer = streamer

                audioRecorder?.onAudioBuffer = { [weak streamer] buffer in
                    streamer?.sendAudioChunk(buffer)
                }

                audioRecorder?.startRecording()

                let sampleRate = Int(audioRecorder?.currentSampleRate ?? 48000)
                streamer.start(sampleRate: sampleRate) { [weak self] partialText in
                    OperationQueue.main.addOperation {
                        self?.overlayWindowController?.viewModel.partialText = partialText
                    }
                }
            } else if isOpenAIWhisperEngine {
                // OpenAI Whisper 云端：只录音，不做本地流式预览
                dbg("[App] 使用 OpenAI Whisper 云端 STT")
                audioRecorder?.onAudioBuffer = nil
                audioRecorder?.startRecording()
            }
        } else {
            // 本地 Whisper：录音 + 本地流式预览
            dbg("[App] 使用本地 Whisper STT")
            overlayWindowController?.viewModel.showPartialText = true
            audioRecorder?.onAudioBuffer = nil
            audioRecorder?.startRecording()
            startStreamingTranscription()
        }
    }

    func handleRecordingCancel() {
        dbg("[App] handleRecordingCancel 被调用")
        SoundManager.shared.playCancel()
        hotkeyManager?.resetRecordingState()
        hotkeyManager?.cleanupEsc()
        hotkeyManager?.onThinkingCancel = nil
        stopAllStreaming()
        statusBarController?.setRecordingState(false)

        if overlayWindowController?.viewModel.isThinking == true {
            // LLM 优化中取消：跳过优化，直接输出原文
            TextOptimizer.shared.cancel()
            let rawText = pendingRawText
            pendingRawText = nil
            overlayWindowController?.hide()
            if let rawText = rawText, !rawText.isEmpty {
                typeText(rawText)
            }
        } else {
            audioRecorder?.stopRecording { _ in }
            overlayWindowController?.hide()
        }
    }

    private func fallbackToLocalWhisper() {
        dbg("[App] 降级到本地 Whisper")
        stopAllStreaming()
        overlayWindowController?.viewModel.showPartialText = true
        audioRecorder?.onAudioBuffer = nil
        audioRecorder?.startRecording()
        startStreamingTranscription()
    }

    private func stopAllStreaming() {
        stopStreamingTranscription()
        deepgramStreamer?.stop { _ in }
        deepgramStreamer = nil
    }

    func handleRecordingStop() {
        // 静音检测：录音超过 3 秒且一直静音则视为未说话，直接退出
        let vm = overlayWindowController?.viewModel
        let elapsed = CFAbsoluteTimeGetCurrent() - (vm?.recordingStartTime ?? 0)
        if elapsed >= 3.0 && (vm?.peakLevel ?? 1) < 0.15 {
            dbg("[App] 录音 \(String(format: "%.1f", elapsed))s 无语音输入，直接退出")
            handleRecordingCancel()
            return
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        dbg("[Perf] ===== 开始处理 =====")
        hotkeyManager?.finishRecording()
        hotkeyManager?.onThinkingCancel = { [weak self] in
            self?.handleRecordingCancel()
        }
        statusBarController?.setRecordingState(false)
        overlayWindowController?.viewModel.isThinking = true
        overlayWindowController?.viewModel.showPartialText = false
        overlayWindowController?.viewModel.partialText = ""

        // 捕获当前前台应用的上下文（录音停止后可能切换应用）
        let appContext = ContextProvider.shared.detect()

        if isDeepgramEngine, let streamer = deepgramStreamer {
            // ── Deepgram 云端路径：直接从 WebSocket 拿最终文本 ──
            dbg("[Perf] STT 引擎: Deepgram(云端)，等待最终结果...")
            stopStreamingTranscription()
            audioRecorder?.stopRecording { _ in }

            streamer.stop { [weak self] text in
                let tSTTEnd = CFAbsoluteTimeGetCurrent()
                dbg("[Perf] Deepgram 最终结果耗时: \(String(format: "%.0f", (tSTTEnd - t0) * 1000))ms, 结果长度: \(text?.count ?? 0)")
                self?.deepgramStreamer = nil

                guard let self = self, let rawText = text, !rawText.isEmpty else {
                    dbg("[App] Deepgram 转写为空")
                    OperationQueue.main.addOperation {
                        self?.overlayWindowController?.viewModel.isThinking = false
                        self?.overlayWindowController?.hide()
                    }
                    return
                }

                self.processTranscriptionResult(rawText: rawText, t0: t0, appContext: appContext)
            }
        } else if isOpenAIWhisperEngine {
            // ── OpenAI Whisper 云端路径：录音结束后上传完整音频 ──
            stopStreamingTranscription()
            let snapshot = audioRecorder?.currentPCMSnapshot()

            audioRecorder?.stopRecording { [weak self] url in
                guard let self = self else { return }
                if let url = url { try? FileManager.default.removeItem(at: url) }

                guard let snapshot = snapshot else {
                    dbg("[App] 录音数据为空")
                    OperationQueue.main.addOperation {
                        self.overlayWindowController?.viewModel.isThinking = false
                        self.overlayWindowController?.hide()
                    }
                    return
                }

                dbg("[Perf] PCM 数据大小: \(snapshot.data.count / 1024)KB")
                let tSTTStart = CFAbsoluteTimeGetCurrent()
                dbg("[Perf] STT 引擎: OpenAI Whisper(云端)，最终转写...")

                OpenAIWhisperTranscriber.shared.transcribeBuffer(pcmData: snapshot.data, format: snapshot.format) { [weak self] text in
                    let tSTTEnd = CFAbsoluteTimeGetCurrent()
                    dbg("[Perf] OpenAI Whisper 转写耗时: \(String(format: "%.0f", (tSTTEnd - tSTTStart) * 1000))ms, 结果长度: \(text?.count ?? 0)")

                    guard let self = self, let rawText = text, !rawText.isEmpty else {
                        dbg("[App] OpenAI Whisper 转写为空")
                        OperationQueue.main.addOperation {
                            self?.overlayWindowController?.viewModel.isThinking = false
                            self?.overlayWindowController?.hide()
                        }
                        return
                    }

                    self.processTranscriptionResult(rawText: rawText, t0: t0, appContext: appContext)
                }
            }
        } else {
            // ── Whisper 本地路径：用 PCM 快照做最终转写 ──
            stopStreamingTranscription()
            let snapshot = audioRecorder?.currentPCMSnapshot()

            audioRecorder?.stopRecording { [weak self] url in
                guard let self = self else { return }
                if let url = url { try? FileManager.default.removeItem(at: url) }

                let t1 = CFAbsoluteTimeGetCurrent()
                dbg("[Perf] stopRecording 耗时: \(String(format: "%.0f", (t1 - t0) * 1000))ms")

                guard let snapshot = snapshot else {
                    dbg("[App] 录音数据为空")
                    OperationQueue.main.addOperation {
                        self.overlayWindowController?.viewModel.isThinking = false
                        self.overlayWindowController?.hide()
                    }
                    return
                }

                dbg("[Perf] PCM 数据大小: \(snapshot.data.count / 1024)KB")

                let tSTTStart = CFAbsoluteTimeGetCurrent()
                dbg("[Perf] STT 引擎: Whisper(本地)，最终转写...")

                WhisperTranscriber.shared.transcribeBuffer(pcmData: snapshot.data, format: snapshot.format, language: SpeechLanguage.current.whisperCode) { [weak self] text in
                    let tSTTEnd = CFAbsoluteTimeGetCurrent()
                    dbg("[Perf] STT 转写耗时: \(String(format: "%.0f", (tSTTEnd - tSTTStart) * 1000))ms, 结果长度: \(text?.count ?? 0)")

                    guard let self = self, let rawText = text, !rawText.isEmpty else {
                        dbg("[App] Whisper 转写为空")
                        OperationQueue.main.addOperation {
                            self?.overlayWindowController?.viewModel.isThinking = false
                            self?.overlayWindowController?.hide()
                        }
                        return
                    }

                    self.processTranscriptionResult(rawText: rawText, t0: t0, appContext: appContext)
                }
            }
        }
    }

    /// 转写结果后续处理：语音命令 → 语片段 → LLM 优化 → 复制到剪贴板 → 保存历史
    private func processTranscriptionResult(rawText: String, t0: CFAbsoluteTime, appContext: AppContext? = nil) {
        // 1. 语音命令处理
        let commandProcessed = VoiceCommandProcessor.shared.process(rawText)
        // 2. 语片段匹配
        let snippetProcessed = SnippetManager.shared.process(commandProcessed)

        pendingRawText = snippetProcessed
        let optimizer = TextOptimizer.shared

        if isOfflineMode {
            // 离线模式：跳过 LLM 优化，直接输出原文
            dbg("[Perf] 离线模式，跳过 LLM 优化")
            dbg("[Perf] 总耗时: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            dbg("[Perf] ===== 处理完成 =====")
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.hotkeyManager?.cleanupEsc()
                self.hotkeyManager?.onThinkingCancel = nil
                self.overlayWindowController?.viewModel.isThinking = false
                self.overlayWindowController?.hide()
                self.typeText(snippetProcessed)
                HistoryManager.shared.addRecord(rawText: rawText, optimizedText: snippetProcessed, sttEngine: self.sttEngineType)
            }
        } else if optimizer.needsKeyConfiguration {
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.hotkeyManager?.cleanupEsc()
                self.hotkeyManager?.onThinkingCancel = nil
                self.overlayWindowController?.viewModel.isThinking = false
                self.overlayWindowController?.hide()
                self.showMissingApiKeyAlert(provider: optimizer.selectedProvider)
                self.typeText(snippetProcessed)
                HistoryManager.shared.addRecord(rawText: rawText, optimizedText: snippetProcessed, sttEngine: self.sttEngineType)
            }
        } else if optimizer.isAvailable {
            // isThinking 已在 handleRecordingStop 中设为 true
            let tLLMStart = CFAbsoluteTimeGetCurrent()
            dbg("[Perf] LLM 优化引擎: \(optimizer.selectedProvider.displayName)，开始优化...")
            optimizer.optimize(rawText: snippetProcessed, context: appContext) { [weak self] result in
                let tLLMEnd = CFAbsoluteTimeGetCurrent()
                dbg("[Perf] LLM 优化耗时: \(String(format: "%.0f", (tLLMEnd - tLLMStart) * 1000))ms")
                dbg("[Perf] 总耗时: \(String(format: "%.0f", (tLLMEnd - t0) * 1000))ms")
                dbg("[Perf] ===== 处理完成 =====")
                OperationQueue.main.addOperation {
                    guard let self = self else { return }
                    self.hotkeyManager?.cleanupEsc()
                    self.hotkeyManager?.onThinkingCancel = nil
                    self.overlayWindowController?.hide()
                    switch result {
                    case .success(let optimized):
                        self.typeText(optimized)
                        HistoryManager.shared.addRecord(rawText: rawText, optimizedText: optimized, sttEngine: self.sttEngineType)
                    case .failure(let error):
                        if case .networkError = error {
                            dbg("[App] LLM 优化网络错误: \(error)")
                        }
                        self.typeText(snippetProcessed)
                        HistoryManager.shared.addRecord(rawText: rawText, optimizedText: snippetProcessed, sttEngine: self.sttEngineType)
                    }
                }
            }
        } else {
            dbg("[Perf] 无 LLM 优化，总耗时: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            dbg("[Perf] ===== 处理完成 =====")
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.hotkeyManager?.cleanupEsc()
                self.hotkeyManager?.onThinkingCancel = nil
                self.overlayWindowController?.viewModel.isThinking = false
                self.overlayWindowController?.hide()
                self.typeText(snippetProcessed)
                HistoryManager.shared.addRecord(rawText: rawText, optimizedText: snippetProcessed, sttEngine: self.sttEngineType)
            }
        }
    }

    // MARK: - Streaming Transcription

    private func startStreamingTranscription() {
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.performStreamingTranscription()
        }
    }

    private func stopStreamingTranscription() {
        streamingTimer?.invalidate()
        streamingTimer = nil
    }

    private func performStreamingTranscription() {
        guard let snapshot = audioRecorder?.currentPCMSnapshot() else { return }
        // 使用本地 Whisper 做流式预览（Deepgram 的 transcribeBuffer 会返回 nil）
        WhisperTranscriber.shared.transcribeBuffer(pcmData: snapshot.data, format: snapshot.format, language: SpeechLanguage.current.whisperCode) { [weak self] text in
            OperationQueue.main.addOperation {
                guard let self = self else { return }
                if let text = text, !text.isEmpty {
                    self.overlayWindowController?.viewModel.partialText = text
                }
            }
        }
    }

    // MARK: - Text Input

    private func typeText(_ text: String) {
        dbg("[App] typeText 被调用，文本长度: \(text.count)，内容: \(text)")
        SoundManager.shared.playStop()

        // 将转写结果放入剪贴板，用户可随时 ⌘V 粘贴
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        dbg("[App] 剪贴板已设置，验证长度: \(pasteboard.string(forType: .string)?.count ?? 0)")

        // 尝试自动粘贴（需要辅助功能权限）
        let trusted = AXIsProcessTrusted()
        if trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.simulatePaste()
            }
        } else {
            dbg("[App] 辅助功能未授权，跳过自动粘贴，文本已在剪贴板")
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9  // 'v'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            dbg("[App] CGEvent 创建失败")
            return
        }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        dbg("[App] ⌘V 已发送")
    }

    // MARK: - Settings

    private func showMissingApiKeyAlert(provider: LLMProvider) {
        let alert = NSAlert()
        alert.messageText = "需要配置 \(provider.displayName) API Key"
        alert.informativeText = "你已选择使用 \(provider.displayName) 进行转写优化，请先在设置中填入有效的 API Key。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
