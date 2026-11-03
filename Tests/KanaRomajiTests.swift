import XCTest
@testable import JianRiJi

final class KanaRomajiTests: XCTestCase {

    func testBasicAndLongVowels() {
        XCTAssertEqual(KanaRomaji.romaji(for: "がっこう"), "gakkou")
        XCTAssertEqual(KanaRomaji.romaji(for: "たべる"), "taberu")
        XCTAssertEqual(KanaRomaji.romaji(for: "きゅう"), "kyuu")
        XCTAssertEqual(KanaRomaji.romaji(for: "じゅんび"), "junbi")
        XCTAssertEqual(KanaRomaji.romaji(for: "みっつ"), "mittsu")
    }

    func testScreenshotSegments() {
        // 截图里那句的各段读音，は → ha、を → wo，与截图一致。
        XCTAssertEqual(KanaRomaji.romaji(for: "すうがく"), "suugaku")
        XCTAssertEqual(KanaRomaji.romaji(for: "もんだい"), "mondai")
        XCTAssertEqual(KanaRomaji.romaji(for: "とく"), "toku")
        XCTAssertEqual(KanaRomaji.romaji(for: "たのしい"), "tanoshii")
        XCTAssertEqual(KanaRomaji.romaji(for: "です"), "desu")
        XCTAssertEqual(KanaRomaji.romaji(for: "は"), "ha")
        XCTAssertEqual(KanaRomaji.romaji(for: "を"), "wo")
    }

    func testForeignSoundsAndKatakana() {
        XCTAssertEqual(KanaRomaji.romaji(for: "そふぁー"), "sofaa")
        XCTAssertEqual(KanaRomaji.romaji(for: "こーひー"), "koohii")
        XCTAssertEqual(KanaRomaji.romaji(for: "ちぇっく"), "chekku")
        XCTAssertEqual(KanaRomaji.romaji(for: "ソファー"), "sofaa")
    }

    func testAnnotatedExampleSegmented() {
        let segments = AnnotatedExample.parse("ぼくは 数学[すうがく]が 不得意[ふとくい]だ")
        XCTAssertEqual(segments.map { $0.text }, ["ぼくは", "数学", "が", "不得意", "だ"])
        XCTAssertEqual(segments.map { $0.reading }, ["ぼくは", "すうがく", "が", "ふとくい", "だ"])
        XCTAssertEqual(segments.map { $0.romaji }, ["bokuha", "suugaku", "ga", "futokui", "da"])
    }

    func testAnnotatedExampleWholeSentenceReturnsEmpty() {
        // 整句读音不带 [，调用方改用整句显示，不按段拆。
        XCTAssertTrue(AnnotatedExample.parse("がっこうはえきのちかくです。").isEmpty)
    }
}
