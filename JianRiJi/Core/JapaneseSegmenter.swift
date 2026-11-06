import Foundation

/// 例句里切出来的一段：词形 + 读音 +（能对上词库时的）词条本身。
///
/// 设计原则：**不编造**。
/// - 词库 / 变形 / 功能词命中的段，读音来自词库字段；
/// - 纯假名段，读音就是它自己；
/// - 词库外、又不是纯假名的段（如「大阪」这种没收录的地名），读音给 nil，界面就不标读音，
///   而不是用音读规则硬猜一个。
struct ExampleSegment: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 词库精确命中
        case word
        /// 变形命中（あります → ある / 食べて → 食べる）
        case inflection
        /// 助词、助动词、形式名词（词库不收，靠内置表）
        case particle
        /// 词库外的假名块（たち / りま 之类）
        case kana
        /// 词库外的汉字块（不给读音）
        case unknownKanji
        /// 标点
        case punctuation
        /// 数字、拉丁字母等其它字符
        case other
    }

    /// 在整句里的顺序，同一句话重新分词后保持不变，可直接当 ForEach 的 id。
    let id: Int
    /// 原句里这一段的样子
    let surface: String
    /// 假名读音；拿不到就是 nil
    let reading: String?
    /// 能对上词库时的词条
    let word: Word?
    let kind: Kind

    var romaji: String? {
        guard let reading, !reading.isEmpty else { return nil }
        return KanaRomaji.romaji(for: reading)
    }

    /// 标点不给点击热区。
    var isTappable: Bool {
        kind != .punctuation && !surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 点开详情时能不能给完整词条。
    var hasDictionaryEntry: Bool { word != nil }
}

/// 本地日语分词 + 注音。
///
/// 为什么自己做：工程不引第三方依赖（见 docs/MUSE_PROMPT.md 硬约束 2），
/// 而「例句逐词可点」必须要有一个分词器。这里用 seed_words.json 的 10660 条词库
/// 当词典，做**正向最长匹配**，再用三条后处理规则收拾边角：
///
/// 1. 相邻同类未知块合并（た + ち → たち）；
/// 2. 单字词条 + 紧随的未知汉字合成一块（大 + 阪 → 大阪，整块标记为未收录）；
/// 3. 白名单假名后缀并入前一个实词（私 + たち → 私たち）。
///
/// 另外用 `Conjugation` 反推变形表（あります → ある、なりました → なる），
/// 让例句里的活用形也能对上词条。这套规则在真实词库上验证过，
/// 「私たちはチームの連携を強化する必要があります。」会切成和参考实现一样的 11 段。
final class JapaneseSegmenter {

    static let shared = JapaneseSegmenter()

    /// 生产代码只用 `shared`。这里是 internal 而不是 private，
    /// 是为了单测能造一个独立实例、喂一份小词库，不去动全局单例的状态。
    init() {}

    private struct Inflection {
        let word: Word
        /// 变形后的假名形（食べます → たべます）；拿不到时为 nil
        let kana: String?
    }

    private struct Token {
        var kind: ExampleSegment.Kind
        var surface: String
        var reading: String?
        var word: Word?
    }

    private var byTerm: [String: Word] = [:]
    private var byReading: [String: Word] = [:]
    private var inflections: [String: Inflection] = [:]
    private var maxTokenLength = 2
    private var prepared = false

    /// 按整句缓存分词结果：翻来翻去不会反复算同一句。
    private var cache: [String: [ExampleSegment]] = [:]
    private static let cacheLimit = 200

    // MARK: - 内置功能词
    //
    // 词库（seed_words.json）收的是「词」，不收助词 / 助动词 / 形式名词。
    // 少了这张表，句子会被切成「私｜た｜ち｜は」这种碎块。

    private static let functionWords: Set<String> = [
        // 助词
        "は", "が", "を", "の", "に", "で", "と", "も", "へ", "や", "か",
        "ね", "よ", "な", "さ", "わ", "ぞ", "ぜ", "て",
        "から", "まで", "より", "ほど", "くらい", "ぐらい", "など", "だけ", "しか",
        "ばかり", "ながら", "ので", "のに", "けど", "けれど", "けれども", "ても", "でも",
        "たり", "だり", "って",
        // 助动词 / 断定
        "です", "ます", "でした", "ません", "ましょう", "でしょう", "だろう", "だった",
        "だ", "である", "ました", "ませんでした",
        "ない", "なかった", "たい", "たく", "たかった", "れる", "られる", "せる", "させる",
        // 形式名词 / 形式用言
        "よう", "こと", "もの", "ため", "はず", "つもり", "わけ", "ところ",
        "みたい", "らしい", "そう", "ように", "かねない",
    ]

    /// 允许并入前一个实词的假名后缀：私 + たち → 私たち。
    /// 只收这几个，避免把「働く」后面的「こと」之类误并进来。
    private static let suffixWhitelist: Set<String> = [
        "たち", "ら", "ども", "さん", "さま", "ちゃん", "くん", "がた",
    ]

