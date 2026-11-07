import XCTest
@testable import JianRiJi

/// 断句单测：长句要按句读切开，短句要原样留着，别被切碎。
final class SpeechTextTests: XCTestCase {

    func testSplitsAtSentenceEnd() {
        let pieces = SpeechText.split("私は学生です。元気です。")
        XCTAssertEqual(pieces, ["私は学生です。", "元気です。"])
    }

    func testKeepsShortTextWhole() {
        XCTAssertEqual(SpeechText.split("こんにちは"), ["こんにちは"])
    }

    func testSplitsAtCommaOnlyWhenLongEnough() {
        // 逗号前不足 6 个字不切，避免「、とても」这种碎片。
        XCTAssertEqual(SpeechText.split("はい、そうです。"), ["はい、そうです。"])
        // 够长就在逗号处断开。
        let pieces = SpeechText.split("昨日は雨でしたが、今日はよく晴れています。")
        XCTAssertEqual(pieces, ["昨日は雨でしたが、", "今日はよく晴れています。"])
    }

    func testLongTextIsSlicedByLimit() {
        let text = String(repeating: "あ", count: 50)
        let pieces = SpeechText.split(text, limit: 24)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces[0].count, 24)
        XCTAssertEqual(pieces[1].count, 24)
        XCTAssertEqual(pieces[2].count, 2)
        XCTAssertEqual(pieces.joined(), text)
    }

    func testEmptyInput() {
        XCTAssertTrue(SpeechText.split("").isEmpty)
        XCTAssertTrue(SpeechText.split("   ").isEmpty)
    }

    func testTrimsWhitespaceAroundPieces() {
        let pieces = SpeechText.split("  はい。  ")
        XCTAssertEqual(pieces, ["はい。"])
    }
}
