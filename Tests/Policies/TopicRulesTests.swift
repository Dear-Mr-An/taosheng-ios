import XCTest
@testable import TaoShengPolicies

final class TopicRulesTests: XCTestCase {
    func testEndAtFromMinutes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(TopicRules.endAt(start: start, minutes: 30), start.addingTimeInterval(1800))
        XCTAssertEqual(TopicRules.endAt(start: start, minutes: 120), start.addingTimeInterval(7200))
    }

    func testEndAtNilWhenManual() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(TopicRules.endAt(start: start, minutes: 0))
        XCTAssertNil(TopicRules.endAt(start: start, minutes: -5))
    }

    func testAutoFinishOnlyWhenPassed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = TopicRules.endAt(start: start, minutes: 30)!
        XCTAssertFalse(TopicRules.shouldAutoFinish(endAt: end, now: start.addingTimeInterval(1799), isRecording: true))
        XCTAssertTrue(TopicRules.shouldAutoFinish(endAt: end, now: end, isRecording: true))
        XCTAssertFalse(TopicRules.shouldAutoFinish(endAt: end, now: end, isRecording: false))
        XCTAssertFalse(TopicRules.shouldAutoFinish(endAt: nil, now: end, isRecording: true))
    }

    func testDisplayNameFallsBackToKind() {
        XCTAssertEqual(TopicRules.displayName("  ", kind: "会议"), "会议")
        XCTAssertEqual(TopicRules.displayName(" 产品讨论会 ", kind: "会议"), "产品讨论会")
    }
}