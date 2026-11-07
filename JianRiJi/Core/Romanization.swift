import Foundation

/// 罗马字归一化。
///
/// 拼写 / 听写模式让用户敲 romaji，但同一个假名有两套罗马字：
/// **平文式（Hepburn）**——教材主流：shi / chi / tsu / fu / ji / sha / cha / ja
/// **训令式（Kunrei）**——部分输入法与老教材：si / ti / tu / hu / zi / sya / tya / zya
///
/// 加上长音写法差异（おう / ō / ou / o-），用户几乎不可能每次都敲出词库里的那一串。
/// 原来的实现只做 lowercase + 去空格，等于逼用户背「我们用的是哪套拼法」——
/// 这不是在考单词，是在考转写规则。
///
/// 这里把两边都折叠到同一形态再比较：只要**读法相同**就算对。
enum Romanization {

    /// 训令式 → 平文式。按长度从长到短替换，避免 `sya` 被 `si` 抢先吃掉。
    private static let kunreiPairs: [(String, String)] = [
        // 三字母（拗音）
        ("sya", "sha"), ("syu", "shu"), ("syo", "sho"),
        ("tya", "cha"), ("tyu", "chu"), ("tyo", "cho"),
        ("zya", "ja"), ("zyu", "ju"), ("zyo", "jo"),
        ("dya", "ja"), ("dyu", "ju"), ("dyo", "jo"),
        // 二字母
        ("si", "shi"), ("ti", "chi"), ("tu", "tsu"), ("hu", "fu"),
        ("zi", "ji"), ("di", "ji"), ("du", "zu"),
    ]

    /// 带音调的元音 → 双写元音（词库用的是双写体系：gakkou / kyuukei）。
    private static let macronPairs: [(String, String)] = [
        ("ā", "aa"), ("ī", "ii"), ("ū", "uu"), ("ē", "ee"), ("ō", "ou"),
        ("â", "aa"), ("î", "ii"), ("û", "uu"), ("ê", "ee"), ("ô", "ou"),
    ]

    /// 归一化到可比较形态。两边都过一遍这个函数再比较。
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()

        // 全角字符（全角字母、全角空格）先折半。
        if let halfwidth = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
            s = halfwidth
        }

        for (from, to) in macronPairs {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // 分隔符一律去掉：用户敲 "gak kou" / "gak-kou" / "gakkou" 都该算对。
        for separator in [" ", "\u{3000}", "-", "–", "—", "'", "’", "・", "."] {
            s = s.replacingOccurrences(of: separator, with: "")
        }

        // 长音符：kōhī 里出现的 "-" 已被去掉；剩余 `ou`/`oo` 的等价交给下面的元音折叠。
        s = foldLongVowels(s)

        for (from, to) in kunreiPairs {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    /// `ou` / `oo` / `ô` 在日语里都是长音 おー。
    /// 只折叠 `ou` → `o` 会有个坑：`ou` 也可能是 お+う 两个独立元音（如「思う」omou）。
    /// 所以这里**不做单向压缩**，只把 `oo` 折成 `ou`，让 `koori` 与 `kouri` 等价，
    /// 同时保留 `ou` 原样，避免把 omou 和 omo 混为一谈。
    private static func foldLongVowels(_ s: String) -> String {
        s.replacingOccurrences(of: "oo", with: "ou")
    }

    /// 判断用户输入是否与标准答案等价。
    /// - Parameters:
    ///   - typed: 用户敲的内容（可能是 romaji，也可能是假名）
    ///   - word: 目标词条
    static func matches(typed: String, word: Word) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 直接敲假名也算对：有些人用日语输入法，能打假名就打假名。
        if trimmed == word.reading || trimmed == word.term { return true }
        // 片假名输入：读音折成平假名再比。
        let hiragana = trimmed.applyingTransform(.hiraganaToKatakana, reverse: true) ?? trimmed
        if hiragana == word.reading || hiragana == word.term { return true }

        return normalize(trimmed) == normalize(word.romaji)
    }
}
