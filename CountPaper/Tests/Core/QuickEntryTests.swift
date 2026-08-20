import XCTest
@testable import CountPaperCore

final class QuickEntryTests: XCTestCase {
    func testShortcutAndMultipleAmountsCreateBalancedEntries() {
        let accounts = ["资产:现金", "负债:信用卡", "收入:工资", "费用:餐饮"]
        XCTAssertEqual(quickEntryAmounts("32 57", allowsMultiple: true)?.count, 2)
        XCTAssertEqual(quickEntryAmounts("-20", allowsMultiple: false), [Decimal(string: "-20")!])
        XCTAssertEqual(smartLedgerTransaction(shortcut: "餐饮32", accounts: accounts, defaultAsset: "资产:现金", date: "2026-03-01"), "# 2026-03-01\n- 餐饮\n  - 费用:餐饮  32.00\n  - 资产:现金  -32.00")
        XCTAssertEqual(quickEntryAccountOptions(accounts: accounts, kind: .expense).source, ["资产:现金", "负债:信用卡"])
    }
}
