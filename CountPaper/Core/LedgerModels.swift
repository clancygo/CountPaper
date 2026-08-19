import Foundation

/// The five account roots supported by CountPaper's plain-text format.
/// Kept in Core so calculations, validation, macOS and a future iOS client
/// agree on classification without importing AppKit.
enum LedgerAccountKind: CaseIterable {
    case asset
    case liability
    case equity
    case income
    case expense
}

func ledgerAccountKind(_ account: String) -> LedgerAccountKind? {
    switch account.split(separator: ":", maxSplits: 1).first.map(String.init) {
    case "资产", "Assets": return .asset
    case "负债", "Liabilities": return .liability
    case "权益", "Equity": return .equity
    case "收入", "Income": return .income
    case "费用", "Expenses": return .expense
    default: return nil
    }
}

func isLedgerAccount(_ account: String, _ kind: LedgerAccountKind) -> Bool {
    ledgerAccountKind(account) == kind
}

struct LedgerPosting: Equatable {
    let account: String
    let amount: Decimal
    let line: Int
}

struct LedgerTransaction: Equatable {
    let date: String
    let time: String?
    let summary: String
    let flag: Character?
    let postings: [LedgerPosting]
    let payee: String?
    let tags: [String]
    let links: [String]
    let startLine: Int
    let endLine: Int
}

struct LedgerBalanceIssue: Equatable {
    let date: String
    let summary: String
    let line: Int
    let difference: Decimal
}

struct LedgerBudget: Equatable {
    let month: String
    let account: String
    let amount: Decimal
    let line: Int
}

struct LedgerReconciliation: Equatable {
    let date: String
    let account: String
    /// The user-facing statement balance, not the account's debit/credit sign.
    let statementBalance: Decimal
    let line: Int
}

struct LedgerEvent: Equatable {
    let date: String
    let title: String
    let line: Int
}

struct LedgerAccountNote: Equatable {
    let account: String
    let text: String
    let line: Int
}

enum JournalSearchField: CaseIterable {
    case all, summary, account, payee, tag, link

    var title: String {
        switch self {
        case .all: "全部"
        case .summary: "摘要"
        case .account: "账户"
        case .payee: "收款方"
        case .tag: "标签"
        case .link: "链接"
        }
    }
}

enum JournalStatusFilter: CaseIterable {
    case all, confirmed, pending

    var title: String {
        switch self {
        case .all: "全部状态"
        case .confirmed: "已确认"
        case .pending: "待确认"
        }
    }
}

struct PersonalSummary: Equatable {
    let transactions: Int
    let income: [String: Decimal]
    let expenses: [String: Decimal]
    var incomeTotal: Decimal { income.values.reduce(.zero, +) }
    var expenseTotal: Decimal { expenses.values.reduce(.zero, +) }
    var net: Decimal { incomeTotal - expenseTotal }
}

struct LedgerReport: Equatable {
    var diagnostics: [String] = []
    var balanceIssues: [LedgerBalanceIssue] = []
    var balances: [String: Decimal] = [:]
    var expenses: [String: Decimal] = [:]
    var accounts: [String] = []
    var journal: [LedgerTransaction] = []
    var budgets: [LedgerBudget] = []
    var reconciliations: [LedgerReconciliation] = []
    var events: [LedgerEvent] = []
    var accountNotes: [LedgerAccountNote] = []
    var transactions = 0

    func personalSummary(month: String?) -> PersonalSummary {
        personalSummary(entries: journal.filter { month == nil || $0.date.hasPrefix(month! + "-") })
    }

    func personalSummary(startDate: String?, endDate: String?) -> PersonalSummary {
        personalSummary(entries: reportEntries(startDate: startDate, endDate: endDate))
    }

    func reportEntries(startDate: String?, endDate: String?) -> [LedgerTransaction] {
        journal.filter { entry in
            (startDate == nil || entry.date >= startDate!) && (endDate == nil || entry.date <= endDate!)
        }
    }

    func personalSummary(entries: [LedgerTransaction]) -> PersonalSummary {
        var income: [String: Decimal] = [:]
        var expenses: [String: Decimal] = [:]
        for entry in entries {
            for posting in entry.postings {
                if isLedgerAccount(posting.account, .income) { income[posting.account, default: .zero] += -posting.amount }
                if isLedgerAccount(posting.account, .expense) { expenses[posting.account, default: .zero] += posting.amount }
            }
        }
        return PersonalSummary(transactions: entries.count, income: income, expenses: expenses)
    }

    func journal(matching query: String, field: JournalSearchField = .all, status: JournalStatusFilter = .all) -> [LedgerTransaction] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusMatched = journal.filter { entry in
            switch status {
            case .all: true
            case .confirmed: entry.flag != "!"
            case .pending: entry.flag == "!"
            }
        }
        guard !term.isEmpty else { return statusMatched }
        return statusMatched.filter { entry in
            switch field {
            case .all:
                entry.date.localizedCaseInsensitiveContains(term) ||
                entry.summary.localizedCaseInsensitiveContains(term) ||
                entry.payee?.localizedCaseInsensitiveContains(term) == true ||
                entry.tags.contains { $0.localizedCaseInsensitiveContains(term) } ||
                entry.links.contains { $0.localizedCaseInsensitiveContains(term) } ||
                entry.postings.contains { $0.account.localizedCaseInsensitiveContains(term) }
            case .summary: entry.summary.localizedCaseInsensitiveContains(term)
            case .account: entry.postings.contains { $0.account.localizedCaseInsensitiveContains(term) }
            case .payee: entry.payee?.localizedCaseInsensitiveContains(term) == true
            case .tag: entry.tags.contains { $0.localizedCaseInsensitiveContains(term) }
            case .link: entry.links.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
    }
}
