import SwiftUI
import AppKit
import CoreText

enum PreviewLayout {
    static func cardWidth(text: String, size: Double, available: Double) -> Double {
        let font = NSFont.systemFont(ofSize: size)
        let longest = String(text.prefix(512)).components(separatedBy: .newlines).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(available, min(600, max(280, ceil(longest) + 56)))
    }
}

/// Reuses the scalar measurements needed to align Library rows. Keeping CTLines
/// would retain shaped glyph runs for every font seen while scrolling.
enum PreviewTextMetrics {
    struct Measurement: Equatable {
        let ascent: Double
        let descent: Double
        let lines: Int
    }
    private static let cache = PreviewTextMetricsCache()

    static func clearCache() { cache.clear() }

    static func measure(text: String, font: CTFont, width: Double) -> Measurement {
        let visibleText = String(text.prefix(512))
        return cache.value(text: visibleText, font: font, width: width) {
            calculate(text: visibleText, font: font, width: width)
        }
    }

    static func calculate(text: String, font: CTFont, width: Double) -> Measurement {
        let attributed = NSAttributedString(string: String(text.prefix(512)), attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var offset = 0
        var lines = 0
        var ascent = Double(CTFontGetAscent(font))
        var descent = Double(CTFontGetDescent(font))
        while offset < attributed.length && lines < 3 {
            let length = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, width))
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
            var lineAscent: CGFloat = 0
            var lineDescent: CGFloat = 0
            CTLineGetTypographicBounds(line, &lineAscent, &lineDescent, nil)
            let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ascent = max(ascent, lineAscent, inkBounds.maxY)
            descent = max(descent, lineDescent, -inkBounds.minY)
            offset += length
            lines += 1
        }
        return Measurement(ascent: ascent, descent: descent, lines: lines)
    }
}

final class PreviewTextMetricsCache {
    private final class Key: NSObject {
        let text: String
        let font: CTFont
        let width: Double
        init(text: String, font: CTFont, width: Double) {
            self.text = text; self.font = font; self.width = width
        }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(text)
            hasher.combine(CFHash(font))
            hasher.combine(width.bitPattern)
            return hasher.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return width.bitPattern == other.width.bitPattern && CFEqual(font, other.font) &&
                text.utf8.elementsEqual(other.text.utf8)
        }
    }
    private final class Entry: NSObject {
        let measurement: PreviewTextMetrics.Measurement
        init(_ measurement: PreviewTextMetrics.Measurement) { self.measurement = measurement }
    }
    private let cache: NSCache<Key, Entry> = {
        let cache = NSCache<Key, Entry>()
        cache.countLimit = 384
        return cache
    }()
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func clear() {
        lock.lock()
        generation &+= 1
        cache.removeAllObjects()
        lock.unlock()
    }

    func value(text: String, font: CTFont, width: Double,
               calculate: () -> PreviewTextMetrics.Measurement) -> PreviewTextMetrics.Measurement {
        let key = Key(text: text, font: font, width: width)
        lock.lock()
        if let entry = cache.object(forKey: key) {
            lock.unlock()
            return entry.measurement
        }
        let startingGeneration = generation
        lock.unlock()
        // Font fallback and shaping can be expensive. A catalog refresh may
        // invalidate this miss while it runs; never reinsert its stale result.
        let measurement = calculate()
        lock.lock()
        if generation == startingGeneration { cache.setObject(Entry(measurement), forKey: key) }
        lock.unlock()
        return measurement
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
    var maximumLines: Int? = nil
    private func ascender(_ name: String) -> Double {
        (OpenType.font(name: name, size: size, axes: library.pro.axes[name] ?? [:], features: library.pro.features[name] ?? [:]) as NSFont).ascender
    }
    var body: some View {
        let sharedBaseline = baseline ?? ceil(max(ascender(candidate), ascender(reference))) + 4
        ZStack(alignment: .topLeading) {
            FontPreview(text: text, name: reference, size: size, wraps: true, ink: .systemCyan, variations: library.pro.axes[reference] ?? [:], features: library.pro.features[reference] ?? [:], baseline: sharedBaseline, maximumLines: maximumLines)
            FontPreview(text: text, name: candidate, size: size, wraps: true, ink: .systemOrange, variations: library.pro.axes[candidate] ?? [:], features: library.pro.features[candidate] ?? [:], baseline: sharedBaseline, maximumLines: maximumLines).opacity(0.65)
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
    var maximumLines: Int? { didSet { if maximumLines != oldValue { invalidateContent() } } }
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
        var truncated: Bool
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
        while offset < string.length && lines.count < max(1,maximumLines ?? Int.max) {
            let length = wraps ? max(1, CTTypesetterSuggestLineBreak(setter, offset, max(1, width))) : string.length
            lines.append(CTTypesetterCreateLine(setter, CFRange(location: offset, length: length)))
            offset += length
        }
        let truncated = offset < string.length
        if truncated, let last = lines.last {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string:"…",attributes:[.font:font,.foregroundColor:ink]))
            let range = CTLineGetStringRange(last)
            let tail = (string.string as NSString).substring(with:NSRange(location:range.location,length:range.length)).trimmingCharacters(in:.whitespacesAndNewlines)
            let extended = CTLineCreateWithAttributedString(NSAttributedString(string:tail+"…",attributes:[.font:font,.foregroundColor:ink]))
            lines[lines.count-1] = CTLineCreateTruncatedLine(extended,max(1,width),.end,ellipsis) ?? extended
        }
        let first = baseline ?? ceil(CTFontGetAscent(font)) + 4
        let advance = max(first + CTFontGetDescent(font) + CTFontGetLeading(font), CTFontGetSize(font) * 1.2)
        let lastDescent = lines.map { line -> Double in
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            return max(descent, -CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).minY)
        }.max() ?? CTFontGetDescent(font)
        let result = Lines(lines: lines, first: first, advance: advance, height: ceil(first + Double(max(0, lines.count - 1)) * advance + lastDescent + 6), truncated: truncated)
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
