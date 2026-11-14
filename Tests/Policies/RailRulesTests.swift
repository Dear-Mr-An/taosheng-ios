import Foundation
import XCTest
@testable import TaoShengPolicies

/// 时间线右侧的小时轴：高亮哪一格由「列表顶部那一行」决定。
/// 这里钉死的是那个筛选算法——直接取所有行 minY 的最大值会永远命中列表最后一条。
final class RailRulesTests: XCTestCase {

    func testPicksRowThatJustPassedTheTop() {
        // a 已经滚出顶部太远、d 还在屏幕下方很远；b/c 里 c 离顶部最近
        let offsets: [String: Double] = ["a": -600, "b": -180, "c": -40, "d": 900]
        XCTAssertEqual(RailRules.activeKey(offsets), "c")
    }

    func testIgnoresRowsBelowTheTop() {
        // 只有下方那些行时不该有高亮（避免把远处的事件算成当前小时）
        let offsets: [String: Double] = ["x": 120, "y": 880]
        XCTAssertNil(RailRules.activeKey(offsets))
    }

    func testIgnoresRowsScrolledFarAbove() {
        let offsets: [String: Double] = ["x": -900, "y": -400]
        XCTAssertNil(RailRules.activeKey(offsets))
    }

    func testAcceptsRowSlightlyAboveTop() {
        // 上滑惯性里顶部那一行会略小于 0，仍然算它
        XCTAssertEqual(RailRules.activeKey(["a": -3]), "a")
        // 再往下一点就不算了（-261 越过 down 边界）
        XCTAssertNil(RailRules.activeKey(["a": -261]))
    }

    func testEmptyMap() {
        XCTAssertNil(RailRules.activeKey([:]))
    }

    /// 回归：0.6.3 的「全部」页把 12 行全算进去，最底下那行 minY 最大，于是永远高亮最后一格。
    func testRegressionLastRowDoesNotWin() {
        var offsets: [String: Double] = [:]
        for i in 0..<12 {
            offsets["row-\(i)"] = Double(i) * 150 - 300   // 首行已滚出顶部，末行在屏幕很下方
        }
        // 旧算法会返回 row-11；正确结果是「已经越过顶部、离顶部最近」的 row-2（minY = 0）
        XCTAssertEqual(RailRules.activeKey(offsets), "row-2")
        XCTAssertNotEqual(RailRules.activeKey(offsets), "row-11")
    }
}