import Cocoa
import CoreServices
import UniformTypeIdentifiers

enum CountPaperTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let canvas = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.090, green: 0.086, blue: 0.080, alpha: 1)
    )
    static let surface = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.135, green: 0.129, blue: 0.120, alpha: 1)
    )
    static let raisedSurface = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.165, green: 0.157, blue: 0.145, alpha: 1)
    )
    static let softSurface = adaptive(
        light: NSColor(calibratedRed: 0.967, green: 0.973, blue: 0.980, alpha: 1),
        dark: NSColor(calibratedRed: 0.190, green: 0.181, blue: 0.166, alpha: 1)
    )
    static let border = adaptive(
        light: NSColor(calibratedRed: 0.855, green: 0.878, blue: 0.902, alpha: 0.82),
        dark: NSColor(calibratedWhite: 0.36, alpha: 0.52)
    )
    static let ink = adaptive(light: NSColor(calibratedRed: 0.105, green: 0.122, blue: 0.145, alpha: 1), dark: NSColor(calibratedWhite: 0.93, alpha: 1))
    static let secondaryInk = adaptive(light: NSColor(calibratedRed: 0.365, green: 0.408, blue: 0.455, alpha: 1), dark: NSColor(calibratedWhite: 0.66, alpha: 1))
    static let blue = adaptive(
        light: NSColor(calibratedRed: 0.13, green: 0.38, blue: 0.70, alpha: 1),
        dark: NSColor(calibratedRed: 0.46, green: 0.68, blue: 0.80, alpha: 1)
    )
    static let blueSoft = adaptive(
        light: NSColor(calibratedRed: 0.875, green: 0.925, blue: 0.982, alpha: 1),
        dark: NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.37, alpha: 0.82)
    )
    static let red = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.31, blue: 0.27, alpha: 1), dark: NSColor(calibratedRed: 0.90, green: 0.48, blue: 0.43, alpha: 1))
    static let gold = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.54, blue: 0.18, alpha: 1), dark: NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.31, alpha: 1))
}

final class CountPaperSurfaceView: NSView {
    var fillColor: NSColor
    var strokeColor: NSColor?
    var radius: CGFloat
    var hasSoftShadow: Bool

    init(fill: NSColor, stroke: NSColor? = nil, radius: CGFloat = 0, shadow: Bool = false) {
        self.fillColor = fill
        self.strokeColor = stroke
        self.radius = radius
        self.hasSoftShadow = shadow
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = strokeColor == nil ? 0 : 0.6
        layer?.borderColor = strokeColor?.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = hasSoftShadow ? 0.07 : 0
        layer?.shadowRadius = hasSoftShadow ? 12 : 0
        layer?.shadowOffset = NSSize(width: 0, height: -3)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

enum CountPaperPreference {
    static let multipleAmounts = "preferences.multipleAmounts"
    static let multipleAmountsMigrated = "preferences.multipleAmountsMigrated"
    static let checkBalanceOnOpen = "preferences.checkBalanceOnOpen"
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

struct LedgerBalanceIssue: Equatable {
    let date: String
    let summary: String
    let line: Int
    let difference: Decimal
}

func aggregateLedgerReports(_ reports: [LedgerReport]) -> LedgerReport {
    var combined = LedgerReport()
    var accountSet = Set<String>()
    for report in reports {
        combined.diagnostics.append(contentsOf: report.diagnostics)
        combined.balanceIssues.append(contentsOf: report.balanceIssues)
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
    var rows = ["日期,时间,状态,类型,摘要,收款方,分类,账户,转入账户,标签,链接,金额"]
    for entry in entries {
        let status = entry.flag == "!" ? "待确认" : "已确认"
        let tags = entry.tags.map { "#\($0)" }.joined(separator: " ")
        let info = ledgerTransactionUIInfo(entry)
        rows.append([
            entry.date, entry.time ?? "", status, info.kindTitle(english: false), entry.summary, entry.payee ?? "",
            info.category ?? "", info.account ?? "", info.destinationAccount ?? "", tags,
            entry.links.joined(separator: " "), LedgerParser.format(info.amount)
        ].map(csvField).joined(separator: ","))
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
        case .expense, .income:
            return [category, account].compactMap { $0 }.joined(separator: " · ")
        case .transfer:
            return [account, destinationAccount].compactMap { $0 }.joined(separator: " → ")
        case .other:
            return account ?? (english ? "Other" : "其他")
        }
    }
}

func ledgerAccountDisplayName(_ account: String) -> String {
    let components = account.split(separator: ":").map(String.init)
    return components.count > 1 ? components.dropFirst().joined(separator: " · ") : account
}

func isInternalBalanceAdjustmentAccount(_ account: String) -> Bool {
    account == "权益:余额调整" || account == "Equity:BalanceAdjustment"
}

/// Adds a declaration without interpreting or reformatting the rest of a
/// plain-text ledger. The internal offset account is only created on demand.
func ledgerSourceAddingAccountDeclaration(_ raw: String, account: String) -> String? {
    guard !raw.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "- \(account)" }) else { return raw }
    let newline = raw.contains("\r\n") ? "\r\n" : "\n"
    let lines = raw.components(separatedBy: newline)
    var offset = 0
    var inAccountSection = false
    var lastAccountEnd: Int?
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lineEnd = offset + line.utf16.count + (index < lines.count - 1 ? newline.utf16.count : 0)
        if trimmed == "@账户" || trimmed == "@accounts" { inAccountSection = true }
        else if line.hasPrefix("# ") { inAccountSection = false }
        if inAccountSection, line.hasPrefix("- ") { lastAccountEnd = lineEnd }
        offset = lineEnd
    }
    guard let insertionOffset = lastAccountEnd else { return nil }
    let updated = NSMutableString(string: raw)
    updated.insert("- \(account)\(newline)", at: insertionOffset)
    return updated as String
}

func balanceAdjustmentCounterpart(for account: String) -> String {
    account.hasPrefix("Assets:") || account.hasPrefix("Liabilities:") ? "Equity:BalanceAdjustment" : "权益:余额调整"
}

func ledgerTransactionUIInfo(_ entry: LedgerTransaction) -> LedgerTransactionUIInfo {
    let amount = ledgerTransactionDisplayAmount(entry)
    if let category = entry.postings.first(where: { isLedgerAccount($0.account, .expense) }) {
        let payment = entry.postings.first { isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }
        return LedgerTransactionUIInfo(kind: .expense, category: ledgerAccountDisplayName(category.account), account: payment.map { ledgerAccountDisplayName($0.account) }, destinationAccount: nil, amount: amount)
    }
    if let category = entry.postings.first(where: { isLedgerAccount($0.account, .income) }) {
        let received = entry.postings.first { isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }
        return LedgerTransactionUIInfo(kind: .income, category: ledgerAccountDisplayName(category.account), account: received.map { ledgerAccountDisplayName($0.account) }, destinationAccount: nil, amount: amount)
    }
    if entry.postings.count >= 2, entry.postings.allSatisfy({ isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }) {
        return LedgerTransactionUIInfo(kind: .transfer, category: nil, account: ledgerAccountDisplayName(entry.postings[1].account), destinationAccount: ledgerAccountDisplayName(entry.postings[0].account), amount: amount)
    }
    return LedgerTransactionUIInfo(kind: .other, category: nil, account: entry.postings.first.map { ledgerAccountDisplayName($0.account) }, destinationAccount: nil, amount: amount)
}

func ledgerTransactionDisplayAmount(_ entry: LedgerTransaction) -> Decimal {
    if let expense = entry.postings.first(where: { isLedgerAccount($0.account, .expense) }) { return expense.amount }
    if let income = entry.postings.first(where: { isLedgerAccount($0.account, .income) }) { return -income.amount }
    return entry.postings.first(where: { $0.amount > .zero })?.amount ?? entry.postings.first?.amount ?? .zero
}

func ledgerTransactionDetail(_ entry: LedgerTransaction) -> String {
    var parts = [entry.summary]
    if let payee = entry.payee, !payee.isEmpty { parts.append(payee) }
    if !entry.tags.isEmpty { parts.append(entry.tags.map { "#\($0)" }.joined(separator: " ")) }
    return parts.joined(separator: " · ")
}

func filteredLedgerTransactions(_ entries: [LedgerTransaction], query: String = "", startDate: String? = nil, endDate: String? = nil, minimumAmount: Decimal? = nil, maximumAmount: Decimal? = nil, tag: String? = nil) -> [LedgerTransaction] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    return entries.filter { entry in
        let amount = ledgerTransactionDisplayAmount(entry)
        if let startDate, entry.date < startDate { return false }
        if let endDate, entry.date > endDate { return false }
        if let minimumAmount, amount < minimumAmount { return false }
        if let maximumAmount, amount > maximumAmount { return false }
        if let tag, !entry.tags.contains(tag) { return false }
        guard !needle.isEmpty else { return true }
        let searchable = ([entry.date, entry.time ?? "", entry.summary, entry.payee ?? "", LedgerParser.format(amount)] + entry.tags + entry.links + entry.postings.map(\.account)).joined(separator: " ").localizedLowercase
        return searchable.contains(needle)
    }
}

/// One chronological pass updates balances. Formatting every requested account
/// after every transaction is inherently O(transactions × accounts), while the
/// accounting work itself remains O(postings) and never rescans prior entries.
func chronologicallyOrderedTransactions(_ entries: [LedgerTransaction]) -> [LedgerTransaction] {
    entries.sorted {
        if $0.date != $1.date { return $0.date < $1.date }
        if ($0.time ?? "") != ($1.time ?? "") { return ($0.time ?? "") < ($1.time ?? "") }
        return $0.startLine < $1.startLine
    }
}

func ledgerTransactionDateTime(_ entry: LedgerTransaction) -> String {
    entry.time.map { "\(entry.date) \($0)" } ?? entry.date
}

func signedLedgerAmount(_ value: Decimal) -> String {
    value > .zero ? "+\(LedgerParser.format(value))" : LedgerParser.format(value)
}

func reconciliationModeText(entries: [LedgerTransaction], accounts: [String], english: Bool = false, newestFirst: Bool = false) -> String {
    let tracked = accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }.sorted()
    guard !entries.isEmpty else { return english ? "No transactions" : "尚无交易" }
    guard !tracked.isEmpty else { return english ? "No asset or liability accounts" : "尚未声明资产或负债账户" }
    let chronological = chronologicallyOrderedTransactions(entries)
    var balances: [String: Decimal] = [:]
    balances.reserveCapacity(tracked.count)
    var rendered: [(entry: LedgerTransaction, line: String)] = []
    rendered.reserveCapacity(chronological.count)
    for entry in chronological {
        var trackedChanges: [String: Decimal] = [:]
        for posting in entry.postings {
            if isLedgerAccount(posting.account, .asset) || isLedgerAccount(posting.account, .liability) {
                balances[posting.account, default: .zero] += posting.amount
                trackedChanges[posting.account, default: .zero] += posting.amount
            }
        }
        let info = ledgerTransactionUIInfo(entry)
        let details = [entry.payee, entry.tags.isEmpty ? nil : entry.tags.map { "#\($0)" }.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " · ")
        let heading = "\(ledgerTransactionDateTime(entry))  \(entry.summary)\(details.isEmpty ? "" : "  ·  \(details)")"
        let balanceItems = tracked.compactMap { account -> String? in
            guard let rawChange = trackedChanges[account], rawChange != .zero else { return nil }
            let balance = displayBalance(balances[account, default: .zero], account: account)
            let change = displayBalance(rawChange, account: account)
            return "\(ledgerAccountDisplayName(account)) \(LedgerParser.format(balance)) (\(signedLedgerAmount(change)))"
        }
        let kind = info.kindTitle(english: english)
        let line = "\(heading)     \(kind) \(LedgerParser.format(info.amount))  ·  \(balanceItems.joined(separator: "   ·   "))"
        rendered.append((entry, line))
    }
    if newestFirst { rendered.reverse() }
    return rendered.map(\.line).joined(separator: "\n")
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

struct LedgerDateConsolidation: Equatable {
    let text: String
    let mergedHeadings: Int
    let removedEmptyHeadings: Int
}

/// Makes the outline invariant explicit: every ISO date owns one and only one
/// section. Complete transaction/comment lines move together; their contents
/// are never interpreted or rewritten by this structural operation.
func consolidatedLedgerDateSections(_ raw: String) -> LedgerDateConsolidation {
    let newline = raw.contains("\r\n") ? "\r\n" : "\n"
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
    let hadTrailingNewline = normalized.hasSuffix("\n")
    var lines = normalized.components(separatedBy: "\n")
    if hadTrailingNewline, lines.last == "" { lines.removeLast() }
    struct Occurrence { let date: String; var body: [String] }
    var prefix: [String] = []
    var occurrences: [Occurrence] = []
    let headingPattern = try! NSRegularExpression(pattern: "^# (\\d{4}-\\d{2}-\\d{2})\\s*$")
    for line in lines {
        let range = NSRange(line.startIndex..., in: line)
        if let match = headingPattern.firstMatch(in: line, range: range),
           let dateRange = Range(match.range(at: 1), in: line) {
            occurrences.append(Occurrence(date: String(line[dateRange]), body: []))
        } else if occurrences.isEmpty {
            prefix.append(line)
        } else {
            occurrences[occurrences.count - 1].body.append(line)
        }
    }
    guard !occurrences.isEmpty else { return LedgerDateConsolidation(text: raw, mergedHeadings: 0, removedEmptyHeadings: 0) }

    func trimmedBlankLines(_ source: [String]) -> [String] {
        var result = source
        while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeFirst() }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }
        return result
    }
    while prefix.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { prefix.removeLast() }
    var orderedDates: [String] = []
    var grouped: [String: [String]] = [:]
    var merged = 0
    var removedEmpty = 0
    for occurrence in occurrences {
        let body = trimmedBlankLines(occurrence.body)
        if grouped[occurrence.date] == nil {
            orderedDates.append(occurrence.date)
            grouped[occurrence.date] = []
        } else {
            merged += 1
        }
        if body.isEmpty { removedEmpty += 1; continue }
        if grouped[occurrence.date]?.isEmpty == false { grouped[occurrence.date]?.append("") }
        grouped[occurrence.date]?.append(contentsOf: body)
    }
    let sections = orderedDates.compactMap { date -> String? in
        guard let body = grouped[date], !body.isEmpty else { return nil }
        return (["# \(date)"] + body).joined(separator: "\n")
    }
    var result = prefix.joined(separator: "\n")
    if !result.isEmpty, !sections.isEmpty { result += "\n\n" }
    result += sections.joined(separator: "\n\n")
    if hadTrailingNewline { result += "\n" }
    guard merged > 0 || removedEmpty > 0 else { return LedgerDateConsolidation(text: raw, mergedHeadings: 0, removedEmptyHeadings: 0) }
    return LedgerDateConsolidation(text: result.replacingOccurrences(of: "\n", with: newline), mergedHeadings: merged, removedEmptyHeadings: removedEmpty)
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

