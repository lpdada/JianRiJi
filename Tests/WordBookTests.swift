import XCTest
@testable import JianRiJi

/// 词书系统与语法学会标记的单测。Store 是 @MainActor，
/// 所以整个类标 @MainActor；这里不依赖 Bundle 里的 JSON，
/// 只测不依赖已加载数据的纯逻辑与回退路径。
@MainActor
final class WordBookTests: XCTestCase {

    private func word(jlpt: String, book: String? = nil, tags: [String]? = nil) -> Word {
        Word(
            id: "test-\(jlpt)-\(book ?? "none")",
            term: "测试",
            reading: "てすと",
            romaji: "tesuto",
            meaning: "测试",
            partOfSpeech: "名词",
            jlpt: jlpt,
            example: nil,
            exampleZh: nil,
            variants: nil,
            note: nil,
            exampleFurigana: nil,
            book: book,
            tags: tags
        )
    }

    private func book(
        id: String = "b1",
        filterType: String,
        filterValue: String? = nil
    ) -> WordBook {
        WordBook(
            id: id,
            title: "测试词书",
            badge: "测",
            categories: ["常用词单"],
            author: "简日记",
            note: "测试",
            filterType: filterType,
            filterValue: filterValue,
            tint: 0
        )
    }

    private func grammarPoint(
        title: String = "〜は〜です",
        meaning: String? = "〜是〜",
        connection: String? = "名词1 は 名词2 です",
        note: String? = "は读作 wa",
        exampleReading: String? = "は…です",
        tag: String? = "判断",
        example: String? = "私は学生です。"
    ) -> GrammarPoint {
        GrammarPoint(
            id: "g-test",
            level: "N5",
            title: title,
            connection: connection,
            meaning: meaning,
            example: example,
            exampleReading: exampleReading,
            exampleZh: "我是学生。",
            note: note,
            tag: tag,
            examples: nil
        )
    }

    // MARK: - resolvedBook 兜底

    func testResolvedBookFallbackByJlpt() {
        XCTAssertEqual(word(jlpt: "N5").resolvedBook, "初级上")
        XCTAssertEqual(word(jlpt: "N4").resolvedBook, "初级下")
        XCTAssertEqual(word(jlpt: "N3").resolvedBook, "中级")
        XCTAssertEqual(word(jlpt: "N2").resolvedBook, "高级")
        XCTAssertEqual(word(jlpt: "N1").resolvedBook, "高级")
    }

    func testResolvedBookExplicitWinsOverFallback() {
        XCTAssertEqual(word(jlpt: "N5", book: "我的课").resolvedBook, "我的课")
        // 空字符串当没写，走兜底。
        XCTAssertEqual(word(jlpt: "N5", book: "").resolvedBook, "初级上")
    }

    // MARK: - WordBook.matches

    func testWordBookMatches() {
        XCTAssertTrue(book(filterType: "all").matches(word(jlpt: "N5")))
        XCTAssertTrue(book(filterType: "book", filterValue: "初级上").matches(word(jlpt: "N5")))
        XCTAssertFalse(book(filterType: "book", filterValue: "初级下").matches(word(jlpt: "N5")))
        XCTAssertTrue(book(filterType: "jlpt", filterValue: "N5").matches(word(jlpt: "N5")))
        XCTAssertFalse(book(filterType: "jlpt", filterValue: "N4").matches(word(jlpt: "N5")))
        XCTAssertTrue(book(filterType: "tag", filterValue: "日常").matches(word(jlpt: "N5", tags: ["日常", "食物"])))
        XCTAssertFalse(book(filterType: "tag", filterValue: "日常").matches(word(jlpt: "N5")))
        XCTAssertFalse(book(filterType: "tag", filterValue: nil).matches(word(jlpt: "N5", tags: ["日常"])))
    }

    // MARK: - currentBook 回退

