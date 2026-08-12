import Cocoa
import CoreServices
import UniformTypeIdentifiers

enum CountPaperPreference {
    static let multipleAmounts = "preferences.multipleAmounts"
    static let multipleAmountsMigrated = "preferences.multipleAmountsMigrated"
    static let language = "preferences.language"
    /// A user-chosen external editor for opening the plain-text ledger file.
    /// An empty value deliberately means "let macOS choose".
    static let sourceEditorApplicationPath = "preferences.sourceEditorApplicationPath"
}

enum AppLanguage: String { case chinese, english }

enum LedgerAccountKind { case asset, liability, equity, income, expense }

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

func isLedgerAccount(_ account: String, _ kind: LedgerAccountKind) -> Bool { ledgerAccountKind(account) == kind }

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
        name = String(spacedParts[0])
        amountText = String(spacedParts[1])
    } else if spacedParts.count == 1,
              let expression = try? NSRegularExpression(pattern: "^(.+?)([+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+))$"),
              let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let nameRange = Range(match.range(at: 1), in: normalized),
              let amountRange = Range(match.range(at: 2), in: normalized) {
        name = String(normalized[nameRange])
        amountText = String(normalized[amountRange])
    } else {
        return nil
    }
    guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")), amount != .zero else { return nil }
    let candidates = accounts.filter { $0 == name || $0.hasSuffix(":" + name) }
    guard candidates.count == 1, let account = candidates.first else { return nil }
    if isLedgerAccount(account, .expense) {
        return "# \(date)\n- \(name)\n  - \(account)  \(LedgerParser.format(amount))\n  - \(defaultAsset)  \(LedgerParser.format(-amount))"
    }
    if isLedgerAccount(account, .income) {
        return "# \(date)\n- \(name)\n  - \(defaultAsset)  \(LedgerParser.format(amount))\n  - \(account)  \(LedgerParser.format(-amount))"
    }
    return nil
}

struct LedgerAutoCorrection: Equatable {
    let text: String
    let changes: Int
}

/// Only normalizes unambiguous typography and directive spacing. It never adds,
/// removes, reorders, or rebalances a transaction.
func safeLedgerAutoCorrection(_ source: String) -> LedgerAutoCorrection {
    var text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{3000}", with: " ")
    text = text.replacingOccurrences(of: "format:countpaper/0.2", with: "format: countpaper/0.2")
    text = text.replacingOccurrences(of: "currency:CNY", with: "currency: CNY")
    text = text.replacingOccurrences(of: "format：", with: "format:")
    text = text.replacingOccurrences(of: "currency：", with: "currency:")
    let lines = text.components(separatedBy: "\n")
    let normalizedLines = lines.map { line in
        // A trailing space is meaningful while the user is composing a new
        // Markdown list item. Removing it changes "- " into "-" and forces a
        // whole-document correction that disrupts the editor selection.
        if line == "- " || line == "  - " { return line }
        return line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
    }
    let normalized = normalizedLines.joined(separator: "\n")
    let changes = normalized == source ? 0 : 1
    return LedgerAutoCorrection(text: normalized, changes: changes)
}

struct LedgerReport {
    var diagnostics: [String] = []
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

func aggregateLedgerReports(_ reports: [LedgerReport]) -> LedgerReport {
    var combined = LedgerReport()
    var accountSet = Set<String>()
    for report in reports {
        combined.diagnostics.append(contentsOf: report.diagnostics)
        for (account, amount) in report.balances { combined.balances[account, default: .zero] += amount }
        for (account, amount) in report.expenses { combined.expenses[account, default: .zero] += amount }
        accountSet.formUnion(report.accounts)
        combined.journal.append(contentsOf: report.journal)
        combined.budgets.append(contentsOf: report.budgets)
        combined.reconciliations.append(contentsOf: report.reconciliations)
        combined.events.append(contentsOf: report.events)
        combined.accountNotes.append(contentsOf: report.accountNotes)
        combined.transactions += report.transactions
    }
    combined.accounts = accountSet.sorted()
    combined.journal.sort { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.startLine < rhs.startLine
    }
    return combined
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

enum PersonalReportKind: CaseIterable {
    case trend, category, tag

    var title: String {
        switch self {
        case .trend: "趋势"
        case .category: "分类"
        case .tag: "标签"
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

struct MonthlyPersonalSummary: Equatable {
    let month: String
    let summary: PersonalSummary
}

func monthlyPersonalSummaries(report: LedgerReport) -> [MonthlyPersonalSummary] {
    monthlyPersonalSummaries(entries: report.journal)
}

func monthlyPersonalSummaries(entries: [LedgerTransaction]) -> [MonthlyPersonalSummary] {
    let months = Set(entries.map { String($0.date.prefix(7)) }).sorted()
    return months.map { month in
        let monthEntries = entries.filter { $0.date.hasPrefix(month + "-") }
        var income: [String: Decimal] = [:]
        var expenses: [String: Decimal] = [:]
        for entry in monthEntries {
            for posting in entry.postings {
                if isLedgerAccount(posting.account, .income) { income[posting.account, default: .zero] += -posting.amount }
                if isLedgerAccount(posting.account, .expense) { expenses[posting.account, default: .zero] += posting.amount }
            }
        }
        return MonthlyPersonalSummary(month: month, summary: PersonalSummary(transactions: monthEntries.count, income: income, expenses: expenses))
    }
}

struct PersonalAnalytics: Equatable {
    let expenseTransactions: Int
    let averageExpense: Decimal
    let largestExpenseAccount: String?
    let largestExpense: Decimal
    let paymentAccounts: [String: Decimal]
    let tagExpenses: [String: Decimal]
}

func personalAnalytics(entries: [LedgerTransaction]) -> PersonalAnalytics {
    var expenseTransactions = 0
    var expenseTotal = Decimal.zero
    var paymentAccounts: [String: Decimal] = [:]
    var tagExpenses: [String: Decimal] = [:]
    var expenseCategories: [String: Decimal] = [:]
    for entry in entries {
        let expense = entry.postings.filter { isLedgerAccount($0.account, .expense) && $0.amount > .zero }
        let amount = expense.reduce(Decimal.zero) { $0 + $1.amount }
        guard amount > .zero else { continue }
        expenseTransactions += 1
        expenseTotal += amount
        for posting in expense { expenseCategories[posting.account, default: .zero] += posting.amount }
        for posting in entry.postings where !isLedgerAccount(posting.account, .expense) && posting.amount < .zero {
            paymentAccounts[posting.account, default: .zero] += -posting.amount
        }
        for tag in entry.tags { tagExpenses[tag, default: .zero] += amount }
    }
    let largest = expenseCategories.max { lhs, rhs in lhs.value < rhs.value }
    return PersonalAnalytics(
        expenseTransactions: expenseTransactions,
        averageExpense: expenseTransactions == 0 ? .zero : expenseTotal / Decimal(expenseTransactions),
        largestExpenseAccount: largest?.key,
        largestExpense: largest?.value ?? .zero,
        paymentAccounts: paymentAccounts,
        tagExpenses: tagExpenses
    )
}

func csvField(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }

func personalReportCSV(report: LedgerReport, month: String?, startDate: String? = nil, endDate: String? = nil, tag: String? = nil, account: String? = nil) -> String {
    let baseEntries = startDate != nil || endDate != nil ? report.reportEntries(startDate: startDate, endDate: endDate) : report.journal.filter { month == nil || $0.date.hasPrefix(month! + "-") }
    let tagEntries = tag.map { selected in baseEntries.filter { $0.tags.contains(selected) } } ?? baseEntries
    let entries = account.map { selected in tagEntries.filter { $0.postings.contains { $0.account == selected } } } ?? tagEntries
    let summary = report.personalSummary(entries: entries)
    let period = startDate != nil || endDate != nil ? "\(startDate ?? "起始") 至 \(endDate ?? "今日")" : (month ?? "全部期间")
    var rows = ["期间,类型,分类,实际金额,预算金额,预算结余"]
    rows.append([period, "交易数", "", String(summary.transactions), "", ""].map(csvField).joined(separator: ","))
    for (account, amount) in summary.income.sorted(by: { $0.key < $1.key }) {
        rows.append([period, "收入", account, LedgerParser.format(amount), "", ""].map(csvField).joined(separator: ","))
    }
    let budgets = month.map { selectedMonth in report.budgets.filter { $0.month == selectedMonth } } ?? []
    let budgetByAccount = Dictionary(uniqueKeysWithValues: budgets.map { ($0.account, $0.amount) })
    let expenseAccounts = Set(summary.expenses.keys).union(budgetByAccount.keys).sorted()
    for account in expenseAccounts {
        let actual = summary.expenses[account] ?? .zero
        let budget = budgetByAccount[account]
        rows.append([period, "支出", account, LedgerParser.format(actual), budget.map(LedgerParser.format) ?? "", budget.map { LedgerParser.format($0 - actual) } ?? ""].map(csvField).joined(separator: ","))
    }
    rows.append([period, "收支结余", "", LedgerParser.format(summary.net), "", ""].map(csvField).joined(separator: ","))
    return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
}

func journalCSV(report: LedgerReport, month: String?, startDate: String? = nil, endDate: String? = nil, tag: String? = nil, account: String? = nil) -> String {
    let baseEntries = startDate != nil || endDate != nil ? report.reportEntries(startDate: startDate, endDate: endDate) : report.journal.filter { month == nil || $0.date.hasPrefix(month! + "-") }
    let tagEntries = tag.map { selected in baseEntries.filter { $0.tags.contains(selected) } } ?? baseEntries
    let entries = account.map { selected in tagEntries.filter { $0.postings.contains { $0.account == selected } } } ?? tagEntries
    var rows = ["日期,状态,摘要,收款方,标签,链接,账户,金额"]
    for entry in entries {
        let status = entry.flag == "!" ? "待确认" : "已确认"
        let tags = entry.tags.map { "#\($0)" }.joined(separator: " ")
        for posting in entry.postings {
            rows.append([entry.date, status, entry.summary, entry.payee ?? "", tags, entry.links.joined(separator: " "), posting.account, LedgerParser.format(posting.amount)].map(csvField).joined(separator: ","))
        }
    }
    return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
}

enum LedgerSyntaxKind: Hashable { case comment, directive, date, account, amount }

struct LedgerSyntaxToken {
    let kind: LedgerSyntaxKind
    let range: NSRange
}

/// A display-only lexer. Its UTF-16 ranges are suitable for NSTextStorage and
/// never participate in parsing, saving, or source edits.
func ledgerSyntaxTokens(in text: String) -> [LedgerSyntaxToken] {
    let source = text as NSString
    var tokens: [LedgerSyntaxToken] = []
    var location = 0
    while location < source.length {
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let line = source.substring(with: lineRange)
        let contentLength = line.trimmingCharacters(in: .newlines).utf16.count
        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = source.range(of: trimmed, options: [], range: contentRange)
        let contentStart = trimmedRange.location == NSNotFound ? lineRange.location : trimmedRange.location
        if trimmed.hasPrefix(";") {
            tokens.append(LedgerSyntaxToken(kind: .comment, range: contentRange))
        } else if ["账本", "本位币", "账户", "账户备注", "预算", "对账", "事件"].contains(where: { trimmed.hasPrefix($0 + " ") }) {
            let keyword = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            tokens.append(LedgerSyntaxToken(kind: .directive, range: NSRange(location: contentStart, length: keyword.utf16.count)))
        } else if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s|$)", options: .regularExpression) != nil {
            tokens.append(LedgerSyntaxToken(kind: .date, range: NSRange(location: contentStart, length: 10)))
        } else if !trimmed.isEmpty, line.first?.isWhitespace == true {
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let account = parts.first {
                tokens.append(LedgerSyntaxToken(kind: .account, range: NSRange(location: contentStart, length: String(account).utf16.count)))
            }
            if let amount = parts.last, Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) != nil {
                let amountRange = (line as NSString).range(of: String(amount), options: .backwards, range: NSRange(location: 0, length: contentLength))
                if amountRange.location != NSNotFound {
                    tokens.append(LedgerSyntaxToken(kind: .amount, range: NSRange(location: lineRange.location + amountRange.location, length: amountRange.length)))
                }
            }
        }
        location = NSMaxRange(lineRange)
    }
    return tokens
}

struct LedgerPosting {
    let account: String
    let amount: Decimal
    let line: Int
}

struct LedgerTransaction {
    let date: String
    let summary: String
    let flag: Character?
    let postings: [LedgerPosting]
    let payee: String?
    let tags: [String]
    let links: [String]
    let startLine: Int
    let endLine: Int
}

func transactionMetadata(fromComment comment: String) -> (payee: String?, tags: [String]) {
    let content = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let payeePrefixes = ["收款方:", "收款方："]
    if let prefix = payeePrefixes.first(where: { content.hasPrefix($0) }) {
        let value = String(content.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty ? nil : value, [])
    }
    let tagPrefixes = ["标签:", "标签："]
    if let prefix = tagPrefixes.first(where: { content.hasPrefix($0) }) {
        let values = String(content.dropFirst(prefix.count))
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == "\t" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (nil, values.filter { seen.insert($0).inserted })
    }
    return (nil, [])
}

func normalizedTransactionLinks(_ value: String) -> [String]? {
    let candidates = value
        .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == "\t" || $0 == "\n" })
        .map(String.init)
    guard !candidates.isEmpty else { return [] }
    var seen = Set<String>()
    var output: [String] = []
    for candidate in candidates {
        guard let components = URLComponents(string: candidate),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false else { return nil }
        if seen.insert(candidate).inserted { output.append(candidate) }
    }
    return output
}

func transactionLinks(fromComment comment: String) -> [String] {
    let content = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = ["链接:", "链接："]
    guard let prefix = prefixes.first(where: { content.hasPrefix($0) }) else { return [] }
    return normalizedTransactionLinks(String(content.dropFirst(prefix.count))) ?? []
}

enum QuickEntryKind: Int, CaseIterable {
    case expense, income, transfer

    var title: String { switch self { case .expense: "记一笔支出"; case .income: "记一笔收入"; case .transfer: "记录转账" } }
    var defaultSummary: String { switch self { case .expense: "支出"; case .income: "收入"; case .transfer: "转账" } }
}

struct QuickEntryAccountOptions: Equatable {
    let destination: [String]
    let source: [String]
}

struct LedgerSourceInsertion: Equatable {
    let location: Int
    let text: String
}

/// Returns a local insertion that keeps one outline section per date whenever
/// possible. Existing whitespace and every unrelated source character remain
/// untouched.
func ledgerTransactionInsertion(in raw: String, date: String, transactionBlocks: [String]) -> LedgerSourceInsertion {
    let source = raw as NSString
    let newline = raw.contains("\r\n") ? "\r\n" : "\n"
    let body = transactionBlocks.map { $0.replacingOccurrences(of: "\n", with: newline) }.joined(separator: newline)
    var matchingHeadingEnd: Int?
    var nextHeadingStart: Int?
    var location = 0
    while location < source.length {
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "# \(date)" {
            matchingHeadingEnd = NSMaxRange(lineRange)
            nextHeadingStart = nil
        } else if matchingHeadingEnd != nil, trimmed.hasPrefix("# ") {
            nextHeadingStart = lineRange.location
            break
        }
        let next = NSMaxRange(lineRange)
        if next <= location { break }
        location = next
    }
    if let headingEnd = matchingHeadingEnd {
        var insertionLocation = nextHeadingStart ?? source.length
        while insertionLocation > 0 {
            let character = source.character(at: insertionLocation - 1)
            guard character == 10 || character == 13 else { break }
            insertionLocation -= 1
        }
        insertionLocation = max(insertionLocation, headingEnd)
        let prefix = insertionLocation > headingEnd ? newline : ""
        return LedgerSourceInsertion(location: insertionLocation, text: prefix + body)
    }
    let prefix: String
    if raw.isEmpty { prefix = "" }
    else if raw.hasSuffix(newline) { prefix = newline }
    else { prefix = newline + newline }
    return LedgerSourceInsertion(location: source.length, text: prefix + "# \(date)" + newline + body)
}

func quickEntryAccountOptions(accounts: [String], kind: QuickEntryKind) -> QuickEntryAccountOptions {
    let liquid = accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
    switch kind {
    case .expense:
        return QuickEntryAccountOptions(destination: accounts.filter { isLedgerAccount($0, .expense) }, source: liquid)
    case .income:
        return QuickEntryAccountOptions(destination: accounts.filter { isLedgerAccount($0, .asset) }, source: accounts.filter { isLedgerAccount($0, .income) })
    case .transfer:
        return QuickEntryAccountOptions(destination: liquid, source: liquid)
    }
}

struct QuickEntrySuggestion: Equatable {
    let summary: String
    let payee: String?
    let tags: [String]
    let destination: String
    let source: String
    let amount: Decimal
}

/// Recent templates are derived on demand from the open text ledger. They are
/// intentionally not persisted as a second ledger store.
func quickEntrySuggestions(report: LedgerReport, kind: QuickEntryKind, limit: Int = 8) -> [QuickEntrySuggestion] {
    var output: [QuickEntrySuggestion] = []
    var seen = Set<String>()
    let liquidAccount: (String) -> Bool = { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
    for transaction in report.journal.reversed() {
        guard transaction.postings.count == 2,
              let positive = transaction.postings.first(where: { $0.amount > .zero }),
              let negative = transaction.postings.first(where: { $0.amount < .zero }) else { continue }
        let matches: Bool
        switch kind {
        case .expense:
            matches = isLedgerAccount(positive.account, .expense) && liquidAccount(negative.account)
        case .income:
            matches = liquidAccount(positive.account) && isLedgerAccount(negative.account, .income)
        case .transfer:
            matches = liquidAccount(positive.account) && liquidAccount(negative.account)
        }
        guard matches else { continue }
        let suggestion = QuickEntrySuggestion(summary: transaction.summary, payee: transaction.payee, tags: transaction.tags, destination: positive.account, source: negative.account, amount: positive.amount)
        let key = "\(suggestion.summary)\u{0}\(suggestion.payee ?? "")\u{0}\(suggestion.tags.joined(separator: ","))\u{0}\(suggestion.destination)\u{0}\(suggestion.source)\u{0}\(LedgerParser.format(suggestion.amount))"
        guard seen.insert(key).inserted else { continue }
        output.append(suggestion)
        if output.count == limit { break }
    }
    return output
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
    /// The user-facing statement balance, not the account's internal debit/credit sign.
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

func displayBalance(_ raw: Decimal, account: String) -> Decimal {
    (isLedgerAccount(account, .liability) || isLedgerAccount(account, .equity) || isLedgerAccount(account, .income)) ? -raw : raw
}

func reconciliationDifference(report: LedgerReport, reconciliation: LedgerReconciliation) -> Decimal {
    let raw = report.journal
        .filter { $0.date <= reconciliation.date }
        .flatMap(\.postings)
        .filter { $0.account == reconciliation.account }
        .reduce(Decimal.zero) { $0 + $1.amount }
    return displayBalance(raw, account: reconciliation.account) - reconciliation.statementBalance
}

func ledgerSourceRange(in text: String, fromLine startLine: Int, throughLine endLine: Int) -> NSRange? {
    guard startLine >= 1, endLine >= startLine else { return nil }
    let source = text as NSString
    var line = 1
    var location = 0
    while line < startLine {
        let newline = source.range(of: "\n", options: [], range: NSRange(location: location, length: source.length - location))
        guard newline.location != NSNotFound else { return nil }
        location = NSMaxRange(newline)
        line += 1
    }
    let start = location
    while line <= endLine {
        let newline = source.range(of: "\n", options: [], range: NSRange(location: location, length: source.length - location))
        guard newline.location != NSNotFound else { return NSRange(location: start, length: source.length - start) }
        location = NSMaxRange(newline)
        line += 1
    }
    return NSRange(location: start, length: location - start)
}

func ledgerLineRange(in text: String, line targetLine: Int) -> NSRange? {
    ledgerSourceRange(in: text, fromLine: targetLine, throughLine: targetLine)
}

func adjustedIndentation(in text: String, selection: NSRange, increase: Bool) -> (range: NSRange, replacement: String)? {
    let source = text as NSString
    guard source.length > 0, selection.location <= source.length else { return nil }
    let startRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let endLocation = min(source.length, max(selection.location, NSMaxRange(selection)) - (selection.length > 0 ? 1 : 0))
    let endRange = source.lineRange(for: NSRange(location: endLocation, length: 0))
    let affected = NSRange(location: startRange.location, length: NSMaxRange(endRange) - startRange.location)
    let original = source.substring(with: affected)
    let lineEnding = original.contains("\r\n") ? "\r\n" : "\n"
    let hasTerminalLineEnding = original.hasSuffix(lineEnding)
    var lines = original.components(separatedBy: lineEnding)
    if hasTerminalLineEnding { lines.removeLast() }
    var replacement = lines.map { line -> String in
        if increase { return "    " + line }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
        if line.hasPrefix(" ") { return String(line.dropFirst()) }
        return line
    }.joined(separator: lineEnding)
    if hasTerminalLineEnding { replacement += lineEnding }
    return (affected, replacement)
}

/// Produces the text inserted by Return in the source editor.  Ledger postings are
/// intentionally indented, so carrying only the leading whitespace keeps raw-text
/// entry quick without imposing TaskPaper-style hierarchy on transaction headings.
func inheritedIndentationInsertion(in text: String, selection: NSRange) -> String? {
    let source = text as NSString
    guard selection.length == 0, selection.location <= source.length else { return nil }
    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let beforeCursor = source.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
    let indentation = String(beforeCursor.prefix { $0 == " " || $0 == "\t" })
    let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
    return lineEnding + indentation
}

/// Markdown-outline Return behavior for CountPaper 0.2. It only adds list
/// markers for ledger headings/items and deliberately leaves IME composition to
/// AppKit.
func outlineNewlineInsertion(in text: String, selection: NSRange) -> String? {
    let source = text as NSString
    guard selection.length == 0, selection.location <= source.length else { return nil }
    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let rawLine = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
    let current = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix: String
    if rawLine.hasPrefix("  - ") { prefix = "  - " }
    else if rawLine.hasPrefix("- ") || rawLine.hasPrefix("# ") { prefix = "- " }
    else if current.isEmpty {
        let before = source.substring(to: lineRange.location).components(separatedBy: .newlines).reversed().first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?.trimmingCharacters(in: .whitespaces) ?? ""
        prefix = before.hasPrefix("  - ") ? "  - " : (before.hasPrefix("# ") || before.hasPrefix("- ") ? "- " : "")
    } else {
        return inheritedIndentationInsertion(in: text, selection: selection)
    }
    let ending = text.contains("\r\n") ? "\r\n" : "\n"
    return ending + prefix
}

final class LedgerTextView: NSTextView {
    private var insertionGeneration = 0

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        insertionGeneration += 1
        let generation = insertionGeneration
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let insertedLength: Int
        if let text = insertString as? String { insertedLength = (text as NSString).length }
        else if let attributed = insertString as? NSAttributedString { insertedLength = attributed.length }
        else { super.insertText(insertString, replacementRange: replacementRange); return }
        let sourceBeforeInsertion = string as NSString
        let editedLineBeforeInsertion = sourceBeforeInsertion.lineRange(for: NSRange(location: min(range.location, sourceBeforeInsertion.length), length: 0))
        let previousLineBeforeInsertion: NSRange? = editedLineBeforeInsertion.location > 0
            ? sourceBeforeInsertion.lineRange(for: NSRange(location: editedLineBeforeInsertion.location - 1, length: 0))
            : nil
        super.insertText(insertString, replacementRange: replacementRange)
        let caret = NSRange(location: range.location + insertedLength, length: 0)
        for delay in [0.02, 0.22] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.insertionGeneration == generation, caret.location <= (self.string as NSString).length else { return }
                let lineRange = (self.string as NSString).lineRange(for: NSRange(location: caret.location, length: 0))
                let selection = self.selectedRange()
                let systemSelectedCurrentLine = selection.length > 0 &&
                    selection.location >= lineRange.location && NSMaxRange(selection) <= NSMaxRange(lineRange)
                let systemSelectedPreviousLine = previousLineBeforeInsertion.map {
                    selection.length > 0 && selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0)
                } ?? false
                guard systemSelectedCurrentLine || systemSelectedPreviousLine else { return }
                self.setSelectedRange(caret)
                self.scrollRangeToVisible(caret)
            }
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        guard
              let insertion = outlineNewlineInsertion(in: string, selection: selectedRange()) else {
            super.insertNewline(sender)
            return
        }
        let range = selectedRange()
        let previousLineRange = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        guard shouldChangeText(in: range, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: range, with: insertion)
        didChangeText()
        let caret = NSRange(location: range.location + (insertion as NSString).length, length: 0)
        setSelectedRange(caret)
        scrollRangeToVisible(caret)
        let insertedRange = NSRange(location: range.location, length: (insertion as NSString).length)
        for delay in [0.02, 0.22] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, NSMaxRange(insertedRange) <= (self.string as NSString).length else { return }
                let selection = self.selectedRange()
                let allowedSelectionEnd = min((self.string as NSString).length, NSMaxRange(insertedRange) + 1)
                let systemSelectedInsertedText = selection.length > 0 &&
                    selection.location >= insertedRange.location && NSMaxRange(selection) <= allowedSelectionEnd
                let systemSelectedPreviousLine = selection.length > 0 &&
                    selection.location >= previousLineRange.location && NSMaxRange(selection) <= NSMaxRange(previousLineRange)
                guard systemSelectedInsertedText || systemSelectedPreviousLine else { return }
                self.setSelectedRange(caret)
                self.scrollRangeToVisible(caret)
            }
        }
    }
}

