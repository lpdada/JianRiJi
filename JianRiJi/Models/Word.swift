import Foundation

/// 一条词条。字段来自 Resources/seed_words.json。
struct Word: Identifiable, Codable, Hashable {
    let id: String
    /// 表记：学校 / たべる
    let term: String
    /// 假名读音：がっこう
    let reading: String
    /// 罗马字：gakkou
    let romaji: String
    /// 中文释义
    let meaning: String
    /// 词性：名词 / 动词(五段) / 形容词(い) / 形容动词
    let partOfSpeech: String
    /// JLPT 级别：N5 ... N1
    let jlpt: String
    /// 例句（日文），可为空
    let example: String?
    /// 例句中文，可为空
    let exampleZh: String?
    /// 变形表等补充形式，可为空。旧 JSON 里没有这个键时解码为 nil，不影响已有词条。
    let variants: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case id, term, reading, romaji, meaning, jlpt, example, variants
        case partOfSpeech = "pos"
        case exampleZh = "example_zh"
    }

    /// 详情页标题：有汉字表记时显示「表记（读音）」
    var displayTitle: String {
        term == reading ? term : "\(term)（\(reading)）"
    }
}

extension Word {
    /// 仅用于预览与单元测试的占位数据。
    static let sample = Word(
        id: "w999",
        term: "灯台",
        reading: "とうだい",
        romaji: "toudai",
        meaning: "灯塔",
        partOfSpeech: "名词",
        jlpt: "N3",
        example: "海の向こうに灯台が見える。",
        exampleZh: "海的那头能看见灯塔。"
    )
}
