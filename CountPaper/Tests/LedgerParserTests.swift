import Cocoa

@main
struct LedgerParserTests {
    static func main() {
        let sample = """
        ---
        format: countpaper/0.2
        currency: CNY
        ---

        @账户
        - 资产:现金
        - 收入:工资
        - 费用:餐饮

        # 2026-08-01
        - 工资
          - 资产:现金  1000.00
          - 收入:工资  -1000.00

        # 2026-08-02
        - 午餐
          - 时间: 12:35
          - 收款方: 星巴克
          - 标签: #咖啡, 日常
          - 费用:餐饮  32.50
          - 资产:现金  -32.50
        """
        let report = LedgerParser.parse(sample)
        expect(report.diagnostics.isEmpty, "有效的大纲账本不应报错")
        expect(report.transactions == 2 && report.balances["资产:现金"] == Decimal(string: "967.50"), "大纲分录应正确计算余额")
        expect(report.journal.last?.date == "2026-08-02" && report.journal.last?.summary == "午餐", "日期标题与交易条目应被正确关联")
        expect(report.journal.last?.payee == "星巴克" && report.journal.last?.tags == ["咖啡", "日常"], "缩进元数据条目应被正确解析")
        expect(report.journal.last?.time == "12:35", "交易时间应精确解析到分钟")
        expect(ledgerTransactionDetail(report.journal.last!).contains("星巴克") && ledgerTransactionDetail(report.journal.last!).contains("#咖啡"), "最近交易应组合摘要、收款方和标签")
        expect(filteredLedgerTransactions(report.journal, query: "星巴克").count == 1, "交易管理器应能按收款方或备注检索")
        expect(filteredLedgerTransactions(report.journal, startDate: "2026-08-02", endDate: "2026-08-02", minimumAmount: 30, maximumAmount: 40, tag: "咖啡").count == 1, "交易管理器应组合日期、金额和标签筛选")
        expect(filteredLedgerTransactions(report.journal, minimumAmount: 40, tag: "咖啡").isEmpty, "交易金额范围应排除不符合记录")
        expect(report.personalSummary(month: "2026-08").expenseTotal == Decimal(string: "32.50"), "报表应按新格式正确汇总支出")
        let reconciliationText = reconciliationModeText(entries: report.journal, accounts: report.accounts)
        expect(reconciliationText.contains("2026-08-02 12:35") && reconciliationText.contains("资产:现金  967.50"), "逐笔对账应在线性累计后显示每笔交易后的资产余额")
        expect(!reconciliationText.contains(" · 第") && !reconciliationText.contains(" · line"), "日记账与对账界面不应暴露源码行号")
        expect(renderedReportBlockIndex(at: reconciliationText.range(of: "午餐")!.lowerBound.utf16Offset(in: reconciliationText), in: reconciliationText) == 1, "隐藏行号后仍应能按交易块定位原文")
        let revisedReport = LedgerParser.parse(sample.replacingOccurrences(of: "32.50", with: "42.50").replacingOccurrences(of: "-32.50", with: "-42.50"))
        expect(reconciliationModeText(entries: revisedReport.journal, accounts: revisedReport.accounts).contains("资产:现金  957.50"), "修改历史交易后全部后续余额应同步重算")
        let english = sample
            .replacingOccurrences(of: "currency: CNY", with: "currency: USD")
            .replacingOccurrences(of: "资产:现金", with: "Assets:Cash")
            .replacingOccurrences(of: "收入:工资", with: "Income:Salary")
            .replacingOccurrences(of: "费用:餐饮", with: "Expenses:Dining")
            .replacingOccurrences(of: "时间:", with: "time:")
        let englishReport = LedgerParser.parse(english)
        expect(englishReport.diagnostics.isEmpty && englishReport.journal.last?.time == "12:35" && englishReport.personalSummary(month: "2026-08").expenseTotal == Decimal(string: "32.50"), "英文账户根级、时间元数据与 USD 模板应被正确解析和统计")
        let combinedReport = aggregateLedgerReports([report, englishReport])
        let combinedSummary = combinedReport.personalSummary(month: "2026-08")
        expect(combinedReport.transactions == 4 && combinedSummary.expenseTotal == Decimal(string: "65.00") && combinedSummary.incomeTotal == Decimal(string: "2000.00"), "所有打开账本报表应合并各账本文本解析结果")
        expect(Set(combinedReport.accounts).isSuperset(of: ["资产:现金", "Assets:Cash"]), "多账本聚合应保留不同语言的账户维度")
        let diningJournalCSV = journalCSV(report: report, month: "2026-08", account: "费用:餐饮")
        expect(diningJournalCSV.contains("午餐") && !diningJournalCSV.contains("工资\""), "账户筛选应只保留包含所选账户的交易")

        let oldSyntax = "账本 0.1\n本位币 CNY\n账户 资产:现金\n"
        expect(!LedgerParser.parse(oldSyntax).diagnostics.isEmpty, "旧格式不得被新解析器兼容")
        let missingDate = sample.replacingOccurrences(of: "# 2026-08-01\n", with: "")
        expect(LedgerParser.parse(missingDate).diagnostics.contains { $0.contains("账户声明无效") }, "账户区后的交易必须先有日期一级标题")
        let unbalanced = sample.replacingOccurrences(of: "资产:现金  -32.50", with: "资产:现金  -30.00")
        expect(LedgerParser.parse(unbalanced).diagnostics.contains { $0.contains("不平衡") }, "不平衡交易必须报错")

        let smartExpense = smartLedgerTransaction(shortcut: "餐饮32", accounts: ["资产:现金", "费用:餐饮", "收入:工资"], defaultAsset: "资产:现金", date: "2026-03-01")
        expect(smartExpense == "# 2026-03-01\n- 餐饮\n  - 费用:餐饮  32.00\n  - 资产:现金  -32.00", "紧凑智能输入应生成 Markdown 大纲交易")
        let smartIncome = smartLedgerTransaction(shortcut: "工资 -20", accounts: ["资产:现金", "费用:餐饮", "收入:工资"], defaultAsset: "资产:现金", date: "2026-03-01")
        expect(smartIncome == "# 2026-03-01\n- 工资\n  - 资产:现金  -20.00\n  - 收入:工资  20.00", "负金额收入应保持平衡")
        expect(quickEntryAmounts("32 57", allowsMultiple: true)?.count == 2 && quickEntryAmounts("-20", allowsMultiple: false) == [Decimal(string: "-20")!], "表单金额应支持批量和负数")
        let quickAccounts = ["资产:现金", "负债:信用卡", "收入:工资", "费用:餐饮"]
        let expenseOptions = quickEntryAccountOptions(accounts: quickAccounts, kind: .expense)
        expect(expenseOptions.destination == ["费用:餐饮"] && expenseOptions.source == ["资产:现金", "负债:信用卡"], "统一记账切到支出时应显示费用和付款账户")
        let incomeOptions = quickEntryAccountOptions(accounts: quickAccounts, kind: .income)
        expect(incomeOptions.destination == ["资产:现金"] && incomeOptions.source == ["收入:工资"], "统一记账切到收入时应显示收款和收入账户")
        let transferOptions = quickEntryAccountOptions(accounts: quickAccounts, kind: .transfer)
        expect(transferOptions.destination == transferOptions.source && transferOptions.destination.count == 2, "统一记账切到转账时两侧都应使用资产或负债账户")
        let backgroundDirtySessions = [
            LedgerSession(url: URL(fileURLWithPath: "/tmp/current.countpaper"), text: "current", isDirty: false),
            LedgerSession(url: nil, text: "background edit", isDirty: true)
        ]
        expect(dirtyLedgerSessionIndexes(backgroundDirtySessions) == [1], "退出检查必须识别非当前标签中的未保存更改")
        expect(dirtyLedgerSessionIndexes([LedgerSession(url: nil, text: "clean")]).isEmpty, "所有标签干净时不应触发退出保存提示")
        let repeatedOpenURLs = [
            URL(fileURLWithPath: "/tmp/ledger.countpaper"),
            URL(fileURLWithPath: "/tmp/./ledger.countpaper"),
            URL(fileURLWithPath: "/tmp/notes.txt"),
            URL(fileURLWithPath: "/tmp/second.COUNTPAPER")
        ]
        let uniqueOpenURLs = uniqueLedgerDocumentURLs(repeatedOpenURLs)
        expect(uniqueOpenURLs.map(\.lastPathComponent) == ["ledger.countpaper", "second.COUNTPAPER"], "Finder 重复打开事件应去重并忽略非账本文件")
        expect(shouldReplacePlaceholderLedger([LedgerSession(url: nil, text: "template")]), "冷启动文件应替换未编辑的占位账本")
        expect(!shouldReplacePlaceholderLedger([LedgerSession(url: nil, text: "edited", isDirty: true)]), "Finder 打开文件不得覆盖用户尚未保存的修改")
        expect(!shouldReplacePlaceholderLedger([LedgerSession(url: URL(fileURLWithPath: "/tmp/real.countpaper"), text: "saved")]), "真实文件标签不得被后续打开请求替换")
        let unchangedSignature = LedgerFileSignature(modificationDate: Date(timeIntervalSince1970: 1), size: 10)
        let changedSignature = LedgerFileSignature(modificationDate: Date(timeIntervalSince1970: 2), size: 20)
        expect(externalChangeAction(last: unchangedSignature, current: unchangedSignature, hasUnsavedChanges: false) == .none, "文件签名不变时不应触发外部变更")
        expect(externalChangeAction(last: unchangedSignature, current: changedSignature, hasUnsavedChanges: false) == .reload, "无本地修改时应重新载入外部变更")
        expect(externalChangeAction(last: unchangedSignature, current: changedSignature, hasUnsavedChanges: true) == .conflict, "有本地修改时外部变更必须进入冲突状态")
        let existingDateSource = "# 2026-08-11\n- 原交易\n  - 费用:餐饮  1.00\n  - 资产:现金  -1.00\n"
        let sameDateInsertion = ledgerTransactionInsertion(in: existingDateSource, date: "2026-08-11", transactionBlocks: ["- 新交易\n  - 费用:餐饮  2.00\n  - 资产:现金  -2.00"])
        let sameDateResult = NSMutableString(string: existingDateSource)
        sameDateResult.insert(sameDateInsertion.text, at: sameDateInsertion.location)
        expect(sameDateResult.components(separatedBy: "# 2026-08-11").count == 2 && sameDateResult.contains("- 原交易\n") && sameDateResult.contains("- 新交易\n"), "快速记账应插入已有日期章节而不是重复日期标题")
        let newDateInsertion = ledgerTransactionInsertion(in: existingDateSource, date: "2026-08-12", transactionBlocks: ["- 次日交易\n  - 费用:餐饮  3.00\n  - 资产:现金  -3.00"])
        expect(newDateInsertion.location == existingDateSource.utf16.count && newDateInsertion.text.contains("# 2026-08-12\n- 次日交易"), "新日期快速记账应创建新的一级日期标题")
        let duplicateDates = """
        ---
        format: countpaper/0.2
        currency: CNY
        ---

        @账户
        - 资产:现金
        - 费用:餐饮

        # 2026-08-11
        - 早餐
          - 费用:餐饮  10.00
          - 资产:现金  -10.00

        # 2026-08-12
        - 午餐
          - 费用:餐饮  20.00
          - 资产:现金  -20.00

        # 2026-08-11
        - 晚餐
          - 费用:餐饮  30.00
          - 资产:现金  -30.00

        # 2026-08-13
        """
        expect(LedgerParser.parse(duplicateDates).diagnostics.contains { $0.contains("重复日期标题") }, "解析器应报告重复日期标题")
        let consolidatedDates = consolidatedLedgerDateSections(duplicateDates)
        expect(consolidatedDates.mergedHeadings == 1 && consolidatedDates.removedEmptyHeadings == 1, "日期整理应统计合并与空标题")
        expect(consolidatedDates.text.components(separatedBy: "# 2026-08-11").count == 2 && consolidatedDates.text.contains("早餐") && consolidatedDates.text.contains("晚餐"), "同日完整交易必须统一到一个日期标题下")
        expect(!consolidatedDates.text.contains("# 2026-08-13"), "没有交易的空日期标题应被移除")
        expect(LedgerParser.parse(consolidatedDates.text).diagnostics.isEmpty, "整理后的账本应保持格式有效和平衡")
        let editableOutline = "- 午餐\n  - 收款方: 星巴克\n  - 标签: 咖啡, 日常\n  - 费用:餐饮  32.50\n  - 资产:现金  -32.50\n"
        let editedOutline = canonicalOutlineTransactionBlock(source: editableOutline, summary: "午后咖啡", flag: nil, payee: "星巴克", tags: ["咖啡"], destination: "费用:餐饮", sourceAccount: "资产:现金", amount: Decimal(string: "-20")!)
        expect(editedOutline == "- 午后咖啡\n  - 收款方: 星巴克\n  - 标签: 咖啡\n  - 费用:餐饮  -20.00\n  - 资产:现金  20.00\n", "表单修改应生成合法的大纲交易并保留负金额语义")
        expect(canonicalOutlineTransactionBlock(source: "- 复杂交易\n  - 自定义说明\n  - 费用:餐饮  1.00\n  - 资产:现金  -1.00\n", summary: "复杂交易", flag: nil, payee: nil, tags: [], destination: "费用:餐饮", sourceAccount: "资产:现金", amount: 1) == nil, "表单修改不得吞掉未知手写条目")
        expect(safeLedgerAutoCorrection("# 2026-08-11\n- ").text == "# 2026-08-11\n- ", "自动修正不得移除正在编辑的交易条目空格")
        expect(outlineNewlineInsertion(in: "# 2026-08-11", selection: NSRange(location: 12, length: 0)) == "\n- ", "日期标题回车应新建交易条目")
        expect(outlineNewlineInsertion(in: "- 午餐", selection: NSRange(location: 4, length: 0)) == "\n- ", "交易条目回车应新建同级交易")
        expect(outlineNewlineInsertion(in: "  - 费用:餐饮  32.50", selection: NSRange(location: 15, length: 0)) == "\n  - ", "分录回车应新建同级缩进条目")

        let manyTransactions = String(repeating: "\n# 2026-08-03\n- 测试\n  - 费用:餐饮  1.00\n  - 资产:现金  -1.00\n", count: 10_000)
        let started = Date()
        let largeReport = LedgerParser.parse(sample + manyTransactions)
        let elapsed = Date().timeIntervalSince(started)
        expect(largeReport.transactions == 10_002, "大账本交易数应正确")
        expect(elapsed < 5, "一万笔交易解析耗时过长：\(elapsed)s")
        let reconciliationStarted = Date()
        let largeReconciliation = reconciliationModeText(entries: largeReport.journal, accounts: largeReport.accounts)
        let reconciliationElapsed = Date().timeIntervalSince(reconciliationStarted)
        expect(largeReconciliation.contains("资产:现金"), "大账本对账应生成资产余额快照")
        expect(reconciliationElapsed < 5, "一万笔逐笔对账生成耗时过长：\(reconciliationElapsed)s")
        print("LedgerParserTests passed — parse 10k: \(String(format: "%.3f", elapsed))s; reconcile 10k: \(String(format: "%.3f", reconciliationElapsed))s")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAILED: \(message)\n", stderr); exit(1) }
    }
}
