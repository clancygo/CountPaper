import Foundation

/// Minimal, lossless text mutation primitives for the CountPaper format.
/// Higher-level form editors must first prove a transaction is safe to edit;
/// once they have a replacement block, this writer changes exactly that UTF-16
/// source range and leaves every other byte of user-authored text untouched.
enum LedgerWriter {
    static func replacing(_ range: NSRange, in source: String, with replacement: String) -> String? {
        let length = (source as NSString).length
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= length else { return nil }
        let updated = NSMutableString(string: source)
        updated.replaceCharacters(in: range, with: replacement)
        return updated as String
    }
}
