import Foundation
import OSLog

/// 文件级日志器。
///
/// 不能写成 `@MainActor` 类里的 `private static let`：`nonisolated` 的资源加载函数
/// 访问不到被 actor 隔离的静态属性，编译期直接报错。
private enum StoreLog {
    static let store = Logger(subsystem: "com.lpdada.jianriji", category: "store")
    static let persistence = Logger(subsystem: "com.lpdada.jianriji", category: "persistence")
}

// MARK: - Schema

/// 存档 schema 版本。
///
/// 任何影响 `PersistedState` / `AppSettings` / `SRSState` 结构的改动都要 +1，
/// 并在 `StateFile.decode` 之后补一段迁移；否则老用户升级后进度会整段丢。
///
/// - v1：无 schemaVersion，卡片全量落盘，朗读地址默认指向第三方服务器。
/// - v2：只落「动过」的卡；ttsServerURL 默认空（纯本地）；SRSState 增加
///   intervalDays / lapses；卡片带 fuzz。
enum StateSchema {
    static let current = 2
}

/// 老版本里写死的默认值。迁移时用来识别「用户从未主动改过」，从而安全清空。
enum LegacyDefaults {
    static let thirdPartyTTS = "https://asr.ysloving.com"
}

// MARK: - 设置

/// 设置项。全部 Codable，方便直接落盘。
struct AppSettings: Codable, Equatable, Sendable {
    /// 每天最多引入多少新词
    var dailyGoal: Int = 20
    /// 单轮复习上限
    var reviewLimit: Int = 60
    /// 卡片上是否显示罗马字
    var showRomaji: Bool = true
    /// 卡片翻面时自动朗读
    var autoSpeak: Bool = false
    /// 朗读速度，0.3 ~ 0.6
    var speechRate: Double = 0.45
    /// 当前词书 id（books.json 的 id），`all` 为全部。
    /// 旧存档里可能是 JLPT 级别（如 N5），启动时匹配不到词书会归到全部。
    var deckFilter: String = WordBook.allID
    /// AI 厂商；Key 本身不放这里，存在 Keychain 里，按厂商分条目。
    var aiVendor: AIVendor = .opencodeGo
    /// AI 模型，空 = 用厂商默认值
    var aiModel: String = ""
    /// AI 接口地址，空 = 用厂商默认值；自定义厂商必须填
    var aiBaseURL: String = ""
    /// 朗读服务器地址。
    ///
    /// **默认空字符串 = 纯本地合成，不把任何学习内容发到网络。**
    /// v1 曾默认指向作者自建的第三方代理，等于用户一朗读就向第三方上传例句；
    /// v2 起改为显式填地址才启用，由设置页在填写前展示隐私说明。
    var ttsServerURL: String = ""
    /// 间隔模糊：同一批词不会挤在同一天到期（原实现没有，批量导入后会出现「复习雪崩」）。
    var reviewFuzz: Bool = true

    enum CodingKeys: String, CodingKey {
        case dailyGoal, reviewLimit, showRomaji, autoSpeak, speechRate, deckFilter
        case aiVendor, aiModel, aiBaseURL, ttsServerURL, reviewFuzz
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 20
        reviewLimit = try c.decodeIfPresent(Int.self, forKey: .reviewLimit) ?? 60
        showRomaji = try c.decodeIfPresent(Bool.self, forKey: .showRomaji) ?? true
        autoSpeak = try c.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? false
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.45
        deckFilter = try c.decodeIfPresent(String.self, forKey: .deckFilter) ?? WordBook.allID
        aiVendor = try c.decodeIfPresent(AIVendor.self, forKey: .aiVendor) ?? .opencodeGo
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? ""
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? ""
        reviewFuzz = try c.decodeIfPresent(Bool.self, forKey: .reviewFuzz) ?? true

