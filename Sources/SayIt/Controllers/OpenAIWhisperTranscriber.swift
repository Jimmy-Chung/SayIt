import Foundation
import AVFoundation
import AudioToolbox

/// OpenAI Whisper API 云端语音转写
final class OpenAIWhisperTranscriber {

    static let shared = OpenAIWhisperTranscriber()
    private init() {}

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openaiWhisperApiKey") ?? ""
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: - Transcribe PCM Buffer

    /// 将 PCM buffer 转写为文本（录音结束时调用）
    func transcribeBuffer(pcmData: Data, format: AVAudioFormat, completion: @escaping (String?) -> Void) {
        guard !apiKey.isEmpty else {
            dbg("[OpenAIWhisper] API Key 为空")
            completion(nil)
            return
        }

        // 将 PCM 数据转为 M4A（AAC 压缩），失败则 fallback 到 WAV
        let audioData: Data
        let audioFilename: String
        let audioMimeType: String

        if let m4aData = pcmToM4A(pcmData: pcmData, format: format) {
            audioData = m4aData
            audioFilename = "audio.m4a"
            audioMimeType = "audio/m4a"
            dbg("[OpenAIWhisper] 使用 M4A 格式，大小: \(m4aData.count / 1024)KB")
        } else if let wavData = pcmToWAV(pcmData: pcmData, format: format) {
            audioData = wavData
            audioFilename = "audio.wav"
            audioMimeType = "audio/wav"
            dbg("[OpenAIWhisper] M4A 编码失败，fallback WAV，大小: \(wavData.count / 1024)KB")
        } else {
            dbg("[OpenAIWhisper] 音频编码失败")
            completion(nil)
            return
        }

        let baseURL = UserDefaults.standard.string(forKey: "openaiWhisperBaseURL")?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://api.openai.com"
        let url = URL(string: "\(baseURL)/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let modelName = UserDefaults.standard.string(forKey: "openaiWhisperModel")?.trimmingCharacters(in: .whitespaces) ?? "whisper-1"

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        // file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(audioMimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        field("model", modelName)
        field("response_format", "text")
        let lang = SpeechLanguage.current
        if lang != .auto_detect {
            field("language", lang.whisperCode)
        }
        // close
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                dbg("[OpenAIWhisper] 请求失败: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard let data = data else {
                dbg("[OpenAIWhisper] 无响应数据")
                completion(nil)
                return
            }

            guard statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                dbg("[OpenAIWhisper] HTTP \(statusCode): \(String(body.prefix(300)))")
                completion(nil)
                return
            }

            // response_format=text 直接返回纯文本
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            dbg("[OpenAIWhisper] 转写完成(\(result?.count ?? 0)字): \(result?.prefix(100) ?? "")")
            completion(result?.isEmpty == true ? nil : result)
        }.resume()
    }

    // MARK: - M4A (AAC) Encoding via ExtAudioFile

    private func pcmToM4A(pcmData: Data, format: AVAudioFormat) -> Data? {
        guard let float32Data = resampleToMono16k(pcmData: pcmData, sourceFormat: format) else { return nil }

        let sampleRate: Float64 = 16000
        let frameCount = float32Data.count / 4
        guard frameCount > 0 else { return nil }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a") as CFURL
        defer { try? FileManager.default.removeItem(at: tmpURL as URL) }

        // 输出格式：AAC
        var outDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        // 创建输出文件
        var extFile: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            tmpURL, kAudioFileM4AType, &outDesc, nil,
            AudioFileFlags.eraseFile.rawValue, &extFile
        )
        guard status == noErr, let file = extFile else {
            dbg("[OpenAIWhisper] ExtAudioFile 创建失败: \(status)")
            return nil
        }
        defer { ExtAudioFileDispose(file) }

        // 设置客户端格式（输入 PCM）
        var clientDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientDesc)
        guard status == noErr else {
            dbg("[OpenAIWhisper] 设置客户端格式失败: \(status)")
            return nil
        }

        // 设置编码比特率
        var bitRate: UInt32 = 32000
        var codecDesc = outDesc
        // 需要通过 converter 属性设置 bitrate
        var converterRef: AudioConverterRef?
        var converterSize = UInt32(MemoryLayout<AudioConverterRef>.size)
        status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &converterSize, &converterRef)
        if status == noErr, let converter = converterRef {
            AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate,
                                      UInt32(MemoryLayout<UInt32>.size), &bitRate)
        }

        // 写入 PCM 数据
        let writeResult: OSStatus = float32Data.withUnsafeBytes { rawPtr in
            let floatPtr = rawPtr.bindMemory(to: Float.self).baseAddress!
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(float32Data.count),
                    mData: UnsafeMutableRawPointer(mutating: floatPtr)
                )
            )
            return ExtAudioFileWrite(file, UInt32(frameCount), &bufferList)
        }

        guard writeResult == noErr else {
            dbg("[OpenAIWhisper] ExtAudioFile 写入失败: \(writeResult)")
            return nil
        }

        // 关闭文件确保数据刷入磁盘
        ExtAudioFileDispose(file)
        // extFile 已被 dispose，清空防止 defer 重复 dispose
        extFile = nil

        return try? Data(contentsOf: tmpURL as URL)
    }

    // MARK: - WAV Encoding (重采样到 16kHz mono int16)

    private func pcmToWAV(pcmData: Data, format: AVAudioFormat) -> Data? {
        // 先重采样到 16kHz mono int16，大幅减小上传体积
        guard let int16Data = resampleToMono16kInt16(pcmData: pcmData, sourceFormat: format) else {
            dbg("[OpenAIWhisper] 重采样失败，使用原始数据")
            return rawPCMToWAV(pcmData: pcmData, format: format)
        }

        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = UInt32(int16Data.count)

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM int16
        wav.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        wav.append("data".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wav.append(int16Data)

        dbg("[OpenAIWhisper] WAV 压缩: \(pcmData.count / 1024)KB → \(wav.count / 1024)KB")
        return wav
    }

    /// fallback: 原始 float32 PCM 直接打包 WAV
    private func rawPCMToWAV(pcmData: Data, format: AVAudioFormat) -> Data? {
        let sampleRate = UInt32(format.sampleRate)
        let channels = UInt16(format.channelCount)
        let bitsPerSample: UInt16 = 32
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = UInt32(pcmData.count)

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(3).littleEndian) { Data($0) })  // IEEE float
        wav.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        wav.append("data".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wav.append(pcmData)
        return wav
    }

    /// 将任意格式 PCM 重采样为 16kHz mono int16
    private func resampleToMono16k(pcmData: Data, sourceFormat: AVAudioFormat) -> Data? {
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: 16000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(pcmData.count / (Int(sourceFormat.channelCount) * 4))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return nil }
        inputBuffer.frameLength = frameCount

        pcmData.withUnsafeBytes { rawPtr in
            if let src = rawPtr.baseAddress, let dst = inputBuffer.floatChannelData?[0] {
                memcpy(dst, src, min(pcmData.count, Int(frameCount) * 4))
            }
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return nil }
        let outFrames = AVAudioFrameCount(Double(frameCount) * 16000.0 / sourceFormat.sampleRate + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return nil }

        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData; inputConsumed = true; return inputBuffer
        }
        guard status != .error, let floatData = outputBuffer.floatChannelData else { return nil }
        return Data(bytes: floatData[0], count: Int(outputBuffer.frameLength) * 4)
    }

    /// float32 → int16
    private func resampleToMono16kInt16(pcmData: Data, sourceFormat: AVAudioFormat) -> Data? {
        guard let float32Data = resampleToMono16k(pcmData: pcmData, sourceFormat: sourceFormat) else { return nil }
        let sampleCount = float32Data.count / 4
        var int16Data = Data(count: sampleCount * 2)
        float32Data.withUnsafeBytes { srcPtr in
            int16Data.withUnsafeMutableBytes { dstPtr in
                let src = srcPtr.bindMemory(to: Float.self)
                let dst = dstPtr.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    let sample = max(-1.0, min(1.0, src[i]))
                    dst[i] = Int16(sample * 32767)
                }
            }
        }
        return int16Data
    }

    // MARK: - Transcribe from file URL

    /// 从 WAV 文件读取并转写（设置页校准用）
    func transcribeBuffer(audioURL: URL, language: String, completion: @escaping (String?) -> Void) {
        guard !apiKey.isEmpty else {
            dbg("[OpenAIWhisper] API Key 为空")
            completion(nil)
            return
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            dbg("[OpenAIWhisper] 无法读取音频文件: \(audioURL.lastPathComponent)")
            completion(nil)
            return
        }

        let baseURL = UserDefaults.standard.string(forKey: "openaiWhisperBaseURL")?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://api.openai.com"
        let url = URL(string: "\(baseURL)/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let modelName = UserDefaults.standard.string(forKey: "openaiWhisperModel")?.trimmingCharacters(in: .whitespaces) ?? "whisper-1"

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        field("model", modelName)
        field("response_format", "text")
        if language != "auto" {
            field("language", language)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                dbg("[OpenAIWhisper] 文件转写失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data else { completion(nil); return }
            guard statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                dbg("[OpenAIWhisper] 文件转写 HTTP \(statusCode): \(String(body.prefix(300)))")
                completion(nil)
                return
            }
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            dbg("[OpenAIWhisper] 文件转写完成: \(result?.prefix(100) ?? "")")
            completion(result?.isEmpty == true ? nil : result)
        }.resume()
    }

    // MARK: - Key Validation

    static func validateKey(key: String, completion: @escaping (Bool, String?) -> Void) {
        guard !key.isEmpty else {
            completion(false, "Key 不能为空")
            return
        }

        let baseURL = UserDefaults.standard.string(forKey: "openaiWhisperBaseURL")?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://api.openai.com"
        let url = URL(string: "\(baseURL)/v1/models/whisper-1")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 {
                completion(true, nil)
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(false, "HTTP \(statusCode): \(String(body.prefix(100)))")
            }
        }.resume()
    }
}
