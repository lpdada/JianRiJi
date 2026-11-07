import XCTest
@testable import JianRiJi

/// 方括号注音解析 + 分段 Token 生成。用例取自 seed_words.json 的真实数据。
final class ExampleTokenizerTests: XCTestCase {

    // MARK: - BracketFuriganaParser

    func testParseBracketFurigana() {
        let parsed = BracketFuriganaParser.parse("日本[にほん] 一[いち]")
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].surface, "日本")
        XCTAssertEqual(parsed[0].furigana, "にほん")
        XCTAssertEqual(parsed[1].surface, "一")
        XCTAssertEqual(parsed[1].furigana, "いち")
        // 绝不能出现 "[" 本身当一段（旧实现曾把 "[" 当 surface 吐出来）。
        XCTAssertFalse(parsed.contains { $0.surface == "[" })
    }

    func testParseTrailingPlainAfterBracket() {
        let parsed = BracketFuriganaParser.parse("私[わたし]の 祖母[そぼ]は 百[ひゃく] 歳[さい]です")
        XCTAssertEqual(parsed.map(\.surface), ["私", "の", "祖母", "は", "百", "歳", "です"])
        XCTAssertEqual(parsed[0].furigana, "わたし")
        XCTAssertNil(parsed[1].furigana)
        XCTAssertEqual(parsed[2].furigana, "そぼ")
        XCTAssertEqual(parsed[4].furigana, "ひゃく")
        XCTAssertEqual(parsed[5].furigana, "さい")
    }

    func testParseNoBrackets() {
        let parsed = BracketFuriganaParser.parse("がっこうはえきのちかくです。")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].surface, "がっこうはえきのちかくです。")
        XCTAssertNil(parsed[0].furigana)
    }

    func testPlainMatches() {
        XCTAssertTrue(BracketFuriganaParser.plainMatches("日本[にほん] 一[いち]", sentence: "日本一"))
        // 整句假名读音不是例句本身：不能硬套。
        XCTAssertFalse(BracketFuriganaParser.plainMatches("きょうはげつようびです。", sentence: "今日は月曜日です。"))
        // 标点周围的空格差异不算不匹配。
        XCTAssertTrue(BracketFuriganaParser.plainMatches(
            "近[ちか]い 将来[しょうらい] 、 更[さら]に 消費税[しょうひぜい]が 上[あ]がりそうだ",
            sentence: "近い将来 、 更に消費税が上がりそうだ"))
    }

    // MARK: - ExampleTokenizer.tokens

    func testTokensFromBracketFurigana() {
        let tokens = ExampleTokenizer.tokens(sentence: "日本一", furigana: "日本[にほん] 一[いち]")
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].surface, "日本")
        XCTAssertEqual(tokens[0].furigana, "にほん")
        XCTAssertEqual(tokens[0].romaji, "nihon")
        XCTAssertEqual(tokens[1].surface, "一")
        XCTAssertEqual(tokens[1].romaji, "ichi")
    }

    func testTokensWholeKanaReadingFallsBackToParticles() {
        // 注音是整句读音、与例句字形对不上：走助词兜底，且每段 surface 必须来自例句本身。
        let tokens = ExampleTokenizer.tokens(sentence: "今日は月曜日です。", furigana: "きょうはげつようびです。")
        XCTAssertTrue(tokens.allSatisfy { "今日は月曜日です。".contains($0.surface) })
        XCTAssertTrue(tokens.contains { $0.surface == "は" })
    }

    func testTokensGrammarExampleParticleSplit() {
        let tokens = ExampleTokenizer.tokens(sentence: "私は学生です。", reading: "わたしはがくせいです。")
        XCTAssertTrue(tokens.contains { $0.surface == "私" })
        XCTAssertTrue(tokens.contains { $0.surface == "は" && $0.furigana == "は" })
        XCTAssertTrue(tokens.contains { $0.surface == "です" })
        XCTAssertTrue(tokens.contains { $0.surface == "。" && $0.isPunctuation })
        // 假名段自己即读音；汉字段不给读音（不猜）。
        XCTAssertNil(tokens.first { $0.surface == "学生" }?.furigana)
    }

    func testTokensSkipWhitespace() {
        let tokens = ExampleTokenizer.tokens(sentence: "明日、学校へ行きます。")
        XCTAssertFalse(tokens.contains { $0.surface.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertFalse(tokens.contains { $0.surface.contains(" ") })
    }

    // MARK: - Romaji

    func testRomajiSokuonAndLongVowel() {
        XCTAssertEqual(Romaji.romaji(from: "がっこう"), "gakkou")
        XCTAssertEqual(Romaji.romaji(from: "きょう"), "kyou")
        XCTAssertEqual(Romaji.romaji(from: "すーぱー"), "suupaa")
    }
}
