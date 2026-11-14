import Foundation
import XCTest
@testable import TaoShengPolicies

final class FeaturePolicyTests: XCTestCase {
    func testLegacyModesFallBackToMeeting() {
        // 0.6.0 去掉了「日常」：老库里的 daily/script/未知值都必须落到会议，不能变成没有模式
        XCTAssertEqual(CaptureMode.restored("script"), .meeting)
        XCTAssertEqual(CaptureMode.restored("daily"), .meeting)
        XCTAssertEqual(CaptureMode.restored("nonsense"), .meeting)
        XCTAssertEqual(CaptureMode.restored(""), .meeting)
        XCTAssertEqual(CaptureMode.allCases.count, 2)
        XCTAssertEqual(CaptureMode.restored("training").separateSpeakers, false)
        XCTAssertEqual(CaptureMode.restored("call"), .meeting)
    }

    func testDeepSeekMigrationNeverReusesAnotherProvidersKey() {
        let saved = """
        [{"id":"deepseek","baseURL":"https://api.deepseek.com/v1","model":"deepseek-chat","key":"deepseek-saved"}]
        """
        let config = DeepSeekConfiguration.migrated(baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", key: "kimi-key", providersJSON: saved)
        XCTAssertEqual(config.key, "deepseek-saved")
        XCTAssertEqual(config.model, "deepseek-flash")
        let empty = DeepSeekConfiguration.migrated(baseURL: "https://api.deepseek.com.evil.test/v1", model: "deepseek-chat", key: "wrong-key", providersJSON: "")
        XCTAssertTrue(empty.key.isEmpty)
    }

    func testOfficialCurrentKeyTakesPrecedenceAndIsTrimmed() {
        let config = DeepSeekConfiguration.migrated(baseURL: "https://api.deepseek.com/v1/", model: "deepseek-v4-pro", key: " official-key\n", providersJSON: "[]")
        XCTAssertEqual(config.key, "official-key")
        XCTAssertEqual(config.model, "deepseek-v4-pro")
    }

    func testClearedDeepSeekKeyDoesNotResurrectArchivedCredentials() {
        let archived = """
        [{"baseURL":"https://api.deepseek.com","model":"deepseek-flash","key":"old-key"}]
        """
        let config = DeepSeekConfiguration.migrated(baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-pro", key: "", providersJSON: archived, allowLegacyProviders: false)
        XCTAssertTrue(config.key.isEmpty)
        XCTAssertEqual(config.model, "deepseek-v4-pro")
    }

    func testBalancePrefersCNYAndKeepsAvailabilityAndGrantedAmount() throws {
        let data = Data("""
        {"is_available":false,"balance_infos":[
          {"currency":"USD","total_balance":"9.00","granted_balance":"0","topped_up_balance":"9.00"},
          {"currency":"CNY","total_balance":"3.25","granted_balance":"1.25","topped_up_balance":"2.00"}
        ]}
        """.utf8)
        let balance = try DeepSeekBalance.parse(data)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.total, Decimal(string: "3.25"))
        XCTAssertEqual(balance.granted, Decimal(string: "1.25"))
        XCTAssertFalse(balance.available)
        XCTAssertTrue(balance.isLow(threshold: 10))
    }

    func testMalformedBalanceIsAnErrorNotZeroAndUSDHasNoCNYWarning() throws {
        XCTAssertThrowsError(try DeepSeekBalance.parse(Data("{\"balance_infos\":[]}".utf8)))
        XCTAssertThrowsError(try DeepSeekBalance.parse(Data("{\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"NaN\"}]}".utf8)))
        let balance = try DeepSeekBalance.parse(Data("{\"is_available\":true,\"balance_infos\":[{\"currency\":\"USD\",\"total_balance\":\"0.50\"}]}".utf8))
        XCTAssertFalse(balance.isLow(threshold: 10))
    }

    func testCancelledPermissionStartCannotBecomeActiveLater() {
        var session = VoiceSessionState()
        let old = session.begin()
        XCTAssertTrue(session.isCurrent(old))
        session.cancel()
        XCTAssertFalse(session.isCurrent(old))
        let next = session.begin()
        XCTAssertFalse(session.isCurrent(old))
        XCTAssertTrue(session.isCurrent(next))
    }

    func testScheduleHonorsDisabledIntervalAndDailyTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: false, byInterval: true, intervalMinutes: 30, hour: 21, now: now, lastRun: nil))
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, byInterval: true, intervalMinutes: 30, hour: 21, now: now, lastRun: now.addingTimeInterval(-60)))
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, byInterval: true, intervalMinutes: 30, hour: 21, now: now, lastRun: now.addingTimeInterval(-1800)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 21))!
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, byInterval: false, intervalMinutes: 30, hour: 21, now: evening.addingTimeInterval(-60), lastRun: nil, calendar: calendar))
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, byInterval: false, intervalMinutes: 30, hour: 21, now: evening, lastRun: nil, calendar: calendar))
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, byInterval: false, intervalMinutes: 30, hour: 21, now: evening, lastRun: evening.addingTimeInterval(-11 * 3600), calendar: calendar))
        XCTAssertTrue(DigestSchedule.shouldRun(enabled: true, byInterval: false, intervalMinutes: 30, hour: 21, now: evening.addingTimeInterval(86400), lastRun: evening, calendar: calendar))
        XCTAssertFalse(DigestSchedule.shouldRun(enabled: true, byInterval: false, intervalMinutes: 30, hour: 21, now: evening.addingTimeInterval(60), lastRun: evening, calendar: calendar))
    }
}
