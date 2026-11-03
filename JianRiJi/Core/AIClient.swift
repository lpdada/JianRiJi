import Foundation

/// AI 厂商。全部走 OpenAI 兼容的 /chat/completions，不做 Anthropic 格式。
/// 模型与地址都可以在设置里改，下面的只是各家默认值。
enum AIVendor: String, CaseIterable, Identifiable, Codable {
    case opencodeGo
    case openai
    case deepseek
    case glm
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opencodeGo: return "Opencode Go"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .glm: return "智谱 GLM"
        case .custom: return "自定义（OpenAI 兼容）"
        }
    }

    /// 预设厂商的固定地址；自定义厂商没有默认值，必须在设置里填。
    var defaultBaseURL: String? {
        switch self {
        case .opencodeGo: return "https://opencode.ai/zen/go/v1"
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .custom: return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .opencodeGo: return "deepseek-v4.1-flash"
        case .openai: return "gpt-4o-mini"
        case .deepseek: return "deepseek-chat"
        case .glm: return "glm-4-flash"
        case .custom: return ""
        }
    }
}

enum AIError: LocalizedError {
    case noKey
    case notConfigured(String)
    case http(Int, String)
    case network(Error)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "当前厂商还没保存 API Key，去「设置 → AI」里添加。"
        case .notConfigured(let what):
            return "AI 还没配好：\(what)"
        case .http(let code, let message):
            return message.isEmpty ? "模型返回 HTTP \(code)。" : "模型返回 HTTP \(code)：\(message)"
        case .network(let error):
            return "网络请求失败：\(error.localizedDescription)"
        case .badResponse:
            return "模型返回的内容解析失败，换个模型或稍后再试。"
        }
    }
}

/// 只发给用户选中的厂商。Key 从 Keychain 读，绝不写进日志、存档或错误信息里。
enum AIClient {

    static func effectiveModel(settings: AppSettings) -> String {
        let custom = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? settings.aiVendor.defaultModel : custom
    }

    static func effectiveBaseURL(settings: AppSettings) -> String? {
        let custom = settings.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return settings.aiVendor.defaultBaseURL
    }

    static func hasKey(settings: AppSettings) -> Bool {
        KeychainHelper.read(account: settings.aiVendor.rawValue) != nil
    }

    static func chat(settings: AppSettings, system: String, user: String) async throws -> String {
        guard let key = KeychainHelper.read(account: settings.aiVendor.rawValue) else {
            throw AIError.noKey
        }
        guard let baseURLString = effectiveBaseURL(settings: settings),
              let baseURL = URL(string: baseURLString) else {
            throw AIError.notConfigured("自定义厂商请先填接口地址。")
        }
        let model = effectiveModel(settings: settings)
        guard !model.isEmpty else {
            throw AIError.notConfigured("请先填模型名。")
        }
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if settings.aiVendor == .opencodeGo {
            // Opencode 网关靠这三个头路由，不光认 Key。session 是本机固定 UUID，
            // request 每次请求一个新 UUID，client 固定填 App 名。
            request.setValue("JianRiJi", forHTTPHeaderField: "x-opencode-client")
            request.setValue(opencodeSessionID(), forHTTPHeaderField: "x-opencode-session")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "x-opencode-request")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
            "max_tokens": 800,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, errorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return ""
        }
        return message
    }

    private static func opencodeSessionID() -> String {
        let key = "aiOpencodeSessionID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