struct LedgerFileSignature: Equatable {
    let modificationDate: Date
    let size: Int
}

struct LedgerSession {
    let id: UUID
    var url: URL?
    var text: String
    var isDirty: Bool
    var signature: LedgerFileSignature?
    var hasExternalConflict: Bool
    var selection: NSRange

    init(url: URL?, text: String, isDirty: Bool = false, signature: LedgerFileSignature? = nil, hasExternalConflict: Bool = false, selection: NSRange = NSRange(location: 0, length: 0)) {
        self.id = UUID()
        self.url = url
        self.text = text
        self.isDirty = isDirty
        self.signature = signature
        self.hasExternalConflict = hasExternalConflict
        self.selection = selection
    }
}

func dirtyLedgerSessionIndexes(_ sessions: [LedgerSession]) -> [Int] {
    sessions.indices.filter { sessions[$0].isDirty }
}

enum ExternalChangeAction: Equatable { case none, reload, conflict }

func externalChangeAction(last: LedgerFileSignature?, current: LedgerFileSignature?, hasUnsavedChanges: Bool) -> ExternalChangeAction {
    guard let last, let current, last != current else { return .none }
    return hasUnsavedChanges ? .conflict : .reload
}

func diagnosticLineNumbers(in diagnostics: [String]) -> [Int] {
    let expression = try! NSRegularExpression(pattern: "第\\s*(\\d+)\\s*行")
    return Array(Set(diagnostics.compactMap { diagnostic -> Int? in
        let range = NSRange(diagnostic.startIndex..., in: diagnostic)
        guard let match = expression.firstMatch(in: diagnostic, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: diagnostic) else { return nil }
        return Int(diagnostic[swiftRange])
    })).sorted()
}

func updatedRecentPaths(_ paths: [String], adding path: String, limit: Int = 10) -> [String] {
    Array(([path] + paths.filter { $0 != path }).prefix(limit))
}

/// Finds the source ledger line named by the journal block at a rendered-report offset.
/// The report is deliberately plain text, so this keeps its navigation affordance
/// independent of a private view database.
func journalSourceLine(atReportOffset offset: Int, in renderedText: String) -> Int? {
    let source = renderedText as NSString
    guard offset >= 0, offset <= source.length else { return nil }
    let separator = source.range(of: "\n\n", options: .backwards, range: NSRange(location: 0, length: offset))
    let blockStart = separator.location == NSNotFound ? 0 : NSMaxRange(separator)
    let block = source.substring(with: NSRange(location: blockStart, length: offset - blockStart))
    let expression = try! NSRegularExpression(pattern: "第\\s*(\\d+)\\s*行")
    let range = NSRange(block.startIndex..., in: block)
    guard let match = expression.firstMatch(in: block, range: range),
          let lineRange = Range(match.range(at: 1), in: block) else { return nil }
    return Int(block[lineRange])
}

/// Resolves an account-tree line to a precise journal account query.  The tree
/// displays leaf names for readability, so duplicate leaf names deliberately
/// return nil rather than navigating to a potentially wrong account.
func accountFilterQuery(atReportOffset offset: Int, in renderedText: String, accounts: [String]) -> String? {
    let source = renderedText as NSString
    guard offset >= 0, offset <= source.length else { return nil }
    let lineRange = source.lineRange(for: NSRange(location: offset, length: 0))
    let line = source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let name = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) else { return nil }
    if accounts.contains(name) || ["资产", "负债", "权益", "收入", "费用"].contains(name) { return name }
    let matches = accounts.filter { $0.split(separator: ":").last.map(String.init) == name }
    return matches.count == 1 ? matches[0] : nil
}

func canonicalTransactionReplacement(source: String, date: String, summary: String, flag: Character?, payee: String?, tags: [String], links: [String] = [], destination: String, sourceAccount: String, amount: Decimal) -> String? {
    let lineEnding = source.contains("\r\n") ? "\r\n" : "\n"
    let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
    let lines = normalized.components(separatedBy: "\n")
    guard lines.count >= 3 else { return nil }
    var postingLines: [String] = []
    var metadataIndent: String?
    for line in lines.dropFirst() {
        guard line.first?.isWhitespace == true else { return nil }
        let body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix(";") {
            let metadata = transactionMetadata(fromComment: String(body.dropFirst()))
            let links = transactionLinks(fromComment: String(body.dropFirst()))
            guard metadata.payee != nil || !metadata.tags.isEmpty || !links.isEmpty else { return nil }
            metadataIndent = metadataIndent ?? String(line.prefix { $0 == " " || $0 == "\t" })
        } else {
            postingLines.append(line)
        }
    }
    guard postingLines.count == 2 else { return nil }
    let firstIndent = String(postingLines[0].prefix { $0 == " " || $0 == "\t" })
    let secondIndent = String(postingLines[1].prefix { $0 == " " || $0 == "\t" })
    let flagText = flag.map { " \($0)" } ?? ""
    let ending = source.hasSuffix("\r\n") || source.hasSuffix("\n") ? lineEnding : ""
    let commentIndent = metadataIndent ?? firstIndent
    let payeeLine = payee?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "\(lineEnding)\(commentIndent); 收款方: \(payee!.trimmingCharacters(in: .whitespacesAndNewlines))" : ""
    let tagLine = tags.isEmpty ? "" : "\(lineEnding)\(commentIndent); 标签: \(tags.joined(separator: ", "))"
    let linkLine = links.isEmpty ? "" : "\(lineEnding)\(commentIndent); 链接: \(links.joined(separator: ", "))"
    return "\(date)\(flagText) \(summary)\(payeeLine)\(tagLine)\(linkLine)\(lineEnding)\(firstIndent)\(destination)  \(LedgerParser.format(amount))\(lineEnding)\(secondIndent)\(sourceAccount)  \(LedgerParser.format(-amount))\(ending)"
}

enum LedgerParser {
    static let roots = Set(["资产", "负债", "权益", "收入", "费用", "Assets", "Liabilities", "Equity", "Income", "Expenses"])
    private static var gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// CountPaper 0.2: a Markdown outline. The source file is deliberately
    /// strict—there is no legacy transaction syntax fallback.
    static func parse(_ text: String) -> LedgerReport {
        var report = LedgerReport()
        var accounts = Set<String>()
        var current: [LedgerPosting] = []
        var transactionStart: Int?
        var transactionSummary: String?
        var transactionFlag: Character?
        var transactionPayee: String?
        var transactionTags: [String] = []
    var transactionLinkValues: [String] = []
        var transactionHasError = false
        var currentDate: String?
        var inFrontMatter = false
        var sawOpeningFence = false
        var sawClosingFence = false
        var sawAccountMarker = false
        var inAccountSection = false
        let lines = text.components(separatedBy: .newlines)

        func finishTransaction(at line: Int) {
            guard let start = transactionStart else { return }
            if current.count < 2 {
                report.diagnostics.append("错误：第 \(start) 行交易至少需要两条分录")
                transactionHasError = true
            }
            let total = current.reduce(Decimal.zero) { $0 + $1.amount }
            if total != .zero {
                report.diagnostics.append("错误：第 \(start) 行交易不平衡（差额 \(format(total))）")
                transactionHasError = true
            }
            if !transactionHasError {
                report.transactions += 1
                for posting in current {
                    report.balances[posting.account, default: .zero] += posting.amount
                    if isLedgerAccount(posting.account, .expense) { report.expenses[posting.account, default: .zero] += posting.amount }
                }
                report.journal.append(LedgerTransaction(date: currentDate ?? "", summary: transactionSummary ?? "", flag: transactionFlag, postings: current, payee: transactionPayee, tags: transactionTags, links: transactionLinkValues, startLine: start, endLine: max(start, line - 1)))
            }
            current = []
            transactionStart = nil
            transactionSummary = nil
            transactionFlag = nil
            transactionPayee = nil
            transactionTags = []
            transactionLinkValues = []
            transactionHasError = false
        }

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if !sawOpeningFence {
                if trimmed.isEmpty { continue }
                if trimmed == "---" { sawOpeningFence = true; inFrontMatter = true; continue }
                report.diagnostics.append("错误：第 \(lineNumber) 行应以 Markdown 文件头“---”开始")
                continue
            }
            if inFrontMatter {
                if trimmed == "---" { inFrontMatter = false; sawClosingFence = true; continue }
                if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }
                if trimmed == "format: countpaper/0.2" || trimmed.range(of: "^currency: [A-Z]{3}$", options: .regularExpression) != nil { continue }
                report.diagnostics.append("错误：第 \(lineNumber) 行文件头无法识别")
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }
            if trimmed == "@账户" {
                guard !sawAccountMarker, transactionStart == nil, currentDate == nil else { report.diagnostics.append("错误：第 \(lineNumber) 行 @账户 只能在正文开始处出现一次"); continue }
                sawAccountMarker = true
                inAccountSection = true
                continue
            }
            if rawLine.hasPrefix("# ") {
                finishTransaction(at: lineNumber)
                inAccountSection = false
                let date = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if isValidISODate(date) { currentDate = date } else { currentDate = nil; report.diagnostics.append("错误：第 \(lineNumber) 行日期标题应为“# YYYY-MM-DD”") }
                continue
            }
            if rawLine.hasPrefix("- ") {
                if inAccountSection {
                    let account = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    let root = account.split(separator: ":").first.map(String.init) ?? ""
                    if !roots.contains(root) || account.contains(" ") || account.contains("#") || account.hasSuffix(":") || account.hasPrefix(":") || !accounts.insert(account).inserted {
                        report.diagnostics.append("错误：第 \(lineNumber) 行账户声明无效「\(account)」")
                    }
                    continue
                }
                finishTransaction(at: lineNumber)
                guard let date = currentDate else { report.diagnostics.append("错误：第 \(lineNumber) 行交易必须位于日期标题下方"); continue }
                let remainder = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let marker = remainder.first
                transactionFlag = marker == "*" || marker == "!" ? marker : nil
                transactionSummary = String((transactionFlag == nil ? remainder : String(remainder.dropFirst())).trimmingCharacters(in: .whitespaces))
                if transactionSummary?.isEmpty != false { report.diagnostics.append("错误：第 \(lineNumber) 行交易摘要不能为空"); transactionHasError = true }
                currentDate = date
                transactionStart = lineNumber
                continue
            }
            if rawLine.hasPrefix("  - ") {
                guard transactionStart != nil else { report.diagnostics.append("错误：第 \(lineNumber) 行缩进条目没有所属交易"); continue }
                let body = String(rawLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if body.hasPrefix("收款方:") || body.hasPrefix("收款方：") {
                    transactionPayee = String(body.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if body.hasPrefix("标签:") || body.hasPrefix("标签：") {
                    for tag in transactionMetadata(fromComment: body).tags where !transactionTags.contains(tag) { transactionTags.append(tag) }
                    continue
                }
                if body.hasPrefix("链接:") || body.hasPrefix("链接：") {
                    for link in transactionLinks(fromComment: body) where !transactionLinkValues.contains(link) { transactionLinkValues.append(link) }
                    continue
                }
                let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2, let amount = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")), amount != .zero else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行分录应为“  - 账户名  金额”")
                    transactionHasError = true
                    continue
                }
                let account = String(parts[0])
                if !accounts.contains(account) { report.diagnostics.append("错误：第 \(lineNumber) 行使用了未声明账户「\(account)」"); transactionHasError = true }
                current.append(LedgerPosting(account: account, amount: amount, line: lineNumber))
                continue
            }
            report.diagnostics.append("错误：第 \(lineNumber) 行无法识别；请使用 # 日期、- 交易或两空格缩进的 - 分录")
        }
        finishTransaction(at: lines.count + 1)
        if !sawOpeningFence || !sawClosingFence { report.diagnostics.insert("错误：缺少完整的 Markdown 文件头（---）", at: 0) }
        if !text.contains("format: countpaper/0.2") { report.diagnostics.insert("错误：缺少“format: countpaper/0.2”", at: min(1, report.diagnostics.count)) }
        if text.range(of: "(?m)^currency: [A-Z]{3}$", options: .regularExpression) == nil { report.diagnostics.insert("错误：缺少三位大写 currency: 代码", at: min(2, report.diagnostics.count)) }
        if !sawAccountMarker { report.diagnostics.append("错误：缺少账户区标记“@账户”") }
        if accounts.isEmpty { report.diagnostics.append("错误：至少在 @账户 下声明一个账户") }
        report.accounts = accounts.sorted()
        return report
    }

    // Kept temporarily only to ease source migration while this file is being
    // refactored; it is not called, so 0.1 syntax is never accepted at runtime.
    private static func parseDeprecatedSyntax(_ text: String) -> LedgerReport {
        var report = LedgerReport()
        var accounts = Set<String>()
        var current: [LedgerPosting] = []
        var transactionStart: Int?
        var transactionDate: String?
        var transactionSummary: String?
        var transactionFlag: Character?
        var transactionPayee: String?
        var transactionTags: [String] = []
        var transactionLinkValues: [String] = []
        var transactionHasError = false
        var formatVersion: String?
        var hasHeader = false
        var hasCurrency = false
        var budgetKeys = Set<String>()
        var reconciliationKeys = Set<String>()
        var notedAccounts = Set<String>()
        let lines = text.components(separatedBy: .newlines)

        func finishTransaction(at line: Int) {
            guard let start = transactionStart else { return }
            if current.count < 2 { report.diagnostics.append("错误：第 \(start) 行交易至少需要两条分录"); transactionHasError = true }
            let total = current.reduce(Decimal.zero) { $0 + $1.amount }
            if total != .zero { report.diagnostics.append("错误：第 \(start) 行交易不平衡（差额 \(format(total))）"); transactionHasError = true }
            if !transactionHasError {
                report.transactions += 1
                for posting in current {
                    report.balances[posting.account, default: .zero] += posting.amount
                    if posting.account.hasPrefix("费用:") { report.expenses[posting.account, default: .zero] += posting.amount }
                }
                report.journal.append(LedgerTransaction(date: transactionDate ?? "", summary: transactionSummary ?? "", flag: transactionFlag, postings: current, payee: transactionPayee, tags: transactionTags, links: transactionLinkValues, startLine: start, endLine: max(start, line - 1)))
            }
            current = []
            transactionStart = nil
            transactionDate = nil
            transactionSummary = nil
            transactionFlag = nil
            transactionPayee = nil
            transactionTags = []
            transactionLinkValues = []
            transactionHasError = false
            _ = line
        }

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix(";") {
                if transactionStart != nil, rawLine.first?.isWhitespace == true {
                    let metadata = transactionMetadata(fromComment: String(trimmed.dropFirst()))
                    if let payee = metadata.payee { transactionPayee = payee }
                    for tag in metadata.tags where !transactionTags.contains(tag) { transactionTags.append(tag) }
                    for link in transactionLinks(fromComment: String(trimmed.dropFirst())) where !transactionLinkValues.contains(link) { transactionLinkValues.append(link) }
                }
                continue
            }
            if rawLine.first?.isWhitespace == true {
                guard transactionStart != nil else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行有未归属的缩进行")
                    continue
                }
                let body = trimmed.components(separatedBy: ";").first!.trimmingCharacters(in: .whitespaces)
                let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2, let amount = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")), amount != .zero else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行分录应为“账户名  金额”")
                    transactionHasError = true
                    continue
                }
                let account = String(parts[0])
                if !accounts.contains(account) { report.diagnostics.append("错误：第 \(lineNumber) 行使用了未声明账户「\(account)」"); transactionHasError = true }
                current.append(LedgerPosting(account: account, amount: amount, line: lineNumber))
                continue
            }

            finishTransaction(at: lineNumber)
            if trimmed == "账本 0.1" || trimmed == "账本 0.2" { hasHeader = true; formatVersion = String(trimmed.suffix(3)); continue }
            if trimmed.hasPrefix("本位币 ") {
                let value = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if value.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil { report.diagnostics.append("错误：第 \(lineNumber) 行本位币必须为三个大写字母") }
                hasCurrency = true; continue
            }
            if trimmed.hasPrefix("账户 ") {
                let account = String(trimmed.dropFirst(3)).components(separatedBy: ";").first!.trimmingCharacters(in: .whitespaces)
                let root = account.split(separator: ":").first.map(String.init) ?? ""
                if !roots.contains(root) || account.contains(" ") || account.contains(";") || account.contains("#") || account.hasSuffix(":") || account.hasPrefix(":") || accounts.contains(account) {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户声明无效「\(account)」")
                } else { accounts.insert(account) }
                continue
            }
            if trimmed.hasPrefix("账户备注 ") {
                let parts = trimmed.dropFirst(5).split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard formatVersion == "0.2" else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户备注需要使用「账本 0.2」")
                    continue
                }
                guard parts.count == 2,
                      accounts.contains(String(parts[0])) else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户备注应为“账户备注 已声明账户 内容”")
                    continue
                }
                let text = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, notedAccounts.insert(String(parts[0])).inserted else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户备注内容不能为空，且每个账户只能有一条备注")
                    continue
                }
                report.accountNotes.append(LedgerAccountNote(account: String(parts[0]), text: text, line: lineNumber))
                continue
            }
            if trimmed.hasPrefix("预算 ") {
                let parts = trimmed.dropFirst(3).split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard formatVersion == "0.2" else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行预算需要使用「账本 0.2」")
                    continue
                }
                guard parts.count == 3,
                      isValidMonth(String(parts[0])),
                      accounts.contains(String(parts[1])),
                      String(parts[1]).hasPrefix("费用:"),
                      let amount = Decimal(string: String(parts[2]), locale: Locale(identifier: "en_US_POSIX")), amount > .zero else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行预算应为“预算 YYYY-MM 费用:账户 金额”，且账户须已声明")
                    continue
                }
                let month = String(parts[0]); let account = String(parts[1]); let key = "\(month)\u{1F}\(account)"
                guard budgetKeys.insert(key).inserted else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行重复设置预算「\(month) \(account)」")
                    continue
                }
                report.budgets.append(LedgerBudget(month: month, account: account, amount: amount, line: lineNumber))
                continue
            }
            if trimmed.hasPrefix("对账 ") {
                let parts = trimmed.dropFirst(3).split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard formatVersion == "0.2" else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行对账需要使用「账本 0.2」")
                    continue
                }
                guard parts.count == 3,
                      isValidISODate(String(parts[0])),
                      accounts.contains(String(parts[1])),
                      (String(parts[1]).hasPrefix("资产:") || String(parts[1]).hasPrefix("负债:")),
                      let balance = Decimal(string: String(parts[2]), locale: Locale(identifier: "en_US_POSIX")) else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行对账应为“对账 YYYY-MM-DD 资产或负债账户 账面余额”")
                    continue
                }
                let date = String(parts[0]); let account = String(parts[1]); let key = "\(date)\u{1F}\(account)"
                guard reconciliationKeys.insert(key).inserted else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行重复对账「\(date) \(account)」")
                    continue
                }
                report.reconciliations.append(LedgerReconciliation(date: date, account: account, statementBalance: balance, line: lineNumber))
                continue
            }
            if trimmed.hasPrefix("事件 ") {
                let parts = trimmed.dropFirst(3).split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard formatVersion == "0.2" else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行事件需要使用「账本 0.2」")
                    continue
                }
                guard parts.count == 2,
                      isValidISODate(String(parts[0])) else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行事件应为“事件 YYYY-MM-DD 内容”")
                    continue
                }
                let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行事件内容不能为空")
                    continue
                }
                report.events.append(LedgerEvent(date: String(parts[0]), title: title, line: lineNumber))
                continue
            }
            if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s+[*!])?\\s+.+$", options: .regularExpression) != nil {
                let dateText = String(trimmed.prefix(10))
                transactionHasError = !isValidISODate(dateText)
                if transactionHasError { report.diagnostics.append("错误：第 \(lineNumber) 行日期无效") }
                let remainder = String(trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces))
                let marker = remainder.first
                transactionFlag = marker == "*" || marker == "!" ? marker : nil
                transactionSummary = String((transactionFlag == nil ? remainder : String(remainder.dropFirst())).trimmingCharacters(in: .whitespaces))
                transactionDate = dateText
                transactionStart = lineNumber
            } else {
                report.diagnostics.append("错误：第 \(lineNumber) 行无法识别")
            }
        }
        finishTransaction(at: lines.count + 1)
        if !hasHeader { report.diagnostics.insert("错误：缺少首行版本声明「账本 0.1」或「账本 0.2」", at: 0) }
        if !hasCurrency { report.diagnostics.insert("错误：缺少「本位币 CNY」声明", at: min(1, report.diagnostics.count)) }
        if accounts.isEmpty { report.diagnostics.append("错误：至少声明一个账户") }
        report.accounts = accounts.sorted()
        return report
    }

    static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    private static func isValidISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var components = DateComponents()
        components.calendar = gregorianCalendar
        components.year = year
        components.month = month
        components.day = day
        guard let date = gregorianCalendar.date(from: components) else { return false }
        let verified = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        return verified.year == year && verified.month == month && verified.day == day
    }

    private static func isValidMonth(_ value: String) -> Bool {
        guard value.range(of: "^\\d{4}-\\d{2}$", options: .regularExpression) != nil,
              let month = Int(value.suffix(2)) else { return false }
        return (1...12).contains(month)
    }
}

