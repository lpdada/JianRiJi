import XCTest
@testable import JianRiJi

/// 例句分词 / 注音的单测。
///
/// 不依赖 Bundle 里的 6 万词大词库（测试 bundle 读不到 App 资源），
/// 而是造一份刚好够覆盖规则的小词库，逐条验证：
/// 词条命中、变形命中、功能词、后缀并入、未收录块不给读音。
final class JapaneseSegmenterTests: XCTestCase {

    // MARK: - 夹具

    private func makeWord(
        _ term: String,
        _ reading: String,
        _ pos: String,
        meaning: String = "释义"
    ) -> Word {
        Word(
            id: "t-\(term)",
            term: term,
            reading: reading,
            romaji: KanaRomaji.romaji(for: reading),
            meaning: meaning,
            partOfSpeech: pos,
            jlpt: "N5",
            example: nil,
            exampleZh: nil,
            variants: nil,
            note: nil,
            exampleFurigana: nil,
            book: nil,
            tags: nil
        )
    }

    private var vocabulary: [Word] {
        [
            makeWord("私", "わたし", "代词", meaning: "我"),
            makeWord("チーム", "ちーむ", "名词", meaning: "队，组"),
            makeWord("連携", "れんけい", "名词 / 动词(サ变)", meaning: "合作"),
            makeWord("強化", "きょうか", "名词 / 动词(サ变)", meaning: "强化，加强"),
            makeWord("する", "する", "动词(サ变)", meaning: "做"),
            makeWord("必要", "ひつよう", "形容动词 / 名词", meaning: "必要"),
            makeWord("ある", "ある", "动词(五段)", meaning: "存在；有"),
            makeWord("聞く", "きく", "动词(五段)", meaning: "听"),
            makeWord("食べる", "たべる", "动词(一段)", meaning: "吃"),
            makeWord("しまう", "しまう", "动词(五段)", meaning: "（做完）了"),
            makeWord("一つ", "ひとつ", "名词", meaning: "一个"),
        ]
    }

    private func makeSegmenter() -> JapaneseSegmenter {
        let segmenter = JapaneseSegmenter()
        segmenter.prepare(words: vocabulary)
        return segmenter
    }

    // MARK: - 截图那句

    func testScreenshotSentenceSplitsLikeReference() {
        let segmenter = makeSegmenter()
        let sentence = "私たちはチームの連携を強化する必要があります。"
        let surfaces = segmenter.segment(sentence).map(\.surface)

        XCTAssertEqual(
            surfaces,
            ["私たち", "は", "チーム", "の", "連携", "を", "強化", "する", "必要", "が", "あります", "。"]
        )
    }

    func testScreenshotSentenceReadings() {
        let segmenter = makeSegmenter()
        let segments = segmenter.segment("私たちはチームの連携を強化する必要があります。")
        let bySurface = Dictionary(uniqueKeysWithValues: segments.map { ($0.surface, $0) })

        // 后缀并入后读音要跟着拼起来
        XCTAssertEqual(bySurface["私たち"]?.reading, "わたしたち")
        XCTAssertEqual(bySurface["私たち"]?.word?.term, "私")
        XCTAssertEqual(bySurface["チーム"]?.reading, "ちーむ")
        XCTAssertEqual(bySurface["連携"]?.reading, "れんけい")
        XCTAssertEqual(bySurface["強化"]?.reading, "きょうか")

        // 变形段：表记是 あります，词条是 ある，读音是变形后的假名
        XCTAssertEqual(bySurface["あります"]?.kind, .inflection)
        XCTAssertEqual(bySurface["あります"]?.word?.term, "ある")
        XCTAssertEqual(bySurface["あります"]?.reading, "あります")

        // 助词走内置表，没有词条
        XCTAssertEqual(bySurface["は"]?.kind, .particle)
        XCTAssertNil(bySurface["は"]?.word)
        XCTAssertEqual(bySurface["は"]?.reading, "は")
    }

    // MARK: - 变形

    func testMasuStemBeforeNagara() {
        let segmenter = makeSegmenter()
        let surfaces = segmenter.segment("音楽を聞きながら").map(\.surface)
        // 聞き 是 聞く 的ます形词干，要能单独成段，而不是切成 聞 / き
        XCTAssertTrue(surfaces.contains("聞き"), "实际切分：\(surfaces)")
        let segment = segmenter.segment("音楽を聞きながら").first { $0.surface == "聞き" }
        XCTAssertEqual(segment?.kind, .inflection)
        XCTAssertEqual(segment?.word?.term, "聞く")
        XCTAssertEqual(segment?.reading, "きき")
    }

