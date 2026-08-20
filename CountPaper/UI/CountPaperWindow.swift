import Cocoa

/// Keeps Command-W as a non-destructive window-shelving action.
final class CountPaperWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
