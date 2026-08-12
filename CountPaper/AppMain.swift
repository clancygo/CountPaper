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
        // On newer macOS versions the launch notification can be delivered
        // before a programmatic delegate observes it. Finish the AppKit launch
        // explicitly, then build the only real application window.
        app.finishLaunching()
        appDelegate.launchApplicationInterface()
        app.run()
    }
}
