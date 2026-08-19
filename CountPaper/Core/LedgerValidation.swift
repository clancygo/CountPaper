import Foundation

struct LedgerAutoCorrection: Equatable {
    let text: String
    let changes: Int
}

/// Only normalizes unambiguous typography and directive spacing. It never
/// adds, removes, reorders, or rebalances a transaction.
func safeLedgerAutoCorrection(_ source: String) -> LedgerAutoCorrection {
    var text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{3000}", with: " ")
    text = text.replacingOccurrences(of: "format:countpaper/0.2", with: "format: countpaper/0.2")
    text = text.replacingOccurrences(of: "currency:CNY", with: "currency: CNY")
    text = text.replacingOccurrences(of: "format：", with: "format:")
    text = text.replacingOccurrences(of: "currency：", with: "currency:")
    let normalized = text.components(separatedBy: "\n").map { line in
        // A trailing space is meaningful while composing a Markdown item.
        if line == "- " || line == "  - " { return line }
        return line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
    }.joined(separator: "\n")
    return LedgerAutoCorrection(text: normalized, changes: normalized == source ? 0 : 1)
}

/// A parsed ledger and a form-editable ledger are deliberately different
/// concepts.  This state is used to make conservative editing decisions: a
/// user can always view source text, while structured controls only mutate
/// content that CountPaper understands completely.
enum LedgerValidationLevel: Int, Comparable {
    case valid
    case warning
    case unsafeToModify
    case fatal

    static func < (lhs: LedgerValidationLevel, rhs: LedgerValidationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct LedgerValidation: Equatable {
    let level: LedgerValidationLevel
    let diagnostics: [String]

    static func evaluate(diagnostics: [String], hasUnsupportedEditableContent: Bool = false) -> LedgerValidation {
        let level: LedgerValidationLevel
        if diagnostics.contains(where: { $0.hasPrefix("错误") || $0.localizedCaseInsensitiveContains("error") }) {
            level = .fatal
        } else if hasUnsupportedEditableContent {
            level = .unsafeToModify
        } else if !diagnostics.isEmpty {
            level = .warning
        } else {
            level = .valid
        }
        return LedgerValidation(level: level, diagnostics: diagnostics)
    }
}

enum LedgerOutlineSafety {
    /// Returns true only for a normal two-posting outline transaction whose
    /// every indented row is known to CountPaper. Any custom row means a form
    /// editor must refuse the change and preserve the source verbatim.
    static func isFormEditableTransaction(_ source: String) -> Bool {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
        let lines = normalized.components(separatedBy: "\n")
        guard lines.count >= 3, lines[0].hasPrefix("- ") else { return false }
        var postingCount = 0
        for line in lines.dropFirst() {
            guard line.hasPrefix("  - ") else { return false }
            let body = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("时间:") || body.hasPrefix("时间：") || body.hasPrefix("time:") ||
                body.hasPrefix("收款方:") || body.hasPrefix("收款方：") ||
                body.hasPrefix("标签:") || body.hasPrefix("标签：") ||
                body.hasPrefix("链接:") || body.hasPrefix("链接：") { continue }
            let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2,
                  let amount = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")),
                  amount != .zero else { return false }
            postingCount += 1
        }
        return postingCount == 2
    }
}
