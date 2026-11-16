import XCTest
@testable import TaoShengPolicies

final class ASRRulesTests: XCTestCase {
    func testKindIndexRoundTrip() {
        for (i, k) in ASRRules.kindIndex.enumerated() {
            XCTAssertEqual(ASRRules.index(kind: k), i)
            XCTAssertEqual(ASRRules.kind(index: i), k)
        }
        XCTAssertEqual(ASRRules.kind(index: 99), "doubao")
        XCTAssertEqual(ASRRules.index(kind: "unknown"), 0)
    }

    func testCadence() {
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 0, custom: 45), 1)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 1, custom: 45), 15)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 2, custom: 45), 30)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 3, custom: 45), 45)
        XCTAssertEqual(ASRRules.cadenceMinutes(index: 3, custom: 1), 5)
        XCTAssertEqual(ASRRules.cadenceIndex(minutes: 45), 3)
    }

    func testEndpointPrefersSavedBase() {
        XCTAssertEqual(ASRRules.endpoint(base: " https://a.example/v1 ", legacyFull: "https://old/v1"), "https://a.example/v1")
        XCTAssertEqual(ASRRules.endpoint(base: "", legacyFull: "https://old/v1"), "https://old/v1")
        XCTAssertEqual(ASRRules.endpoint(base: "", legacyFull: ""), "")
    }

    func testNetworkGate() {
        XCTAssertFalse(ASRRules.needsNetwork(kind: "appleSpeech"))
        XCTAssertTrue(ASRRules.needsNetwork(kind: "doubao"))
        XCTAssertTrue(ASRRules.needsNetwork(kind: "openAICompatible"))
    }

    func testParseReplyAcceptsRealText() {
        let ok = Data(#"{"text":" 你好 "}"#.utf8)
        XCTAssertEqual(ASRRules.parseReply(contentType: "application/json", body: ok), .text("你好"))
        let plain = Data("纯文本原话".utf8)
        XCTAssertEqual(ASRRules.parseReply(contentType: "text/plain; charset=utf-8", body: plain), .text("纯文本原话"))
    }

    func testParseReplyRejectsHtmlErrorJsonAndEmptyText() {
        let html = Data("<html><body>502 Bad Gateway</body></html>".utf8)
        if case .text = ASRRules.parseReply(contentType: "text/html", body: html) {
            XCTFail("HTML 不能当成原话")
        }
        let err = Data(#"{"error":{"message":"invalid key"}}"#.utf8)
        XCTAssertEqual(ASRRules.parseReply(contentType: "application/json", body: err), .bad("invalid key"))
        let empty = Data(#"{"text":""}"#.utf8)
        if case .text = ASRRules.parseReply(contentType: "application/json", body: empty) {
            XCTFail("空 text 不能当成原话")
        }
        let none = Data(#"{"foo":1}"#.utf8)
        if case .text = ASRRules.parseReply(contentType: "application/json", body: none) {
            XCTFail("没有 text 字段不能当成原话")
        }
        XCTAssertEqual(ASRRules.parseReply(contentType: "application/json", body: Data()), .bad("空响应"))
    }

    func testWipeRules() {
        XCTAssertTrue(WipeRules.secrets.contains("asrKey"))
        XCTAssertTrue(WipeRules.secrets.contains("llm2Key"))
        XCTAssertTrue(WipeRules.defaultsKeys.contains("rsQuietUntil"))
        XCTAssertFalse(WipeRules.secrets.contains("llmUsage.2026-01-01"))
    }

    func testPushGate() {
        XCTAssertEqual(PushGate.todoItems(["事件", "待办", "约定"]), [1, 2])
        XCTAssertTrue(PushGate.shouldPushTodo(enabled: true, categories: ["待办"]))
        XCTAssertFalse(PushGate.shouldPushTodo(enabled: false, categories: ["待办"]))
        XCTAssertFalse(PushGate.shouldPushTodo(enabled: true, categories: ["事件"]))
    }
}