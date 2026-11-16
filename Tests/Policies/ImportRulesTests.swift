import XCTest
@testable import TaoShengPolicies

final class ImportRulesTests: XCTestCase {
    func testSameNameDifferentContentAreDistinct() {
        let a = ImportRules.key(name: "录音.m4a", size: 100, modifiedEpoch: 1_700_000_000)
        let b = ImportRules.key(name: "录音.m4a", size: 200, modifiedEpoch: 1_700_000_000)
        let c = ImportRules.key(name: "录音.m4a", size: 100, modifiedEpoch: 1_700_000_999)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(ImportRules.shouldImport(key: a, seen: [b, c]))
        XCTAssertFalse(ImportRules.shouldImport(key: a, seen: [a]))
    }

    func testSummaryMentionsFailures() {
        XCTAssertEqual(ImportRules.summary(added: 2, failedNames: []), "导入 2 段，已排队转写")
        XCTAssertEqual(ImportRules.summary(added: 0, failedNames: []), "没有导入任何文件")
        let s = ImportRules.summary(added: 1, failedNames: ["a.m4a", "b.m4a"])
        XCTAssertTrue(s.contains("1 个失败"))
        XCTAssertTrue(s.contains("a.m4a"))
    }

    func testEmptyKeyNeverImports() {
        XCTAssertFalse(ImportRules.shouldImport(key: "", seen: []))
    }
}