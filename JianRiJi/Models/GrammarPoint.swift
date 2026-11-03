import Foundation

/// 一个分级语法点。数据来自 Resources/grammar_points.json（自编 270 条，N5–N1）。
/// 除 id / level / title 外都做成可选：以后改表时某列留空，整表不会因此解不出来。
struct GrammarPoint: Identifiable, Codable, Hashable {
    let id: String
    /// JLPT 级别：N5 ... N1
    let level: String
    /// 语法点：〜は〜です
    let title: String
    /// 接续：名词1 + は + 名词2 + です
    let connection: String?
    /// 意义：……是……
    let meaning: String?
    /// 例句（日文）
    let example: String?
    /// 例句假名
    let exampleReading: String?
    /// 例句中文
    let exampleZh: String?
    /// 备注 / 注意事项
    let note: String?
    /// 标签：判断句 / 逆接 / 原因 ……
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case id, level, title, connection, meaning, example, note, tag
        case exampleReading = "exampleReading"
        case exampleZh = "exampleZh"
    }
}