/// Finder can deliver the same Apple Event more than once when a document is
/// double-clicked repeatedly while the app is launching. Normalize aliases and
/// preserve request order so one document creates exactly one ledger tab.
func uniqueLedgerDocumentURLs(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    var output: [URL] = []
    for url in urls where url.isFileURL && url.pathExtension.lowercased() == "countpaper" {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        let key = normalized.path.precomposedStringWithCanonicalMapping
        if seen.insert(key).inserted { output.append(normalized) }
    }
    return output
}

func shouldReplacePlaceholderLedger(_ sessions: [LedgerSession]) -> Bool {
    sessions.count == 1 && sessions[0].url == nil && !sessions[0].isDirty
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

/// Maps a click in a plain-text report to its transaction block without exposing
/// implementation-only source line numbers in the interface.
func renderedReportBlockIndex(at offset: Int, in renderedText: String) -> Int? {
    let source = renderedText as NSString
    guard offset >= 0, offset <= source.length else { return nil }
    let prefix = source.substring(to: offset)
    return prefix.components(separatedBy: "\n\n").count - 1
}

/// The compact reconciliation list uses one physical line per transaction.
func reconciliationLineIndex(at offset: Int, in renderedText: String) -> Int? {
    let source = renderedText as NSString
    guard offset >= 0, offset <= source.length else { return nil }
    let prefix = source.substring(to: offset)
    return prefix.components(separatedBy: "\n").count - 1
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

/// Rebuilds only one CountPaper 0.2 outline transaction. Unknown indented
/// content makes the transaction ineligible for form editing, preventing a
/// convenient edit from silently discarding hand-written text.
func canonicalOutlineTransactionBlock(source: String, summary: String, flag: Character?, time: String? = nil, payee: String?, tags: [String], links: [String] = [], destination: String, sourceAccount: String, amount: Decimal) -> String? {
    guard amount != .zero else { return nil }
    let lineEnding = source.contains("\r\n") ? "\r\n" : "\n"
    let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
    let lines = normalized.components(separatedBy: "\n")
    guard lines.count >= 3, lines[0].hasPrefix("- ") else { return nil }
    var postingCount = 0
    for line in lines.dropFirst() {
        guard line.hasPrefix("  - ") else { return nil }
        let body = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("时间:") || body.hasPrefix("时间：") || body.hasPrefix("time:") ||
            body.hasPrefix("收款方:") || body.hasPrefix("收款方：") ||
            body.hasPrefix("标签:") || body.hasPrefix("标签：") ||
            body.hasPrefix("链接:") || body.hasPrefix("链接：") { continue }
        let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")) != nil else { return nil }
        postingCount += 1
    }
    guard postingCount == 2 else { return nil }
    let marker = flag.map { " \($0)" } ?? ""
    var output = "-\(marker) \(summary)"
    if let time, time.range(of: "^(?:[01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil {
        let timeKey = source.contains("  - time:") ? "time:" : "时间:"
        output += "\(lineEnding)  - \(timeKey) \(time)"
    }
    if let payee, !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { output += "\(lineEnding)  - 收款方: \(payee.trimmingCharacters(in: .whitespacesAndNewlines))" }
    if !tags.isEmpty { output += "\(lineEnding)  - 标签: \(tags.joined(separator: ", "))" }
    if !links.isEmpty { output += "\(lineEnding)  - 链接: \(links.joined(separator: ", "))" }
    output += "\(lineEnding)  - \(destination)  \(LedgerParser.format(amount))"
    output += "\(lineEnding)  - \(sourceAccount)  \(LedgerParser.format(-amount))"
    if source.hasSuffix("\r\n") || source.hasSuffix("\n") { output += lineEnding }
    return output
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
        var transactionTime: String?
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
        var seenDateHeadings = Set<String>()
        let lines = text.components(separatedBy: .newlines)

        func finishTransaction(at line: Int) {
            guard let start = transactionStart else { return }
            if current.count < 2 {
                report.diagnostics.append("错误：第 \(start) 行交易缺少完整账户信息")
                transactionHasError = true
            }
            let total = current.reduce(Decimal.zero) { $0 + $1.amount }
            if total != .zero {
                report.diagnostics.append("错误：第 \(start) 行交易不平衡（差额 \(format(total))）")
                report.balanceIssues.append(LedgerBalanceIssue(date: currentDate ?? "", summary: transactionSummary ?? "", line: start, difference: total))
                transactionHasError = true
            }
            if !transactionHasError {
                report.transactions += 1
                for posting in current {
                    report.balances[posting.account, default: .zero] += posting.amount
                    if isLedgerAccount(posting.account, .expense) { report.expenses[posting.account, default: .zero] += posting.amount }
                }
                report.journal.append(LedgerTransaction(date: currentDate ?? "", time: transactionTime, summary: transactionSummary ?? "", flag: transactionFlag, postings: current, payee: transactionPayee, tags: transactionTags, links: transactionLinkValues, startLine: start, endLine: max(start, line - 1)))
            }
            current = []
            transactionStart = nil
            transactionSummary = nil
            transactionTime = nil
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
            if trimmed == "@账户" || trimmed == "@accounts" {
                guard !sawAccountMarker, transactionStart == nil, currentDate == nil else { report.diagnostics.append("错误：第 \(lineNumber) 行账户区标记只能在正文开始处出现一次"); continue }
                sawAccountMarker = true
                inAccountSection = true
                continue
            }
            if rawLine.hasPrefix("# ") {
                finishTransaction(at: lineNumber)
                inAccountSection = false
                let date = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if isValidISODate(date) {
                    currentDate = date
                    if !seenDateHeadings.insert(date).inserted { report.diagnostics.append("错误：第 \(lineNumber) 行重复日期标题“# \(date)”；同一天的交易必须位于同一标题下") }
                } else { currentDate = nil; report.diagnostics.append("错误：第 \(lineNumber) 行日期标题应为“# YYYY-MM-DD”") }
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
                if let prefix = ["时间:", "时间：", "time:"].first(where: { body.hasPrefix($0) }) {
                    let value = String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if value.range(of: "^(?:[01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil { transactionTime = value }
                    else { report.diagnostics.append("错误：第 \(lineNumber) 行时间应为 24 小时制 HH:mm"); transactionHasError = true }
                    continue
                }
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
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户记录应为“  - 账户名  金额”")
                    transactionHasError = true
                    continue
                }
                let account = String(parts[0])
                if !accounts.contains(account) { report.diagnostics.append("错误：第 \(lineNumber) 行使用了未声明账户「\(account)」"); transactionHasError = true }
                current.append(LedgerPosting(account: account, amount: amount, line: lineNumber))
                continue
            }
            report.diagnostics.append("错误：第 \(lineNumber) 行无法识别；请使用 # 日期、- 交易或两空格缩进的账户记录")
        }
        finishTransaction(at: lines.count + 1)
        if !sawOpeningFence || !sawClosingFence { report.diagnostics.insert("错误：缺少完整的 Markdown 文件头（---）", at: 0) }
        if !text.contains("format: countpaper/0.2") { report.diagnostics.insert("错误：缺少“format: countpaper/0.2”", at: min(1, report.diagnostics.count)) }
        if text.range(of: "(?m)^currency: [A-Z]{3}$", options: .regularExpression) == nil { report.diagnostics.insert("错误：缺少三位大写 currency: 代码", at: min(2, report.diagnostics.count)) }
        if !sawAccountMarker { report.diagnostics.append("错误：缺少账户区标记“@账户”或“@accounts”") }
        if accounts.isEmpty { report.diagnostics.append("错误：至少在账户区标记下声明一个账户") }
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
            if current.count < 2 { report.diagnostics.append("错误：第 \(start) 行交易缺少完整账户信息"); transactionHasError = true }
            let total = current.reduce(Decimal.zero) { $0 + $1.amount }
            if total != .zero {
                report.diagnostics.append("错误：第 \(start) 行交易不平衡（差额 \(format(total))）")
                report.balanceIssues.append(LedgerBalanceIssue(date: transactionDate ?? "", summary: transactionSummary ?? "", line: start, difference: total))
                transactionHasError = true
            }
            if !transactionHasError {
                report.transactions += 1
                for posting in current {
                    report.balances[posting.account, default: .zero] += posting.amount
                    if posting.account.hasPrefix("费用:") { report.expenses[posting.account, default: .zero] += posting.amount }
                }
                report.journal.append(LedgerTransaction(date: transactionDate ?? "", time: nil, summary: transactionSummary ?? "", flag: transactionFlag, postings: current, payee: transactionPayee, tags: transactionTags, links: transactionLinkValues, startLine: start, endLine: max(start, line - 1)))
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
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户记录应为“账户名  金额”")
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

final class DashboardRecentTextView: NSTextView {
    var onRowClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let offset = min(characterIndexForInsertion(at: point), (string as NSString).length)
        let prefix = (string as NSString).substring(to: offset)
        onRowClick?(prefix.reduce(into: 0) { if $1 == "\n" { $0 += 1 } })
    }

    override func insertNewline(_ sender: Any?) {
        let offset = min(selectedRange().location, (string as NSString).length)
        let prefix = (string as NSString).substring(to: offset)
        onRowClick?(prefix.reduce(into: 0) { if $1 == "\n" { $0 += 1 } })
    }
}

final class TransactionBrowserController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let english: Bool
    private let panel: NSPanel
    private let search = NSSearchField(frame: .zero)
    private let startDate = NSDatePicker()
    private let endDate = NSDatePicker()
    private let minimumAmount = NSTextField(string: "")
    private let maximumAmount = NSTextField(string: "")
    private let tagPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let table = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let editButton = NSButton(title: "", target: nil, action: nil)
    private let deleteButton = NSButton(title: "", target: nil, action: nil)
    private var transactions: [LedgerTransaction]
    private var filtered: [LedgerTransaction] = []
    var onEdit: ((LedgerTransaction) -> Void)?
    var onDelete: ((LedgerTransaction) -> Bool)?

    init(transactions: [LedgerTransaction], english: Bool) {
        self.transactions = transactions
        self.english = english
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        buildInterface()
        updateTransactions(transactions, resetFilters: true)
    }

    private func ui(_ chinese: String, _ englishText: String) -> String { english ? englishText : chinese }

    private func buildInterface() {
        panel.title = ui("全部交易", "All Transactions")
        panel.minSize = NSSize(width: 760, height: 500)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        let content = CountPaperSurfaceView(fill: CountPaperTheme.canvas)
        panel.contentView = content

        let heading = NSTextField(labelWithString: ui("查找交易", "Find Transactions"))
        heading.font = .systemFont(ofSize: 22, weight: .semibold); heading.textColor = CountPaperTheme.ink
        heading.frame = NSRect(x: 24, y: 552, width: 220, height: 28)
        content.addSubview(heading)

        search.placeholderString = ui("搜索日期、金额、摘要、收款方、账户或标签", "Search date, amount, description, payee, account, or tag")
        search.sendsSearchStringImmediately = true; search.target = self; search.action = #selector(filtersChanged(_:)); search.delegate = self
        search.frame = NSRect(x: 24, y: 510, width: 480, height: 28); search.autoresizingMask = [.width]
        content.addSubview(search)
        tagPicker.target = self; tagPicker.action = #selector(filtersChanged(_:)); tagPicker.frame = NSRect(x: 516, y: 510, width: 176, height: 28); tagPicker.autoresizingMask = [.minXMargin]
        content.addSubview(tagPicker)
        let reset = NSButton(title: ui("重置筛选", "Reset"), target: self, action: #selector(resetFilters(_:)))
        reset.bezelStyle = .rounded; reset.frame = NSRect(x: 704, y: 510, width: 172, height: 28); reset.autoresizingMask = [.minXMargin]
        content.addSubview(reset)

        startDate.datePickerStyle = .textFieldAndStepper; startDate.datePickerElements = .yearMonthDay; startDate.target = self; startDate.action = #selector(filtersChanged(_:))
        endDate.datePickerStyle = .textFieldAndStepper; endDate.datePickerElements = .yearMonthDay; endDate.target = self; endDate.action = #selector(filtersChanged(_:))
        minimumAmount.placeholderString = ui("最低金额", "Minimum amount"); maximumAmount.placeholderString = ui("最高金额", "Maximum amount")
        minimumAmount.delegate = self; maximumAmount.delegate = self
        let filterItems: [(String, NSView, CGFloat)] = [
            (ui("从", "From"), startDate, 150), (ui("到", "To"), endDate, 150),
            (ui("金额", "Amount"), minimumAmount, 120), (ui("至", "to"), maximumAmount, 120)
        ]
        var x: CGFloat = 24
        for (title, control, width) in filterItems {
            let label = NSTextField(labelWithString: title); label.textColor = CountPaperTheme.secondaryInk; label.font = .systemFont(ofSize: 11, weight: .medium)
            label.frame = NSRect(x: x, y: 472, width: 46, height: 22); content.addSubview(label); x += 42
            control.frame = NSRect(x: x, y: 469, width: width, height: 26); content.addSubview(control); x += width + 14
        }

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 72, width: 852, height: 382))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 12; scroll.layer?.borderWidth = 0.6; scroll.layer?.borderColor = CountPaperTheme.border.cgColor
        scroll.autoresizingMask = [.width, .height]
        let columns: [(String, String, CGFloat)] = [
            ("date", ui("日期与时间", "Date & Time"), 132), ("detail", ui("摘要与备注", "Description & Notes"), 253),
            ("account", ui("分类 / 账户", "Category / Account"), 230), ("tags", ui("标签", "Tags"), 130), ("amount", ui("金额", "Amount"), 90)
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier)); column.title = title; column.width = width
            table.addTableColumn(column)
        }
        table.headerView = NSTableHeaderView(); table.rowHeight = 34; table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(editSelected(_:)); table.allowsEmptySelection = true
        scroll.documentView = table; content.addSubview(scroll)

        countLabel.textColor = CountPaperTheme.secondaryInk; countLabel.font = .systemFont(ofSize: 12)
        countLabel.frame = NSRect(x: 24, y: 26, width: 260, height: 24); countLabel.autoresizingMask = [.maxYMargin]
        content.addSubview(countLabel)
        editButton.title = ui("修改", "Edit"); editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: editButton.title); editButton.imagePosition = .imageLeading; editButton.target = self; editButton.action = #selector(editSelected(_:)); editButton.isEnabled = false
        editButton.frame = NSRect(x: 610, y: 20, width: 84, height: 30); editButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(editButton)
        deleteButton.title = ui("删除", "Delete"); deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: deleteButton.title); deleteButton.imagePosition = .imageLeading; deleteButton.contentTintColor = CountPaperTheme.red; deleteButton.target = self; deleteButton.action = #selector(deleteSelected(_:)); deleteButton.isEnabled = false
        deleteButton.frame = NSRect(x: 702, y: 20, width: 84, height: 30); deleteButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(deleteButton)
        let close = NSButton(title: ui("完成", "Done"), target: self, action: #selector(close(_:))); close.bezelStyle = .rounded
        close.frame = NSRect(x: 794, y: 20, width: 82, height: 30); close.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(close)
    }

    func show() {
        panel.center(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(search); NSApp.activate(ignoringOtherApps: true)
    }

    func updateTransactions(_ entries: [LedgerTransaction], resetFilters: Bool = false) {
        transactions = entries.sorted { $0.date == $1.date ? $0.startLine > $1.startLine : $0.date > $1.date }
        let dates = transactions.compactMap { Self.dateFormatter.date(from: $0.date) }
        if resetFilters {
            startDate.dateValue = dates.min() ?? Date(); endDate.dateValue = dates.max() ?? Date()
            search.stringValue = ""; minimumAmount.stringValue = ""; maximumAmount.stringValue = ""
        }
        let priorTag = resetFilters ? nil : tagPicker.titleOfSelectedItem
        tagPicker.removeAllItems(); tagPicker.addItem(withTitle: ui("所有标签", "All Tags"))
        tagPicker.addItems(withTitles: Array(Set(transactions.flatMap(\.tags))).sorted().map { "#\($0)" })
        if let priorTag { tagPicker.selectItem(withTitle: priorTag) }
        refresh()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()

    private func refresh() {
        let selectedTag = tagPicker.indexOfSelectedItem > 0 ? tagPicker.titleOfSelectedItem.map { String($0.dropFirst()) } : nil
        let min = Decimal(string: minimumAmount.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        let max = Decimal(string: maximumAmount.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        filtered = filteredLedgerTransactions(transactions, query: search.stringValue, startDate: Self.dateFormatter.string(from: startDate.dateValue), endDate: Self.dateFormatter.string(from: endDate.dateValue), minimumAmount: min, maximumAmount: max, tag: selectedTag)
        table.reloadData(); table.deselectAll(nil); updateSelectionState()
        countLabel.stringValue = ui("找到 \(filtered.count) 笔交易", "\(filtered.count) transactions")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let entry = filtered[row]
        let value: String = switch identifier.rawValue {
        case "date": ledgerTransactionDateTime(entry)
        case "detail": ledgerTransactionDetail(entry)
        case "account": ledgerTransactionUIInfo(entry).context(english: english)
        case "tags": entry.tags.map { "#\($0)" }.joined(separator: " ")
        case "amount": LedgerParser.format(ledgerTransactionDisplayAmount(entry))
        default: ""
        }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier; cell.subviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: value); label.lineBreakMode = .byTruncatingTail; label.textColor = CountPaperTheme.ink
        label.font = identifier.rawValue == "amount" ? .monospacedDigitSystemFont(ofSize: 12, weight: .medium) : .systemFont(ofSize: 12)
        label.alignment = identifier.rawValue == "amount" ? .right : .left; label.frame = NSRect(x: 5, y: 7, width: max(30, (tableColumn?.width ?? 100) - 10), height: 19); label.autoresizingMask = [.width]
        cell.addSubview(label); return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSelectionState() }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    @objc private func filtersChanged(_ sender: Any?) { refresh() }
    private func updateSelectionState() { let valid = filtered.indices.contains(table.selectedRow); editButton.isEnabled = valid; deleteButton.isEnabled = valid }

    @objc private func resetFilters(_ sender: Any?) { updateTransactions(transactions, resetFilters: true) }
    @objc private func editSelected(_ sender: Any?) {
        guard filtered.indices.contains(table.selectedRow) else { return }
        let entry = filtered[table.selectedRow]; panel.orderOut(nil); onEdit?(entry)
    }
    @objc private func deleteSelected(_ sender: Any?) {
        guard filtered.indices.contains(table.selectedRow) else { return }
        let entry = filtered[table.selectedRow]
        if onDelete?(entry) == true { transactions.removeAll { $0.startLine == entry.startLine }; refresh() }
    }
    @objc private func close(_ sender: Any?) { panel.orderOut(nil) }
}

final class DateRangeSelectionBinder: NSObject {
    let picker: NSDatePicker
    let mode: NSSegmentedControl
    let startLabel: NSTextField
    let endLabel: NSTextField
    var startDate: Date
    var endDate: Date
    private let formatter: DateFormatter

    init(picker: NSDatePicker, mode: NSSegmentedControl, startLabel: NSTextField, endLabel: NSTextField, startDate: Date, endDate: Date, formatter: DateFormatter) {
        self.picker = picker; self.mode = mode; self.startLabel = startLabel; self.endLabel = endLabel
        self.startDate = startDate; self.endDate = endDate; self.formatter = formatter
        super.init(); refreshLabels()
    }

    @objc func changeMode(_ sender: NSSegmentedControl) {
        picker.dateValue = sender.selectedSegment == 0 ? startDate : endDate
        refreshLabels()
    }
    @objc func chooseDate(_ sender: NSDatePicker) {
        if mode.selectedSegment == 0 {
            startDate = sender.dateValue
            if startDate > endDate { endDate = startDate }
        } else {
            endDate = sender.dateValue
            if endDate < startDate { startDate = endDate }
        }
        refreshLabels()
    }
    private func refreshLabels() {
        startLabel.stringValue = formatter.string(from: startDate)
        endLabel.stringValue = formatter.string(from: endDate)
        startLabel.textColor = mode.selectedSegment == 0 ? CountPaperTheme.blue : CountPaperTheme.secondaryInk
        endLabel.textColor = mode.selectedSegment == 1 ? CountPaperTheme.blue : CountPaperTheme.secondaryInk
    }
}

final class AccountBalanceLabelBinder: NSObject {
    let picker: NSPopUpButton
    let label: NSTextField
    let report: LedgerReport
    let english: Bool

    init(picker: NSPopUpButton, label: NSTextField, report: LedgerReport, english: Bool) {
        self.picker = picker; self.label = label; self.report = report; self.english = english
    }

    @objc func update(_ sender: Any?) {
        let account = picker.titleOfSelectedItem ?? ""
        let current = displayBalance(report.balances[account, default: .zero], account: account)
        label.stringValue = english ? "Current ledger balance: \(LedgerParser.format(current))" : "当前账面余额：\(LedgerParser.format(current))"
    }
}

/// CountPaper retains a live source document in memory. Command-W shelves the
/// window instead of closing the last native window, avoiding the termination
/// path while keeping the requested shortcut behaviour.
final class CountPaperWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown,
           modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return
        }
        super.sendEvent(event)
    }

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
        CountPaperTheme.surface.setFill()
        bounds.fill()
        switch kind {
        case .trend: drawTrend()
        case .category: drawPieReport(title: "支出分类", values: expenseCategories, stripPrefix: "费用:")
        case .tag: drawPieReport(title: "标签支出", values: tagExpenses, stripPrefix: "")
        }
    }

    private func drawTrend() {
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: CountPaperTheme.ink]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: CountPaperTheme.secondaryInk]
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
        let gridColor = CountPaperTheme.border.withAlphaComponent(0.55)
        for fraction in [0.0, 0.5, 1.0] {
            let y = plot.minY + plot.height * fraction
            gridColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            path.lineWidth = fraction == 0.5 ? 1.0 : 0.5
            path.stroke()
        }
        let incomeColor = CountPaperTheme.blue
        let expenseColor = CountPaperTheme.red
        let netColor = CountPaperTheme.gold
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
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: CountPaperTheme.ink]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: CountPaperTheme.secondaryInk]
        (title as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 24), withAttributes: titleAttributes)
        let entries = values.sorted { $0.value > $1.value }
        let total = entries.reduce(Decimal.zero) { $0 + $1.value }
        guard total > .zero else {
            ("当前筛选条件下暂无可统计数据" as NSString).draw(at: NSPoint(x: 14, y: bounds.midY - 6), withAttributes: detailAttributes)
            return
        }
        let colors: [NSColor] = [
            CountPaperTheme.red,
            CountPaperTheme.gold,
            CountPaperTheme.blue,
            CountPaperTheme.red.withAlphaComponent(0.66),
            CountPaperTheme.blue.withAlphaComponent(0.62)
        ]
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
    private let dashboardRecentView = DashboardRecentTextView()
    private let dashboardEditButton = NSButton(title: "", target: nil, action: nil)
    private let dashboardDeleteButton = NSButton(title: "", target: nil, action: nil)
    private let dashboardMoreButton = NSButton(title: "", target: nil, action: nil)
    private let inlineSaveButton = NSButton(title: "", target: nil, action: nil)
    private let inlineCancelEditButton = NSButton(title: "", target: nil, action: nil)
    private let inlineEntryTitleLabel = NSTextField(labelWithString: "")
    private var dashboardRecentTransactions: [LedgerTransaction] = []
    private var selectedDashboardTransaction: LedgerTransaction?
    private var editingDashboardTransaction: LedgerTransaction?
    private var transactionBrowserController: TransactionBrowserController?
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
    private enum SidePanelMode { case overview, journal, reconciliation, accounts, reports }
    private var sidePanelMode: SidePanelMode = .overview
    private var reportNavigationLines: [Int] = []
    private weak var sidePanelControl: NSSegmentedControl?
    private var sidebarButtons: [NSButton] = []
    private let documentNameLabel = NSTextField(labelWithString: "")
    private let inspectorTitleLabel = NSTextField(labelWithString: "")
    private weak var journalFilterContainer: NSStackView?
    private weak var reportFilterContainer: NSStackView?
    private weak var accountActionContainer: NSStackView?
    private weak var reconciliationOrderContainer: NSStackView?
    private let reconciliationOrderControl = NSSegmentedControl(labels: ["" , ""], trackingMode: .selectOne, target: nil, action: nil)
    private var reconciliationNewestFirst = true
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
    private var pendingOpenURLs: [URL] = []
    private var documentOpenWorkItem: DispatchWorkItem?
    private var lastKnownFileSignature: LedgerFileSignature?
    private var hasExternalConflict = false
    private var fileMonitorTimer: Timer?
    private let recentMenu = NSMenu(title: "最近使用")
    private let countPaperContentType = UTType(filenameExtension: "countpaper") ?? .plainText
    private var quickEntryFormBinder: QuickEntryFormBinder?
    private let syntaxHighlightLimit = 1_500_000
    private var highlightedReportLine: NSRange?
    private var allowsMultipleAmounts: Bool { UserDefaults.standard.bool(forKey: CountPaperPreference.multipleAmounts) }
    private var checksBalanceOnOpen: Bool { UserDefaults.standard.bool(forKey: CountPaperPreference.checkBalanceOnOpen) }
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
        UserDefaults.standard.register(defaults: [
            CountPaperPreference.multipleAmounts: true,
            CountPaperPreference.checkBalanceOnOpen: true
        ])
        if !UserDefaults.standard.bool(forKey: CountPaperPreference.multipleAmountsMigrated) {
            UserDefaults.standard.set(true, forKey: CountPaperPreference.multipleAmounts)
            UserDefaults.standard.set(true, forKey: CountPaperPreference.multipleAmountsMigrated)
        }
        buildMenu()
        buildWindow()
        buildSourceWindow()
        let launchURLs = uniqueLedgerDocumentURLs(pendingOpenURLs)
        pendingOpenURLs = []
        if launchURLs.isEmpty {
            loadUntitledSample()
        } else {
            launchURLs.forEach(loadDocument(at:))
        }
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
        revealMainWindow()
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
        enqueueDocumentOpenRequests(urls)
    }

    /// Compatibility path for Launch Services versions which still dispatch
    /// the legacy filename selector for a registered document type.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        enqueueDocumentOpenRequests([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        enqueueDocumentOpenRequests(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    private func enqueueDocumentOpenRequests(_ urls: [URL]) {
        let ledgerURLs = uniqueLedgerDocumentURLs(urls)
        guard !ledgerURLs.isEmpty else {
            revealMainWindow()
            return
        }
        pendingOpenURLs = uniqueLedgerDocumentURLs(pendingOpenURLs + ledgerURLs)
        guard hasCompletedLaunch, window != nil else {
            return
        }
        // Coalesce the burst of Apple Events produced by repeated Finder
        // double-clicks. Existing open tabs provide a second idempotency guard.
        documentOpenWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.drainDocumentOpenRequests() }
        documentOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func drainDocumentOpenRequests() {
        documentOpenWorkItem = nil
        guard hasCompletedLaunch, window != nil else { return }
        let urls = uniqueLedgerDocumentURLs(pendingOpenURLs)
        pendingOpenURLs = []
        urls.forEach(loadDocument(at:))
        revealMainWindow()
    }

    private func revealMainWindow() {
        guard let window else { return }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
        fileMenu.addItem(withTitle: ui("设为 .countpaper 默认打开应用", "Set as Default .countpaper App"), action: #selector(setAsDefaultEditor(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: ui("导出当前收支报表 CSV…", "Export Current Report CSV…"), action: #selector(exportReportCSV(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: ui("导出当前日记账 CSV…", "Export Current Journal CSV…"), action: #selector(exportJournalCSV(_:)), keyEquivalent: "")
        let recent = NSMenuItem(title: ui("最近使用", "Recent Documents"), action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        fileMenu.addItem(recent)
        rebuildRecentMenu()
        let edit = NSMenuItem(title: ui("编辑", "Edit"), action: nil, keyEquivalent: ""); menu.addItem(edit)
        let editMenu = NSMenu(title: ui("编辑", "Edit")); edit.submenu = editMenu
        editMenu.addItem(withTitle: ui("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: ui("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: ui("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: ui("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: ui("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: ui("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: ui("向右缩进", "Indent Right"), action: #selector(indentSelectedLines(_:)), keyEquivalent: "]")
        editMenu.addItem(withTitle: ui("向左缩进", "Indent Left"), action: #selector(outdentSelectedLines(_:)), keyEquivalent: "[")
        let find = editMenu.addItem(withTitle: ui("查找…", "Find…"), action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editMenu.addItem(withTitle: ui("跳转到行…", "Go to Line…"), action: #selector(goToLine(_:)), keyEquivalent: "l")
        let ledger = NSMenuItem(title: ui("账本", "Ledger"), action: nil, keyEquivalent: ""); menu.addItem(ledger)
        let ledgerMenu = NSMenu(title: ui("账本", "Ledger")); ledger.submenu = ledgerMenu
        ledgerMenu.addItem(withTitle: ui("记一笔…", "Record Transaction…"), action: #selector(recordTransaction(_:)), keyEquivalent: "e")
        ledgerMenu.addItem(.separator())
        ledgerMenu.addItem(withTitle: ui("添加账户…", "Add Account…"), action: #selector(addAccount(_:)), keyEquivalent: "a")
        ledgerMenu.addItem(withTitle: ui("调整账户余额…", "Adjust Account Balance…"), action: #selector(adjustAccountBalance(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("添加账户备注…", "Add Account Note…"), action: #selector(addAccountNote(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("添加对账记录…", "Add Reconciliation…"), action: #selector(addReconciliation(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("添加事件…", "Add Event…"), action: #selector(addEvent(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("编辑光标所在交易…", "Edit Transaction at Cursor…"), action: #selector(editTransactionAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("打开光标所在交易的链接…", "Open Transaction Link at Cursor…"), action: #selector(openTransactionLinkAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("标记待确认／确认光标所在交易", "Toggle Transaction Confirmation"), action: #selector(toggleTransactionStatusAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("删除光标所在交易…", "Delete Transaction at Cursor…"), action: #selector(deleteTransactionAtCursor(_:)), keyEquivalent: "")
        ledgerMenu.addItem(.separator())
        ledgerMenu.addItem(withTitle: ui("合并重复日期标题", "Merge Duplicate Date Headings"), action: #selector(consolidateDateHeadings(_:)), keyEquivalent: "")
        ledgerMenu.addItem(withTitle: ui("重新校验", "Validate Again"), action: #selector(reparseNow), keyEquivalent: "r")
        ledgerMenu.addItem(withTitle: ui("跳到下一个错误", "Go to Next Error"), action: #selector(jumpToNextDiagnostic(_:)), keyEquivalent: "j")
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
        let container = CountPaperSurfaceView(fill: CountPaperTheme.canvas)
        container.layer?.masksToBounds = true
        let stack = NSStackView(frame: container.bounds)
        stack.orientation = .vertical
        stack.alignment = .width; stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 30, right: 28)
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

        dashboardTitleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        dashboardTitleLabel.textColor = CountPaperTheme.ink
        dashboardTitleLabel.alignment = .left
        dashboardTitleLabel.widthAnchor.constraint(equalToConstant: 644).isActive = true
        stack.addArrangedSubview(dashboardTitleLabel)
        let summaryCard = CountPaperSurfaceView(fill: CountPaperTheme.surface, stroke: CountPaperTheme.border, radius: 16, shadow: true)
        summaryCard.widthAnchor.constraint(equalToConstant: 644).isActive = true
        summaryCard.heightAnchor.constraint(equalToConstant: 92).isActive = true
        let statRow = NSStackView(); statRow.orientation = .horizontal; statRow.alignment = .centerY; statRow.spacing = 0
        statRow.translatesAutoresizingMaskIntoConstraints = false
        let metricLabels = [dashboardIncomeLabel, dashboardExpenseLabel, dashboardNetLabel]
        for (index, label) in metricLabels.enumerated() {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.alignment = .center
            label.widthAnchor.constraint(equalToConstant: 214).isActive = true
            label.heightAnchor.constraint(equalToConstant: 70).isActive = true
            statRow.addArrangedSubview(label)
            if index < metricLabels.count - 1 {
                let separator = CountPaperSurfaceView(fill: CountPaperTheme.border)
                separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 42).isActive = true
                statRow.addArrangedSubview(separator)
            }
        }
        summaryCard.addSubview(statRow)
        NSLayoutConstraint.activate([
            statRow.centerXAnchor.constraint(equalTo: summaryCard.centerXAnchor),
            statRow.centerYAnchor.constraint(equalTo: summaryCard.centerYAnchor)
        ])
        stack.addArrangedSubview(summaryCard)

        let entryCard = CountPaperSurfaceView(fill: CountPaperTheme.raisedSurface, stroke: CountPaperTheme.border, radius: 16, shadow: true)
        entryCard.widthAnchor.constraint(equalToConstant: 644).isActive = true
        let entry = NSStackView(); entry.orientation = .vertical; entry.alignment = .leading; entry.spacing = 9
        entry.edgeInsets = NSEdgeInsets(top: 15, left: 18, bottom: 15, right: 18); entry.translatesAutoresizingMaskIntoConstraints = false
        inlineEntryTitleLabel.stringValue = ui("记一笔", "New Entry")
        inlineEntryTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold); inlineEntryTitleLabel.textColor = CountPaperTheme.ink
        let entryHeader = NSStackView(); entryHeader.orientation = .horizontal; entryHeader.alignment = .centerY
        entryHeader.widthAnchor.constraint(equalToConstant: 608).isActive = true
        entryHeader.addArrangedSubview(inlineEntryTitleLabel); entryHeader.addArrangedSubview(NSView())
        inlineKindControl.selectedSegment = 0; inlineKindControl.selectedSegmentBezelColor = CountPaperTheme.blue; inlineKindControl.setAccessibilityLabel(ui("交易类型", "Transaction type")); inlineKindControl.widthAnchor.constraint(equalToConstant: 148).isActive = true
        entryHeader.addArrangedSubview(inlineKindControl); entry.addArrangedSubview(entryHeader)
        let firstRow = NSStackView(); firstRow.orientation = .horizontal; firstRow.spacing = 8
        inlineAmountField.placeholderString = ui("金额，如 32 57", "Amount, e.g. 32 57"); inlineAmountField.setAccessibilityLabel(ui("金额，可输入多个数字", "Amount; multiple values supported")); inlineAmountField.widthAnchor.constraint(equalToConstant: 148).isActive = true
        inlineSummaryField.placeholderString = ui("摘要（可选）", "Description (optional)"); inlineSummaryField.widthAnchor.constraint(equalToConstant: 200).isActive = true
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
        let accountRow = NSStackView(); accountRow.orientation = .horizontal; accountRow.alignment = .top; accountRow.spacing = 12
        func accountField(label: NSTextField, picker: NSPopUpButton) -> NSStackView {
            let group = NSStackView(); group.orientation = .vertical; group.alignment = .leading; group.spacing = 3
            label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = CountPaperTheme.secondaryInk
            picker.widthAnchor.constraint(equalToConstant: 298).isActive = true
            group.addArrangedSubview(label); group.addArrangedSubview(picker)
            return group
        }
        accountRow.addArrangedSubview(accountField(label: inlineDestinationLabel, picker: inlineDestinationPicker))
        accountRow.addArrangedSubview(accountField(label: inlineSourceLabel, picker: inlineSourcePicker))
        entry.addArrangedSubview(accountRow)
        let actionRow = NSStackView(); actionRow.orientation = .horizontal; actionRow.alignment = .centerY; actionRow.spacing = 8
        actionRow.widthAnchor.constraint(equalToConstant: 608).isActive = true
        inlineSuggestionPicker.widthAnchor.constraint(equalToConstant: 238).isActive = true; inlineSuggestionPicker.setAccessibilityLabel(ui("最近交易模板", "Recent transaction templates"))
        inlineCancelEditButton.title = ui("取消修改", "Cancel Edit"); inlineCancelEditButton.target = self; inlineCancelEditButton.action = #selector(cancelInlineTransactionEdit(_:)); inlineCancelEditButton.bezelStyle = .inline; inlineCancelEditButton.isHidden = true
        inlineSaveButton.title = ui("记入账本", "Record"); inlineSaveButton.target = self; inlineSaveButton.action = #selector(recordInlineTransaction(_:))
        stylePrimaryButton(inlineSaveButton)
        inlineSaveButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        inlineSaveButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        inlineSaveButton.keyEquivalent = "\r"
        actionRow.addArrangedSubview(inlineSuggestionPicker); actionRow.addArrangedSubview(NSView()); actionRow.addArrangedSubview(inlineCancelEditButton); actionRow.addArrangedSubview(inlineSaveButton); entry.addArrangedSubview(actionRow)
        entryCard.addSubview(entry)
        NSLayoutConstraint.activate([
            entry.leadingAnchor.constraint(equalTo: entryCard.leadingAnchor), entry.trailingAnchor.constraint(equalTo: entryCard.trailingAnchor),
            entry.topAnchor.constraint(equalTo: entryCard.topAnchor), entry.bottomAnchor.constraint(equalTo: entryCard.bottomAnchor)
        ])
        entryCard.heightAnchor.constraint(equalToConstant: 184).isActive = true
        stack.addArrangedSubview(entryCard)

        let recentTitle = NSTextField(labelWithString: ui("最近交易", "Recent Transactions"))
        recentTitle.font = .systemFont(ofSize: 15, weight: .semibold); recentTitle.textColor = CountPaperTheme.ink
        let recentHeader = NSStackView(); recentHeader.orientation = .horizontal; recentHeader.alignment = .centerY
        recentHeader.widthAnchor.constraint(equalToConstant: 644).isActive = true
        recentHeader.addArrangedSubview(recentTitle)
        dashboardMoreButton.title = ui("更多…", "More…"); dashboardMoreButton.target = self; dashboardMoreButton.action = #selector(showTransactionBrowser(_:)); styleDashboardActionButton(dashboardMoreButton, symbol: "list.bullet.rectangle", tint: CountPaperTheme.blue, filled: true); dashboardMoreButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        dashboardEditButton.title = ui("修改", "Edit"); dashboardEditButton.target = self; dashboardEditButton.action = #selector(editSelectedDashboardTransaction(_:)); styleDashboardActionButton(dashboardEditButton, symbol: "pencil", tint: CountPaperTheme.blue); dashboardEditButton.widthAnchor.constraint(equalToConstant: 62).isActive = true; dashboardEditButton.isEnabled = false
        dashboardDeleteButton.title = ui("删除", "Delete"); dashboardDeleteButton.target = self; dashboardDeleteButton.action = #selector(deleteSelectedDashboardTransaction(_:)); styleDashboardActionButton(dashboardDeleteButton, symbol: "trash", tint: CountPaperTheme.red); dashboardDeleteButton.widthAnchor.constraint(equalToConstant: 62).isActive = true; dashboardDeleteButton.isEnabled = false
        let openTextFile = NSButton(title: ui("编辑文本", "Edit Text"), target: self, action: #selector(openLedgerInTextEditor(_:)))
        styleDashboardActionButton(openTextFile, symbol: "doc.plaintext", tint: CountPaperTheme.secondaryInk)
        openTextFile.widthAnchor.constraint(equalToConstant: 84).isActive = true
        openTextFile.toolTip = ui("使用系统默认或“设置”中选择的 App 打开当前账本文件", "Open the current ledger in macOS's default app or the app selected in Settings")
        openTextFile.setAccessibilityLabel(ui("用外部 App 打开文本文件", "Open text file in external app"))
        recentHeader.addArrangedSubview(NSView())
        recentHeader.addArrangedSubview(dashboardMoreButton)
        recentHeader.addArrangedSubview(dashboardEditButton)
        recentHeader.addArrangedSubview(dashboardDeleteButton)
        recentHeader.addArrangedSubview(openTextFile)
        stack.addArrangedSubview(recentHeader)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 14; scroll.layer?.backgroundColor = CountPaperTheme.surface.cgColor; scroll.layer?.borderWidth = 0.6; scroll.layer?.borderColor = CountPaperTheme.border.cgColor
        scroll.widthAnchor.constraint(equalToConstant: 644).isActive = true
        dashboardRecentView.isEditable = false; dashboardRecentView.isSelectable = true
        dashboardRecentView.textColor = CountPaperTheme.ink; dashboardRecentView.backgroundColor = .clear
        dashboardRecentView.font = .systemFont(ofSize: 13, weight: .regular)
        dashboardRecentView.textContainerInset = NSSize(width: 16, height: 12)
        dashboardRecentView.selectedTextAttributes = [.backgroundColor: CountPaperTheme.blueSoft, .foregroundColor: CountPaperTheme.ink]
        dashboardRecentView.setAccessibilityLabel(ui("最近交易", "Recent transactions"))
        dashboardRecentView.onRowClick = { [weak self] row in self?.selectDashboardTransaction(at: row) }
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

        let root = CountPaperSurfaceView(fill: CountPaperTheme.canvas)
        let shell = NSStackView()
        shell.orientation = .horizontal
        shell.spacing = 0
        shell.translatesAutoresizingMaskIntoConstraints = false

        // A deliberate near-white surface reads as paper, rather than the
        // coloured system sidebar material that was tinting the whole app.
        let sidebar = CountPaperSurfaceView(fill: CountPaperTheme.softSurface, stroke: CountPaperTheme.border)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 184).isActive = true
        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 6
        sidebarStack.edgeInsets = NSEdgeInsets(top: 48, left: 12, bottom: 14, right: 12)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        let brand = NSTextField(labelWithString: "CountPaper")
        brand.font = .systemFont(ofSize: 20, weight: .semibold)
        brand.textColor = CountPaperTheme.ink
        sidebarStack.addArrangedSubview(brand)
        sidebarStack.setCustomSpacing(18, after: brand)
        sidebarButtons = [
            makeSidebarButton(title: ui("概览", "Overview"), symbol: "chart.bar.xaxis", tag: 0),
            makeSidebarButton(title: ui("日记账", "Journal"), symbol: "list.bullet", tag: 1),
            makeSidebarButton(title: ui("对账", "Reconcile"), symbol: "checkmark.rectangle.stack", tag: 2),
            makeSidebarButton(title: ui("账户", "Accounts"), symbol: "wallet.pass", tag: 3),
            makeSidebarButton(title: ui("报表", "Reports"), symbol: "chart.pie", tag: 4)
        ]
        sidebarButtons.forEach { button in
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 160).isActive = true
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
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 14)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = CountPaperTheme.canvas.cgColor
        documentNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        documentNameLabel.textColor = CountPaperTheme.ink
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
            let button = NSButton(title: "", target: self, action: action)
            button.isBordered = false; button.wantsLayer = true; button.layer?.cornerRadius = 6; button.layer?.backgroundColor = CountPaperTheme.softSurface.cgColor
            button.controlSize = .small
            let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)?.withSymbolConfiguration(symbolConfiguration)
            button.imagePosition = .imageOnly
            button.contentTintColor = CountPaperTheme.secondaryInk
            button.toolTip = name
            button.setAccessibilityLabel(name)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            bar.addArrangedSubview(button)
        }
        let recordButton = NSButton(title: ui("记一笔", "Record"), target: self, action: #selector(recordTransaction(_:)))
        stylePrimaryButton(recordButton)
        recordButton.controlSize = .small
        recordButton.font = .systemFont(ofSize: 11.5, weight: .semibold)
        recordButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        recordButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        recordButton.keyEquivalent = "e"
        recordButton.keyEquivalentModifierMask = [.command]
        let recordSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        recordButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: recordButton.title)?.withSymbolConfiguration(recordSymbolConfiguration)
        recordButton.imagePosition = .imageLeading
        recordButton.imageHugsTitle = true
        setPrimaryButtonTitle(recordButton, recordButton.title)
        recordButton.setAccessibilityLabel(ui("记一笔交易", "Record a transaction"))
        bar.addArrangedSubview(recordButton)
        workspace.addArrangedSubview(bar)

        let tabBar = NSStackView()
        tabBar.orientation = .horizontal
        tabBar.alignment = .centerY
        tabBar.spacing = 6
        tabBar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 5, right: 12)
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = CountPaperTheme.canvas.cgColor
        ledgerTabControl.trackingMode = .selectOne
        ledgerTabControl.segmentStyle = .capsule
        ledgerTabControl.selectedSegmentBezelColor = CountPaperTheme.blue
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

        let body = CountPaperSurfaceView(fill: CountPaperTheme.canvas)
        // One explicit content host is more reliable than a horizontal stack
        // when whole pages are swapped in and out of view.
        let contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        let dashboard = buildDashboard()
        dashboardContainer = dashboard
        dashboard.translatesAutoresizingMaskIntoConstraints = false
        let reportContainer = CountPaperSurfaceView(fill: CountPaperTheme.surface, stroke: CountPaperTheme.border, radius: 16)
        inspectorContainer = reportContainer
        reportContainer.translatesAutoresizingMaskIntoConstraints = false
        let reportStack = NSStackView(frame: reportContainer.bounds)
        reportStack.orientation = .vertical
        reportStack.alignment = .leading
        reportStack.spacing = 0
        reportStack.autoresizingMask = [.width, .height]
        let inspectorHeader = NSStackView()
        inspectorHeader.orientation = .vertical
        inspectorHeader.alignment = .leading
        inspectorHeader.spacing = 10
        inspectorHeader.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 14, right: 20)
        inspectorHeader.wantsLayer = true
        inspectorHeader.layer?.backgroundColor = CountPaperTheme.surface.cgColor
        inspectorTitleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        inspectorTitleLabel.textColor = CountPaperTheme.ink
        inspectorTitleLabel.alignment = .left
        inspectorTitleLabel.stringValue = ui("概览", "Overview")
        inspectorHeader.addArrangedSubview(inspectorTitleLabel)
        let journalFilters = NSStackView()
        journalFilters.orientation = .horizontal
        journalFilters.alignment = .centerY
        journalFilters.spacing = 8
        journalFilters.isHidden = true
        journalSearchField.widthAnchor.constraint(equalToConstant: 330).isActive = true
        journalFilters.addArrangedSubview(journalSearchField)
        journalFilters.addArrangedSubview(journalSearchScope)
        journalFilters.addArrangedSubview(journalStatusFilter)
        journalFilters.addArrangedSubview(NSView())
        inspectorHeader.addArrangedSubview(journalFilters)
        journalFilterContainer = journalFilters
        let reconciliationControls = NSStackView()
        reconciliationControls.orientation = .horizontal
        reconciliationControls.alignment = .centerY
        reconciliationControls.spacing = 8
        reconciliationControls.isHidden = true
        reconciliationOrderControl.setLabel(ui("最新在前", "Newest First"), forSegment: 0)
        reconciliationOrderControl.setLabel(ui("最早在前", "Oldest First"), forSegment: 1)
        reconciliationOrderControl.selectedSegment = 0
        reconciliationOrderControl.target = self
        reconciliationOrderControl.action = #selector(changeReconciliationOrder(_:))
        reconciliationOrderControl.selectedSegmentBezelColor = CountPaperTheme.blue
        reconciliationOrderControl.setAccessibilityLabel(ui("对账排序", "Reconciliation order"))
        reconciliationControls.addArrangedSubview(reconciliationOrderControl)
        reconciliationControls.addArrangedSubview(NSView())
        inspectorHeader.addArrangedSubview(reconciliationControls)
        reconciliationOrderContainer = reconciliationControls
        let reportFilters = NSStackView()
        reportFilters.orientation = .horizontal
        reportFilters.alignment = .centerY
        reportFilters.spacing = 8
        reportFilters.isHidden = true
        reportLedgerScopePicker.addItems(withTitles: [ui("当前账本", "Current Ledger"), ui("所有打开账本", "All Open Ledgers")])
        reportLedgerScopePicker.target = self; reportLedgerScopePicker.action = #selector(changeReportLedgerScope(_:))
        reportLedgerScopePicker.setAccessibilityLabel(ui("报表账本范围", "Report ledger scope"))
        reportLedgerScopePicker.widthAnchor.constraint(equalToConstant: 120).isActive = true
        periodPicker.target = self; periodPicker.action = #selector(changeReportPeriod(_:))
        periodPicker.setAccessibilityLabel(ui("报表时间", "Report period")); periodPicker.widthAnchor.constraint(equalToConstant: 130).isActive = true
        reportKindControl.target = self; reportKindControl.action = #selector(changeReportKind(_:))
        reportKindControl.selectedSegment = 0; reportKindControl.setAccessibilityLabel(ui("报表类型", "Report kind"))
        reportKindControl.selectedSegmentBezelColor = CountPaperTheme.blue
        reportKindControl.widthAnchor.constraint(equalToConstant: 156).isActive = true
        reportTagPicker.target = self; reportTagPicker.action = #selector(changeReportTag(_:))
        reportTagPicker.setAccessibilityLabel(ui("报表标签筛选", "Report tag filter")); reportTagPicker.widthAnchor.constraint(equalToConstant: 138).isActive = true
        reportAccountPicker.target = self; reportAccountPicker.action = #selector(changeReportAccount(_:))
        reportAccountPicker.setAccessibilityLabel(ui("报表账户筛选", "Report account filter")); reportAccountPicker.widthAnchor.constraint(equalToConstant: 176).isActive = true
        reportFilters.addArrangedSubview(reportLedgerScopePicker); reportFilters.addArrangedSubview(periodPicker); reportFilters.addArrangedSubview(reportKindControl); reportFilters.addArrangedSubview(reportTagPicker); reportFilters.addArrangedSubview(reportAccountPicker); reportFilters.addArrangedSubview(NSView())
        inspectorHeader.addArrangedSubview(reportFilters)
        reportFilterContainer = reportFilters
        let accountActions = NSStackView()
        accountActions.orientation = .horizontal
        accountActions.alignment = .centerY
        accountActions.spacing = 8
        accountActions.isHidden = true
        for (title, action, symbol) in [
            (ui("添加账户", "Add Account"), #selector(addAccount(_:)), "plus"),
            (ui("修改", "Edit"), #selector(editAccount(_:)), "pencil"),
            (ui("删除", "Delete"), #selector(deleteAccount(_:)), "trash")
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageLeading
            button.controlSize = .small
            accountActions.addArrangedSubview(button)
        }
        accountActions.addArrangedSubview(NSView())
        inspectorHeader.addArrangedSubview(accountActions)
        accountActionContainer = accountActions
        reportStack.addArrangedSubview(inspectorHeader)
        reportChartView.translatesAutoresizingMaskIntoConstraints = false
        reportChartView.heightAnchor.constraint(equalToConstant: 224).isActive = true
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
        reportView.textContainerInset = NSSize(width: 18, height: 16)
        reportView.textColor = CountPaperTheme.ink
        reportView.backgroundColor = CountPaperTheme.surface
        reportView.isSelectable = true
        reportView.selectedTextAttributes = [.backgroundColor: CountPaperTheme.blue, .foregroundColor: NSColor.white]
        reportView.setAccessibilityLabel("账本概览")
        reportView.onReportClick = { [weak self] offset in self?.handleReportClick(at: offset) }
        reportView.isEditable = false; reportView.delegate = self; reportView.font = .systemFont(ofSize: 14, weight: .regular); reportScrollView.documentView = reportView; reportStack.addArrangedSubview(reportScrollView); reportContainer.addSubview(reportStack)
        NSLayoutConstraint.activate([
            inspectorHeader.widthAnchor.constraint(equalTo: reportContainer.widthAnchor),
            inspectorTitleLabel.widthAnchor.constraint(equalTo: reportContainer.widthAnchor, constant: -40),
            journalFilters.widthAnchor.constraint(equalTo: reportContainer.widthAnchor, constant: -40),
            reconciliationControls.widthAnchor.constraint(equalTo: reportContainer.widthAnchor, constant: -40),
            reportFilters.widthAnchor.constraint(equalTo: reportContainer.widthAnchor, constant: -40),
            accountActions.widthAnchor.constraint(equalTo: reportContainer.widthAnchor, constant: -40),
            reportChartView.widthAnchor.constraint(equalTo: reportContainer.widthAnchor),
            reportScrollView.widthAnchor.constraint(equalTo: reportContainer.widthAnchor)
        ])
        contentHost.addSubview(dashboard)
        contentHost.addSubview(reportContainer)
        body.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 18),
            contentHost.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -18),
            contentHost.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            contentHost.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -18),
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
            bar.heightAnchor.constraint(equalToConstant: 46),
            tabBar.heightAnchor.constraint(equalToConstant: 38)
        ])
        workspace.addArrangedSubview(statusBar)
        shell.addArrangedSubview(workspace)
        // NSStackView otherwise prefers the inspector's intrinsic width on
        // first launch. Pin the flexible workspace to the shell explicitly so
        // every page uses the window's full remaining width.
        workspace.widthAnchor.constraint(equalTo: shell.widthAnchor, constant: -184).isActive = true
        root.addSubview(shell); window.contentView = root
        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: root.leadingAnchor), shell.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shell.topAnchor.constraint(equalTo: root.topAnchor), shell.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func makeSidebarButton(title: String, symbol: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(changeSidebarMode(_:)))
        button.tag = tag
        button.identifier = NSUserInterfaceItemIdentifier(symbol)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13.5, weight: .medium)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(configuration)
        // Sidebar glyphs must remain one-color symbols. Palette rendering made
        // chart.bar.xaxis look selected even when another row was active.
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.setAccessibilityLabel(title)
        return button
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = CountPaperTheme.blue.cgColor
        button.layer?.cornerRadius = 7
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        setPrimaryButtonTitle(button, button.title)
    }

    private func styleDashboardActionButton(_ button: NSButton, symbol: String, tint: NSColor, filled: Bool = false) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = filled ? CountPaperTheme.blueSoft.cgColor : NSColor.clear.cgColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)
        button.imagePosition = .imageLeading
        button.contentTintColor = tint
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: button.font as Any, .foregroundColor: tint])
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func setPrimaryButtonTitle(_ button: NSButton, _ title: String) {
        button.title = title
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: button.font as Any,
            .foregroundColor: NSColor.white
        ])
    }

    private func updateSidebarSelection() {
        for button in sidebarButtons {
            let selected = button.tag == sidebarModeIndex
            // Recreate the template symbol during every selection update so no
            // palette or cached selected-state layer can leak into another row.
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let icon = NSImage(systemSymbolName: button.identifier?.rawValue ?? "circle", accessibilityDescription: button.title)?.withSymbolConfiguration(configuration)
            icon?.isTemplate = true
            button.image = icon
            button.layer?.backgroundColor = selected ? CountPaperTheme.blueSoft.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? CountPaperTheme.blue : CountPaperTheme.secondaryInk
            button.font = .systemFont(ofSize: 13.5, weight: selected ? .semibold : .medium)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: button.font as Any,
                .foregroundColor: selected ? CountPaperTheme.blue : CountPaperTheme.ink,
                .paragraphStyle: paragraph
            ])
        }
    }

    private var sidebarModeIndex: Int {
        switch sidePanelMode {
        case .overview: return 0
        case .journal: return 1
        case .reconciliation: return 2
        case .accounts: return 3
        case .reports: return 4
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
        if sender.tag == 4 {
            sidePanelMode = .reports
            apply(report: latestReport)
            updateSidebarSelection()
            return
        }
        sidePanelMode = switch sender.tag {
        case 1: .journal
        case 2: .reconciliation
        case 3: .accounts
        default: .overview
        }
        updateSidebarSelection()
        apply(report: latestReport)
    }

    @objc private func changeSidePanel(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 4 {
            sidePanelMode = .reports
            apply(report: latestReport)
            updateSidebarSelection()
            return
        }
        sidePanelMode = switch sender.selectedSegment {
        case 1: .journal
        case 2: .reconciliation
        case 3: .accounts
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

    @objc private func changeReconciliationOrder(_ sender: NSSegmentedControl) {
        reconciliationNewestFirst = sender.selectedSegment == 0
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
        alert.informativeText = ui("在同一日历上切换“起始”和“结束”后选日期。", "Switch between Start and End, then choose both dates on the same calendar.")
        let content = NSStackView(frame: NSRect(x: 0, y: 0, width: 250, height: 245))
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 8
        let initialStart = selectedReportStartDate.flatMap(formatter.date(from:)) ?? dates.first.flatMap(formatter.date(from:)) ?? Date()
        let initialEnd = selectedReportEndDate.flatMap(formatter.date(from:)) ?? dates.last.flatMap(formatter.date(from:)) ?? Date()
        let mode = NSSegmentedControl(labels: [ui("起始", "Start"), ui("结束", "End")], trackingMode: .selectOne, target: nil, action: nil)
        mode.selectedSegment = 0; mode.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let labels = NSStackView(); labels.orientation = .horizontal; labels.distribution = .fillEqually; labels.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let startLabel = NSTextField(labelWithString: ""); startLabel.alignment = .center; startLabel.textColor = CountPaperTheme.blue
        let endLabel = NSTextField(labelWithString: ""); endLabel.alignment = .center; endLabel.textColor = CountPaperTheme.secondaryInk
        labels.addArrangedSubview(startLabel); labels.addArrangedSubview(endLabel)
        let calendar = NSDatePicker(); calendar.datePickerStyle = .clockAndCalendar; calendar.datePickerElements = .yearMonthDay; calendar.dateValue = initialStart
        calendar.widthAnchor.constraint(equalToConstant: 220).isActive = true; calendar.heightAnchor.constraint(equalToConstant: 170).isActive = true
        let binder = DateRangeSelectionBinder(picker: calendar, mode: mode, startLabel: startLabel, endLabel: endLabel, startDate: initialStart, endDate: initialEnd, formatter: formatter)
        mode.target = binder; mode.action = #selector(DateRangeSelectionBinder.changeMode(_:))
        calendar.target = binder; calendar.action = #selector(DateRangeSelectionBinder.chooseDate(_:))
        content.addArrangedSubview(mode); content.addArrangedSubview(labels); content.addArrangedSubview(calendar)
        alert.accessoryView = content
        alert.addButton(withTitle: ui("应用", "Apply"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            updatePeriodPicker(for: latestReport)
            return
        }
        let startDate = formatter.string(from: binder.startDate)
        let endDate = formatter.string(from: binder.endDate)
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
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 242))
        let heading = NSTextField(labelWithString: ui("录入与校验", "Entry & validation"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 0, y: 216, width: 500, height: 20)
        let multiple = NSButton(checkboxWithTitle: ui("一栏录入多个金额", "Enter multiple amounts in one field"), target: nil, action: nil)
        multiple.state = allowsMultipleAmounts ? .on : .off
        multiple.frame = NSRect(x: 0, y: 182, width: 500, height: 24)
        let multipleHint = NSTextField(labelWithString: ui("例如输入 32 57，会生成两笔同类交易。", "For example, 32 57 creates two transactions of the same kind."))
        multipleHint.textColor = .secondaryLabelColor
        multipleHint.font = .systemFont(ofSize: 11)
        multipleHint.frame = NSRect(x: 24, y: 160, width: 470, height: 18)
        let balanceCheck = NSButton(checkboxWithTitle: ui("打开账本时检查交易是否平衡", "Check transaction balance when opening a ledger"), target: nil, action: nil)
        balanceCheck.state = checksBalanceOnOpen ? .on : .off
        balanceCheck.frame = NSRect(x: 0, y: 126, width: 500, height: 24)
        let balanceHint = NSTextField(labelWithString: ui("发现问题时提示交易日期、摘要、差额和所在位置；不会自动修改文件。", "Shows the date, description, difference, and location without changing the file."))
        balanceHint.textColor = .secondaryLabelColor
        balanceHint.font = .systemFont(ofSize: 11)
        balanceHint.frame = NSRect(x: 24, y: 104, width: 470, height: 18)
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
        [heading, multiple, multipleHint, balanceCheck, balanceHint, languageLabel, language, editorLabel, editorName, chooseEditor, resetEditor].forEach(form.addSubview)
        let alert = NSAlert()
        alert.messageText = ui("设置", "Settings")
        alert.informativeText = ui("常用设置集中于此；原始文本不会被应用自动改写。", "Common settings live here; the app never automatically rewrites your source text.")
        alert.accessoryView = form
        alert.addButton(withTitle: ui("完成", "Done"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let oldLanguage = appLanguage
        UserDefaults.standard.set(multiple.state == .on, forKey: CountPaperPreference.multipleAmounts)
        UserDefaults.standard.set(balanceCheck.state == .on, forKey: CountPaperPreference.checkBalanceOnOpen)
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
            CommandPaletteItem(title: "调整账户余额", detail: "输入实际余额，自动记录初始余额或调整额", action: { [weak self] in self?.adjustAccountBalance(nil) }),
            CommandPaletteItem(title: "添加账户备注", detail: "记录账户用途、结算日等不影响余额的信息", action: { [weak self] in self?.addAccountNote(nil) }),
            CommandPaletteItem(title: "设置预算", detail: "添加当前月份的费用预算", action: { [weak self] in self?.addBudget(nil) }),
            CommandPaletteItem(title: "添加事件", detail: "记录换工作、搬家等不影响余额的账本事件", action: { [weak self] in self?.addEvent(nil) }),
            CommandPaletteItem(title: "编辑当前交易", detail: "用表单更新光标所在的标准交易", action: { [weak self] in self?.editTransactionAtCursor(nil) }),
            CommandPaletteItem(title: "打开当前交易链接", detail: "在默认浏览器中打开该交易关联的网页", action: { [weak self] in self?.openTransactionLinkAtCursor(nil) }),
            CommandPaletteItem(title: "跳转到行", detail: "快速定位账本文本中的行号", action: { [weak self] in self?.goToLine(nil) }),
            CommandPaletteItem(title: "跳到下一个错误", detail: "定位下一条格式诊断", action: { [weak self] in self?.jumpToNextDiagnostic(nil) }),
            CommandPaletteItem(title: "重新校验", detail: "立即重新解析当前账本", action: { [weak self] in self?.reparseNow() }),
            CommandPaletteItem(title: "保存文稿", detail: "保存到当前文件或选择保存位置", action: { [weak self] in self?.saveDocument(nil) }),
            CommandPaletteItem(title: "打开文稿", detail: "打开本地 .countpaper 账本文件", action: { [weak self] in self?.openDocument(nil) })
        ]
        CommandPaletteController(items: commands).show()
    }

    private func loadUntitledSample() {
        ledgerSessions = [LedgerSession(url: nil, text: starterTemplate(for: appLanguage))]
        activeLedgerIndex = 0
        restoreActiveLedgerSession()
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [countPaperContentType]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDocument(at: url)
    }

    private func loadDocument(at url: URL) {
        if let existing = ledgerSessions.firstIndex(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
            switchToLedgerSession(at: existing)
            checkBalanceAfterOpening(text: textView.string, fileName: url.lastPathComponent)
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if shouldReplacePlaceholderLedger(ledgerSessions) {
                autosaveWorkItem?.cancel()
                ledgerSessions.removeAll()
            } else {
                persistActiveLedgerSession()
            }
            ledgerSessions.append(LedgerSession(url: url, text: text, signature: fileSignature(for: url)))
            activeLedgerIndex = ledgerSessions.count - 1
            rememberRecentDocument(url)
            restoreActiveLedgerSession()
            checkBalanceAfterOpening(text: text, fileName: url.lastPathComponent)
        }
        catch { presentError("无法打开文件：\(error.localizedDescription)") }
    }

    private func checkBalanceAfterOpening(text: String, fileName: String) {
        guard checksBalanceOnOpen else { return }
        let issues = LedgerParser.parse(text).balanceIssues
        guard !issues.isEmpty else { return }
        let shown = issues.prefix(8).map { issue -> String in
            let date = issue.date.isEmpty ? ui("日期未知", "Unknown date") : issue.date
            let summary = issue.summary.isEmpty ? ui("未命名交易", "Untitled transaction") : issue.summary
            return ui("• \(date)「\(summary)」— 第 \(issue.line) 行，差额 \(LedgerParser.format(issue.difference))", "• \(date) “\(summary)” — line \(issue.line), difference \(LedgerParser.format(issue.difference))")
        }.joined(separator: "\n")
        let remainder = issues.count > 8 ? ui("\n另有 \(issues.count - 8) 处未列出。", "\n\(issues.count - 8) more issue(s) not shown.") : ""
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ui("发现 \(issues.count) 笔不平衡交易", "\(issues.count) unbalanced transaction(s) found")
        alert.informativeText = ui("“\(fileName)”中的这些交易不会计入余额和报表。文件未被修改。\n\n\(shown)\(remainder)", "These transactions in “\(fileName)” are excluded from balances and reports. The file was not changed.\n\n\(shown)\(remainder)")
        alert.addButton(withTitle: ui("查看第一处", "Show First"))
        alert.addButton(withTitle: ui("稍后处理", "Later"))
        guard alert.runModal() == .alertFirstButtonReturn, let first = issues.first,
              let range = ledgerLineRange(in: textView.string, line: first.line) else { return }
        showSourceEditor(nil)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        statusLabel.stringValue = ui("已定位到不平衡交易", "Located the unbalanced transaction")
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
            let empty = NSMenuItem(title: ui("没有最近文稿", "No Recent Documents"), action: nil, keyEquivalent: "")
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
        guard let transaction = transactionAtCursor(in: raw),
              let components = editableComponents(for: transaction),
              let range = ledgerSourceRange(in: raw, fromLine: transaction.startLine, throughLine: transaction.endLine) else {
            presentError(ui("这笔交易无法使用表单修改，请改用“查看原始文本”。", "This transaction cannot be edited with the form. Use View Source Text instead."))
            return
        }
        let original = (raw as NSString).substring(with: range)
        guard canonicalOutlineTransactionBlock(source: original, summary: transaction.summary, flag: transaction.flag, time: transaction.time, payee: transaction.payee, tags: transaction.tags, links: transaction.links, destination: components.destination.account, sourceAccount: components.source.account, amount: components.destination.amount) != nil else {
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
        let destination = NSPopUpButton(frame: .zero, pullsDown: false); destination.addItems(withTitles: latestReport.accounts); destination.selectItem(withTitle: components.destination.account)
        let source = NSPopUpButton(frame: .zero, pullsDown: false); source.addItems(withTitles: latestReport.accounts); source.selectItem(withTitle: components.source.account)
        let amount = NSTextField(string: LedgerParser.format(components.destination.amount))
        let accountLabels: (String, String) = switch components.kind {
        case .expense: (ui("费用分类", "Category"), ui("付款账户", "Paid from"))
        case .income: (ui("收款账户", "Received in"), ui("收入分类", "Income category"))
        case .transfer: (ui("转入账户", "Transfer to"), ui("转出账户", "Transfer from"))
        }
        let fields: [(String, NSView)] = [(ui("日期", "Date"), date), (ui("摘要", "Description"), summary), (ui("收款方", "Payee"), payee), (ui("标签", "Tags"), tags), (ui("链接", "Links"), links), (accountLabels.0, destination), (accountLabels.1, source), (ui("金额", "Amount"), amount)]
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
                alert.informativeText = components.kind == .transfer ? ui("转入和转出账户不能相同。", "Transfer accounts must differ.") : ui("分类与收付款账户不能相同。", "The category and payment account must differ.")
                continue
            }
            guard let replacement = canonicalOutlineTransactionBlock(source: original, summary: cleanedSummary, flag: transaction.flag, time: transaction.time, payee: cleanedPayee.isEmpty ? nil : cleanedPayee, tags: cleanedTags, links: cleanedLinks, destination: destination.titleOfSelectedItem!, sourceAccount: source.titleOfSelectedItem!, amount: value) else { return }
            let newDate = dateFormatter.string(from: date.dateValue)
            let updated = NSMutableString(string: raw)
            updated.replaceCharacters(in: range, with: newDate == transaction.date ? replacement : "")
            if newDate != transaction.date {
                let organizedBase = consolidatedLedgerDateSections(updated as String).text
                updated.setString(organizedBase)
                let insertion = ledgerTransactionInsertion(in: organizedBase, date: newDate, transactionBlocks: [replacement.trimmingCharacters(in: .newlines)])
                updated.insert(insertion.text, at: insertion.location)
            }
            textView.string = consolidatedLedgerDateSections(updated as String).text
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
        let updated = NSMutableString(string: raw)
        updated.replaceCharacters(in: range, with: "")
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: consolidatedLedgerDateSections(updated as String).text)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    @objc private func consolidateDateHeadings(_ sender: Any?) {
        let raw = textView.string
        let result = consolidatedLedgerDateSections(raw)
        guard result.text != raw else {
            statusLabel.stringValue = ui("日期结构已经整齐", "Date sections are already organized")
            return
        }
        let alert = NSAlert()
        alert.messageText = ui("合并重复日期标题？", "Merge Duplicate Date Headings?")
        alert.informativeText = ui("将把同一天的完整交易块移动到一个 # 日期标题下，并移除空日期标题。交易内容不会改变。", "Complete transaction blocks for the same day will move under one # date heading, and empty date headings will be removed. Transaction contents will not change.")
        alert.addButton(withTitle: ui("合并", "Merge"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: result.text)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
        statusLabel.stringValue = ui("已合并 \(result.mergedHeadings) 个重复日期标题", "Merged \(result.mergedHeadings) duplicate date headings")
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

    @objc private func adjustAccountBalance(_ sender: Any?) {
        let accounts = latestReport.accounts.filter { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
        guard !accounts.isEmpty else {
            presentError(ui("请先添加至少一个资产或负债账户。", "Add at least one asset or liability account first."))
            return
        }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 124))
        let date = NSDatePicker(); date.datePickerStyle = .clockAndCalendar; date.datePickerElements = .yearMonthDay; date.dateValue = Date()
        let account = NSPopUpButton(frame: .zero, pullsDown: false); account.addItems(withTitles: accounts)
        let balance = NSTextField(string: ""); balance.placeholderString = ui("例如 1,250.00", "e.g. 1,250.00")
        let note = NSTextField(string: ""); note.placeholderString = ui("可选，例如：开户时余额", "Optional, e.g. opening balance")
        let accountLabel = NSTextField(labelWithString: "")
        accountLabel.textColor = .secondaryLabelColor; accountLabel.font = .systemFont(ofSize: 11)
        let updateLabel = AccountBalanceLabelBinder(picker: account, label: accountLabel, report: latestReport, english: appLanguage == .english)
        account.target = updateLabel; account.action = #selector(AccountBalanceLabelBinder.update(_:)); updateLabel.update(nil)
        let rows: [(String, NSView)] = [
            (ui("日期", "Date"), date), (ui("账户", "Account"), account),
            (ui("实际余额", "Actual balance"), balance), (ui("备注", "Note"), note)
        ]
        for (index, pair) in rows.enumerated() {
            let y = CGFloat(94 - index * 28)
            let label = NSTextField(labelWithString: pair.0); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 90, height: 24)
            pair.1.frame = NSRect(x: 102, y: y, width: 278, height: 24)
            form.addSubview(label); form.addSubview(pair.1)
        }
        accountLabel.frame = NSRect(x: 102, y: 70, width: 278, height: 16)
        form.addSubview(accountLabel)
        let alert = NSAlert()
        alert.messageText = ui("调整账户余额", "Adjust Account Balance")
        alert.informativeText = ui("输入实际余额。若账面余额为 0，将记录为初始余额；否则会新增一笔余额调整。原有交易不会被改动。", "Enter the actual balance. A zero ledger balance becomes an opening balance; otherwise a balance adjustment is added. Existing transactions are never changed.")
        alert.accessoryView = form
        alert.addButton(withTitle: ui("确认调整", "Adjust"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let target = Decimal(string: balance.stringValue.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")), target >= .zero else {
                alert.informativeText = ui("实际余额必须是大于或等于 0 的数字。", "Actual balance must be a number greater than or equal to zero.")
                continue
            }
            let selected = account.titleOfSelectedItem!
            let current = displayBalance(latestReport.balances[selected, default: .zero], account: selected)
            let difference = target - current
            guard difference != .zero else {
                alert.informativeText = ui("实际余额与当前账面余额相同，无需调整。", "The actual balance already matches the ledger balance.")
                continue
            }
            let cleanedNote = note.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedNote.contains("\n") else {
                alert.informativeText = ui("备注不能包含换行。", "The note cannot contain line breaks.")
                continue
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
            insertBalanceAdjustment(date: formatter.string(from: date.dateValue), account: selected, targetBalance: target, currentBalance: current, note: cleanedNote)
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

    @objc private func editAccount(_ sender: Any?) {
        let accounts = latestReport.accounts.filter { !isInternalBalanceAdjustmentAccount($0) }
        guard !accounts.isEmpty else { presentError(ui("请先添加账户。", "Add an account first.")); return }
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 60))
        let account = NSPopUpButton(frame: NSRect(x: 110, y: 34, width: 264, height: 24), pullsDown: false); account.addItems(withTitles: accounts)
        let newName = NSTextField(frame: NSRect(x: 110, y: 2, width: 264, height: 24)); newName.placeholderString = ui("只输入冒号后的名称", "Enter the name after the colon")
        for (title, y) in [(ui("原账户", "Account"), CGFloat(34)), (ui("新名称", "New name"), CGFloat(2))] {
            let label = NSTextField(labelWithString: title); label.alignment = .right; label.frame = NSRect(x: 0, y: y, width: 98, height: 24); form.addSubview(label)
        }
        form.addSubview(account); form.addSubview(newName)
        let alert = NSAlert(); alert.messageText = ui("修改账户", "Edit Account")
        alert.informativeText = ui("将同步更新账户声明和交易中的账户名称。", "The account declaration and its transaction postings will be renamed together.")
        alert.accessoryView = form; alert.addButton(withTitle: ui("修改", "Save")); alert.addButton(withTitle: ui("取消", "Cancel"))
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let old = account.titleOfSelectedItem!
            let cleaned = newName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !cleaned.contains(":"), !cleaned.contains(";"), !cleaned.contains("#"), !cleaned.contains(where: { $0.isWhitespace }) else {
                alert.informativeText = ui("账户名称不能为空，且不能含空白、冒号、分号或 #。", "The name cannot be empty or contain whitespace, :, ;, or #."); continue
            }
            let root = old.split(separator: ":").first.map(String.init) ?? ""
            let replacement = "\(root):\(cleaned)"
            guard replacement != old else { return }
            guard !latestReport.accounts.contains(replacement) else { alert.informativeText = ui("该账户名称已存在。", "That account already exists."); continue }
            replaceAccount(old, with: replacement)
            return
        }
    }

    @objc private func deleteAccount(_ sender: Any?) {
        let accounts = latestReport.accounts.filter { !isInternalBalanceAdjustmentAccount($0) }
        guard !accounts.isEmpty else { presentError(ui("没有可删除的账户。", "There is no account to delete.")); return }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false); picker.addItems(withTitles: accounts)
        let alert = NSAlert(); alert.messageText = ui("删除账户", "Delete Account")
        alert.informativeText = ui("只能删除从未用于交易的账户。", "Only accounts that have never been used by a transaction can be deleted.")
        alert.accessoryView = picker; alert.addButton(withTitle: ui("删除", "Delete")); alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, let selected = picker.titleOfSelectedItem else { return }
        guard !latestReport.journal.contains(where: { $0.postings.contains(where: { $0.account == selected }) }) else {
            presentError(ui("此账户已用于交易，为保护历史记录不能删除。可改名，或保留不用。", "This account is used by transactions and cannot be deleted. Rename it or leave it unused.")); return
        }
        removeAccountDeclaration(selected)
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
            if trimmed == "@账户" || trimmed == "@accounts" { inAccountSection = true }
            else if line.hasPrefix("# ") { inAccountSection = false }
            if inAccountSection, line.hasPrefix("- ") { lastAccountEnd = lineEnd }
            offset = lineEnd
        }
        guard let insertionOffset = lastAccountEnd else {
            presentError(ui("未找到账户区；请先修正文件头后再添加账户。", "Could not find the account section. Fix the file header before adding an account."))
            return
        }
        let text = "- \(account)\(newline)"
        textView.textStorage?.replaceCharacters(in: NSRange(location: insertionOffset, length: 0), with: text)
        textView.didChangeText()
        isDirty = true
        scheduleParse(immediately: true)
        scheduleAutosave()
    }

    private func replaceAccount(_ old: String, with replacement: String) {
        let newline = textView.string.contains("\r\n") ? "\r\n" : "\n"
        let updated = textView.string.components(separatedBy: newline).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "- \(old)" { return line.replacingOccurrences(of: old, with: replacement) }
            if line.hasPrefix("  - \(old) ") || line.hasPrefix("\t- \(old) ") { return line.replacingOccurrences(of: old, with: replacement) }
            return line
        }.joined(separator: newline)
        textView.string = updated; textView.didChangeText(); isDirty = true; scheduleParse(immediately: true); scheduleAutosave()
        statusLabel.stringValue = ui("账户已修改", "Account updated")
    }

    private func removeAccountDeclaration(_ account: String) {
        let newline = textView.string.contains("\r\n") ? "\r\n" : "\n"
        let updated = textView.string.components(separatedBy: newline).filter { $0.trimmingCharacters(in: .whitespaces) != "- \(account)" }.joined(separator: newline)
        textView.string = updated; textView.didChangeText(); isDirty = true; scheduleParse(immediately: true); scheduleAutosave()
        statusLabel.stringValue = ui("账户已删除", "Account deleted")
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

    private func insertBalanceAdjustment(date: String, account: String, targetBalance: Decimal, currentBalance: Decimal, note: String) {
        let displayedDifference = targetBalance - currentBalance
        let rawDifference = isLedgerAccount(account, .liability) ? -displayedDifference : displayedDifference
        let counterpart = balanceAdjustmentCounterpart(for: account)
        guard let withCounterpart = ledgerSourceAddingAccountDeclaration(textView.string, account: counterpart) else {
            presentError(ui("未找到账户区，无法记录余额调整。", "The account section could not be found, so the balance adjustment could not be recorded.")); return
        }
        let baseTitle = currentBalance == .zero ? ui("初始余额", "Opening balance") : ui("余额调整", "Balance adjustment")
        let summary: String
        if note.isEmpty { summary = baseTitle }
        else { summary = appLanguage == .english ? "\(baseTitle) — \(note)" : "\(baseTitle)：\(note)" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"
        let timeKey = appLanguage == .english ? "time:" : "时间:"
        let block = "- \(summary)\n  - \(timeKey) \(formatter.string(from: Date()))\n  - \(account)  \(LedgerParser.format(rawDifference))\n  - \(counterpart)  \(LedgerParser.format(-rawDifference))"
        let consolidated = consolidatedLedgerDateSections(withCounterpart).text
        let insertion = ledgerTransactionInsertion(in: consolidated, date: date, transactionBlocks: [block])
        let updated = NSMutableString(string: consolidated); updated.insert(insertion.text, at: insertion.location)
        textView.string = updated as String; textView.didChangeText(); isDirty = true; scheduleParse(immediately: true); scheduleAutosave()
        statusLabel.stringValue = currentBalance == .zero ? ui("已设置初始余额", "Opening balance set") : ui("余额已调整", "Balance adjusted")
    }

    private func insertTransactions(date: String, summary: String, payee: String, tags: String, links: String, destination: String, source: String, amounts: [Decimal]) {
        let normalizedTags = transactionMetadata(fromComment: "标签: \(tags)").tags
        let normalizedLinks = normalizedTransactionLinks(links) ?? []
        let timeFormatter = DateFormatter(); timeFormatter.locale = Locale(identifier: "en_US_POSIX"); timeFormatter.dateFormat = "HH:mm"
        let timeLine = "\n  - \(appLanguage == .english ? "time:" : "时间:") \(timeFormatter.string(from: Date()))"
        let payeeLine = payee.isEmpty ? "" : "\n  - 收款方: \(payee)"
        let tagsLine = normalizedTags.isEmpty ? "" : "\n  - 标签: \(normalizedTags.joined(separator: ", "))"
        let linkLine = normalizedLinks.isEmpty ? "" : "\n  - 链接: \(normalizedLinks.joined(separator: ", "))"
        let blocks = amounts.map { amount in "- \(summary)\(timeLine)\(payeeLine)\(tagsLine)\(linkLine)\n  - \(destination)  \(LedgerParser.format(amount))\n  - \(source)  \(LedgerParser.format(-amount))" }
        let original = textView.string
        let consolidated = consolidatedLedgerDateSections(original).text
        let insertion = ledgerTransactionInsertion(in: consolidated, date: date, transactionBlocks: blocks)
        if consolidated == original {
            textView.textStorage?.replaceCharacters(in: NSRange(location: insertion.location, length: 0), with: insertion.text)
        } else {
            let updated = NSMutableString(string: consolidated)
            updated.insert(insertion.text, at: insertion.location)
            textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (original as NSString).length), with: updated as String)
        }
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
        let signature = fileSignature(for: url)
        let action = externalChangeAction(last: lastKnownFileSignature, current: signature, hasUnsavedChanges: isDirty)
        switch action {
        case .none: break
        case .reload:
            reloadActiveDocumentFromDisk()
            statusLabel.stringValue = "已重新载入外部修改"
        case .conflict:
            hasExternalConflict = true
            // Record the observed version before presenting the warning. This
            // avoids repeatedly presenting the same conflict every monitor
            // interval while preserving the local session for Save As.
            lastKnownFileSignature = signature
            persistActiveLedgerSession()
            autosaveWorkItem?.cancel()
            statusLabel.stringValue = "检测到外部修改：自动保存已暂停，请重新载入或另存为"
            presentError(ui("检测到外部修改，自动保存已暂停。请重新载入，或使用“另存为”保留当前修改。", "An external change was detected and autosave has paused. Reload the file or use Save As to preserve your current changes."))
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
        case .journal, .reconciliation: openJournalEntry(atReportOffset: offset)
        case .accounts: openAccountJournal(atReportOffset: offset)
        case .overview, .reports: break
        }
    }

    private func openJournalEntry(atReportOffset offset: Int) {
        let block = sidePanelMode == .reconciliation
            ? reconciliationLineIndex(at: offset, in: reportView.string)
            : renderedReportBlockIndex(at: offset, in: reportView.string)
        guard let block,
              reportNavigationLines.indices.contains(block) else { return }
        let line = reportNavigationLines[block]
        guard
              let range = ledgerLineRange(in: textView.string, line: line) else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        statusLabel.stringValue = ui("已定位到原始交易", "Located the source transaction")
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
        accountActionContainer?.isHidden = sidePanelMode != .accounts
        reconciliationOrderContainer?.isHidden = sidePanelMode != .reconciliation
        inspectorTitleLabel.stringValue = switch sidePanelMode {
        case .overview: ui("概览", "Overview")
        case .journal: ui("日记账", "Journal")
        case .reconciliation: ui("对账", "Reconcile")
        case .accounts: ui("账户", "Accounts")
        case .reports: ui("报表", "Reports")
        }
        let output: String
        switch sidePanelMode {
        case .overview:
            reportNavigationLines = []
            output = overviewText(for: report)
        case .journal:
            reportNavigationLines = Array(report.journal(matching: journalQuery, field: journalSearchFieldScope, status: journalStatus).reversed()).map(\.startLine)
            output = journalText(for: report)
        case .reconciliation:
            let hasTrackedAccounts = report.accounts.contains { isLedgerAccount($0, .asset) || isLedgerAccount($0, .liability) }
            var navigation = chronologicallyOrderedTransactions(report.journal).map(\.startLine)
            if reconciliationNewestFirst { navigation.reverse() }
            reportNavigationLines = hasTrackedAccounts ? navigation : []
            reconciliationOrderControl.selectedSegment = reconciliationNewestFirst ? 0 : 1
            output = reconciliationModeText(entries: report.journal, accounts: report.accounts, english: appLanguage == .english, newestFirst: reconciliationNewestFirst)
        case .accounts:
            reportNavigationLines = []
            output = accountTreeText(for: report)
        case .reports:
            reportNavigationLines = []
            output = reportText(for: report)
        }
        let reportAccessibilityLabel = switch sidePanelMode {
        case .overview: "账本概览"
        case .journal: "日记账"
        case .reconciliation: "逐笔对账"
        case .accounts: "账户树"
        case .reports: "个人收支报表"
        }
        reportView.setAccessibilityLabel(reportAccessibilityLabel)
        reportView.string = output
        applyReportTypography()
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
        dashboardIncomeLabel.attributedStringValue = dashboardMetric(title: ui("收入", "Income"), value: LedgerParser.format(summary.incomeTotal))
        dashboardExpenseLabel.attributedStringValue = dashboardMetric(title: ui("支出", "Expenses"), value: LedgerParser.format(summary.expenseTotal))
        dashboardNetLabel.attributedStringValue = dashboardMetric(title: ui("结余", "Net"), value: LedgerParser.format(summary.net))
        // The text file may be organised by project, month, or manual order.
        // "Recent" must therefore be ordered by its declared date—not by where
        // a transaction happens to occur in the source—while retaining source
        // order for entries made on the same day.
        let recent = Array(report.journal
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.startLine > $1.startLine
            }
            .prefix(8))
        dashboardRecentTransactions = recent
        transactionBrowserController?.updateTransactions(report.journal)
        selectedDashboardTransaction = nil
        dashboardEditButton.isEnabled = false
        dashboardDeleteButton.isEnabled = false
        dashboardRecentView.string = recent.isEmpty
            ? ui("暂无交易", "No transactions")
            : recent.map { entry in
                let fullDetail = ledgerTransactionDetail(entry)
                let detail = fullDetail.count > 19 ? String(fullDetail.prefix(18)) + "…" : fullDetail
                let context = ledgerTransactionUIInfo(entry).context(english: appLanguage == .english)
                let compactContext = context.count > 24 ? String(context.prefix(23)) + "…" : context
                return "\(ledgerTransactionDateTime(entry))\t\(detail)\t\(compactContext)\t\(LedgerParser.format(ledgerTransactionDisplayAmount(entry)))"
            }.joined(separator: "\n")
        applyDashboardRecentTypography()
    }

    private func selectDashboardTransaction(at row: Int) {
        guard dashboardRecentTransactions.indices.contains(row) else { return }
        selectedDashboardTransaction = dashboardRecentTransactions[row]
        dashboardEditButton.isEnabled = true
        dashboardDeleteButton.isEnabled = true
        let source = dashboardRecentView.string as NSString
        var location = 0
        for _ in 0..<row {
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
        }
        let range = source.lineRange(for: NSRange(location: min(location, source.length), length: 0))
        dashboardRecentView.setSelectedRange(range)
    }

    @objc private func showTransactionBrowser(_ sender: Any?) {
        if transactionBrowserController == nil {
            let controller = TransactionBrowserController(transactions: latestReport.journal, english: appLanguage == .english)
            controller.onEdit = { [weak self] transaction in
                self?.sidePanelMode = .overview
                self?.updateSidebarSelection()
                self?.beginEditingDashboardTransaction(transaction)
            }
            controller.onDelete = { [weak self] transaction in self?.deleteDashboardTransaction(transaction) ?? false }
            transactionBrowserController = controller
        } else {
            transactionBrowserController?.updateTransactions(latestReport.journal)
        }
        transactionBrowserController?.show()
    }

    private func editableComponents(for transaction: LedgerTransaction) -> (kind: QuickEntryKind, destination: LedgerPosting, source: LedgerPosting)? {
        guard transaction.postings.count == 2 else { return nil }
        if let destination = transaction.postings.first(where: { isLedgerAccount($0.account, .expense) }),
           let source = transaction.postings.first(where: { $0.line != destination.line && (isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability)) }) {
            return (.expense, destination, source)
        }
        if let source = transaction.postings.first(where: { isLedgerAccount($0.account, .income) }),
           let destination = transaction.postings.first(where: { $0.line != source.line && (isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability)) }) {
            return (.income, destination, source)
        }
        if transaction.postings.allSatisfy({ isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }) {
            return (.transfer, transaction.postings[0], transaction.postings[1])
        }
        return nil
    }

    @objc private func editSelectedDashboardTransaction(_ sender: Any?) {
        guard let transaction = selectedDashboardTransaction else { return }
        beginEditingDashboardTransaction(transaction)
    }

    private func beginEditingDashboardTransaction(_ transaction: LedgerTransaction) {
        guard let components = editableComponents(for: transaction),
              let range = ledgerSourceRange(in: textView.string, fromLine: transaction.startLine, throughLine: transaction.endLine) else { return }
        let original = (textView.string as NSString).substring(with: range)
        guard canonicalOutlineTransactionBlock(source: original, summary: transaction.summary, flag: transaction.flag, time: transaction.time, payee: transaction.payee, tags: transaction.tags, links: transaction.links, destination: components.destination.account, sourceAccount: components.source.account, amount: components.destination.amount) != nil else {
            presentError(ui("这笔交易包含复杂或无法识别的手写内容，请使用“编辑文本”保留原样修改。", "This transaction contains complex hand-written content. Use Edit Text to preserve it while editing."))
            return
        }
        editingDashboardTransaction = transaction
        inlineKindControl.selectedSegment = components.kind.rawValue
        inlineEntryBinder?.changeKind(inlineKindControl)
        inlineAmountField.stringValue = LedgerParser.format(components.destination.amount)
        inlineSummaryField.stringValue = transaction.summary
        inlineDestinationPicker.selectItem(withTitle: components.destination.account)
        inlineSourcePicker.selectItem(withTitle: components.source.account)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        inlineDatePicker.dateValue = formatter.date(from: transaction.date) ?? Date()
        updateInlineDateButtonTitle()
        inlineEntryTitleLabel.stringValue = ui("修改交易", "Edit Transaction")
        setPrimaryButtonTitle(inlineSaveButton, ui("保存修改", "Save Changes"))
        inlineCancelEditButton.isHidden = false
        inlineSuggestionPicker.isEnabled = false
        window.makeFirstResponder(inlineAmountField)
    }

    @objc private func cancelInlineTransactionEdit(_ sender: Any?) {
        editingDashboardTransaction = nil
        inlineEntryTitleLabel.stringValue = ui("记一笔", "New Entry")
        setPrimaryButtonTitle(inlineSaveButton, ui("记入账本", "Record"))
        inlineCancelEditButton.isHidden = true
        inlineSuggestionPicker.isEnabled = true
        inlineAmountField.stringValue = ""
        inlineSummaryField.stringValue = ""
        inlineSuggestionPicker.selectItem(at: 0)
    }

    @objc private func deleteSelectedDashboardTransaction(_ sender: Any?) {
        guard let transaction = selectedDashboardTransaction else { return }
        _ = deleteDashboardTransaction(transaction)
    }

    private func deleteDashboardTransaction(_ transaction: LedgerTransaction) -> Bool {
        guard let range = ledgerSourceRange(in: textView.string, fromLine: transaction.startLine, throughLine: transaction.endLine) else { return false }
        let alert = NSAlert()
        alert.messageText = ui("删除这笔交易？", "Delete This Transaction?")
        alert.informativeText = ui("\(transaction.date) · \(transaction.summary)\n删除后账本和报表会立即更新。", "\(transaction.date) · \(transaction.summary)\nThe ledger and reports will update immediately.")
        alert.addButton(withTitle: ui("删除", "Delete"))
        alert.addButton(withTitle: ui("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let raw = textView.string
        let updated = NSMutableString(string: raw)
        updated.replaceCharacters(in: range, with: "")
        let organized = consolidatedLedgerDateSections(updated as String).text
        if organized == updated as String {
            textView.textStorage?.replaceCharacters(in: range, with: "")
        } else {
            textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: organized)
        }
        textView.didChangeText()
        isDirty = true
        if editingDashboardTransaction?.startLine == transaction.startLine { cancelInlineTransactionEdit(nil) }
        scheduleParse(immediately: true)
        scheduleAutosave()
        statusLabel.stringValue = ui("交易已删除", "Transaction deleted")
        return true
    }

    private func dashboardMetric(title: String, value: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        let result = NSMutableAttributedString(string: "\(title)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: CountPaperTheme.secondaryInk,
            .paragraphStyle: paragraph
        ])
        result.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: CountPaperTheme.ink,
            .paragraphStyle: paragraph
        ]))
        return result
    }

    private func applyDashboardRecentTypography() {
        guard let storage = dashboardRecentView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 7
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: 132),
            NSTextTab(textAlignment: .left, location: 330),
            NSTextTab(textAlignment: .right, location: 590)
        ]
        storage.setAttributes([
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: CountPaperTheme.ink,
            .paragraphStyle: paragraph
        ], range: fullRange)
        let source = storage.string as NSString
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange) as NSString
            let firstTab = line.range(of: "\t")
            if firstTab.location != NSNotFound {
                storage.addAttributes([.foregroundColor: CountPaperTheme.secondaryInk, .font: NSFont.systemFont(ofSize: 12)], range: NSRange(location: lineRange.location, length: firstTab.location))
                let lastTab = line.range(of: "\t", options: .backwards)
                if lastTab.location != NSNotFound {
                    let amountRange = NSRange(location: lineRange.location + NSMaxRange(lastTab), length: max(0, lineRange.length - NSMaxRange(lastTab)))
                    storage.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), range: amountRange)
                }
            }
            location = NSMaxRange(lineRange)
        }
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
        if editingDashboardTransaction != nil {
            updateInlineTransaction()
            return
        }
        guard let binder = inlineEntryBinder,
              let amounts = quickEntryAmounts(inlineAmountField.stringValue, allowsMultiple: allowsMultipleAmounts),
              let destination = inlineDestinationPicker.titleOfSelectedItem,
              let source = inlineSourcePicker.titleOfSelectedItem else {
            presentError(ui("请输入有效金额。", "Enter a valid amount."))
            window.makeFirstResponder(inlineAmountField)
            return
        }
        guard binder.kind != .transfer || destination != source else {
            presentError(ui("转入与转出账户不能相同。", "Transfer accounts must differ."))
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

    private func updateInlineTransaction() {
        guard let transaction = editingDashboardTransaction,
              let binder = inlineEntryBinder,
              let amount = quickEntryAmounts(inlineAmountField.stringValue, allowsMultiple: false)?.first,
              amount != .zero,
              let destination = inlineDestinationPicker.titleOfSelectedItem,
              let source = inlineSourcePicker.titleOfSelectedItem else {
            presentError(ui("修改交易时请输入一个非零金额。", "Enter one non-zero amount when editing a transaction."))
            return
        }
        guard binder.kind != .transfer || destination != source else {
            presentError(ui("转入与转出账户不能相同。", "Transfer accounts must differ."))
            return
        }
        let raw = textView.string
        guard let range = ledgerSourceRange(in: raw, fromLine: transaction.startLine, throughLine: transaction.endLine) else {
            presentError(ui("原交易位置已经变化，请重新选择后修改。", "The source transaction moved. Select it again before editing."))
            cancelInlineTransactionEdit(nil)
            return
        }
        let original = (raw as NSString).substring(with: range)
        let fallback: String = switch binder.kind { case .expense: ui("支出", "Expense"); case .income: ui("收入", "Income"); case .transfer: ui("转账", "Transfer") }
        let enteredSummary = inlineSummaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let newDate = formatter.string(from: inlineDatePicker.dateValue)
        guard let replacement = canonicalOutlineTransactionBlock(source: original, summary: enteredSummary.isEmpty ? fallback : enteredSummary, flag: transaction.flag, time: transaction.time, payee: transaction.payee, tags: transaction.tags, links: transaction.links, destination: destination, sourceAccount: source, amount: amount) else {
            presentError(ui("无法安全修改这笔交易，请使用“编辑文本”。", "This transaction cannot be edited safely. Use Edit Text instead."))
            return
        }
        if newDate == transaction.date {
            let updated = NSMutableString(string: raw)
            updated.replaceCharacters(in: range, with: replacement)
            let organized = consolidatedLedgerDateSections(updated as String).text
            if organized == updated as String {
                textView.textStorage?.replaceCharacters(in: range, with: replacement)
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (raw as NSString).length), with: organized)
            }
        } else {
            let updated = NSMutableString(string: raw)
            updated.replaceCharacters(in: range, with: "")
            let block = replacement.trimmingCharacters(in: .newlines)
            let organizedBase = consolidatedLedgerDateSections(updated as String).text
            let insertion = ledgerTransactionInsertion(in: organizedBase, date: newDate, transactionBlocks: [block])
            let final = NSMutableString(string: organizedBase)
            final.insert(insertion.text, at: insertion.location)
            textView.string = consolidatedLedgerDateSections(final as String).text
        }
        textView.didChangeText()
        isDirty = true
        cancelInlineTransactionEdit(nil)
        scheduleParse(immediately: true)
        scheduleAutosave()
        statusLabel.stringValue = ui("交易已更新", "Transaction updated")
        window.makeFirstResponder(inlineAmountField)
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
            for (account, raw) in report.balances.sorted(by: { $0.key < $1.key }) where !isInternalBalanceAdjustmentAccount(account) {
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
            guard !journalQuery.isEmpty || journalStatus != .all else { return "尚无交易" }
            let scope = journalSearchFieldScope == .all ? "" : "\(journalSearchFieldScope.title)中的"
            let queryText = journalQuery.isEmpty ? "" : "与「\(journalQuery)」匹配的"
            let statusText = journalStatus == .all ? "" : "\(journalStatus.title)的"
            return "没有\(queryText)\(scope)\(statusText)交易"
        }
        var output = ""
        for entry in entries.reversed() {
            let flag = entry.flag.map { " \($0)" } ?? ""
            let info = ledgerTransactionUIInfo(entry)
            output += "\(ledgerTransactionDateTime(entry))\(flag)  \(entry.summary)  ·  \(LedgerParser.format(info.amount))\n"
            output += "    \(info.kindTitle(english: appLanguage == .english))：\(info.context(english: appLanguage == .english))\n"
            if let payee = entry.payee { output += "    收款方：\(payee)\n" }
            if !entry.tags.isEmpty { output += "    标签：\(entry.tags.map { "#\($0)" }.joined(separator: " "))\n" }
            for link in entry.links { output += "    链接：\(link)\n" }
            output += "\n"
        }
        return output
    }

    private func accountTreeText(for report: LedgerReport) -> String {
        let visibleAccounts = report.accounts.filter { !isInternalBalanceAdjustmentAccount($0) }
        guard !visibleAccounts.isEmpty else { return ui("尚未声明账户", "No accounts declared") }
        var output = ""
        let notes = Dictionary(uniqueKeysWithValues: report.accountNotes.map { ($0.account, $0.text) })
        let roots = appLanguage == .english ? ["Assets", "Liabilities", "Equity", "Income", "Expenses"] : ["资产", "负债", "权益", "收入", "费用"]
        let invertedRoots = Set(appLanguage == .english ? ["Liabilities", "Equity", "Income"] : ["负债", "权益", "收入"])
        for root in roots {
            let accounts = visibleAccounts.filter { $0 == root || $0.hasPrefix("\(root):") }
            guard !accounts.isEmpty else { continue }
            let rawTotal = accounts.reduce(Decimal.zero) { total, account in total + (report.balances[account] ?? .zero) }
            let displayTotal = invertedRoots.contains(root) ? -rawTotal : rawTotal
            output += "\(root)  \(LedgerParser.format(displayTotal))\n"
            for account in accounts {
                let depth = account.split(separator: ":").count - 1
                let display = (invertedRoots.contains(root) ? -(report.balances[account] ?? .zero) : (report.balances[account] ?? .zero))
                output += "\(String(repeating: "  ", count: depth))\(account.split(separator: ":").last!)  \(LedgerParser.format(display))\n"
                if let note = notes[account] { output += "\(String(repeating: "  ", count: depth + 1))· \(note)\n" }
            }
            output += "\n"
        }
        return output
    }

    private func applyReportTypography() {
        guard let storage = reportView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = 3
        baseParagraph.paragraphSpacing = 2
        storage.setAttributes([
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraph
        ], range: fullRange)

        let source = storage.string as NSString
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = source.substring(with: lineRange)
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let leadingWhitespace = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3

            switch sidePanelMode {
            case .journal:
                if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil {
                    paragraph.paragraphSpacingBefore = location == 0 ? 0 : 12
                    paragraph.paragraphSpacing = 4
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .paragraphStyle: paragraph], range: lineRange)
                } else if leadingWhitespace > 0 {
                    storage.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor], range: lineRange)
                }
            case .reconciliation:
                if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil {
                    paragraph.paragraphSpacingBefore = location == 0 ? 0 : 8
                    paragraph.paragraphSpacing = 1
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .paragraphStyle: paragraph], range: lineRange)
                } else if leadingWhitespace > 0 {
                    paragraph.paragraphSpacing = 1
                    storage.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: CountPaperTheme.secondaryInk, .paragraphStyle: paragraph], range: lineRange)
                }
            case .accounts:
                let isRoot = leadingWhitespace == 0 && ["资产", "负债", "权益", "收入", "费用"].contains { trimmed.hasPrefix($0 + "  ") || trimmed == $0 }
                if isRoot {
                    paragraph.paragraphSpacingBefore = location == 0 ? 0 : 14
                    paragraph.paragraphSpacing = 5
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .paragraphStyle: paragraph], range: lineRange)
                } else if leadingWhitespace > 0 {
                    storage.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor], range: lineRange)
                }
            case .reports:
                if location == 0 {
                    paragraph.paragraphSpacing = 12
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .paragraphStyle: paragraph], range: lineRange)
                } else if trimmed.contains("合计") || trimmed.contains("结余") || trimmed.contains("平均") || trimmed.contains("交易") || trimmed.contains("笔数") {
                    storage.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular), range: lineRange)
                }
            case .overview:
                break
            }
            location = NSMaxRange(lineRange)
        }
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
        let accounts = report.accounts.filter { !isInternalBalanceAdjustmentAccount($0) }.sorted()
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
        let timeFormatter = DateFormatter(); timeFormatter.locale = Locale(identifier: "en_US_POSIX"); timeFormatter.dateFormat = "HH:mm"
        let now = timeFormatter.string(from: Date())
        if language == .english {
            return """
            ---
            format: countpaper/0.2
            currency: USD
            ---

            @accounts
            - Assets:Cash
            - Assets:Bank
            - Liabilities:CreditCard
            - Equity:BalanceAdjustment
            - Income:Salary
            - Expenses:Dining
            - Expenses:Transport
            - Expenses:Groceries

            # \(today)
            - Lunch
              - time: \(now)
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
        - 权益:余额调整
        - 收入:工资
        - 费用:餐饮
        - 费用:交通
        - 费用:日用品

        # \(today)
        - 今日午餐
          - 时间: \(now)
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) { layoutDocumentViews() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // A document window's red close button shelves the editing session.
        // Keeping one live NSWindow eliminates AppKit/Launch Services races in
        // which a later Finder open event targets a deallocated window.
        if sender === window {
            sender.orderOut(nil)
            return false
        }
        return true
    }
}
