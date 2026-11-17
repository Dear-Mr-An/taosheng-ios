import XCTest
@testable import TaoShengPolicies

/// 认人的两条判据：过阈值、并且和第二名拉开差距。
final class SpeakerNameTests: XCTestCase {

    func testAboveThresholdWithClearLeadNamesThePerson() {
        let scores = [(id: "a", score: 0.90), (id: "b", score: 0.70)]
        let hit = SpeakerRules.bestName(scores, threshold: 0.82)
        XCTAssertEqual(hit?.id, "a")
        XCTAssertEqual(hit?.score ?? 0, 0.90, accuracy: 1e-9)
    }

    func testBelowThresholdStaysUnnamed() {
        let scores = [(id: "a", score: 0.81), (id: "b", score: 0.40)]
        XCTAssertNil(SpeakerRules.bestName(scores, threshold: 0.82))
    }

    func testTwoCloseCandidatesStaysUnnamed() {
        // 0.90 与 0.85 差 0.05，不到 0.08：认错人比不认更糟
        let scores = [(id: "a", score: 0.90), (id: "b", score: 0.85)]
        XCTAssertNil(SpeakerRules.bestName(scores, threshold: 0.82))
    }

    func testSingleCandidateOnlyNeedsThreshold() {
        XCTAssertEqual(SpeakerRules.bestName([(id: "a", score: 0.83)], threshold: 0.82)?.id, "a")
        XCTAssertNil(SpeakerRules.bestName([], threshold: 0.82))
    }
}
