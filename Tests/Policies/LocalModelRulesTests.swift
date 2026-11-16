import XCTest
@testable import TaoShengPolicies

final class LocalModelRulesTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(LocalModelRules.percent(received: 0, total: 100), 0)
        XCTAssertEqual(LocalModelRules.percent(received: 50, total: 100), 50)
        XCTAssertEqual(LocalModelRules.percent(received: 1, total: 1000), 1)      // 向上取整
        XCTAssertEqual(LocalModelRules.percent(received: 100, total: 100), 100)
        XCTAssertEqual(LocalModelRules.percent(received: 200, total: 100), 100)   // 不越界
        XCTAssertEqual(LocalModelRules.percent(received: 10, total: 0), 0)
    }

    func testProgressAndSizeText() {
        XCTAssertEqual(LocalModelRules.progressText(received: 68_000_000, total: 239_233_841),
                       "下载 29% · 68/239 MB")
        XCTAssertEqual(LocalModelRules.sizeText(239_233_841), "239 MB")
        XCTAssertEqual(LocalModelRules.sizeText(1_200_000_000), "1.2 GB")
        XCTAssertEqual(LocalModelRules.sizeText(0), "0 MB")
    }

    func testCompleteNeedsBothFiles() {
        XCTAssertTrue(LocalModelRules.isComplete(modelBytes: Int64(LocalModelRules.modelBytes),
                                                 tokensBytes: 315_894))
        // 模型差一个字节都不算完成
        XCTAssertFalse(LocalModelRules.isComplete(modelBytes: Int64(LocalModelRules.modelBytes) - 1,
                                                  tokensBytes: 315_894))
        // tokens 为空 / 超过 1 MB 也不算
        XCTAssertFalse(LocalModelRules.isComplete(modelBytes: Int64(LocalModelRules.modelBytes), tokensBytes: 0))
        XCTAssertFalse(LocalModelRules.isComplete(modelBytes: Int64(LocalModelRules.modelBytes), tokensBytes: 2_000_000))
    }

    func testResumeOffset() {
        XCTAssertEqual(LocalModelRules.resumeOffset(existing: 0, total: 100), 0)
        XCTAssertEqual(LocalModelRules.resumeOffset(existing: 40, total: 100), 40)
        XCTAssertEqual(LocalModelRules.resumeOffset(existing: 100, total: 100), 0)   // 已完整，从头校验
        XCTAssertEqual(LocalModelRules.resumeOffset(existing: 120, total: 100), 0)   // 多出来，重下
    }

    func testPhaseText() {
        XCTAssertEqual(LocalModelRules.phaseText(.absent), "还没下载")
        XCTAssertEqual(LocalModelRules.phaseText(.verifying), "校验文件…")
        XCTAssertEqual(LocalModelRules.phaseText(.ready), "已就绪 · 离网也能转写")
        XCTAssertTrue(LocalModelRules.phaseText(.failed("网络断了")).contains("网络断了"))
    }

    func testSpaceGuard() {
        XCTAssertTrue(LocalModelRules.enoughSpace(free: 400_000_000))
        XCTAssertFalse(LocalModelRules.enoughSpace(free: 200_000_000))
    }
}
