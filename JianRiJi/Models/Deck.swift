import Foundation

/// 一个词本。当前按 JLPT 分档，将来可以换成教材分册（大家的日本语 初级1…）。
/// id 与 AppSettings.deckFilter 对应；`all` 表示全部。
struct Deck: Identifiable, Hashable {
    static let allID = "all"

    let id: String
    let title: String
    let subtitle: String
    /// 封面角标文字，如 N5 / 全
    let badge: String
    let words: [Word]

    var count: Int { words.count }
    var isAll: Bool { id == Deck.allID }
}
