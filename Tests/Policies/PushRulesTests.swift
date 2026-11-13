import Foundation
import XCTest
@testable import TaoShengPolicies

/// 推送通道与展示用的纯逻辑：每一条都对应过一个真实故障。
final class PushRulesTests: XCTestCase {

    // MARK: - ntfy 地址

    func testNtfyTopicIsAppendedOnceToHost() {
        XCTAssertEqual(PushRules.ntfyURL(url: "https://ntfy.sh", extra: "taosheng")?.absoluteString,
                       "https://ntfy.sh/taosheng")
        XCTAssertEqual(PushRules.ntfyURL(url: "https://ntfy.sh/", extra: "taosheng")?.absoluteString,
                       "https://ntfy.sh/taosheng")
        // 以前会拼成 /taosheng/taosheng
        XCTAssertEqual(PushRules.ntfyURL(url: "https://ntfy.sh/taosheng", extra: "taosheng")?.absoluteString,
                       "https://ntfy.sh/taosheng")
        XCTAssertEqual(PushRules.ntfyURL(url: "", extra: "t")?.absoluteString,
                       "https://ntfy.sh/t")
    }

    func testNtfyURLWithoutTopicIsUsedAsIsButNeedsAPath() {
        XCTAssertEqual(PushRules.ntfyURL(url: "https://ntfy.sh/mytopic", extra: "")?.absoluteString,
                       "https://ntfy.sh/mytopic")
        XCTAssertNil(PushRules.ntfyURL(url: "https://ntfy.sh", extra: ""))
        XCTAssertNil(PushRules.ntfyURL(url: "https://ntfy.sh/", extra: ""))
        XCTAssertNil(PushRules.ntfyURL(url: "", extra: ""))
    }

    // MARK: - 业务错误码

    func testBusinessFailureIsDetectedEvenOnHTTP200() {
        XCTAssertEqual(PushRules.isFailure(kind: "wecom", body: ["errcode": 93000, "errmsg": "invalid webhook url"]),
                       "invalid webhook url")
        XCTAssertNil(PushRules.isFailure(kind: "wecom", body: ["errcode": 0, "errmsg": "ok"]))
        XCTAssertEqual(PushRules.isFailure(kind: "pushplus", body: ["code": 903, "msg": "无效的用户token"]),
                       "无效的用户token")
        XCTAssertNil(PushRules.isFailure(kind: "pushplus", body: ["code": "200"]))
        XCTAssertNotNil(PushRules.isFailure(kind: "telegram", body: ["ok": false, "description": "Unauthorized"]))
        XCTAssertNil(PushRules.isFailure(kind: "telegram", body: ["ok": true]))
        XCTAssertNotNil(PushRules.isFailure(kind: "feishu", body: ["code": 9499]))
        XCTAssertNotNil(PushRules.isFailure(kind: "serverchan", body: ["code": 40001]))
        XCTAssertNotNil(PushRules.isFailure(kind: "bark", body: ["code": 400]))
        // 非 JSON / 没字段：交给 HTTP 状态码判断
        XCTAssertNil(PushRules.isFailure(kind: "wecom", body: nil))
        XCTAssertNil(PushRules.isFailure(kind: "unknown", body: ["code": 1]))
    }

    // MARK: - 截断

    func testClampKeepsTextInsideLimits() {
        XCTAssertEqual(PushRules.clampBytes("短", 4096), "短")
        let long = String(repeating: "好", count: 2000) // 6000 字节
        let cut = PushRules.clampBytes(long, 4096)
        XCTAssertLessThanOrEqual(cut.utf8.count, 4096 + "…（内容过长已截断）".utf8.count)
        XCTAssertTrue(cut.hasSuffix("…（内容过长已截断）"))
        // 不能切出半个汉字
        XCTAssertFalse(cut.contains("\u{FFFD}"))
        XCTAssertEqual(PushRules.clampChars("一二三四五", 3), "一二三…（内容过长已截断）")
        XCTAssertEqual(PushRules.clampChars("一二三", 3), "一二三")
    }

    // MARK: - 周几

    func testWeekNameMatchesCalendarWeekday() {
        XCTAssertEqual(PushRules.weekName(1), "周日")
        XCTAssertEqual(PushRules.weekName(2), "周一")
        XCTAssertEqual(PushRules.weekName(6), "周五")
        XCTAssertEqual(PushRules.weekName(7), "周六")
        XCTAssertEqual(PushRules.weekName(0), "周日")
        // 越界不崩
        XCTAssertEqual(PushRules.weekName(99), "周六")
    }

    // MARK: - 整理退避

    func testDigestRetryDelayBacksOffAndCaps() {
        XCTAssertEqual(PushRules.retryDelay(streak: 0), 300)
        XCTAssertEqual(PushRules.retryDelay(streak: 1), 300)
        XCTAssertEqual(PushRules.retryDelay(streak: 2), 600)
        XCTAssertEqual(PushRules.retryDelay(streak: 3), 1200)
        XCTAssertEqual(PushRules.retryDelay(streak: 20), 3600)
    }

    // MARK: - LIKE 转义

    func testEscapeLikeStopsWildcards() {
        XCTAssertEqual(PushRules.escapeLike("50%"), "50\\%")
        XCTAssertEqual(PushRules.escapeLike("a_b"), "a\\_b")
        XCTAssertEqual(PushRules.escapeLike("c:\\x"), "c:\\\\x")
        XCTAssertEqual(PushRules.escapeLike("正常"), "正常")
    }
}
