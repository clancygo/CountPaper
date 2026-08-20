import XCTest
@testable import CountPaperCore

final class ParserTests: XCTestCase {
    func testStrictOutlineParsesTransactionsAndMetadata() {
        let source = """
        ---
        format: countpaper/0.2
        currency: CNY
        ---

        @账户
        - 资产:现金
        - 收入:工资
        - 费用:餐饮

        # 2026-08-01
        - 工资
          - 资产:现金  1000.00
          - 收入:工资  -1000.00

        # 2026-08-02
        - 午餐
          - 时间: 12:35
          - 收款方: 星巴克
          - 标签: #咖啡, 日常
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """
        let report = LedgerCoreParser.parse(source)
        XCTAssertTrue(report.diagnostics.isEmpty)
        XCTAssertEqual(report.transactions, 2)
        XCTAssertEqual(report.balances["资产:现金"], Decimal(string: "967.50"))
        XCTAssertEqual(report.journal.last?.time, "12:35")
        XCTAssertEqual(report.journal.last?.payee, "星巴克")
        XCTAssertEqual(report.journal.last?.tags, ["咖啡", "日常"])
    }

    func testInvalidAndUnbalancedOutlineProducesDiagnostics() {
        XCTAssertFalse(LedgerCoreParser.parse("账本 0.1").diagnostics.isEmpty)
        let source = """
        ---
        format: countpaper/0.2
        currency: CNY
        ---
        @账户
        - 资产:现金
        - 费用:餐饮
        # 2026-08-02
        - 午餐
          - 费用:餐饮  32.50
          - 资产:现金  -30.00
        """
        let report = LedgerCoreParser.parse(source)
        XCTAssertEqual(report.balanceIssues.first?.difference, Decimal(string: "2.50"))
        XCTAssertTrue(report.diagnostics.contains { $0.contains("不平衡") })
    }
}