        // v1 → v2 迁移：曾经默认写死的第三方朗读地址，用户没主动改过的一律清空，
        // 保证「升级不会偷偷开始联网」。
        switch try c.decodeIfPresent(String.self, forKey: .ttsServerURL) {
        case LegacyDefaults.thirdPartyTTS:
            ttsServerURL = ""
        case let saved?:
            ttsServerURL = saved
        case nil:
            ttsServerURL = ""
        }
    }
}

// MARK: - 记录

/// 一次评分记录。统计和热力图全靠它。
struct ReviewLogEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var wordID: String
    var gradeRaw: Int
    /// 评这次分之前是不是新词（用来算「今天引入了多少新词」）
    var wasNew: Bool
    var at: Date = Date()

    var grade: ReviewGrade { ReviewGrade(rawValue: gradeRaw) ?? .good }
}

struct DayCount: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    let count: Int
}

/// 落盘用的整体快照。
struct PersistedState: Codable, Sendable {
    var schemaVersion: Int = StateSchema.current
    var cards: [String: SRSState] = [:]
    var settings: AppSettings = AppSettings()
    var log: [ReviewLogEntry] = []
    var favorites: [String] = []
    var learnedGrammar: [String] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion, cards, settings, log, favorites, learnedGrammar
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 缺键的老存档按 v1 处理。
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        cards = try c.decodeIfPresent([String: SRSState].self, forKey: .cards) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        learnedGrammar = try c.decodeIfPresent([String].self, forKey: .learnedGrammar) ?? []
    }
}

// MARK: - 磁盘

/// 存档读写：原子写、备份轮转、损坏现场留档。
/// 只处理 `Data`，不碰 Store 的 `@Published`，所以可以安全地在后台线程调用。
enum StateFile {
    static let fileName = "state.json"
    static let backupName = "state.bak.json"
    /// 损坏现场最多留几份，避免坏文件把用户磁盘占满。
    static let maxQuarantineCopies = 3

    struct Loaded {
        enum Source: String { case main, backup }
        let state: PersistedState
        let source: Source
    }

    enum LoadResult {
        case success(Loaded)
        /// 首次安装，没有存档。
        case empty
        /// 存档存在但读不出来，且备份也不可用：**不要用空状态覆盖它**。
        case failed(String)
    }

    static func directory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("JianRiJi", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func mainURL() -> URL { directory().appendingPathComponent(fileName) }
    static func backupURL() -> URL { directory().appendingPathComponent(backupName) }

    static func decode(_ data: Data) throws -> PersistedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedState.self, from: data)
    }

    static func encode(_ state: PersistedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // 不转义斜杠，存档里带 URL 时可读且更小。
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    static func load() -> LoadResult {
        let fm = FileManager.default
        let main = mainURL()
        guard fm.fileExists(atPath: main.path) else { return .empty }

        do {
            let data = try Data(contentsOf: main)
            return .success(Loaded(state: try decode(data), source: .main))
        } catch let primaryError {
            // 主文件坏了：先留现场，再试上一份备份。
            quarantine(main)
            if let data = try? Data(contentsOf: backupURL()),
               let state = try? decode(data) {
                return .success(Loaded(state: state, source: .backup))
            }
            return .failed(String(describing: primaryError))
        }
    }

    /// 把坏文件挪到 state.corrupt-<时间戳>.json，不直接删——里面可能有用户几个月的进度。
    private static func quarantine(_ url: URL) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("state.corrupt-\(stamp).json")
        try? fm.moveItem(at: url, to: dest)
        pruneQuarantine()
    }

    private static func pruneQuarantine() {
        let fm = FileManager.default
        let dir = directory()
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let corrupt = names
            .filter { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".json") }
            .sorted()
        guard corrupt.count > maxQuarantineCopies else { return }
        for name in corrupt.prefix(corrupt.count - maxQuarantineCopies) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}

