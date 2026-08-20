import Foundation

enum LedgerTransactionUIKind { case expense, income, transfer, other }

struct LedgerTransactionUIInfo {
    let kind: LedgerTransactionUIKind
    let category: String?
    let account: String?
    let destinationAccount: String?
    let amount: Decimal

    func kindTitle(english: Bool) -> String {
        switch kind {
        case .expense: english ? "Expense" : "支出"
        case .income: english ? "Income" : "收入"
        case .transfer: english ? "Transfer" : "转账"
        case .other: english ? "Transaction" : "交易"
        }
    }

    func context(english: Bool) -> String {
        switch kind {
        case .expense, .income: [category, account].compactMap { $0 }.joined(separator: " · ")
        case .transfer: [account, destinationAccount].compactMap { $0 }.joined(separator: " → ")
        case .other: account ?? (english ? "Other" : "其他")
        }
    }
}
