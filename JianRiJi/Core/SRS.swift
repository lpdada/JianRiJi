import Foundation

/// 单张卡片的四档评分。与 Anki 的 Again/Hard/Good/Easy 同构，不抄代码，只借用这套被验证过的手感。
enum ReviewGrade: Int, Codable, CaseIterable, Identifiable {
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
struct SRSState: Codable, Hashable {
    /// 记忆台阶：0 = 新词，9 = 台阶顶端
    var level: Int = 0
    /// 难度系数，越小越难
    var ease: Double = 2.5
    /// 下次到期时间
    var due: Date = Date()
    var correct: Int = 0
    var wrong: Int = 0
    var lastReviewed: Date?

    /// 从没学过
    var isNew: Bool { level == 0 && lastReviewed == nil }

    /// 0...1 的掌握度
    var mastery: Double {
        Double(level) / Double(max(1, SRS.ladders.count - 1))
    }

    /// 已掌握：只剩最后一两级没走完
    var isMastered: Bool { level >= SRS.ladders.count - 2 }
}

/// 艾宾浩斯式台阶。单位是「天」，第一格用分钟级重来。
enum SRS {
    static let ladders: [Double] = [0, 1, 2, 4, 7, 15, 30, 60, 120, 240]

    /// 新词答错后的重来间隔：10 分钟
    static let relearnInterval: TimeInterval = 10 * 60

    /// 某台阶对应的间隔（天），带 ease 修正。
    static func intervalDays(level: Int, ease: Double) -> Double {
        guard level > 0 else { return relearnInterval / 86_400 }
        let base = ladders[min(level, ladders.count - 1)]
        let factor = 1 + (ease - 2.5) * 0.2
        return max(0.007, base * factor)
    }

    /// 纯函数：给定当前状态与评分，算出下一个状态。方便单测。
    static func next(_ state: SRSState, grade: ReviewGrade, now: Date = Date()) -> SRSState {
        var s = state
        switch grade {
        case .again:
            s.wrong += 1
            s.level = max(0, s.level - 2)
            s.ease = max(1.3, s.ease - 0.2)
            s.lastReviewed = now
            s.due = now.addingTimeInterval(relearnInterval)

        case .hard:
            s.wrong += 1
            s.ease = max(1.3, s.ease - 0.15)
            s.level = min(ladders.count - 1, max(1, s.level))
            s.lastReviewed = now
            let span = intervalDays(level: s.level, ease: s.ease) * 0.5 * 86_400
            s.due = now.addingTimeInterval(span)

        case .good:
            s.correct += 1
            s.level = min(ladders.count - 1, s.level + 1)
            s.lastReviewed = now
            s.due = now.addingTimeInterval(intervalDays(level: s.level, ease: s.ease) * 86_400)

        case .easy:
            s.correct += 1
            s.level = min(ladders.count - 1, s.level + 2)
            s.ease = min(3.2, s.ease + 0.15)
            s.lastReviewed = now
            s.due = now.addingTimeInterval(intervalDays(level: s.level, ease: s.ease) * 86_400)
        }
        return s
    }
}
