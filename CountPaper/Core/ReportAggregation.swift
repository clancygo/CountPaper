import Foundation

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
