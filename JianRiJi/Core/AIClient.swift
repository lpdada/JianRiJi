import Foundation

/// AI 厂商。全部走 OpenAI 兼容的 /chat/completions，不做 Anthropic 格式。
/// 模型与地址都可以在设置里改，下面的只是各家默认值。
enum AIVendor: String, CaseIterable, Identifiable, Codable, Sendable {
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
    /// 设备锁着，Keychain 读不到（不是「没配置」）。
    case keychainLocked
    case notConfigured(String)
    case http(Int, String)
    case rateLimited(retryAfter: Int?)
    case network(String)
    case badResponse
    /// 用户切页 / 主动取消。UI 不该把它当错误弹出来。
    case cancelled
    case busy

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "当前厂商还没保存 API Key，去「设置 → AI」里添加。"
        case .keychainLocked:
            return "设备锁定中，解锁后重试。"
        case .notConfigured(let what):
            return "AI 还没配好：\(what)"
        case .http(let code, let message):
            return message.isEmpty ? "模型返回 HTTP \(code)。" : "模型返回 HTTP \(code)：\(message)"
        case .rateLimited(let retryAfter):
            if let retryAfter { return "请求太频繁，\(retryAfter) 秒后自动重试。" }
            return "请求太频繁，稍后再试。"
        case .network(let message):
            return "网络请求失败：\(message)"
        case .badResponse:
            return "模型返回的内容解析失败，换个模型或稍后再试。"
        case .cancelled:
            return "已取消。"
        case .busy:
            return "还有请求在跑，等它回来再试。"
        }
    }

    /// 是否值得弹给用户看。取消不算错误。
    var isSilent: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// 同时在跑的 AI 请求上限。
///
/// 原实现连点「问猫爪」会并发打十几个请求，每个都可能计费、都可能 429。
/// 这里把并发压到 2，超出的排队，而不是全部轰出去。
actor AIRequestGate {
    static let shared = AIRequestGate(limit: 2)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        active += 1
    }

    func release() {
        active = max(0, active - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }
}

/// 只发给用户选中的厂商。Key 从 Keychain 读，绝不写进日志、存档或错误信息里。
enum AIClient {

