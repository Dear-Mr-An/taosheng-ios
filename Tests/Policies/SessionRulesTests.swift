import Foundation
import XCTest
@testable import TaoShengPolicies

/// 0.6.0 会议流程里那些「必须钉死」的纯逻辑：
/// 豆包返回怎么解析、说话人怎么编号、老模式怎么迁移、会话状态怎么流转、场景谁说了算。
final class SessionRulesTests: XCTestCase {

    // MARK: - 豆包响应解析

    /// 依据 BytePlus 同源 schema：utterances[].additions 里放说话人，时间给毫秒。
    func testParsesSpeakerFromAdditions() {
        let result: [String: Any] = [
            "utterances": [
                ["text": "第一句", "start_time": 0, "end_time": 1200,
                 "additions": ["speaker": "1"]],
                ["text": "第二句", "start_time": 1200, "end_time": 3500,
                 "additions": ["speaker": "2"]]
            ]
        ]
        let spans = DoubaoResultParser.utterances(fromResult: result)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].speakerRaw, "1")
        XCTAssertEqual(spans[1].speakerRaw, "2")
        // 毫秒换成秒：1200ms 应该是 1.2s
        XCTAssertEqual(spans[1].start, 1.2, accuracy: 0.001)
        XCTAssertEqual(spans[1].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(spans[0].text, "第一句")
    }

    func testFallsBackToTopLevelSpeakerAndAlternateTimeKeys() {
        let result: [String: Any] = [
            "utterances": [
                ["text": "甲", "speaker": "speaker_1", "start": 0.5, "end": 2.0],
                ["text": "乙", "speaker_id": 3, "startTime": 2.0, "endTime": 4.0]
            ]
        ]
        let spans = DoubaoResultParser.utterances(fromResult: result)
        XCTAssertEqual(spans.map(\.speakerRaw), ["speaker_1", "3"])
        XCTAssertEqual(spans[0].start, 0.5, accuracy: 0.001)
        XCTAssertEqual(spans[1].end, 4.0, accuracy: 0.001)
    }

    func testWithoutUtterancesKeepsWholeText() {
        let spans = DoubaoResultParser.utterances(fromResult: ["text": "整段话"])
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].text, "整段话")
        XCTAssertNil(spans[0].speakerRaw)
    }

    // MARK: - 说话人编号

    func testNumberingFollowsFirstAppearance() {
        let spans = [
            UtteranceSpan(speakerRaw: "B", start: 0, end: 1, text: "一"),
            UtteranceSpan(speakerRaw: "A", start: 1, end: 2, text: "二"),
            UtteranceSpan(speakerRaw: "B", start: 2, end: 3, text: "三"),
            UtteranceSpan(speakerRaw: nil, start: 3, end: 4, text: "四")
        ]
        let map = SpeakerRules.numbering(spans)
        XCTAssertEqual(map["B"], 1)
        XCTAssertEqual(map["A"], 2)
        XCTAssertEqual(SpeakerRules.distinctSpeakers(spans), 2)

        let labeled = SpeakerRules.label(spans)
        XCTAssertEqual(labeled.map(\.speaker), ["说话人1", "说话人2", "说话人1", "说话人1"])
    }

    func testDurationsSortedByNumber() {
        let labeled = [
            LabeledSpan(speaker: "说话人2", start: 0, end: 12, text: "a"),
            LabeledSpan(speaker: "说话人1", start: 0, end: 5, text: "b"),
            LabeledSpan(speaker: "说话人2", start: 12, end: 20, text: "c")
        ]
        let d = SpeakerRules.durations(labeled)
        XCTAssertEqual(d.map(\.name), ["说话人1", "说话人2"])
        XCTAssertEqual(d[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(d[1].seconds, 20, accuracy: 0.001)
    }

    // MARK: - 模式与场景

    func testLegacyModesBecomeMeeting() {
        // 0.6.0 删了「日常」：老库里 daily / script / 未知名都不能变成没有模式
        XCTAssertEqual(CaptureMode.restored("daily"), .meeting)
        XCTAssertEqual(CaptureMode.restored("script"), .meeting)
        XCTAssertEqual(CaptureMode.restored("whatever"), .meeting)
        XCTAssertEqual(CaptureMode.restored(""), .meeting)
        XCTAssertEqual(CaptureMode.restored("training"), .training)
        // 0.6.1 起只有会议和培训，通话/日常/脚本一律落到会议
        XCTAssertEqual(CaptureMode.restored("call"), .meeting)
        XCTAssertEqual(CaptureMode.allCases.map(\.rawValue), ["meeting", "training"])
    }

    func testSceneIsDecidedByMode() {
        XCTAssertEqual(SceneRules.scene(forMode: "meeting"), "会议")
        XCTAssertEqual(SceneRules.scene(forMode: "training"), "培训")
        XCTAssertEqual(SceneRules.scene(forMode: "call"), "会议")
        // 模型以前会把会议写成「日常」「工作会议」，现在一律按模式写死
        XCTAssertEqual(SceneRules.scene(forMode: "daily"), "会议")
        XCTAssertEqual(SceneRules.scene(forMode: nil), "会议")
    }

    // MARK: - 会话状态

    func testStateFlowRejectsIllegalMoves() {
        XCTAssertTrue(SessionFlow.canMove(from: .recording, to: .finalizing))
        XCTAssertTrue(SessionFlow.canMove(from: .finalizing, to: .digesting))
        XCTAssertTrue(SessionFlow.canMove(from: .digesting, to: .done))
        // 失败后可以从头补，也可以直接接着整理（已经分好人的情况）
        XCTAssertTrue(SessionFlow.canMove(from: .failed, to: .finalizing))
        XCTAssertTrue(SessionFlow.canMove(from: .failed, to: .digesting))
        // 这几种必须拒绝，否则会出现「跳过录音直接完成」
        XCTAssertFalse(SessionFlow.canMove(from: .recording, to: .done))
        XCTAssertFalse(SessionFlow.canMove(from: .recording, to: .digesting))
        XCTAssertFalse(SessionFlow.canMove(from: .done, to: .recording))
        XCTAssertFalse(SessionFlow.canMove(from: .done, to: .failed))
    }

    func testRecoveryAfterKillFinalizesInsteadOfRecording() {
        // App 被杀之后不可能还在录，只能按已有录音收尾
        XCTAssertEqual(SessionState.recovered("recording"), .finalizing)
        XCTAssertEqual(SessionState.recovered("finalizing"), .finalizing)
        XCTAssertEqual(SessionState.recovered("digesting"), .digesting)
        XCTAssertEqual(SessionState.recovered("done"), .done)
        XCTAssertEqual(SessionState.recovered("failed"), .failed)
        XCTAssertNil(SessionState.recovered("garbage"))
        XCTAssertNil(SessionState.recovered(nil))
    }

    func testSettledOnlyForDoneAndFailed() {
        XCTAssertTrue(SessionState.done.isSettled)
        XCTAssertTrue(SessionState.failed.isSettled)
        XCTAssertFalse(SessionState.recording.isSettled)
        XCTAssertFalse(SessionState.finalizing.isSettled)
        XCTAssertFalse(SessionState.digesting.isSettled)
    }
}