final class JournalReportTextView: NSTextView {
    var onReportClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let location = convert(event.locationInWindow, from: nil)
        onReportClick?(characterIndexForInsertion(at: location))
    }

    override func insertNewline(_ sender: Any?) {
        onReportClick?(selectedRange().location)
    }
}

/// CountPaper retains a live source document in memory. Command-W shelves the
/// window instead of closing the last native window, avoiding the termination
/// path while keeping the requested shortcut behaviour.
final class CountPaperWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A compact native chart: muted bars communicate monthly income/expense, while
/// the line keeps the period's net result visible without introducing a web view.
final class PersonalReportChartView: NSView {
    var monthly: [MonthlyPersonalSummary] = [] {
        didSet {
            setAccessibilityValue(monthly.isEmpty ? "暂无趋势数据" : "包含 \(monthly.count) 个统计月份的收入、支出与结余趋势")
            needsDisplay = true
        }
    }
    var expenseCategories: [String: Decimal] = [:] { didSet { needsDisplay = true } }
    var tagExpenses: [String: Decimal] = [:] { didSet { needsDisplay = true } }
    var kind: PersonalReportKind = .trend { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityLabel("个人报表图表")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        switch kind {
        case .trend: drawTrend()
        case .category: drawPieReport(title: "支出分类", values: expenseCategories, stripPrefix: "费用:")
        case .tag: drawPieReport(title: "标签支出", values: tagExpenses, stripPrefix: "")
        }
    }

