import XCTest
@testable import CountPaperCore

final class ReportTests: XCTestCase {
    func testAccountRootsAndPersonalSummary() {
        XCTAssertEqual(ledgerAccountKind("资产:现金"), .asset)
        XCTAssertEqual(ledgerAccountKind("Expenses:Dining"), .expense)
        let report = LedgerCoreParser.parse("""
        ---
        format: countpaper/0.2
        currency: CNY
        ---
        @账户
        - 资产:现金
        - 费用:餐饮
        # 2026-08-01
        - 午餐
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """)
        XCTAssertEqual(report.personalSummary(month: "2026-08").expenseTotal, Decimal(string: "32.50"))
    }
}
