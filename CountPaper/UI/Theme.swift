import Cocoa

enum CountPaperTheme {
    // CountPaper owns the paper and warning hues. Everything that describes
    // macOS UI semantics (text, separators, selection and accent) is supplied
    // by AppKit so Appearance, Increase Contrast and the user's accent colour
    // are respected automatically.
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// The one brand-owned base: white paper in light appearance, a warm
    /// charcoal paper in dark appearance.
    static let paper = adaptive(light: .white, dark: NSColor(calibratedRed: 0.090, green: 0.086, blue: 0.080, alpha: 1))
    static let canvas = paper
    static let surface = NSColor.textBackgroundColor
    static let raisedSurface = NSColor.controlBackgroundColor
    static let softSurface = NSColor.underPageBackgroundColor

    // System semantic colours — do not replace these with calibrated RGB.
    static let border = NSColor.separatorColor
    static let ink = NSColor.labelColor
    static let secondaryInk = NSColor.secondaryLabelColor
    static let accent = NSColor.controlAccentColor
    static let accentSoft = NSColor.selectedContentBackgroundColor

    // Compatibility names keep call sites legible while they inherit the
    // system accent and selection behaviour above.
    static let blue = accent
    static let blueSoft = accentSoft
    static let red = NSColor.systemRed
    static let warning = adaptive(light: NSColor(calibratedRed: 0.72, green: 0.54, blue: 0.18, alpha: 1), dark: NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.31, alpha: 1))
    static let gold = warning
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
