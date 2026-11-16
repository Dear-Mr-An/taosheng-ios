import Foundation
import XCTest
@testable import TaoShengPolicies

/// 0.8.0：暂停的跨进程恢复。杀掉 App 再打开时，到期的暂停必须自己把录音拉回来。
final class QuietRulesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    func testStillPausedBeforeDeadline() {
        let until = now.addingTimeInterval(600)
        XCTAssertEqual(QuietRules.onLaunch(savedUntil: until, heldByPause: true, now: now),
                       .stillPaused(until: until))
    }

    func testExpiredPauseResumesWhenHeldByPause() {
        // 关键回归：暂停 15 分钟 → 杀 App → 过期后重开，必须恢复录音
        let until = now.addingTimeInterval(-60)
        XCTAssertEqual(QuietRules.onLaunch(savedUntil: until, heldByPause: true, now: now),
                       .expiredResume)
    }

    func testExpiredWithoutHoldDoesNotStartRecording() {
        // 同一个键被别的流程写坏时，不能因为过期就擅自打开麦克风
        let until = now.addingTimeInterval(-60)
        XCTAssertEqual(QuietRules.onLaunch(savedUntil: until, heldByPause: false, now: now), .idle)
    }

    func testNoSavedDeadlineIsIdle() {
        XCTAssertEqual(QuietRules.onLaunch(savedUntil: nil, heldByPause: true, now: now), .idle)
    }

    func testDeadlineExactlyNowCountsAsExpired() {
        XCTAssertEqual(QuietRules.onLaunch(savedUntil: now, heldByPause: true, now: now),
                       .expiredResume)
    }
}
