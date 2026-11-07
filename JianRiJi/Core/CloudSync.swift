import Foundation

/// 云端同步的进度包：只含学习进度，不含词库本身（词库随包走）。
/// cards 只放动过的卡（新词不进包——10,660 张全放会超服务端 512KB 上限）；
/// log 只留最近 500 条。服务端不解析，直接原样存。
struct CloudProgressPayload: Codable {
    var version: Int = 1
    var cards: [String: SRSState] = [:]
    var log: [ReviewLogEntry] = []
    var favorites: [String] = []
    var learnedGrammar: [String] = []

    enum CodingKeys: String, CodingKey { case version, cards, log, favorites, learnedGrammar }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cards = try c.decodeIfPresent([String: SRSState].self, forKey: .cards) ?? [:]
        log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        learnedGrammar = try c.decodeIfPresent([String].self, forKey: .learnedGrammar) ?? []
    }
}

/// 进度包的拼装与合并（纯函数，可单测）。
enum CloudPayload {
    static let maxLogEntries = 500
    static let maxStoredLogEntries = 5_000

    /// 从 Store 的当前状态拼一个待上传的包。
    static func build(
        cards: [String: SRSState],
        log: [ReviewLogEntry],
        favorites: Set<String>,
        learnedGrammar: Set<String>
    ) -> CloudProgressPayload {
        var payload = CloudProgressPayload()
        payload.cards = cards.filter { !$0.value.isNew }
        payload.log = Array(log.suffix(maxLogEntries))
        payload.favorites = Array(favorites)
        payload.learnedGrammar = Array(learnedGrammar)
        return payload
    }

    /// 合并本地与云端：卡片按 lastReviewed 取新（同时间取 level 高的）；
    /// log 按 id 去重、按时间排、留 5,000 条；收藏与学会语法取并集。
    static func merge(local: CloudProgressPayload, cloud: CloudProgressPayload) -> CloudProgressPayload {
        var out = CloudProgressPayload()
        var cards = local.cards
        for (id, cloudState) in cloud.cards {
            if let localState = cards[id] {
                cards[id] = newer(localState, cloudState)
            } else {
                cards[id] = cloudState
            }
        }
        out.cards = cards

        var seenIDs = Set<UUID>()
        var mergedLog: [ReviewLogEntry] = []
        for entry in (local.log + cloud.log).sorted(by: { $0.at < $1.at }) {
            guard !seenIDs.contains(entry.id) else { continue }
            seenIDs.insert(entry.id)
            mergedLog.append(entry)
        }
        out.log = Array(mergedLog.suffix(maxStoredLogEntries))
        out.favorites = Array(Set(local.favorites).union(cloud.favorites))
        out.learnedGrammar = Array(Set(local.learnedGrammar).union(cloud.learnedGrammar))
        return out
    }

    /// 两张卡取较新的：lastReviewed 晚的赢；都没记录时取 level 高的。
    static func newer(_ a: SRSState, _ b: SRSState) -> SRSState {
        switch (a.lastReviewed, b.lastReviewed) {
        case let (x?, y?):
            if x != y { return x > y ? a : b }
            return a.level >= b.level ? a : b
        case (_?, nil):
            return a
        case (nil, _?):
            return b
        case (nil, nil):
            return a.level >= b.level ? a : b
        }
    }

    static func encode(_ payload: CloudProgressPayload) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    static func decode(_ data: Data) -> CloudProgressPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CloudProgressPayload.self, from: data)
    }
}

/// 登录 / 同步 / 组队的界面状态机：只管云端，不管词库。
///
/// 用法：RootView 里建一个，attach(store) 后把 token 恢复出来；
/// 地址没填（settings.cloudBaseURL 为空）时所有云功能都关着，
/// 只显示“未配置服务器”，不发任何请求。
@MainActor
final class CloudSync: ObservableObject {
    @Published private(set) var account: CloudAPI.CloudUser?
    @Published private(set) var team: CloudAPI.CloudTeam?
    @Published private(set) var members: [CloudAPI.TeamMember] = []
    @Published private(set) var teamHistory: [String] = []
    @Published private(set) var syncing = false
    @Published var syncStatus: String = ""

    weak var store: Store?

    private var autoSyncTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let lastCloudUpdatedAtKey = "cloud.lastCloudUpdatedAt"
    private static let cachedUserKey = "cloud.cachedUser"

    private var lastCloudUpdatedAt: Int {
        get { defaults.integer(forKey: Self.lastCloudUpdatedAtKey) }
        set { defaults.set(newValue, forKey: Self.lastCloudUpdatedAtKey) }
    }

