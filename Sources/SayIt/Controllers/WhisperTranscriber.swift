import Foundation
import AVFoundation

/// 封装 whisper.cpp，提供异步转写接口
final class WhisperTranscriber: TranscriptionService {

    // MARK: - Singleton

    static let shared = WhisperTranscriber()

    // MARK: - State

    private var context: OpaquePointer?   // WhisperContext *
    private let queue = DispatchQueue(label: "com.sayit.whisper", qos: .userInitiated)
    private(set) var isLoaded = false

    // MARK: - Init

    private init() {}

    // MARK: - Load Model

    /// 异步加载模型，完成后回调主线程
    func loadModel(at url: URL, completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let old = self.context {
                whisper_wrapper_free(old)
                self.context = nil
                self.isLoaded = false
            }
            let ctx = whisper_wrapper_init(url.path)
            let ok = ctx != nil
            self.context = ctx
            self.isLoaded = ok
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 从 App Bundle 加载默认模型（ggml-base.bin），未找到则回调 false
    func loadBundledModel(completion: @escaping (Bool) -> Void) {
        guard let url = Bundle.main.url(forResource: "ggml-base", withExtension: "bin") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        loadModel(at: url, completion: completion)
    }

    // MARK: - TranscriptionService

    func prepare(completion: @escaping (Bool) -> Void) {
        loadBundledModel(completion: completion)
    }

    // MARK: - Transcribe

    /// 当前用户词典拼接到 whisper initial_prompt 中的内容
    private var dictionaryPrompt: String {
        let suffix = UserDictionary.shared.whisperPromptSuffix
        // whisper.cpp initial_prompt 建议不超过 500 字符
        let maxLen = 400
        if suffix.count > maxLen {
            return String(suffix.prefix(maxLen))
        }
        return suffix
    }

    /// 转写音频文件（WAV，任意采样率，自动重采样到 16 kHz）
    func transcribe(audioURL: URL, language: String = "zh", completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self, let ctx = self.context else {
                dbg("[Whisper] context 为空，模型未加载")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let pcm = self.loadAudioAsPCM16k(url: audioURL) else {
                dbg("[Whisper] 音频转换失败: \(audioURL.lastPathComponent)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let sampleCount = pcm.count / 4
            dbg("[Whisper] 开始转写，采样点数: \(sampleCount)，时长约 \(sampleCount / 16000) 秒")

            let prompt = self.dictionaryPrompt
            var outText: UnsafeMutablePointer<CChar>? = nil
            let ok: Bool = pcm.withUnsafeBytes { ptr -> Bool in
                let floatPtr = ptr.bindMemory(to: Float.self).baseAddress!
                return whisper_wrapper_transcribe(ctx, floatPtr, Int32(sampleCount), language, prompt, &outText)
            }

            var result: String? = nil
            if ok, let cStr = outText {
                result = String(cString: cStr).trimmingCharacters(in: .whitespaces)
                free(cStr)
            }
            dbg("[Whisper] 转写完成，ok=\(ok)，结果: \(result ?? "(nil)")")
            completion(result)
        }
    }

    // MARK: - Audio Conversion

    /// 将任意格式音频读取并重采样为 16 kHz mono float32 PCM
    private func loadAudioAsPCM16k(url: URL) -> Data? {
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: 16000,
                                        channels: 1,
                                        interleaved: false)!
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            return nil
        }

        let inputFrameCapacity = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                 frameCapacity: inputFrameCapacity) else { return nil }
        guard (try? file.read(into: inputBuffer)) != nil else { return nil }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(inputFrameCapacity) * targetFormat.sampleRate / file.processingFormat.sampleRate + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: outputFrameCapacity) else { return nil }

        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }

        guard status != .error, let channelData = outputBuffer.floatChannelData else { return nil }

        let frameCount = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * 4)
        return data
    }

    /// 从原始 PCM buffer + 格式 重采样到 16kHz 并转写（同步，在 whisper queue 上调用）
    func transcribeBuffer(pcmData: Data, format: AVAudioFormat, language: String = "zh", completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self, let ctx = self.context else {
                completion(nil)
                return
            }

            guard let pcm16k = self.resampleToMono16k(pcmData: pcmData, sourceFormat: format) else {
                completion(nil)
                return
            }

            let sampleCount = pcm16k.count / 4
            guard sampleCount > 8000 else {  // 至少 0.5 秒
                completion(nil)
                return
            }

            let prompt = self.dictionaryPrompt
            var outText: UnsafeMutablePointer<CChar>? = nil
            let ok: Bool = pcm16k.withUnsafeBytes { ptr -> Bool in
                let floatPtr = ptr.bindMemory(to: Float.self).baseAddress!
                return whisper_wrapper_transcribe(ctx, floatPtr, Int32(sampleCount), language, prompt, &outText)
            }

            var result: String? = nil
            if ok, let cStr = outText {
                result = String(cString: cStr).trimmingCharacters(in: .whitespaces)
                free(cStr)
            }
            completion(result)
        }
    }

    /// 将任意格式 PCM Data 重采样为 16kHz mono float32
    private func resampleToMono16k(pcmData: Data, sourceFormat: AVAudioFormat) -> Data? {
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: 16000,
                                        channels: 1,
                                        interleaved: false)!

        let frameCount = AVAudioFrameCount(pcmData.count / (Int(sourceFormat.channelCount) * 4))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return nil }
        inputBuffer.frameLength = frameCount

        // 把 Data 拷贝进 inputBuffer
        pcmData.withUnsafeBytes { rawPtr in
            if let src = rawPtr.baseAddress, let dst = inputBuffer.floatChannelData?[0] {
                memcpy(dst, src, min(pcmData.count, Int(frameCount) * 4))
            }
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return nil }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(frameCount) * 16000.0 / sourceFormat.sampleRate + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: outputFrameCapacity) else { return nil }

        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }

        guard status != .error, let channelData = outputBuffer.floatChannelData else { return nil }
        return Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 4)
    }

    deinit {
        if let ctx = context {
            whisper_wrapper_free(ctx)
        }
    }
}
