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
    // Deliberately read-only views of document state. Session must never be a
    // second mutation path for file URL, text, dirty state or conflicts.
    var url: URL? { document.url }
    var text: String { document.text }
    var isDirty: Bool { document.isDirty }
    var signature: LedgerFileSignature? { document.signature }
    var hasExternalConflict: Bool { document.hasExternalConflict }
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