    func testCurrentBookFallsBackToAll() {
        let store = Store()
        XCTAssertEqual(store.currentBook.id, WordBook.allID)
        XCTAssertEqual(store.currentBook.title, "全部词本")
        // 旧存档的 JLPT 级别值匹配不到任何词书，同样回到全部词本。
        store.settings.deckFilter = "N5"
        XCTAssertEqual(store.currentBook.id, WordBook.allID)
    }

    func testSelectBookWritesDeckFilter() {
        let store = Store()
        let target = book(id: "jlpt-n5", filterType: "jlpt", filterValue: "N5")
        store.selectBook(target)
        XCTAssertEqual(store.settings.deckFilter, "jlpt-n5")
    }

    // MARK: - 语法学会标记幂等

    func testMarkGrammarLearnedIsIdempotent() {
        let store = Store()
        let point = grammarPoint()
        XCTAssertFalse(store.isGrammarLearned(point))
        store.markGrammarLearned(point)
        store.markGrammarLearned(point)
        XCTAssertTrue(store.isGrammarLearned(point))
        // 计数来自已加载的语法点，单测里没加载数据，所以是 0；
        // 这里只确认重复标记没有让计数凭空变多。
        XCTAssertEqual(store.learnedGrammarCount(forLevel: "N5"), 0)
    }

    // MARK: - 语法搜索五字段

    func testGrammarMatchesFiveFields() {
        let point = grammarPoint()
        XCTAssertTrue(point.matches(query: "は〜です"))
        XCTAssertTrue(point.matches(query: "是"))
        XCTAssertTrue(point.matches(query: "名词1"))
        XCTAssertTrue(point.matches(query: "wa"))
        XCTAssertTrue(point.matches(query: "は…です"))
        XCTAssertTrue(point.matches(query: "判断"))
        XCTAssertFalse(point.matches(query: "不存在的词"))
    }

    // MARK: - 解码：新字段缺键即 nil（不能给默认值）

    func testWordDecodesWithoutBookAndTags() throws {
        let json = """
        {"id":"w1","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5"}
        """
        let decoded = try JSONDecoder().decode(Word.self, from: Data(json.utf8))
        XCTAssertNil(decoded.book)
        XCTAssertNil(decoded.tags)
        XCTAssertEqual(decoded.resolvedBook, "初级上")
    }

    func testWordDecodesWithBookAndTags() throws {
        let json = """
        {"id":"w1","term":"学校","reading":"がっこう","romaji":"gakkou","meaning":"学校","pos":"名词","jlpt":"N5","book":"初级上","tags":["日常"]}
        """
        let decoded = try JSONDecoder().decode(Word.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.book, "初级上")
        XCTAssertEqual(decoded.tags, ["日常"])
    }

    func testGrammarDecodesExamplesArray() throws {
        let json = """
        {"id":"g1","level":"N5","title":"〜は〜です","examples":[{"ja":"私は学生です。","zh":"我是学生。"},{"ja":"彼は先生です。","zh":"他是老师。"}]}
        """
        let decoded = try JSONDecoder().decode(GrammarPoint.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.examples?.count, 2)
        XCTAssertEqual(decoded.examples?.first?.ja, "私は学生です。")
    }

    func testGrammarDecodesWithoutExamples() throws {
        let json = """
        {"id":"g1","level":"N5","title":"〜は〜です"}
        """
        let decoded = try JSONDecoder().decode(GrammarPoint.self, from: Data(json.utf8))
        XCTAssertNil(decoded.examples)
    }

    func testWordBookDecodesBooksShape() throws {
        let json = """
        {"id":"chuji-shang","title":"初级上","badge":"初上","categories":["常用词单"],"author":"简日记","note":"N5 归到这里","filterType":"book","filterValue":"初级上","tint":1}
        """
        let decoded = try JSONDecoder().decode(WordBook.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.filterValue, "初级上")
        XCTAssertTrue(decoded.matches(word(jlpt: "N5")))
    }
}
