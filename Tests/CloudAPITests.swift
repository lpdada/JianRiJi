import XCTest
@testable import JianRiJi

/// 云端客户端与进度包的单测：只测纯函数，不碰网络。
final class CloudAPITests: XCTestCase {

    // MARK: - 地址归一化

    func testEndpointURL() {
        XCTAssertEqual(
            CloudAPI.endpointURL(for: "https://api.example.com", path: "/api/health")?.absoluteString,
            "https://api.example.com/api/health"
        )
        // 末尾斜杠
        XCTAssertEqual(
            CloudAPI.endpointURL(for: "https://api.example.com/", path: "/api/sync")?.absoluteString,
            "https://api.example.com/api/sync"
        )
        // 无协议补 https
        XCTAssertEqual(
            CloudAPI.endpointURL(for: "api.example.com", path: "api/team")?.absoluteString,
            "https://api.example.com/api/team"
        )
        // 本地 http 放行
        XCTAssertEqual(
            CloudAPI.endpointURL(for: "http://127.0.0.1:8787", path: "/api/auth/sms")?.absoluteString,
            "http://127.0.0.1:8787/api/auth/sms"
        )
        // 首尾空格
        XCTAssertEqual(
            CloudAPI.endpointURL(for: "  https://api.example.com  ", path: "/api/health")?.absoluteString,
            "https://api.example.com/api/health"
        )
    }

    func testEndpointURLInvalid() {
        XCTAssertNil(CloudAPI.endpointURL(for: "", path: "/api/health"))
        XCTAssertNil(CloudAPI.endpointURL(for: "   ", path: "/api/health"))
        XCTAssertNil(CloudAPI.endpointURL(for: "ftp://example.com", path: "/api/health"))
        XCTAssertNil(CloudAPI.endpointURL(for: "://", path: "/api/health"))
        XCTAssertNil(CloudAPI.endpointURL(for: "https://", path: "/api/health"))
    }

    // MARK: - 手机号

    func testIsValidPhone() {
        XCTAssertTrue(CloudAPI.isValidPhone("13812345678"))
        XCTAssertTrue(CloudAPI.isValidPhone("19900001122"))
        XCTAssertTrue(CloudAPI.isValidPhone(" 13812345678 "))
        XCTAssertFalse(CloudAPI.isValidPhone("12812345678"))
        XCTAssertFalse(CloudAPI.isValidPhone("1381234567"))
        XCTAssertFalse(CloudAPI.isValidPhone("138123456789"))
        XCTAssertFalse(CloudAPI.isValidPhone("1381234567a"))
        XCTAssertFalse(CloudAPI.isValidPhone(""))
    }

    // MARK: - 请求构造

    func testMakeRequestThrowsNotConfiguredForEmptyBase() {
        XCTAssertThrowsError(
            try CloudAPI.makeRequest(baseURL: "", path: "/api/sync", method: "GET", token: nil, body: nil, timeout: 15)
        ) { error in
            guard case CloudAPI.Failure.notConfigured = error else {
                return XCTFail("应报 notConfigured，实际 \(error)")
            }
        }
    }

    func testMakeRequestSetsAuthHeader() throws {
        let request = try CloudAPI.makeRequest(
            baseURL: "https://api.example.com",
            path: "/api/sync",
            method: "PUT",
            token: "tok123",
            body: Data("{}".utf8),
            timeout: 15
        )
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/api/sync")
    }

