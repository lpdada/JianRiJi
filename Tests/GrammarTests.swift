import XCTest
@testable import JianRiJi

final class GrammarTests: XCTestCase {

    func testGrammarPointDecodes() throws {
        let json = """
        [{"id":"g001","level":"N5","title":"〜は〜です","connection":"名词1 + は + 名词2 + です","meaning":"……是……","example":"私は学生です。","exampleReading":"わたしはがくせいです。","exampleZh":"我是学生。","note":"「は」提示主题，读作 wa 不读 ha","tag":"判断句"}]
        """.data(using: .utf8)!
        let points = try JSONDecoder().decode([GrammarPoint].self, from: json)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].level, "N5")
        XCTAssertEqual(points[0].title, "〜は〜です")
        XCTAssertEqual(points[0].exampleZh, "我是学生。")
        XCTAssertEqual(points[0].tag, "判断句")
    }

    func testGrammarPointAllowsMissingOptionalFields() throws {
        let json = """
        [{"id":"g002","level":"N2","title":"〜ざるを得ない"}]
        """.data(using: .utf8)!
        let points = try JSONDecoder().decode([GrammarPoint].self, from: json)
        XCTAssertNil(points[0].meaning)
        XCTAssertNil(points[0].example)
    }

    func testWordDecodesWithNote() throws {
        let json = """
        [{"id":"w001","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5","note":"「学校へ行く」用へ或に都可"}]
        """.data(using: .utf8)!
        let words = try JSONDecoder().decode([Word].self, from: json)
        XCTAssertEqual(words[0].note, "「学校へ行く」用へ或に都可")
        XCTAssertNil(words[0].variants)
    }
}
