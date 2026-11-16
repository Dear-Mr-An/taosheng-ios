import XCTest
@testable import TaoShengPolicies

final class LLMRouteTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(LLMRoute.normalize("  https://api.deepseek.com/ "), "https://api.deepseek.com")
        XCTAssertEqual(LLMRoute.normalize("https://ark.cn-beijing.volces.com/api/v3///"), "https://ark.cn-beijing.volces.com/api/v3")
    }

    func testOfficialDetection() {
        XCTAssertTrue(LLMRoute.isOfficialDeepSeek("https://api.deepseek.com"))
        XCTAssertTrue(LLMRoute.isOfficialDeepSeek("https://api.deepseek.com/"))
        XCTAssertFalse(LLMRoute.isOfficialDeepSeek("https://ark.cn-beijing.volces.com/api/v3"))
        XCTAssertFalse(LLMRoute.isOfficialDeepSeek("https://api.deepseek.com.evil.com"))
        XCTAssertFalse(LLMRoute.isOfficialDeepSeek("http://api.deepseek.com"))
    }

    func testBalanceOnlyOfficial() {
        XCTAssertTrue(LLMRoute.balanceSupported(base: "https://api.deepseek.com"))
        XCTAssertFalse(LLMRoute.balanceSupported(base: "https://api.siliconflow.cn/v1"))
    }

    func testBaseKeepsCustomAndFallsBack() {
        XCTAssertEqual(LLMRoute.resolveBase(stored: "https://api.siliconflow.cn/v1/"), "https://api.siliconflow.cn/v1")
        XCTAssertEqual(LLMRoute.resolveBase(stored: "   "), LLMRoute.deepSeekBase)
    }

    func testModelIsNotForced() {
        XCTAssertEqual(LLMRoute.resolveModel(stored: "qwen-plus", official: false), "qwen-plus")
        XCTAssertEqual(LLMRoute.resolveModel(stored: "deepseek-chat", official: true), "deepseek-chat")
        XCTAssertEqual(LLMRoute.resolveModel(stored: "", official: true), "deepseek-flash")
        XCTAssertEqual(LLMRoute.resolveModel(stored: " ", official: false), "")
    }

    func testChatURL() {
        XCTAssertEqual(LLMRoute.chatURL(base: "https://api.siliconflow.cn/v1")?.absoluteString,
                       "https://api.siliconflow.cn/v1/chat/completions")
        XCTAssertEqual(LLMRoute.chatURL(base: "https://x.test/chat/completions")?.absoluteString,
                       "https://x.test/chat/completions")
    }
}