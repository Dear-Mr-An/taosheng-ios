import XCTest
@testable import TaoShengPolicies

final class DigestWindowTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testIdleGate() {
        // 刚说完 5 分钟，但要求停 10 分钟：不整理
        XCTAssertFalse(DigestWindow.ready(lastEnd: base, now: base.addingTimeInterval(300),
                                          idleMin: 10, pendingSegments: 0))
        // 停满 10 分钟：整理
        XCTAssertTrue(DigestWindow.ready(lastEnd: base, now: base.addingTimeInterval(600),
                                         idleMin: 10, pendingSegments: 0))
        // 还有段没转写完：不整理
        XCTAssertFalse(DigestWindow.ready(lastEnd: base, now: base.addingTimeInterval(3600),
                                          idleMin: 10, pendingSegments: 2))
        // 没有录音：可以跑（开机补整理）
        XCTAssertTrue(DigestWindow.ready(lastEnd: nil, now: base, idleMin: 10, pendingSegments: 0))
    }

    func testCapChangesBatchSize() {
        // 0、20、40、70 分钟各一段：30 分钟上限只能带 2 条，60 分钟带 3 条，120 分钟带 4 条
        let starts = [0.0, 20, 40, 70].map { base.addingTimeInterval($0 * 60) }
        XCTAssertEqual(DigestWindow.headCount(starts: starts, capMin: 30), 2)
        XCTAssertEqual(DigestWindow.headCount(starts: starts, capMin: 60), 3)
        XCTAssertEqual(DigestWindow.headCount(starts: starts, capMin: 120), 4)
        XCTAssertEqual(DigestWindow.headCount(starts: [], capMin: 30), 0)
        // 单段就超过上限也要能带一条，不能永远卡住
        let one = [base, base.addingTimeInterval(3 * 3600)]
        XCTAssertEqual(DigestWindow.headCount(starts: one, capMin: 1), 1)
    }
}