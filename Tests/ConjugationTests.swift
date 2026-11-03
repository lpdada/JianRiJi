import XCTest
@testable import JianRiJi

/// 变形纯函数的单测。种子词表里没有サ变动词，所以サ变用现场构造的 Word 测。
final class ConjugationTests: XCTestCase {

    private func word(term: String, reading: String, pos: String) -> Word {
        Word(
            id: "test-\(term)",
            term: term,
            reading: reading,
            romaji: "",
            meaning: "测试",
            partOfSpeech: pos,
            jlpt: "N5",
            example: nil,
            exampleZh: nil,
            variants: nil,
            note: nil
        )
    }

    // MARK: - 五段

    func testGodanMu() {
        let forms = Conjugation.conjugate(word(term: "飲む", reading: "のむ", pos: "动词(五段)"))
        XCTAssertEqual(forms?.masu, "飲みます")
        XCTAssertEqual(forms?.te, "飲んで")
        XCTAssertEqual(forms?.ta, "飲んだ")
        XCTAssertEqual(forms?.nai, "飲まない")
        XCTAssertEqual(forms?.potential, "飲める")
        XCTAssertEqual(forms?.volitional, "飲もう")
    }

    func testGodanIkuIsSpecial() {
        // 行く的て形 / た形不走く的常规（行いて / 行いた是错的）。
        let forms = Conjugation.conjugate(word(term: "行く", reading: "いく", pos: "动词(五段)"))
        XCTAssertEqual(forms?.masu, "行きます")
        XCTAssertEqual(forms?.te, "行って")
        XCTAssertEqual(forms?.ta, "行った")
        XCTAssertEqual(forms?.nai, "行かない")
        XCTAssertEqual(forms?.potential, "行ける")
        XCTAssertEqual(forms?.volitional, "行こう")
    }

    func testGodanKAndSu() {
        let kaku = Conjugation.conjugate(word(term: "書く", reading: "かく", pos: "动词(五段)"))
        XCTAssertEqual(kaku?.te, "書いて")
        XCTAssertEqual(kaku?.ta, "書いた")
        XCTAssertEqual(kaku?.potential, "書ける")

        let hanasu = Conjugation.conjugate(word(term: "話す", reading: "はなす", pos: "动词(五段)"))
        XCTAssertEqual(hanasu?.te, "話して")
        XCTAssertEqual(hanasu?.ta, "話した")
        XCTAssertEqual(hanasu?.nai, "話さない")
    }

    func testGodanRuIsNotIchidan() {
        // 減る以る结尾，但是五段，词性说了算，不能按词尾猜成一段。
        let forms = Conjugation.conjugate(word(term: "減る", reading: "へる", pos: "动词(五段)"))
        XCTAssertEqual(forms?.masu, "減ります")
        XCTAssertEqual(forms?.te, "減って")
        XCTAssertEqual(forms?.ta, "減った")
        XCTAssertEqual(forms?.potential, "減れる")
        XCTAssertEqual(forms?.volitional, "減ろう")
    }

    // MARK: - 一段 / カ变 / サ变

    func testIchidan() {
        let forms = Conjugation.conjugate(word(term: "食べる", reading: "たべる", pos: "动词(一段)"))
        XCTAssertEqual(forms?.masu, "食べます")
        XCTAssertEqual(forms?.te, "食べて")
        XCTAssertEqual(forms?.ta, "食べた")
        XCTAssertEqual(forms?.nai, "食べない")
        XCTAssertEqual(forms?.potential, "食べられる")
        XCTAssertEqual(forms?.volitional, "食べよう")
    }

    func testKahen() {
        let forms = Conjugation.conjugate(word(term: "来る", reading: "くる", pos: "动词(カ变)"))
        XCTAssertEqual(forms?.masu, "来ます")
        XCTAssertEqual(forms?.te, "来て")
        XCTAssertEqual(forms?.ta, "来た")
        XCTAssertEqual(forms?.nai, "来ない")
        XCTAssertEqual(forms?.potential, "来られる")
        XCTAssertEqual(forms?.volitional, "来よう")
    }

