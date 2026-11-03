import Foundation

struct Kana: Identifiable, Hashable {
    let kana: String
    let romaji: String

    var id: String { kana + romaji }
    var isPlaceholder: Bool { kana.isEmpty }
}

/// 五十音数据。手工录入，按行分组，空位保留占位符以便对齐。
enum KanaData {
    private static let gap = Kana(kana: "", romaji: "")

    static let seion: [[Kana]] = [
        [k("あ", "a"), k("い", "i"), k("う", "u"), k("え", "e"), k("お", "o")],
        [k("か", "ka"), k("き", "ki"), k("く", "ku"), k("け", "ke"), k("こ", "ko")],
        [k("さ", "sa"), k("し", "shi"), k("す", "su"), k("せ", "se"), k("そ", "so")],
        [k("た", "ta"), k("ち", "chi"), k("つ", "tsu"), k("て", "te"), k("と", "to")],
        [k("な", "na"), k("に", "ni"), k("ぬ", "nu"), k("ね", "ne"), k("の", "no")],
        [k("は", "ha"), k("ひ", "hi"), k("ふ", "fu"), k("へ", "he"), k("ほ", "ho")],
        [k("ま", "ma"), k("み", "mi"), k("む", "mu"), k("め", "me"), k("も", "mo")],
        [k("や", "ya"), gap, k("ゆ", "yu"), gap, k("よ", "yo")],
        [k("ら", "ra"), k("り", "ri"), k("る", "ru"), k("れ", "re"), k("ろ", "ro")],
        [k("わ", "wa"), gap, gap, gap, k("を", "wo")],
        [k("ん", "n"), gap, gap, gap, gap]
    ]

    static let dakuten: [[Kana]] = [
        [k("が", "ga"), k("ぎ", "gi"), k("ぐ", "gu"), k("げ", "ge"), k("ご", "go")],
        [k("ざ", "za"), k("じ", "ji"), k("ず", "zu"), k("ぜ", "ze"), k("ぞ", "zo")],
        [k("だ", "da"), k("ぢ", "ji(di)"), k("づ", "zu(du)"), k("で", "de"), k("ど", "do")],
        [k("ば", "ba"), k("び", "bi"), k("ぶ", "bu"), k("べ", "be"), k("ぼ", "bo")]
    ]

    static let handakuten: [[Kana]] = [
        [k("ぱ", "pa"), k("ぴ", "pi"), k("ぷ", "pu"), k("ぺ", "pe"), k("ぽ", "po")]
    ]

    static let yoon: [[Kana]] = [
        [k("きゃ", "kya"), k("きゅ", "kyu"), k("きょ", "kyo")],
        [k("しゃ", "sha"), k("しゅ", "shu"), k("しょ", "sho")],
        [k("ちゃ", "cha"), k("ちゅ", "chu"), k("ちょ", "cho")],
        [k("にゃ", "nya"), k("にゅ", "nyu"), k("にょ", "nyo")],
        [k("ひゃ", "hya"), k("ひゅ", "hyu"), k("ひょ", "hyo")],
        [k("みゃ", "mya"), k("みゅ", "myu"), k("みょ", "myo")],
        [k("りゃ", "rya"), k("りゅ", "ryu"), k("りょ", "ryo")],
        [k("ぎゃ", "gya"), k("ぎゅ", "gyu"), k("ぎょ", "gyo")],
        [k("じゃ", "ja"), k("じゅ", "ju"), k("じょ", "jo")],
        [k("びゃ", "bya"), k("びゅ", "byu"), k("びょ", "byo")],
        [k("ぴゃ", "pya"), k("ぴゅ", "pyu"), k("ぴょ", "pyo")]
    ]

    /// 片假名对照：同一个音，按平假名顺序给。
    static let katakanaMap: [String: String] = [
        "あ": "ア", "い": "イ", "う": "ウ", "え": "エ", "お": "オ",
        "か": "カ", "き": "キ", "く": "ク", "け": "ケ", "こ": "コ",
        "さ": "サ", "し": "シ", "す": "ス", "せ": "セ", "そ": "ソ",
        "た": "タ", "ち": "チ", "つ": "ツ", "て": "テ", "と": "ト",
        "な": "ナ", "に": "ニ", "ぬ": "ヌ", "ね": "ネ", "の": "ノ",
        "は": "ハ", "ひ": "ヒ", "ふ": "フ", "へ": "ヘ", "ほ": "ホ",
        "ま": "マ", "み": "ミ", "む": "ム", "め": "メ", "も": "モ",
        "や": "ヤ", "ゆ": "ユ", "よ": "ヨ",
        "ら": "ラ", "り": "リ", "る": "ル", "れ": "レ", "ろ": "ロ",
        "わ": "ワ", "を": "ヲ", "ん": "ン"
    ]

    private static func k(_ kana: String, _ romaji: String) -> Kana {
        Kana(kana: kana, romaji: romaji)
    }
}
