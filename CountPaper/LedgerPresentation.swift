import Cocoa

/// Display-only hierarchy derived from plain-text account declarations. It
/// retains no private ledger state; balances and notes are rebuilt per parse.
final class AccountOutlineNode {
    let title: String
    let path: String
    var account: String?
    var balance: Decimal = .zero
    var note: String?
    var children: [AccountOutlineNode] = []

    init(title: String, path: String, account: String? = nil) {
        self.title = title
        self.path = path
        self.account = account
    }
}

struct ReconciliationRow {
    let entry: LedgerTransaction
    let accountSummary: String
}

/// Native reconciliation rows are calculated in one chronological balance
/// pass, never by re-parsing the text representation used by older views.
func reconciliationRows(entries: [LedgerTransaction], accounts: [String], newestFirst: Bool) -> [ReconciliationRow] {
    let tracked = accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }.sorted()
    var balances: [String: Decimal] = [:]
    var rows: [ReconciliationRow] = []
    for entry in chronologicallyOrderedTransactions(entries) {
        var changed: [String: Decimal] = [:]
        for posting in entry.postings where tracked.contains(posting.account) {
            balances[posting.account, default: .zero] += posting.amount
            changed[posting.account, default: .zero] += posting.amount
        }
        let summary = tracked.compactMap { account -> String? in
            guard let delta = changed[account], delta != .zero else { return nil }
            let balance = displayBalance(balances[account, default: .zero], account: account)
            let change = displayBalance(delta, account: account)
            return "\(ledgerAccountDisplayName(account))  \(LedgerParser.format(balance)) (\(signedLedgerAmount(change)))"
        }.joined(separator: "  ·  ")
        rows.append(ReconciliationRow(entry: entry, accountSummary: summary))
    }
    return newestFirst ? Array(rows.reversed()) : rows
}
