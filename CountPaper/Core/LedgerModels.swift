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
