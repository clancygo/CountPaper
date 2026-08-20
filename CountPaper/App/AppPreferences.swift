import Foundation

enum CountPaperPreference {
    static let multipleAmounts = "preferences.multipleAmounts"
    static let multipleAmountsMigrated = "preferences.multipleAmountsMigrated"
    static let checkBalanceOnOpen = "preferences.checkBalanceOnOpen"
    static let language = "preferences.language"
    static let sourceEditorApplicationPath = "preferences.sourceEditorApplicationPath"
    static let workspaceSidePanelMode = "workspace.sidePanelMode"
    static let workspaceReportKind = "workspace.reportKind"
    static let workspaceReportsAllLedgers = "workspace.reportsAllLedgers"
    static let workspaceReconciliationNewestFirst = "workspace.reconciliationNewestFirst"
    static let workspaceReportMonth = "workspace.reportMonth"
    static let workspaceReportStartDate = "workspace.reportStartDate"
    static let workspaceReportEndDate = "workspace.reportEndDate"
    static let workspaceReportTag = "workspace.reportTag"
    static let workspaceReportAccount = "workspace.reportAccount"
}

enum AppLanguage: String { case chinese, english }
