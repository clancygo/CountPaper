import Foundation

enum QuickEntryKind: Int, CaseIterable {
    case expense, income, transfer

    var title: String { switch self { case .expense: "记一笔支出"; case .income: "记一笔收入"; case .transfer: "记录转账" } }
    var defaultSummary: String { switch self { case .expense: "支出"; case .income: "收入"; case .transfer: "转账" } }
}

struct QuickEntryAccountOptions: Equatable {
    let destination: [String]
    let source: [String]
}

struct QuickEntrySuggestion: Equatable {
    let summary: String
    let payee: String?
    let tags: [String]
    let destination: String
    let source: String
    let amount: Decimal
}

func quickEntryAmounts(_ text: String, allowsMultiple: Bool) -> [Decimal]? {
    let values = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "，" || $0 == "," })
    guard !values.isEmpty, (allowsMultiple || values.count == 1) else { return nil }
    let amounts = values.compactMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
    guard amounts.count == values.count, amounts.allSatisfy({ $0 != .zero }) else { return nil }
    return amounts
}

func accountCompletionCandidates(_ partial: String, accounts: [String]) -> [String] {
    let query = partial.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return [] }
    return accounts.filter { $0.range(of: query, options: [.caseInsensitive, .anchored]) != nil }.sorted()
}

func smartLedgerTransaction(shortcut: String, accounts: [String], defaultAsset: String, date: String) -> String? {
    let normalized = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    let spacedParts = normalized.split(whereSeparator: { $0 == " " || $0 == "\t" })
    let name: String
    let amountText: String
    if spacedParts.count == 2 {
        name = String(spacedParts[0]); amountText = String(spacedParts[1])
    } else if spacedParts.count == 1,
              let expression = try? NSRegularExpression(pattern: "^(.+?)([+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+))$"),
              let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let nameRange = Range(match.range(at: 1), in: normalized),
              let amountRange = Range(match.range(at: 2), in: normalized) {
        name = String(normalized[nameRange]); amountText = String(normalized[amountRange])
    } else { return nil }
    guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")), amount != .zero else { return nil }
    let candidates = accounts.filter { $0 == name || $0.hasSuffix(":" + name) }
    guard candidates.count == 1, let account = candidates.first else { return nil }
    if isLedgerAccount(account, .expense) {
        return "# \(date)\n- \(name)\n  - \(account)  \(LedgerCoreParser.format(amount))\n  - \(defaultAsset)  \(LedgerCoreParser.format(-amount))"
    }
    if isLedgerAccount(account, .income) {
        return "# \(date)\n- \(name)\n  - \(defaultAsset)  \(LedgerCoreParser.format(amount))\n  - \(account)  \(LedgerCoreParser.format(-amount))"
    }
    return nil
}

func quickEntryAccountOptions(accounts: [String], kind: QuickEntryKind) -> QuickEntryAccountOptions {
    let liquid = accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
    switch kind {
    case .expense: return QuickEntryAccountOptions(destination: accounts.filter { isLedgerAccount($0, .expense) }, source: liquid)
    case .income: return QuickEntryAccountOptions(destination: accounts.filter { isLedgerAccount($0, .asset) }, source: accounts.filter { isLedgerAccount($0, .income) })
    case .transfer: return QuickEntryAccountOptions(destination: liquid, source: liquid)
    }
}

func quickEntrySuggestions(report: LedgerReport, kind: QuickEntryKind, limit: Int = 8) -> [QuickEntrySuggestion] {
    var output: [QuickEntrySuggestion] = []
    var seen = Set<String>()
    for transaction in report.journal.reversed() {
        guard transaction.postings.count == 2,
              let positive = transaction.postings.first(where: { $0.amount > .zero }),
              let negative = transaction.postings.first(where: { $0.amount < .zero }) else { continue }
        let liquid: (String) -> Bool = { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
        let matches: Bool
        switch kind {
        case .expense: matches = isLedgerAccount(positive.account, .expense) && liquid(negative.account)
        case .income: matches = liquid(positive.account) && isLedgerAccount(negative.account, .income)
        case .transfer: matches = liquid(positive.account) && liquid(negative.account)
        }
        guard matches else { continue }
        let suggestion = QuickEntrySuggestion(summary: transaction.summary, payee: transaction.payee, tags: transaction.tags, destination: positive.account, source: negative.account, amount: positive.amount)
        let key = "\(suggestion.summary)\u{0}\(suggestion.payee ?? "")\u{0}\(suggestion.tags.joined(separator: ","))\u{0}\(suggestion.destination)\u{0}\(suggestion.source)\u{0}\(LedgerCoreParser.format(suggestion.amount))"
        guard seen.insert(key).inserted else { continue }
        output.append(suggestion)
        if output.count == limit { break }
    }
    return output
}