    func testMakeRequestWithoutTokenHasNoAuthHeader() throws {
        let request = try CloudAPI.makeRequest(
            baseURL: "https://api.example.com",
            path: "/api/health",
            method: "GET",
            token: nil,
            body: nil,
            timeout: 15
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - 进度包拼装

    func testBuildFiltersNewCardsAndCapsLog() {
        var cards: [String: SRSState] = [:]
        var fresh = SRSState()
        fresh.level = 0
        fresh.lastReviewed = nil
        cards["w-fresh"] = fresh
        var touched = SRSState()
        touched.level = 2
        touched.lastReviewed = Date()
        cards["w-touched"] = touched

        var log: [ReviewLogEntry] = []
        for i in 0..<600 {
            log.append(ReviewLogEntry(wordID: "w\(i)", gradeRaw: 2, wasNew: false, at: Date(timeIntervalSince1970: Double(i))))
        }

        let payload = CloudPayload.build(
            cards: cards,
            log: log,
            favorites: ["w-touched"],
            learnedGrammar: ["g1"]
        )
        XCTAssertNil(payload.cards["w-fresh"])
        XCTAssertNotNil(payload.cards["w-touched"])
        XCTAssertEqual(payload.log.count, 500)
        XCTAssertEqual(payload.log.last?.wordID, "w599")
        XCTAssertEqual(payload.favorites, ["w-touched"])
        XCTAssertEqual(payload.learnedGrammar, ["g1"])
        XCTAssertEqual(payload.version, 1)
    }

    // MARK: - 卡片取新

    func testNewerPrefersLaterReview() {
        var old = SRSState()
        old.level = 5
        old.lastReviewed = Date(timeIntervalSince1970: 1000)
        var newer = SRSState()
        newer.level = 1
        newer.lastReviewed = Date(timeIntervalSince1970: 2000)
        XCTAssertEqual(CloudPayload.newer(old, newer).level, 1)
        XCTAssertEqual(CloudPayload.newer(newer, old).level, 1)
    }

    func testNewerPrefersReviewedOverUnreviewed() {
        var reviewed = SRSState()
        reviewed.level = 1
        reviewed.lastReviewed = Date()
        let fresh = SRSState()
        XCTAssertEqual(CloudPayload.newer(reviewed, fresh).level, 1)
        XCTAssertEqual(CloudPayload.newer(fresh, reviewed).level, 1)
    }

    func testNewerTieBreaksByLevel() {
        var low = SRSState()
        low.level = 2
        low.lastReviewed = Date(timeIntervalSince1970: 1000)
        var high = SRSState()
        high.level = 4
        high.lastReviewed = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(CloudPayload.newer(low, high).level, 4)
    }

    // MARK: - 合并

    func testMergeTakesUnionAndDedupesLog() {
        var localCard = SRSState()
        localCard.level = 2
        localCard.lastReviewed = Date(timeIntervalSince1970: 1000)
        var cloudCard = SRSState()
        cloudCard.level = 3
        cloudCard.lastReviewed = Date(timeIntervalSince1970: 2000)
        var local = CloudProgressPayload()
        local.cards = ["w1": localCard]
        local.log = [ReviewLogEntry(wordID: "w1", gradeRaw: 2, wasNew: true, at: Date(timeIntervalSince1970: 100))]
        local.favorites = ["w1"]
        var cloud = CloudProgressPayload()
        cloud.cards = ["w1": cloudCard, "w2": cloudCard]
        cloud.log = local.log
        cloud.learnedGrammar = ["g1"]

        let merged = CloudPayload.merge(local: local, cloud: cloud)
        XCTAssertEqual(merged.cards["w1"]?.level, 3)
        XCTAssertNotNil(merged.cards["w2"])
        XCTAssertEqual(merged.log.count, 1)
        XCTAssertEqual(Set(merged.favorites), ["w1"])
        XCTAssertEqual(merged.learnedGrammar, ["g1"])
    }

    func testEncodeDecodeRoundTrip() {
        var card = SRSState()
        card.level = 3
        card.lastReviewed = Date(timeIntervalSince1970: 1_700_000_000)
        var payload = CloudProgressPayload()
        payload.cards = ["w1": card]
        payload.log = [ReviewLogEntry(wordID: "w1", gradeRaw: 2, wasNew: false, at: Date(timeIntervalSince1970: 500))]
        payload.favorites = ["w1"]
        payload.learnedGrammar = ["g1"]

        guard let data = CloudPayload.encode(payload) else {
            return XCTFail("编码失败")
        }
        XCTAssertLessThan(data.count, CloudAPI.maxPayloadBytes)
        guard let decoded = CloudPayload.decode(data) else {
            return XCTFail("解码失败")
        }
        XCTAssertEqual(decoded.cards["w1"]?.level, 3)
        XCTAssertEqual(decoded.log.count, 1)
        XCTAssertEqual(decoded.favorites, ["w1"])
        XCTAssertEqual(decoded.learnedGrammar, ["g1"])
    }

    func testDecodeToleratesMissingKeys() {
        let json = #"{"version":1}"#.data(using: .utf8)!
        let decoded = CloudPayload.decode(json)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.cards.count, 0)
        XCTAssertEqual(decoded?.log.count, 0)
    }
}
