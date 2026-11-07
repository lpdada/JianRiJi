import XCTest
@testable import JianRiJi

/// 服务器合成 Nanami 的单测：只测纯函数，不碰网络。
final class ServerTTSTests: XCTestCase {

    // MARK: - 地址归一化

    func testEndpointURL() {
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "https://asr.ysloving.com")?.absoluteString,
            "https://asr.ysloving.com/tts"
        )
        // 末尾斜杠
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "https://asr.ysloving.com/")?.absoluteString,
            "https://asr.ysloving.com/tts"
        )
        // 无协议补 https
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "asr.ysloving.com")?.absoluteString,
            "https://asr.ysloving.com/tts"
        )
        // 完整 /tts 不重复补
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "https://asr.ysloving.com/tts")?.absoluteString,
            "https://asr.ysloving.com/tts"
        )
        // 本地 http 放行
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "http://127.0.0.1:18003")?.absoluteString,
            "http://127.0.0.1:18003/tts"
        )
        // 空白与首尾空格
        XCTAssertEqual(
            ServerTTS.endpointURL(for: "  https://asr.ysloving.com  ")?.absoluteString,
            "https://asr.ysloving.com/tts"
        )
    }

    func testEndpointURLInvalid() {
        XCTAssertNil(ServerTTS.endpointURL(for: ""))
        XCTAssertNil(ServerTTS.endpointURL(for: "   "))
        XCTAssertNil(ServerTTS.endpointURL(for: "ftp://example.com"))
        XCTAssertNil(ServerTTS.endpointURL(for: "://"))
        XCTAssertNil(ServerTTS.endpointURL(for: "https://"))
    }

    func testMakeRequestThrowsNotConfiguredForEmptyBase() {
        XCTAssertThrowsError(
            try ServerTTS.makeRequest(baseURL: "", text: "test", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0, timeout: 15)
        ) { error in
            guard let failure = error as? ServerTTS.Failure, case .notConfigured = failure else {
                XCTFail("应为 notConfigured，实际：\(error)")
                return
            }
        }
    }

    func testMakeRequestThrowsInvalidURLForBadBase() {
        XCTAssertThrowsError(
            try ServerTTS.makeRequest(baseURL: "ftp://example.com", text: "test", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0, timeout: 15)
        ) { error in
            guard let failure = error as? ServerTTS.Failure, case .invalidURL = failure else {
                XCTFail("应为 invalidURL，实际：\(error)")
                return
            }
        }
    }

    func testMakeRequestThrowsTooLong() {
        let long = String(repeating: "あ", count: ServerTTS.maxTextLength + 1)
        XCTAssertThrowsError(
            try ServerTTS.makeRequest(baseURL: ServerTTS.defaultBaseURL, text: long, voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0, timeout: 15)
        ) { error in
            guard let failure = error as? ServerTTS.Failure, case .textTooLong = failure else {
                XCTFail("应为 textTooLong，实际：\(error)")
                return
            }
        }
    }

    // MARK: - MP3 嗅探

    func testLooksLikeMP3() {
        // ID3 标签头
        XCTAssertTrue(ServerTTS.looksLikeMP3(Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00])))
        // MPEG 帧同步：0xFF 0xFB
        XCTAssertTrue(ServerTTS.looksLikeMP3(Data([0xFF, 0xFB, 0x90, 0x00])))
        XCTAssertTrue(ServerTTS.looksLikeMP3(Data([0xFF, 0xF3, 0x00, 0x00])))
        // JSON 错误体
        XCTAssertFalse(ServerTTS.looksLikeMP3(Data("{\"detail\":\"error\"}".utf8)))
        // 垃圾数据
        XCTAssertFalse(ServerTTS.looksLikeMP3(Data([0x00, 0x01, 0x02, 0x03])))
        // 太短
        XCTAssertFalse(ServerTTS.looksLikeMP3(Data([0xFF])))
        XCTAssertFalse(ServerTTS.looksLikeMP3(Data()))
    }

    // MARK: - 语速映射

    func testRatePercent() {
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.45), 0)
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.30), -30)
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.60), 30)
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.50), 10)
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.40), -10)
        // 越界夹住
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.20), -50)
        XCTAssertEqual(ServerTTS.ratePercent(forSpeechRate: 0.80), 50)
    }

    // MARK: - 切段

    func testChunksShortText() {
        XCTAssertEqual(ServerTTS.chunks(of: "こんにちは。"), ["こんにちは。"])
        XCTAssertEqual(ServerTTS.chunks(of: "  こんにちは。  "), ["こんにちは。"])
    }

    func testChunksEmpty() {
        XCTAssertTrue(ServerTTS.chunks(of: "").isEmpty)
        XCTAssertTrue(ServerTTS.chunks(of: "   ").isEmpty)
    }

    func testChunksLongText() {
        // 25 句 × 100 字 = 2500 字，每句 100 字整。
        let sentence = String(repeating: "あ", count: 99) + "。"
        let text = String(repeating: sentence, count: 25)
        let chunks = ServerTTS.chunks(of: text)
        XCTAssertTrue(chunks.count > 1, "应切成多段，实际 \(chunks.count) 段")
        XCTAssertTrue(chunks.allSatisfy { $0.count <= ServerTTS.maxTextLength }, "每段都 ≤1000 字")
        XCTAssertEqual(chunks.joined(), text)
    }

    func testChunksHardSplitsSingleLongSentence() {
        let text = String(repeating: "あ", count: 1500)
        let chunks = ServerTTS.chunks(of: text)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 1000)
        XCTAssertEqual(chunks[1].count, 500)
    }

    func testChunksRespectsNewlines() {
        let text = String(repeating: "あ", count: 600) + "\n" + String(repeating: "い", count: 600)
        let chunks = ServerTTS.chunks(of: text)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= ServerTTS.maxTextLength })
    }

    // MARK: - 旧存档解码

    func testOldSettingsJSONDecodesWithDefaultServerURL() throws {
        // 旧存档没有 ttsServerURL 键，应取到默认地址。
        let json = """
        {"dailyGoal": 20, "speechRate": 0.5}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.ttsServerURL, ServerTTS.defaultBaseURL)
        XCTAssertEqual(settings.speechRate, 0.5)
    }

    func testSettingsJSONWithCustomServerURL() throws {
        let json = """
        {"ttsServerURL": "https://example.com"}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.ttsServerURL, "https://example.com")
    }

    func testCacheKeyIsStableAndDistinct() {
        let a = ServerTTSCache.key(text: "こんにちは", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0)
        let b = ServerTTSCache.key(text: "こんにちは", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0)
        let c = ServerTTSCache.key(text: "こんばんは", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 0)
        let d = ServerTTSCache.key(text: "こんにちは", voiceID: ServerTTS.nanamiVoiceID, ratePercent: 10)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
        XCTAssertEqual(a.count, 64)
    }
}
