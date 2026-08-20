import Cocoa

/// Source editor behaviour that protects the insertion point from AppKit's
/// transient whole-line selection and continues the 0.2 outline on Return.
final class LedgerTextView: NSTextView {
    private var insertionGeneration = 0

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        insertionGeneration += 1
        let generation = insertionGeneration
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let insertedLength: Int
        if let text = insertString as? String { insertedLength = (text as NSString).length }
        else if let attributed = insertString as? NSAttributedString { insertedLength = attributed.length }
        else { super.insertText(insertString, replacementRange: replacementRange); return }
        let sourceBeforeInsertion = string as NSString
        let editedLineBeforeInsertion = sourceBeforeInsertion.lineRange(for: NSRange(location: min(range.location, sourceBeforeInsertion.length), length: 0))
        let previousLineBeforeInsertion = editedLineBeforeInsertion.location > 0 ? sourceBeforeInsertion.lineRange(for: NSRange(location: editedLineBeforeInsertion.location - 1, length: 0)) : nil
        super.insertText(insertString, replacementRange: replacementRange)
        let caret = NSRange(location: range.location + insertedLength, length: 0)
        for delay in [0.02, 0.22] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.insertionGeneration == generation, caret.location <= (self.string as NSString).length else { return }
                let lineRange = (self.string as NSString).lineRange(for: NSRange(location: caret.location, length: 0))
                let selection = self.selectedRange()
                let current = selection.length > 0 && selection.location >= lineRange.location && NSMaxRange(selection) <= NSMaxRange(lineRange)
                let previous = previousLineBeforeInsertion.map { selection.length > 0 && selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0) } ?? false
                guard current || previous else { return }
                self.setSelectedRange(caret); self.scrollRangeToVisible(caret)
            }
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let insertion = outlineNewlineInsertion(in: string, selection: selectedRange()) else { super.insertNewline(sender); return }
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: range, with: insertion)
        didChangeText()
        let caret = NSRange(location: range.location + (insertion as NSString).length, length: 0)
        setSelectedRange(caret); scrollRangeToVisible(caret)
    }
}
