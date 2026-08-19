import Foundation

/// The strict CountPaper 0.2 Markdown-outline parser. It depends only on
/// Foundation and Core domain types, making document loading and validation
/// reusable by both macOS and a future iOS client.
enum LedgerCoreParser {
    static let roots = Set(["资产", "负债", "权益", "收入", "费用", "Assets", "Liabilities", "Equity", "Income", "Expenses"])

    static func parse(_ text: String) -> LedgerReport {
        var report = LedgerReport()
        var accounts = Set<String>()
        var postings: [LedgerPosting] = []
        var transactionStart: Int?
        var summary: String?
        var time: String?
        var flag: Character?
        var payee: String?
        var tags: [String] = []
        var links: [String] = []
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
            if postings.count < 2 {
                report.diagnostics.append("错误：第 \(start) 行交易缺少完整账户信息")
                transactionHasError = true
            }
            let total = postings.reduce(Decimal.zero) { $0 + $1.amount }
            if total != .zero {
                report.diagnostics.append("错误：第 \(start) 行交易不平衡（差额 \(format(total))）")
                report.balanceIssues.append(LedgerBalanceIssue(date: currentDate ?? "", summary: summary ?? "", line: start, difference: total))
                transactionHasError = true
            }
            if !transactionHasError {
                report.transactions += 1
                for posting in postings {
                    report.balances[posting.account, default: .zero] += posting.amount
                    if isLedgerAccount(posting.account, .expense) { report.expenses[posting.account, default: .zero] += posting.amount }
                }
                report.journal.append(LedgerTransaction(date: currentDate ?? "", time: time, summary: summary ?? "", flag: flag, postings: postings, payee: payee, tags: tags, links: links, startLine: start, endLine: max(start, line - 1)))
            }
            postings = []; transactionStart = nil; summary = nil; time = nil; flag = nil; payee = nil; tags = []; links = []; transactionHasError = false
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
                guard !sawAccountMarker, transactionStart == nil, currentDate == nil else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户区标记只能在正文开始处出现一次"); continue
                }
                sawAccountMarker = true; inAccountSection = true; continue
            }
            if rawLine.hasPrefix("# ") {
                finishTransaction(at: lineNumber)
                inAccountSection = false
                let date = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if isValidISODate(date) {
                    currentDate = date
                    if !seenDateHeadings.insert(date).inserted {
                        report.diagnostics.append("错误：第 \(lineNumber) 行重复日期标题“# \(date)”；同一天的交易必须位于同一标题下")
                    }
                } else {
                    currentDate = nil; report.diagnostics.append("错误：第 \(lineNumber) 行日期标题应为“# YYYY-MM-DD”")
                }
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
                flag = marker == "*" || marker == "!" ? marker : nil
                summary = String((flag == nil ? remainder : String(remainder.dropFirst())).trimmingCharacters(in: .whitespaces))
                if summary?.isEmpty != false { report.diagnostics.append("错误：第 \(lineNumber) 行交易摘要不能为空"); transactionHasError = true }
                currentDate = date; transactionStart = lineNumber; continue
            }
            if rawLine.hasPrefix("  - ") {
                guard transactionStart != nil else { report.diagnostics.append("错误：第 \(lineNumber) 行缩进条目没有所属交易"); continue }
                let body = String(rawLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if let prefix = ["时间:", "时间：", "time:"].first(where: { body.hasPrefix($0) }) {
                    let value = String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if value.range(of: "^(?:[01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil { time = value }
                    else { report.diagnostics.append("错误：第 \(lineNumber) 行时间应为 24 小时制 HH:mm"); transactionHasError = true }
                    continue
                }
                if body.hasPrefix("收款方:") || body.hasPrefix("收款方：") { payee = String(body.dropFirst(4)).trimmingCharacters(in: .whitespaces); continue }
                if body.hasPrefix("标签:") || body.hasPrefix("标签：") {
                    for tag in metadata(from: body).tags where !tags.contains(tag) { tags.append(tag) }; continue
                }
                if body.hasPrefix("链接:") || body.hasPrefix("链接：") {
                    for link in parsedLinks(from: body) where !links.contains(link) { links.append(link) }; continue
                }
                let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2, let amount = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")), amount != .zero else {
                    report.diagnostics.append("错误：第 \(lineNumber) 行账户记录应为“  - 账户名  金额”"); transactionHasError = true; continue
                }
                let account = String(parts[0])
                if !accounts.contains(account) { report.diagnostics.append("错误：第 \(lineNumber) 行使用了未声明账户「\(account)」"); transactionHasError = true }
                postings.append(LedgerPosting(account: account, amount: amount, line: lineNumber)); continue
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

    static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    private static func metadata(from body: String) -> (payee: String?, tags: [String]) {
        let value = body.drop(while: { $0 != ":" && $0 != "：" }).dropFirst().trimmingCharacters(in: .whitespaces)
        return (nil, value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty })
    }

    private static func parsedLinks(from body: String) -> [String] {
        let value = body.drop(while: { $0 != ":" && $0 != "：" }).dropFirst().trimmingCharacters(in: .whitespaces)
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func isValidISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents(); components.calendar = calendar; components.year = year; components.month = month; components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        return verified.year == year && verified.month == month && verified.day == day
    }
}
