import XCTest
@testable import CountPaperCore

final class ExportTests: XCTestCase {
    func testJournalCSVExportsOneNaturalLanguageRowPerTransaction() {
        let report = LedgerCoreParser.parse("""
        ---
        format: countpaper/0.2
        currency: CNY
        ---
        @账户
        - 资产:现金
        - 费用:餐饮
        # 2026-08-02
        - 午餐
          - 收款方: 星巴克
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """)
        let csv = journalCSV(report: report, month: "2026-08", account: "费用:餐饮")
        XCTAssertEqual(csv.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 2)
        XCTAssertTrue(csv.contains("午餐") && csv.contains("\"支出\""))
    }
}
