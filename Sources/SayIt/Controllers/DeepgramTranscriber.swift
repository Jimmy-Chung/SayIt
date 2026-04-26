import Foundation
import AVFoundation

/// Deepgram Nova-3 云端语音转写
final class DeepgramTranscriber: TranscriptionService {

    static let shared = DeepgramTranscriber()
    private init() {}

    var isLoaded: Bool {
        !apiKey.isEmpty
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "deepgramApiKey") ?? ""
    }

    func prepare(completion: @escaping (Bool) -> Void) {
        let ok = !apiKey.isEmpty
        if !ok {
            dbg("[Deepgram] API Key 未配置")
        } else {
            dbg("[Deepgram] 就绪")
        }
        DispatchQueue.main.async { completion(ok) }
    }

    func transcribe(audioURL: URL, language: String, completion: @escaping (String?) -> Void) {
        guard !apiKey.isEmpty else {
            dbg("[Deepgram] API Key 为空")
            completion(nil)
            return
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            dbg("[Deepgram] 无法读取音频文件: \(audioURL.lastPathComponent)")
            completion(nil)
            return
        }

        let lang = language == "zh" ? "zh-CN" : language
        let urlStr = "https://api.deepgram.com/v1/listen?model=nova-3&language=\(lang)&smart_format=true&punctuate=true"
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 30

        dbg("[Deepgram] 发送转写请求，音频大小: \(audioData.count) bytes，语言: \(lang)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                dbg("[Deepgram] 请求失败: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard let data = data else {
                dbg("[Deepgram] 无响应数据")
                completion(nil)
                return
            }

            guard statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                dbg("[Deepgram] HTTP \(statusCode): \(String(body.prefix(300)))")
                completion(nil)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let channels = results["channels"] as? [[String: Any]],
                  let firstChannel = channels.first,
                  let alternatives = firstChannel["alternatives"] as? [[String: Any]],
                  let firstAlt = alternatives.first,
                  let transcript = firstAlt["transcript"] as? String else {
                dbg("[Deepgram] 解析失败: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
                completion(nil)
                return
            }

            let result = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            dbg("[Deepgram] 转写完成: \(result.prefix(100))")
            completion(result.isEmpty ? nil : result)
        }.resume()
    }

    func transcribeBuffer(pcmData: Data, format: AVAudioFormat, language: String, completion: @escaping (String?) -> Void) {
        // 云端转写不支持实时 buffer 转写，返回 nil
        completion(nil)
    }

    // MARK: - Key Validation

    /// 用 Deepgram 的 /projects 接口校验 Key 是否有效
    static func validateKey(key: String, completion: @escaping (Bool, String?) -> Void) {
        guard !key.isEmpty else {
            completion(false, "Key 不能为空")
            return
        }

        let url = URL(string: "https://api.deepgram.com/v1/projects")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
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
