import SwiftUI
import AppKit
import CoreText

enum PreviewLayout {
    static func cardWidth(text: String, size: Double, available: Double) -> Double {
        let font = NSFont.systemFont(ofSize: size)
        let longest = text.components(separatedBy: .newlines).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(available, max(280, ceil(longest) + 56))
    }
}

/// Both real fonts share a first baseline; each retains its own glyph advances and wrapping.
struct OverlayPreview: View {
    let text: String
    let candidate: String
    let reference: String
    let size: Double
    @ObservedObject var library: Library
    var baseline: Double? = nil
    private func ascender(_ name: String) -> Double {
        (OpenType.font(name: name, size: size, axes: library.pro.axes[name] ?? [:], features: library.pro.features[name] ?? [:]) as NSFont).ascender
    }
    var body: some View {
        let sharedBaseline = baseline ?? ceil(max(ascender(candidate), ascender(reference))) + 4
        ZStack(alignment: .topLeading) {
            FontPreview(text: text, name: reference, size: size, wraps: true, ink: .systemCyan, variations: library.pro.axes[reference] ?? [:], features: library.pro.features[reference] ?? [:], baseline: sharedBaseline)
            FontPreview(text: text, name: candidate, size: size, wraps: true, ink: .systemOrange, variations: library.pro.axes[candidate] ?? [:], features: library.pro.features[candidate] ?? [:], baseline: sharedBaseline).opacity(0.65)
        }.frame(maxWidth: .infinity, minHeight: size * 1.5, alignment: .topLeading)
    }
}

/// Draws Core Text lines at explicit baselines, without NSTextField's font-specific cell insets.
final class BaselineTextView: NSView {
    var text = "" { didSet { if text != oldValue { invalidateContent() } } }
    var font = CTFontCreateWithName("Helvetica" as CFString, 16, nil) { didSet { invalidateContent() } }
    var ink = NSColor.labelColor { didSet { if !ink.isEqual(oldValue) { invalidateContent() } } }
    var paper: NSColor? { didSet { needsDisplay = true } }
    var wraps = false { didSet { if wraps != oldValue { invalidateContent() } } }
    var baseline: Double? { didSet { if baseline != oldValue { invalidateContent() } } }
    private var cachedLayout: (width: Double, content: Lines)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    struct Lines {
        var lines: [CTLine]
        var first: Double
        var advance: Double
        var height: Double
    }
    func invalidateContent() {
        cachedLayout = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }
    func layout(width: Double) -> Lines {
        if let cachedLayout, cachedLayout.width == width { return cachedLayout.content }
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let setter = CTTypesetterCreateWithAttributedString(string)
        var lines: [CTLine] = []
        var offset = 0
        while offset < string.length {
            let length = wraps ? max(1, CTTypesetterSuggestLineBreak(setter, offset, max(1, width))) : string.length
            lines.append(CTTypesetterCreateLine(setter, CFRange(location: offset, length: length)))
            offset += length
        }
        let first = baseline ?? ceil(CTFontGetAscent(font)) + 4
        let advance = max(first + CTFontGetDescent(font) + CTFontGetLeading(font), CTFontGetSize(font) * 1.2)
        let lastDescent = lines.map { line -> Double in
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            return max(descent, -CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).minY)
        }.max() ?? CTFontGetDescent(font)
        let result = Lines(lines: lines, first: first, advance: advance, height: ceil(first + Double(max(0, lines.count - 1)) * advance + lastDescent + 6))
        cachedLayout = (width, result)
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        if let paper { paper.setFill(); bounds.fill() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let content = layout(width: bounds.width)
        context.saveGState()
        context.textMatrix = .identity
        for (index, line) in content.lines.enumerated() {
            context.textPosition = CGPoint(x: 0, y: bounds.height - content.first - Double(index) * content.advance)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
