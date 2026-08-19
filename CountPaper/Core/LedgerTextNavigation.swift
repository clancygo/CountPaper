import Foundation

struct LedgerSourceInsertion: Equatable {
    let location: Int
    let text: String
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
        if trimmed == "# \(date)" { matchingHeadingEnd = NSMaxRange(lineRange); nextHeadingStart = nil }
        else if matchingHeadingEnd != nil, trimmed.hasPrefix("# ") { nextHeadingStart = lineRange.location; break }
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
        return LedgerSourceInsertion(location: insertionLocation, text: (insertionLocation > headingEnd ? newline : "") + body)
    }
    let prefix = raw.isEmpty ? "" : (raw.hasSuffix(newline) ? newline : newline + newline)
    return LedgerSourceInsertion(location: source.length, text: prefix + "# \(date)" + newline + body)
}

func ledgerSourceRange(in text: String, fromLine startLine: Int, throughLine endLine: Int) -> NSRange? {
    guard startLine >= 1, endLine >= startLine else { return nil }
    let source = text as NSString
    var line = 1; var location = 0
    while line < startLine {
        let newline = source.range(of: "\n", options: [], range: NSRange(location: location, length: source.length - location))
        guard newline.location != NSNotFound else { return nil }
        location = NSMaxRange(newline); line += 1
    }
    let start = location
    while line <= endLine {
        let newline = source.range(of: "\n", options: [], range: NSRange(location: location, length: source.length - location))
        guard newline.location != NSNotFound else { return NSRange(location: start, length: source.length - start) }
        location = NSMaxRange(newline); line += 1
    }
    return NSRange(location: start, length: location - start)
}

func ledgerLineRange(in text: String, line targetLine: Int) -> NSRange? {
    ledgerSourceRange(in: text, fromLine: targetLine, throughLine: targetLine)
}

func inheritedIndentationInsertion(in text: String, selection: NSRange) -> String? {
    let source = text as NSString
    guard selection.length == 0, selection.location <= source.length else { return nil }
    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let beforeCursor = source.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
    return (text.contains("\r\n") ? "\r\n" : "\n") + String(beforeCursor.prefix { $0 == " " || $0 == "\t" })
}

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
    } else { return inheritedIndentationInsertion(in: text, selection: selection) }
    return (text.contains("\r\n") ? "\r\n" : "\n") + prefix
}
