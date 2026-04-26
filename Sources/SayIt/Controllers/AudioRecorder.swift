import AppKit
import AVFoundation
import MediaPlayer

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var currentURL: URL?
    private(set) var isRecording = false

    /// 实时音量回调 (0.0 ~ 1.0)
    var onAudioLevel: ((Float) -> Void)?
    /// 实时音频 buffer 回调（用于流式推送给云端 STT）
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// 当前录音采样率
    var currentSampleRate: Double {
        recordingFormat?.sampleRate ?? 48000
    }

    /// 录音中累积的 PCM float32 数据（原始采样率）
    private let bufferLock = NSLock()
    private var accumulatedPCM = Data()
    private var recordingFormat: AVAudioFormat?

    /// 录音开始前是否暂停了其他音频
    private var didPauseOtherAudio = false

    func startRecording() {
        guard !isRecording else { return }

        pauseOtherAudio()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        recordingFormat = format

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        currentURL = url

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            return
        }

        bufferLock.lock()
        accumulatedPCM = Data()
        bufferLock.unlock()

        installTap(on: inputNode, format: format)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            currentURL = nil
        }
    }

    private func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            try? self.outputFile?.write(from: buffer)
            self.onAudioBuffer?(buffer)
            if let channelData = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Float>.size)
                self.bufferLock.lock()
                self.accumulatedPCM.append(data)
                self.bufferLock.unlock()
            }
            let level = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.onAudioLevel?(level)
            }
        }
    }

    @objc private func handleAudioConfigurationChange(_ notification: Notification) {
        guard isRecording, let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)

        let newFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = newFormat

        if let url = currentURL {
            outputFile = try? AVAudioFile(forWriting: url, settings: newFormat.settings)
        }

        installTap(on: inputNode, format: newFormat)

        do {
            try engine.start()
        } catch {
            dbg("[AudioRecorder] 音频设备切换后重启失败: \(error)")
        }
    }

    /// 获取当前已录制的 PCM 数据快照（线程安全）
    func currentPCMSnapshot() -> (data: Data, format: AVAudioFormat)? {
        bufferLock.lock()
        let snapshot = accumulatedPCM
        let fmt = recordingFormat
        bufferLock.unlock()
        guard !snapshot.isEmpty, let fmt = fmt else { return nil }
        return (snapshot, fmt)
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let engine = audioEngine else {
            completion(nil)
            return
        }

        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        outputFile = nil
        isRecording = false
        audioEngine = nil

        bufferLock.lock()
        accumulatedPCM = Data()
        bufferLock.unlock()

        resumeOtherAudio()

        let url = currentURL
        currentURL = nil
        completion(url)
    }

    // MARK: - 背景音频控制

    private func pauseOtherAudio() {
        if isAudioPlaying() {
            didPauseOtherAudio = true
            sendMediaPlayPauseKey()
            dbg("[AudioRecorder] 已暂停背景音频")
        } else {
            didPauseOtherAudio = false
        }
    }

    private func resumeOtherAudio() {
        if didPauseOtherAudio {
            didPauseOtherAudio = false
            sendMediaPlayPauseKey()
            dbg("[AudioRecorder] 已恢复背景音频")
        }
    }

    private func isAudioPlaying() -> Bool {
        MPNowPlayingInfoCenter.default().playbackState == .playing
    }

    private func sendMediaPlayPauseKey() {
        let keyCode: UInt16 = 16  // NX_KEYTYPE_PLAY = 16
        func postMediaKey(keyDown: Bool) {
            let flags: Int32 = keyDown ? 0xa00 : 0xb00  // NX_KEYDOWN : NX_KEYUP
            let data1 = Int(keyCode) << 16 | Int(flags)
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        postMediaKey(keyDown: true)
        postMediaKey(keyDown: false)
    }

    // MARK: - Device Info

    static func currentInputDeviceName() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceNameCFString
        var name: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }

        return name as String
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            sum += data[i] * data[i]
        }
        let rms = sqrtf(sum / Float(max(frames, 1)))
        let normalized = min(max(rms * 5.0, 0), 1.0)
        return normalized
    }
}