    func testSahenConstructed() {
        // 种子里没有サ变，现场构造测。
        let benkyo = Conjugation.conjugate(word(term: "勉強する", reading: "べんきょうする", pos: "动词(サ变)"))
        XCTAssertEqual(benkyo?.masu, "勉強します")
        XCTAssertEqual(benkyo?.te, "勉強して")
        XCTAssertEqual(benkyo?.ta, "勉強した")
        XCTAssertEqual(benkyo?.nai, "勉強しない")
        XCTAssertEqual(benkyo?.potential, "勉強できる")
        XCTAssertEqual(benkyo?.volitional, "勉強しよう")

        let suru = Conjugation.conjugate(word(term: "する", reading: "する", pos: "动词(サ变)"))
        XCTAssertEqual(suru?.masu, "します")
        XCTAssertEqual(suru?.te, "して")
        XCTAssertEqual(suru?.potential, "できる")
    }

    // MARK: - 形容词

    func testIAdjective() {
        let forms = Conjugation.conjugate(word(term: "大きい", reading: "おおきい", pos: "形容词(い)"))
        XCTAssertEqual(forms?.te, "大きくて")
        XCTAssertEqual(forms?.ta, "大きかった")
        XCTAssertEqual(forms?.nai, "大きくない")
        XCTAssertNil(forms?.masu)
        XCTAssertEqual(forms?.displayRows.map { $0.label }, ["て形", "过去形", "否定形"])
    }

    func testIiIsIrregular() {
        let forms = Conjugation.conjugate(word(term: "いい", reading: "いい", pos: "形容词(い)"))
        XCTAssertEqual(forms?.te, "よくて")
        XCTAssertEqual(forms?.ta, "よかった")
        XCTAssertEqual(forms?.nai, "よくない")
    }

    func testNaAdjective() {
        let shizuka = Conjugation.conjugate(word(term: "静か", reading: "しずか", pos: "形容动词"))
        XCTAssertEqual(shizuka?.te, "静かで")
        XCTAssertEqual(shizuka?.ta, "静かだった")
        XCTAssertEqual(shizuka?.nai, "静かではない")

        // 綺麗以い结尾，但是形容动词，词性说了算，不能按词尾走い形容词。
        let kirei = Conjugation.conjugate(word(term: "綺麗", reading: "きれい", pos: "形容动词"))
        XCTAssertEqual(kirei?.te, "綺麗で")
        XCTAssertEqual(kirei?.ta, "綺麗だった")
        XCTAssertEqual(kirei?.nai, "綺麗ではない")
    }

    // MARK: - 降级：判断不出来就不显示

    func testUndeterminedReturnsNil() {
        XCTAssertNil(Conjugation.conjugate(word(term: "学校", reading: "がっこう", pos: "名词")))
        XCTAssertNil(Conjugation.conjugate(word(term: "何か", reading: "なにか", pos: "未知词性")))
        XCTAssertNil(Conjugation.conjugate(word(term: "test", reading: "test", pos: "动词(五段)")))
    }

    func testVerbDisplayRowsHaveSixForms() {
        let forms = Conjugation.conjugate(word(term: "飲む", reading: "のむ", pos: "动词(五段)"))
        XCTAssertEqual(
            forms?.displayRows.map { $0.label },
            ["ます形", "て形", "た形", "ない形", "可能形", "意志形"]
        )
    }

    // MARK: - 旧 JSON 兼容：没有 variants 键也能解码

    func testWordDecodesWithoutVariants() throws {
        let json = """
        [{"id":"w001","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5","example":"学校まで歩く。","example_zh":"走到学校。"}]
        """.data(using: .utf8)!
        let words = try JSONDecoder().decode([Word].self, from: json)
        XCTAssertNil(words[0].variants)
    }

    func testWordDecodesWithVariants() throws {
        let json = """
        [{"id":"w001","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5","variants":{"复数":"学校たち"}}]
        """.data(using: .utf8)!
        let words = try JSONDecoder().decode([Word].self, from: json)
        XCTAssertEqual(words[0].variants?["复数"], "学校たち")
    }
}
