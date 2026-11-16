import XCTest
@testable import TaoShengPolicies

final class ASRRulesTests: XCTestCase {
    func testKindRoundTrip() {
        for i in 0..<ASRRules.kindIndex.count {
            XCTAssertEqual(ASRRules.index(kind: ASRRules.kind(index: i)), i)
        }
        XCTAssertEqual(ASRRules.kind(index: 9), "doubao")
        XCTAssertEqual(ASRRules.index(kind: "unknown"), 0)
    }

    func testCadenceMapping() {
        XCTAssertEqual(ASRRules.cadenceIndex(minutes: 1), 0)
        XCTAssertEqual(ASRRules.cadenceIndex(minutes: 15), 1)
        XCTAssertEqual(ASRRules.cadenceIndex(minutes: 30), 2)
        XCTAssertEqual(ASRRules.cadenceIndex(minutes: 45), 3)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 0, custom: 45), 1)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 1, custom: 45), 15)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 2, custom: 45), 30)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 3, custom: 45), 45)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 3, custom: 1), 5)
    }

    func testPushTodoRules() {
        XCTAssertFalse(PushGate.shouldPushTodo(enabled: false, categories: ["待办"]))
        XCTAssertFalse(PushGate.shouldPushTodo(enabled: true, categories: ["事件"]))
        XCTAssertTrue(PushGate.shouldPushTodo(enabled: true, categories: ["事件", "待办"]))
        XCTAssertEqual(PushGate.todoItems(["事件", "约定", "灵感"]), [1, 2])
    }

    func testWipeCoversAllSecrets() {
        XCTAssertEqual(WipeRules.secrets.sorted(), ["asrKey", "backupPass", "doubaoApiKey", "llm2Key", "llmKey"])
        XCTAssertTrue(WipeRules.defaultsKeys.contains("rsAmapKey"))
    }
}