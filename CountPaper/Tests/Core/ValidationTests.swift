import XCTest
@testable import CountPaperCore

final class ValidationTests: XCTestCase {
    func testValidationAndSafeCorrection() {
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: []).level, .valid)
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: ["warning: spacing"]).level, .warning)
        XCTAssertEqual(LedgerValidation.evaluate(diagnostics: ["错误：缺少文件头"]).level, .fatal)
        XCTAssertEqual(safeLedgerAutoCorrection("# 2026-08-20\n- ").text, "# 2026-08-20\n- ")
        XCTAssertEqual(safeLedgerAutoCorrection("format:countpaper/0.2\n").text, "format: countpaper/0.2\n")
    }

    func testOutlineSafetyRejectsUnknownEditableContent() {
        XCTAssertTrue(LedgerOutlineSafety.isFormEditableTransaction("- Lunch\n  - Expenses:Dining  20\n  - Assets:Cash  -20\n"))
        XCTAssertFalse(LedgerOutlineSafety.isFormEditableTransaction("- Lunch\n  - custom: preserve me\n  - Expenses:Dining  20\n  - Assets:Cash  -20\n"))
    }
}
