import XCTest
@testable import TaoShengPolicies

/// 人声检测的纯规则：切窗、前滚、最短人声、回落阈值。
/// 依据原版 `StreamingVad.kt`（512 样本一窗）、`CaptureTuning.kt`（1 秒前滚 / 1 秒最短人声 / RMS 门限）。
final class VadRulesTests: XCTestCase {

    func testChunkSplitsInto512AndKeepsRemainder() {
        var carry: [Float] = []
        let frames = VadRules.chunk([Float](repeating: 0.1, count: 1000), carry: &carry)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 512)
        XCTAssertEqual(carry.count, 488)

        let more = VadRules.chunk([Float](repeating: 0.1, count: 24), carry: &carry)
        XCTAssertEqual(more.count, 1)
        XCTAssertEqual(more[0].count, 512)
        XCTAssertTrue(carry.isEmpty)
    }

    func testChunkHandlesEmptyInputWithoutDroppingCarry() {
        var carry: [Float] = [Float](repeating: 0.2, count: 100)
        let frames = VadRules.chunk([], carry: &carry)
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(carry.count, 100)
    }

    func testPreRollKeepsLastSecondOnly() {
        let samples = (0..<30_000).map { Float($0) }
        let trimmed = VadRules.trimmedPreRoll(samples)
        XCTAssertEqual(trimmed.count, VadRules.preRollSamples)
        XCTAssertEqual(trimmed.first, 14_000)
        XCTAssertEqual(trimmed.last, 29_999)
    }

    func testSpeechNeedsOneSecondOfVoicedAudio() {
        XCTAssertFalse(VadRules.kept(voicedSamples: 15_999, force: false))
        XCTAssertTrue(VadRules.kept(voicedSamples: 16_000, force: false))
        XCTAssertTrue(VadRules.kept(voicedSamples: 0, force: true))
    }

    func testVadVerdictWinsOverEnergy() {
        // 音乐/风扇这类声音音量够，但模型说不像人声 —— 不能开段。
        XCTAssertFalse(VadRules.isSpeech(rms: 0.2, energyThreshold: 0.02, vad: false))
        // 轻声说话模型认得，就别因为音量低丢掉。
        XCTAssertTrue(VadRules.isSpeech(rms: 0.001, energyThreshold: 0.02, vad: true))
    }

    func testFallbackEnergyRespectsRmsGate() {
        // 没有 VAD 时回到能量阈值，但低于 -54 dBFS 的一律当安静。
        XCTAssertFalse(VadRules.isSpeech(rms: 0.001, energyThreshold: 0.0001, vad: nil))
        XCTAssertFalse(VadRules.isSpeech(rms: 0.01, energyThreshold: 0.02, vad: nil))
        XCTAssertTrue(VadRules.isSpeech(rms: 0.03, energyThreshold: 0.02, vad: nil))
    }
}
