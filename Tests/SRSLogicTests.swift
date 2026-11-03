import XCTest
@testable import JianRiJi

final class SRSLogicTests: XCTestCase {

    // MARK: - 新词

    func testNewWordIsNewBeforeReview() {
        let state = SRSState()
        XCTAssertTrue(state.isNew)
        XCTAssertEqual(state.level, 0)
        XCTAssertEqual(state.mastery, 0, accuracy: 0.0001)
    }

    // MARK: - 评分推进

    func testGoodAdvancesOneStepAndSchedulesOneDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let next = SRS.next(SRSState(), grade: .good, now: now)

        XCTAssertEqual(next.level, 1)
        XCTAssertEqual(next.correct, 1)
        XCTAssertFalse(next.isNew)

        let expected = now.addingTimeInterval(SRS.intervalDays(level: 1, ease: 2.5) * 86_400)
        XCTAssertEqual(next.due.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testEasyJumpsTwoStepsAndRaisesEase() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let next = SRS.next(SRSState(), grade: .easy, now: now)

        XCTAssertEqual(next.level, 2)
        XCTAssertGreaterThan(next.ease, 2.5)
    }

    func testHardKeepsLevelButShortensInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SRSState()
        state.level = 4
        let next = SRS.next(state, grade: .hard, now: now)

        XCTAssertEqual(next.level, 4)
        XCTAssertLessThan(next.ease, state.ease)
        XCTAssertGreaterThan(next.due, now)
    }

    // MARK: - 忘了

    func testAgainDropsTwoLevelsAndReappearsInTenMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SRSState()
        state.level = 5
        let next = SRS.next(state, grade: .again, now: now)

        XCTAssertEqual(next.level, 3)
        XCTAssertEqual(next.wrong, 1)
        XCTAssertEqual(next.due.timeIntervalSince(now), SRS.relearnInterval, accuracy: 1)
    }

    func testAgainNeverGoesBelowZero() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let next = SRS.next(SRSState(), grade: .again, now: now)
        XCTAssertEqual(next.level, 0)
        XCTAssertFalse(next.isNew, "答错过的卡已经不算新词了")
    }

    // MARK: - 边界

    func testLevelIsCappedAtLadderTop() {
        var state = SRSState()
        state.level = SRS.ladders.count - 1
        let next = SRS.next(state, grade: .easy)
        XCTAssertEqual(next.level, SRS.ladders.count - 1)
    }

    func testEaseNeverDropsBelowFloor() {
        var state = SRSState()
        for _ in 0..<40 {
            state = SRS.next(state, grade: .again)
        }
        XCTAssertEqual(state.ease, 1.3, accuracy: 0.0001)
    }

    func testIntervalsGrowWithLevel() {
        var previous = 0.0
        for level in 1..<SRS.ladders.count {
            let days = SRS.intervalDays(level: level, ease: 2.5)
            XCTAssertGreaterThan(days, previous, "台阶 \(level) 的间隔应该比上一级长")
            previous = days
        }
    }

    // MARK: - 词条解码

    func testWordDecodesSeedShape() throws {
        let json = """
        [{"id":"w001","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5","example":"学校まで歩く。","example_zh":"走到学校。"}]
        """.data(using: .utf8)!

        let words = try JSONDecoder().decode([Word].self, from: json)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].partOfSpeech, "名词")
        XCTAssertEqual(words[0].exampleZh, "走到学校。")
        XCTAssertEqual(words[0].displayTitle, "学校（がっこう）")
    }

    func testWordAllowsMissingOptionalFields() throws {
        let json = """
        [{"id":"w002","term":"水","reading":"みず","romaji":"mizu","meaning":"水","pos":"名词","jlpt":"N5"}]
        """.data(using: .utf8)!

        let words = try JSONDecoder().decode([Word].self, from: json)
        XCTAssertNil(words[0].example)
        XCTAssertNil(words[0].exampleZh)
    }
}