    func testTeFormInflection() {
        let segmenter = makeSegmenter()
        let segment = segmenter.segment("食べてしまいました").first { $0.surface == "食べて" }
        XCTAssertEqual(segment?.kind, .inflection)
        XCTAssertEqual(segment?.word?.term, "食べる")
        XCTAssertEqual(segment?.reading, "たべて")
    }

    func testMasuPastDerivation() {
        let segmenter = makeSegmenter()
        let segment = segmenter.segment("食べてしまいました").first { $0.surface == "しまいました" }
        XCTAssertEqual(segment?.kind, .inflection)
        XCTAssertEqual(segment?.word?.term, "しまう")
        XCTAssertEqual(segment?.reading, "しまいました")
    }

    // MARK: - 未收录 / 标点 / 空白

    func testUnknownKanjiBlockHasNoReading() {
        let segmenter = makeSegmenter()
        let segments = segmenter.segment("大阪で働く")
        let unknown = segments.first { $0.surface == "大阪" }
        XCTAssertNotNil(unknown)
        XCTAssertEqual(unknown?.kind, .unknownKanji)
        XCTAssertNil(unknown?.word)
        // 没有读音就老老实实给 nil，不按音读规则硬猜
        XCTAssertNil(unknown?.reading)
        XCTAssertNil(unknown?.romaji)
        XCTAssertFalse(unknown?.hasDictionaryEntry ?? true)
    }

    func testNaAdjectiveDoesNotSwallowDesu() {
        // 回归：形容动词的「〜で」形一度把「必要です。」切成「必要で｜す」。
        let segmenter = makeSegmenter()
        let surfaces = segmenter.segment("必要です。").map(\.surface)
        XCTAssertEqual(surfaces, ["必要", "です", "。"])
    }

    func testPunctuationIsNotTappable() {
        let segmenter = makeSegmenter()
        let segments = segmenter.segment("必要です。")
        let mark = segments.last
        XCTAssertEqual(mark?.surface, "。")
        XCTAssertEqual(mark?.kind, .punctuation)
        XCTAssertFalse(mark?.isTappable ?? true)
    }

    func testWhitespaceDoesNotProduceSegments() {
        let segmenter = makeSegmenter()
        let segments = segmenter.segment("  必要  です  ")
        XCTAssertFalse(segments.contains { $0.surface.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(segments.map(\.surface), ["必要", "です"])
    }

    // MARK: - 稳定性

    func testSegmentIsCachedAndStable() {
        let segmenter = makeSegmenter()
        let sentence = "私たちはチームの連携を強化する必要があります。"
        let first = segmenter.segment(sentence)
        let second = segmenter.segment(sentence)
        XCTAssertEqual(first, second)
        // id 是句子内序号，ForEach 靠它做唯一标识
        XCTAssertEqual(first.map(\.id), Array(0..<first.count))
    }

    func testEmptyInput() {
        let segmenter = makeSegmenter()
        XCTAssertTrue(segmenter.segment("").isEmpty)
        XCTAssertTrue(segmenter.segment("   ").isEmpty)
    }

    // MARK: - 记忆技巧：拍数

    func testMorae() {
        XCTAssertEqual(MnemonicBuilder.morae("きょうか"), ["きょ", "う", "か"])
        XCTAssertEqual(MnemonicBuilder.morae("がっこう"), ["が", "っ", "こ", "う"])
        XCTAssertEqual(MnemonicBuilder.morae("ちーむ"), ["ち", "ー", "む"])
        XCTAssertEqual(MnemonicBuilder.morae("しゃしん"), ["しゃ", "し", "ん"])
    }

    // MARK: - 记忆技巧：本地生成

    func testLocalMnemonicForVerbHasConjugation() {
        let word = makeWord("食べる", "たべる", "动词(一段)", meaning: "吃")
        let mnemonic = MnemonicBuilder.local(for: word)
        XCTAssertTrue(mnemonic.lines.contains { $0.id == "reading" })
        XCTAssertTrue(mnemonic.lines.contains { $0.id == "pos" })
        XCTAssertTrue(mnemonic.lines.contains { $0.id == "conjugation" })
        XCTAssertLessThanOrEqual(mnemonic.lines.count, 4)
    }

    func testLocalMnemonicNeverEmptyForNoun() {
        let word = makeWord("連携", "れんけい", "名词 / 动词(サ变)", meaning: "合作")
        let mnemonic = MnemonicBuilder.local(for: word)
        XCTAssertFalse(mnemonic.isEmpty)
    }
}
