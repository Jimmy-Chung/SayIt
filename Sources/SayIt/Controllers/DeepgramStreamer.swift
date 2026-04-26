import Foundation
import AVFoundation

/// Deepgram WebSocket 流式语音转文字
final class DeepgramStreamer {

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var onPartialResult: ((String) -> Void)?
    private var onComplete: ((String?) -> Void)?
    private var finalSegments: [String] = []
    private var currentInterim: String = ""
    private var finished = false

    // MARK: - Start

    func start(sampleRate: Int, onPartial: @escaping (String) -> Void) {
        let apiKey = UserDefaults.standard.string(forKey: "deepgramApiKey") ?? ""
        guard !apiKey.isEmpty else {
            dbg("[DeepgramStream] API Key 为空")
            return
        }

        self.onPartialResult = onPartial
        self.finalSegments = []
        self.currentInterim = ""
        self.finished = false

        let langCode = SpeechLanguage.current.deepgramCode
        let urlStr = "wss://api.deepgram.com/v1/listen?model=nova-3&language=\(langCode)&smart_format=true&punctuate=true&interim_results=true&encoding=linear16&sample_rate=\(sampleRate)&channels=1"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        dbg("[DeepgramStream] WebSocket 已连接, sampleRate=\(sampleRate)")
        receiveMessage()
    }

    // MARK: - Send Audio

    /// 发送 float32 PCM buffer，内部转换为 int16
    func sendAudioChunk(_ buffer: AVAudioPCMBuffer) {
        guard let ws = webSocket, !finished else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        var int16Data = Data(count: frameCount * 2)

        int16Data.withUnsafeMutableBytes { rawPtr in
            let ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, channelData[0][i]))
                ptr[i] = Int16(sample * 32767)
            }
        }

        ws.send(.data(int16Data)) { error in
            if let error = error {
                dbg("[DeepgramStream] 发送错误: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Stop

    func stop(completion: @escaping (String?) -> Void) {
        guard !finished else {
            let result = buildFinalText()
            completion(result.isEmpty ? nil : result)
            return
        }

        self.onComplete = completion

        // 发送 CloseStream 告知 Deepgram 音频结束
        let closeMsg = "{\"type\": \"CloseStream\"}"
        webSocket?.send(.string(closeMsg)) { [weak self] error in
            if let error = error {
                dbg("[DeepgramStream] CloseStream 发送失败: \(error.localizedDescription)")
                self?.finish()
            }
        }

        // 超时保护：5 秒后强制结束
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finish()
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self, !self.finished else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receiveMessage()

            case .failure(let error):
                dbg("[DeepgramStream] 连接关闭: \(error.localizedDescription)")
                self.finish()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "Results" else { return }

        let isFinal = json["is_final"] as? Bool ?? false

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else { return }

        if isFinal {
            if !transcript.isEmpty {
                finalSegments.append(transcript)
            }
            currentInterim = ""
        } else {
            currentInterim = transcript
        }

        let fullText = buildFinalText()
        if !fullText.isEmpty {
            onPartialResult?(fullText)
        }
    }

    // MARK: - Finish

    private func buildFinalText() -> String {
        (finalSegments.joined() + currentInterim).trimmingCharacters(in: .whitespaces)
    }

    private func finish() {
        guard !finished else { return }
        finished = true

        let result = buildFinalText()
        let completion = onComplete
        onComplete = nil
        onPartialResult = nil

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        dbg("[DeepgramStream] 最终结果(\(result.count)字): \(result.prefix(100))")
        completion?(result.isEmpty ? nil : result)
    }
}
