import Foundation

/// Lexical categories mirror CountPaper 0.2's Markdown-outline grammar.
enum LedgerSyntaxKind: Hashable {
    case comment, frontMatter, accountMarker, date, transaction, metadata, account, amount, tag, link
}

struct LedgerSyntaxToken {
    let kind: LedgerSyntaxKind
    let range: NSRange
}

/// A display-only lexer. Its UTF-16 ranges are suitable for NSTextStorage and
/// never participate in parsing, saving, or source edits.
func ledgerSyntaxTokens(in text: String) -> [LedgerSyntaxToken] {
    let source = text as NSString
    var tokens: [LedgerSyntaxToken] = []
    var location = 0
    var inFrontMatter = false
    var sawFrontMatter = false
    var inAccountSection = false

    func add(_ kind: LedgerSyntaxKind, _ location: Int, _ length: Int) {
        guard length > 0 else { return }
        tokens.append(LedgerSyntaxToken(kind: kind, range: NSRange(location: location, length: length)))
    }

    while location < source.length {
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let line = source.substring(with: lineRange)
        let contentLength = line.trimmingCharacters(in: .newlines).utf16.count
        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = source.range(of: trimmed, options: [], range: contentRange)
        let contentStart = trimmedRange.location == NSNotFound ? lineRange.location : trimmedRange.location
        if trimmed == "---" {
            add(.frontMatter, contentStart, trimmed.utf16.count)
            if !sawFrontMatter { sawFrontMatter = true; inFrontMatter = true }
            else if inFrontMatter { inFrontMatter = false }
        } else if inFrontMatter {
            if trimmed.hasPrefix(";") { add(.comment, contentStart, trimmed.utf16.count) }
            else if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon])
                add(.frontMatter, contentStart, key.utf16.count)
            }
        } else if trimmed.hasPrefix(";") {
            add(.comment, contentStart, trimmed.utf16.count)
        } else if trimmed == "@账户" || trimmed == "@accounts" {
            inAccountSection = true; add(.accountMarker, contentStart, trimmed.utf16.count)
        } else if line.hasPrefix("# ") {
            inAccountSection = false; add(.date, lineRange.location, contentLength)
        } else if line.hasPrefix("- ") {
            if inAccountSection { add(.account, lineRange.location + 2, max(0, contentLength - 2)) }
            else { add(.transaction, lineRange.location, contentLength) }
        } else if line.hasPrefix("  - ") {
            let bodyStart = lineRange.location + 4
            let body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let metadataPrefixes = ["时间:", "时间：", "time:", "收款方:", "收款方：", "标签:", "标签：", "链接:", "链接："]
            if let prefix = metadataPrefixes.first(where: { body.hasPrefix($0) }) {
                add(.metadata, bodyStart, prefix.utf16.count)
                let valueStart = bodyStart + prefix.utf16.count
                if prefix.hasPrefix("标签") {
                    let value = String(body.dropFirst(prefix.count))
                    for tag in value.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == "\t" }) {
                        let name = String(tag); let offset = (body as NSString).range(of: name).location
                        if offset != NSNotFound { add(.tag, bodyStart + offset, name.utf16.count) }
                    }
                } else if prefix.hasPrefix("链接") { add(.link, valueStart, max(0, body.utf16.count - prefix.utf16.count)) }
            } else {
                let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if let account = parts.first { add(.account, bodyStart, String(account).utf16.count) }
                if let amount = parts.last, Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) != nil {
                    let amountRange = (body as NSString).range(of: String(amount), options: .backwards)
                    if amountRange.location != NSNotFound { add(.amount, bodyStart + amountRange.location, amountRange.length) }
                }
            }
        }
        location = NSMaxRange(lineRange)
    }
    return tokens
}
