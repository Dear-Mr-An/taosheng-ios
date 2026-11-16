import XCTest
@testable import TaoShengPolicies

final class LocationStatsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testTotalsSplitHomeAndAway() {
        let visits = [
            LocationStats.Visit(arriveAt: t0, leaveAt: t0.addingTimeInterval(3600), isHome: true, latitude: 31.2, longitude: 121.4),
            LocationStats.Visit(arriveAt: t0.addingTimeInterval(3600), leaveAt: t0.addingTimeInterval(5400), isHome: false, latitude: 31.23, longitude: 121.47)
        ]
        let t = LocationStats.totals(visits)
        XCTAssertEqual(t.homeMinutes, 60)
        XCTAssertEqual(t.awayMinutes, 30)
        XCTAssertGreaterThan(t.kilometers, 1.0)
        XCTAssertLessThan(t.kilometers, 12.0)
    }

    func testEmptyAndSamePoint() {
        XCTAssertEqual(LocationStats.totals([]), LocationStats.Totals(homeMinutes: 0, awayMinutes: 0, kilometers: 0))
        XCTAssertEqual(LocationStats.distance(31.2, 121.4, 31.2, 121.4), 0, accuracy: 0.001)
    }

    func testZeroDurationIgnored() {
        let v = LocationStats.Visit(arriveAt: t0, leaveAt: t0, isHome: true, latitude: 1, longitude: 1)
        XCTAssertEqual(LocationStats.totals([v]).homeMinutes, 0)
    }
}