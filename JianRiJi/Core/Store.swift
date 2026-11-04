import Foundation

/// 设置项。全部 Codable，方便直接落盘。
struct AppSettings: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case dailyGoal, reviewLimit, showRomaji, autoSpeak, speechRate, deckFilter
        case aiVendor, aiModel, aiBaseURL
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
    }
}

/// 一次评分记录。统计和热力图全靠它。
struct ReviewLogEntry: Codable, Identifiable, Hashable {
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
private struct PersistedState: Codable {
    var cards: [String: SRSState] = [:]
    var settings: AppSettings = AppSettings()
    var log: [ReviewLogEntry] = []
    var favorites: [String] = []
    var learnedGrammar: [String] = []

    enum CodingKeys: String, CodingKey { case cards, settings, log, favorites, learnedGrammar }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cards = try c.decodeIfPresent([String: SRSState].self, forKey: .cards) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        learnedGrammar = try c.decodeIfPresent([String].self, forKey: .learnedGrammar) ?? []
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var words: [Word] = []
    @Published private(set) var grammarPoints: [GrammarPoint] = []
    @Published private(set) var allBooks: [WordBook] = []
    @Published private(set) var learnedGrammar: Set<String> = []
    @Published private(set) var cards: [String: SRSState] = [:]
    @Published private(set) var log: [ReviewLogEntry] = []
    @Published private(set) var favorites: Set<String> = []

    @Published var settings: AppSettings = AppSettings() {
        didSet { schedulePersist() }
    }

    private var bootstrapped = false
    private var persistTask: DispatchWorkItem?
    private let calendar = Calendar.current

    // MARK: - 生命周期

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        words = Self.loadSeedWords()
        grammarPoints = Self.loadGrammarPoints()
        allBooks = Self.loadBooks()
        loadState()
        normalizeBook()
        ensureCards()
    }

    /// 旧存档的 deckFilter 可能是 JLPT 级别（如 N5），现在它是词书 id；
    /// 匹配不到任何词书时回到全部词本，并把修正后的值写回去。
    private func normalizeBook() {
        if allBooks.first(where: { $0.id == settings.deckFilter }) == nil {
            settings.deckFilter = WordBook.allID
        }
    }

    private static func loadSeedWords() -> [Word] {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "seed_words", withExtension: "json") else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Word].self, from: data)
        } catch {
            #if DEBUG
            print("[JianRiJi] seed_words.json 解析失败：\(error)")
            #endif
            return []
        }
    }

    private static func loadGrammarPoints() -> [GrammarPoint] {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "grammar_points", withExtension: "json") else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([GrammarPoint].self, from: data)
        } catch {
            #if DEBUG
            print("[JianRiJi] grammar_points.json 解析失败：\(error)")
            #endif
            return []
        }
    }

    private static func loadBooks() -> [WordBook] {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "books", withExtension: "json") else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([WordBook].self, from: data)
        } catch {
            #if DEBUG
            print("[JianRiJi] books.json 解析失败：\(error)")
            #endif
            return []
        }
    }

    /// 词库里每个词都保证有状态；缺的补成「新词，立刻到期」。
    private func ensureCards() {
        for word in words where cards[word.id] == nil {
            cards[word.id] = SRSState(level: 0, ease: 2.5, due: Date())
        }
    }

    private var stateURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("JianRiJi", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("state.json")
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(PersistedState.self, from: data) else { return }
        cards = snapshot.cards
        settings = snapshot.settings
        log = snapshot.log
        favorites = Set(snapshot.favorites)
        learnedGrammar = Set(snapshot.learnedGrammar)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.persist() }
        }
        persistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func persist() {
        var snapshot = PersistedState()
        snapshot.cards = cards
        snapshot.settings = settings
        snapshot.log = log
        snapshot.favorites = Array(favorites)
        snapshot.learnedGrammar = Array(learnedGrammar)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: stateURL, options: .atomic)
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
        switch book.filterType {
        case "learned":
            return words.filter { word in
                guard let state = cards[word.id] else { return false }
                return !state.isNew
            }
        case "favorite":
            return words.filter { favorites.contains($0.id) }
        default:
            return words.filter { book.matches($0) }
        }
    }

    func wordCount(in book: WordBook) -> Int {
        words(in: book).count
    }

    /// 这本词书里已经开始的词（不是新词）有多少。
    func learnedCount(in book: WordBook) -> Int {
        words(in: book).filter { word in
            guard let state = cards[word.id] else { return false }
            return !state.isNew
        }.count
    }

    func selectBook(_ book: WordBook) {
        settings.deckFilter = book.id
        objectWillChange.send()
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
        persist()
    }

    func learnedGrammarCount(forLevel level: String) -> Int {
        grammarPoints(forLevel: level).filter { learnedGrammar.contains($0.id) }.count
    }

    /// 到期且不是新词的卡片，按到期时间排。
    var dueReviews: [Word] {
        let now = Date()
        return scopedWords
            .filter { word in
                guard let s = cards[word.id] else { return false }
                return !s.isNew && s.due <= now
            }
            .sorted { lhs, rhs in
                (cards[lhs.id]?.due ?? now) < (cards[rhs.id]?.due ?? now)
            }
    }

    var freshWords: [Word] {
        scopedWords.filter { cards[$0.id]?.isNew ?? false }
    }

    var todayStart: Date { calendar.startOfDay(for: Date()) }

    var newIntroducedToday: Int {
        log.filter { $0.wasNew && $0.at >= todayStart }.count
    }

    var newAllowance: Int {
        max(0, settings.dailyGoal - newIntroducedToday)
    }

    var reviewedToday: Int {
        log.filter { $0.at >= todayStart }.count
    }

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

    func grade(word: Word, grade: ReviewGrade) {
        var state = cards[word.id] ?? SRSState()
        let wasNew = state.isNew
        state = SRS.next(state, grade: grade, now: Date())
        cards[word.id] = state
        log.append(ReviewLogEntry(wordID: word.id, gradeRaw: grade.rawValue, wasNew: wasNew))
        if log.count > 5_000 {
            log.removeFirst(log.count - 5_000)
        }
        persist()
    }

    func card(for word: Word) -> SRSState {
        cards[word.id] ?? SRSState()
    }

    func resetCard(for word: Word) {
        cards[word.id] = SRSState()
        persist()
    }

    func resetAllProgress() {
        cards.removeAll()
        log.removeAll()
        favorites.removeAll()
        ensureCards()
        persist()
    }

    // MARK: - 收藏

    func isFavorite(_ word: Word) -> Bool { favorites.contains(word.id) }

    func toggleFavorite(_ word: Word) {
        if favorites.contains(word.id) {
            favorites.remove(word.id)
        } else {
            favorites.insert(word.id)
        }
        persist()
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
        words.first { $0.id == id }
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
            let count = log.filter { $0.at >= day && $0.at < end }.count
            return DayCount(day: day, count: count)
        }
    }

    /// 正确率 0...1，没有记录时返回 nil
    var accuracy: Double? {
        guard !log.isEmpty else { return nil }
        let correct = log.filter { $0.gradeRaw >= ReviewGrade.good.rawValue }.count
        return Double(correct) / Double(log.count)
    }
}
