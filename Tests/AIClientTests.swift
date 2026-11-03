import XCTest
@testable import JianRiJi

final class AIClientTests: XCTestCase {

    func testOpencodeGoDefaults() {
        var settings = AppSettings()
        settings.aiVendor = .opencodeGo
        settings.aiModel = ""
        settings.aiBaseURL = ""
        XCTAssertEqual(AIClient.effectiveModel(settings: settings), "deepseek-v4.1-flash")
        XCTAssertEqual(AIClient.effectiveBaseURL(settings: settings), "https://opencode.ai/zen/go/v1")
    }

    func testCustomOverridesDefaults() {
        var settings = AppSettings()
        settings.aiVendor = .deepseek
        settings.aiModel = "deepseek-reasoner"
        settings.aiBaseURL = "https://example.invalid/v1"
        XCTAssertEqual(AIClient.effectiveModel(settings: settings), "deepseek-reasoner")
        XCTAssertEqual(AIClient.effectiveBaseURL(settings: settings), "https://example.invalid/v1")
    }

    func testCustomVendorRequiresBaseURL() {
        var settings = AppSettings()
        settings.aiVendor = .custom
        settings.aiModel = "some-model"
        settings.aiBaseURL = ""
        XCTAssertNil(AIClient.effectiveBaseURL(settings: settings))
    }
}
