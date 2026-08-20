import Foundation

enum LedgerSyntaxKind: Hashable { case comment, directive, date, account, amount }

struct LedgerSyntaxToken {
    let kind: LedgerSyntaxKind
    let range: NSRange
}

/// A display-only lexer. Its UTF-16 ranges are suitable for NSTextStorage and
/// never participate in parsing, saving, or source edits.
func ledgerSyntaxTokens(in text: String) -> [LedgerSyntaxToken] {
    let source = text as NSString
    var tokens: [LedgerSyntaxToken] = []; var location = 0
    while location < source.length {
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let line = source.substring(with: lineRange)
        let contentLength = line.trimmingCharacters(in: .newlines).utf16.count
        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = source.range(of: trimmed, options: [], range: contentRange)
        let contentStart = trimmedRange.location == NSNotFound ? lineRange.location : trimmedRange.location
        if trimmed.hasPrefix(";") {
            tokens.append(LedgerSyntaxToken(kind: .comment, range: contentRange))
        } else if ["账本", "本位币", "账户", "账户备注", "预算", "对账", "事件"].contains(where: { trimmed.hasPrefix($0 + " ") }) {
            let keyword = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            tokens.append(LedgerSyntaxToken(kind: .directive, range: NSRange(location: contentStart, length: keyword.utf16.count)))
        } else if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}(?:\\s|$)", options: .regularExpression) != nil {
            tokens.append(LedgerSyntaxToken(kind: .date, range: NSRange(location: contentStart, length: 10)))
        } else if !trimmed.isEmpty, line.first?.isWhitespace == true {
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let account = parts.first { tokens.append(LedgerSyntaxToken(kind: .account, range: NSRange(location: contentStart, length: String(account).utf16.count))) }
            if let amount = parts.last, Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) != nil {
                let amountRange = (line as NSString).range(of: String(amount), options: .backwards, range: NSRange(location: 0, length: contentLength))
                if amountRange.location != NSNotFound { tokens.append(LedgerSyntaxToken(kind: .amount, range: NSRange(location: lineRange.location + amountRange.location, length: amountRange.length))) }
            }
        }
        location = NSMaxRange(lineRange)
    }
    return tokens
}
