import Foundation

/// 云端（登录 / 云同步 / 团队打卡）的 HTTP 客户端，对应词屿 server/ 的 API。
///
/// 约定：POST {base}/api/auth/sms，POST {base}/api/auth/login，
/// GET/PUT {base}/api/sync，GET/POST {base}/api/team/*。
/// 服务端地址由用户在设置里填，空 = 功能关闭；token 由调用方
/// 在每次请求里带 Authorization: Bearer，本类不落盘。
/// 短信通道服务端是空实现：开发模式下 /auth/sms 会直接返回 devCode，
/// 生产模式不返回也不真发短信——没接短信商之前只能用开发模式。
final class CloudAPI {
    static let defaultTimeout: Double = 15
    /// 服务端 sync 的 payload 上限（512KB），超了会报 413。
    static let maxPayloadBytes = 512 * 1024

    enum Failure: LocalizedError {
        case notConfigured
        case invalidURL
        case invalidPhone
        case invalidCode
        case unauthorized
        case http(status: Int, body: String)
        case invalidResponse
        case payloadTooLarge
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "没有配置云端服务器地址"
            case .invalidURL: return "云端服务器地址无效"
            case .invalidPhone: return "手机号格式不对"
            case .invalidCode: return "请输入 6 位验证码"
            case .unauthorized: return "登录已过期，请重新登录"
            case .http(let status, let body):
                let snippet = body.isEmpty ? "" : "：\(body.prefix(120))"
                return "服务器返回 \(status)\(snippet)"
            case .invalidResponse: return "服务器返回的内容看不懂"
            case .payloadTooLarge: return "进度数据超过服务器上限（512KB）"
            case .network(let message): return "连接云端服务器失败：\(message)"
            }
        }
    }

    struct CloudUser: Codable, Equatable {
        var id: Int
        var phone: String
        var nickname: String
    }

    struct CloudTeam: Codable, Equatable {
        var id: Int
        var name: String
        var code: String
        var days: Int
        var deposit: Int
        var status: String
        var memberCount: Int
        var allDoneToday: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, code, days, deposit, status, memberCount, allDoneToday
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
            days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 30
            deposit = try c.decodeIfPresent(Int.self, forKey: .deposit) ?? 0
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
            memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
            allDoneToday = try c.decodeIfPresent(Bool.self, forKey: .allDoneToday) ?? false
        }
    }

    struct TeamMember: Codable, Equatable, Identifiable {
        var id: Int
        var nickname: String
        /// 服务端返回 0/1。
        var checkedToday: Int
        var totalDays: Int

        var hasCheckedToday: Bool { checkedToday == 1 }
    }

    struct SyncSnapshot {
        var payload: Data?
        var updatedAt: Int
    }

    var baseURL: String
    var token: String?
    /// 测试可注入；返回响应体 + 状态码。
    var send: (URLRequest) async throws -> (Data, Int)

    init(
        baseURL: String,
        token: String? = nil,
        send: @escaping (URLRequest) async throws -> (Data, Int) = CloudAPI.defaultSend
    ) {
        self.baseURL = baseURL
        self.token = token
        self.send = send
    }

    static func defaultSend(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.network("响应不是 HTTP")
        }
        return (data, http.statusCode)
    }

    // MARK: - 纯函数（可单测）

    /// 手机号：11 位，1 开头，第二位 3-9，其余全是数字（与服务端同一条规则）。
    static func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 11 else { return false }
        let chars = Array(digits)
        guard chars[0] == "1",
              let second = chars[1].wholeNumberValue,
              (3...9).contains(second) else { return false }
        return chars.allSatisfy { $0.isNumber }
    }

    /// 地址归一化：接受 `https://host`、`https://host/`、无协议的 `host`；
    /// 要求 http/https + 有 host，否则返回 nil。空地址返回 nil（未配置）。
    static func endpointURL(for base: String, path: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasSuffix(":") else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        let cleanPath = path.hasPrefix("/") ? path : "/" + path
        return url.appendingPathComponent(cleanPath)
    }

    static func makeRequest(
        baseURL: String,
        path: String,
        method: String,
        token: String?,
        body: Data?,
        timeout: Double
    ) throws -> URLRequest {
        guard let url = endpointURL(for: baseURL, path: path) else {
            throw baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? Failure.notConfigured
                : Failure.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(max(timeout, 5), 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    // MARK: - 调用

    private struct EmptyResponse: Decodable {}

    private func call<T: Decodable>(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> T {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            body: body,
            timeout: Self.defaultTimeout
        )
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        if status == 401 {
            throw Failure.unauthorized
        }
        guard (200...299).contains(status) else {
            throw Failure.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Failure.invalidResponse
        }
    }

    private func jsonBody(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw Failure.invalidResponse
        }
    }

    func health() async throws -> Bool {
        struct Health: Decodable { var ok: Bool }
        let result: Health = try await call(path: "/api/health", method: "GET")
        return result.ok
    }

    /// 发验证码。开发模式下服务端直接返回 devCode（6 位），App 里会显示出来；
    /// 生产模式不返回，只能等短信——服务端没接短信商，生产模式发了也收不到。
    func requestCode(phone: String) async throws -> String? {
        guard Self.isValidPhone(phone) else { throw Failure.invalidPhone }
        struct Reply: Decodable {
            var sent: Bool
            var devCode: String?
        }
        let body = try jsonBody(["phone": phone])
        let reply: Reply = try await call(path: "/api/auth/sms", method: "POST", body: body)
        return reply.devCode
    }

    func login(phone: String, code: String) async throws -> (token: String, user: CloudUser) {
        guard Self.isValidPhone(phone) else { throw Failure.invalidPhone }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6, trimmedCode.allSatisfy({ $0.isNumber }) else {
            throw Failure.invalidCode
        }
        struct Reply: Decodable {
            var token: String
            var user: CloudUser
        }
        let body = try jsonBody(["phone": phone, "code": trimmedCode])
        let reply: Reply = try await call(path: "/api/auth/login", method: "POST", body: body)
        return (reply.token, reply.user)
    }

    func me() async throws -> CloudUser {
        struct Reply: Decodable { var user: CloudUser }
        let reply: Reply = try await call(path: "/api/auth/me", method: "GET")
        return reply.user
    }

    func rename(nickname: String) async throws {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try jsonBody(["nickname": name])
        let _: EmptyResponse = try await call(path: "/api/auth/me", method: "PATCH", body: body)
    }

    /// 拉云端进度。服务端不解析 payload，这里也原样透传，不按任何结构解。
    func syncGet() async throws -> SyncSnapshot {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            path: "/api/sync",
            method: "GET",
            token: token,
            body: nil,
            timeout: Self.defaultTimeout
        )
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        if status == 401 {
            throw Failure.unauthorized
        }
        guard (200...299).contains(status) else {
            throw Failure.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedAt = object["updatedAt"] as? Int else {
            throw Failure.invalidResponse
        }
        var payloadData: Data?
        if let payload = object["payload"], !(payload is NSNull) {
            payloadData = try? JSONSerialization.data(withJSONObject: payload)
        }
        return SyncSnapshot(payload: payloadData, updatedAt: updatedAt)
    }

    /// 推云端进度。超 512KB 服务端报 413。
    @discardableResult
    func syncPut(payload: Data) async throws -> Int {
        guard payload.count <= Self.maxPayloadBytes else { throw Failure.payloadTooLarge }
        // 服务端要的是 {"payload": {...}}，这里把已编码的 JSON 嵌进去。
        var object: [String: Any] = [:]
        if let parsed = try? JSONSerialization.jsonObject(with: payload) {
            object["payload"] = parsed
        } else {
            throw Failure.invalidResponse
        }
        let body = try jsonBody(object)
        struct Reply: Decodable { var updatedAt: Int }
        let reply: Reply = try await call(path: "/api/sync", method: "PUT", body: body)
        return reply.updatedAt
    }

    struct TeamReply: Decodable {
        var team: CloudTeam?
        var members: [TeamMember]
    }

    func teamGet() async throws -> TeamReply {
        try await call(path: "/api/team", method: "GET")
    }

    func teamCreate(name: String, days: Int, deposit: Int) async throws -> CloudTeam {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedDays = min(max(days, 7), 100)
        let clampedDeposit = min(max(deposit, 0), 10_000)
        let body = try jsonBody(["name": cleanName, "days": clampedDays, "deposit": clampedDeposit])
        struct Reply: Decodable { var team: CloudTeam }
        let reply: Reply = try await call(path: "/api/team/create", method: "POST", body: body)
        return reply.team
    }

    func teamJoin(code: String) async throws -> CloudTeam {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = try jsonBody(["code": clean])
        struct Reply: Decodable { var team: CloudTeam }
        let reply: Reply = try await call(path: "/api/team/join", method: "POST", body: body)
        return reply.team
    }

    func teamLeave() async throws {
        let _: EmptyResponse = try await call(path: "/api/team/leave", method: "POST")
    }

    /// 今日打卡。返回是否已经打过（服务端去重）。
    func teamCheckin() async throws -> Bool {
        struct Reply: Decodable {
            var ok: Bool
            var already: Bool?
        }
        let reply: Reply = try await call(path: "/api/team/checkin", method: "POST")
        return reply.already ?? false
    }

    func teamHistory() async throws -> [String] {
        struct Reply: Decodable { var dates: [String] }
        let reply: Reply = try await call(path: "/api/team/history", method: "GET")
        return reply.dates
    }
}
