import Cocoa

enum CountPaperTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let canvas = adaptive(light: NSColor(calibratedWhite: 1.0, alpha: 1), dark: NSColor(calibratedRed: 0.090, green: 0.086, blue: 0.080, alpha: 1))
    static let surface = adaptive(light: NSColor(calibratedWhite: 1.0, alpha: 1), dark: NSColor(calibratedRed: 0.135, green: 0.129, blue: 0.120, alpha: 1))
    static let raisedSurface = adaptive(light: NSColor(calibratedWhite: 1.0, alpha: 1), dark: NSColor(calibratedRed: 0.165, green: 0.157, blue: 0.145, alpha: 1))
    static let softSurface = adaptive(light: NSColor(calibratedRed: 0.967, green: 0.973, blue: 0.980, alpha: 1), dark: NSColor(calibratedRed: 0.190, green: 0.181, blue: 0.166, alpha: 1))
    static let border = adaptive(light: NSColor(calibratedRed: 0.855, green: 0.878, blue: 0.902, alpha: 0.82), dark: NSColor(calibratedWhite: 0.36, alpha: 0.52))
    static let ink = adaptive(light: NSColor(calibratedRed: 0.105, green: 0.122, blue: 0.145, alpha: 1), dark: NSColor(calibratedWhite: 0.93, alpha: 1))
    static let secondaryInk = adaptive(light: NSColor(calibratedRed: 0.365, green: 0.408, blue: 0.455, alpha: 1), dark: NSColor(calibratedWhite: 0.66, alpha: 1))
    static let blue = adaptive(light: NSColor(calibratedRed: 0.13, green: 0.38, blue: 0.70, alpha: 1), dark: NSColor(calibratedRed: 0.46, green: 0.68, blue: 0.80, alpha: 1))
    static let blueSoft = adaptive(light: NSColor(calibratedRed: 0.875, green: 0.925, blue: 0.982, alpha: 1), dark: NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.37, alpha: 0.82))
    static let red = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.31, blue: 0.27, alpha: 1), dark: NSColor(calibratedRed: 0.90, green: 0.48, blue: 0.43, alpha: 1))
    static let gold = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.54, blue: 0.18, alpha: 1), dark: NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.31, alpha: 1))
}

final class CountPaperSurfaceView: NSView {
    var fillColor: NSColor
    var strokeColor: NSColor?
    var radius: CGFloat
    var hasSoftShadow: Bool

    init(fill: NSColor, stroke: NSColor? = nil, radius: CGFloat = 0, shadow: Bool = false) {
        fillColor = fill; self.strokeColor = stroke; self.radius = radius; hasSoftShadow = shadow
        super.init(frame: .zero); wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor; layer?.cornerRadius = radius
        layer?.borderWidth = strokeColor == nil ? 0 : 0.6; layer?.borderColor = strokeColor?.cgColor
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = hasSoftShadow ? 0.07 : 0
        layer?.shadowRadius = hasSoftShadow ? 12 : 0; layer?.shadowOffset = NSSize(width: 0, height: -3)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
