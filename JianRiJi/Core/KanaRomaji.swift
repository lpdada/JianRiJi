import Foundation

/// 假名 → romaji（Hepburn 风格，与词库转换脚本同一套规则，便于经典模式给注音例句逐段标 romaji）。
/// 约定与截图一致：は → ha、を → wo，不做助词特殊化；ん一律 n（じゅんび → junbi）；
/// 长音保留（おう → ou、きゅう → kyuu）；片假名长音 ー 重复前一个元音（コーヒー → koohii）。
enum KanaRomaji {

    private static let table: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
        // 外来语音节
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
        "てぃ": "ti", "でぃ": "di", "ちぇ": "che", "しぇ": "she", "じぇ": "je",
        "ゔ": "vu", "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
    ]

    private static let kataToHira: [Character: Character] = [
        "ア": "あ", "イ": "い", "ウ": "う", "エ": "え", "オ": "お",
        "カ": "か", "キ": "き", "ク": "く", "ケ": "け", "コ": "こ",
        "サ": "さ", "シ": "し", "ス": "す", "セ": "せ", "ソ": "そ",
        "タ": "た", "チ": "ち", "ツ": "つ", "テ": "て", "ト": "と",
        "ナ": "な", "ニ": "に", "ヌ": "ぬ", "ネ": "ね", "ノ": "の",
        "ハ": "は", "ヒ": "ひ", "フ": "ふ", "ヘ": "へ", "ホ": "ほ",
        "マ": "ま", "ミ": "み", "ム": "む", "メ": "め", "モ": "も",
        "ヤ": "や", "ユ": "ゆ", "ヨ": "よ",
        "ラ": "ら", "リ": "り", "ル": "る", "レ": "れ", "ロ": "ろ",
        "ワ": "わ", "ヲ": "を", "ン": "ん",
        "ガ": "が", "ギ": "ぎ", "グ": "ぐ", "ゲ": "げ", "ゴ": "ご",
        "ザ": "ざ", "ジ": "じ", "ズ": "ず", "ゼ": "ぜ", "ゾ": "ぞ",
        "ダ": "だ", "ヂ": "ぢ", "ヅ": "づ", "デ": "で", "ド": "ど",
        "バ": "ば", "ビ": "び", "ブ": "ぶ", "ベ": "べ", "ボ": "ぼ",
        "パ": "ぱ", "ピ": "ぴ", "プ": "ぷ", "ペ": "ぺ", "ポ": "ぽ",
        "ヴ": "ゔ",
        "ァ": "ぁ", "ィ": "ぃ", "ゥ": "ぅ", "ェ": "ぇ", "ォ": "ぉ",
        "ッ": "っ", "ャ": "ゃ", "ュ": "ゅ", "ョ": "ょ", "ヮ": "ゎ",
        "ヵ": "か", "ヶ": "け",
    ]

    static func romaji(for kana: String) -> String {
        let hira = String(kana.map { kataToHira[$0] ?? $0 })
        let chars = Array(hira)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "ー" {
                if let last = out.last, "aeiou".contains(last) {
                    out.append(last)
                }
                i += 1
                continue
            }
            if ch == "っ" {
                if i + 1 < chars.count {
                    let next: String
                    if i + 2 < chars.count, let two = table[String(chars[i + 1...i + 2])] {
                        next = two
                    } else {
                        next = table[String(chars[i + 1])] ?? ""
                    }
                    if let first = next.first {
                        out.append(first)
                    }
                }
                i += 1
                continue
            }
            if i + 1 < chars.count, let two = table[String(chars[i...i + 1])] {
                out += two
                i += 2
                continue
            }
            if let one = table[String(ch)] {
                out += one
                i += 1
                continue
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    /// 判断一个字符串是否全部是假名（平假名 / 片假名 / 长音 / 促音），用于注音例句分段时决定读音。
    static func isKana(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { ch in
            ("ぁ" <= ch && ch <= "ゖ") || ("ァ" <= ch && ch <= "ヺ") || ch == "ー"
        }
    }
}

/// 注音例句的一段：词形 + 可选读音。读音为空时只显示词形（汉字无注音的情况）。
struct AnnotatedSegment: Identifiable {
    let id = UUID()
    let text: String
    let reading: String?

    var romaji: String? {
        guard let reading, !reading.isEmpty else { return nil }
        return KanaRomaji.romaji(for: reading)
    }
}

/// 解析注音例句：
/// - 分段式（带 `[`）：按空格分段，每段是「词形[读音]」或纯假名/标点；
/// - 整句式（不带 `[`）：返回空数组，调用方改用整句读音 + romaji 显示。
enum AnnotatedExample {
    static func parse(_ furigana: String) -> [AnnotatedSegment] {
        guard furigana.contains("[") else { return [] }
        return furigana
            .split(separator: " ")
            .flatMap { token -> [AnnotatedSegment] in
                let part = String(token)
                guard let open = part.firstIndex(of: "["),
                      let close = part.firstIndex(of: "]"),
                      open < close else {
                    let reading = KanaRomaji.isKana(part) ? part : nil
                    return [AnnotatedSegment(text: part, reading: reading)]
                }
                let text = String(part[..<open])
                let reading = String(part[part.index(after: open)..<close])
                let tail = String(part[part.index(after: close)...])
                // 「数学[すうがく]が」这种段：词形后还带假名助词，拆成两段，读音各标各的。
                if tail.isEmpty {
                    return [AnnotatedSegment(text: text, reading: reading)]
                }
                let tailReading = KanaRomaji.isKana(tail) ? tail : nil
                return [
                    AnnotatedSegment(text: text, reading: reading),
                    AnnotatedSegment(text: tail, reading: tailReading),
                ]
            }
    }
}
