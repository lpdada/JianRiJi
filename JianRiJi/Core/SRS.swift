import Foundation

/// 单张卡片的四档评分。与 Anki 的 Again/Hard/Good/Easy 同构，不抄代码，只借用这套被验证过的手感。
enum ReviewGrade: Int, Codable, CaseIterable, Identifiable, Sendable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "忘了"
        case .hard: return "模糊"
        case .good: return "记得"
        case .easy: return "很熟"
        }
    }

    var subtitle: String {
        switch self {
        case .again: return "10 分钟后再来"
        case .hard: return "间隔减半"
        case .good: return "按台阶往前走"
        case .easy: return "跳两级"
        }
    }
}

/// 一张卡的记忆状态。
///
/// v2 起手写 `init(from:)`：Swift 合成的 Decodable **不会**给缺失的键用属性默认值，
/// 直接加字段会让 v1 存档整份解码失败。所有新字段一律 `decodeIfPresent`。
struct SRSState: Codable, Hashable, Sendable {
    /// 记忆台阶：0 = 新词，9 = 台阶顶端
    var level: Int
    /// 难度系数，越小越难
    var ease: Double
    /// 下次到期时间
    var due: Date
    var correct: Int
    var wrong: Int
    var lastReviewed: Date?
    /// 当前实际间隔（天）。v2 新增：台阶到顶后靠它继续拉长，避免永远停在 240 天。
    /// nil 表示这是 v1 存档，读取时由 `level` 反推。
    var intervalDays: Double?
    /// 「忘了」的累计次数，用于识别 leech（反复记不住的词）。
    var lapses: Int

    init(
        level: Int = 0,
        ease: Double = 2.5,
        due: Date = Date(),
        correct: Int = 0,
        wrong: Int = 0,
        lastReviewed: Date? = nil,
        intervalDays: Double? = nil,
        lapses: Int = 0
    ) {
        self.level = level
        self.ease = ease
        self.due = due
        self.correct = correct
        self.wrong = wrong
        self.lastReviewed = lastReviewed
        self.intervalDays = intervalDays
        self.lapses = lapses
    }

    enum CodingKeys: String, CodingKey {
        case level, ease, due, correct, wrong, lastReviewed, intervalDays, lapses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        ease = try c.decodeIfPresent(Double.self, forKey: .ease) ?? 2.5
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? Date()
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        wrong = try c.decodeIfPresent(Int.self, forKey: .wrong) ?? 0
        lastReviewed = try c.decodeIfPresent(Date.self, forKey: .lastReviewed)
        intervalDays = try c.decodeIfPresent(Double.self, forKey: .intervalDays)
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(level, forKey: .level)
        try c.encode(ease, forKey: .ease)
        try c.encode(due, forKey: .due)
        try c.encode(correct, forKey: .correct)
        try c.encode(wrong, forKey: .wrong)
        try c.encodeIfPresent(lastReviewed, forKey: .lastReviewed)
        try c.encodeIfPresent(intervalDays, forKey: .intervalDays)
        try c.encode(lapses, forKey: .lapses)
    }

    /// 从没学过
    var isNew: Bool { level == 0 && lastReviewed == nil }

    /// 一个字节都没动过。存档只落「动过」的卡，这让存档从数 MB 降到几十 KB。
    var isUntouched: Bool {
        level == 0 && lastReviewed == nil && correct == 0 && wrong == 0 && lapses == 0
    }

    /// 反复记不住（Anki 的 leech 阈值是 8 次 lapse）。UI 可据此提示「换个记法 / 拆词」。
    var isLeech: Bool { lapses >= SRS.leechThreshold }

    /// 0...1 的掌握度
    var mastery: Double {
        Double(level) / Double(max(1, SRS.ladders.count - 1))
    }

    /// 已掌握：只剩最后一两级没走完
    var isMastered: Bool { level >= SRS.ladders.count - 2 }

    /// 真实间隔（天）。v1 存档没有这个字段时按台阶反推。
    var effectiveIntervalDays: Double {
        intervalDays ?? SRS.intervalDays(level: level, ease: ease)
    }
}

/// 艾宾浩斯式台阶。单位是「天」，第一格用分钟级重来。
enum SRS {
    static let ladders: [Double] = [0, 1, 2, 4, 7, 15, 30, 60, 120, 240]

    /// 新词答错后的重来间隔：10 分钟
    static let relearnInterval: TimeInterval = 10 * 60

