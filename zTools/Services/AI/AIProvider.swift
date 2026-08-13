import Foundation

protocol AIProvider: Sendable {
    var id: String { get }
    func translate(text: String, from: String?, to: String) async throws -> String
}

struct OpenAICompatibleProvider: AIProvider {
    let id: String
    let baseURL: URL
    let apiKey: String
    let model: String

    func translate(text: String, from: String?, to: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslateError.missingAPIKey
        }

        let endpoint = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let source = from?.isEmpty == false ? from! : "auto"
        let system = """
        You are a professional translator. Translate the user content into language code "\(to)".
        Source language hint: \(source).
        Rules:
        - Output only the translated text
        - Preserve meaning, tone, and formatting
        - Do not add explanations
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TranslateError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw TranslateError.http(http.statusCode, Self.friendlyServerMessage(data: data, code: http.statusCode))
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw TranslateError.emptyResult
            }
            return content
        } catch let error as TranslateError {
            throw error
        } catch let error as URLError {
            throw TranslateError.network(error.localizedDescription)
        } catch {
            throw TranslateError.network(error.localizedDescription)
        }
    }

    /// 连通性测试：发极短翻译请求
    func testConnection() async throws -> String {
        try await translate(text: "ping", from: "en", to: "zh")
    }

    private static func friendlyServerMessage(data: Data, code: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any] {
                if let msg = err["message"] as? String { return msg }
            }
            if let msg = obj["message"] as? String { return msg }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        switch code {
        case 401: return "API Key 无效或未授权 (401)"
        case 402: return "账户余额不足 (402)"
        case 403: return "无访问权限 (403)"
        case 429: return "请求过于频繁，请稍后重试 (429)"
        case 500...599: return "服务端错误 (\(code))"
        default:
            return raw.isEmpty ? "HTTP \(code)" : raw
        }
    }
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

enum TranslateError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyResult
    case network(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "请先在设置中配置 API Key"
        case .invalidURL: "API 地址无效，请检查 Base URL"
        case .invalidResponse: "响应格式无效"
        case .emptyResult: "模型返回为空"
        case .network(let message): "网络错误：\(message)"
        case .http(_, let message): message
        }
    }
}
