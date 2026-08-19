import Foundation

/// A complete ledger document, independent of any AppKit view.
///
/// UI code may keep a cursor position or selection per tab, but it should not
/// own file URLs, dirty state, parsing, external-change state, or persistence.
/// Those responsibilities live here so macOS and a future iOS client share the
/// same document semantics.
final class LedgerDocument {
    let id: UUID
    var url: URL?
    private(set) var text: String {
        didSet { report = LedgerCoreParser.parse(text) }
    }
    private(set) var report: LedgerReport
    private(set) var isDirty: Bool
    private(set) var signature: LedgerFileSignature?
    private(set) var hasExternalConflict: Bool

    var validation: LedgerValidation {
        LedgerValidation.evaluate(diagnostics: report.diagnostics)
    }

    init(url: URL?, text: String, isDirty: Bool = false, signature: LedgerFileSignature? = nil, hasExternalConflict: Bool = false) {
        self.id = UUID()
        self.url = url
        self.text = text
        self.report = LedgerCoreParser.parse(text)
        self.isDirty = isDirty
        self.signature = signature
        self.hasExternalConflict = hasExternalConflict
    }

    func replaceText(_ newText: String, markingDirty: Bool) {
        text = newText
        if markingDirty { isDirty = true }
    }

    func update(url: URL?, signature: LedgerFileSignature?, isDirty: Bool, hasExternalConflict: Bool) {
        self.url = url
        self.signature = signature
        self.isDirty = isDirty
        self.hasExternalConflict = hasExternalConflict
    }

    @discardableResult
    func save(to destination: URL? = nil, backupLimit: Int = 20, recoveryDirectory: URL? = nil) throws -> LedgerDocumentStorage.SaveResult {
        let target = destination ?? url
        guard let target else { throw CocoaError(.fileNoSuchFile) }
        let result = try LedgerDocumentStorage.save(text, to: target, backupLimit: backupLimit, recoveryDirectory: recoveryDirectory)
        url = target
        signature = Self.fileSignature(for: target)
        isDirty = false
        hasExternalConflict = false
        return result
    }

    func reload() throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        replaceText(try String(contentsOf: url, encoding: .utf8), markingDirty: false)
        isDirty = false
        hasExternalConflict = false
        signature = Self.fileSignature(for: url)
    }

    func pendingExternalChangeAction() -> ExternalChangeAction {
        externalChangeAction(last: signature, current: url.flatMap(Self.fileSignature), hasUnsavedChanges: isDirty)
    }

    func markExternalConflict() {
        signature = url.flatMap(Self.fileSignature)
        hasExternalConflict = true
    }

    static func fileSignature(for url: URL) -> LedgerFileSignature? {
        LedgerDocumentStorage.fileSignature(for: url)
    }
}