/// 串行化落盘。
///
/// 原实现的 `persist()` 在 `@MainActor` 上同步 encode + write 整份存档（含全部卡）；
/// 这里拆成「主线程 encode（几毫秒）+ 后台 actor 写盘（I/O）」，并用 `lastWritten`
/// 去重，避免同一份内容反复刷盘。
actor StateWriter {
    private let main: URL
    private let backup: URL
    private var lastWritten: Data?

    init(main: URL = StateFile.mainURL(), backup: URL = StateFile.backupURL()) {
        self.main = main
        self.backup = backup
    }

    /// 写失败只记日志，不向上抛：UI 不应因为磁盘满而崩。
    func write(_ data: Data) {
        guard data != lastWritten else { return }
        let fm = FileManager.default
        do {
            // 上一份好的先转成备份，再原子写新的。顺序反了会在崩溃时两份都坏。
            if fm.fileExists(atPath: main.path) {
                try? fm.removeItem(at: backup)
                try? fm.copyItem(at: main, to: backup)
            }
            try data.write(to: main, options: .atomic)
            lastWritten = data
        } catch {
            StoreLog.persistence.error("写存档失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 测试与「重置进度」用：清掉去重缓存，强制下一份一定落盘。
    func invalidateCache() {
        lastWritten = nil
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    /// 评分日志上限。超过后批量裁剪，而不是每次只丢一条（原来每次评分都要 memmove 整表）。
    private static let maxLogEntries = 5_000
    private static let logTrimBatch = 500

    @Published private(set) var words: [Word] = []
    @Published private(set) var grammarPoints: [GrammarPoint] = []
    @Published private(set) var allBooks: [WordBook] = []
    @Published private(set) var learnedGrammar: Set<String> = []
    @Published private(set) var cards: [String: SRSState] = [:]
    @Published private(set) var log: [ReviewLogEntry] = []
    @Published private(set) var favorites: Set<String> = []

    /// 词库与存档是否都就位。首帧之前 UI 应显示加载态，而不是「0 个词」。
    @Published private(set) var isReady = false

    @Published var settings: AppSettings = AppSettings() {
        didSet {
            guard oldValue != settings else { return }
            schedulePersist(delay: 0.6)
            // 朗读地址是 AppSettings 的唯一来源，同步给 Speech 用。
            Speech.shared.serverBaseURL = settings.ttsServerURL
        }
    }

    // MARK: 内部状态

    private let writer: StateWriter
    private let calendar = Calendar.current

    private var bootstrapped = false
    private var loadTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    /// 存档损坏且无法恢复时为 true：此时**拒绝任何写入**，避免把坏档覆盖成空档。
    private var recoveryFailed = false

    // 缓存：SwiftUI body 会高频读取这些派生值，原实现每次都遍历 10660 条词。
    private var wordsByID: [String: Word] = [:]
    private var bookStatsCache: [String: BookStats] = [:]
    private var scopeCache: (bookID: String, words: [Word])?
    private var freshCache: (cardsVersion: Int, bookID: String, words: [Word])?
    private var dueCache: (cardsVersion: Int, bookID: String, tick: Int, words: [Word])?
    private var todayCache: (logVersion: Int, day: Date, introduced: Int, reviewed: Int)?

    private var cardsVersion = 0
    private var logVersion = 0

    private struct BookStats {
        let total: Int
        let learned: Int
    }

    init(writer: StateWriter = StateWriter()) {
        self.writer = writer
    }

    // MARK: - 生命周期

    /// 启动加载。
    ///
    /// 三个 JSON 里 `seed_words.json` 有 3.9 MB：**必须离开主线程解析**，
    /// 否则冷启动会白屏几百毫秒到一秒（原实现在 `@MainActor` 上同步 `Data(contentsOf:)`）。
    /// 只有 3.6 KB 的 `books.json` 留在主线程，保证首帧就有词书骨架。
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        allBooks = Self.loadResource([WordBook].self, name: "books") ?? []

        loadTask = Task { [weak self] in
            async let loadedWords = Self.loadResourceOffMain([Word].self, name: "seed_words")
            async let loadedGrammar = Self.loadResourceOffMain([GrammarPoint].self, name: "grammar_points")
            let (words, grammar) = await (loadedWords, loadedGrammar)
            guard let self else { return }

            self.words = words ?? []
            self.grammarPoints = grammar ?? []
            self.rebuildIndexes()
            self.loadState()
            self.normalizeBook()
            self.ensureCards()
            self.invalidateAllCaches()
            self.isReady = true
            self.objectWillChange.send()
        }
    }

    /// 离开页面 / 进后台时调用，保证未落盘的评分不丢。
    func flush() {
        persistNow()
    }

    nonisolated private static func loadResource<T: Decodable & Sendable>(
        _ type: T.Type,
        name: String
    ) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            StoreLog.store.fault("资源缺失：\(name, privacy: .public).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            StoreLog.store.fault("资源解析失败 \(name, privacy: .public).json：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated private static func loadResourceOffMain<T: Decodable & Sendable>(
        _ type: T.Type,
        name: String
    ) async -> T? {
        await Task.detached(priority: .userInitiated) {
            loadResource(type, name: name)
        }.value
    }

    /// 旧存档的 deckFilter 可能是 JLPT 级别（如 N5），现在它是词书 id；
    /// 匹配不到任何词书时回到全部词本，并把修正后的值写回去。
    private func normalizeBook() {
        guard !allBooks.isEmpty else { return }
        if allBooks.first(where: { $0.id == settings.deckFilter }) == nil {
            settings.deckFilter = WordBook.allID
        }
    }

    /// 词库里每个词都保证有状态；缺的补成「新词，立刻到期」。
    private func ensureCards() {
        guard !words.isEmpty else { return }
        for word in words where cards[word.id] == nil {
            cards[word.id] = SRSState(level: 0, ease: 2.5, due: Date())
        }
    }

    private func rebuildIndexes() {
        // 词库理论上 id 唯一，但导入工具出错时不能因此崩在启动路径上。
        wordsByID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func loadState() {
        switch StateFile.load() {
        case .success(let loaded):
            cards = loaded.state.cards
            settings = loaded.state.settings
            log = loaded.state.log
            favorites = Set(loaded.state.favorites)
            learnedGrammar = Set(loaded.state.learnedGrammar)
            if loaded.source == .backup {
                StoreLog.store.warning("主存档损坏，已从备份恢复 \(loaded.state.log.count) 条评分记录")
                // 恢复出来的内容立刻写回主文件，避免下次又走备份路径。
                persistNow()
            }

        case .empty:
            break

        case .failed(let reason):
            // 存档存在但读不出来：保持空状态，但**禁止写入**，
            // 避免用户下一次评分就把几个月进度覆盖掉。
            recoveryFailed = true
            StoreLog.store.error("存档读取失败，已冻结写入：\(reason, privacy: .public)")
        }
    }

    // MARK: - 落盘

    private func schedulePersist(delay: TimeInterval) {
        guard isReady, !recoveryFailed else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persist() {
        persistNow()
    }

    private func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard isReady, !recoveryFailed else { return }

        var snapshot = PersistedState()
        snapshot.schemaVersion = StateSchema.current
        // 关键：只落「动过」的卡。原实现把 10660 个新词的默认状态全部写盘，
        // 存档常年几 MB，每评一次分就整份重写一遍。
        snapshot.cards = cards.filter { !$0.value.isUntouched }
        snapshot.settings = settings
        snapshot.log = log
        snapshot.favorites = Array(favorites)
        snapshot.learnedGrammar = Array(learnedGrammar)

        guard let data = try? StateFile.encode(snapshot) else {
            StoreLog.store.error("存档编码失败，本次未落盘")
            return
        }
        // encode 在主线程（无 I/O，毫秒级），write 交给 actor 串行后台执行。
        Task { await writer.write(data) }
    }

    private func trimLogIfNeeded() {
        guard log.count > Self.maxLogEntries else { return }
        // 批量裁剪：每次只丢一条会导致每次评分都 memmove 整表。
        log.removeFirst(log.count - Self.maxLogEntries + Self.logTrimBatch)
    }

    // MARK: - 缓存失效

    private func invalidateAllCaches() {
        bookStatsCache.removeAll(keepingCapacity: true)
        scopeCache = nil
        freshCache = nil
        dueCache = nil
        todayCache = nil
    }

    /// `scope: true` 只用于「词书范围本身变了」（切词书、收藏、词库重载）。
    /// 单纯的评分不改变范围，没必要连 scopeCache 一起丢。
    private func invalidateCaches(scope: Bool) {
        bookStatsCache.removeAll(keepingCapacity: true)
        freshCache = nil
        dueCache = nil
        todayCache = nil
        if scope { scopeCache = nil }
    }

    // MARK: - 队列

    var totalCount: Int { words.count }

    // MARK: - 词书

    /// 当前词书范围内的词。切换词书后这里立刻变，复习队列跟着变，不用重开页面。
    var scopedWords: [Word] {
        words(in: currentBook)
    }

    var books: [WordBook] { allBooks }

    var currentBook: WordBook {
        allBooks.first { $0.id == settings.deckFilter } ?? allBooks.first ?? fallbackBook
    }

    var currentBookTitle: String { currentBook.title }

    func words(in book: WordBook) -> [Word] {
        if let cache = scopeCache, cache.bookID == book.id { return cache.words }
        let result: [Word]
        switch book.filterType {
        case "learned":
            result = words.filter { cards[$0.id]?.isNew == false }
        case "favorite":
            result = words.filter { favorites.contains($0.id) }
        default:
            result = words.filter { book.matches($0) }
        }
        scopeCache = (book.id, result)
        return result
    }

    /// 一本词书的「总数 / 已开始」一次算完并缓存。
    /// 首页 Hero 卡与词本列表原来每帧对 13 本书各扫一遍 10660 条词。
    private func stats(in book: WordBook) -> BookStats {
        if let cached = bookStatsCache[book.id] { return cached }
        let scoped = words(in: book)
        var learned = 0
        for word in scoped where cards[word.id]?.isNew == false {
            learned += 1
        }
        let stats = BookStats(total: scoped.count, learned: learned)
        bookStatsCache[book.id] = stats
        return stats
    }

    func wordCount(in book: WordBook) -> Int { stats(in: book).total }

    /// 这本词书里已经开始的词（不是新词）有多少。
    func learnedCount(in book: WordBook) -> Int { stats(in: book).learned }

    func selectBook(_ book: WordBook) {
        guard settings.deckFilter != book.id else { return }
        settings.deckFilter = book.id
        scopeCache = nil
        invalidateCaches(scope: true)
    }

    /// books.json 读不到时的保底：只有全部词本。
    private var fallbackBook: WordBook {
        WordBook(
            id: WordBook.allID,
            title: "全部词本",
            badge: "全",
            categories: ["常用词单"],
            author: "简日记",
            note: "全部词条",
            filterType: "all",
            filterValue: nil,
            tint: 0
        )
    }

    // MARK: - 语法

    func grammarPoints(forLevel level: String) -> [GrammarPoint] {
        level == "全部" ? grammarPoints : grammarPoints.filter { $0.level == level }
    }

    func grammarSearch(_ query: String, level: String) -> [GrammarPoint] {
        let base = grammarPoints(forLevel: level)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { $0.matches(query: q) }
    }

    func isGrammarLearned(_ point: GrammarPoint) -> Bool {
        learnedGrammar.contains(point.id)
    }

    /// 重复点也不会重复计数：学会状态存在 Set 里。
    func markGrammarLearned(_ point: GrammarPoint) {
        guard !learnedGrammar.contains(point.id) else { return }
        learnedGrammar.insert(point.id)
        persistNow()
    }

    func learnedGrammarCount(forLevel level: String) -> Int {
        grammarPoints(forLevel: level).filter { learnedGrammar.contains($0.id) }.count
    }

    // MARK: - 到期与队列

    /// 到期且不是新词的卡片，按到期时间排。
    /// 30 秒一个时间桶：时间在走，但没必要每帧重排一次。
    var dueReviews: [Word] {
        let book = currentBook
        let tick = Int(Date().timeIntervalSince1970 / 30)
        if let cache = dueCache,
           cache.cardsVersion == cardsVersion,
           cache.bookID == book.id,
           cache.tick == tick {
            return cache.words
        }
        let now = Date()
        let result = words(in: book)
            .filter { word in
                guard let state = cards[word.id] else { return false }
                return !state.isNew && state.due <= now
            }
            .sorted { lhs, rhs in
                (cards[lhs.id]?.due ?? now) < (cards[rhs.id]?.due ?? now)
            }
        dueCache = (cardsVersion, book.id, tick, result)
        return result
    }

    var freshWords: [Word] {
        let book = currentBook
        if let cache = freshCache, cache.cardsVersion == cardsVersion, cache.bookID == book.id {
            return cache.words
        }
        let result = words(in: book).filter { cards[$0.id]?.isNew ?? false }
        freshCache = (cardsVersion, book.id, result)
        return result
    }

    var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// 今天的「新词引入数 / 总复习数」一次算完，避免 body 里各调一次各扫一遍日志。
    private func todayStats() -> (introduced: Int, reviewed: Int) {
        let day = todayStart
        if let cache = todayCache, cache.logVersion == logVersion, cache.day == day {
            return (cache.introduced, cache.reviewed)
        }
        var introduced = 0
        var reviewed = 0
        for entry in log where entry.at >= day {
            reviewed += 1
            if entry.wasNew { introduced += 1 }
        }
        todayCache = (logVersion, day, introduced, reviewed)
        return (introduced, reviewed)
    }

    var newIntroducedToday: Int { todayStats().introduced }

    var newAllowance: Int {
        max(0, settings.dailyGoal - newIntroducedToday)
    }

    var reviewedToday: Int { todayStats().reviewed }

    var remainingDueCount: Int { dueReviews.count }

    var masteredCount: Int {
        cards.values.filter { $0.isMastered }.count
    }

    var learningCount: Int {
        cards.values.filter { !$0.isNew && !$0.isMastered }.count
    }

    /// 今日进度 0...1：已复习 /（已复习 + 剩余）
    var todayProgress: Double {
        let done = reviewedToday
        let total = done + remainingDueCount + min(newAllowance, freshWords.count)
        guard total > 0 else { return done > 0 ? 1 : 0 }
        return min(1, Double(done) / Double(total))
    }

    /// 一轮的题：先到期复习，再补新词。
    func sessionQueue() -> [Word] {
        var queue = Array(dueReviews.prefix(settings.reviewLimit))
        let room = max(0, settings.reviewLimit - queue.count)
        if room > 0 {
            queue.append(contentsOf: freshWords.prefix(min(room, newAllowance)))
        }
        return queue
    }

    // MARK: - 评分

    /// 一次评分前的现场。误点「很熟」时用来回滚。
    private struct GradeUndo {
        let wordID: String
        /// nil 表示评分前这张卡还不存在（撤销时应当删掉）。
        let previous: SRSState?
    }

    /// 撤销栈上限。够把一串误点救回来，又不会无限占内存。
    private static let maxUndoSteps = 20

    private var undoStack: [GradeUndo] = []

    /// 界面上「撤销」按钮的显隐读它。
    var canUndoGrade: Bool { !undoStack.isEmpty }

    func grade(word: Word, grade: ReviewGrade) {
        let previous = cards[word.id]
        var state = previous ?? SRSState()
        let wasNew = state.isNew
        state = SRS.next(
            state,
            grade: grade,
            now: Date(),
            fuzz: settings.reviewFuzz,
            seed: SRS.stableSeed(word.id)
        )
        cards[word.id] = state
        log.append(ReviewLogEntry(wordID: word.id, gradeRaw: grade.rawValue, wasNew: wasNew))
        trimLogIfNeeded()

        undoStack.append(GradeUndo(wordID: word.id, previous: previous))
        if undoStack.count > Self.maxUndoSteps {
            undoStack.removeFirst(undoStack.count - Self.maxUndoSteps)
        }

        cardsVersion &+= 1
        logVersion &+= 1
        invalidateCaches(scope: false)
        // 连续评分合并成一次落盘，而不是每点一下写一遍整份存档。
        schedulePersist(delay: 1.2)
    }

    /// 撤销上一次评分：恢复卡片状态，并把那条日志摘掉。
    /// 返回 false 表示没有可撤销的记录。
    @discardableResult
    func undoLastGrade() -> Bool {
        guard let undo = undoStack.popLast() else { return false }
        if let previous = undo.previous {
            cards[undo.wordID] = previous
        } else {
            cards.removeValue(forKey: undo.wordID)
        }
        // 只摘掉「确实属于这次评分」的那条，避免日志被裁剪过之后误删。
        if log.last?.wordID == undo.wordID {
            log.removeLast()
        }
        cardsVersion &+= 1
        logVersion &+= 1
        invalidateCaches(scope: false)
        persistNow()
        return true
    }

    func card(for word: Word) -> SRSState {
        cards[word.id] ?? SRSState()
    }

    func resetCard(for word: Word) {
        cards[word.id] = SRSState()
        // 手动重置后，撤销栈里的快照已经和当前状态对不上，清掉。
        undoStack.removeAll()
        cardsVersion &+= 1
        invalidateCaches(scope: false)
        persistNow()
    }

    func resetAllProgress() {
        cards.removeAll()
        log.removeAll()
        favorites.removeAll()
        undoStack.removeAll()
        ensureCards()
        cardsVersion &+= 1
        logVersion &+= 1
        invalidateAllCaches()
        persistNow()
    }

    // MARK: - 收藏

    func isFavorite(_ word: Word) -> Bool { favorites.contains(word.id) }

    func toggleFavorite(_ word: Word) {
        if favorites.contains(word.id) {
            favorites.remove(word.id)
        } else {
            favorites.insert(word.id)
        }
        invalidateCaches(scope: true)
        persistNow()
    }

    var favoriteWords: [Word] {
        words.filter { favorites.contains($0.id) }
    }

    // MARK: - 检索

    func search(_ query: String) -> [Word] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let lowered = raw.lowercased()
        let squashed = lowered.replacingOccurrences(of: " ", with: "")
        return words.filter { word in
            word.term.contains(raw)
                || word.reading.contains(raw)
                || word.meaning.contains(raw)
                || word.romaji.lowercased().contains(squashed)
        }
    }

    func word(withID id: String) -> Word? {
        if let hit = wordsByID[id] { return hit }
        // 索引未建好（或词库刚重载）时回落到线性查找，但不再每帧都走这条路。
        return words.first { $0.id == id }
    }

    // MARK: - 统计

    var streak: Int {
        var days = Set(log.map { calendar.startOfDay(for: $0.at) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            days.remove(cursor)
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    var weekCounts: [DayCount] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let count = log.reduce(0) { total, entry in
                total + ((entry.at >= day && entry.at < end) ? 1 : 0)
            }
            return DayCount(day: day, count: count)
        }
    }

    /// 正确率 0...1，没有记录时返回 nil
    var accuracy: Double? {
        guard !log.isEmpty else { return nil }
        let correct = log.reduce(0) { $0 + ($1.gradeRaw >= ReviewGrade.good.rawValue ? 1 : 0) }
        return Double(correct) / Double(log.count)
    }
}