    private static let punctuation: Set<Character> = [
        "。", "、", "，", "．", ",", ".", "!", "?", "！", "？",
        "「", "」", "『", "』", "（", "）", "(", ")",
        "［", "］", "[", "]", "…", "‥", "・", "：", ":", "；", ";",
        "—", "―", "〜", "～",
    ]

    // MARK: - 构建索引

    /// 幂等。词库变化（切换词本）不需要重建——索引是全量词库的。
    func prepare(words: [Word]) {
        guard !prepared, !words.isEmpty else { return }
        prepared = true

        var termIndex: [String: Word] = [:]
        var readingIndex: [String: Word] = [:]
        var inflectionIndex: [String: Inflection] = [:]
        var longest = 1

        for word in words {
            if termIndex[word.term] == nil { termIndex[word.term] = word }
            if !word.reading.isEmpty, readingIndex[word.reading] == nil {
                readingIndex[word.reading] = word
            }
            longest = max(longest, word.term.count)

            for surface in Self.inflectionSurfaces(of: word) {
                // 已经是一个独立词条的串不要当变形，否则会盖掉本义。
                guard surface.surface.count >= 2,
                      termIndex[surface.surface] == nil,
                      inflectionIndex[surface.surface] == nil else { continue }
                inflectionIndex[surface.surface] = Inflection(word: word, kana: surface.kana)
                longest = max(longest, surface.surface.count)
            }
        }

        for key in Self.functionWords { longest = max(longest, key.count) }

        byTerm = termIndex
        byReading = readingIndex
        inflections = inflectionIndex
        maxTokenLength = min(longest, 12)
        cache.removeAll(keepingCapacity: true)
    }

    var isPrepared: Bool { prepared }

    /// 给「记忆技巧」用：按表记找词条。
    func word(forTerm term: String) -> Word? {
        byTerm[term]
    }

    /// 给「记忆技巧」用：同音词（用来提示同音异义）。
    func word(forReading reading: String) -> Word? {
        byReading[reading]
    }

    // MARK: - 变形表

    /// 一个词条所有可能的活用形，以及它们对应的假名形。
    private static func inflectionSurfaces(of word: Word) -> [(surface: String, kana: String?)] {
        let pos = word.partOfSpeech
        let inflectable = pos.contains("动词") || pos.contains("五段") || pos.contains("一段")
            || pos.contains("カ变") || pos.contains("サ变")
            || pos.contains("形容词") || pos.contains("形容动词")
            || pos.contains("イ形") || pos.contains("ナ形")
        guard inflectable, let forms = Conjugation.conjugate(word) else { return [] }

        var han: [String?] = [
            forms.masu, forms.te, forms.ta, forms.nai, forms.potential, forms.volitional,
        ]

        var kana: [String?] = []
        if !word.reading.isEmpty, word.reading != word.term {
            let kanaWord = Self.rewritten(word, term: word.reading)
            if let kanaForms = Conjugation.conjugate(kanaWord) {
                kana = [
                    kanaForms.masu, kanaForms.te, kanaForms.ta,
                    kanaForms.nai, kanaForms.potential, kanaForms.volitional,
                ]
            }
        }

        // 形容动词的「〜で」形（必要で）会吞掉后面的「です」，
        // 把「必要です。」切成「必要で｜す」。这一形不参与分词，
        // 详情页照样显示它（那是 Conjugation.displayRows 的事）。
        if case .naAdjective = forms.kind {
            han[1] = nil
            if kana.count > 1 { kana[1] = nil }
        }

        var out: [(surface: String, kana: String?)] = []
        for index in han.indices {
            guard let surface = han[index], surface.count >= 2 else { continue }
            let kanaSurface: String? = index < kana.count ? kana[index] : nil
            out.append((surface, kanaSurface))
        }

        // ます形派生：なりました / なりません / なりましょう。
        // 词库只收辞书形，不补这一层的话「なりました」会被切碎。
        if let masu = forms.masu, masu.hasSuffix("ます") {
            let stem = String(masu.dropLast(2))
            let firstKana: String? = kana.isEmpty ? nil : kana[0]
            var kanaStem: String?
            if let kanaMasu = firstKana, kanaMasu.hasSuffix("ます") {
                kanaStem = String(kanaMasu.dropLast(2))
            }
            for suffix in ["ました", "ません", "ましょう", "ませんでした"] {
                out.append((stem + suffix, kanaStem.map { $0 + suffix }))
            }
            // ます形词干：聞きながら / 働き続ける
            if stem.count >= 2 {
                out.append((stem, kanaStem))
            }
        }
        return out
    }

    /// 复制一个词条、换掉表记（用来给 reading 也跑一遍变形，拿到假名形）。
    private static func rewritten(_ word: Word, term: String) -> Word {
        Word(
            id: word.id,
            term: term,
            reading: word.reading,
            romaji: word.romaji,
            meaning: word.meaning,
            partOfSpeech: word.partOfSpeech,
            jlpt: word.jlpt,
            example: word.example,
            exampleZh: word.exampleZh,
            variants: word.variants,
            note: word.note,
            exampleFurigana: word.exampleFurigana,
            book: word.book,
            tags: word.tags
        )
    }

