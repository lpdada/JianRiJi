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
    /// 注意：这里不能给 = nil 默认值——带默认值的属性会被合成 Decodable 跳过，
    /// JSON 里有 variants 也会解成 nil（CI 单测已实证）。Optional 本身缺键就是 nil。
    let variants: [String: String]?
    /// 精讲解析，可为空。同样不能给默认值，原因同上。
    let note: String?
    /// 例句注音，可为空。两种形态都见过：
    /// 分段式如「数学[すうがく]が 不得意[ふとくい]だ」，经典模式按段拆成 假名 / 词形 / romaji 三行；
    /// 整句式如「がっこうはえきのちかくです。」（或精讲的例句假名），经典模式整句显示读音与 romaji。
    let exampleFurigana: String?
    /// 所属词书，如「初级上」；缺省时按 JLPT 兜底，见 resolvedBook。
    /// 同样不能给默认值，原因同 note。
    let book: String?
    /// 标签，如「日常」，用于日常高频一类词书。同样不能给默认值。
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, term, reading, romaji, meaning, jlpt, example, variants, note, book, tags
        case partOfSpeech = "pos"
        case exampleZh = "example_zh"
        case exampleFurigana = "example_furigana"
    }

    /// 详情页标题：有汉字表记时显示「表记（读音）」
    var displayTitle: String {
        term == reading ? term : "\(term)（\(reading)）"
    }

    /// 没写 book 的旧数据按 JLPT 归到对应词书，保证每本词书都有内容。
    /// 注意：这里返回的是 books.json 里 book 类词书的 filterValue，不是书名。
    var resolvedBook: String {
        if let book, !book.isEmpty { return book }
        switch jlpt {
        case "N5": return "初级上"
        case "N4": return "初级下"
        case "N3": return "中级"
        default: return "高级"
        }
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
        exampleZh: "海的那头能看见灯塔。",
        variants: nil,
        note: nil,
        exampleFurigana: nil,
        book: nil,
        tags: nil
    )
}
