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
    /// 当前词本 id，`all` 为全部
    var deckFilter: String = Deck.allID

    enum CodingKeys: String, CodingKey {
        case dailyGoal, reviewLimit, showRomaji, autoSpeak, speechRate, deckFilter
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 20
        reviewLimit = try c.decodeIfPresent(Int.self, forKey: .reviewLimit) ?? 60
        showRomaji = try c.decodeIfPresent(Bool.self, forKey: .showRomaji) ?? true
        autoSpeak = try c.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? false
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.45
        deckFilter = try c.decodeIfPresent(String.self, forKey: .deckFilter) ?? Deck.allID
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

    enum CodingKeys: String, CodingKey { case cards, settings, log, favorites }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cards = try c.decodeIfPresent([String: SRSState].self, forKey: .cards) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        log = try c.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var words: [Word] = []
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
        loadState()
        ensureCards()
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - 队列

    var totalCount: Int { words.count }

    // MARK: - 词本

    /// 当前词本范围内的词。
    var scopedWords: [Word] {
        let id = settings.deckFilter
        return id == Deck.allID ? words : words.filter { $0.jlpt == id }
    }

    var decks: [Deck] {
        let levels = ["N5", "N4", "N3", "N2", "N1"]
        let subtitles: [String: String] = [
            "N5": "入门核心词汇",
            "N4": "基础进阶词汇",
            "N3": "中级词汇",
            "N2": "高级词汇",
            "N1": "精通词汇"
        ]
        var result: [Deck] = [
            Deck(id: Deck.allID, title: "全部词本", subtitle: "N5 → N3 全部词条", badge: "全", words: words)
        ]
        for level in levels {
            let subset = words.filter { $0.jlpt == level }
            guard !subset.isEmpty else { continue }
            result.append(Deck(
                id: level,
                title: "JLPT \(level)",
                subtitle: subtitles[level] ?? "",
                badge: level,
                words: subset
            ))
        }
        return result
    }

    var currentDeckTitle: String {
        decks.first { $0.id == settings.deckFilter }?.title ?? "全部词本"
    }

    func selectDeck(_ deck: Deck) {
        settings.deckFilter = deck.id
        objectWillChange.send()
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
