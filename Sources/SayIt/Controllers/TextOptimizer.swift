import Foundation

enum OptimizeError: Error {
    case notConfigured
    case networkError
    case apiError(String)
    case parseError
}

final class TextOptimizer {

    static let shared = TextOptimizer()
    private init() {}
    private var currentTask: URLSessionDataTask?

    private let systemPrompt = """
你是一个语音转文字的后处理助手。你的输入来自语音识别引擎（ASR），可能包含识别错误。用户的语音输入主要用于与 AI 对话，因此输出应当逻辑清晰、结构化、口吻职业化。

请严格按以下规则处理：

## 核心原则
- ASR 纠错：语音识别经常把专业术语、技术名词、英文单词识别错误。你必须根据上下文推断用户的真实意图，修正这类错误。例如："whiper"→"Whisper"、"Adan"→"Agent"、"派森"→"Python"、"吉特"→"Git"、"诶派爱"→"API"。对于中英混杂的表达，优先还原为正确的英文术语。
- 最小修正：除 ASR 纠错外，只修正错别字、多余的语气词（嗯、啊、那个、就是）、口误重复词，以及补充缺失的标点。绝对不要改写用户的措辞、句式和原意。如果一句话本身逻辑完整、表达清晰，不做任何修改。
- 职业化口吻：去除口语化的冗余表达，使文本读起来简洁专业，但不要替换用户的核心用词。

## 标点与格式规则
- 根据语气补充正确的标点：疑问语气用问号，感叹/强调用感叹号，祈使/陈述用句号，未说完的停顿用逗号或省略号。
- 当后句是对前句的解释或展开时，使用冒号连接。
- 特殊名词、技术术语、或表示引用的内容，用「」标注。
- 当用户表达了分点内容（如"第一点/第二点"、"首先/其次"、"1/2/3"、或语义上可明确分点的并列内容），必须换行并使用有序列表（1. 2. 3.）格式输出。
- 当分点内容存在层级关系（如大点下包含小点），必须识别并体现层级结构。大点用数字序号（1. 2. 3.），子要点用字母序号并缩进，格式示例：
  1. 第一点
     (a) 子要点一
     (b) 子要点二
  2. 第二点
  如有更深层级，继续用 i. ii. iii. 缩进。
- 当用户列举多个并列项但无明确顺序时，使用无序列表（- ）格式。
- 代码相关的标识符（函数名、变量名、文件名、命令等）使用反引号包裹。

## 禁止行为（最高优先级）
- 你绝对不是聊天助手，禁止回答任何问题。即使用户的语音是提问，你也只能纠正转写错误并补充标点，绝不能生成回答内容。
- 不要添加用户没有表达的内容。
- 不要对用户的观点进行总结、归纳或补充。
- 不要添加开头的称呼或结尾的总结语。
- 不要展开、解释或扩写用户的任何表述。
- 不要输出任何解释，只输出处理后的文本。
- 输出长度必须与输入长度基本一致，不得显著变长。
"""

    // MARK: - State

    var selectedProvider: LLMProvider {
        LLMProvider(rawValue: UserDefaults.standard.string(forKey: "selectedLLMProvider") ?? "none") ?? .none
    }

    func apiKey(for provider: LLMProvider) -> String {
        guard provider != .none else { return "" }
        return UserDefaults.standard.string(forKey: provider.apiKeyStorageKey) ?? ""
    }

    var isAvailable: Bool {
        selectedProvider != .none && !apiKey(for: selectedProvider).isEmpty
    }

    var needsKeyConfiguration: Bool {
        selectedProvider != .none && apiKey(for: selectedProvider).isEmpty
    }

    // MARK: - Provider Config

    private func endpoint(for provider: LLMProvider) -> URL {
        switch provider {
        case .deepseek: return URL(string: "https://api.deepseek.com/chat/completions")!
        case .gemini:   return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .minimax:
            let base = UserDefaults.standard.string(forKey: "minimaxBaseURL")
                ?? "https://api.minimax.chat"
            return URL(string: "\(base)/v1/chat/completions")!
        case .none:     fatalError()
        }
    }

    private func model(for provider: LLMProvider) -> String {
        switch provider {
        case .deepseek: return "deepseek-chat"
        case .gemini:   return "gemini-2.5-pro"
        case .minimax:  return "MiniMax-Text-01"
        case .none:     return ""
        }
    }

    // MARK: - Optimize (所有 Provider 统一走 OpenAI 兼容格式)

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func optimize(rawText: String, context: AppContext? = nil, completion: @escaping (Result<String, OptimizeError>) -> Void) {
        let provider = selectedProvider
        let key = apiKey(for: provider)
        guard provider != .none, !key.isEmpty else {
            completion(.failure(.notConfigured))
            return
        }
        dbg("[TextOptimizer] 使用 \(provider.displayName) 优化，文本长度: \(rawText.count)")

        var req = URLRequest(url: endpoint(for: provider))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20

        var prompt = systemPrompt
        if let context = context, context != .general {
            prompt += context.llmPromptSuffix
        }

        let body: [String: Any] = [
            "model": model(for: provider),
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user",   "content": rawText]
            ],
            "temperature": 0.2,
            "max_tokens": max(32, rawText.count + 16)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        currentTask = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            self?.currentTask = nil
            if let error = error {
                dbg("[TextOptimizer] 请求失败: \(error.localizedDescription)")
                completion(.failure(.networkError))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(statusCode) else {
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8)?.prefix(200) } ?? ""
                dbg("[TextOptimizer] API 错误: HTTP \(statusCode), body: \(bodyStr)")
                completion(.failure(.apiError("HTTP \(statusCode)")))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                if let data = data {
                    dbg("[TextOptimizer] 解析失败: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
                }
                completion(.failure(.parseError))
                return
            }
            let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
            dbg("[TextOptimizer] 优化完成: \(result.prefix(100))")
            completion(.success(result))
        }
        currentTask?.resume()
    }

    // MARK: - Key Validation

    func validateKey(provider: LLMProvider, key: String, completion: @escaping (Bool, String?) -> Void) {
        guard provider != .none, !key.isEmpty else {
            completion(false, "Key 不能为空")
            return
        }

        let url = endpoint(for: provider)
        dbg("[TextOptimizer] 验证 \(provider.displayName) Key, URL: \(url.absoluteString)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        let body: [String: Any] = [
            "model": model(for: provider),
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            dbg("[TextOptimizer] 验证响应: HTTP \(statusCode), body: \(String(bodyStr.prefix(300)))")

            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            if statusCode == 200 {
                completion(true, nil)
            } else {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let errMsg = error["message"] as? String {
                    completion(false, errMsg)
                } else {
                    completion(false, "HTTP \(statusCode): \(String(bodyStr.prefix(100)))")
                }
            }
        }.resume()
    }
}
