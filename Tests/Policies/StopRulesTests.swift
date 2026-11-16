import XCTest
@testable import TaoShengPolicies

final class StopRulesTests: XCTestCase {
    func testUserStopStaysStopped() {
        XCTAssertEqual(StopRules.stateAfterUserStop().captureWanted, false)
        XCTAssertEqual(StopRules.stateAfterUserStop().userStopped, true)
        XCTAssertFalse(StopRules.shouldAutoStart(captureWanted: false, userStopped: true))
        XCTAssertFalse(StopRules.shouldAutoStart(captureWanted: true, userStopped: true))
    }

    func testAutoStartWhenWanted() {
        XCTAssertTrue(StopRules.shouldAutoStart(captureWanted: true, userStopped: false))
        XCTAssertFalse(StopRules.shouldAutoStart(captureWanted: false, userStopped: false))
    }

    func testSessionEndResumesOnlyWhenAlwaysListening()  {
        XCTAssertTrue(StopRules.shouldResumeAfterSessionEnd(reason: .sessionEnd, alwaysListening: true))
        XCTAssertFalse(StopRules.shouldResumeAfterSessionEnd(reason: .sessionEnd, alwaysListening: false))
        XCTAssertFalse(StopRules.shouldResumeAfterSessionEnd(reason: .userStop, alwaysListening: true))
    }

    func testMicChoice() {
        XCTAssertEqual(MicRules.choice(uid: "", hasExternal: true), .builtIn)
        XCTAssertEqual(MicRules.choice(uid: "  ", hasExternal: false), .builtIn)
        XCTAssertEqual(MicRules.choice(uid: "auto", hasExternal: true), .external)
        XCTAssertEqual(MicRules.choice(uid: "auto", hasExternal: false), .builtIn)
        XCTAssertEqual(MicRules.choice(uid: "USB-Audio", hasExternal: true), .specific("USB-Audio"))
        XCTAssertEqual(MicRules.keepUidAfterReplug("auto"), "auto")
    }

    func testEmptyUidMeansBuiltInMic() {
        // 「手机麦克风」必须明确选内置麦，不能只 setPreferredInput(nil) 让系统随便挑
        XCTAssertEqual(MicRules.choice(uid: "", hasExternal: false), .builtIn)
        XCTAssertEqual(MicRules.choice(uid: "", hasExternal: true), .builtIn)
    }

    func testAutoPrefersExternalButKeepsPreference() {
        XCTAssertEqual(MicRules.choice(uid: "auto", hasExternal: true), .external)
        XCTAssertEqual(MicRules.choice(uid: "auto", hasExternal: false), .builtIn)
        // 插拔不把 auto 偏好清成空
        XCTAssertEqual(MicRules.keepUidAfterReplug("auto"), "auto")
        XCTAssertEqual(MicRules.keepUidAfterReplug("usb-123"), "usb-123")
    }

    func testRouteChangeKeepsAutoAndClearsMissingSpecificInput() {
        XCTAssertEqual(
            MicRules.uidAfterRouteChange(preferredUID: "auto", availableUIDs: []),
            "auto"
        )
        XCTAssertEqual(
            MicRules.uidAfterRouteChange(preferredUID: "usb-123", availableUIDs: []),
            ""
        )
        XCTAssertEqual(
            MicRules.uidAfterRouteChange(preferredUID: "usb-123", availableUIDs: ["usb-123"]),
            "usb-123"
        )
    }

    func testUserStopAlsoMarksWantedOff() {
        let s = StopRules.stateAfterUserStop()
        XCTAssertFalse(s.captureWanted)
        XCTAssertTrue(s.userStopped)
        XCTAssertFalse(StopRules.shouldAutoStart(captureWanted: s.captureWanted, userStopped: s.userStopped))
    }

    func testSessionEndRestoresAlwaysListening() {
        XCTAssertTrue(StopRules.shouldResumeAfterSessionEnd(reason: .sessionEnd, alwaysListening: true))
        XCTAssertFalse(StopRules.shouldResumeAfterSessionEnd(reason: .userStop, alwaysListening: true))
        XCTAssertFalse(StopRules.shouldResumeAfterSessionEnd(reason: .sessionEnd, alwaysListening: false))
    }
}
