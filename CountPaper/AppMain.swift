import Cocoa

@main
struct CountPaperMain {
    // NSApplication keeps its delegate weakly. Holding it for the process
    // lifetime prevents an optimised build from releasing the delegate during
    // launch and leaving only AppKit's empty fallback window.
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
