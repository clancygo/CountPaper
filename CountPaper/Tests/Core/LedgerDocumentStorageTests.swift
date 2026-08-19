import Foundation
import XCTest
@testable import CountPaperCore

final class LedgerDocumentStorageTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountPaperCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testSaveReplacesOnlyVerifiedTemporaryFileAndPreservesRecoveryVersion() throws {
        let ledger = testDirectory.appendingPathComponent("Ledger.countpaper")
        let backups = testDirectory.appendingPathComponent("Backups", isDirectory: true)

        let first = try LedgerDocumentStorage.save("first", to: ledger, recoveryDirectory: backups)
        XCTAssertNil(first.backupURL)
        XCTAssertEqual(try String(contentsOf: ledger, encoding: .utf8), "first")

        let second = try LedgerDocumentStorage.save("second", to: ledger, recoveryDirectory: backups)
        XCTAssertEqual(try String(contentsOf: ledger, encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(second.backupURL), encoding: .utf8), "first")
    }

    func testBackupRetentionIsIsolatedPerLedger() throws {
        let work = testDirectory.appendingPathComponent("Work.countpaper")
        let life = testDirectory.appendingPathComponent("Life.countpaper")
        let backups = testDirectory.appendingPathComponent("Backups", isDirectory: true)

        try LedgerDocumentStorage.save("work-1", to: work, backupLimit: 20, recoveryDirectory: backups)
        try LedgerDocumentStorage.save("work-2", to: work, backupLimit: 20, recoveryDirectory: backups)

        try LedgerDocumentStorage.save("life-1", to: life, backupLimit: 2, recoveryDirectory: backups)
        try LedgerDocumentStorage.save("life-2", to: life, backupLimit: 2, recoveryDirectory: backups)
        try LedgerDocumentStorage.save("life-3", to: life, backupLimit: 2, recoveryDirectory: backups)
        try LedgerDocumentStorage.save("life-4", to: life, backupLimit: 2, recoveryDirectory: backups)

        // A subsequent work save must retain both work revisions even though
        // the other document has already exhausted its smaller budget.
        try LedgerDocumentStorage.save("work-3", to: work, backupLimit: 20, recoveryDirectory: backups)

        let workBackups = try LedgerDocumentStorage.backups(for: work, recoveryDirectory: backups)
        let lifeBackups = try LedgerDocumentStorage.backups(for: life, recoveryDirectory: backups)
        XCTAssertEqual(workBackups.count, 2)
        XCTAssertEqual(lifeBackups.count, 2)
        XCTAssertEqual(Set(try workBackups.map { try String(contentsOf: $0, encoding: .utf8) }), Set(["work-1", "work-2"]))
        XCTAssertEqual(Set(try lifeBackups.map { try String(contentsOf: $0, encoding: .utf8) }), Set(["life-2", "life-3"]))
    }

    func testExternalSignatureDetectsReplacement() throws {
        let ledger = testDirectory.appendingPathComponent("Ledger.countpaper")
        try "initial".write(to: ledger, atomically: true, encoding: .utf8)
        let original = try XCTUnwrap(LedgerDocumentStorage.fileSignature(for: ledger))
        try "replacement with a different length".write(to: ledger, atomically: true, encoding: .utf8)
        let replacement = try XCTUnwrap(LedgerDocumentStorage.fileSignature(for: ledger))

        XCTAssertEqual(externalChangeAction(last: original, current: replacement, hasUnsavedChanges: false), .reload)
        XCTAssertEqual(externalChangeAction(last: original, current: replacement, hasUnsavedChanges: true), .conflict)
        XCTAssertEqual(externalChangeAction(last: original, current: nil, hasUnsavedChanges: false), .deleted)
        XCTAssertEqual(externalChangeAction(last: original, current: nil, hasUnsavedChanges: true), .deleted)
        XCTAssertEqual(externalChangeAction(last: nil, current: nil, hasUnsavedChanges: false), .none)
    }

    func testAccountRootsAreSharedDomainRules() {
        XCTAssertEqual(ledgerAccountKind("资产:现金"), .asset)
        XCTAssertEqual(ledgerAccountKind("Expenses:Dining"), .expense)
        XCTAssertTrue(isLedgerAccount("Liabilities:CreditCard", .liability))
        XCTAssertNil(ledgerAccountKind("Custom:Account"))
    }

    func testWriterChangesOnlyTheRequestedUTF16Range() {
        let source = "; before\n- coffee ☕ 18\n; after\n"
        let range = (source as NSString).range(of: "coffee ☕ 18")
        XCTAssertEqual(
            LedgerWriter.replacing(range, in: source, with: "tea 🍵 20"),
            "; before\n- tea 🍵 20\n; after\n"
        )
        XCTAssertNil(LedgerWriter.replacing(NSRange(location: 999, length: 1), in: source, with: "x"))
    }

    func testValidationSeparatesFatalSyntaxFromUnsafeStructuredEditing() {
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: []).level, .valid)
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: ["warning: spacing"]).level, .warning)
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: [], hasUnsupportedEditableContent: true).level, .unsafeToModify)
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: ["错误：缺少文件头"]).level, .fatal)
        XCTAssertTrue(LedgerOutlineSafety.isFormEditableTransaction("- Lunch\n  - Expenses:Dining  20\n  - Assets:Cash  -20\n"))
        XCTAssertFalse(LedgerOutlineSafety.isFormEditableTransaction("- Lunch\n  - custom: preserve me\n  - Expenses:Dining  20\n  - Assets:Cash  -20\n"))
    }

    func testSafeAutoCorrectionNeverConsumesAnInProgressListMarker() {
        XCTAssertEqual(safeLedgerAutoCorrection("# 2026-08-20\n- ").text, "# 2026-08-20\n- ")
        XCTAssertEqual(safeLedgerAutoCorrection("format:countpaper/0.2\ncurrency:CNY\n").text, "format: countpaper/0.2\ncurrency: CNY\n")
    }

    func testCoreParserBuildsStrictOutlineReport() {
        let source = """
        ---
        format: countpaper/0.2
        currency: CNY
        ---

        @账户
        - 资产:现金
        - 费用:餐饮

        # 2026-08-20
        - 午餐
          - 时间: 12:30
          - 收款方: 小店
          - 标签: 日常, #午餐
          - 费用:餐饮  20.00
          - 资产:现金  -20.00
        """
        let report = LedgerCoreParser.parse(source)
        XCTAssertTrue(report.diagnostics.isEmpty)
        XCTAssertEqual(report.transactions, 1)
        XCTAssertEqual(report.journal.first?.time, "12:30")
        XCTAssertEqual(report.journal.first?.tags, ["日常", "午餐"])
        XCTAssertEqual(report.balances["资产:现金"], Decimal(-20))
    }
}
