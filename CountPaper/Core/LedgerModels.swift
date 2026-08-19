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
