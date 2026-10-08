import AppKit
import CoreText

enum PreviewRenderingChecks {
    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() {
                throw NSError(domain: "Typefield.PreviewRenderingCheck", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let view = BodyColumnsNativeView(frame: NSRect(x: 0, y: 0, width: 740, height: 520))
        let text = String(repeating: "Body text flows across columns. Café العربية हिन्दी.\n\n", count: 30)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        @discardableResult
        func update(_ content: String = text, font nextFont: CTFont? = nil,
                    columns: Int = 2, width: Double = 740, lineHeight: Double = 1.3,
                    tracking: Double = 0, alignment: NSTextAlignment = .left,
                    ink: NSColor = .labelColor, paper: NSColor = .textBackgroundColor) -> Bool {
            view.update(text: content, font: nextFont ?? font, columns: columns, width: width,
                        lineHeight: lineHeight, tracking: tracking, alignment: alignment,
                        ink: ink, paper: paper)
        }
        try check(update(), "The initial body layout must configure its text views")
        let first = view.subviews[0] as! NSTextView
        let second = view.subviews[1] as! NSTextView
        let storage = first.textStorage!
        let layout = first.layoutManager!
        try check(first.textStorage === second.textStorage && first.layoutManager === second.layoutManager,
                  "Body columns must flow through a single TextKit graph")
        try check(storage.string == text && first.frame.width == 358 && second.frame.minX == 382,
                  "The body string and fixed column gap must survive initialization")
        for container in layout.textContainers { layout.ensureLayout(for: container) }
        let firstRange = layout.glyphRange(for: layout.textContainers[0])
        let secondRange = layout.glyphRange(for: layout.textContainers[1])
        try check(firstRange.length > 0 && secondRange.length > 0 && NSMaxRange(firstRange) == secondRange.location,
                  "Text must continue into the next column without repetition or omission")

        let selection = NSRange(location: 12, length: 8)
        first.setSelectedRange(selection)
        for _ in 0..<100 {
            try check(!update(font: CTFontCreateCopyWithAttributes(font, 18, nil, nil)),
                      "Equivalent body input must skip TextKit reconfiguration")
        }
        try check(view.subviews[0] === first && first.textStorage === storage && first.layoutManager === layout &&
                    first.selectedRange() == selection,
                  "Unrelated inspector changes must preserve text views, layout and body selection")

        try check(update(width: 600), "A changed width must update the columns")
        try check(view.subviews[0] === first && first.frame.width == 288 && second.frame.minX == 312 &&
                    first.textContainer?.containerSize.width == 288 && first.selectedRange() == selection,
                  "Width changes must resize the retained containers and preserve selection")
        let largeFont = CTFontCreateCopyWithAttributes(font, 22, nil, nil)
        try check(update(font: largeFont, lineHeight: 1.6, tracking: 1.5, alignment: .justified, ink: .systemRed),
                  "Changed font, paragraph attributes and ink must update the body")
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        let paragraph = attributes[.paragraphStyle] as! NSParagraphStyle
        try check((attributes[.font] as? NSFont)?.pointSize == 22 &&
                    paragraph.lineHeightMultiple == 1.6 && paragraph.paragraphSpacing == 14 &&
                    paragraph.alignment == .justified && (attributes[.kern] as? Double) == 1.5 &&
                    (attributes[.foregroundColor] as? NSColor)?.isEqual(NSColor.systemRed) == true,
                  "The retained storage must receive all changed typography and color inputs")
        try check(first.selectedRange() == selection,
                  "Typography changes must preserve selection in unchanged body text")

        update()
        let oldParagraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as AnyObject
        try check(update(paper: .systemYellow), "Changed paper must update the body background")
        let newParagraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as AnyObject
        try check(first.backgroundColor.isEqual(NSColor.systemYellow) && second.backgroundColor.isEqual(NSColor.systemYellow) &&
                    oldParagraph === newParagraph && first.selectedRange() == selection,
                  "A paper-only change must preserve typography and selection")

        try check(update(columns: 3, width: 900), "A changed column count must rebuild the column containers")
        let three = view.subviews.compactMap { $0 as? NSTextView }
        try check(three.count == 3 && layout.textContainers.count == 3 &&
                    three.allSatisfy { $0.textStorage === storage && $0.frame.width == 284 } &&
                    three[2].frame.minX == 616 && three[0].selectedRange() == selection,
                  "Column changes must retain the shared storage and selection with correct geometry")
        try check(update("Short"), "Replacement text must update the stored body")
        try check(storage.string == "Short" && (view.subviews[0] as! NSTextView).selectedRange() == NSRange(location: 0, length: 0),
                  "A replacement body must reset selection safely for shorter text")
        try check(update("") && storage.length == 0 && layout.textContainers.count == 2,
                  "Empty body text must remain valid in the retained layout")
        update("é")
        try check(update("e\u{301}") && storage.length == 2,
                  "Canonically equivalent replacement text must retain its exact Unicode representation")
        print("PASS: body previews retain TextKit layout and selection across unrelated updates, and refresh text, typography, columns and colors.")

        let serif = CTFontCreateWithName("Times-Roman" as CFString, 56, nil)
        var metricFonts = [font, serif, CTFontCreateCopyWithAttributes(font, 57, nil, nil)]
        for enabled in [0, 1] {
            let attributes: [CFString: Any] = [kCTFontFeatureSettingsAttribute:
                [[kCTFontOpenTypeFeatureTag: "liga", kCTFontOpenTypeFeatureValue: enabled] as [CFString: Any]]]
            metricFonts.append(CTFontCreateCopyWithAttributes(serif, 56, nil,
                                                              CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)))
        }
        let variable = NSFont.systemFont(ofSize: 56) as CTFont
        if let axis = (CTFontCopyVariationAxes(variable) as? [[String: Any]])?.first,
           let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? Int,
           let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
           let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double {
            for value in [minimum, maximum] {
                let descriptor = CTFontDescriptorCreateWithAttributes(
                    [kCTFontVariationAttribute: [identifier: value]] as CFDictionary)
                metricFonts.append(CTFontCreateCopyWithAttributes(variable, 56, nil, descriptor))
            }
        }
        let texts = ["", "H", "office affine ffi", "Café العربية हिन्दी 日本語 한글", "first\nsecond\nthird\nfourth",
                     String(repeating: "Long mixed preview العربية हिन्दी 日本語. ", count: 25), "e\u{301}é"]
        var measurements = 0
        PreviewTextMetrics.clearCache()
        for metricFont in metricFonts {
            for sample in texts {
                for width in [1.0, 180, 280, 280.25] {
                    let expected = PreviewTextMetrics.calculate(text: sample, font: metricFont, width: width)
                    let measured = PreviewTextMetrics.measure(text: sample, font: metricFont, width: width)
                    let repeated = PreviewTextMetrics.measure(text: sample,
                                                             font: CTFontCreateCopyWithAttributes(metricFont, CTFontGetSize(metricFont), nil, nil),
                                                             width: width)
                    try check(measured == expected && repeated == expected && measured.lines <= 3,
                              "Cached measurements must match native shaping for all text, font and exact-width inputs")
                    measurements += 1
                }
            }
        }

        let cache = PreviewTextMetricsCache()
        var calculations = 0
        func lookup(_ sample: String = "office ffi", font: CTFont = serif, width: Double = 280) -> PreviewTextMetrics.Measurement {
            cache.value(text: sample, font: font, width: width) {
                calculations += 1
                return PreviewTextMetrics.calculate(text: sample, font: font, width: width)
            }
        }
        _ = lookup()
        _ = lookup(font: CTFontCreateCopyWithAttributes(serif, 56, nil, nil))
        try check(calculations == 1, "Equivalent CTFont values must share a cached measurement")
        _ = lookup(width: 280.25)
        _ = lookup(font: font)
        _ = lookup("office ffi changed")
        try check(calculations == 4, "Changed width, font and text must each receive fresh measurements")
        let beforeVariants = calculations
        for variant in metricFonts.suffix(metricFonts.count - 3) { _ = lookup(font: variant) }
        // Core Text normalizes an explicitly enabled default ligature setting
        // back to the base font. Such equivalent instances should share a hit.
        let changedVariants = metricFonts.suffix(metricFonts.count - 3).filter { !CFEqual($0, serif) }.count
        try check(calculations == beforeVariants + changedVariants,
                  "Feature and variable-axis font instances must keep separate cached measurements")
        _ = lookup("é")
        _ = lookup("e\u{301}")
        try check(calculations == beforeVariants + changedVariants + 2,
                  "Cache keys must distinguish exact Unicode input representations")
        cache.clear()
        let beforeRefresh = calculations
        _ = lookup()
        try check(calculations == beforeRefresh + 1, "A catalog refresh must discard existing measurements")

        // Recreate a catalog invalidation arriving while a miss is still shaping.
        cache.clear()
        _ = cache.value(text: "office ffi", font: serif, width: 280) {
            cache.clear()
            return PreviewTextMetrics.Measurement(ascent: -1, descent: -1, lines: -1)
        }
        let afterConcurrentClear = lookup()
        try check(afterConcurrentClear.ascent > 0 && calculations == beforeRefresh + 2,
                  "A measurement started before catalog invalidation must not repopulate the cleared cache")
        print("PASS: \(measurements) cached Library measurements match native shaping; font settings, exact width/text and catalog invalidation remain isolated.")
    }
}