    private func drawTrend() {
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        ("收支趋势" as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 24), withAttributes: titleAttributes)
        ("收入 / 支出 / 结余" as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 39), withAttributes: detailAttributes)
        let series = Array(monthly.suffix(6))
        guard !series.isEmpty else {
            ("录入跨月交易后显示柱状与结余曲线" as NSString).draw(at: NSPoint(x: 14, y: bounds.midY - 6), withAttributes: detailAttributes)
            return
        }
        let plot = NSRect(x: 30, y: 25, width: max(40, bounds.width - 46), height: max(38, bounds.height - 76))
        let dataMaximum = max(series.reduce(1.0) { partial, item in
            max(partial, decimalDouble(item.summary.incomeTotal), decimalDouble(item.summary.expenseTotal), abs(decimalDouble(item.summary.net)))
        }, 1)
        // Leave headroom so one month's only expense does not turn into a
        // misleading full-height column. Income belongs above zero, expense
        // below it, and the net line moves on both sides of the baseline.
        let maximum = dataMaximum / 0.76
        let baseline = plot.midY
        let halfHeight = plot.height / 2
        let gridColor = NSColor.separatorColor.withAlphaComponent(0.55)
        for fraction in [0.0, 0.5, 1.0] {
            let y = plot.minY + plot.height * fraction
            gridColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            path.lineWidth = fraction == 0.5 ? 1.0 : 0.5
            path.stroke()
        }
        let incomeColor = NSColor.systemGreen.blended(withFraction: 0.42, of: .controlBackgroundColor) ?? .systemGreen
        let expenseColor = NSColor.systemRed.blended(withFraction: 0.42, of: .controlBackgroundColor) ?? .systemRed
        let netColor = NSColor.systemBlue.blended(withFraction: 0.34, of: .controlBackgroundColor) ?? .systemBlue
        let step = plot.width / CGFloat(series.count)
        let barWidth = max(4, min(16, step * 0.20))
        let line = NSBezierPath()
        for (index, item) in series.enumerated() {
            let centerX = plot.minX + step * (CGFloat(index) + 0.5)
            let incomeHeight = max(0, min(halfHeight, halfHeight * CGFloat(decimalDouble(item.summary.incomeTotal) / maximum)))
            let expenseHeight = max(0, min(halfHeight, halfHeight * CGFloat(decimalDouble(item.summary.expenseTotal) / maximum)))
            incomeColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: centerX - barWidth - 2, y: baseline, width: barWidth, height: incomeHeight), xRadius: 2, yRadius: 2).fill()
            expenseColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: centerX + 2, y: baseline - expenseHeight, width: barWidth, height: expenseHeight), xRadius: 2, yRadius: 2).fill()
            let netY = baseline + max(-halfHeight, min(halfHeight, halfHeight * CGFloat(decimalDouble(item.summary.net) / maximum)))
            if index == 0 { line.move(to: NSPoint(x: centerX, y: netY)) } else { line.line(to: NSPoint(x: centerX, y: netY)) }
            let label = "\(item.month.suffix(2))月"
            let labelSize = (label as NSString).size(withAttributes: detailAttributes)
            (label as NSString).draw(at: NSPoint(x: centerX - labelSize.width / 2, y: 7), withAttributes: detailAttributes)
        }
        netColor.setStroke()
        line.lineWidth = 1.7
        line.stroke()
        for (index, item) in series.enumerated() {
            let centerX = plot.minX + step * (CGFloat(index) + 0.5)
            let netY = baseline + max(-halfHeight, min(halfHeight, halfHeight * CGFloat(decimalDouble(item.summary.net) / maximum)))
            netColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: centerX - 2.4, y: netY - 2.4, width: 4.8, height: 4.8)).fill()
        }
    }

    private func drawPieReport(title: String, values: [String: Decimal], stripPrefix: String) {
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        (title as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 24), withAttributes: titleAttributes)
        let entries = values.sorted { $0.value > $1.value }
        let total = entries.reduce(Decimal.zero) { $0 + $1.value }
        guard total > .zero else {
            ("当前筛选条件下暂无可统计数据" as NSString).draw(at: NSPoint(x: 14, y: bounds.midY - 6), withAttributes: detailAttributes)
            return
        }
        let colors: [NSColor] = [.systemOrange, .systemPurple, .systemTeal, .systemPink, .systemBlue].map { $0.blended(withFraction: 0.40, of: .controlBackgroundColor) ?? $0 }
        let diameter = min(112, bounds.height - 54, bounds.width * 0.35)
        let center = NSPoint(x: 28 + diameter / 2, y: bounds.midY - 4)
        let radius = diameter / 2
        var angle = CGFloat(90)
        for (index, entry) in entries.prefix(5).enumerated() {
            let portion = CGFloat(NSDecimalNumber(decimal: entry.value / total).doubleValue) * 360
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle - portion, clockwise: true)
            path.close()
            colors[index % colors.count].setFill()
            path.fill()
            angle -= portion
        }
        let legendX = center.x + radius + 18
        for (index, entry) in entries.prefix(5).enumerated() {
            let labelKey = entry.key.replacingOccurrences(of: stripPrefix, with: "")
            let label = "\(stripPrefix.isEmpty ? "#" : "")\(labelKey)  \(LedgerParser.format(entry.value))"
            colors[index % colors.count].setFill()
            NSBezierPath(roundedRect: NSRect(x: legendX, y: bounds.height - 50 - CGFloat(index * 22), width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            (label as NSString).draw(at: NSPoint(x: legendX + 14, y: bounds.height - 53 - CGFloat(index * 22)), withAttributes: detailAttributes)
        }
    }

    private func decimalDouble(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

/// Owns the live controls in the unified quick-entry sheet. Switching the
/// transaction kind only changes form choices; no ledger text is touched until
/// the user confirms a record action.
final class QuickEntryFormBinder: NSObject {
    let report: LedgerReport
    let allAccounts: [String]
    let english: Bool
    weak var kindControl: NSSegmentedControl?
    weak var suggestionPicker: NSPopUpButton?
    weak var destinationLabel: NSTextField?
    weak var sourceLabel: NSTextField?
    weak var summaryField: NSTextField?
    weak var payeeField: NSTextField?
    weak var tagsField: NSTextField?
    weak var destinationPicker: NSPopUpButton?
    weak var sourcePicker: NSPopUpButton?
    weak var amountField: NSTextField?
    private(set) var suggestions: [QuickEntrySuggestion] = []

    init(report: LedgerReport, allAccounts: [String], english: Bool, kindControl: NSSegmentedControl, suggestionPicker: NSPopUpButton, destinationLabel: NSTextField, sourceLabel: NSTextField, summaryField: NSTextField, payeeField: NSTextField, tagsField: NSTextField, destinationPicker: NSPopUpButton, sourcePicker: NSPopUpButton, amountField: NSTextField) {
        self.report = report
        self.allAccounts = allAccounts
        self.english = english
        self.kindControl = kindControl
        self.suggestionPicker = suggestionPicker
        self.destinationLabel = destinationLabel
        self.sourceLabel = sourceLabel
        self.summaryField = summaryField
        self.payeeField = payeeField
        self.tagsField = tagsField
        self.destinationPicker = destinationPicker
        self.sourcePicker = sourcePicker
        self.amountField = amountField
        super.init()
        kindControl.target = self
        kindControl.action = #selector(changeKind(_:))
        suggestionPicker.target = self
        suggestionPicker.action = #selector(applySuggestion(_:))
        refreshForSelectedKind()
    }

    var kind: QuickEntryKind {
        QuickEntryKind(rawValue: kindControl?.selectedSegment ?? 0) ?? .expense
    }

    @objc func changeKind(_ sender: NSSegmentedControl) {
        refreshForSelectedKind()
        amountField?.becomeFirstResponder()
    }

    @objc func applySuggestion(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        guard suggestions.indices.contains(index) else { return }
        let suggestion = suggestions[index]
        summaryField?.stringValue = suggestion.summary
        payeeField?.stringValue = suggestion.payee ?? ""
        tagsField?.stringValue = suggestion.tags.joined(separator: ", ")
        destinationPicker?.selectItem(withTitle: suggestion.destination)
        sourcePicker?.selectItem(withTitle: suggestion.source)
        amountField?.stringValue = LedgerParser.format(suggestion.amount)
        amountField?.becomeFirstResponder()
    }

    func rememberAccountChoices() {
        if let destination = destinationPicker?.titleOfSelectedItem {
            UserDefaults.standard.set(destination, forKey: "quick.\(kind.defaultSummary).destination")
        }
        if let source = sourcePicker?.titleOfSelectedItem {
            UserDefaults.standard.set(source, forKey: "quick.\(kind.defaultSummary).source")
        }
    }

    private func refreshForSelectedKind() {
        let options = quickEntryAccountOptions(accounts: allAccounts, kind: kind)
        repopulate(destinationPicker, with: options.destination, rememberedKey: "quick.\(kind.defaultSummary).destination")
        repopulate(sourcePicker, with: options.source, rememberedKey: "quick.\(kind.defaultSummary).source")
        let labels: (String, String)
        switch kind {
        case .expense: labels = english ? ("Category", "Paid from") : ("费用分类", "付款账户")
        case .income: labels = english ? ("Received in", "Income category") : ("收款账户", "收入分类")
        case .transfer: labels = english ? ("Transfer to", "Transfer from") : ("转入账户", "转出账户")
        }
        destinationLabel?.stringValue = labels.0
        sourceLabel?.stringValue = labels.1

        suggestions = quickEntrySuggestions(report: report, kind: kind)
        suggestionPicker?.removeAllItems()
        suggestionPicker?.addItem(withTitle: english ? "Fill from a recent transaction…" : "从最近交易填入…")
        for suggestion in suggestions {
            suggestionPicker?.addItem(withTitle: "\(suggestion.summary) · \(LedgerParser.format(suggestion.amount))")
        }
        suggestionPicker?.isEnabled = !suggestions.isEmpty
        if suggestions.isEmpty {
            suggestionPicker?.item(at: 0)?.title = english ? "No recent transactions" : "暂无最近交易"
        }
    }

    private func repopulate(_ picker: NSPopUpButton?, with items: [String], rememberedKey: String) {
        guard let picker else { return }
        let current = picker.titleOfSelectedItem
        picker.removeAllItems()
        picker.addItems(withTitles: items)
        if let current, items.contains(current) { picker.selectItem(withTitle: current) }
        else if let remembered = UserDefaults.standard.string(forKey: rememberedKey), items.contains(remembered) { picker.selectItem(withTitle: remembered) }
    }
}

struct CommandPaletteItem {
    let title: String
    let detail: String
    let action: () -> Void
}

private final class CommandPalettePanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// A small native command palette.  It stays deliberately local: commands are
/// actions already available in the menu bar and no command history is stored.
final class CommandPaletteController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let items: [CommandPaletteItem]
    private var filtered: [CommandPaletteItem] = []
    private let panel: CommandPalettePanel
    private let searchField = NSSearchField(frame: .zero)
    private let table = NSTableView(frame: .zero)

    init(items: [CommandPaletteItem]) {
        self.items = items
        panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 530, height: 338), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "命令面板"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        searchField.frame = NSRect(x: 18, y: 292, width: 494, height: 28)
        searchField.placeholderString = "输入命令，例如：支出、日记账、保存"
        searchField.delegate = self
        searchField.setAccessibilityLabel("搜索命令")
        content.addSubview(searchField)

        let scroll = NSScrollView(frame: NSRect(x: 18, y: 54, width: 494, height: 226))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        table.headerView = nil
        table.rowHeight = 42
        table.selectionHighlightStyle = .regular
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(executeSelected(_:))
        table.setAccessibilityLabel("命令结果")
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command")))
        scroll.documentView = table
        content.addSubview(scroll)

        let hint = NSTextField(labelWithString: "↑↓ 选择  ·  Return 执行  ·  Esc 取消")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.frame = NSRect(x: 18, y: 18, width: 360, height: 20)
        content.addSubview(hint)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        cancel.frame = NSRect(x: 428, y: 12, width: 84, height: 28)
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)
        refresh()
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.runModal(for: panel)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("commandCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = identifier
        cell.subviews.forEach { $0.removeFromSuperview() }
        let item = filtered[row]
        let label = NSTextField(wrappingLabelWithString: "\(item.title)\n\(item.detail)")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 8, y: 3, width: max(100, tableView.bounds.width - 16), height: 36)
        label.autoresizingMask = [.width]
        cell.addSubview(label)
        return cell
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) { moveSelection(by: 1); return true }
        if commandSelector == #selector(NSResponder.moveUp(_:)) { moveSelection(by: -1); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { executeSelected(nil); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        return false
    }

    @objc private func executeSelected(_ sender: Any?) {
        guard !filtered.isEmpty else { return }
        let index = table.selectedRow >= 0 ? table.selectedRow : 0
        guard filtered.indices.contains(index) else { return }
        let action = filtered[index].action
        dismiss()
        DispatchQueue.main.async(execute: action)
    }

    @objc private func cancel(_ sender: Any?) { dismiss() }

    func windowWillClose(_ notification: Notification) { NSApp.stopModal() }

    private func refresh() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = max(0, table.selectedRow)
        let next = min(max(0, current + delta), filtered.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func dismiss() {
        NSApp.stopModal()
        panel.orderOut(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    private var window: NSWindow!
    private let textView = LedgerTextView()
    private var sourceWindow: NSPanel?
    private let dashboardTitleLabel = NSTextField(labelWithString: "")
    private let dashboardIncomeLabel = NSTextField(labelWithString: "")
    private let dashboardExpenseLabel = NSTextField(labelWithString: "")
    private let dashboardNetLabel = NSTextField(labelWithString: "")
    private let dashboardRecentView = NSTextView()
    private let inlineKindControl = NSSegmentedControl(labels: ["支出", "收入", "转账"], trackingMode: .selectOne, target: nil, action: nil)
    private let inlineSuggestionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inlineAmountField = NSTextField(string: "")
    private let inlineSummaryField = NSTextField(string: "")
    private let inlineDestinationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inlineSourcePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inlineDestinationLabel = NSTextField(labelWithString: "")
    private let inlineSourceLabel = NSTextField(labelWithString: "")
    private let inlinePayeeField = NSTextField(string: "")
    private let inlineTagsField = NSTextField(string: "")
    private let inlineDatePicker = NSDatePicker()
    private let inlineDateButton = NSButton(title: "", target: nil, action: nil)
    private let inlineTodayButton = NSButton(title: "", target: nil, action: nil)
    private let inlineYesterdayButton = NSButton(title: "", target: nil, action: nil)
    private var inlineEntryBinder: QuickEntryFormBinder?
    private let reportView = JournalReportTextView()
    private let reportChartView = PersonalReportChartView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let ledgerTabControl = NSSegmentedControl(frame: .zero)
    private let ledgerTabsTitle = NSTextField(labelWithString: "")
    private var ledgerSessions: [LedgerSession] = []
    private var activeLedgerIndex = 0
    private var isSwitchingLedgerSession = false
    private var hasApprovedTermination = false
    private var documentURL: URL?
    private var isDirty = false
    private var autosaveWorkItem: DispatchWorkItem?
    private let parseQueue = DispatchQueue(label: "com.countpaper.parse", qos: .userInitiated)
    private var parseWorkItem: DispatchWorkItem?
    private var parseGeneration = 0
    private var latestReport = LedgerReport()
    private enum SidePanelMode { case overview, journal, accounts, reports }
    private var sidePanelMode: SidePanelMode = .overview
    private weak var sidePanelControl: NSSegmentedControl?
    private var sidebarButtons: [NSButton] = []
    private let documentNameLabel = NSTextField(labelWithString: "")
    private let inspectorTitleLabel = NSTextField(labelWithString: "")
    private weak var journalFilterContainer: NSStackView?
    private weak var reportFilterContainer: NSStackView?
    private weak var dashboardContainer: NSView?
    private weak var inspectorContainer: NSView?
    private var inspectorCompactWidthConstraint: NSLayoutConstraint?
    private let periodPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reportLedgerScopePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var reportsAllOpenLedgers = false
    private let reportKindControl = NSSegmentedControl(labels: PersonalReportKind.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let reportTagPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reportAccountPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let journalSearchField = NSSearchField(frame: .zero)
    private let journalSearchScope = NSPopUpButton(frame: .zero, pullsDown: false)
    private let journalStatusFilter = NSPopUpButton(frame: .zero, pullsDown: false)
    private var journalQuery = ""
    private var journalSearchFieldScope: JournalSearchField = .all
    private var journalStatus: JournalStatusFilter = .all
    private var selectedReportMonth: String?
    private var selectedReportStartDate: String?
    private var selectedReportEndDate: String?
    private var selectedReportTag: String?
    private var selectedReportAccount: String?
    private var selectedReportKind: PersonalReportKind = .trend
    private var hasInitializedReportPeriod = false
    private var hasCompletedLaunch = false
    private var pendingOpenURL: URL?
    private var lastKnownFileSignature: LedgerFileSignature?
    private var hasExternalConflict = false
    private var fileMonitorTimer: Timer?
    private let recentMenu = NSMenu(title: "最近使用")
    private let countPaperContentType = UTType(filenameExtension: "countpaper") ?? .plainText
    private var quickEntryFormBinder: QuickEntryFormBinder?
    private let syntaxHighlightLimit = 1_500_000
    private var highlightedReportLine: NSRange?
    private var allowsMultipleAmounts: Bool { UserDefaults.standard.bool(forKey: CountPaperPreference.multipleAmounts) }
    private var appLanguage: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: CountPaperPreference.language) ?? "chinese") ?? .chinese }

    private func ui(_ chinese: String, _ english: String) -> String { appLanguage == .english ? english : chinese }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = "CountPaper"
        alert.informativeText = ui("版本 \(version)（构建 \(build)）\n纯文本个人账本", "Version \(version) (Build \(build))\nA plain-text personal ledger")
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: ui("好", "OK"))
        alert.runModal()
    }

    @objc private func hideMainWindow(_ sender: Any?) {
        window.orderOut(nil)
    }

    /// Explicitly callable from the app entry point. Some launch paths can
    /// deliver AppKit's finish notification before a delegate is observed;
    /// keeping this idempotent gives every path the same real main window.
    func launchApplicationInterface() {
        guard !hasCompletedLaunch else { return }
        hasCompletedLaunch = true
        // Batch entry is the normal quick-entry behaviour. Registering a
        // default preserves the Settings switch while making “32 57” work for
        // every new installation instead of silently treating it as invalid.
        UserDefaults.standard.register(defaults: [CountPaperPreference.multipleAmounts: true])
        if !UserDefaults.standard.bool(forKey: CountPaperPreference.multipleAmountsMigrated) {
            UserDefaults.standard.set(true, forKey: CountPaperPreference.multipleAmounts)
            UserDefaults.standard.set(true, forKey: CountPaperPreference.multipleAmountsMigrated)
        }
        buildMenu()
        buildWindow()
        buildSourceWindow()
        if let url = pendingOpenURL { loadDocument(at: url) }
        else { loadUntitledSample() }
        fileMonitorTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(checkForExternalChanges), userInfo: nil, repeats: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.layoutDocumentViews() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchApplicationInterface()
    }

    /// Match document-style macOS apps: closing the final window does not quit
    /// the process; the user can reopen it from the Dock or File menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            revealMainWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hasApprovedTermination { return .terminateNow }
        if confirmClosingAllLedgers() {
            hasApprovedTermination = true
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { fileMonitorTimer?.invalidate() }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        // Finder may deliver an open event while restoring a shelved app. This
        // delegate is already called on the main thread: do the work here.
        // Posting another main-queue block used to retain a stale window path
        // after Command-W, which is the crash reported by users reopening files.
        guard url.isFileURL, url.pathExtension.lowercased() == "countpaper" else {
            revealMainWindow()
            return
        }
        guard window != nil else {
            pendingOpenURL = url
            return
        }
        loadDocument(at: url)
        revealMainWindow()
    }

    private func revealMainWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); menu.addItem(app)
        let appMenu = NSMenu(); app.submenu = appMenu
        let about = appMenu.addItem(withTitle: ui("关于 CountPaper", "About CountPaper"), action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: ui("设置…", "Settings…"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: ui("退出 CountPaper", "Quit CountPaper"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let command = NSMenuItem(title: ui("命令", "Commands"), action: nil, keyEquivalent: ""); menu.addItem(command)
        let commandMenu = NSMenu(title: ui("命令", "Commands")); command.submenu = commandMenu
        commandMenu.addItem(withTitle: ui("打开命令面板…", "Open Command Palette…"), action: #selector(presentCommandPalette(_:)), keyEquivalent: "k")
        let file = NSMenuItem(title: ui("文件", "File"), action: nil, keyEquivalent: ""); menu.addItem(file)
        let fileMenu = NSMenu(title: ui("文件", "File")); file.submenu = fileMenu
        fileMenu.addItem(withTitle: ui("新建", "New"), action: #selector(newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: ui("打开…", "Open…"), action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: ui("保存", "Save"), action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: ui("另存为…", "Save As…"), action: #selector(saveAs(_:)), keyEquivalent: "S")
        let source = fileMenu.addItem(withTitle: ui("查看原始文本", "View Source Text"), action: #selector(showSourceEditor(_:)), keyEquivalent: "")
        source.target = self
        let externalSource = fileMenu.addItem(withTitle: ui("在文本 App 中编辑…", "Edit in Text App…"), action: #selector(openLedgerInTextEditor(_:)), keyEquivalent: "")
        externalSource.target = self
        let hideWindow = fileMenu.addItem(withTitle: ui("隐藏窗口", "Hide Window"), action: #selector(hideMainWindow(_:)), keyEquivalent: "w")
        hideWindow.target = self
        fileMenu.addItem(withTitle: ui("从磁盘重新载入", "Reload from Disk"), action: #selector(reloadFromDisk(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "设为 .countpaper 默认打开应用", action: #selector(setAsDefaultEditor(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "导出当前收支报表 CSV…", action: #selector(exportReportCSV(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "导出当前日记账 CSV…", action: #selector(exportJournalCSV(_:)), keyEquivalent: "")
        let recent = NSMenuItem(title: "最近使用", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        fileMenu.addItem(recent)
        rebuildRecentMenu()
        let edit = NSMenuItem(title: ui("编辑", "Edit"), action: nil, keyEquivalent: ""); menu.addItem(edit)
        let editMenu = NSMenu(title: ui("编辑", "Edit")); edit.submenu = editMenu
        editMenu.addItem(withTitle: ui("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: ui("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "向右缩进", action: #selector(indentSelectedLines(_:)), keyEquivalent: "]")
        editMenu.addItem(withTitle: "向左缩进", action: #selector(outdentSelectedLines(_:)), keyEquivalent: "[")
        let find = editMenu.addItem(withTitle: "查找…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editMenu.addItem(withTitle: "跳转到行…", action: #selector(goToLine(_:)), keyEquivalent: "l")
        let ledger = NSMenuItem(title: ui("账本", "Ledger"), action: nil, keyEquivalent: ""); menu.addItem(ledger)
        let ledgerMenu = NSMenu(title: ui("账本", "Ledger")); ledger.submenu = ledgerMenu
        ledgerMenu.addItem(withTitle: ui("记一笔…", "Record Transaction…"), action: #selector(recordTransaction(_:)), keyEquivalent: "e")
        ledgerMenu.addItem(.separator())
        ledgerMenu.addItem(withTitle: "添加账户…", action: #selector(addAccount(_:)), keyEquivalent: "a")
        ledgerMenu.addItem(withTitle: "添加账户备注…", action: #selector(addAccountNote(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "添加对账记录…", action: #selector(addReconciliation(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "添加事件…", action: #selector(addEvent(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "编辑光标所在交易…", action: #selector(editTransactionAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "打开光标所在交易的链接…", action: #selector(openTransactionLinkAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "标记待确认／确认光标所在交易", action: #selector(toggleTransactionStatusAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "删除光标所在交易…", action: #selector(deleteTransactionAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: "重新校验", action: #selector(reparseNow), keyEquivalent: "r")
        ledgerMenu.addItem(withTitle: "跳到下一个错误", action: #selector(jumpToNextDiagnostic(_:)), keyEquivalent: "j")
        let help = NSMenuItem(title: "帮助", action: nil, keyEquivalent: ""); menu.addItem(help)
        let helpMenu = NSMenu(title: "帮助"); help.submenu = helpMenu
        helpMenu.addItem(withTitle: "CountPaper 文本格式速查", action: #selector(showFormatQuickReference(_:)), keyEquivalent: "?")
        NSApp.mainMenu = menu
    }

    private func buildSourceWindow() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.title = ui("编辑原始文本", "Edit Source Text")
        panel.minSize = NSSize(width: 500, height: 360)
        let scroll = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 22, height: 20)
        textView.isEditable = true
        textView.isSelectable = true
        textView.setAccessibilityLabel(ui("原始账本文本编辑器", "Source ledger text editor"))
        textView.drawsBackground = true
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlTextColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = self
        textView.allowsUndo = true
        scroll.documentView = textView
        panel.contentView?.addSubview(scroll)
        sourceWindow = panel
    }

    private func buildDashboard() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.972, alpha: 1).cgColor
        container.layer?.masksToBounds = true
        let stack = NSStackView(frame: container.bounds)
        stack.orientation = .vertical
        stack.alignment = .width; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Attach the stack before activating constraints from its arranged
        // subviews to `container`; AppKit requires a common ancestor.
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 700),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        dashboardTitleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        dashboardTitleLabel.alignment = .left
        dashboardTitleLabel.widthAnchor.constraint(equalToConstant: 644).isActive = true
        stack.addArrangedSubview(dashboardTitleLabel)
        let statRow = NSStackView(); statRow.orientation = .horizontal; statRow.spacing = 10; statRow.distribution = .fillEqually
        statRow.widthAnchor.constraint(equalToConstant: 644).isActive = true
        [dashboardIncomeLabel, dashboardExpenseLabel, dashboardNetLabel].forEach { label in
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.wantsLayer = true; label.layer?.cornerRadius = 12
            label.layer?.backgroundColor = NSColor(calibratedWhite: 0.945, alpha: 1).cgColor
            label.alignment = .center
            label.heightAnchor.constraint(equalToConstant: 70).isActive = true
            statRow.addArrangedSubview(label)
        }
        stack.addArrangedSubview(statRow)

        let entryCard = NSView(); entryCard.wantsLayer = true; entryCard.layer?.cornerRadius = 12
        entryCard.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 1).cgColor
        entryCard.layer?.borderWidth = 0.5; entryCard.layer?.borderColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
        entryCard.widthAnchor.constraint(equalToConstant: 644).isActive = true
        let entry = NSStackView(); entry.orientation = .vertical; entry.alignment = .leading; entry.spacing = 8
        entry.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18); entry.translatesAutoresizingMaskIntoConstraints = false
        let entryTitle = NSTextField(labelWithString: ui("记账", "Record")); entryTitle.font = .systemFont(ofSize: 15, weight: .semibold); entry.addArrangedSubview(entryTitle)
        inlineKindControl.selectedSegment = 0; inlineKindControl.setAccessibilityLabel(ui("交易类型", "Transaction type")); entry.addArrangedSubview(inlineKindControl)
        let firstRow = NSStackView(); firstRow.orientation = .horizontal; firstRow.spacing = 8
        inlineAmountField.placeholderString = ui("金额，如 32 57", "Amount, e.g. 32 57"); inlineAmountField.setAccessibilityLabel(ui("金额，可输入多个数字", "Amount; multiple values supported")); inlineAmountField.widthAnchor.constraint(equalToConstant: 138).isActive = true
        inlineSummaryField.placeholderString = ui("摘要（可选）", "Description (optional)"); inlineSummaryField.widthAnchor.constraint(equalToConstant: 210).isActive = true
        configureInlineDatePicker()
        configureInlineDateShortcutButtons()
        inlineDateButton.target = self; inlineDateButton.action = #selector(showInlineDateCalendar(_:))
        inlineDateButton.bezelStyle = .texturedRounded
        inlineDateButton.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: ui("选择日期", "Choose date"))
        inlineDateButton.imagePosition = .imageLeading
        inlineDateButton.setAccessibilityLabel(ui("记账日期", "Transaction date"))
        inlineDateButton.toolTip = ui("选择记账日期", "Choose transaction date")
        inlineDateButton.widthAnchor.constraint(equalToConstant: 116).isActive = true
        updateInlineDateButtonTitle()
        firstRow.addArrangedSubview(inlineAmountField); firstRow.addArrangedSubview(inlineSummaryField); firstRow.addArrangedSubview(inlineTodayButton); firstRow.addArrangedSubview(inlineYesterdayButton); firstRow.addArrangedSubview(inlineDateButton); entry.addArrangedSubview(firstRow)
        let accountRow = NSStackView(); accountRow.orientation = .horizontal; accountRow.spacing = 8
        inlineDestinationLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        inlineDestinationPicker.widthAnchor.constraint(equalToConstant: 224).isActive = true
        inlineSourceLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        inlineSourcePicker.widthAnchor.constraint(equalToConstant: 224).isActive = true
        accountRow.addArrangedSubview(inlineDestinationLabel); accountRow.addArrangedSubview(inlineDestinationPicker); accountRow.addArrangedSubview(inlineSourceLabel); accountRow.addArrangedSubview(inlineSourcePicker); entry.addArrangedSubview(accountRow)
        let actionRow = NSStackView(); actionRow.orientation = .horizontal; actionRow.spacing = 8
        inlineSuggestionPicker.widthAnchor.constraint(equalToConstant: 220).isActive = true; inlineSuggestionPicker.setAccessibilityLabel(ui("最近交易模板", "Recent transaction templates"))
        let save = NSButton(title: ui("记入账本", "Record"), target: self, action: #selector(recordInlineTransaction(_:))); save.bezelStyle = .rounded; save.contentTintColor = NSColor(calibratedRed: 0.32, green: 0.42, blue: 0.34, alpha: 1)
        actionRow.addArrangedSubview(inlineSuggestionPicker); actionRow.addArrangedSubview(save); entry.addArrangedSubview(actionRow)
        entryCard.addSubview(entry)
        NSLayoutConstraint.activate([
            entry.leadingAnchor.constraint(equalTo: entryCard.leadingAnchor), entry.trailingAnchor.constraint(equalTo: entryCard.trailingAnchor),
            entry.topAnchor.constraint(equalTo: entryCard.topAnchor), entry.bottomAnchor.constraint(equalTo: entryCard.bottomAnchor)
        ])
        entryCard.heightAnchor.constraint(equalToConstant: 188).isActive = true
        stack.addArrangedSubview(entryCard)

        let recentTitle = NSTextField(labelWithString: ui("最近交易", "Recent Transactions"))
        recentTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let recentHeader = NSStackView(); recentHeader.orientation = .horizontal; recentHeader.alignment = .centerY
        recentHeader.widthAnchor.constraint(equalToConstant: 644).isActive = true
        recentHeader.addArrangedSubview(recentTitle)
        let openTextFile = NSButton(title: ui("编辑文本", "Edit Text"), target: self, action: #selector(openLedgerInTextEditor(_:)))
        openTextFile.bezelStyle = .texturedRounded
        openTextFile.toolTip = ui("使用系统默认或“设置”中选择的 App 打开当前账本文件", "Open the current ledger in macOS's default app or the app selected in Settings")
        openTextFile.setAccessibilityLabel(ui("用外部 App 打开文本文件", "Open text file in external app"))
        recentHeader.addArrangedSubview(NSView())
        recentHeader.addArrangedSubview(openTextFile)
        stack.addArrangedSubview(recentHeader)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 10; scroll.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        scroll.widthAnchor.constraint(equalToConstant: 644).isActive = true
        dashboardRecentView.isEditable = false; dashboardRecentView.isSelectable = true
        dashboardRecentView.textColor = .labelColor; dashboardRecentView.backgroundColor = .clear
        dashboardRecentView.font = .systemFont(ofSize: 13, weight: .regular)
        dashboardRecentView.textContainerInset = NSSize(width: 2, height: 4)
        dashboardRecentView.setAccessibilityLabel(ui("最近交易", "Recent transactions"))
        scroll.documentView = dashboardRecentView
        scroll.heightAnchor.constraint(equalToConstant: 142).isActive = true
        stack.addArrangedSubview(scroll)
        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(bottomSpacer)
        return container
    }

    private func buildWindow() {
        window = CountPaperWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "CountPaper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 920, height: 600)
        window.center(); window.delegate = self
        (window as? CountPaperWindow)?.onCommandW = { [weak self] in self?.hideMainWindow(nil) }

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let shell = NSStackView()
        shell.orientation = .horizontal
        shell.spacing = 0
        shell.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 196).isActive = true
        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 6
        sidebarStack.edgeInsets = NSEdgeInsets(top: 48, left: 12, bottom: 14, right: 12)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        let brand = NSTextField(labelWithString: "CountPaper")
        brand.font = .systemFont(ofSize: 19, weight: .semibold)
        brand.textColor = .labelColor
        sidebarStack.addArrangedSubview(brand)
        sidebarStack.setCustomSpacing(18, after: brand)
        sidebarButtons = [
            makeSidebarButton(title: ui("概览", "Overview"), symbol: "chart.bar.xaxis", tag: 0),
            makeSidebarButton(title: ui("日记账", "Journal"), symbol: "list.bullet", tag: 1),
            makeSidebarButton(title: ui("账户", "Accounts"), symbol: "wallet.pass", tag: 2),
            makeSidebarButton(title: ui("报表", "Reports"), symbol: "chart.pie", tag: 3)
        ]
        sidebarButtons.forEach { button in
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 172).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        let sidebarSpacer = NSView()
        sidebarSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebarStack.addArrangedSubview(sidebarSpacer)
        sidebar.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])
        updateSidebarSelection()
        shell.addArrangedSubview(sidebar)

        let workspace = NSStackView()
        workspace.orientation = .vertical
        workspace.alignment = .width
        workspace.spacing = 0
        // The ledger workspace is the flexible half of the window. Without
        // this explicit low hugging priority, NSStackView can keep it at its
        // intrinsic report width and leave an unusable blank strip on the
        // right of the application.
        workspace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        workspace.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 14)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        documentNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        documentNameLabel.textColor = .labelColor
        documentNameLabel.lineBreakMode = .byTruncatingMiddle
        documentNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)
        for (name, symbol, action) in [
            (ui("新建", "New"), "doc.badge.plus", #selector(newDocument(_:))),
            (ui("打开", "Open"), "folder", #selector(openDocument(_:))),
            (ui("保存", "Save"), "square.and.arrow.down", #selector(saveDocument(_:)))
        ] {
            let button = NSButton(title: name, target: self, action: action)
            button.bezelStyle = .texturedRounded
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            button.imagePosition = .imageLeading
            bar.addArrangedSubview(button)
        }
        let recordButton = NSButton(title: ui("记一笔", "Record"), target: self, action: #selector(recordTransaction(_:)))
        recordButton.bezelStyle = .rounded
        recordButton.keyEquivalent = "e"
        recordButton.keyEquivalentModifierMask = [.command]
        recordButton.contentTintColor = .controlAccentColor
        recordButton.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: recordButton.title)
        recordButton.imagePosition = .imageLeading
        recordButton.setAccessibilityLabel(ui("记一笔交易", "Record a transaction"))
        bar.addArrangedSubview(recordButton)
        workspace.addArrangedSubview(bar)

        let tabBar = NSStackView()
        tabBar.orientation = .horizontal
        tabBar.alignment = .centerY
        tabBar.spacing = 6
        tabBar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 5, right: 12)
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        ledgerTabControl.trackingMode = .selectOne
        ledgerTabControl.segmentStyle = .texturedRounded
        ledgerTabControl.target = self
        ledgerTabControl.action = #selector(changeLedgerTab(_:))
        ledgerTabControl.setAccessibilityLabel(ui("打开的账本", "Open ledgers"))
        ledgerTabControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        ledgerTabControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        ledgerTabControl.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true
        tabBar.addArrangedSubview(ledgerTabControl)
        let openAnother = NSButton(title: "＋", target: self, action: #selector(openDocument(_:)))
        openAnother.bezelStyle = .texturedRounded
        openAnother.toolTip = ui("在新标签页中打开另一个账本", "Open another ledger in a new tab")
        openAnother.setAccessibilityLabel(ui("打开另一个账本标签", "Open another ledger tab"))
        tabBar.addArrangedSubview(openAnother)
        let tabSpacer = NSView()
        tabSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabBar.addArrangedSubview(tabSpacer)
        let previousTab = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: ui("上一个账本", "Previous ledger"))!, target: self, action: #selector(selectPreviousLedgerTab(_:)))
        previousTab.isBordered = false
        previousTab.toolTip = ui("上一个账本", "Previous ledger")
        tabBar.addArrangedSubview(previousTab)
        let nextTab = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: ui("下一个账本", "Next ledger"))!, target: self, action: #selector(selectNextLedgerTab(_:)))
        nextTab.isBordered = false
        nextTab.toolTip = ui("下一个账本", "Next ledger")
        tabBar.addArrangedSubview(nextTab)
        let closeTab = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: ui("关闭账本标签", "Close ledger tab"))!, target: self, action: #selector(closeActiveLedgerTab(_:)))
        closeTab.isBordered = false
        closeTab.toolTip = ui("关闭当前账本标签", "Close current ledger tab")
        closeTab.setAccessibilityLabel(ui("关闭账本标签", "Close ledger tab"))
        tabBar.addArrangedSubview(closeTab)
        workspace.addArrangedSubview(tabBar)

        journalSearchField.placeholderString = "搜索摘要、账户、收款方或链接"
        journalSearchField.target = self
        journalSearchField.action = #selector(changeJournalSearch(_:))
        journalSearchField.setAccessibilityLabel("搜索日记账")
        journalSearchField.isHidden = true
        journalSearchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        journalSearchScope.addItems(withTitles: JournalSearchField.allCases.map(\.title))
        journalSearchScope.target = self
        journalSearchScope.action = #selector(changeJournalSearchScope(_:))
        journalSearchScope.setAccessibilityLabel("日记账搜索字段")
        journalSearchScope.isHidden = true
        journalSearchScope.widthAnchor.constraint(equalToConstant: 96).isActive = true
        journalStatusFilter.addItems(withTitles: JournalStatusFilter.allCases.map(\.title))
        journalStatusFilter.target = self
        journalStatusFilter.action = #selector(changeJournalStatus(_:))
        journalStatusFilter.setAccessibilityLabel("日记账交易状态")
        journalStatusFilter.isHidden = true
        journalStatusFilter.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let body = NSView()
        body.wantsLayer = true
        body.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        // One explicit content host is more reliable than a horizontal stack
        // when whole pages are swapped in and out of view.
        let contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        let dashboard = buildDashboard()
        dashboardContainer = dashboard
        dashboard.translatesAutoresizingMaskIntoConstraints = false
        let reportContainer = NSView()
        inspectorContainer = reportContainer
        reportContainer.translatesAutoresizingMaskIntoConstraints = false
        reportContainer.wantsLayer = true
        reportContainer.layer?.cornerRadius = 10
        reportContainer.layer?.borderWidth = 0.5
        reportContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        reportContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        reportContainer.layer?.masksToBounds = true
        let reportStack = NSStackView(frame: reportContainer.bounds)
        reportStack.orientation = .vertical
        reportStack.spacing = 0
        reportStack.autoresizingMask = [.width, .height]
        let inspectorHeader = NSStackView()
        inspectorHeader.orientation = .vertical
        inspectorHeader.alignment = .leading
        inspectorHeader.spacing = 8
        inspectorHeader.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 10, right: 14)
        inspectorHeader.wantsLayer = true
        inspectorHeader.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        inspectorTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        inspectorTitleLabel.stringValue = ui("概览", "Overview")
        inspectorHeader.addArrangedSubview(inspectorTitleLabel)
        let journalFilters = NSStackView()
        journalFilters.orientation = .vertical
        journalFilters.spacing = 6
        journalFilters.isHidden = true
        journalFilters.addArrangedSubview(journalSearchField)
        let filterRow = NSStackView()
        filterRow.orientation = .horizontal
        filterRow.spacing = 6
        filterRow.addArrangedSubview(journalSearchScope)
        filterRow.addArrangedSubview(journalStatusFilter)
        journalFilters.addArrangedSubview(filterRow)
        inspectorHeader.addArrangedSubview(journalFilters)
        journalFilterContainer = journalFilters
        let reportFilters = NSStackView()
        reportFilters.orientation = .vertical
        reportFilters.alignment = .leading
        reportFilters.spacing = 6
        reportFilters.isHidden = true
        let reportScopeRow = NSStackView(); reportScopeRow.orientation = .horizontal; reportScopeRow.spacing = 6
        reportLedgerScopePicker.addItems(withTitles: [ui("当前账本", "Current Ledger"), ui("所有打开账本", "All Open Ledgers")])
        reportLedgerScopePicker.target = self; reportLedgerScopePicker.action = #selector(changeReportLedgerScope(_:))
        reportLedgerScopePicker.setAccessibilityLabel(ui("报表账本范围", "Report ledger scope"))
        reportLedgerScopePicker.widthAnchor.constraint(equalToConstant: 124).isActive = true
        periodPicker.target = self; periodPicker.action = #selector(changeReportPeriod(_:))
        periodPicker.setAccessibilityLabel(ui("报表时间", "Report period")); periodPicker.widthAnchor.constraint(equalToConstant: 138).isActive = true
        reportKindControl.target = self; reportKindControl.action = #selector(changeReportKind(_:))
        reportKindControl.selectedSegment = 0; reportKindControl.setAccessibilityLabel(ui("报表类型", "Report kind"))
        reportKindControl.widthAnchor.constraint(equalToConstant: 154).isActive = true
        reportScopeRow.addArrangedSubview(reportLedgerScopePicker); reportScopeRow.addArrangedSubview(periodPicker); reportScopeRow.addArrangedSubview(reportKindControl)
        let reportDimensionRow = NSStackView(); reportDimensionRow.orientation = .horizontal; reportDimensionRow.spacing = 6
        reportTagPicker.target = self; reportTagPicker.action = #selector(changeReportTag(_:))
        reportTagPicker.setAccessibilityLabel(ui("报表标签筛选", "Report tag filter")); reportTagPicker.widthAnchor.constraint(equalToConstant: 160).isActive = true
        reportAccountPicker.target = self; reportAccountPicker.action = #selector(changeReportAccount(_:))
        reportAccountPicker.setAccessibilityLabel(ui("报表账户筛选", "Report account filter")); reportAccountPicker.widthAnchor.constraint(equalToConstant: 160).isActive = true
        reportDimensionRow.addArrangedSubview(reportTagPicker); reportDimensionRow.addArrangedSubview(reportAccountPicker)
        reportFilters.addArrangedSubview(reportScopeRow); reportFilters.addArrangedSubview(reportDimensionRow)
        inspectorHeader.addArrangedSubview(reportFilters)
        reportFilterContainer = reportFilters
        reportStack.addArrangedSubview(inspectorHeader)
        reportChartView.translatesAutoresizingMaskIntoConstraints = false
        reportChartView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        reportChartView.isHidden = true
        reportStack.addArrangedSubview(reportChartView)
        let reportScrollView = NSScrollView()
        reportScrollView.hasVerticalScroller = true
        reportScrollView.autohidesScrollers = true
        reportScrollView.borderType = .noBorder
        reportView.minSize = .zero
        reportView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        reportView.isVerticallyResizable = true
        reportView.isHorizontallyResizable = false
        reportView.autoresizingMask = [.width]
        reportView.textContainer?.widthTracksTextView = true
        reportView.textContainer?.containerSize = NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        reportView.textContainerInset = NSSize(width: 8, height: 8)
        reportView.textColor = .labelColor
        reportView.backgroundColor = .textBackgroundColor
        reportView.isSelectable = true
        reportView.selectedTextAttributes = [.backgroundColor: NSColor(calibratedRed: 0.22, green: 0.55, blue: 0.93, alpha: 0.82), .foregroundColor: NSColor.white]
        reportView.setAccessibilityLabel("账本概览")
        reportView.onReportClick = { [weak self] offset in self?.handleReportClick(at: offset) }
        reportView.isEditable = false; reportView.delegate = self; reportView.font = .systemFont(ofSize: 13, weight: .regular); reportScrollView.documentView = reportView; reportStack.addArrangedSubview(reportScrollView); reportContainer.addSubview(reportStack)
        contentHost.addSubview(dashboard)
        contentHost.addSubview(reportContainer)
        body.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            contentHost.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            contentHost.topAnchor.constraint(equalTo: body.topAnchor, constant: 12),
            contentHost.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -12),
            dashboard.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            dashboard.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            dashboard.topAnchor.constraint(equalTo: contentHost.topAnchor),
            dashboard.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            reportContainer.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            reportContainer.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            reportContainer.topAnchor.constraint(equalTo: contentHost.topAnchor),
            reportContainer.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
        ])
        workspace.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: workspace.widthAnchor).isActive = true
        let statusBar = NSView()
        statusBar.isHidden = true
        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor; statusLabel.setAccessibilityLabel("账本状态"); statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBar.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 0),
            bar.heightAnchor.constraint(equalToConstant: 52),
            tabBar.heightAnchor.constraint(equalToConstant: 36)
        ])
        workspace.addArrangedSubview(statusBar)
        shell.addArrangedSubview(workspace)
        // NSStackView otherwise prefers the inspector's intrinsic width on
        // first launch. Pin the flexible workspace to the shell explicitly so
        // every page uses the window's full remaining width.
        workspace.widthAnchor.constraint(equalTo: shell.widthAnchor, constant: -196).isActive = true
        root.addSubview(shell); window.contentView = root
        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: root.leadingAnchor), shell.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shell.topAnchor.constraint(equalTo: root.topAnchor), shell.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func makeSidebarButton(title: String, symbol: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(changeSidebarMode(_:)))
        button.tag = tag
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 14, weight: .medium)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(configuration)
        // Make the symbol an explicit neutral image. Template images inside an
        // NSButton are recoloured by AppKit after selection changes, which was
        // leaving the previously selected icon blue.
        icon?.isTemplate = false
        button.image = icon
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.setAccessibilityLabel(title)
        return button
    }

    private func updateSidebarSelection() {
        for button in sidebarButtons {
            let selected = button.tag == sidebarModeIndex
            // Keep the glyph neutral. AppKit otherwise applies its own tinted
            // selected-image treatment, which reads like a separate square icon.
            button.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
            button.contentTintColor = .labelColor
            button.font = .systemFont(ofSize: 14, weight: selected ? .semibold : .medium)
        }
    }

    private var sidebarModeIndex: Int {
        switch sidePanelMode {
        case .overview: return 0
        case .journal: return 1
        case .accounts: return 2
        case .reports: return 3
        }
    }

    private func updateDocumentChrome() {
        let name = documentURL?.lastPathComponent ?? "\(ui("未命名", "Untitled")).countpaper"
        documentNameLabel.stringValue = isDirty ? "\(name)  •" : name
        documentNameLabel.toolTip = documentURL?.path ?? ui("尚未选择保存位置", "No save location selected")
        updateLedgerTabs()
    }

    private func updateLedgerTabs() {
        ledgerTabsTitle.stringValue = ledgerSessions.count > 1
            ? ui("打开的账本（\(ledgerSessions.count)）", "Open Ledgers (\(ledgerSessions.count))")
            : ui("打开的账本", "Open Ledgers")
        ledgerTabControl.segmentCount = ledgerSessions.count
        for index in ledgerSessions.indices {
            let session = ledgerSessions[index]
            let fullName = session.url?.lastPathComponent ?? "\(ui("未命名", "Untitled")).countpaper"
            let name = fullName.count > 22 ? String(fullName.prefix(19)) + "…" : fullName
            ledgerTabControl.setLabel(session.isDirty ? "\(name) •" : name, forSegment: index)
            ledgerTabControl.setToolTip(session.url?.path ?? ui("尚未选择保存位置", "No save location selected"), forSegment: index)
            ledgerTabControl.setWidth(max(110, min(176, CGFloat(name.count * 9 + 30))), forSegment: index)
        }
        ledgerTabControl.selectedSegment = ledgerSessions.indices.contains(activeLedgerIndex) ? activeLedgerIndex : -1
    }

    private func persistActiveLedgerSession() {
        guard ledgerSessions.indices.contains(activeLedgerIndex) else { return }
        ledgerSessions[activeLedgerIndex].url = documentURL
        ledgerSessions[activeLedgerIndex].text = textView.string
        ledgerSessions[activeLedgerIndex].isDirty = isDirty
        ledgerSessions[activeLedgerIndex].signature = lastKnownFileSignature
        ledgerSessions[activeLedgerIndex].hasExternalConflict = hasExternalConflict
        ledgerSessions[activeLedgerIndex].selection = textView.selectedRange()
    }

    private func restoreActiveLedgerSession() {
        guard ledgerSessions.indices.contains(activeLedgerIndex) else { return }
        let session = ledgerSessions[activeLedgerIndex]
        isSwitchingLedgerSession = true
        documentURL = session.url
        isDirty = session.isDirty
        lastKnownFileSignature = session.signature
        hasExternalConflict = session.hasExternalConflict
        textView.string = session.text
        let textLength = (session.text as NSString).length
        let selection = NSRange(location: min(session.selection.location, textLength), length: min(session.selection.length, max(0, textLength - min(session.selection.location, textLength))))
        textView.setSelectedRange(selection)
        isSwitchingLedgerSession = false
        selectedReportMonth = nil
        selectedReportStartDate = nil
        selectedReportEndDate = nil
        selectedReportTag = nil
        selectedReportAccount = nil
        hasInitializedReportPeriod = false
        let name = session.url?.lastPathComponent ?? "\(ui("未命名", "Untitled")).countpaper"
        window.title = "\(name) — CountPaper"
        updateDocumentChrome()
        scheduleParse(immediately: true)
    }

    private func switchToLedgerSession(at index: Int) {
        guard ledgerSessions.indices.contains(index), index != activeLedgerIndex else { updateLedgerTabs(); return }
        autosaveWorkItem?.cancel()
        if isDirty, documentURL != nil, !hasExternalConflict { autosave() }
        persistActiveLedgerSession()
        activeLedgerIndex = index
        restoreActiveLedgerSession()
    }

    @objc private func changeLedgerTab(_ sender: NSSegmentedControl) {
        switchToLedgerSession(at: sender.selectedSegment)
    }

    @objc private func selectPreviousLedgerTab(_ sender: Any?) {
        guard ledgerSessions.count > 1 else { return }
        switchToLedgerSession(at: (activeLedgerIndex - 1 + ledgerSessions.count) % ledgerSessions.count)
    }

    @objc private func selectNextLedgerTab(_ sender: Any?) {
        guard ledgerSessions.count > 1 else { return }
        switchToLedgerSession(at: (activeLedgerIndex + 1) % ledgerSessions.count)
    }

    @objc private func closeActiveLedgerTab(_ sender: Any?) {
        guard ledgerSessions.count > 1, ledgerSessions.indices.contains(activeLedgerIndex) else {
            statusLabel.stringValue = ui("至少保留一个账本标签", "Keep at least one ledger tab open")
            return
        }
        persistActiveLedgerSession()
        if isDirty {
            let alert = NSAlert()
            alert.messageText = ui("关闭这个账本标签？", "Close this ledger tab?")
            alert.informativeText = documentURL == nil ? ui("这个未命名账本尚未保存。", "This untitled ledger has not been saved.") : ui("更改尚未保存完成。", "Changes have not finished saving.")
            alert.addButton(withTitle: ui("保存", "Save"))
            alert.addButton(withTitle: ui("不保存", "Don't Save"))
            alert.addButton(withTitle: ui("取消", "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                saveDocument(nil)
                guard !isDirty else { updateLedgerTabs(); return }
            case .alertSecondButtonReturn: break
            default: updateLedgerTabs(); return
            }
        }
        ledgerSessions.remove(at: activeLedgerIndex)
        activeLedgerIndex = min(activeLedgerIndex, ledgerSessions.count - 1)
        restoreActiveLedgerSession()
    }

    private func confirmClosingAllLedgers() -> Bool {
        persistActiveLedgerSession()
        let dirtyCount = dirtyLedgerSessionIndexes(ledgerSessions).count
        guard dirtyCount > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = ui("保存打开账本的更改吗？", "Save changes to open ledgers?")
        alert.informativeText = ui("共有 \(dirtyCount) 个账本包含尚未保存的更改。", "\(dirtyCount) open ledger(s) contain unsaved changes.")
        alert.addButton(withTitle: ui("全部保存", "Save All"))
        alert.addButton(withTitle: ui("不保存", "Don't Save"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAllDirtyLedgerSessions()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func saveAllDirtyLedgerSessions() -> Bool {
        persistActiveLedgerSession()
        for index in dirtyLedgerSessionIndexes(ledgerSessions) {
            if ledgerSessions[index].hasExternalConflict {
                activeLedgerIndex = index
                restoreActiveLedgerSession()
                presentError(ui("“\(documentURL?.lastPathComponent ?? "未命名账本")”已被外部修改。请先重新载入或另存为。", "“\(documentURL?.lastPathComponent ?? "Untitled ledger")” was modified externally. Reload it or save a copy first."))
                return false
            }
            if let url = ledgerSessions[index].url {
                do {
                    try ledgerSessions[index].text.write(to: url, atomically: true, encoding: .utf8)
                    ledgerSessions[index].isDirty = false
                    ledgerSessions[index].signature = fileSignature(for: url)
                    rememberRecentDocument(url)
                } catch {
                    activeLedgerIndex = index
                    restoreActiveLedgerSession()
                    presentError(ui("无法保存 \(url.lastPathComponent)：\(error.localizedDescription)", "Could not save \(url.lastPathComponent): \(error.localizedDescription)"))
                    return false
                }
            } else {
                activeLedgerIndex = index
                restoreActiveLedgerSession()
                saveAs(nil)
                persistActiveLedgerSession()
                guard !ledgerSessions[index].isDirty else { return false }
            }
        }
        if ledgerSessions.indices.contains(activeLedgerIndex) {
            let active = ledgerSessions[activeLedgerIndex]
            documentURL = active.url
            isDirty = active.isDirty
            lastKnownFileSignature = active.signature
            updateDocumentChrome()
        }
        return true
    }

    private func layoutDocumentViews() {
        let reportWidth = max(120, reportView.bounds.width)
        if textView.window != nil {
            let editorWidth = max(120, textView.bounds.width)
            textView.textContainer?.containerSize = NSSize(width: editorWidth - 44, height: CGFloat.greatestFiniteMagnitude)
        }
        reportView.textContainer?.containerSize = NSSize(width: reportWidth - 16, height: CGFloat.greatestFiniteMagnitude)
    }

    @objc private func showSourceEditor(_ sender: Any?) {
        sourceWindow?.title = "\(documentURL?.lastPathComponent ?? ui("未命名.countpaper", "Untitled.countpaper")) · \(ui("原始文本", "Source Text"))"
        sourceWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showDashboardJournal(_ sender: Any?) {
        sidePanelMode = .journal
        updateSidebarSelection()
        apply(report: latestReport)
    }

    @objc private func changeSidebarMode(_ sender: NSButton) {
        if sender.tag == 3 {
            sidePanelMode = .reports
            apply(report: latestReport)
            updateSidebarSelection()
            return
        }
        sidePanelMode = switch sender.tag {
        case 1: .journal
        case 2: .accounts
        default: .overview
        }
        updateSidebarSelection()
        apply(report: latestReport)
    }

    @objc private func changeSidePanel(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 3 {
            sidePanelMode = .reports
            apply(report: latestReport)
            updateSidebarSelection()
            return
        }
        sidePanelMode = switch sender.selectedSegment {
        case 1: .journal
        case 2: .accounts
        default: .overview
        }
        updateSidebarSelection()
        apply(report: latestReport)
    }

    @objc private func changeReportPeriod(_ sender: NSPopUpButton) {
        if sender.titleOfSelectedItem == "自选日期…" {
            presentCustomReportDateRange()
            return
        }
        selectedReportStartDate = nil
        selectedReportEndDate = nil
        selectedReportMonth = sender.titleOfSelectedItem == "全部期间" ? nil : sender.titleOfSelectedItem
        apply(report: latestReport)
    }

    @objc private func changeReportLedgerScope(_ sender: NSPopUpButton) {
        reportsAllOpenLedgers = sender.indexOfSelectedItem == 1
        apply(report: latestReport)
    }

    @objc private func changeReportTag(_ sender: NSPopUpButton) {
        selectedReportTag = sender.titleOfSelectedItem == "所有标签" ? nil : sender.titleOfSelectedItem
        apply(report: latestReport)
    }

    @objc private func changeReportAccount(_ sender: NSPopUpButton) {
        let allTitle = ui("所有账户", "All Accounts")
        selectedReportAccount = sender.titleOfSelectedItem == allTitle ? nil : sender.titleOfSelectedItem
        apply(report: latestReport)
    }

    @objc private func changeReportKind(_ sender: NSSegmentedControl) {
        selectedReportKind = PersonalReportKind.allCases[max(0, sender.selectedSegment)]
        apply(report: latestReport)
    }

    private func presentCustomReportDateRange() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = latestReport.journal.map(\.date).sorted()
        let alert = NSAlert()
        alert.messageText = ui("选择报表时间段", "Choose report date range")
        alert.informativeText = ui("直接在日历中选择起始与结束日期；所有报表会立即按此范围重新计算。", "Choose the start and end dates directly in the calendars; every report will be recalculated for this range.")
        let content = NSStackView(frame: NSRect(x: 0, y: 0, width: 230, height: 370))
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        let start = NSDatePicker()
        start.datePickerStyle = .clockAndCalendar
        start.datePickerElements = .yearMonthDay
        start.dateValue = selectedReportStartDate.flatMap(formatter.date(from:)) ?? dates.first.flatMap(formatter.date(from:)) ?? Date()
        start.setAccessibilityLabel(ui("报表开始日期", "Report start date"))
        start.widthAnchor.constraint(equalToConstant: 220).isActive = true
        start.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let end = NSDatePicker()
        end.datePickerStyle = .clockAndCalendar
        end.datePickerElements = .yearMonthDay
        end.dateValue = selectedReportEndDate.flatMap(formatter.date(from:)) ?? dates.last.flatMap(formatter.date(from:)) ?? Date()
        end.setAccessibilityLabel(ui("报表结束日期", "Report end date"))
        end.widthAnchor.constraint(equalToConstant: 220).isActive = true
        end.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let startColumn = NSStackView(); startColumn.orientation = .vertical; startColumn.alignment = .leading; startColumn.spacing = 6
        startColumn.addArrangedSubview(NSTextField(labelWithString: ui("起始日期", "Start date"))); startColumn.addArrangedSubview(start)
        let endColumn = NSStackView(); endColumn.orientation = .vertical; endColumn.alignment = .leading; endColumn.spacing = 6
        endColumn.addArrangedSubview(NSTextField(labelWithString: ui("结束日期", "End date"))); endColumn.addArrangedSubview(end)
        content.addArrangedSubview(startColumn)
        content.addArrangedSubview(endColumn)
        alert.accessoryView = content
        alert.addButton(withTitle: ui("应用", "Apply"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            updatePeriodPicker(for: latestReport)
            return
        }
        let startDate = formatter.string(from: start.dateValue)
        let endDate = formatter.string(from: end.dateValue)
        guard startDate <= endDate else {
            presentError(ui("开始日期不能晚于结束日期。", "The start date cannot be later than the end date."))
            updatePeriodPicker(for: latestReport)
            return
        }
        selectedReportMonth = nil
        selectedReportStartDate = startDate
        selectedReportEndDate = endDate
        apply(report: latestReport)
    }

    private func formRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let text = NSTextField(labelWithString: label)
        text.alignment = .right
        text.widthAnchor.constraint(equalToConstant: 62).isActive = true
        control.widthAnchor.constraint(equalToConstant: 210).isActive = true
        row.addArrangedSubview(text)
        row.addArrangedSubview(control)
        return row
    }

    @objc private func changeJournalSearch(_ sender: NSSearchField) {
        journalQuery = sender.stringValue
        apply(report: latestReport)
    }

    @objc private func changeJournalSearchScope(_ sender: NSPopUpButton) {
        journalSearchFieldScope = JournalSearchField.allCases[sender.indexOfSelectedItem]
        apply(report: latestReport)
    }

    @objc private func changeJournalStatus(_ sender: NSPopUpButton) {
        journalStatus = JournalStatusFilter.allCases[sender.indexOfSelectedItem]
        apply(report: latestReport)
    }

    @objc private func showSettings(_ sender: Any?) {
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 186))
        let heading = NSTextField(labelWithString: ui("录入与校验", "Entry & validation"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 0, y: 160, width: 500, height: 20)
        let multiple = NSButton(checkboxWithTitle: ui("一栏录入多个金额", "Enter multiple amounts in one field"), target: nil, action: nil)
        multiple.state = allowsMultipleAmounts ? .on : .off
        multiple.frame = NSRect(x: 0, y: 126, width: 500, height: 24)
        let multipleHint = NSTextField(labelWithString: ui("例如输入 32 57，会生成两笔同类交易。", "For example, 32 57 creates two transactions of the same kind."))
        multipleHint.textColor = .secondaryLabelColor
        multipleHint.font = .systemFont(ofSize: 11)
        multipleHint.frame = NSRect(x: 24, y: 104, width: 470, height: 18)
        let language = NSPopUpButton(frame: .zero, pullsDown: false)
        language.addItems(withTitles: ["中文", "English"])
        language.selectItem(at: appLanguage == .english ? 1 : 0)
        let languageLabel = NSTextField(labelWithString: ui("界面语言", "Interface language"))
        languageLabel.frame = NSRect(x: 280, y: 70, width: 160, height: 24)
        language.frame = NSRect(x: 280, y: 42, width: 160, height: 26)
        let editorLabel = NSTextField(labelWithString: ui("文本文件默认 App", "Default text app"))
        editorLabel.frame = NSRect(x: 0, y: 70, width: 180, height: 24)
        let editorName = NSTextField(labelWithString: sourceEditorApplicationName())
        editorName.textColor = .secondaryLabelColor
        editorName.lineBreakMode = .byTruncatingMiddle
        editorName.frame = NSRect(x: 0, y: 42, width: 180, height: 24)
        let chooseEditor = NSButton(title: ui("选择 App…", "Choose App…"), target: self, action: #selector(chooseSourceEditorApplication(_:)))
        chooseEditor.bezelStyle = .texturedRounded
        chooseEditor.frame = NSRect(x: 0, y: 8, width: 108, height: 28)
        let resetEditor = NSButton(title: ui("使用系统默认", "Use System Default"), target: self, action: #selector(resetSourceEditorApplication(_:)))
        resetEditor.bezelStyle = .texturedRounded
        resetEditor.frame = NSRect(x: 116, y: 8, width: 132, height: 28)
        [heading, multiple, multipleHint, languageLabel, language, editorLabel, editorName, chooseEditor, resetEditor].forEach(form.addSubview)
        let alert = NSAlert()
        alert.messageText = ui("设置", "Settings")
        alert.informativeText = ui("常用设置集中于此；原始文本不会被应用自动改写。", "Common settings live here; the app never automatically rewrites your source text.")
        alert.accessoryView = form
        alert.addButton(withTitle: ui("完成", "Done"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let oldLanguage = appLanguage
        UserDefaults.standard.set(multiple.state == .on, forKey: CountPaperPreference.multipleAmounts)
        let newLanguage: AppLanguage = language.indexOfSelectedItem == 1 ? .english : .chinese
        UserDefaults.standard.set(newLanguage.rawValue, forKey: CountPaperPreference.language)
        if oldLanguage != newLanguage {
            let restart = NSAlert()
            restart.messageText = ui("语言将在重启后切换", "Language changes after restart")
            restart.informativeText = ui("请退出并重新打开 CountPaper，以重新构建菜单和工具栏。", "Quit and reopen CountPaper to rebuild menus and the toolbar in the selected language.")
            restart.addButton(withTitle: ui("知道了", "OK"))
            restart.runModal()
        }
    }

    private func sourceEditorApplicationURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: CountPaperPreference.sourceEditorApplicationPath),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func sourceEditorApplicationName() -> String {
        sourceEditorApplicationURL()?.deletingPathExtension().lastPathComponent ?? ui("系统默认", "System Default")
    }

    @objc private func chooseSourceEditorApplication(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let applicationsFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.fileExists(atPath: applicationsFolder.path) {
            panel.directoryURL = applicationsFolder
        }
        panel.message = ui("选择用于打开 .countpaper 纯文本文件的 App", "Choose the app used to open .countpaper plain-text files")
        panel.prompt = ui("选择", "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: CountPaperPreference.sourceEditorApplicationPath)
    }

    @objc private func resetSourceEditorApplication(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: CountPaperPreference.sourceEditorApplicationPath)
    }

    @objc private func openLedgerInTextEditor(_ sender: Any?) {
        guard let ledgerURL = documentURL else {
            presentError(ui("请先保存账本，再使用文本 App 打开文件。", "Save the ledger before opening it in a text app."))
            return
        }
        if isDirty { write(to: ledgerURL) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let openCompletion: (NSRunningApplication?, Error?) -> Void = { [weak self] application, error in
            if error == nil {
                DispatchQueue.main.async {
                    let appName = application?.localizedName ?? self?.sourceEditorApplicationName() ?? ""
                    self?.statusLabel.stringValue = self?.ui("已交由“\(appName)”编辑；保存后 CountPaper 会自动重新载入。", "Editing in “\(appName)”; CountPaper reloads the saved file automatically.") ?? ""
                }
                return
            }
            guard let error else { return }
            DispatchQueue.main.async {
                self?.presentError(self?.ui("无法用文本 App 打开文件：\(error.localizedDescription)", "Could not open the file in a text app: \(error.localizedDescription)") ?? error.localizedDescription)
            }
        }
        if let applicationURL = sourceEditorApplicationURL() {
            NSWorkspace.shared.open([ledgerURL], withApplicationAt: applicationURL, configuration: configuration, completionHandler: openCompletion)
        } else {
            NSWorkspace.shared.open(ledgerURL, configuration: configuration, completionHandler: openCompletion)
        }
    }

    @objc private func newDocument(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [countPaperContentType]
        panel.nameFieldStringValue = ui("我的账本.countpaper", "My Ledger.countpaper")
        panel.message = ui("选择新账本的保存位置", "Choose where to save the new ledger")
        panel.prompt = ui("创建", "Create")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = starterTemplate(for: appLanguage)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            persistActiveLedgerSession()
            ledgerSessions.append(LedgerSession(url: url, text: text, signature: fileSignature(for: url)))
            activeLedgerIndex = ledgerSessions.count - 1
            rememberRecentDocument(url)
            restoreActiveLedgerSession()
            statusLabel.stringValue = ui("已创建 \(url.lastPathComponent)", "Created \(url.lastPathComponent)")
        } catch {
            presentError(ui("无法创建文件：\(error.localizedDescription)", "Could not create file: \(error.localizedDescription)"))
        }
    }

    @objc private func presentCommandPalette(_ sender: Any?) {
        let commands = [
            CommandPaletteItem(title: ui("记一笔", "Record Transaction"), detail: ui("在支出、收入和转账之间自由切换", "Switch freely between expense, income, and transfer"), action: { [weak self] in self?.recordTransaction(nil) }),
            CommandPaletteItem(title: "添加账户", detail: "声明新的资产、负债、收入或费用账户", action: { [weak self] in self?.addAccount(nil) }),
            CommandPaletteItem(title: "添加账户备注", detail: "记录账户用途、结算日等不影响余额的信息", action: { [weak self] in self?.addAccountNote(nil) }),
            CommandPaletteItem(title: "设置预算", detail: "添加当前月份的费用预算", action: { [weak self] in self?.addBudget(nil) }),
            CommandPaletteItem(title: "添加事件", detail: "记录换工作、搬家等不影响余额的账本事件", action: { [weak self] in self?.addEvent(nil) }),
            CommandPaletteItem(title: "编辑当前交易", detail: "用表单更新光标所在的标准交易", action: { [weak self] in self?.editTransactionAtCursor(nil) }),
            CommandPaletteItem(title: "打开当前交易链接", detail: "在默认浏览器中打开该交易关联的网页", action: { [weak self] in self?.openTransactionLinkAtCursor(nil) }),
            CommandPaletteItem(title: "跳转到行", detail: "快速定位账本文本中的行号", action: { [weak self] in self?.goToLine(nil) }),
            CommandPaletteItem(title: "跳到下一个错误", detail: "定位下一条格式诊断", action: { [weak self] in self?.jumpToNextDiagnostic(nil) }),
            CommandPaletteItem(title: "文本格式速查", detail: "查看交易、分录与 0.2 扩展的最小语法", action: { [weak self] in self?.showFormatQuickReference(nil) }),
            CommandPaletteItem(title: "重新校验", detail: "立即重新解析当前账本", action: { [weak self] in self?.reparseNow() }),
            CommandPaletteItem(title: "保存文稿", detail: "保存到当前文件或选择保存位置", action: { [weak self] in self?.saveDocument(nil) }),
            CommandPaletteItem(title: "打开文稿", detail: "打开本地 .countpaper 账本文件", action: { [weak self] in self?.openDocument(nil) })
        ]
        CommandPaletteController(items: commands).show()
    }

    @objc private func showFormatQuickReference(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "CountPaper 文本格式速查"
        alert.informativeText = """
        一笔交易由一个不缩进的交易头和至少两条缩进分录组成；分录金额相加必须为 0。

        2026-08-11 午餐
            费用:餐饮  32.50
            资产:现金  -32.50

        可选的交易内注释：收款方、标签、链接。使用“记支出／收入／转账”会自动生成正确文本。

        账本 0.2 还支持：预算、对账、事件、账户备注。它们不改变既有交易的双分录规则。

        完整规范随项目中的《账本纯文本格式规范-0.1》提供；任何纯文本编辑器都可打开 .countpaper 文件。
        """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func loadUntitledSample() {
        ledgerSessions = [LedgerSession(url: nil, text: starterTemplate(for: appLanguage))]
        activeLedgerIndex = 0
        restoreActiveLedgerSession()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [countPaperContentType, .plainText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDocument(at: url)
    }

    private func loadDocument(at url: URL) {
        if let existing = ledgerSessions.firstIndex(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
            switchToLedgerSession(at: existing)
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            persistActiveLedgerSession()
            ledgerSessions.append(LedgerSession(url: url, text: text, signature: fileSignature(for: url)))
            activeLedgerIndex = ledgerSessions.count - 1
            rememberRecentDocument(url)
            restoreActiveLedgerSession()
        }
        catch { presentError("无法打开文件：\(error.localizedDescription)") }
    }

    private func reloadActiveDocumentFromDisk() {
        guard let url = documentURL else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            textView.string = text
            isDirty = false
            hasExternalConflict = false
            lastKnownFileSignature = fileSignature(for: url)
            persistActiveLedgerSession()
            updateDocumentChrome()
            scheduleParse(immediately: true)
        } catch {
            presentError(ui("无法重新载入文件：\(error.localizedDescription)", "Could not reload file: \(error.localizedDescription)"))
        }
    }

    @objc private func reloadFromDisk(_ sender: Any?) {
        guard documentURL != nil else { return }
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "重新载入文稿？"
            alert.informativeText = "未保存的本地修改将丢失。你可以先使用“另存为”保留副本。"
            alert.addButton(withTitle: "重新载入")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        reloadActiveDocumentFromDisk()
        statusLabel.stringValue = "已从磁盘重新载入"
    }

    @objc private func exportReportCSV(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .plainText]
        let period = reportPeriodTitle.replacingOccurrences(of: " ", with: "")
        panel.nameFieldStringValue = "CountPaper-收支报表-\(period).csv"
        panel.message = "导出当前报表为 CSV"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let sourceReport = expandedReportSource(currentReport: latestReport)
            try personalReportCSV(report: sourceReport, month: selectedReportMonth, startDate: selectedReportStartDate, endDate: selectedReportEndDate, tag: selectedReportTag, account: selectedReportAccount).write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = "已导出 CSV：\(url.lastPathComponent)"
        } catch {
            presentError("无法导出 CSV：\(error.localizedDescription)")
        }
    }

    @objc private func exportJournalCSV(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .plainText]
        let period = reportPeriodTitle.replacingOccurrences(of: " ", with: "")
        panel.nameFieldStringValue = "CountPaper-日记账-\(period).csv"
        panel.message = "导出当前期间的逐笔日记账为 CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try journalCSV(report: latestReport, month: selectedReportMonth, startDate: selectedReportStartDate, endDate: selectedReportEndDate, tag: selectedReportTag, account: selectedReportAccount).write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = "已导出日记账：\(url.lastPathComponent)"
        } catch {
            presentError("导出失败：\(error.localizedDescription)")
        }
    }

    @objc private func setAsDefaultEditor(_ sender: Any?) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let result = LSSetDefaultRoleHandlerForContentType("com.countpaper.document" as CFString, .all, bundleIdentifier as CFString)
        if result == noErr {
            statusLabel.stringValue = "CountPaper 已设为 .countpaper 的默认打开应用"
        } else {
            presentError("无法设置默认打开应用（错误码 \(result)）。请将 App 拖入 Applications 后重试。")
        }
    }

    @objc private func saveDocument(_ sender: Any?) {
        guard let url = documentURL else { saveAs(sender); return }
        write(to: url)
    }

    @objc private func saveAs(_ sender: Any?) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [countPaperContentType]; panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "我的账本.countpaper"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        documentURL = url; hasExternalConflict = false; write(to: url)
    }

    private func write(to url: URL) {
        guard !hasExternalConflict || url != documentURL else {
            presentError("检测到文件已被外部修改。请先“从磁盘重新载入”，或使用“另存为”保留本地版本。")
            return
        }
        do { try textView.string.write(to: url, atomically: true, encoding: .utf8); isDirty = false; lastKnownFileSignature = fileSignature(for: url); persistActiveLedgerSession(); rememberRecentDocument(url); window.title = "\(url.lastPathComponent) — CountPaper"; updateDocumentChrome(); statusLabel.stringValue = "已保存到 \(url.path)" }
        catch { presentError("无法保存文件：\(error.localizedDescription)") }
    }

    private func rememberRecentDocument(_ url: URL) {
        let key = "recentDocumentPaths"
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.set(updatedRecentPaths(paths, adding: url.path), forKey: key)
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let key = "recentDocumentPaths"
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existing != paths { UserDefaults.standard.set(existing, forKey: key) }
        guard !existing.isEmpty else {
            let empty = NSMenuItem(title: "没有最近文稿", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        for path in existing {
            let item = NSMenuItem(title: URL(fileURLWithPath: path).lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.toolTip = path
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        let clear = NSMenuItem(title: "清除最近使用", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = self
        recentMenu.addItem(clear)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            rebuildRecentMenu()
            presentError("找不到最近文稿：\(url.lastPathComponent)")
            return
        }
        loadDocument(at: url)
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: "recentDocumentPaths")
        rebuildRecentMenu()
    }

    @objc private func recordTransaction(_ sender: Any?) { focusInlineEntry(kind: .expense) }
    @objc private func addExpense(_ sender: Any?) { focusInlineEntry(kind: .expense) }
    @objc private func addIncome(_ sender: Any?) { focusInlineEntry(kind: .income) }

    private func focusInlineEntry(kind: QuickEntryKind) {
        sidePanelMode = .overview
        updateSidebarSelection()
        inlineKindControl.selectedSegment = kind.rawValue
        inlineEntryBinder?.changeKind(inlineKindControl)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.window.makeFirstResponder(self?.inlineAmountField) }
    }
    @objc private func addTransfer(_ sender: Any?) { presentQuickEntry(kind: .transfer) }

    @objc private func editTransactionAtCursor(_ sender: Any?) {
        let raw = textView.string
        guard let transaction = transactionAtCursor(in: raw), transaction.postings.count == 2,
              transaction.postings[0].amount > .zero, transaction.postings[1].amount < .zero,
              let range = ledgerSourceRange(in: raw, fromLine: transaction.startLine, throughLine: transaction.endLine) else {
            presentError("请将光标放在一笔标准的两分录交易内。复杂交易请直接在原文中编辑，以保留全部内容。")
            return
        }
        let original = (raw as NSString).substring(with: range)
        guard canonicalTransactionReplacement(source: original, date: transaction.date, summary: transaction.summary, flag: transaction.flag, payee: transaction.payee, tags: transaction.tags, links: transaction.links, destination: transaction.postings[0].account, sourceAccount: transaction.postings[1].account, amount: transaction.postings[0].amount) != nil else {
            presentError("这笔交易含未知注释或非标准排版。请直接在原文中编辑，以保留全部内容。")
            return
        }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 276))
        let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay
        let dateFormatter = DateFormatter(); dateFormatter.locale = Locale(identifier: "en_US_POSIX"); dateFormatter.calendar = Calendar(identifier: .gregorian); dateFormatter.dateFormat = "yyyy-MM-dd"
        date.dateValue = dateFormatter.date(from: transaction.date) ?? Date()
        let summary = NSTextField(string: transaction.summary)
        let payee = NSTextField(string: transaction.payee ?? ""); payee.placeholderString = "可选，例如：星巴克"
        let tags = NSTextField(string: transaction.tags.joined(separator: ", ")); tags.placeholderString = "可选，逗号分隔，例如：咖啡, 日常"
        let links = NSTextField(string: transaction.links.joined(separator: ", ")); links.placeholderString = "可选，https://…；多个链接用逗号分隔"
        let destination = NSPopUpButton(frame: .zero, pullsDown: false); destination.addItems(withTitles: latestReport.accounts); destination.selectItem(withTitle: transaction.postings[0].account)
        let source = NSPopUpButton(frame: .zero, pullsDown: false); source.addItems(withTitles: latestReport.accounts); source.selectItem(withTitle: transaction.postings[1].account)
        let amount = NSTextField(string: LedgerParser.format(transaction.postings[0].amount))
        let fields: [(String, NSView)] = [("日期", date), ("摘要", summary), ("收款方", payee), ("标签", tags), ("链接", links), ("增加账户", destination), ("减少账户", source), ("金额", amount)]
        for (index, pair) in fields.enumerated() {
            let y = CGFloat(240 - index * 32)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 95, height: 24)
            pair.1.frame = NSRect(x: 106, y: y, width: 295, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        let alert = NSAlert()
        alert.messageText = "编辑交易"
        alert.informativeText = "只替换当前交易文本；状态和已识别的收款方、标签会被保留。"
        alert.accessoryView = form
        alert.addButton(withTitle: "更新交易")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cleanedSummary = summary.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedPayee = payee.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedTags = transactionMetadata(fromComment: "标签: \(tags.stringValue)").tags
            let cleanedLinks = normalizedTransactionLinks(links.stringValue)
            guard !cleanedSummary.isEmpty, !cleanedSummary.contains("\n"),
                  let value = Decimal(string: amount.stringValue, locale: Locale(identifier: "en_US_POSIX")), value > .zero else {
                alert.informativeText = "摘要不能为空，金额必须是大于 0 的数字。"
                continue
            }
            guard !cleanedPayee.contains("\n"), !cleanedPayee.contains(";") else {
                alert.informativeText = "收款方不能包含换行或分号。"
                continue
            }
            guard let cleanedLinks else {
                alert.informativeText = "链接仅支持完整的 http:// 或 https:// 地址，多个链接请用逗号分隔。"
                continue
            }
            guard destination.titleOfSelectedItem != source.titleOfSelectedItem else {
                alert.informativeText = "增加和减少账户不能相同。"
                continue
            }
            guard let replacement = canonicalTransactionReplacement(source: original, date: dateFormatter.string(from: date.dateValue), summary: cleanedSummary, flag: transaction.flag, payee: cleanedPayee.isEmpty ? nil : cleanedPayee, tags: cleanedTags, links: cleanedLinks, destination: destination.titleOfSelectedItem!, sourceAccount: source.titleOfSelectedItem!, amount: value) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            isDirty = true
            scheduleParse(immediately: true)
            scheduleAutosave()
            textView.setSelectedRange(NSRange(location: range.location, length: replacement.utf16.count))
            textView.scrollRangeToVisible(textView.selectedRange())
            return
        }
    }

    @objc private func openTransactionLinkAtCursor(_ sender: Any?) {
        guard let transaction = transactionAtCursor(in: textView.string), !transaction.links.isEmpty else {
            presentError("请将光标放在包含链接的有效交易内。可在交易表单的“链接”字段添加 http:// 或 https:// 地址。")
            return
        }
        let link: String
        if transaction.links.count == 1 {
            link = transaction.links[0]
        } else {
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28), pullsDown: false)
            picker.addItems(withTitles: transaction.links)
            let alert = NSAlert()
            alert.messageText = "打开交易链接"
            alert.informativeText = "选择要在默认浏览器中打开的链接。"
            alert.accessoryView = picker
            alert.addButton(withTitle: "打开")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn, let selected = picker.titleOfSelectedItem else { return }
            link = selected
        }
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleTransactionStatusAtCursor(_ sender: Any?) {
        let raw = textView.string
        guard let transaction = transactionAtCursor(in: raw),
              let range = ledgerLineRange(in: raw, line: transaction.startLine) else {
            presentError("请先将光标放在一笔格式有效的交易内，再切换确认状态。")
            return
        }
        let originalLine = (raw as NSString).substring(with: range)
        let lineEnding = originalLine.hasSuffix("\r\n") ? "\r\n" : (originalLine.hasSuffix("\n") ? "\n" : "")
        let newFlag: String = transaction.flag == "!" ? "*" : "!"
        let newLine = "\(transaction.date) \(newFlag) \(transaction.summary)\(lineEnding)"
        textView.textStorage?.replaceCharacters(in: range, with: newLine)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
        statusLabel.stringValue = newFlag == "!" ? "已标记为待确认" : "已确认交易"
    }

    @objc private func deleteTransactionAtCursor(_ sender: Any?) {
        let raw = textView.string
        guard let transaction = transactionAtCursor(in: raw),
              let range = ledgerSourceRange(in: raw, fromLine: transaction.startLine, throughLine: transaction.endLine) else {
            presentError("请先将光标放在一笔格式有效的交易内，再执行删除。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除交易？"
        alert.informativeText = "将删除第 \(transaction.startLine)–\(transaction.endLine) 行的「\(transaction.summary)」。此操作可通过“编辑 > 撤销”恢复。"
        alert.addButton(withTitle: "删除交易")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        textView.textStorage?.replaceCharacters(in: range, with: "")
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func transactionAtCursor(in raw: String) -> LedgerTransaction? {
        let line = cursorLine(in: raw)
        return latestReport.journal.first { line >= $0.startLine && line <= $0.endLine }
    }

    @objc private func addBudget(_ sender: Any?) {
        let expenseAccounts = latestReport.accounts.filter { isLedgerAccount($0, .expense) }
        guard !expenseAccounts.isEmpty else {
            presentError("请先添加至少一个费用账户，再设置预算。")
            return
        }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 92))
        let month = NSDatePicker()
        month.datePickerStyle = .clockAndCalendar
        month.datePickerElements = .yearMonth
        month.dateValue = Date()
        let account = NSPopUpButton(frame: .zero, pullsDown: false)
        account.addItems(withTitles: expenseAccounts)
        let amount = NSTextField(string: "")
        amount.placeholderString = "例如 800.00"
        for (index, pair) in [("月份", month as NSView), ("费用分类", account as NSView), ("预算金额", amount as NSView)].enumerated() {
            let y = CGFloat(64 - index * 30)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 90, height: 24)
            pair.1.frame = NSRect(x: 102, y: y, width: 275, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        let alert = NSAlert()
        alert.messageText = "设置月度预算"
        alert.informativeText = textView.string.contains("账本 0.1") ? "首次设置会把版本声明升级为 0.2，并仅插入一行预算指令。" : "预算会以一行纯文本指令写入账本。"
        alert.accessoryView = form
        alert.addButton(withTitle: "设置预算")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let value = Decimal(string: amount.stringValue, locale: Locale(identifier: "en_US_POSIX")), value > .zero else {
                alert.informativeText = "预算金额必须是大于 0 的数字，例如 800.00。"
                continue
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM"
            let key = "\(formatter.string(from: month.dateValue))\u{1F}\(account.titleOfSelectedItem!)"
            guard !latestReport.budgets.contains(where: { "\($0.month)\u{1F}\($0.account)" == key }) else {
                alert.informativeText = "这个月份的该分类已有预算；请直接在原文中修改对应预算行。"
                continue
            }
            insertBudget(month: formatter.string(from: month.dateValue), account: account.titleOfSelectedItem!, amount: value)
            return
        }
    }

    @objc private func addReconciliation(_ sender: Any?) {
        let accounts = latestReport.accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
        guard !accounts.isEmpty else {
            presentError("请先添加至少一个资产或负债账户，再记录对账。")
            return
        }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 92))
        let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay; date.dateValue = Date()
        let account = NSPopUpButton(frame: .zero, pullsDown: false); account.addItems(withTitles: accounts)
        let balance = NSTextField(string: ""); balance.placeholderString = "例如 1,250.00"
        for (index, pair) in [("对账日期", date as NSView), ("账户", account as NSView), ("对账单余额", balance as NSView)].enumerated() {
            let y = CGFloat(64 - index * 30)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 90, height: 24)
            pair.1.frame = NSRect(x: 102, y: y, width: 275, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        let alert = NSAlert()
        alert.messageText = "添加对账记录"
        alert.informativeText = textView.string.contains("账本 0.1") ? "首次对账会把版本声明升级为 0.2，并仅插入一行对账指令。" : "对账会以一行纯文本指令写入账本。"
        alert.accessoryView = form
        alert.addButton(withTitle: "记录对账")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let value = Decimal(string: balance.stringValue.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) else {
                alert.informativeText = "对账单余额必须是数字，例如 1,250.00。"
                continue
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
            let dateText = formatter.string(from: date.dateValue)
            guard !latestReport.reconciliations.contains(where: { $0.date == dateText && $0.account == account.titleOfSelectedItem }) else {
                alert.informativeText = "这个日期的该账户已有对账记录；请直接在原文中修改。"
                continue
            }
            insertReconciliation(date: dateText, account: account.titleOfSelectedItem!, statementBalance: value)
            return
        }
    }

    @objc private func addEvent(_ sender: Any?) {
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 60))
        let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay; date.dateValue = Date()
        let title = NSTextField(string: ""); title.placeholderString = "例如：开始使用新的工资卡"
        for (index, pair) in [("日期", date as NSView), ("事件", title as NSView)].enumerated() {
            let y = CGFloat(34 - index * 30)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 90, height: 24)
            pair.1.frame = NSRect(x: 102, y: y, width: 275, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        let alert = NSAlert()
        alert.messageText = "添加账本事件"
        alert.informativeText = textView.string.contains("账本 0.1") ? "事件不影响余额；首次添加会把版本声明升级为 0.2，并仅插入一行事件指令。" : "事件不影响余额，只会出现在概览时间线。"
        alert.accessoryView = form
        alert.addButton(withTitle: "添加事件")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cleanedTitle = title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedTitle.isEmpty, !cleanedTitle.contains("\n"), !cleanedTitle.contains(";") else {
                alert.informativeText = "事件内容不能为空，且不能包含换行或分号。"
                continue
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
            insertEvent(date: formatter.string(from: date.dateValue), title: cleanedTitle)
            return
        }
    }

    @objc private func addAccountNote(_ sender: Any?) {
        guard !latestReport.accounts.isEmpty else {
            presentError("请先添加账户，再添加账户备注。")
            return
        }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 60))
        let account = NSPopUpButton(frame: .zero, pullsDown: false); account.addItems(withTitles: latestReport.accounts)
        let note = NSTextField(string: ""); note.placeholderString = "例如：每月 8 日出账，25 日还款"
        for (index, pair) in [("账户", account as NSView), ("备注", note as NSView)].enumerated() {
            let y = CGFloat(34 - index * 30)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 90, height: 24)
            pair.1.frame = NSRect(x: 102, y: y, width: 275, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        let alert = NSAlert()
        alert.messageText = "添加账户备注"
        alert.informativeText = textView.string.contains("账本 0.1") ? "备注不影响余额；首次添加会把版本声明升级为 0.2，并仅插入一行备注指令。" : "备注不影响余额，会显示在账户树中。"
        alert.accessoryView = form
        alert.addButton(withTitle: "添加备注")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cleanedNote = note.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedNote.isEmpty, !cleanedNote.contains("\n"), !cleanedNote.contains(";") else {
                alert.informativeText = "备注不能为空，且不能包含换行或分号。"
                continue
            }
            guard !latestReport.accountNotes.contains(where: { $0.account == account.titleOfSelectedItem }) else {
                alert.informativeText = "该账户已有备注；请直接在原文中修改对应备注行。"
                continue
            }
            insertAccountNote(account: account.titleOfSelectedItem!, text: cleanedNote)
            return
        }
    }

    @objc private func addAccount(_ sender: Any?) {
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 60))
        let root = NSPopUpButton(frame: NSRect(x: 92, y: 34, width: 250, height: 24), pullsDown: false)
        root.addItems(withTitles: appLanguage == .english ? ["Assets", "Liabilities", "Equity", "Income", "Expenses"] : ["资产", "负债", "权益", "收入", "费用"])
        let name = NSTextField(frame: NSRect(x: 92, y: 2, width: 250, height: 24))
        name.placeholderString = ui("例如：微信、房租、餐饮", "e.g. Savings, Rent, Dining")
        for (title, y) in [(ui("账户类别", "Account type"), CGFloat(34)), (ui("账户名称", "Account name"), CGFloat(2))] {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y, width: 80, height: 24)
            form.addSubview(label)
        }
        form.addSubview(root)
        form.addSubview(name)
        let alert = NSAlert()
        alert.messageText = "添加账户"
        alert.informativeText = "账户会插入到账户声明区，原有注释与排版保持不变。"
        alert.accessoryView = form
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cleanedName = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedName.isEmpty, !cleanedName.contains(":"), !cleanedName.contains(";"), !cleanedName.contains("#"), !cleanedName.contains(where: { $0.isWhitespace }) else {
                alert.informativeText = "账户名称不能为空，且不能含空白、冒号、分号或 #。"
                continue
            }
            let account = "\(root.titleOfSelectedItem!):\(cleanedName)"
            guard !latestReport.accounts.contains(account) else {
                alert.informativeText = "账户「\(account)」已存在。"
                continue
            }
            insertAccountDeclaration(account)
            return
        }
    }

    private func insertAccountDeclaration(_ account: String) {
        let raw = textView.string
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        let lines = raw.components(separatedBy: newline)
        var offset = 0
        var inAccountSection = false
        var lastAccountEnd: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
            if trimmed == "@账户" { inAccountSection = true }
            else if line.hasPrefix("# ") { inAccountSection = false }
            if inAccountSection, line.hasPrefix("- ") { lastAccountEnd = lineEnd }
            offset = lineEnd
        }
        guard let insertionOffset = lastAccountEnd else {
            presentError("未找到 @账户 区域；请先修正文件头后再添加账户。")
            return
        }
        let text = "- \(account)\(newline)"
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: text)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func insertBudget(month: String, account: String, amount: Decimal) {
        let raw = textView.string
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        let lines = raw.components(separatedBy: newline)
        var offset = 0
        var lastDirectiveEnd: Int?
        var firstTransactionStart: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
            if trimmed.hasPrefix("账户 ") || trimmed.hasPrefix("预算 ") { lastDirectiveEnd = lineEnd }
            if firstTransactionStart == nil, trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s+[*!])?\\s+.+$", options: .regularExpression) != nil { firstTransactionStart = offset }
            offset = lineEnd
        }
        if let headerRange = raw.range(of: "账本 0.1") {
            textView.textStorage?.replaceCharacters(in: NSRange(headerRange, in: raw), with: "账本 0.2")
        }
        let insertionOffset = lastDirectiveEnd ?? firstTransactionStart ?? raw.utf16.count
        let directive = "预算 \(month) \(account) \(LedgerParser.format(amount))\(newline)"
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: directive)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func insertReconciliation(date: String, account: String, statementBalance: Decimal) {
        let raw = textView.string
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        let lines = raw.components(separatedBy: newline)
        var offset = 0
        var lastDirectiveEnd: Int?
        var firstTransactionStart: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
            if trimmed.hasPrefix("账户 ") || trimmed.hasPrefix("预算 ") || trimmed.hasPrefix("对账 ") { lastDirectiveEnd = lineEnd }
            if firstTransactionStart == nil, trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s+[*!])?\\s+.+$", options: .regularExpression) != nil { firstTransactionStart = offset }
            offset = lineEnd
        }
        if let headerRange = raw.range(of: "账本 0.1") {
            textView.textStorage?.replaceCharacters(in: NSRange(headerRange, in: raw), with: "账本 0.2")
        }
        let insertionOffset = lastDirectiveEnd ?? firstTransactionStart ?? raw.utf16.count
        let directive = "对账 \(date) \(account) \(LedgerParser.format(statementBalance))\(newline)"
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: directive)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func insertEvent(date: String, title: String) {
        let raw = textView.string
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        let lines = raw.components(separatedBy: newline)
        var offset = 0
        var lastDirectiveEnd: Int?
        var firstTransactionStart: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
            if trimmed.hasPrefix("账户 ") || trimmed.hasPrefix("预算 ") || trimmed.hasPrefix("对账 ") || trimmed.hasPrefix("事件 ") { lastDirectiveEnd = lineEnd }
            if firstTransactionStart == nil, trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s+[*!])?\\s+.+$", options: .regularExpression) != nil { firstTransactionStart = offset }
            offset = lineEnd
        }
        if let headerRange = raw.range(of: "账本 0.1") {
            textView.textStorage?.replaceCharacters(in: NSRange(headerRange, in: raw), with: "账本 0.2")
        }
        let insertionOffset = lastDirectiveEnd ?? firstTransactionStart ?? raw.utf16.count
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: "事件 \(date) \(title)\(newline)")
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func insertAccountNote(account: String, text: String) {
        let raw = textView.string
        let newline = raw.contains("\r\n") ? "\r\n" : "\n"
        let lines = raw.components(separatedBy: newline)
        var offset = 0
        var lastDirectiveEnd: Int?
        var firstTransactionStart: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
            if trimmed.hasPrefix("账户 ") || trimmed.hasPrefix("账户备注 ") || trimmed.hasPrefix("预算 ") || trimmed.hasPrefix("对账 ") || trimmed.hasPrefix("事件 ") { lastDirectiveEnd = lineEnd }
            if firstTransactionStart == nil, trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s+[*!])?\\s+.+$", options: .regularExpression) != nil { firstTransactionStart = offset }
            offset = lineEnd
        }
        if let headerRange = raw.range(of: "账本 0.1") {
            textView.textStorage?.replaceCharacters(in: NSRange(headerRange, in: raw), with: "账本 0.2")
        }
        let insertionOffset = lastDirectiveEnd ?? firstTransactionStart ?? raw.utf16.count
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: "账户备注 \(account) \(text)\(newline)")
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func presentQuickEntry(kind: QuickEntryKind) {
        let allAccounts = latestReport.accounts
        let initialOptions = quickEntryAccountOptions(accounts: allAccounts, kind: kind)
        guard !initialOptions.destination.isEmpty, !initialOptions.source.isEmpty else {
            presentError(ui("当前账本缺少可用账户。请先在原文中声明所需账户，再使用快速记账。", "This ledger does not have the accounts required for quick entry. Add them in the text first."))
            return
        }

        let formHeight: CGFloat = 488
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: formHeight))
        let kindControl = NSSegmentedControl(labels: [ui("支出", "Expense"), ui("收入", "Income"), ui("转账", "Transfer")], trackingMode: .selectOne, target: nil, action: nil)
        kindControl.selectedSegment = kind.rawValue
        kindControl.setAccessibilityLabel(ui("交易类型", "Transaction type"))
        let suggestions = NSPopUpButton(frame: .zero, pullsDown: false)
        suggestions.setAccessibilityLabel(ui("最近交易", "Recent transactions"))
        let date = NSDatePicker()
        date.datePickerStyle = .clockAndCalendar
        date.datePickerElements = .yearMonthDay
        date.dateValue = Date()
        let dateLabel = NSTextField(labelWithString: ui("日期", "Date"))
        let amount = NSTextField(string: "")
        amount.placeholderString = allowsMultipleAmounts ? ui("例如 32 57 或 -20", "e.g. 32 57 or -20") : ui("例如 32.50 或 -20", "e.g. 32.50 or -20")
        amount.setAccessibilityLabel(ui("金额", "Amount"))
        let summary = NSTextField(string: "")
        summary.placeholderString = ui("可选；留空自动使用交易类型", "Optional; defaults to transaction type")
        let payee = NSTextField(string: "")
        payee.placeholderString = ui("可选，例如：星巴克", "Optional, e.g. Starbucks")
        let tags = NSTextField(string: "")
        tags.placeholderString = ui("可选，逗号分隔，例如：咖啡, 日常", "Optional, comma separated")
        let destination = NSPopUpButton(frame: .zero, pullsDown: false)
        let source = NSPopUpButton(frame: .zero, pullsDown: false)
        let destinationLabel = NSTextField(labelWithString: "")
        let sourceLabel = NSTextField(labelWithString: "")
        let fields: [(NSTextField, NSView)] = [
            (NSTextField(labelWithString: ui("类型", "Type")), kindControl),
            (NSTextField(labelWithString: ui("常用", "Recent")), suggestions),
            (NSTextField(labelWithString: ui("金额", "Amount")), amount),
            (NSTextField(labelWithString: ui("摘要", "Description")), summary),
            (destinationLabel, destination),
            (sourceLabel, source),
            (dateLabel, date),
            (NSTextField(labelWithString: ui("收款方", "Payee")), payee),
            (NSTextField(labelWithString: ui("标签", "Tags")), tags)
        ]
        for (index, pair) in fields.enumerated() {
            let y = formHeight - 36 - CGFloat(index * 32)
            pair.0.alignment = .right
            pair.0.frame = NSRect(x: 0, y: y, width: 95, height: 24)
            pair.1.frame = NSRect(x: 106, y: y, width: 295, height: 24)
            form.addSubview(pair.0)
            form.addSubview(pair.1)
        }
        // A graphical NSDatePicker needs real room for the month grid. Keeping it
        // in a 24-point text-field row was the source of the truncated calendar.
        dateLabel.frame = NSRect(x: 0, y: 102, width: 95, height: 24)
        date.frame = NSRect(x: 106, y: 26, width: 295, height: 160)
        let binder = QuickEntryFormBinder(report: latestReport, allAccounts: allAccounts, english: appLanguage == .english, kindControl: kindControl, suggestionPicker: suggestions, destinationLabel: destinationLabel, sourceLabel: sourceLabel, summaryField: summary, payeeField: payee, tagsField: tags, destinationPicker: destination, sourcePicker: source, amountField: amount)
        quickEntryFormBinder = binder
        let alert = NSAlert()
        alert.messageText = ui("快速记账", "Quick Entry")
        alert.informativeText = allowsMultipleAmounts ? ui("输入金额即可记账；多个金额用空格分隔，负数用于冲减。", "Enter an amount to record; separate multiple amounts with spaces, and use negatives for reversals.") : ui("输入金额即可记账；负数用于冲减。", "Enter an amount to record; use a negative amount for a reversal.")
        alert.accessoryView = form
        alert.addButton(withTitle: ui("记账", "Record"))
        alert.addButton(withTitle: ui("记账并继续", "Record & Continue"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.window.initialFirstResponder = amount
        defer { quickEntryFormBinder = nil }
        while true {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            guard let values = quickEntryAmounts(amount.stringValue, allowsMultiple: allowsMultipleAmounts) else {
                alert.informativeText = allowsMultipleAmounts ? ui("请输入一个或多个非零金额，以空格分隔，例如 32 57 或 -20。", "Enter one or more non-zero amounts separated by spaces, such as 32 57 or -20.") : ui("请输入一个非零金额，例如 32.50 或 -20。", "Enter a non-zero amount, such as 32.50 or -20.")
                continue
            }
            let selectedKind = binder.kind
            guard let selectedDestination = destination.titleOfSelectedItem, let selectedSource = source.titleOfSelectedItem else {
                alert.informativeText = ui("当前类型缺少可用账户，请先在原文中添加账户。", "The selected type has no available accounts. Add accounts in the ledger text first.")
                continue
            }
            if selectedKind == .transfer && selectedDestination == selectedSource {
                alert.informativeText = ui("转入和转出账户不能相同。", "Transfer source and destination accounts must differ.")
                continue
            }
            let entrySummary = summary.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let entryPayee = payee.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let entryTags = tags.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entryPayee.contains("\n"), !entryTags.contains("\n"), !entryPayee.contains(";") else {
                alert.informativeText = ui("收款方和标签不能包含换行；收款方也不能包含分号。", "Payee and tags cannot contain line breaks, and payee cannot contain semicolons.")
                continue
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            binder.rememberAccountChoices()
            let fallbackSummary: String = switch selectedKind {
            case .expense: ui("支出", "Expense")
            case .income: ui("收入", "Income")
            case .transfer: ui("转账", "Transfer")
            }
            insertTransactions(date: formatter.string(from: date.dateValue), summary: entrySummary.isEmpty ? fallbackSummary : entrySummary, payee: entryPayee, tags: entryTags, links: "", destination: selectedDestination, source: selectedSource, amounts: values)
            guard response == .alertSecondButtonReturn else { return }
            amount.stringValue = ""
            summary.stringValue = ""
            payee.stringValue = ""
            tags.stringValue = ""
            suggestions.selectItem(at: 0)
            alert.informativeText = ui("已记入。继续输入金额即可录入下一笔。", "Recorded. Enter the next amount to continue.")
            alert.window.initialFirstResponder = amount
            DispatchQueue.main.async { alert.window.makeFirstResponder(amount) }
        }
    }

    private func insertTransaction(date: String, summary: String, payee: String, tags: String, links: String, destination: String, source: String, amount: Decimal) {
        insertTransactions(date: date, summary: summary, payee: payee, tags: tags, links: links, destination: destination, source: source, amounts: [amount])
    }

    private func insertTransactions(date: String, summary: String, payee: String, tags: String, links: String, destination: String, source: String, amounts: [Decimal]) {
        let normalizedTags = transactionMetadata(fromComment: "标签: \(tags)").tags
        let normalizedLinks = normalizedTransactionLinks(links) ?? []
        let payeeLine = payee.isEmpty ? "" : "\n  - 收款方: \(payee)"
        let tagsLine = normalizedTags.isEmpty ? "" : "\n  - 标签: \(normalizedTags.joined(separator: ", "))"
        let linkLine = normalizedLinks.isEmpty ? "" : "\n  - 链接: \(normalizedLinks.joined(separator: ", "))"
        let blocks = amounts.map { amount in "- \(summary)\(payeeLine)\(tagsLine)\(linkLine)\n  - \(destination)  \(LedgerParser.format(amount))\n  - \(source)  \(LedgerParser.format(-amount))" }
        let insertion = ledgerTransactionInsertion(in: textView.string, date: date, transactionBlocks: blocks)
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertion.location, length: 0), with: insertion.text)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
        let caret = NSRange(location: insertion.location + insertion.text.utf16.count, length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        if amounts.count > 1 { statusLabel.stringValue = "已录入 \(amounts.count) 笔交易" }
    }

    func textDidChange(_ notification: Notification) {
        guard !isSwitchingLedgerSession else { return }
        isDirty = true
        persistActiveLedgerSession()
        updateDocumentChrome()
        scheduleParse()
        scheduleAutosave()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as? NSTextView === reportView else { return }
        highlightSelectedReportLine()
        openJournalEntry(atReportOffset: reportView.selectedRange().location)
    }

    private func highlightSelectedReportLine() {
        guard let storage = reportView.textStorage else { return }
        if let prior = highlightedReportLine, NSMaxRange(prior) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: prior)
        }
        let selected = reportView.selectedRange()
        guard selected.location <= storage.length else { highlightedReportLine = nil; return }
        let range = (reportView.string as NSString).lineRange(for: NSRange(location: selected.location, length: 0))
        guard range.length > 0 else { highlightedReportLine = nil; return }
        storage.addAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.33, green: 0.67, blue: 1.0, alpha: 0.30), range: range)
        highlightedReportLine = range
    }

    private func redrawTextViews() {
        if let textContainer = textView.textContainer { textView.layoutManager?.ensureLayout(for: textContainer) }
        if let reportContainer = reportView.textContainer { reportView.layoutManager?.ensureLayout(for: reportContainer) }
        textView.needsDisplay = true
        reportView.needsDisplay = true
        textView.displayIfNeeded()
        reportView.displayIfNeeded()
    }

    private func applySyntaxHighlighting() {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        let selectionBeforeHighlighting = textView.selectedRange()
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)], range: fullRange)
        guard storage.length <= syntaxHighlightLimit else {
            storage.endEditing()
            if selectionBeforeHighlighting.location <= storage.length { textView.setSelectedRange(selectionBeforeHighlighting) }
            return
        }
        let muted: (NSColor) -> NSColor = { color in
            color.blended(withFraction: 0.62, of: .labelColor) ?? color
        }
        let colors: [LedgerSyntaxKind: NSColor] = [
            .comment: .tertiaryLabelColor,
            .directive: muted(.systemTeal),
            .date: muted(.systemBlue),
            .account: muted(.systemPurple),
            .amount: muted(.systemOrange)
        ]
        for token in ledgerSyntaxTokens(in: textView.string) where NSMaxRange(token.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: colors[token.kind] ?? .labelColor, range: token.range)
        }
        storage.endEditing()
        if selectionBeforeHighlighting.location <= storage.length {
            textView.setSelectedRange(selectionBeforeHighlighting)
        }
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        guard documentURL != nil else {
            statusLabel.stringValue = "未保存的修改：请使用“保存”选择文件位置"
            return
        }
        let workItem = DispatchWorkItem { [weak self] in self?.autosave() }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func autosave() {
        guard isDirty, !hasExternalConflict, let url = documentURL else { return }
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            lastKnownFileSignature = fileSignature(for: url)
            persistActiveLedgerSession()
            updateDocumentChrome()
            statusLabel.stringValue = "已自动保存"
        } catch {
            statusLabel.stringValue = "自动保存失败：\(error.localizedDescription)"
        }
    }

    private func fileSignature(for url: URL) -> LedgerFileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate,
              let size = values.fileSize else { return nil }
        return LedgerFileSignature(modificationDate: date, size: size)
    }

    @objc private func checkForExternalChanges() {
        guard let url = documentURL else { return }
        let action = externalChangeAction(last: lastKnownFileSignature, current: fileSignature(for: url), hasUnsavedChanges: isDirty)
        switch action {
        case .none: break
        case .reload:
            reloadActiveDocumentFromDisk()
            statusLabel.stringValue = "已重新载入外部修改"
        case .conflict:
            hasExternalConflict = true
            persistActiveLedgerSession()
            autosaveWorkItem?.cancel()
            statusLabel.stringValue = "检测到外部修改：自动保存已暂停，请重新载入或另存为"
        }
    }

    @objc private func reparseNow() { scheduleParse(immediately: true) }

    @objc private func jumpToNextDiagnostic(_ sender: Any?) {
        let lines = diagnosticLineNumbers(in: latestReport.diagnostics)
        guard !lines.isEmpty else {
            statusLabel.stringValue = "当前没有可定位的行级错误"
            return
        }
        let currentLine = cursorLine(in: textView.string)
        let target = lines.first(where: { $0 > currentLine }) ?? lines[0]
        guard let range = ledgerLineRange(in: textView.string, line: target) else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.window?.makeFirstResponder(textView)
        statusLabel.stringValue = "已定位到第 \(target) 行错误"
    }

    @objc private func goToLine(_ sender: Any?) {
        let field = NSTextField(string: "\(cursorLine(in: textView.string))")
        field.placeholderString = "例如 42"
        let alert = NSAlert()
        alert.messageText = "跳转到行"
        alert.informativeText = "输入要定位的源文本行号。"
        alert.accessoryView = field
        alert.addButton(withTitle: "跳转")
        alert.addButton(withTitle: "取消")
        while alert.runModal() == .alertFirstButtonReturn {
            guard let line = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), line > 0,
                  let range = ledgerLineRange(in: textView.string, line: line) else {
                alert.informativeText = "请输入现有的正整数行号。"
                continue
            }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            window.makeFirstResponder(textView)
            statusLabel.stringValue = "已定位到第 \(line) 行"
            return
        }
    }

    @objc private func indentSelectedLines(_ sender: Any?) { adjustSelectedIndentation(increase: true) }
    @objc private func outdentSelectedLines(_ sender: Any?) { adjustSelectedIndentation(increase: false) }

    private func adjustSelectedIndentation(increase: Bool) {
        guard let adjustment = adjustedIndentation(in: textView.string, selection: textView.selectedRange(), increase: increase) else { return }
        textView.textStorage?.replaceCharacters(in: adjustment.range, with: adjustment.replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: adjustment.range.location, length: adjustment.replacement.utf16.count))
        textView.scrollRangeToVisible(textView.selectedRange())
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func handleReportClick(at offset: Int) {
        switch sidePanelMode {
        case .journal: openJournalEntry(atReportOffset: offset)
        case .accounts: openAccountJournal(atReportOffset: offset)
        case .overview, .reports: break
        }
    }

    private func openJournalEntry(atReportOffset offset: Int) {
        guard let line = journalSourceLine(atReportOffset: offset, in: reportView.string),
              let range = ledgerLineRange(in: textView.string, line: line) else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        statusLabel.stringValue = "已定位原文第 \(line) 行；右侧选中内容保持高亮"
    }

    private func openAccountJournal(atReportOffset offset: Int) {
        guard let query = accountFilterQuery(atReportOffset: offset, in: reportView.string, accounts: latestReport.accounts) else {
            statusLabel.stringValue = "无法确定该账户；同名账户请用日记账搜索"
            return
        }
        sidePanelMode = .journal
        sidePanelControl?.selectedSegment = 1
        updateSidebarSelection()
        journalQuery = query
        journalSearchField.stringValue = query
        journalSearchFieldScope = .account
        journalSearchScope.selectItem(withTitle: JournalSearchField.account.title)
        journalStatus = .all
        journalStatusFilter.selectItem(withTitle: JournalStatusFilter.all.title)
        apply(report: latestReport)
        statusLabel.stringValue = "正在查看「\(query)」的流水"
    }

    private func cursorLine(in raw: String) -> Int {
        let length = min(textView.selectedRange().location, (raw as NSString).length)
        return (raw as NSString).substring(to: length).reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    private func scheduleParse(immediately: Bool = false) {
        parseWorkItem?.cancel()
        parseGeneration += 1
        let generation = parseGeneration
        let textSnapshot = textView.string
        if !immediately { statusLabel.stringValue = "正在校验…" }
        let workItem = DispatchWorkItem { [weak self] in
            let report = LedgerParser.parse(textSnapshot)
            DispatchQueue.main.async {
                guard let self, generation == self.parseGeneration else { return }
                self.apply(report: report)
            }
        }
        parseWorkItem = workItem
        let delay = immediately ? 0 : 0.16
        parseQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func apply(report: LedgerReport) {
        latestReport = report
        let isHome = sidePanelMode == .overview
        // Home is intentionally a recording workspace, not a duplicate text
        // overview. Every analytical view takes the entire content area.
        dashboardContainer?.isHidden = !isHome
        inspectorContainer?.isHidden = isHome
        inspectorCompactWidthConstraint?.isActive = false
        let expandedSourceReport = expandedReportSource(currentReport: report)
        updatePeriodPicker(for: expandedSourceReport)
        updateReportTagPicker(for: expandedSourceReport)
        updateReportAccountPicker(for: expandedSourceReport)
        journalSearchField.isHidden = sidePanelMode != .journal
        journalSearchScope.isHidden = sidePanelMode != .journal
        journalStatusFilter.isHidden = sidePanelMode != .journal
        journalFilterContainer?.isHidden = sidePanelMode != .journal
        reportFilterContainer?.isHidden = sidePanelMode != .reports
        inspectorTitleLabel.stringValue = switch sidePanelMode {
        case .overview: ui("概览", "Overview")
        case .journal: ui("日记账", "Journal")
        case .accounts: ui("账户", "Accounts")
        case .reports: ui("报表", "Reports")
        }
        let output: String
        switch sidePanelMode {
        case .overview: output = overviewText(for: report)
        case .journal: output = journalText(for: report)
        case .accounts: output = accountTreeText(for: report)
        case .reports: output = reportText(for: report)
        }
        let reportAccessibilityLabel = switch sidePanelMode {
        case .overview: "账本概览"
        case .journal: "日记账"
        case .accounts: "账户树"
        case .reports: "个人收支报表"
        }
        reportView.setAccessibilityLabel(reportAccessibilityLabel)
        reportView.string = output
        reportChartView.isHidden = sidePanelMode != .reports
        reportChartView.monthly = monthlyPersonalSummaries(entries: currentReportEntries(in: report))
        let reportEntries = currentReportEntries(in: report)
        let reportSummary = report.personalSummary(entries: reportEntries)
        let reportAnalytics = personalAnalytics(entries: reportEntries)
        reportChartView.expenseCategories = reportSummary.expenses
        reportChartView.tagExpenses = reportAnalytics.tagExpenses
        reportChartView.kind = selectedReportKind
        statusLabel.stringValue = report.diagnostics.isEmpty ? "" : "\(report.diagnostics.count) 个格式问题"
        updateDashboard(for: report)
        applySyntaxHighlighting()
        layoutDocumentViews()
        redrawTextViews()
    }

    private func updateDashboard(for report: LedgerReport) {
        configureInlineEntry(for: report)
        let latestMonth = report.journal.map { String($0.date.prefix(7)) }.max()
        let summary = report.personalSummary(month: latestMonth)
        dashboardTitleLabel.stringValue = latestMonth.map { ui("\($0)", $0) } ?? ui("本月", "This Month")
        dashboardIncomeLabel.stringValue = ui("收入\n\(LedgerParser.format(summary.incomeTotal))", "Income\n\(LedgerParser.format(summary.incomeTotal))")
        dashboardExpenseLabel.stringValue = ui("支出\n\(LedgerParser.format(summary.expenseTotal))", "Expenses\n\(LedgerParser.format(summary.expenseTotal))")
        dashboardNetLabel.stringValue = ui("结余\n\(LedgerParser.format(summary.net))", "Net\n\(LedgerParser.format(summary.net))")
        // The text file may be organised by project, month, or manual order.
        // "Recent" must therefore be ordered by its declared date—not by where
        // a transaction happens to occur in the source—while retaining source
        // order for entries made on the same day.
        let recent = report.journal
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.startLine > $1.startLine
            }
            .prefix(8)
        dashboardRecentView.string = recent.isEmpty
            ? ui("暂无交易", "No transactions")
            : recent.map { entry in
                let amount = entry.postings.first(where: { isLedgerAccount($0.account, .expense) || isLedgerAccount($0.account, .income) })?.amount
                    ?? entry.postings.first?.amount
                    ?? .zero
                return "\(entry.date)    \(entry.summary)    \(LedgerParser.format(amount))"
            }.joined(separator: "\n")
    }

    private func configureInlineDatePicker() {
        // This picker only stores the selected value. The graphical calendar is
        // created when requested, avoiding a permanently embedded AppKit date
        // control competing with the compact recording form's layout.
        inlineDatePicker.datePickerStyle = .textField
        inlineDatePicker.datePickerElements = .yearMonthDay
        inlineDatePicker.dateValue = Date()
    }

    private func configureInlineDateShortcutButtons() {
        inlineTodayButton.title = ui("今天", "Today")
        inlineYesterdayButton.title = ui("昨天", "Yesterday")
        for button in [inlineTodayButton, inlineYesterdayButton] {
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.widthAnchor.constraint(equalToConstant: 54).isActive = true
        }
        inlineTodayButton.target = self; inlineTodayButton.action = #selector(selectTodayForInlineEntry(_:))
        inlineYesterdayButton.target = self; inlineYesterdayButton.action = #selector(selectYesterdayForInlineEntry(_:))
        inlineTodayButton.setAccessibilityLabel(ui("日期设为今天", "Set date to today"))
        inlineYesterdayButton.setAccessibilityLabel(ui("日期设为昨天", "Set date to yesterday"))
    }

    @objc private func showInlineDateCalendar(_ sender: NSButton) {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = inlineDatePicker.dateValue
        picker.setAccessibilityLabel(ui("选择记账日期", "Choose transaction date"))
        picker.frame = NSRect(x: 0, y: 0, width: 240, height: 170)
        let alert = NSAlert()
        alert.messageText = ui("选择日期", "Choose Date")
        alert.informativeText = ui("“今天”和“昨天”可直接在记账栏选择。", "Use the Today and Yesterday buttons in the form for the usual choices.")
        alert.accessoryView = picker
        alert.addButton(withTitle: ui("确定", "Done"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        inlineDatePicker.dateValue = picker.dateValue
        updateInlineDateButtonTitle()
    }

    @objc private func selectTodayForInlineEntry(_ sender: Any?) {
        inlineDatePicker.dateValue = Date()
        updateInlineDateButtonTitle()
    }

    @objc private func selectYesterdayForInlineEntry(_ sender: Any?) {
        inlineDatePicker.dateValue = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        updateInlineDateButtonTitle()
    }

    private func updateInlineDateButtonTitle() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = appLanguage == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_Hans_CN")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        inlineDateButton.title = formatter.string(from: inlineDatePicker.dateValue)
        inlineTodayButton.state = calendar.isDateInToday(inlineDatePicker.dateValue) ? .on : .off
        inlineYesterdayButton.state = calendar.isDateInYesterday(inlineDatePicker.dateValue) ? .on : .off
    }

    private func configureInlineEntry(for report: LedgerReport) {
        guard !report.accounts.isEmpty else { return }
        let previousKind = inlineKindControl.selectedSegment >= 0 ? inlineKindControl.selectedSegment : 0
        inlineKindControl.selectedSegment = previousKind
        inlineEntryBinder = QuickEntryFormBinder(report: report, allAccounts: report.accounts, english: appLanguage == .english, kindControl: inlineKindControl, suggestionPicker: inlineSuggestionPicker, destinationLabel: inlineDestinationLabel, sourceLabel: inlineSourceLabel, summaryField: inlineSummaryField, payeeField: inlinePayeeField, tagsField: inlineTagsField, destinationPicker: inlineDestinationPicker, sourcePicker: inlineSourcePicker, amountField: inlineAmountField)
    }

    @objc private func recordInlineTransaction(_ sender: Any?) {
        guard let binder = inlineEntryBinder,
              let amounts = quickEntryAmounts(inlineAmountField.stringValue, allowsMultiple: allowsMultipleAmounts),
              let destination = inlineDestinationPicker.titleOfSelectedItem,
              let source = inlineSourcePicker.titleOfSelectedItem else {
            statusLabel.stringValue = ui("请输入有效金额。", "Enter a valid amount.")
            window.makeFirstResponder(inlineAmountField)
            return
        }
        guard binder.kind != .transfer || destination != source else {
            statusLabel.stringValue = ui("转入与转出账户不能相同。", "Transfer accounts must differ.")
            return
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let fallback: String = switch binder.kind { case .expense: ui("支出", "Expense"); case .income: ui("收入", "Income"); case .transfer: ui("转账", "Transfer") }
        binder.rememberAccountChoices()
        insertTransactions(date: formatter.string(from: inlineDatePicker.dateValue), summary: inlineSummaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : inlineSummaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), payee: "", tags: "", links: "", destination: destination, source: source, amounts: amounts)
        inlineAmountField.stringValue = ""
        inlineSummaryField.stringValue = ""
        inlineSuggestionPicker.selectItem(at: 0)
        window.makeFirstResponder(inlineAmountField)
        statusLabel.stringValue = amounts.count == 1 ? ui("已记入账本", "Recorded") : ui("已记入 \(amounts.count) 笔交易", "Recorded \(amounts.count) transactions")
    }

    private func expandedReportSource(currentReport: LedgerReport) -> LedgerReport {
        guard reportsAllOpenLedgers else { return currentReport }
        let reports = ledgerSessions.enumerated().map { index, session in
            index == activeLedgerIndex ? currentReport : LedgerParser.parse(session.text)
        }
        return aggregateLedgerReports(reports)
    }

    private func overviewText(for report: LedgerReport) -> String {
        var output = "概览\n\n"
        if report.balances.isEmpty { output += "尚无有效交易。\n" }
        else {
            output += "账户余额\n"
            for (account, raw) in report.balances.sorted(by: { $0.key < $1.key }) {
                let display = displayBalance(raw, account: account)
                output += "\(account)  \(LedgerParser.format(display))\n"
            }
            output += "\n费用汇总\n"
            for (account, amount) in report.expenses.sorted(by: { $0.key < $1.key }) { output += "\(account)  \(LedgerParser.format(amount))\n" }
        }
        if !report.reconciliations.isEmpty {
            output += "\n对账\n"
            let latestByAccount = Dictionary(grouping: report.reconciliations, by: \.account).compactMap { $0.value.max { $0.date < $1.date } }.sorted { $0.account < $1.account }
            for item in latestByAccount {
                let difference = reconciliationDifference(report: report, reconciliation: item)
                let status = difference == .zero ? "✓ 已一致" : "⚠ 差额 \(LedgerParser.format(difference))"
                output += "\(item.account)  \(item.date)  对账单 \(LedgerParser.format(item.statementBalance))  \(status)\n"
            }
        }
        if !report.events.isEmpty {
            output += "\n近期事件\n"
            for event in report.events.sorted(by: { $0.date > $1.date }).prefix(6) {
                output += "\(event.date)  \(event.title)\n"
            }
        }
        output += "\n诊断\n"
        output += report.diagnostics.isEmpty ? "✓ 格式有效，\(report.transactions) 笔已计入交易。" : report.diagnostics.joined(separator: "\n")
        return output
    }

    private func journalText(for report: LedgerReport) -> String {
        let entries = report.journal(matching: journalQuery, field: journalSearchFieldScope, status: journalStatus)
        guard !entries.isEmpty else {
            guard !journalQuery.isEmpty || journalStatus != .all else { return "日记账\n\n尚无有效交易。" }
            let scope = journalSearchFieldScope == .all ? "" : "\(journalSearchFieldScope.title)中的"
            let queryText = journalQuery.isEmpty ? "" : "与「\(journalQuery)」匹配的"
            let statusText = journalStatus == .all ? "" : "\(journalStatus.title)的"
            return "日记账\n\n没有\(queryText)\(scope)\(statusText)有效交易。"
        }
        let count = entries.count == report.journal.count ? "" : " · \(entries.count) / \(report.journal.count) 笔"
        var output = "日记账 · 最新在前\(count)\n点按任一交易可定位到原文\n\n"
        for entry in entries.reversed() {
            let flag = entry.flag.map { " \($0)" } ?? ""
            output += "\(entry.date)\(flag)  \(entry.summary)  · 第 \(entry.startLine) 行\n"
            if let payee = entry.payee { output += "    收款方：\(payee)\n" }
            if !entry.tags.isEmpty { output += "    标签：\(entry.tags.map { "#\($0)" }.joined(separator: " "))\n" }
            for link in entry.links { output += "    链接：\(link)\n" }
            for posting in entry.postings {
                output += "    \(posting.account)  \(LedgerParser.format(posting.amount))\n"
            }
            output += "\n"
        }
        return output
    }

    private func accountTreeText(for report: LedgerReport) -> String {
        guard !report.accounts.isEmpty else { return "账户\n\n尚未声明账户。" }
        var output = "账户\n点按账户可查看对应流水\n\n"
        let notes = Dictionary(uniqueKeysWithValues: report.accountNotes.map { ($0.account, $0.text) })
        for root in ["资产", "负债", "权益", "收入", "费用"] {
            let accounts = report.accounts.filter { $0 == root || $0.hasPrefix("\(root):") }
            guard !accounts.isEmpty else { continue }
            let rawTotal = accounts.reduce(Decimal.zero) { total, account in total + (report.balances[account] ?? .zero) }
            let displayTotal = ["负债", "权益", "收入"].contains(root) ? -rawTotal : rawTotal
            output += "\(root)  \(LedgerParser.format(displayTotal))\n"
            for account in accounts {
                let depth = account.split(separator: ":").count - 1
                let display = (["负债", "权益", "收入"].contains(root) ? -(report.balances[account] ?? .zero) : (report.balances[account] ?? .zero))
                output += "\(String(repeating: "  ", count: depth))\(account.split(separator: ":").last!)  \(LedgerParser.format(display))\n"
                if let note = notes[account] { output += "\(String(repeating: "  ", count: depth + 1))· \(note)\n" }
            }
            output += "\n"
        }
        return output
    }

    private func updatePeriodPicker(for report: LedgerReport) {
        let months = Array(Set(report.journal.map { String($0.date.prefix(7)) })).sorted(by: >)
        let desired: String?
        if selectedReportStartDate != nil || selectedReportEndDate != nil {
            desired = "自选日期…"
        } else if !hasInitializedReportPeriod {
            desired = months.first
            hasInitializedReportPeriod = true
        } else if let selected = selectedReportMonth {
            desired = months.contains(selected) ? selected : months.first
        } else {
            desired = nil
        }
        if periodPicker.itemTitles != ["全部期间"] + months + ["自选日期…"] {
            periodPicker.removeAllItems()
            periodPicker.addItems(withTitles: ["全部期间"] + months + ["自选日期…"])
        }
        if desired != "自选日期…" { selectedReportMonth = desired }
        periodPicker.selectItem(withTitle: desired ?? "全部期间")
    }

    private func updateReportTagPicker(for report: LedgerReport) {
        let tags = Array(Set(report.journal.flatMap(\.tags))).sorted()
        let desired = selectedReportTag.flatMap { tags.contains($0) ? $0 : nil }
        if reportTagPicker.itemTitles != ["所有标签"] + tags {
            reportTagPicker.removeAllItems()
            reportTagPicker.addItems(withTitles: ["所有标签"] + tags)
        }
        selectedReportTag = desired
        reportTagPicker.selectItem(withTitle: desired ?? "所有标签")
        reportKindControl.selectedSegment = PersonalReportKind.allCases.firstIndex(of: selectedReportKind) ?? 0
    }

    private func updateReportAccountPicker(for report: LedgerReport) {
        let allTitle = ui("所有账户", "All Accounts")
        let accounts = report.accounts.sorted()
        let desired = selectedReportAccount.flatMap { accounts.contains($0) ? $0 : nil }
        if reportAccountPicker.itemTitles != [allTitle] + accounts {
            reportAccountPicker.removeAllItems()
            reportAccountPicker.addItems(withTitles: [allTitle] + accounts)
        }
        selectedReportAccount = desired
        reportAccountPicker.selectItem(withTitle: desired ?? allTitle)
    }

    private func reportText(for report: LedgerReport) -> String {
        let entries = currentReportEntries(in: report)
        let selectedSummary = report.personalSummary(entries: entries)
        let title = reportPeriodTitle
        let analytics = personalAnalytics(entries: entries)
        let tagFilter = selectedReportTag.map { " · 标签 #\($0)" } ?? ""
        let accountFilter = selectedReportAccount.map { " · 账户 \($0)" } ?? ""
        var output = "\(selectedReportKind.title)报表 · \(title)\(tagFilter)\(accountFilter)\n\n"
        switch selectedReportKind {
        case .trend:
            output += "已计入交易  \(selectedSummary.transactions) 笔\n收入合计      \(LedgerParser.format(selectedSummary.incomeTotal))\n支出合计      \(LedgerParser.format(selectedSummary.expenseTotal))\n收支结余      \(LedgerParser.format(selectedSummary.net))\n支出笔数      \(analytics.expenseTransactions) 笔\n单笔平均支出  \(LedgerParser.format(analytics.averageExpense))\n"
        case .category:
            output += "支出合计      \(LedgerParser.format(selectedSummary.expenseTotal))\n支出笔数      \(analytics.expenseTransactions) 笔\n"
            if let category = analytics.largestExpenseAccount { output += "最大支出分类  \(category) · \(LedgerParser.format(analytics.largestExpense))\n" }
            output += "\n分类明细\n"
            output += selectedSummary.expenses.isEmpty ? "暂无支出。\n" : selectedSummary.expenses.sorted(by: { $0.value > $1.value }).map { "\($0.key)  \(LedgerParser.format($0.value))" }.joined(separator: "\n") + "\n"
            output += "\n付款账户\n"
            output += analytics.paymentAccounts.isEmpty ? "暂无支出付款账户。\n" : analytics.paymentAccounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)  \(LedgerParser.format($0.value))" }.joined(separator: "\n")
        case .tag:
            output += "带标签支出笔数  \(analytics.expenseTransactions) 笔\n\n标签明细\n"
            output += analytics.tagExpenses.isEmpty ? "暂无带标签的支出。\n" : analytics.tagExpenses.sorted(by: { $0.value > $1.value }).map { "#\($0.key)  \(LedgerParser.format($0.value))" }.joined(separator: "\n") + "\n"
        }
        return output
    }

    private var reportPeriodTitle: String {
        if let start = selectedReportStartDate, let end = selectedReportEndDate { return "\(start) 至 \(end)" }
        return selectedReportMonth ?? "全部期间"
    }

    private func currentReportEntries(in report: LedgerReport) -> [LedgerTransaction] {
        let periodEntries: [LedgerTransaction]
        if selectedReportStartDate != nil || selectedReportEndDate != nil { periodEntries = report.reportEntries(startDate: selectedReportStartDate, endDate: selectedReportEndDate) }
        else { periodEntries = report.journal.filter { selectedReportMonth == nil || $0.date.hasPrefix(selectedReportMonth! + "-") } }
        let tagEntries = selectedReportTag.map { tag in periodEntries.filter { $0.tags.contains(tag) } } ?? periodEntries
        return selectedReportAccount.map { account in tagEntries.filter { transaction in transaction.postings.contains { $0.account == account } } } ?? tagEntries
    }

    private func presentError(_ text: String) { let alert = NSAlert(); alert.messageText = "CountPaper"; alert.informativeText = text; alert.runModal() }

    private func starterTemplate(for language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if language == .english {
            return """
            ---
            format: countpaper/0.2
            currency: USD
            ---

            @账户
            - Assets:Cash
            - Assets:Bank
            - Liabilities:CreditCard
            - Income:Salary
            - Expenses:Dining
            - Expenses:Transport
            - Expenses:Groceries

            # \(today)
            - Lunch
              - Expenses:Dining  12.50
              - Assets:Cash  -12.50
            """
        }
        return """
        ---
        format: countpaper/0.2
        currency: CNY
        ---

        @账户
        - 资产:现金
        - 资产:银行卡
        - 资产:支付宝
        - 负债:信用卡
        - 收入:工资
        - 费用:餐饮
        - 费用:交通
        - 费用:日用品

        # \(today)
        - 今日午餐
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) { layoutDocumentViews() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmClosingAllLedgers()
    }
}
