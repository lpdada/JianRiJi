import Foundation

/// 动词 / 形容词变形，纯函数、无 UI、可单测。
/// 词性只认 Word.partOfSpeech 里写明的类别，认不出来就返回 nil（详情页整块不显示），不猜。
/// 动词给 ます形 / て形 / た形 / ない形 / 可能形 / 意志形；
/// 形容词给 て形 / 过去形（存在 ta 里）/ 否定形（存在 nai 里）。
enum ConjugationKind {
    case godan
    case ichidan
    case kahen
    case sahen
    case iAdjective
    case naAdjective
}

struct ConjugationForms {
    let kind: ConjugationKind
    let masu: String?
    let te: String
    /// 动词是た形，形容词是过去形。
    let ta: String
    /// 动词是否定形，形容词是否定形。
    let nai: String
    let potential: String?
    let volitional: String?

    /// 详情页按顺序展示的行，形容词只出三行，动词出六行。
    var displayRows: [(label: String, value: String)] {
        switch kind {
        case .godan, .ichidan, .kahen, .sahen:
            return [
                ("ます形", masu ?? ""),
                ("て形", te),
                ("た形", ta),
                ("ない形", nai),
                ("可能形", potential ?? ""),
                ("意志形", volitional ?? ""),
            ].filter { !$0.1.isEmpty }
        case .iAdjective, .naAdjective:
            return [
                ("て形", te),
                ("过去形", ta),
                ("否定形", nai),
            ]
        }
    }
}

enum Conjugation {
    /// 主入口：词性判断不出来、词形不合规则时返回 nil。
    static func conjugate(_ word: Word) -> ConjugationForms? {
        let pos = word.partOfSpeech
        let term = word.term

        if pos.contains("五段") {
            return godan(term)
        }
        if pos.contains("一段") {
            return ichidan(term)
        }
        if pos.contains("カ变") || pos.contains("カ変") {
            return kahen(term)
        }
        if pos.contains("サ变") || pos.contains("サ変") {
            return sahen(term)
        }
        // 形容动词要先判：它不含“形容词”三个字，但顺序写前面更稳。
        if pos.contains("形容动词") || pos.contains("ナ形") {
            return ConjugationForms(
                kind: .naAdjective,
                masu: nil,
                te: term + "で",
                ta: term + "だった",
                nai: term + "ではない",
                potential: nil,
                volitional: nil
            )
        }
        if pos.contains("形容词") || pos.contains("イ形") {
            return iAdjective(word)
        }
        return nil
    }

    // MARK: - 动词

    private static func godan(_ term: String) -> ConjugationForms? {
        guard let last = term.last else { return nil }
        let stem = String(term.dropLast())
        let isIku = term == "行く" || term == "いく"
        switch last {
        case "う":
            return forms(.godan, masu: stem + "います", te: stem + "って", ta: stem + "った",
                          nai: stem + "わない", potential: stem + "える", volitional: stem + "おう")
        case "く":
            return forms(.godan, masu: stem + "きます",
                          te: isIku ? stem + "って" : stem + "いて",
                          ta: isIku ? stem + "った" : stem + "いた",
                          nai: stem + "かない", potential: stem + "ける", volitional: stem + "こう")
        case "ぐ":
            return forms(.godan, masu: stem + "ぎます", te: stem + "いで", ta: stem + "いだ",
                          nai: stem + "がない", potential: stem + "げる", volitional: stem + "ごう")
        case "す":
            return forms(.godan, masu: stem + "します", te: stem + "して", ta: stem + "した",
                          nai: stem + "さない", potential: stem + "せる", volitional: stem + "そう")
        case "つ":
            return forms(.godan, masu: stem + "ちます", te: stem + "って", ta: stem + "った",
                          nai: stem + "たない", potential: stem + "てる", volitional: stem + "とう")
        case "ぬ":
            return forms(.godan, masu: stem + "にます", te: stem + "んで", ta: stem + "んだ",
                          nai: stem + "なない", potential: stem + "ねる", volitional: stem + "のう")
        case "ぶ":
            return forms(.godan, masu: stem + "びます", te: stem + "んで", ta: stem + "んだ",
                          nai: stem + "ばない", potential: stem + "べる", volitional: stem + "ぼう")
        case "む":
            return forms(.godan, masu: stem + "みます", te: stem + "んで", ta: stem + "んだ",
                          nai: stem + "まない", potential: stem + "める", volitional: stem + "もう")
        case "る":
            return forms(.godan, masu: stem + "ります", te: stem + "って", ta: stem + "った",
                          nai: stem + "らない", potential: stem + "れる", volitional: stem + "ろう")
        default:
            return nil
        }
    }

    private static func ichidan(_ term: String) -> ConjugationForms? {
        guard term.hasSuffix("る") else { return nil }
        let stem = String(term.dropLast())
        return forms(.ichidan, masu: stem + "ます", te: stem + "て", ta: stem + "た",
                     nai: stem + "ない", potential: stem + "られる", volitional: stem + "よう")
    }

    private static func kahen(_ term: String) -> ConjugationForms? {
        if term == "来る" {
            return forms(.kahen, masu: "来ます", te: "来て", ta: "来た",
                         nai: "来ない", potential: "来られる", volitional: "来よう")
        }
        if term == "くる" {
            return forms(.kahen, masu: "きます", te: "きて", ta: "きた",
                         nai: "こない", potential: "こられる", volitional: "こよう")
        }
        return nil
    }

    private static func sahen(_ term: String) -> ConjugationForms? {
        guard term.hasSuffix("する") else { return nil }
        let base = String(term.dropLast(2))
        return forms(.sahen, masu: base + "します", te: base + "して", ta: base + "した",
                     nai: base + "しない", potential: base + "できる", volitional: base + "しよう")
    }

    private static func forms(_ kind: ConjugationKind, masu: String, te: String, ta: String,
                              nai: String, potential: String, volitional: String) -> ConjugationForms {
        ConjugationForms(kind: kind, masu: masu, te: te, ta: ta, nai: nai,
                         potential: potential, volitional: volitional)
    }

    // MARK: - 形容词

    private static func iAdjective(_ word: Word) -> ConjugationForms? {
        // いい / 良い 是不规则的：词干按 よ 走，不按 い 去尾。
        if word.term == "いい" || word.term == "良い" || word.reading == "いい" {
            return ConjugationForms(kind: .iAdjective, masu: nil, te: "よくて", ta: "よかった",
                                    nai: "よくない", potential: nil, volitional: nil)
        }
        guard word.term.hasSuffix("い") else { return nil }
        let stem = String(word.term.dropLast())
        return ConjugationForms(kind: .iAdjective, masu: nil, te: stem + "くて", ta: stem + "かった",
                                nai: stem + "くない", potential: nil, volitional: nil)
    }
}