    /// 专用会话：默认超时、不缓存、不在弱网下无限等待。
    /// 原来用 `URLSession.shared`（60 秒请求超时 + 无限资源等待），AI 卡住时用户只能看转圈。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "JianRiJi/0.4 (iOS)",
        ]
        return URLSession(configuration: configuration)
    }()

    private static let maxAttempts = 3

    // MARK: - 配置解析

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

    // MARK: - 对话

    static func chat(
        settings: AppSettings,
        system: String,
        user: String,
        maxTokens: Int = 800
    ) async throws -> String {
        let request = try makeRequest(
            settings: settings,
            system: system,
            user: user,
            maxTokens: maxTokens,
            stream: false
        )

        await AIRequestGate.shared.acquire()
        do {
            let (data, http) = try await perform(request)
            guard (200..<300).contains(http.statusCode) else {
                let message = errorMessage(from: data, key: currentKey(for: settings))
                if http.statusCode == 429 {
                    throw AIError.rateLimited(retryAfter: retryAfterSeconds(from: http))
                }
                throw AIError.http(http.statusCode, message)
            }
            let content = try parseContent(from: data)
            await AIRequestGate.shared.release()
            return content
        } catch {
            await AIRequestGate.shared.release()
            throw error
        }
    }

    /// 流式输出（SSE）。UI 需要「打字机」效果时接这个；不接也不影响普通 `chat`。
    /// 注意：调用方负责在 View 上以 `@MainActor` 增量刷新。
    static func streamChat(
        settings: AppSettings,
        system: String,
        user: String,
        maxTokens: Int = 800,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        var request = try makeRequest(
            settings: settings,
            system: system,
            user: user,
            maxTokens: maxTokens,
            stream: true
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        await AIRequestGate.shared.acquire()
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.http(http.statusCode, "")
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let piece = delta["content"] as? String,
                      !piece.isEmpty else { continue }
                await onDelta(piece)
            }
            await AIRequestGate.shared.release()
        } catch {
            await AIRequestGate.shared.release()
            throw normalize(error)
        }
    }

    // MARK: - 请求构造

    private static func makeRequest(
        settings: AppSettings,
        system: String,
        user: String,
        maxTokens: Int,
        stream: Bool
    ) throws -> URLRequest {
        guard let baseURLString = effectiveBaseURL(settings: settings),
              let baseURL = URL(string: baseURLString) else {
            throw AIError.notConfigured("自定义厂商请先填接口地址。")
        }
        let model = effectiveModel(settings: settings)
        guard !model.isEmpty else {
            throw AIError.notConfigured("请先填模型名。")
        }
        let key: String
        do {
            key = try KeychainHelper.readOrThrow(account: settings.aiVendor.rawValue)
        } catch KeychainError.locked {
            throw AIError.keychainLocked
        } catch {
            throw AIError.noKey
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if settings.aiVendor == .opencodeGo {
            // Opencode 网关靠这三个头路由，不光认 Key。
            request.setValue("JianRiJi", forHTTPHeaderField: "x-opencode-client")
            request.setValue(opencodeSessionID(), forHTTPHeaderField: "x-opencode-session")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "x-opencode-request")
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
            "max_tokens": max(64, min(maxTokens, 4096)),
        ]
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - 发送与重试

    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
                if shouldRetry(status: http.statusCode), attempt < maxAttempts {
                    try await sleepBeforeRetry(attempt: attempt, status: http.statusCode, response: http)
                    continue
                }
                return (data, http)
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as URLError where error.code == .cancelled {
                throw AIError.cancelled
            } catch let error as URLError {
                // 连接被断、DNS 抖动：重试一次就够，不要把用户的流量耗在重试上。
                if shouldRetry(urlError: error), attempt < maxAttempts {
                    try await sleepBeforeRetry(attempt: attempt, status: nil, response: nil)
                    continue
                }
                throw AIError.network(error.localizedDescription)
            }
        }
    }

    private static func shouldRetry(status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    private static func shouldRetry(urlError: URLError) -> Bool {
        switch urlError.code {
        case .timedOut, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func sleepBeforeRetry(
        attempt: Int,
        status: Int?,
        response: HTTPURLResponse?
    ) async throws {
        var seconds = pow(2.0, Double(attempt - 1)) * 0.8
        if status == 429, let response,
           let header = response.value(forHTTPHeaderField: "Retry-After"),
           let value = Double(header) {
            seconds = min(max(value, 1), 8)
        }
        try await Task.sleep(nanoseconds: UInt64(min(max(seconds, 0.4), 8) * 1_000_000_000))
    }

    // MARK: - 响应解析

    private static func parseContent(from data: Data) throws -> String {
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

    private static func errorMessage(from data: Data, key: String?) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return ""
        }
        return redact(message, key: key)
    }

    /// 上游把请求体回显在错误里是常事，回显里可能带 Authorization。
    /// 进 UI 之前统一抹掉。
    static func redact(_ text: String, key: String?) -> String {
        var out = text
        if let key, !key.isEmpty {
            out = out.replacingOccurrences(of: key, with: "***")
        }
        out = out.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{8,}"#,
            with: "sk-***",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"Bearer\s+\S+"#,
            with: "Bearer ***",
            options: .regularExpression
        )
        return String(out.prefix(300))
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let value = Int(header) {
            return value
        }
        return nil
    }

    private static func currentKey(for settings: AppSettings) -> String? {
        KeychainHelper.read(account: settings.aiVendor.rawValue)
    }

    private static func normalize(_ error: Error) -> AIError {
        if let aiError = error as? AIError { return aiError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .network(error.localizedDescription)
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
