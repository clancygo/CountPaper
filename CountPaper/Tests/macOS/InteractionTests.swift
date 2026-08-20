import Cocoa

enum InteractionTests {
    static func run() {
        let report = LedgerParser.parse(MacOSTestSupport.sample)
        let kinds = Set(ledgerSyntaxTokens(in: MacOSTestSupport.sample).map(\.kind))
        MacOSTestSupport.expect(kinds.isSuperset(of: [.frontMatter, .accountMarker, .date, .transaction, .account, .amount]), "syntax highlighter follows outline tokens")
        MacOSTestSupport.expect(filteredLedgerTransactions(report.journal, query: "午餐").count == 1, "journal search filters transactions")
        MacOSTestSupport.expect(reconciliationRows(entries: report.journal, accounts: report.accounts, newestFirst: true).first?.accountSummary.contains("现金") == true, "reconciliation provides post-transaction balances")
    }
}
