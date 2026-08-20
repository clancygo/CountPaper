import Foundation

func isInternalBalanceAdjustmentAccount(_ account: String) -> Bool {
    account == "权益:余额调整" || account == "Equity:BalanceAdjustment"
}

func ledgerSourceAddingAccountDeclaration(_ raw: String, account: String) -> String? {
    guard !raw.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "- \(account)" }) else { return raw }
    let newline = raw.contains("\r\n") ? "\r\n" : "\n"
    let lines = raw.components(separatedBy: newline)
    var offset = 0; var inAccountSection = false; var lastAccountEnd: Int?
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
        if trimmed == "@账户" || trimmed == "@accounts" { inAccountSection = true }
        else if line.hasPrefix("# ") { inAccountSection = false }
        if inAccountSection, line.hasPrefix("- ") { lastAccountEnd = lineEnd }
        offset = lineEnd
    }
    guard let insertionOffset = lastAccountEnd else { return nil }
    let updated = NSMutableString(string: raw); updated.insert("- \(account)\(newline)", at: insertionOffset)
    return updated as String
}

func balanceAdjustmentCounterpart(for account: String) -> String {
    account.hasPrefix("Assets:") || account.hasPrefix("Liabilities:") ? "Equity:BalanceAdjustment" : "权益:余额调整"
}
