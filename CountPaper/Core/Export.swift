import Foundation

func csvField(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }

func personalReportCSV(report: LedgerReport, month: String?, startDate: String? = nil, endDate: String? = nil, tag: String? = nil, account: String? = nil) -> String {
    let baseEntries = startDate != nil || endDate != nil ? report.reportEntries(startDate: startDate, endDate: endDate) : report.journal.filter { month == nil || $0.date.hasPrefix(month! + "-") }
    let tagEntries = tag.map { selected in baseEntries.filter { $0.tags.contains(selected) } } ?? baseEntries
    let entries = account.map { selected in tagEntries.filter { $0.postings.contains { $0.account == selected } } } ?? tagEntries
    let summary = report.personalSummary(entries: entries)
    let period = startDate != nil || endDate != nil ? "\(startDate ?? "起始") 至 \(endDate ?? "今日")" : (month ?? "全部期间")
    var rows = ["期间,类型,分类,实际金额,预算金额,预算结余"]
    rows.append([period, "交易数", "", String(summary.transactions), "", ""].map(csvField).joined(separator: ","))
    for (account, amount) in summary.income.sorted(by: { $0.key < $1.key }) { rows.append([period, "收入", account, LedgerCoreParser.format(amount), "", ""].map(csvField).joined(separator: ",")) }
    let budgets = month.map { selectedMonth in report.budgets.filter { $0.month == selectedMonth } } ?? []
    let budgetByAccount = Dictionary(uniqueKeysWithValues: budgets.map { ($0.account, $0.amount) })
    for account in Set(summary.expenses.keys).union(budgetByAccount.keys).sorted() {
        let actual = summary.expenses[account] ?? .zero; let budget = budgetByAccount[account]
        rows.append([period, "支出", account, LedgerCoreParser.format(actual), budget.map(LedgerCoreParser.format) ?? "", budget.map { LedgerCoreParser.format($0 - actual) } ?? ""].map(csvField).joined(separator: ","))
    }
    rows.append([period, "收支结余", "", LedgerCoreParser.format(summary.net), "", ""].map(csvField).joined(separator: ","))
    return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
}

func journalCSV(report: LedgerReport, month: String?, startDate: String? = nil, endDate: String? = nil, tag: String? = nil, account: String? = nil) -> String {
    let baseEntries = startDate != nil || endDate != nil ? report.reportEntries(startDate: startDate, endDate: endDate) : report.journal.filter { month == nil || $0.date.hasPrefix(month! + "-") }
    let tagEntries = tag.map { selected in baseEntries.filter { $0.tags.contains(selected) } } ?? baseEntries
    let entries = account.map { selected in tagEntries.filter { $0.postings.contains { $0.account == selected } } } ?? tagEntries
    var rows = ["日期,时间,状态,类型,摘要,收款方,分类,账户,转入账户,标签,链接,金额"]
    for entry in entries {
        let info = ledgerExportInfo(entry)
        rows.append([entry.date, entry.time ?? "", entry.flag == "!" ? "待确认" : "已确认", info.kind, entry.summary, entry.payee ?? "", info.category ?? "", info.account ?? "", info.destination ?? "", entry.tags.map { "#\($0)" }.joined(separator: " "), entry.links.joined(separator: " "), LedgerCoreParser.format(info.amount)].map(csvField).joined(separator: ","))
    }
    return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
}

private func ledgerExportInfo(_ entry: LedgerTransaction) -> (kind: String, category: String?, account: String?, destination: String?, amount: Decimal) {
    func display(_ account: String) -> String {
        let parts = account.split(separator: ":").map(String.init)
        return parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : account
    }
    let amount: Decimal = {
        if let expense = entry.postings.first(where: { isLedgerAccount($0.account, .expense) }) { return expense.amount }
        if let income = entry.postings.first(where: { isLedgerAccount($0.account, .income) }) { return -income.amount }
        return entry.postings.first(where: { $0.amount > .zero })?.amount ?? entry.postings.first?.amount ?? .zero
    }()
    if let category = entry.postings.first(where: { isLedgerAccount($0.account, .expense) }) {
        let payment = entry.postings.first { isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }
        return ("支出", display(category.account), payment.map { display($0.account) }, nil, amount)
    }
    if let category = entry.postings.first(where: { isLedgerAccount($0.account, .income) }) {
        let received = entry.postings.first { isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }
        return ("收入", display(category.account), received.map { display($0.account) }, nil, amount)
    }
    if entry.postings.count >= 2, entry.postings.allSatisfy({ isLedgerAccount($0.account, .asset) || isLedgerAccount($0.account, .liability) }) {
        return ("转账", nil, display(entry.postings[1].account), display(entry.postings[0].account), amount)
    }
    return ("交易", nil, entry.postings.first.map { display($0.account) }, nil, amount)
}
