import Cocoa

@main
struct DocumentWorkflowTests {
    static func main() {
        let sessions = [
            LedgerSession(url: URL(fileURLWithPath: "/tmp/current.countpaper"), text: "current", isDirty: false),
            LedgerSession(url: nil, text: "background edit", isDirty: true)
        ]
        MacOSTestSupport.expect(dirtyLedgerSessionIndexes(sessions) == [1], "background dirty sessions are retained")
        let urls = [URL(fileURLWithPath: "/tmp/ledger.countpaper"), URL(fileURLWithPath: "/tmp/./ledger.countpaper"), URL(fileURLWithPath: "/tmp/notes.txt")]
        MacOSTestSupport.expect(uniqueLedgerDocumentURLs(urls).count == 1, "Finder opens are deduplicated")
        runDocumentSaveOpenWorkflow()
        InteractionTests.run()
        print("macOS document workflow tests passed")
    }

    private static func runDocumentSaveOpenWorkflow() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CountPaperWorkflow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.countpaper")
        let backups = directory.appendingPathComponent("Backups")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let document = LedgerDocument(url: nil, text: MacOSTestSupport.sample)
            _ = try document.save(to: url, recoveryDirectory: backups)
            document.replaceText(document.text.replacingOccurrences(of: "午餐", with: "工作流午餐"), markingDirty: true)
            _ = try document.save(recoveryDirectory: backups)
            let reopened = LedgerDocument(url: url, text: try String(contentsOf: url, encoding: .utf8), signature: LedgerDocument.fileSignature(for: url))
            MacOSTestSupport.expect(reopened.report.journal.last?.summary == "工作流午餐" && !reopened.isDirty, "save and reopen retains document state")
        } catch { MacOSTestSupport.fail("workflow failed: \(error)") }
    }
}

enum MacOSTestSupport {
    static let sample = """
    ---
    format: countpaper/0.2
    currency: CNY
    ---

    @账户
    - 资产:现金
    - 费用:餐饮

    # 2026-08-02
    - 午餐
      - 费用:餐饮  32.50
      - 资产:现金  -32.50
    """
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) { guard condition() else { fail(message) } }
    static func fail(_ message: String) -> Never { fputs("FAILED: \(message)\n", stderr); exit(1) }
}