    var isConfigured: Bool {
        guard let base = store?.settings.cloudBaseURL else { return false }
        return !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isLoggedIn: Bool { account != nil }

    private func makeAPI() -> CloudAPI? {
        guard let base = store?.settings.cloudBaseURL,
              !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CloudAPI(baseURL: base, token: KeychainHelper.readCloudToken())
    }

    // MARK: - 接入

    func attach(_ store: Store) {
        self.store = store
        if let data = defaults.data(forKey: Self.cachedUserKey),
           let user = try? JSONDecoder().decode(CloudAPI.CloudUser.self, from: data),
           KeychainHelper.readCloudToken() != nil {
            account = user
            startAutoSync()
            Task { await refreshTeamQuietly() }
        }
    }

    private func cacheUser(_ user: CloudAPI.CloudUser?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: Self.cachedUserKey)
        } else {
            defaults.removeObject(forKey: Self.cachedUserKey)
        }
    }

    // MARK: - 账号

    /// 发验证码。开发模式下服务端直接返回 devCode，调用方显示出来即可。
    func requestCode(phone: String) async throws -> String? {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        return try await api.requestCode(phone: phone)
    }

    func login(phone: String, code: String) async throws {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        let (token, user) = try await api.login(phone: phone, code: code)
        guard KeychainHelper.saveCloudToken(token) else {
            throw CloudAPI.Failure.network("token 存不进 Keychain")
        }
        account = user
        cacheUser(user)
        startAutoSync()
        await syncNow()
        await refreshTeamQuietly()
    }

    func logout() {
        stopAutoSync()
        KeychainHelper.deleteCloudToken()
        cacheUser(nil)
        account = nil
        team = nil
        members = []
        teamHistory = []
        syncStatus = ""
    }

    func rename(nickname: String) async throws {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        try await api.rename(nickname: nickname)
        if var user = account {
            user.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            account = user
            cacheUser(user)
        }
    }

    func refreshAccount() async {
        guard let api = makeAPI(), KeychainHelper.readCloudToken() != nil else { return }
        do {
            let user = try await api.me()
            account = user
            cacheUser(user)
        } catch {
            // 离线时不把已恢复的账号清掉，等下次再说。
        }
    }

    // MARK: - 同步

    /// 同步一次：先拉云端，云端比本地新就合并进来；否则把本地推上去。
    /// 冲突按卡片各自取新（见 CloudPayload.merge），不是整包覆盖。
    func syncNow() async {
        guard let store, let api = makeAPI(), account != nil else {
            if !isConfigured { syncStatus = "未配置云端服务器地址" }
            return
        }
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let snapshot = try await api.syncGet()
            if let data = snapshot.payload,
               let cloudPayload = CloudPayload.decode(data),
               snapshot.updatedAt > lastCloudUpdatedAt {
                let merged = CloudPayload.merge(local: store.cloudSnapshot(), cloud: cloudPayload)
                store.applyCloudSnapshot(merged)
                lastCloudUpdatedAt = snapshot.updatedAt
            }
            if let uploadData = CloudPayload.encode(store.cloudSnapshot()) {
                let updatedAt = try await api.syncPut(payload: uploadData)
                lastCloudUpdatedAt = updatedAt
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            syncStatus = "已同步 \(formatter.string(from: Date()))"
        } catch let failure as CloudAPI.Failure {
            if case .unauthorized = failure {
                logout()
                syncStatus = "登录已过期，请重新登录"
            } else {
                syncStatus = failure.localizedDescription
            }
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    private func startAutoSync() {
        stopAutoSync()
        autoSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await syncNow()
            }
        }
    }

    private func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - 组队

    func refreshTeam() async {
        guard let api = makeAPI(), account != nil else { return }
        do {
            let reply = try await api.teamGet()
            team = reply.team
            members = reply.members
        } catch {
            syncStatus = error.localizedDescription
        }
    }

    private func refreshTeamQuietly() async {
        guard let api = makeAPI(), account != nil else { return }
        if let reply = try? await api.teamGet() {
            team = reply.team
            members = reply.members
        }
    }

    func createTeam(name: String, days: Int, deposit: Int) async throws {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        team = try await api.teamCreate(name: name, days: days, deposit: deposit)
        await refreshTeam()
    }

    func joinTeam(code: String) async throws {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        team = try await api.teamJoin(code: code)
        await refreshTeam()
    }

    func leaveTeam() async throws {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        try await api.teamLeave()
        team = nil
        members = []
        teamHistory = []
    }

    /// 今日打卡。返回 true 表示今天已经打过（服务端去重）。
    @discardableResult
    func checkin() async throws -> Bool {
        guard let api = makeAPI() else { throw CloudAPI.Failure.notConfigured }
        let already = try await api.teamCheckin()
        await refreshTeam()
        return already
    }

    func loadHistory() async {
        guard let api = makeAPI(), account != nil else { return }
        teamHistory = (try? await api.teamHistory()) ?? []
    }
}
