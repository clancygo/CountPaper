import Foundation

/// UI selection is session state, while document data and persistence remain
/// owned by LedgerDocument. This Foundation-only type deliberately has no
/// AppKit dependency.
struct LedgerSession {
    let document: LedgerDocument
    var selection: NSRange

    init(url: URL?, text: String, isDirty: Bool = false, signature: LedgerFileSignature? = nil, hasExternalConflict: Bool = false, selection: NSRange = NSRange(location: 0, length: 0)) {
        document = LedgerDocument(url: url, text: text, isDirty: isDirty, signature: signature, hasExternalConflict: hasExternalConflict)
        self.selection = selection
    }

    var id: UUID { document.id }
    var url: URL? { get { document.url } set { document.url = newValue } }
    var text: String { get { document.text } set { document.replaceText(newValue, markingDirty: false) } }
    var isDirty: Bool { get { document.isDirty } set { document.update(url: document.url, signature: document.signature, isDirty: newValue, hasExternalConflict: document.hasExternalConflict) } }
    var signature: LedgerFileSignature? { get { document.signature } set { document.update(url: document.url, signature: newValue, isDirty: document.isDirty, hasExternalConflict: document.hasExternalConflict) } }
    var hasExternalConflict: Bool { get { document.hasExternalConflict } set { document.update(url: document.url, signature: document.signature, isDirty: document.isDirty, hasExternalConflict: newValue) } }
}

func dirtyLedgerSessionIndexes(_ sessions: [LedgerSession]) -> [Int] { sessions.indices.filter { sessions[$0].isDirty } }

func uniqueLedgerDocumentURLs(_ urls: [URL]) -> [URL] {
    var seen = Set<String>(); var output: [URL] = []
    for url in urls where url.isFileURL && url.pathExtension.lowercased() == "countpaper" {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        if seen.insert(normalized.path.precomposedStringWithCanonicalMapping).inserted { output.append(normalized) }
    }
    return output
}

func shouldReplacePlaceholderLedger(_ sessions: [LedgerSession]) -> Bool { sessions.count == 1 && sessions[0].url == nil && !sessions[0].isDirty }
