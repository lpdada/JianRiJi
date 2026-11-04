import Foundation

/// 一本词书。数据来自 Resources/books.json。
/// filterType 决定用哪种规则从词库里筛词，加新词书不用改代码；
/// learned / favorite 两类要读学习状态，由 Store.words(in:) 另外处理。
struct WordBook: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    /// 封面角标，如 初上 / N5 / 日常
    let badge: String
    /// 归属分类页签：常用词单 / 考试词单 / 生活实用 / 日常高频 / 已学词单
    let categories: [String]
    let author: String
    let note: String
    /// all / book / jlpt / tag / learned / favorite
    let filterType: String
    let filterValue: String?
    /// Theme.deckTints 的下标
    let tint: Int

    static let allID = "all"

    var isAll: Bool { id == WordBook.allID }

    func matches(_ word: Word) -> Bool {
        switch filterType {
        case "book":
            return word.resolvedBook == filterValue
        case "jlpt":
            return word.jlpt == filterValue
        case "tag":
            guard let tag = filterValue else { return false }
            return word.tags?.contains(tag) ?? false
        default:
            return true
        }
    }
}
