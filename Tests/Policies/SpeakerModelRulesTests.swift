import XCTest
@testable import TaoShengPolicies

final class SpeakerModelRulesTests: XCTestCase {
    func testModelIsPinned() {
        XCTAssertEqual(SpeakerModelRules.modelBytes, 28_281_138)
        XCTAssertEqual(SpeakerModelRules.modelSHA256.count, 64)
        XCTAssertEqual(SpeakerModelRules.embeddingDim, 192)
        XCTAssertTrue(SpeakerModelRules.isComplete(bytes: 28_281_138))
        XCTAssertFalse(SpeakerModelRules.isComplete(bytes: 28_281_137))
    }

    func testThresholdDependsOnDimension() {
        XCTAssertEqual(SpeakerModelRules.threshold(forDim: 192), 0.65)
        XCTAssertEqual(SpeakerModelRules.threshold(forDim: 48), 0.82)
        XCTAssertEqual(SpeakerModelRules.clusterThreshold(forDim: 192), 0.70)
        XCTAssertEqual(SpeakerModelRules.clusterThreshold(forDim: 48), 0.80)
        XCTAssertTrue(SpeakerModelRules.needsRebuild(storedDim: 48))
        XCTAssertFalse(SpeakerModelRules.needsRebuild(storedDim: 192))
    }

    func testWindowStarts() {
        // 不足 1.5 秒不取样
        XCTAssertEqual(SpeakerModelRules.windowStarts(totalSamples: 23_999), [])
        // 1.5 秒到 3 秒：整段一个窗
        XCTAssertEqual(SpeakerModelRules.windowStarts(totalSamples: 24_000), [0])
        XCTAssertEqual(SpeakerModelRules.windowStarts(totalSamples: 48_000), [0])
        // 刚好超过一个窗也还是一个
        XCTAssertEqual(SpeakerModelRules.windowStarts(totalSamples: 48_001), [0])
        // 30 秒最多取 8 个窗，最后一个贴着结尾
        let starts = SpeakerModelRules.windowStarts(totalSamples: 30 * 16_000)
        XCTAssertEqual(starts.count, 8)
        XCTAssertEqual(starts.first, 0)
        XCTAssertEqual(starts.last, 30 * 16_000 - 3 * 16_000)
        XCTAssertEqual(starts, starts.sorted())
    }

    func testDownloadPieces() {
        XCTAssertEqual(SpeakerModelRules.percent(received: 14_000_000, total: 28_281_138), 50)
        XCTAssertEqual(SpeakerModelRules.percent(received: 0, total: 0), 0)
        XCTAssertEqual(SpeakerModelRules.progressText(received: 14_000_000, total: 28_281_138),
                       "下载 50% · 14/28 MB")
        XCTAssertTrue(SpeakerModelRules.enoughSpace(free: 100_000_000))
        XCTAssertFalse(SpeakerModelRules.enoughSpace(free: 50_000_000))
        XCTAssertTrue(SpeakerModelRules.phaseText(.ready).contains("192"))
        XCTAssertTrue(SpeakerModelRules.phaseText(.absent).contains("48"))
    }
}