    // MARK: - 分词

    func segment(_ text: String) -> [ExampleSegment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let cached = cache[trimmed] { return cached }

        let tokens = merge(rawTokens(Array(trimmed)))
        var segments: [ExampleSegment] = []
        segments.reserveCapacity(tokens.count)
        for (index, token) in tokens.enumerated() {
            segments.append(
                ExampleSegment(
                    id: index,
                    surface: token.surface,
                    reading: token.reading,
                    word: token.word,
                    kind: token.kind
                )
            )
        }

        // 缓存不设淘汰策略会把长句子一直攒着，简单地满了就清空。
        if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[trimmed] = segments
        return segments
    }

    private func rawTokens(_ chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var index = 0
        let count = chars.count

        while index < count {
            let char = chars[index]

            // 空白不进段，交给布局的间距处理。
            if char == " " || char == "\u{3000}" || char == "\n" || char == "\t" {
                index += 1
                continue
            }

            if Self.punctuation.contains(char) {
                tokens.append(Token(kind: .punctuation, surface: String(char), reading: nil, word: nil))
                index += 1
                continue
            }

            var matched: (Token, Int)?
            var length = min(maxTokenLength, count - index)
            while length >= 1 {
                let surface = String(chars[index..<(index + length)])
                if let token = lookup(surface) {
                    matched = (token, length)
                    break
                }
                length -= 1
            }

            if let (token, consumed) = matched {
                tokens.append(token)
                index += consumed
                continue
            }

            if Self.isKanji(char) {
                tokens.append(Token(kind: .unknownKanji, surface: String(char), reading: nil, word: nil))
            } else if Self.isKana(char) {
                tokens.append(Token(kind: .kana, surface: String(char), reading: String(char), word: nil))
            } else {
                tokens.append(Token(kind: .other, surface: String(char), reading: nil, word: nil))
            }
            index += 1
        }
        return tokens
    }

    /// 功能词优先：句子里「で」几乎总是助词，而不是词库里那条接续词。
    private func lookup(_ surface: String) -> Token? {
        if Self.functionWords.contains(surface) {
            return Token(kind: .particle, surface: surface, reading: surface, word: nil)
        }
        if let word = byTerm[surface] {
            return Token(kind: .word, surface: surface, reading: word.reading, word: word)
        }
        if let inflection = inflections[surface] {
            // 变形段优先用变形后的假名；拿不到就只在整段是假名时直接用原文，
            // 否则给 nil——不能拿辞书形读音冒充活用形读音。
            let reading: String?
            if let kana = inflection.kana, !kana.isEmpty {
                reading = kana
            } else if Self.isAllKana(surface) {
                reading = surface
            } else {
                reading = nil
            }
            return Token(kind: .inflection, surface: surface, reading: reading, word: inflection.word)
        }
        return nil
    }

    // MARK: - 后处理

    private func merge(_ tokens: [Token]) -> [Token] {
        // 1) 相邻同类未知块合并：た｜ち → たち
        var merged: [Token] = []
        for token in tokens {
            let mergeable = token.kind == .unknownKanji || token.kind == .kana
            if mergeable, let last = merged.last, last.kind == token.kind {
                let tail = merged.count - 1
                merged[tail].surface += token.surface
                if let head = merged[tail].reading, let follow = token.reading {
                    merged[tail].reading = head + follow
                } else {
                    merged[tail].reading = nil
                }
            } else {
                merged.append(token)
            }
        }

        // 2) 单字词条 + 紧随的未知汉字 → 一个未收录块：大 + 阪 → 大阪
        var joined: [Token] = []
        var cursor = 0
        while cursor < merged.count {
            let token = merged[cursor]
            let isSingleEntry = (token.kind == .word || token.kind == .inflection)
                && token.surface.count == 1
            if isSingleEntry, cursor + 1 < merged.count, merged[cursor + 1].kind == .unknownKanji {
                joined.append(
                    Token(
                        kind: .unknownKanji,
                        surface: token.surface + merged[cursor + 1].surface,
                        reading: nil,
                        word: nil
                    )
                )
                cursor += 2
                continue
            }
            joined.append(token)
            cursor += 1
        }

        // 3) 白名单后缀并入前一个实词：私 + たち → 私たち
        var result: [Token] = []
        for token in joined {
            let isSuffix = token.kind == .kana && Self.suffixWhitelist.contains(token.surface)
            if isSuffix, let last = result.last,
               last.kind == .word || last.kind == .inflection,
               let head = result[result.count - 1].reading,
               let follow = token.reading {
                result[result.count - 1].surface += token.surface
                result[result.count - 1].reading = head + follow
            } else {
                result.append(token)
            }
        }
        return result
    }

    // MARK: - 字符判定

    private static func isKanji(_ char: Character) -> Bool {
        if char == "々" || char == "〆" { return true }
        guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }

    private static func isKana(_ char: Character) -> Bool {
        if char == "ー" { return true }
        guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x3041...0x3096).contains(value) || (0x30A1...0x30FA).contains(value)
    }

    private static func isAllKana(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { isKana($0) }
    }
}
