import Foundation
import XCTest
@testable import TaoShengPolicies

/// 0.6.5「什么时候整理」三档：转写完就整理（默认）/ 按间隔 / 按时间点。
final class DigestTimingTests: XCTestCase {
    func testDefaultsToAfterTranscribe() {
        // 老版本没有这个键、或者存了脏值，都要落到第一档，不能变成「什么都不整理」
        XCTAssertEqual(DigestTiming.restored(nil), .afterTranscribe)
        XCTAssertEqual(DigestTiming.restored(""), .afterTranscribe)
        XCTAssertEqual(DigestTiming.restored("nonsense"), .afterTranscribe)
        XCTAssertEqual(DigestTiming.restored("interval"), .interval)
        XCTAssertEqual(DigestTiming.restored("clock"), .clock)
        XCTAssertEqual(DigestTiming.allCases.count, 3)
        // 界面上第一档就是默认档
        XCTAssertEqual(DigestTiming.allCases.first, .afterTranscribe)
    }

    func testMigratesLegacyIntervalFlag() {
        // 0.6.4 及以前只存 digestByInterval：true 是旧默认（等于没选过），false 是用户主动选的按时间点
        XCTAssertEqual(DigestTiming.migrated(byInterval: nil), .afterTranscribe)
        XCTAssertEqual(DigestTiming.migrated(byInterval: true), .afterTranscribe)
        XCTAssertEqual(DigestTiming.migrated(byInterval: false), .clock)
    }

    func testTimerOnlyRunsForIntervalAndClock() {
        XCTAssertFalse(DigestTiming.afterTranscribe.usesTimer)
        XCTAssertTrue(DigestTiming.interval.usesTimer)
        XCTAssertTrue(DigestTiming.clock.usesTimer)
    }

    func testTriggerNeedsTimingTextKeyAndIdle() {
        XCTAssertTrue(DigestTrigger.afterTranscribe(timing: .afterTranscribe, newText: true,
                                                    hasKey: true, working: false))
        // 四个条件缺任何一个都不该动大模型
        XCTAssertFalse(DigestTrigger.afterTranscribe(timing: .interval, newText: true,
                                                     hasKey: true, working: false))
        XCTAssertFalse(DigestTrigger.afterTranscribe(timing: .clock, newText: true,
                                                     hasKey: true, working: false))
        XCTAssertFalse(DigestTrigger.afterTranscribe(timing: .afterTranscribe, newText: false,
                                                     hasKey: true, working: false))
        XCTAssertFalse(DigestTrigger.afterTranscribe(timing: .afterTranscribe, newText: true,
                                                     hasKey: false, working: false))
        XCTAssertFalse(DigestTrigger.afterTranscribe(timing: .afterTranscribe, newText: true,
                                                     hasKey: true, working: true))
    }

    func testScheduleNeverRunsTimerInAfterTranscribe() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 21))!

        // 第一档靠「转写完」事件驱动，定时器一律不跑，否则等于又变回按间隔整理
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, timing: .afterTranscribe,
                                                intervalMinutes: 5, hour: 21, now: now,
                                                lastRun: nil, calendar: calendar))
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, timing: .afterTranscribe,
                                                intervalMinutes: 5, hour: 21, now: now,
                                                lastRun: now.addingTimeInterval(-86400), calendar: calendar))

        // 按间隔：和 0.6.4 行为一致（5 分钟到了就该跑）
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, timing: .interval,
                                               intervalMinutes: 5, hour: 21, now: now,
                                               lastRun: now.addingTimeInterval(-301), calendar: calendar))
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, timing: .interval,
                                                intervalMinutes: 5, hour: 21, now: now,
                                                lastRun: now.addingTimeInterval(-120), calendar: calendar))
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: false, timing: .interval,
                                                intervalMinutes: 5, hour: 21, now: now,
                                                lastRun: now.addingTimeInterval(-86400), calendar: calendar))

        // 按时间点：到了 21:00 且今天还没跑过才跑
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, timing: .clock,
                                               intervalMinutes: 5, hour: 21, now: now,
                                               lastRun: nil, calendar: calendar))
        // 21:00 之后已经跑过一次：今天不再跑
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, timing: .clock,
                                                intervalMinutes: 5, hour: 21, now: now,
                                                lastRun: now.addingTimeInterval(60), calendar: calendar))
        // 还没到 21:00：不跑
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, timing: .clock,
                                                intervalMinutes: 5, hour: 21,
                                                now: now.addingTimeInterval(-120), lastRun: nil,
                                                calendar: calendar))
    }
}