    /// 单张卡最大间隔：5 年。到顶后不再无限增长，但也不卡死在台阶顶端。
    static let maxIntervalDays: Double = 1_825

    /// 连续「忘了」多少次算 leech。
    static let leechThreshold = 8

    /// 某台阶对应的间隔（天），带 ease 修正。
    static func intervalDays(level: Int, ease: Double) -> Double {
        intervalDays(level: level, ease: ease, previous: nil)
    }

    /// 带「上一次间隔」的版本：台阶到顶后按上一次 ×1.3 继续拉长。
    ///
    /// 原实现在 level 到 9 之后 `min(count-1, level+1)` 永远返回 9，
    /// 间隔固定 240 天 —— 学满的词永远「到期—复习—再 240 天」，
    /// 曲线在顶端是断的，这不是记忆曲线该有的形状。
    static func intervalDays(level: Int, ease: Double, previous: Double?) -> Double {
        guard level > 0 else { return relearnInterval / 86_400 }
        let capped = min(level, ladders.count - 1)
        let base = ladders[capped]
        let factor = 1 + (ease - 2.5) * 0.2
        var days = max(0.007, base * factor)
        if level >= ladders.count - 1, let previous, previous > 0 {
            days = max(days, previous * 1.3)
        }
        return min(days, maxIntervalDays)
    }

    /// 稳定哈希（FNV-1a）。不能用 `String.hashValue`：Swift 每个进程的 hash seed 随机，
    /// 单测会时好时坏。
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 0.95 ... 1.05 的确定性抖动。
    ///
    /// 没有这个的话，同一天批量导入的一批词会拿到完全相同的间隔，
    /// 从此每次到期都是整批撞在一起（复习雪崩），实际每天要么 0 词要么爆量。
    static func fuzzFactor(seed: UInt64) -> Double {
        var x = seed &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        let unit = Double(x % 10_001) / 10_000.0
        return 0.95 + unit * 0.10
    }

    /// 短期间隔不抖：10 分钟的「再来一次」抖成 9.5 分钟没有意义。
    private static func applyFuzz(_ days: Double, enabled: Bool, seed: UInt64) -> Double {
        guard enabled, days >= 2 else { return days }
        return min(max(days * fuzzFactor(seed: seed), 1), maxIntervalDays)
    }

    /// 纯函数：给定当前状态与评分，算出下一个状态。方便单测。
    ///
    /// `fuzz` 默认 **false**：现有单测断言的是精确间隔，默认开抖动会让它们随机失败。
    /// App 侧由 `Store.grade` 按 `settings.reviewFuzz` 显式传入。
    static func next(
        _ state: SRSState,
        grade: ReviewGrade,
        now: Date = Date(),
        fuzz: Bool = false,
        seed: UInt64 = 0
    ) -> SRSState {
        var s = state
        let previous = s.intervalDays

        switch grade {
        case .again:
            s.wrong += 1
            s.lapses += 1
            s.level = max(0, s.level - 2)
            s.ease = max(1.3, s.ease - 0.2)
            s.lastReviewed = now
            s.intervalDays = relearnInterval / 86_400
            s.due = now.addingTimeInterval(relearnInterval)

        case .hard:
            s.wrong += 1
            s.ease = max(1.3, s.ease - 0.15)
            // 新词点「模糊」：算学过一次，但不跳级。
            s.level = min(ladders.count - 1, max(1, s.level))
            s.lastReviewed = now
            let days = intervalDays(level: s.level, ease: s.ease, previous: previous) * 0.5
            s.intervalDays = days
            s.due = now.addingTimeInterval(days * 86_400)

        case .good:
            s.correct += 1
            s.level = min(ladders.count - 1, s.level + 1)
            s.lastReviewed = now
            let days = applyFuzz(
                intervalDays(level: s.level, ease: s.ease, previous: previous),
                enabled: fuzz,
                seed: seed
            )
            s.intervalDays = days
            s.due = now.addingTimeInterval(days * 86_400)

        case .easy:
            s.correct += 1
            s.level = min(ladders.count - 1, s.level + 2)
            s.ease = min(3.2, s.ease + 0.15)
            s.lastReviewed = now
            let days = applyFuzz(
                intervalDays(level: s.level, ease: s.ease, previous: previous),
                enabled: fuzz,
                seed: seed
            )
            s.intervalDays = days
            s.due = now.addingTimeInterval(days * 86_400)
        }
        return s
    }
}
