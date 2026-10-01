import Foundation
import AppKit
import CoreText

enum StudioChecks {
    static func stress() throws {
        let font=NSFont(name:"Helvetica",size:24)!
        let style=NSMutableParagraphStyle();style.firstLineHeadIndent=40
        func width(_ text: String) -> Double {
            CanvasBoardLayout.minimumTextFrameWidth(for:CanvasElement(rect:.zero,text:NSAttributedString(string:text,attributes:[.font:font,.paragraphStyle:style])))
        }
        func token(_ value: String) -> Double { CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:[.font:font])),nil,nil,nil) }
        try verify(width("   i abcdefghijklmnop") == ceil(max(token("i")+40,token("abcdefghijklmnop"))),"Only the first token receives paragraph indent")
        try verify(width("i\r\n   abcdefghijklmnop") == ceil(token("abcdefghijklmnop")+40),"CRLF paragraphs must retain first-line indent")
        try verify(width("i\u{2029}   abcdefghijklmnop") == ceil(token("abcdefghijklmnop")+40),"Unicode paragraph separators must retain indent")
        let started=Date()
        let measured=width(String(repeating:"Word ",count:40_000))
        let elapsed=Date().timeIntervalSince(started)
        try verify(measured == ceil(token("Word")+40),"Long paragraph sizing changed the first token width")
        try verify(elapsed<5,"200,000-character width scan exceeded five seconds")
        var direction=TypeDirection(name:"Long paragraph stress",fonts:["Helvetica"]);direction.canvas = .editorial
        direction.styles[TypeRole.body.rawValue]!.text=String(repeating:"Word ",count:40_000)
        CanvasPlanCache.removeAll()
        let planStart=Date(),plan=CanvasPlanCache.plan(for:direction)
        let planElapsed=Date().timeIntervalSince(planStart)
        try verify(!plan.elements.isEmpty && plan.size.width.isFinite && plan.size.height.isFinite,"Long paragraph layout returned invalid geometry")
        try verify(planElapsed<10,"Long paragraph board layout exceeded ten seconds")
        let body=plan.elements.filter { $0.role == .body }
        try verify(!body.isEmpty && body.allSatisfy { $0.text?.string == direction.style(.body).text },"Editorial template multiplied or truncated a long article")
        try verify(CanvasPlan.editorialSample("Short copy",repetitions:4)==Array(repeating:"Short copy",count:4).joined(separator:"\n\n"),"Short editorial sample repetition changed")
        let warmStart=Date()
        for _ in 0..<20 { _ = CanvasPlanCache.plan(for:direction) }
        let warmElapsed=Date().timeIntervalSince(warmStart)
        try verify(warmElapsed<1,"Long paragraph layout was not cached across inspector updates")
        print("STRESS TEXT: 200,000 characters, width scan \(String(format:"%.3f",elapsed))s, full board \(String(format:"%.3f",planElapsed))s, 20 cached reads \(String(format:"%.3f",warmElapsed))s")
        let view=BaselineTextView();view.font=CTFontCreateWithName("Helvetica" as CFString,26,nil);view.wraps=true;view.maximumLines=3
        view.text=String(repeating:"ABO ",count:2500)
        let bounded=view.layout(width:280)
        try verify(bounded.lines.count==3 && bounded.truncated && bounded.height<150,"Library preview did not bound its layout")
        view.text="ABO"
        try verify(view.layout(width:280).lines.count==1 && !view.layout(width:280).truncated,"Short preview retained stale overflow state")
        try verify(PreviewLayout.cardWidth(text:String(repeating:"ABO ",count:2500),size:26,available:1800)==600,"Long preview monopolized the grid width")
    }
    @discardableResult static func handoff(catalog: [Family], parent: URL) throws -> URL {
        var board = TypeBoard(); board.name = "Studio <handoff> & review"
        var canvas = TypeDirection(name: "Canvas 1")
        canvas.styles[TypeRole.display.rawValue]!.text = "A <script>alert('never')</script> & \"quote\" \\ $name café 🖋\nSecond line"
        canvas.styles[TypeRole.display.rawValue]!.axes = [2003265652: 520]
        canvas.styles[TypeRole.body.rawValue]!.features = ["liga": 0]
        canvas.styles[TypeRole.body.rawValue]!.kerning = false
        canvas.styles[TypeRole.body.rawValue]!.lineHeight = 29
        board.directions = [canvas, canvas.copy(name: "Canvas 2")]
        board.directions[1].styles[TypeRole.caption.rawValue]!.fontName = "Missing Font </style><script>bad</script>"
        let unscaledEntryCount = DeveloperHandoff.entries([board]).count
        board.directions[1].canvasScale = 2
        try verify(DeveloperHandoff.entries([board]).count == unscaledEntryCount, "Canvas scaling must not duplicate baseline and rendered handoff styles")
        let folder = try DeveloperHandoff.write(title: board.name, boards: [board], catalog: catalog, parent: parent)
        func read(_ name: String) throws -> String { try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        try verify(files.count == 11 && files.contains("Typography.swift") && files.contains("Typography.kt"), "Complete handoff package")
        let fontFiles = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("fonts").path)
        try verify(fontFiles.isEmpty, "Never redistribute font binaries")
        let tokens = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("tokens.json"))) as! [String: Any]
        try verify(tokens["format"] as? String == "FontShelf typography handoff", "Version-1 handoff format stays compatible")
        let swiftStarter = try read("Typography.swift"), composeStarter = try read("Typography.kt")
        try verify(swiftStarter.contains("TypefieldTypography") && composeStarter.contains("TypefieldTypography"), "Generated native types use the new product name")
        let styles = tokens["typography"] as! [String: [String: Any]]
        try verify(styles.count >= 14 && Set(styles.keys).count == styles.count, "All canvases, unique styles")
        let value = styles["b1-c1-display"]!["$value"] as! [String: Any]
        try verify((value["axes"] as? [String: Double])?["wght"] == 520, "Variable axes preserved")
        let scaledDisplay = styles["b1-c2-display"]!["$value"] as! [String: Any]
        let scaledBody = styles["b1-c2-body"]!["$value"] as! [String: Any]
        try verify((scaledDisplay["fontSize"] as? Double) == 128 && abs((scaledDisplay["lineHeight"] as? Double ?? 0) - 172.8) < 0.001 && (scaledBody["fontSize"] as? Double) == 36 && (scaledBody["lineHeight"] as? Double) == 58, "Scaled canvas typography must use rendered font sizes and line heights")
        let html = try read("index.html"), css = try read("typography.css")
        try verify(!html.contains("<script>") && html.contains("&lt;script&gt;") && html.contains("café 🖋"), "HTML must escape sample text and retain Unicode")
        try verify(html.contains("Typefield: Developer handoff") && !html.contains("FONTSHELF / DEVELOPER HANDOFF"), "Visible handoff branding must use Typefield")
        try verify(css.contains("clamp(") && css.contains("\"wght\" 520") && css.contains("font-display: swap") && css.contains("font-feature-settings: \"kern\" 0, \"liga\" 0") && css.contains("font-kerning: none"), "CSS carries axes, features, kerning and loading policy")
        try verify(css.contains("--b1-c2-display-size: \(DeveloperHandoff.fluid(128))") && html.contains("128 px") && swiftStarter.contains("\"b1-c2-display\": Style(postScriptName:") && swiftStarter.contains("size: 128") && composeStarter.contains("fontSize = 128.sp"), "CSS, specimen and native starters must agree with scaled canvas typography")
        try verify(DeveloperHandoff.fluid(16) == "1rem" && DeveloperHandoff.number(0) == "0" && DeveloperHandoff.number(100) == "100", "Fluid scale and numeric precision")
        let manifest = try read("fonts.json")
        try verify(!manifest.contains("/Users/") && manifest.contains("\"availableOnExportingMac\" : false"), "Missing fonts marked without leaking local paths")
        let restored = try JSONDecoder().decode([TypeBoard].self, from: JSONSerialization.data(withJSONObject: tokens["sourceBoards"]!))
        try verify(restored == [board], "Handoff retains exact source design data")
        let second = try DeveloperHandoff.write(title: board.name, boards: [board], catalog: catalog, parent: parent)
        try verify(second != folder && FileManager.default.fileExists(atPath: folder.path), "Repeated export must not overwrite")
        print("PASS: developer handoff files, all canvases, axes/features, source round-trip, escaping, font licensing safeguards and no-overwrite export.")
        return folder
    }
    static func verify(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion failed", line: Int = #line) throws {
        if !condition() { throw NSError(domain: "FontShelfCheck", code: line, userInfo: [NSLocalizedDescriptionKey: "\(message) (StudioChecks.swift:\(line))"]) }
    }
    /// Compare the actual arrangement of text and shapes, without making copy,
    /// section titles, colors or exact pixel positions part of the contract.
    static func templateGeometrySignature(_ plan: CanvasPlan) -> String {
        let width = max(1, plan.artboardSize.width), height = max(1, plan.artboardSize.height)
        return plan.elements.map { element in
            let kind = element.text != nil ? "T" : element.image != nil ? "I" : "S"
            let column = min(7, max(0, Int(element.rect.midX / width * 8)))
            let row = min(15, max(0, Int(element.rect.midY / height * 16)))
            let span = min(7, max(0, Int(element.rect.width / width * 8)))
            return "\(kind)\(column):\(row):\(span)"
        }.joined(separator: "|")
    }
    static func verifyTemplateTextGeometry(_ plan: CanvasPlan, kind: CanvasKind, width: Double) throws {
        let text = plan.elements.filter { $0.text != nil }
        let label = "\(kind.rawValue) at \(Int(width)) px"
        for element in text {
            let measured = element.text!.boundingRect(with: CGSize(width: max(1, element.rect.width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            try verify(measured.height <= element.rect.height + 5, "\(label): a text frame is shorter than its rendered content")
            if let section = plan.sections.first(where: { $0.id == element.sectionID }) {
                try verify(element.rect.minY >= section.rect.minY - 1 && element.rect.maxY <= section.rect.maxY + 1,
                           "\(label): editable text extends beyond its section and may collide after reordering")
            }
        }
        // Text may deliberately sit on top of a shape or image, but separate
        // text objects should never cover each other's rendered glyph area.
        let bounds = text.map { plan.textBounds(for: $0) }
        for first in text.indices {
            for second in text.indices where second > first {
                let overlap = bounds[first].intersection(bounds[second])
                try verify(overlap.isNull || overlap.width < 4 || overlap.height < 4,
                           "\(label): rendered text objects overlap (\(text[first].textID ?? text[first].sectionID), \(text[second].textID ?? text[second].sectionID))")
            }
        }
    }
    static func integration(source: URL) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-activation-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(source.lastPathComponent)
        let manager = ActivationManager(journal: root.appendingPathComponent("activation.json"))
        defer {
            if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: source, to: target) }
            manager.clear(restore: false)
            CTFontManagerUnregisterFontsForURL(target as CFURL, .session, nil)
            CTFontManagerUnregisterFontsForURL(target as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: root)
        }
        func check(_ condition: Bool, _ message: String) throws { if !condition { throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
        let watcher = FolderWatcher()
        var initialized = false, changes = 0
        watcher.configure(roots: [root.path], initialized: { _, _ in initialized = true }) { _, _ in changes += 1 }
        func wait(_ predicate: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(10)
            while !predicate() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            return predicate()
        }
        try check(wait { initialized }, "Initial folder scan did not finish")
        try check(changes == 0, "Initial folder scan must not trigger a redundant library reload")
        try FileManager.default.copyItem(at: source, to: target)
        try check(wait { changes > 0 }, "Watcher did not detect a new font")
        let count = FontCatalog.registerFolder(root.path)
        try check(count == 1 && CTFontManagerGetScopeForURL(target as CFURL) == .process, "Font did not register for preview")
        _ = try manager.activate(target)
        try check(manager.owns(target) && CTFontManagerGetScopeForURL(target as CFURL) == .session, "Session activation failed")
        let overlappingProcessScope = CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
        let processWinsScopeLookup = overlappingProcessScope && CTFontManagerGetScopeForURL(target as CFURL) == .process
        let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(target as CFURL) as? [CTFontDescriptor])!.first!
        let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as! String
        let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--font-available", name]
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0, "Session font was not visible to a separate process")
        try manager.deactivate(target)
        try check(!manager.owns(target) && CTFontManagerGetScopeForURL(target as CFURL) == .process, "Deactivation did not restore preview scope")
        if overlappingProcessScope {
            CTFontManagerUnregisterFontsForURL(target as CFURL, .process, nil)
            try check(CTFontManagerGetScopeForURL(target as CFURL) != .session, "Deactivation left a hidden session registration after overlapping process registration")
            print("PASS: overlapping process registration during session activation (scope lookup preferred process: \(processWinsScopeLookup)).")
        } else {
            print("SKIP: CoreText rejected overlapping process registration during session activation; dual-scope regression path was not exercised.")
        }
        let prior = changes
        try FileManager.default.removeItem(at: target)
        try check(wait { changes > prior }, "Watcher did not detect deletion")
        FontCatalog.reconcileFolders([root.path])
        try check(FontCatalog.registeredFiles[target.path] == nil, "Removed font remained registered")
        try check(!FontCatalog.scan().flatMap(\.faces).contains { $0.name == name }, "Removed font remained in the fresh catalog")
        withExtendedLifetime(watcher) {}
        print("PASS: live recursive watcher, original-file preview, temporary activation visible to a separate process, deactivation and removal reconciliation.")
    }
    static func run(catalog: [Family]) throws {
        try verify(StudioHexColor.parse(" #4f6b91 \n") == "4F6B91", "Pasted hex colors must normalize before saving")
        try verify(StudioHexColor.parse("#aBc") == "AABBCC", "Short CSS hex colors must expand to saved RGB values")
        try verify(StudioHexColor.parse("4F6B91") == "4F6B91", "Hex colors without # must be accepted")
        try verify(NSColor(hex: "4F6B91").rgbHex == "4F6B91", "Color picker channels must round-trip to the same hex value")
        for invalid in ["", "#", "#12", "#1234", "#11223344", "#12FG56", "##123456"] {
            try verify(StudioHexColor.parse(invalid) == nil, "Invalid hex drafts must not be saved: " + invalid)
        }
        try verify(abs((SpacesProofing.contrastRatio(ink: "000000", paper: "FFFFFF") ?? 0) - 21) < 0.001)
        try verify(abs((SpacesProofing.contrastRatio(ink: "777777", paper: "FFFFFF") ?? 0) - 4.478) < 0.01)
        try verify(SpacesProofing.contrastRatio(ink: "bad", paper: "FFFFFF") == nil)
        try verify(SpacesProofing.longestLine("Short\nA longer line") == 13)
        let newCanvas = TypeDirection()
        try verify(newCanvas.paper == "FFFFFF" && CanvasPlan(direction: newCanvas).paper.rgbHex == "FFFFFF", "New Spaces canvases must start with a neutral white background")
        var savedWarmCanvas = newCanvas
        savedWarmCanvas.paper = "F5F2EA"
        let restoredWarmCanvas = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(savedWarmCanvas))
        try verify(restoredWarmCanvas.paper == "F5F2EA" && CanvasPlan(direction: restoredWarmCanvas).paper.rgbHex == "F5F2EA", "Existing canvas background colors must survive loading and rendering")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-studio-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try handoff(catalog: catalog, parent: root)
        let store = StudioStore(url: root.appendingPathComponent("spaces.json"))
        let space = store.addSpace("Client")!, boardID = store.addBoard(space: space, fonts: ["Georgia", "Helvetica"])!
        var board = store.state.spaces[0].boards[0]
        let pairSeed = board.directions[0]
        try verify(pairSeed.style(.display).fontName == "Georgia" && pairSeed.style(.heading).fontName == "Georgia" && pairSeed.style(.body).fontName == "Helvetica", "Two-font typeboards must seed display and supporting roles predictably")
        let multiSeed = TypeDirection(fonts: ["Display", "Heading", "Subheading", "Body", "UI", "Mono"])
        try verify(multiSeed.style(.display).fontName == "Display" && multiSeed.style(.heading).fontName == "Heading" && multiSeed.style(.subheading).fontName == "Subheading" && multiSeed.style(.body).fontName == "Body" && multiSeed.style(.label).fontName == "UI" && multiSeed.style(.mono).fontName == "Mono", "Multi-font typeboards must put every selected font into an initial role")
        var mappedSeed = TypeDirection(fonts: ["One", "Two"], roleFonts: [TypeRole.display.rawValue: "Two", TypeRole.body.rawValue: "One"])
        try verify(mappedSeed.style(.display).fontName == "Two" && mappedSeed.style(.body).fontName == "One" && mappedSeed.style(.caption).fontName == "Two", "Typeboard role choices must override suggestions")
        var remappedBody = mappedSeed.style(.body); remappedBody.fontName = "Changed later"; mappedSeed.styles[TypeRole.body.rawValue] = remappedBody
        try verify(mappedSeed.style(.body).fontName == "Changed later", "Initial typeboard role choices must remain freely editable")
        let seedDraft = TypeboardSeedDraft(fonts: ["One", "Two", "One"], source: "Fixture")
        try verify(seedDraft.fonts == ["One", "Two"] && seedDraft.suggested.count == TypeRole.allCases.count, "Typeboard setup must deduplicate candidates and suggest every role")
        try verify(board.canvasName(board.directions[0]) == "Canvas 1")
        var legacyBoard = board; legacyBoard.directions[0].name = "Direction A copy"
        try verify(legacyBoard.canvasName(legacyBoard.directions[0]) == "Canvas 1" && legacyBoard.directions[0].name == "Direction A copy", "Legacy canvas labels must not rewrite saved names")
        try verify(CanvasZoomInput.clamped(0.001) == 0.1 && CanvasZoomInput.clamped(12) == 4 && CanvasZoomInput.clamped(.nan) == 1, "Zoom bounds")
        var textCanvas = TypeDirection()
        let originalPlan = CanvasPlan(direction: textCanvas)
        let textElement = originalPlan.elements.first { $0.role == .label }!
        let preciseTextBounds = originalPlan.textBounds(for: textElement)
        try verify(originalPlan.text(at: NSPoint(x: preciseTextBounds.midX, y: preciseTextBounds.midY))?.textID == textElement.textID, "Exact text hit-test must select the clicked text element")
        let proofText = NSAttributedString(string: "abcdefghij klmnopqrst", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.black])
        let narrowProof = CanvasElement(rect: CGRect(x: 0, y: 0, width: 70, height: 100), text: proofText, sectionID: "proof")
        let wideProof = CanvasElement(rect: CGRect(x: 0, y: 0, width: 400, height: 100), text: proofText, sectionID: "proof")
        let narrowLines = CanvasProofing.renderedLines(for: narrowProof)!, wideLines = CanvasProofing.renderedLines(for: wideProof)!
        try verify(narrowLines.count > wideLines.count && narrowLines.longestCharacters < wideLines.longestCharacters, "Proofing must count actual wrapped line fragments in the rendered text frame")
        var contrastPlan = CanvasPlan(arrangement: [], width: 120)
        contrastPlan.paper = .white
        contrastPlan.elements = [CanvasElement(rect: CGRect(x: 0, y: 0, width: 120, height: 100), color: NSColor(white: 0.95, alpha: 1)), narrowProof]
        let lightContrast = CanvasProofing.contrast(for: narrowProof, in: contrastPlan)!
        contrastPlan.elements[0].color = .black
        let darkContrast = CanvasProofing.contrast(for: narrowProof, in: contrastPlan)!
        try verify(lightContrast.minimum > 4.5 && darkContrast.minimum < 1.1, "Proofing must sample overlapping fills behind the selected text instead of canvas paper alone")
        contrastPlan.elements.append(CanvasElement(rect: narrowProof.rect, color: .gray))
        try verify(CanvasProofing.contrast(for: narrowProof, in: contrastPlan)?.overlaid == true, "Proofing must disclose artwork painted over the text frame")
        let accessibleCanvas = CanvasNativeView(plan: originalPlan)
        accessibleCanvas.directionID = UUID()
        var accessibleSelection: String?
        accessibleCanvas.onTextSelect = { accessibleSelection = $0.textID }
        accessibleCanvas.updateAccessibilityItems()
        let accessibleChildren = accessibleCanvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        let accessibleText = accessibleChildren.first { $0.accessibilityIdentifier() == "spaces-text-" + textElement.textID! }
        try verify(accessibleText?.accessibilityPerformPress() == true && accessibleSelection == textElement.textID, "Each drawn text object must be a navigable accessibility child that selects its matching object")
        let trailingWhitespace = NSPoint(x: textElement.rect.maxX - 1, y: textElement.rect.midY)
        if !preciseTextBounds.contains(trailingWhitespace) { try verify(originalPlan.text(at: trailingWhitespace)?.textID != textElement.textID, "Text hit-testing must not treat the full section-width layout box as glyph content") }
        var indentedCanvas = textCanvas; indentedCanvas.styles[TypeRole.label.rawValue]!.indent = 80; indentedCanvas.styles[TypeRole.label.rawValue]!.text = "Indented label"
        let indentedPlan = CanvasPlan(direction: indentedCanvas)
        let indentedElement = indentedPlan.elements.first { $0.role == .label }!
        let indentedBounds = indentedPlan.textBounds(for: indentedElement)
        try verify(indentedBounds.minX >= indentedElement.rect.minX + 70 && indentedPlan.text(at: NSPoint(x: indentedBounds.midX, y: indentedBounds.midY))?.textID == indentedElement.textID, "Text hit-testing must follow the rendered first-line indent")
        try verify(indentedPlan.text(at: NSPoint(x: indentedElement.rect.minX + 5, y: indentedBounds.midY))?.textID != indentedElement.textID, "Blank space before an indented line must not select its text")
        let centeredEditor = CanvasNativeView.editorFrame(textRect: CGRect(x: 140, y: 10, width: 20, height: 20), alignment: .center, zoom: 1, bounds: CGRect(x: 0, y: 0, width: 300, height: 100))
        let rightEditor = CanvasNativeView.editorFrame(textRect: CGRect(x: 270, y: 10, width: 20, height: 20), alignment: .right, zoom: 1, bounds: CGRect(x: 0, y: 0, width: 300, height: 100))
        try verify(abs(centeredEditor.midX - 150) < 0.01 && abs(rightEditor.maxX - 293) < 0.01, "Minimum-size inline editors must preserve centered and right-aligned text anchors")
        let textID = textElement.textID!
        textCanvas.setCanvasText("Explore the studio", textID: textID)
        let textData = try JSONEncoder().encode(textCanvas)
        let decodedTextCanvas = try JSONDecoder().decode(TypeDirection.self, from: textData)
        try verify(CanvasPlan(direction: decodedTextCanvas).elements.first { $0.textID == textID }?.text?.string == "Explore the studio", "Selected text override must persist and render")
        let sharedLabelText = textCanvas.style(.label).text
        textCanvas.setCanvasText(sharedLabelText, textID: textID)
        try verify(textCanvas.textOverrides?[textID] == sharedLabelText && CanvasPlan(direction: textCanvas).elements.first { $0.textID == textID }?.text?.string == sharedLabelText, "An explicit edit matching the shared role sample must not revert to a template-specific default")
        let emptyEditorColor = CanvasNativeView.editorTextColor(NSAttributedString(string: ""), fallback: .systemOrange)
        try verify(emptyEditorColor.isEqual(NSColor.systemOrange), "Empty canvas text must use a safe editor color instead of reading outside the string")
        try verify(TypeDirection.acceptsCanvasText(String(repeating: "a", count: TypeDirection.maximumTextBytes)) && !TypeDirection.acceptsCanvasText(String(repeating: "a", count: TypeDirection.maximumTextBytes + 1)), "Direct canvas edits must enforce the persisted workspace text limit")
        var importedTextCanvas = TypeDirection(); importedTextCanvas.canvas = .imported
        importedTextCanvas.importedLayout = ImportedLayout(width: 320, height: 200, layers: [ImportedLayer(name: "Hero", x: 10, y: 10, width: 280, height: 80, color: "222222", style: TypeStyle(fontName: "Helvetica", size: 24, text: "Original"))])
        let importedLayerID = importedTextCanvas.importedLayout!.layers[0].id
        try verify(importedTextCanvas.setImportedText("Edited directly", layerID: importedLayerID) && CanvasPlan(direction: importedTextCanvas).elements.first?.text?.string == "Edited directly", "Imported canvas text must support direct edits by layer")
        let canvasA = UUID(), canvasB = UUID(), canvasC = UUID()
        var visible = CanvasVisibility.solo(canvasA)
        visible = CanvasVisibility.selecting(canvasB, from: canvasA, shown: visible)
        visible = CanvasVisibility.selecting(canvasC, from: canvasB, shown: visible)
        try verify(visible == [canvasA, canvasB, canvasC], "Selecting another canvas must preserve the visible comparison set")
        try verify(CanvasBoardLayout.frameControlsAreActive(canvasID: canvasC, selectedDirectionID: canvasC, frameCanvasID: nil)
                   && !CanvasBoardLayout.frameControlsAreActive(canvasID: canvasA, selectedDirectionID: canvasC, frameCanvasID: nil)
                   && CanvasBoardLayout.frameControlsAreActive(canvasID: canvasA, selectedDirectionID: canvasC, frameCanvasID: canvasA),
                   "Normal canvas selection must show resize handles, and explicit frame selection must remain active")
        visible.remove(canvasA)
        try verify(CanvasVisibility.prune(visible, valid: [canvasA, canvasC], selected: canvasC) == [canvasC] && CanvasVisibility.solo(canvasB) == [canvasB], "Canvas hide, prune and solo state")
        var tallLegacyImport = TypeDirection(name: "Tall legacy import")
        tallLegacyImport.canvas = .imported
        tallLegacyImport.width = 320
        tallLegacyImport.importedLayout = ImportedLayout(width: 320, height: 20_000,
            layers: [ImportedLayer(name: "Lower text", x: 20, y: 15_000, width: 280, height: 500, color: "222222",
                                   style: TypeStyle(fontName: "Helvetica", size: 28, text: "Legacy lower content"))])
        let tallLegacyPlan = CanvasPlan(direction: tallLegacyImport)
        try verify(tallLegacyPlan.size.height >= 20_000 && tallLegacyPlan.artboardSize.height >= 20_000
                   && tallLegacyPlan.size == tallLegacyPlan.artboardSize
                   && (tallLegacyPlan.elements.first { $0.text != nil }?.rect.minY ?? 0) >= 15_000,
                   "Untouched legacy imported text below 10k must retain its full preview and export artboard bounds")
        let tallLegacyView = CanvasNativeView(plan: tallLegacyPlan)
        let tallLegacyPDF = tallLegacyView.dataWithPDF(inside: tallLegacyView.bounds)
        guard let tallLegacyProvider = CGDataProvider(data: tallLegacyPDF as CFData),
              let tallLegacyDocument = CGPDFDocument(tallLegacyProvider),
              let tallLegacyPage = tallLegacyDocument.page(at: 1) else {
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tall legacy imported canvas PDF could not be read"])
        }
        let tallLegacyMediaBox = tallLegacyPage.getBoxRect(.mediaBox)
        try verify(tallLegacyMediaBox.height >= 20_000
                   && (tallLegacyPlan.elements.first { $0.text != nil }?.rect.maxY ?? .greatestFiniteMagnitude) <= tallLegacyMediaBox.maxY,
                   "Legacy imported lower text must remain within the full-height PDF media box")
        let sidebarSuite = "FontShelf-sidebar-check-" + UUID().uuidString
        let sidebarDefaults = UserDefaults(suiteName: sidebarSuite)!
        defer { sidebarDefaults.removePersistentDomain(forName: sidebarSuite) }
        try verify(!WorkspaceSidebarPreference.collapsed(in: sidebarDefaults), "The workspace sidebar must be expanded by default")
        WorkspaceSidebarPreference.setCollapsed(true, in: sidebarDefaults)
        let reloadedSidebarDefaults = UserDefaults(suiteName: sidebarSuite)!
        try verify(WorkspaceSidebarPreference.collapsed(in: reloadedSidebarDefaults), "Collapsed workspace sidebar state must persist across view recreation")
        WorkspaceSidebarPreference.setCollapsed(false, in: reloadedSidebarDefaults)
        try verify(!WorkspaceSidebarPreference.collapsed(in: sidebarDefaults), "Expanded workspace sidebar state must persist")
        try verify(WorkspaceSidebarLayout.reservedWidth(collapsed: false) == 256 && WorkspaceSidebarLayout.reservedWidth(collapsed: true) == 0, "Collapsing the workspace sidebar must return its complete width to Library and Spaces")
        try verify(WorkspaceSidebarLayout.revealWidth >= 44 && WorkspaceSidebarLayout.revealHeight >= 44, "The collapsed sidebar reveal control must keep a full-size accessible hit target")
        let inspectorSuite = "Typefield-inspector-check-" + UUID().uuidString
        let inspectorDefaults = UserDefaults(suiteName: inspectorSuite)!
        defer { inspectorDefaults.removePersistentDomain(forName: inspectorSuite) }
        try verify(StudioInspectorPreference.mode(in: inspectorDefaults) == .expanded, "The Spaces inspector must start expanded")
        StudioInspectorPreference.setMode(.slim, in: inspectorDefaults)
        try verify(StudioInspectorPreference.mode(in: UserDefaults(suiteName: inspectorSuite)!) == .slim, "The slim inspector choice must persist")
        StudioInspectorPreference.setMode(.floating, in: inspectorDefaults)
        try verify(StudioInspectorPreference.mode(in: inspectorDefaults) == .slim, "A transient floating panel must not replace the saved docked layout")
        StudioInspectorPreference.setMode(.hidden, in: inspectorDefaults)
        try verify(StudioInspectorPreference.mode(in: inspectorDefaults) == .hidden, "The canvas-width inspector choice must persist")
        try verify(StudioInspectorLayout.slimWidth >= 44 && StudioInspectorLayout.fullMinimumWidth > StudioInspectorLayout.slimWidth, "The slim tool rail must keep usable targets and return inspector width to the canvas")
        try verify(WorkspaceHeaderLayout.horizontalPadding == 20 && WorkspaceHeaderLayout.verticalPadding == 14 && WorkspaceHeaderLayout.titleSize == 22 && WorkspaceHeaderLayout.titleHeight == 30, "Library, Spaces, and Letterform Editor must share one header geometry")
        try verify(FontLabCharacterPanelLayout.clamped(0) == FontLabCharacterPanelLayout.minimumWidth && FontLabCharacterPanelLayout.clamped(9_999) == FontLabCharacterPanelLayout.maximumWidth && FontLabCharacterPanelLayout.clamped(300) == 300, "Letterform Editor character panel resizing must remain usable and bounded")
        var inserted = TypeDirection(); let beforeInsert = CanvasPlan(direction: inserted)
        let insertedID = inserted.insert(.heading, target: beforeInsert.sections[1].id, before: true, visible: beforeInsert.sections.map(\.id))
        let afterInsert = CanvasPlan(direction: inserted)
        try verify(afterInsert.sections.map(\.id).firstIndex(of: insertedID) == 1, "Dragged type role was not inserted at its drop position")
        try verify(afterInsert.elements.contains { $0.sectionID == insertedID && $0.role == .heading && $0.text?.string == inserted.style(.heading).text }, "Dragged role must carry its saved style and sample text")
        try verify(StudioRoleScope.affectedTextCount(role: .heading, direction: inserted) == afterInsert.elements.filter { $0.role == .heading && $0.text != nil }.count,
                   "Role scope must count the actual text objects affected by a shared style")
        var addTileCanvas = TypeDirection(); addTileCanvas.canvas = .custom; addTileCanvas.blocks = [.body]
        let beforeAddTile = CanvasPlan(direction: addTileCanvas)
        try verify(StudioRoleScope.affectedTextCount(role: .display, direction: addTileCanvas) == 0, "Missing role must show zero uses")
        let addTileID = addTileCanvas.insert(.display, target: nil, before: false, visible: beforeAddTile.sections.map(\.id))
        try verify(CanvasPlan(direction: addTileCanvas).sections.last?.id == addTileID && StudioRoleScope.affectedTextCount(role: .display, direction: addTileCanvas) == 1,
                   "Clicking Add must place the missing role at the end of the canvas")
        let rolePayload = inserted.id.uuidString + "|role|" + TypeRole.heading.rawValue
        let sectionPayload = inserted.id.uuidString + "|section|" + afterInsert.sections[0].id
        try verify(CanvasDragPayload.parse(rolePayload, directionID: inserted.id, sectionIDs: Set(afterInsert.sections.map(\.id)), acceptsRoles: true) == .role(.heading), "Role drag payload")
        try verify(CanvasDragPayload.parse(rolePayload, directionID: inserted.id, sectionIDs: Set(afterInsert.sections.map(\.id)), acceptsRoles: false) == nil, "Read-only canvas must reject role drops")
        try verify(CanvasDragPayload.parse(sectionPayload, directionID: inserted.id, sectionIDs: Set(afterInsert.sections.map(\.id)), acceptsRoles: false) == .section(afterInsert.sections[0].id), "Section drag payload")
        var summaryDirection = TypeDirection(); summaryDirection.styles[TypeRole.body.rawValue]!.fontName = "Courier"; summaryDirection.styles[TypeRole.body.rawValue]!.tracking = 1.5
        let summary = CanvasTypographySummary(canvas: "Canvas 1", direction: summaryDirection)
        try verify(summary.fonts.contains("Georgia") && summary.fonts.contains("Courier") && summary.text(.roles).contains("Body: Courier"), "Canvas font summary must report fonts actually used by role")
        try verify(summary.text(.full).contains("tracking 1.5 px") && summary.text(.fonts, markdown: true).contains("`Courier`"), "Typography summary detail levels")
        var secondSummaryDirection = summaryDirection
        secondSummaryDirection.name = "Canvas 2"
        secondSummaryDirection.styles[TypeRole.heading.rawValue]!.fontName = "Helvetica"
        let summaryDocument = TypographySummaryDocument(summaries: [summary, CanvasTypographySummary(canvas: "Canvas 2", direction: secondSummaryDirection)])
        try verify(summaryDocument.text(.roles).contains("Canvas 1") && summaryDocument.text(.roles).contains("Canvas 2") && summaryDocument.fonts.contains("Helvetica"), "Selected-canvas typography summary must include every chosen canvas")
        let generatedSpecimen = TypeSystemPDFExporter.specimenDirection(from: secondSummaryDirection)
        try verify(generatedSpecimen.canvas == .specimen && generatedSpecimen.style(.body).fontName == "Courier" && generatedSpecimen.style(.heading).fontName == "Helvetica", "Generated type system must preserve the selected canvas typography")
        let typeSystemPDF = try TypeSystemPDFExporter.data(directions: [summaryDirection, secondSummaryDirection])
        let typeSystemDocument = CGDataProvider(data: typeSystemPDF as CFData).flatMap(CGPDFDocument.init)
        try verify(typeSystemDocument?.numberOfPages == 2, "Type system export must create one PDF page per selected canvas")
        let expectedSpecimen = CanvasPlan(direction: TypeSystemPDFExporter.specimenDirection(from: summaryDirection))
        let specimenPage = typeSystemDocument?.page(at: 1)?.getBoxRect(.mediaBox)
        try verify(specimenPage != nil && abs((specimenPage?.width ?? 0) - expectedSpecimen.size.width) < 1 &&
                   abs((specimenPage?.height ?? 0) - expectedSpecimen.size.height) < 1,
                   "Type system PDF must render its actual specimen dimensions")
        var importedPDFDirection = TypeDirection(name: "Imported Figma frame")
        importedPDFDirection.canvas = .imported
        importedPDFDirection.importedSource = .figma
        importedPDFDirection.importedLayout = ImportedLayout(width: 320, height: 200, layers: [ImportedLayer(name: "Imported headline", x: 12, y: 12, width: 280, height: 48, color: "111111", style: TypeStyle(fontName: "Helvetica", size: 30, text: "Imported content"))])
        do {
            _ = try TypeSystemPDFExporter.data(directions: [importedPDFDirection])
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Type system PDF must reject imported canvases instead of exporting unrelated template content."])
        } catch let error as TypeSystemPDFExporter.ExportError {
            try verify(error.localizedDescription.contains("Use Preview PDF"), "Imported type system PDF failure must explain the supported visual export path")
        }
        var webBoard = TypeBoard(); webBoard.name = "Web audit"; webBoard.directions = [summaryDirection, secondSummaryDirection]
        let webCoverage = CharacterSet.alphanumerics.union(.punctuationCharacters)
        func webFace(_ name: String, family: String = "Georgia", variable: Bool = false, weight: Int = 400, italic: Bool = false, axisRanges: [Int: ClosedRange<Double>] = [:]) -> WebFontAssetFace { WebFontAssetFace(postScriptName: name, familyName: family, coverage: webCoverage, writingSystems: [.latin], glyphCount: 1_000, variable: variable, weight: weight, italic: italic, axisRanges: axisRanges) }
        let helveticaAsset = WebFontAsset(url: root.appendingPathComponent("Helvetica.woff2"), byteCount: 9_000, faces: [webFace("Helvetica", family: "Helvetica")])
        let staticA = WebFontAsset(url: root.appendingPathComponent("Georgia-Regular.woff2"), byteCount: 8_000, faces: [webFace("GeorgiaStaticRegular", weight: 400)])
        let staticB = WebFontAsset(url: root.appendingPathComponent("Georgia-Bold.woff2"), byteCount: 9_500, faces: [webFace("GeorgiaStaticBold", weight: 700)])
        let variableAsset = WebFontAsset(url: root.appendingPathComponent("Georgia-Variable.woff2"), byteCount: 13_000, faces: [webFace("Georgia", variable: true, axisRanges: [WebFontAxis.weight: 300...700])])
        let webReport = WebFontAuditAnalyzer.report(board: webBoard, canvasIDs: [summaryDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [variableAsset, staticA, staticB, helveticaAsset])
        try verify(webReport.rows.count == 1 && webReport.knownBytes == 13_000 && webReport.canvasCount == 1, "Web audit must scope exact WOFF2 totals to chosen canvases and styles")
        try verify(webReport.excludedBytes >= helveticaAsset.byteCount && webReport.comparisons.first?.staticCount == 1 && webReport.comparisons.first?.staticBytes == 8_000, "Variable comparisons must total only static styles selected on the chosen canvases")
        try verify(webReport.rows[0].coverageSource == .exactWebAsset && webReport.rows[0].glyphCount == 1_000, "Coverage and glyph totals must identify the exact unambiguous WOFF2 source")
        try verify(!webReport.text.contains(root.path) && webReport.rows[0].fallback.maxWidthDelta.isFinite, "Copied web audit must omit local paths and keep finite fallback metrics")
        let duplicateGeorgiaAsset = WebFontAsset(url: root.appendingPathComponent("Georgia-Variable-Copy.woff2"), byteCount: 12_500, faces: [webFace("Georgia", variable: true, axisRanges: [WebFontAxis.weight: 300...700])])
        let ambiguousWebReport = WebFontAuditAnalyzer.report(board: webBoard, canvasIDs: [summaryDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [variableAsset, duplicateGeorgiaAsset, staticA])
        try verify(ambiguousWebReport.knownBytes == 0 && ambiguousWebReport.ambiguousAssetNames == ["Georgia"] && ambiguousWebReport.rows[0].asset == nil, "Duplicate PostScript matches must be reported as ambiguous and excluded from transfer totals")
        try verify(ambiguousWebReport.rows[0].coverageSource == .desktopSource && ambiguousWebReport.rows[0].glyphCount == nil, "Ambiguous WOFF2 files must not masquerade as exact web coverage")
        let missingWebReport = WebFontAuditAnalyzer.report(board: webBoard, canvasIDs: [summaryDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [])
        try verify(missingWebReport.knownBytes == 0 && missingWebReport.missingAssetNames == ["Georgia"], "Missing WOFF2 assets must remain explicit instead of producing an estimated total")
        try verify(missingWebReport.rows[0].coverageSource == .desktopSource && missingWebReport.rows[0].subsetOpportunity.contains("unambiguous WOFF2"), "Desktop-only coverage must be labeled and must not fabricate a WOFF2 subsetting estimate")
        let incompatibleVariable = WebFontAsset(url: root.appendingPathComponent("Georgia-Variable-500-700.woff2"), byteCount: 11_000, faces: [webFace("Georgia", variable: true, weight: 500, axisRanges: [WebFontAxis.weight: 500...700])])
        let incompatibleAxisReport = WebFontAuditAnalyzer.report(board: webBoard, canvasIDs: [summaryDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [incompatibleVariable, staticA])
        try verify(incompatibleAxisReport.comparisons.isEmpty && incompatibleAxisReport.knownBytes == 0 && incompatibleAxisReport.rows[0].asset == nil && incompatibleAxisReport.rows[0].assetIncompatible && incompatibleAxisReport.incompatibleAssetNames == ["Georgia"], "A WOFF2 outside the selected style axis range must not be counted or presented as a compatible replacement")
        var extremeAxisDirection = summaryDirection; extremeAxisDirection.styles[TypeRole.display.rawValue]!.axes[WebFontAxis.weight] = 1e300
        var extremeAxisBoard = webBoard; extremeAxisBoard.directions = [extremeAxisDirection]
        let extremeAxisReport = WebFontAuditAnalyzer.report(board: extremeAxisBoard, canvasIDs: [extremeAxisDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [variableAsset])
        try verify(extremeAxisReport.knownBytes == 0 && extremeAxisReport.incompatibleAssetNames == ["Georgia"], "Extreme finite axis values must be handled safely and rejected when outside the asset range")
        var widthAxisDirection = summaryDirection; widthAxisDirection.styles[TypeRole.display.rawValue]!.axes[WebFontAxis.width] = 90
        var widthAxisBoard = webBoard; widthAxisBoard.directions = [widthAxisDirection]
        let widthAxisReport = WebFontAuditAnalyzer.report(board: widthAxisBoard, canvasIDs: [widthAxisDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [variableAsset, staticA])
        try verify(widthAxisReport.comparisons.isEmpty, "Static-size comparisons must be suppressed when the selected instance uses an axis the static metadata cannot match")
        var slantAxisDirection = summaryDirection; slantAxisDirection.styles[TypeRole.display.rawValue]!.axes[WebFontAxis.slant] = -5
        var slantAxisBoard = webBoard; slantAxisBoard.directions = [slantAxisDirection]
        let slantedVariable = WebFontAsset(url: root.appendingPathComponent("Georgia-Slanted-Variable.woff2"), byteCount: 13_000, faces: [webFace("Georgia", variable: true, axisRanges: [WebFontAxis.weight: 300...700, WebFontAxis.slant: -10...0])])
        let staticItalic = WebFontAsset(url: root.appendingPathComponent("Georgia-Italic.woff2"), byteCount: 8_500, faces: [webFace("GeorgiaStaticItalic", italic: true)])
        let slantAxisReport = WebFontAuditAnalyzer.report(board: slantAxisBoard, canvasIDs: [slantAxisDirection.id], fontNames: ["Georgia"], catalog: catalog, assets: [slantedVariable, staticItalic])
        try verify(slantAxisReport.knownBytes == slantedVariable.byteCount && slantAxisReport.comparisons.isEmpty, "A continuous slant instance must not be labeled exactly equivalent to a Boolean static italic face")
        try verify(WebTextScript.names(in: "Hello Ελληνικά العربية 漢字").contains("Latin") && WebTextScript.names(in: "Hello Ελληνικά العربية 漢字").contains("Han"), "Web audit script classification")
        try verify(CanvasPlan(direction: TypeDirection()).elements.contains { $0.textKind == .buttonLabel }, "Canvas plan must identify real button labels for fallback width testing")
        var scopedBoard = TypeBoard(); scopedBoard.directions = [summaryDirection, TypeDirection()]
        try verify(StudioFontCollection.fontNames(in: summaryDirection) == Set(summary.fonts), "Canvas collection font scope")
        try verify(StudioFontCollection.fontNames(in: scopedBoard).isSuperset(of: ["Courier", "Georgia", "Helvetica"]), "Typeboard collection font scope")
        try verify(StudioFontCollection.fontNames(in: [scopedBoard, board]) == StudioFontCollection.fontNames(in: scopedBoard).union(StudioFontCollection.fontNames(in: board)), "Project collection font scope")
        var markdownDirection = TypeDirection(); markdownDirection.name = "A *test*"; markdownDirection.styles[TypeRole.body.rawValue]!.fontName = "Font`Name"
        let markdownSummary = CanvasTypographySummary(canvas: markdownDirection.name, direction: markdownDirection).text(.fonts, markdown: true)
        try verify(markdownSummary.contains("A \\*test\\*") && markdownSummary.contains("``Font`Name``"), "Typography Markdown must escape designer text safely")
        let filterLibrary = Library(storageURL: root.appendingPathComponent("filters/library.json"))
        filterLibrary.families = catalog
        let filterSample = catalog[0]
        filterLibrary.saved.collections["Studio shortlist"] = [filterSample.name]
        filterLibrary.saved.overrides[filterSample.name] = .script
        filterLibrary.saved.favorites = [filterSample.name]
        let usedFaceNames = Set(filterSample.faces.map(\.name))
        try verify(filterLibrary.createCollection("Canvas fonts", postScriptNames: usedFaceNames) == .created(name: "Canvas fonts", count: 1), "Create a collection from used font faces")
        try verify(filterLibrary.saved.collections["Canvas fonts"] == [filterSample.name], "Used styles must deduplicate to their font family")
        try verify(filterLibrary.createCollection("Canvas fonts", postScriptNames: usedFaceNames) == .duplicateName, "Generated collections must not overwrite an existing collection")
        try verify(filterLibrary.createCollection("Missing fonts", postScriptNames: ["FontShelfMissingFace"]) == .noAvailableFonts, "Unavailable faces cannot create an empty collection")
        let scoped = StudioFontFilter.faces(library: filterLibrary, collection: "collection:Studio shortlist", category: "Script", search: "")
        try verify(Set(scoped.map(\.name)) == Set(filterSample.faces.map(\.name)), "Font chooser must honor collection and user category override")
        try verify(StudioFontFilter.faces(library: filterLibrary, collection: "collection:Studio shortlist", category: "Serif", search: "").isEmpty, "Chooser filters intersect")
        try verify(StudioFontFilter.faces(library: filterLibrary, collection: "Favorites", category: "All categories", search: "").count == filterSample.faces.count, "Chooser favorites")
        filterLibrary.selection = "collection:Studio shortlist"
        try verify(filterLibrary.renameCollection("Studio shortlist", to: " Project fonts "), "Collection rename")
        try verify(filterLibrary.saved.collections["Project fonts"] == [filterSample.name] && filterLibrary.saved.collections["Studio shortlist"] == nil && filterLibrary.selection == "collection:Project fonts", "Rename must preserve members and selection")
        filterLibrary.saved.collections["Existing"] = []
        try verify(!filterLibrary.renameCollection("Project fonts", to: "Existing") && !filterLibrary.renameCollection("Project fonts", to: "  "), "Rename cannot overwrite another collection or accept blank names")
        try verify(Library(storageURL: root.appendingPathComponent("filters/library.json")).saved.collections["Project fonts"] == [filterSample.name], "Collection rename persists")
        try verify(board.id == boardID)
        var duplicate = board.directions[0].copy(name: "Direction B")
        duplicate.styles[TypeRole.body.rawValue]!.fontName = "Courier"
        duplicate.styles[TypeRole.body.rawValue]!.axes = [2003265652: 520]
        duplicate.styles[TypeRole.body.rawValue]!.features = ["liga": 0]
        duplicate.notes = "Saved design decision"
        duplicate.styles[TypeRole.body.rawValue]!.alignment = .right
        duplicate.styles[TypeRole.body.rawValue]!.kerning = false
        duplicate.styles[TypeRole.body.rawValue]!.lineHeight = 32
        duplicate.styles[TypeRole.body.rawValue]!.wordSpacing = 3
        duplicate.styles[TypeRole.body.rawValue]!.paragraphSpacing = 12
        duplicate.styles[TypeRole.body.rawValue]!.indent = 20
        duplicate.styles[TypeRole.body.rawValue]!.casing = .upper
        duplicate.styles[TypeRole.body.rawValue]!.underline = true
        duplicate.canvas = .custom
        duplicate.blocks = [.heading, .body, .caption]
        board.checkpoints = [DirectionCheckpoint(direction: duplicate)]
        board.directions.append(duplicate); board.selectedDirection = duplicate.id
        store.update(space: space, board: board)
        let restored = StudioStore(url: store.url)
        let restoredBoard = restored.state.spaces[0].boards[0]
        let reverseData = try JSONSerialization.data(withJSONObject: FigmaLayoutExporter.payload(board: board))
        let importedBoard = try FigmaLayoutImporter.board(data: reverseData, fonts: catalog.flatMap(\.faces))
        try verify(importedBoard.isValid && importedBoard.directions.count == board.directions.count, "Figma typeboard failed validation")
        let importedFirst = importedBoard.directions[0]
        try verify(importedFirst.canvas == .imported && importedFirst.importedSource == .figma && importedFirst.canvasDisplayName == "Figma layout" && importedFirst.canvasUnitLabel == "px" && importedFirst.importedLayout?.layers.filter { $0.style != nil }.count == CanvasPlan(direction: board.directions[0]).elements.filter { $0.text != nil }.count)
        try verify(importedFirst.importedLayout?.layers.first(where: { $0.style != nil })?.style?.fontName == "Helvetica", "Imported font mapping failed")
        let importedEncoded = try JSONEncoder().encode(importedBoard)
        let decodedImported = try JSONDecoder().decode(TypeBoard.self, from: importedEncoded)
        try verify(decodedImported == importedBoard, "Imported geometry/style persistence failed")
        var legacyImportedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(importedFirst)) as! [String: Any]
        legacyImportedObject.removeValue(forKey: "importedSource")
        let legacyImportedData = try JSONSerialization.data(withJSONObject: legacyImportedObject)
        let legacyImportedDirection = try JSONDecoder().decode(TypeDirection.self, from: legacyImportedData)
        try verify(legacyImportedDirection.importedSource == nil && legacyImportedDirection.canvasDisplayName == "Figma layout" && legacyImportedDirection.canvasUnitLabel == "px", "Pre-source Figma layouts must remain compatible")
        try verify(restoredBoard.directions.count == 2 && restoredBoard.selectedDirection == duplicate.id)
        try verify(restoredBoard.directions[0].style(.body).fontName == "Helvetica")
        try verify(restoredBoard.directions[1] == duplicate, "Direction settings were lost on reload")
        try verify(restored.focusedSpace == space && restored.focusedBoard == boardID, "Selected workspace was lost on reload")
        try verify(restoredBoard.checkpoints?.first?.direction == duplicate, "Checkpoint settings were lost on reload")
        restored.undoManager.groupsByEvent = false
        var edited = restoredBoard
        edited.directions[1].hiddenSections = ["Custom layout:block-0"]
        restored.update(space: space, board: edited, action: "Remove Section")
        try verify(restored.undoManager.canUndo && restored.undoManager.undoActionName == "Remove Section")
        restored.undoManager.undo()
        try verify(restored.state.spaces[0].boards[0] == restoredBoard, "Undo did not restore the board")
        try verify(StudioStore(url: restored.url).state.spaces[0].boards[0] == restoredBoard, "Undo was not persisted")
        restored.undoManager.redo()
        try verify(restored.state.spaces[0].boards[0] == edited, "Redo did not restore the edit")
        restored.undoManager.removeAllActions()
        edited.selectedDirection = edited.directions[0].id
        restored.update(space: space, board: edited)
        try verify(!restored.undoManager.canUndo, "Direction navigation polluted edit history")
        let beforeTyping = edited
        edited.directions[0].styles[TypeRole.display.rawValue]!.size = 8
        restored.update(space: space, board: edited, action: "Change Size")
        edited.directions[0].styles[TypeRole.display.rawValue]!.size = 80
        restored.update(space: space, board: edited, action: "Change Size")
        restored.undoManager.undo()
        try verify(restored.state.spaces[0].boards[0] == beforeTyping, "Numeric typing was not coalesced")
        restored.undoManager.redo()
        try verify(restored.state.spaces[0].boards[0] == edited, "Coalesced redo lost the final value")
        restored.removeBoard(space: space, id: edited.id)
        try verify(restored.state.spaces[0].boards.isEmpty)
        restored.undoManager.undo()
        try verify(restored.state.spaces[0].boards.first == edited && restored.focusedBoard == edited.id, "Deleted typeboard was not recovered")
        restored.undoManager.redo()
        try verify(restored.state.spaces[0].boards.isEmpty, "Redo deletion did not remove the typeboard")
        let laterSpace = restored.addSpace("Later space")!
        let laterBoard = restored.addBoard(space: laterSpace)!
        restored.undoManager.removeAllActions()
        try verify(restored.removeSpace(laterSpace) && restored.state.spaces.count == 1 && restored.undoManager.undoActionName == "Delete Space", "Space deletion must be undoable")
        restored.undoManager.undo()
        try verify(restored.state.spaces.count == 2 && restored.state.spaces[1].id == laterSpace && restored.state.spaces[1].boards.first?.id == laterBoard
                   && restored.focusedSpace == laterSpace && restored.focusedBoard == laterBoard,
                   "Undo must restore a non-first Space, its board and its selection")
        try verify(StudioStore(url: restored.url).state.spaces[1].boards.first?.id == laterBoard, "Restored Space must be persisted")
        restored.undoManager.redo()
        try verify(restored.state.spaces.count == 1 && restored.state.spaces[0].id == space && restored.focusedSpace == nil,
                   "Redo must delete the restored Space without shifting focus to another Space")
        try verify(restored.select(space: space) && restored.removeSpace(space), "Deleting a space should save a normalized selection")
        let normalized = StudioStore(url: restored.url)
        try verify(normalized.focusedSpace == nil && normalized.focusedBoard == nil, "Deleted space focus must not persist")
        let corruptURL = root.appendingPathComponent("corrupt.json"), corrupt = Data("broken".utf8)
        try corrupt.write(to: corruptURL)
        let broken = StudioStore(url: corruptURL)
        let blockedSpaceCount = broken.state.spaces.count
        try verify(broken.addSpace("Do not overwrite") == nil, "Read-blocked creation must return failure")
        try verify(broken.readBlocked && broken.state.spaces.count == blockedSpaceCount && !broken.save(), "Read-blocked workspace must reject new spaces")
        try verify(broken.addBoard(space: UUID()) == nil && broken.state.spaces.count == blockedSpaceCount, "Read-blocked workspace must reject new typeboards")
        let unchanged = try Data(contentsOf: corruptURL); try verify(unchanged == corrupt)
        try checkSpacesSaveRollback(in: root)
        let shape = ImportedLayer(name: "Shape", x: 0, y: 0, width: 100, height: 100, color: "FFFFFF")
        let text = ImportedLayer(name: "Text", x: 0, y: 0, width: 100, height: 40, color: "000000", style: TypeStyle(fontName: "Helvetica", size: 18, text: "Text"))
        let importedLayout = ImportedLayout(width: 100, height: 100, layers: [shape, text])
        try verify(importedLayout.textLayerIndex(selectedID: shape.id) == nil && importedLayout.textLayerIndex(selectedID: nil) == 1, "Selecting an imported shape must not redirect to the first text layer")
        let legacyShape = try JSONDecoder().decode(ImportedLayer.self, from: JSONEncoder().encode(shape))
        try verify(legacyShape.strokeColor == nil && legacyShape.strokeWidth == nil && legacyShape.strokeOpacity == nil,
                   "Shapes saved before stroke editing must remain readable")
        let artworkFile = root.appendingPathComponent("artwork.png")
        guard let artworkContext = CGContext(data: nil, width: 16, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create artwork fixture"])
        }
        artworkContext.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        artworkContext.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
        guard let artworkImage = artworkContext.makeImage(),
              let artworkPNG = NSBitmapImageRep(cgImage: artworkImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode artwork fixture"])
        }
        try artworkPNG.write(to: artworkFile)
        var rasterArtwork = try SpacesArtworkImport.load(artworkFile)
        try verify(rasterArtwork.isValidArtwork && rasterArtwork.width == 16 && rasterArtwork.height == 8
                   && rasterArtwork.artworkData?.starts(with: SpacesArtworkImport.pngSignature) == true,
                   "Raster artwork must become a self-contained PNG layer at its intrinsic aspect ratio")
        let svgFile = root.appendingPathComponent("artwork.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="16" viewBox="0 0 32 16"><rect width="32" height="16" fill="#d44"/></svg>"##.utf8).write(to: svgFile)
        var svgArtwork = try SpacesArtworkImport.load(svgFile)
        try verify(svgArtwork.isValidArtwork && svgArtwork.artworkData?.starts(with: SpacesArtworkImport.pngSignature) == true
                   && svgArtwork.width / svgArtwork.height == 2,
                   "SVG artwork must be validated and rendered to a portable embedded image")
        rasterArtwork.x = 80; rasterArtwork.y = 100; rasterArtwork.artworkInFront = true
        svgArtwork.x = 200; svgArtwork.y = 100; svgArtwork.width = 160; svgArtwork.height = 80
        var artworkCanvas = TypeDirection()
        artworkCanvas.artworkLayers = [rasterArtwork, svgArtwork]
        let restoredArtworkCanvas = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(artworkCanvas))
        try FileManager.default.removeItem(at: artworkFile)
        try FileManager.default.removeItem(at: svgFile)
        try verify(restoredArtworkCanvas.artworkLayersAreValid && restoredArtworkCanvas.artworkLayers == artworkCanvas.artworkLayers,
                   "Embedded artwork must survive project round-trip after original files are removed")
        let artworkPlan = CanvasPlan(direction: restoredArtworkCanvas)
        try verify(artworkPlan.elements.filter { $0.image != nil }.count == 2
                   && artworkPlan.sections.contains { $0.id == rasterArtwork.id },
                   "Every Spaces canvas must render embedded artwork as selectable image layers")
        let figmaPreflight = StudioTransferReport(format: .figma, scope: "Typeboard fixture with one canvas", directions: [restoredArtworkCanvas], availableFonts: [])
        let pdfPreflight = StudioTransferReport(format: .previewPDF, scope: "Canvas fixture", directions: [restoredArtworkCanvas], availableFonts: [])
        try verify(figmaPreflight.omittedArtworkCount == 2 && figmaPreflight.detail.contains("Scope: Typeboard fixture")
                   && figmaPreflight.detail.contains("Image layers omitted: 2") && pdfPreflight.omittedArtworkCount == 0,
                   "Export preflight must disclose exact scope and artwork omitted by editable bridges")
        let importReport = StudioImportReport(source: "Figma", boards: [importedBoard], availableFonts: [])
        try verify(importReport.canvasCount == importedBoard.directions.count && !importReport.missingFonts.isEmpty
                   && importReport.detail.contains("Unavailable fonts:"), "Import summary must surface unavailable fonts across all canvases")
        let artworkView = CanvasNativeView(plan: artworkPlan)
        let artworkPDF = artworkView.dataWithPDF(inside: artworkView.bounds)
        guard let pdfProvider = CGDataProvider(data: artworkPDF as CFData),
              let document = CGPDFDocument(pdfProvider), let page = document.page(at: 1) else {
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Artwork PDF could not be read"])
        }
        let pdfBox = page.getBoxRect(.mediaBox)
        let pdfWidth = Int(pdfBox.width), pdfHeight = Int(pdfBox.height)
        var pixels = [UInt8](repeating: 0, count: pdfWidth * pdfHeight * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: pdfWidth, height: pdfHeight,
                                          bitsPerComponent: 8, bytesPerRow: pdfWidth * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            context.drawPDFPage(page)
        }
        let redArtworkRendered = stride(from: 0, to: pixels.count, by: 4).contains { index in
            pixels[index] > 220 && pixels[index + 1] < 50 && pixels[index + 2] < 50 && pixels[index + 3] > 220
        }
        try verify(redArtworkRendered, "Spaces PDF export must contain visible imported image pixels")
        var invalidArtwork = rasterArtwork; invalidArtwork.artworkData = Data("not png".utf8)
        try verify(!invalidArtwork.isValidArtwork, "Invalid embedded artwork must not pass project validation")
        let corruptArtworkFile = root.appendingPathComponent("broken.png")
        try Data("not a bitmap".utf8).write(to: corruptArtworkFile)
        do { _ = try SpacesArtworkImport.load(corruptArtworkFile); try verify(false, "Damaged artwork was accepted") }
        catch SpacesArtworkImportError.cannotRender { }
        var outlined = shape
        outlined.strokeColor = "32547A"; outlined.strokeOpacity = 0.75; outlined.strokeWidth = 5
        let outlinedRoundTrip = try JSONDecoder().decode(ImportedLayer.self, from: JSONEncoder().encode(outlined))
        try verify(outlinedRoundTrip == outlined && ImportedLayout(width: 100, height: 100, layers: [outlined]).isValid,
                   "Shape stroke color, opacity, and width must persist")
        var badStroke = outlined; badStroke.strokeWidth = .infinity
        try verify(!ImportedLayout(width: 100, height: 100, layers: [badStroke]).isValid,
                   "Invalid persisted stroke widths must be rejected")
        badStroke = outlined; badStroke.strokeColor = "not-a-color"
        try verify(!ImportedLayout(width: 100, height: 100, layers: [badStroke]).isValid,
                   "Invalid persisted stroke colors must be rejected")
        var outlinedDirection = TypeDirection(name: "Outlined")
        outlinedDirection.canvas = .imported; outlinedDirection.width = 100
        outlinedDirection.importedLayout = ImportedLayout(width: 100, height: 100, layers: [outlined])
        var wideStrokeDirection = outlinedDirection
        wideStrokeDirection.importedLayout?.layers[0].strokeWidth = 500
        try verify(wideStrokeDirection.maximumCanvasScale == 2,
                   "Canvas scaling must keep imported stroke widths inside the Figma and Adobe export limit")
        outlinedDirection.canvasScale = 2
        let outlinedPlan = CanvasPlan(direction: outlinedDirection)
        try verify(outlinedPlan.elements[0].strokeWidth == 10 && outlinedPlan.elements[0].strokeColor?.rgbHex == "32547A"
                   && abs((outlinedPlan.elements[0].strokeColor?.alphaComponent ?? 0) - 0.75) < 0.001,
                   "Canvas resize must scale stroke width while retaining its color and opacity")
        var outlinedBoard = TypeBoard(); outlinedBoard.directions = [outlinedDirection]
        let outlinedFrame = (FigmaLayoutExporter.payload(board: outlinedBoard)["frames"] as! [[String: Any]])[0]
        let outlinedElement = (outlinedFrame["elements"] as! [[String: Any]])[0]
        try verify((outlinedElement["strokeWidth"] as? Double) == 10
                   && abs(((outlinedElement["stroke"] as? [String: Double])?["a"] ?? 0) - 0.75) < 0.001,
                   "Figma export must retain rendered stroke width and opacity")
        let outlinedImport = try FigmaLayoutImporter.board(data: JSONSerialization.data(withJSONObject: FigmaLayoutExporter.payload(board: outlinedBoard)), fonts: [])
        try verify(outlinedImport.directions[0].importedLayout?.layers[0].strokeWidth == 10
                   && outlinedImport.directions[0].importedLayout?.layers[0].strokeColor == "32547A",
                   "Figma round-trip must preserve editable shape strokes")
        let outlinedAdobe = try AdobeTypeSystemExporter.script(directions: [outlinedDirection], title: "Outlined", target: .illustrator)
        try verify(outlinedAdobe.contains("\"strokeWidth\":10") && outlinedAdobe.contains("shape.strokeColor = rgbColor(item.stroke)"),
                   "Adobe export must create a native stroke at the rendered width")
        var invalid = duplicate; invalid.width = -1
        try verify(!invalid.isValid)
        var invalidText = duplicate; invalidText.styles[TypeRole.body.rawValue]!.lineHeight = -4
        try verify(!invalidText.isValid)
        let legacyStyle = Data(#"{"fontName":"Helvetica","size":18,"leading":1.35,"tracking":0,"axes":{},"features":{},"text":"Legacy document"}"#.utf8)
        let legacy = try JSONDecoder().decode(TypeStyle.self, from: legacyStyle)
        try verify(legacy.alignment == nil && legacy.lineHeight == nil, "Legacy typography failed to decode")
        var legacyKerning = legacy
        legacyKerning.features = ["kern": 0, "liga": 1]
        try verify(legacyKerning.kerning == nil && !legacyKerning.effectiveKerning && legacyKerning.canonicalFeatures == ["kern": 0, "liga": 1], "Legacy OpenType kerning must remain effective")
        try verify(DeveloperHandoff.features(legacyKerning)["kern"] == 0, "Legacy kerning must export without contradictory settings")
        let legacyKerningRoundTrip = try JSONDecoder().decode(TypeStyle.self, from: JSONEncoder().encode(legacyKerning))
        try verify(!legacyKerningRoundTrip.effectiveKerning && legacyKerningRoundTrip.features["kern"] == 0, "Legacy kerning must survive JSON round-trip")
        let legacyKerningText = legacyKerning.attributed("AV", color: .black)
        try verify((legacyKerningText.attribute(.kern, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue == 0, "Legacy disabled kerning must render as disabled")
        var legacyKerningDirection = TypeDirection()
        legacyKerningDirection.styles[TypeRole.body.rawValue] = legacyKerning
        var legacyKerningBoard = TypeBoard()
        legacyKerningBoard.directions = [legacyKerningDirection]
        legacyKerningBoard.selectedDirection = legacyKerningDirection.id
        let legacyKerningFrame = (FigmaLayoutExporter.payload(board: legacyKerningBoard)["frames"] as! [[String: Any]])[0]
        let legacyKerningLayer = (legacyKerningFrame["elements"] as! [[String: Any]]).first { $0["role"] as? String == TypeRole.body.rawValue }!
        try verify(legacyKerningLayer["kerning"] as? Bool == false && (legacyKerningLayer["features"] as? [String: Int])?["kern"] == nil, "Figma export must canonicalize legacy kerning")
        legacyKerning.features["kern"] = 1
        try verify(legacyKerning.effectiveKerning, "Legacy enabled kerning must remain enabled")
        legacyKerning.features["kern"] = 0
        legacyKerning.kerning = true
        try verify(legacyKerning.effectiveKerning && legacyKerning.canonicalFeatures["kern"] == 1, "Explicit kerning must override a stale legacy feature")
        legacyKerning.setKerning(false)
        try verify(legacyKerning.kerning == false && legacyKerning.features["kern"] == nil && !legacyKerning.effectiveKerning, "Changing kerning must remove the legacy duplicate feature")
        let styled = duplicate.style(.body).attributed("One two\nThree", color: .black)
        try verify(styled.string == "ONE TWO\nTHREE")
        let paragraph = styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        try verify(paragraph.alignment == .right && paragraph.minimumLineHeight == 32 && paragraph.paragraphSpacing == 12 && paragraph.firstLineHeadIndent == 20)
        try verify(styled.attribute(.kern, at: 3, effectiveRange: nil) as? Double == 3)
        // Inspector actions must persist and feed the same plan used by PDF/Figma.
        try verify(StudioListFormat.bullets.applying(to: "One\nTwo\n\nThree") == "• One\n• Two\n\n• Three", "Bullet formatting lost paragraph boundaries")
        try verify(StudioListFormat.numbered.applying(to: "• One\n• Two\n\n• Three") == "1. One\n2. Two\n\n1. Three", "Numbered lists did not restart after an empty paragraph")
        try verify(StudioListFormat.none.applying(to: "  1. Café 👋\n  • Second\n- hyphen") == "  Café 👋\n  Second\n- hyphen", "List removal damaged content or indentation")
        let listed = StudioListFormat.bullets.applying(to: "First\nSecond")
        try verify(StudioListFormat.bullets.applying(to: listed) == listed, "Repeated list formatting duplicated markers")
        let alignRect = CGRect(x: 20, y: 30, width: 100, height: 40), alignSize = CGSize(width: 400, height: 300)
        let expectedOrigins: [CGPoint] = [.init(x: 0,y: 30), .init(x: 150,y: 30), .init(x: 300,y: 30), .init(x: 20,y: 0), .init(x: 20,y: 130), .init(x: 20,y: 260)]
        for (alignment, expected) in zip(StudioCanvasAlignment.allCases, expectedOrigins) {
            try verify(alignment.origin(for: alignRect, in: alignSize) == expected, "Canvas alignment moved the wrong axis")
        }
        let scaledAlignment = StudioCanvasAlignment.right.savedOrigin(
            for: CGRect(x: 40, y: 60, width: 200, height: 80),
            in: CGSize(width: 800, height: 600), scale: 2)
        try verify(scaledAlignment == CGPoint(x: 300, y: 30), "Alignment must save unscaled coordinates after proportional canvas resize")
        var arrangementA = TypeDirection(name: "Canvas 1")
        var arrangementB = TypeDirection(name: "Canvas 2")
        let automaticPositions = CanvasBoardLayout.positions(for: [arrangementA, arrangementB])
        let soloOffset = CanvasBoardLayout.visibleOffset(for: [arrangementB], positions: automaticPositions)
        try verify((automaticPositions[arrangementB.id]?.x ?? 0) > (automaticPositions[arrangementA.id]?.x ?? 0)
                   && abs((automaticPositions[arrangementB.id]?.x ?? 0) + soloOffset.width - 24) < 0.001,
                   "Solo Canvas 2 must begin at the board margin and fit without Canvas 1's hidden gap")
        let movedBoardPosition = CanvasBoardLayout.moved(from: automaticPositions[arrangementB.id]!, by: CGSize(width: 80, height: 50), zoom: 0.5)
        arrangementB.boardPosition = movedBoardPosition
        try verify(movedBoardPosition.x == automaticPositions[arrangementB.id]!.x + 160 && movedBoardPosition.y == automaticPositions[arrangementB.id]!.y + 100,
                   "Canvas movement must convert screen drag distance into board coordinates")
        let persistedArrangement = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(arrangementB))
        try verify(persistedArrangement.boardPosition == movedBoardPosition && persistedArrangement.isValid, "Free canvas placement must persist")
        let legacyArrangementJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(arrangementA)) as! [String: Any]
        let legacyArrangement = try JSONDecoder().decode(TypeDirection.self, from: JSONSerialization.data(withJSONObject: legacyArrangementJSON))
        try verify(legacyArrangement.boardPosition == nil && legacyArrangement.canvasScale == nil && legacyArrangement.isValid,
                   "Older canvases without placement or scale must retain their original layout")
        try verify(legacyArrangement.canvasHeight == nil, "Older canvases without an artboard height must retain generated content bounds")
        let startPosition = CanvasBoardPosition(x: 1000, y: 1000)
        let baseArtboard = CanvasPlan(direction: arrangementA).artboardSize
        let topLeftResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                       corner: .topLeft, by: CGSize(width: -baseArtboard.width / 2, height: -baseArtboard.height / 2), zoom: 1)
        try verify(abs(topLeftResize.scale - 1.5) < 0.001
                   && abs(topLeftResize.position.x - (1000 - baseArtboard.width / 2)) < 0.001
                   && abs(topLeftResize.position.y - (1000 - baseArtboard.height / 2)) < 0.001,
                   "Corner resize must keep the opposite corner anchored while scaling proportionally")
        let bottomRightResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                           corner: .bottomRight, by: CGSize(width: 100_000, height: 100_000), zoom: 1)
        try verify(bottomRightResize.scale == arrangementA.maximumCanvasScale && bottomRightResize.position == startPosition,
                   "Corner resize must respect export-safe scale bounds")
        let rightEdgeResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                        edge: .right, by: CGSize(width: 120, height: 0), zoom: 0.5)
        try verify(abs(rightEdgeResize.width - (arrangementA.width + 240)) < 0.001
                   && abs((rightEdgeResize.height ?? 0) - Double(baseArtboard.height)) < 0.001
                   && rightEdgeResize.position == startPosition,
                   "Right edge resize must change width in zoom-adjusted units while retaining rendered height and left/top anchoring")
        let leftEdgeResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                       edge: .left, by: CGSize(width: -40, height: 0), zoom: 1)
        let bottomEdgeResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                         edge: .bottom, by: CGSize(width: 0, height: 60), zoom: 1)
        try verify(leftEdgeResize.width >= arrangementA.width + 40
                   && abs(leftEdgeResize.position.x - (startPosition.x - (leftEdgeResize.width - arrangementA.width))) < 0.001
                   && abs((leftEdgeResize.height ?? 0) - Double(baseArtboard.height)) < 0.001
                   && (bottomEdgeResize.height ?? 0) >= baseArtboard.height + 60
                   && bottomEdgeResize.width == arrangementA.width && bottomEdgeResize.position == startPosition,
                   "All side handles must change one dimension and keep text-fit minimums")
        let topEdgeResize = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                      edge: .top, by: CGSize(width: 0, height: -80), zoom: 0.5)
        try verify(abs((topEdgeResize.height ?? 0) - (baseArtboard.height + 160)) < 0.001
                   && abs(topEdgeResize.position.y - (startPosition.y - 160)) < 0.001
                   && topEdgeResize.width == arrangementA.width,
                   "Top edge resize must change only artboard height while anchoring the opposite edge")
        var horizontalOnlyCanvas = arrangementA
        horizontalOnlyCanvas.width = 960
        horizontalOnlyCanvas.canvasHeight = 1_316
        let horizontalOnlyResize = CanvasBoardLayout.resized(canvas: horizontalOnlyCanvas,
            artboardSize: CanvasPlan(direction: horizontalOnlyCanvas).artboardSize, position: startPosition,
            edge: .right, by: CGSize(width: -63, height: 0), zoom: 1)
        let verticalOnlyResize = CanvasBoardLayout.resized(canvas: horizontalOnlyCanvas,
            artboardSize: CanvasPlan(direction: horizontalOnlyCanvas).artboardSize, position: startPosition,
            edge: .bottom, by: CGSize(width: 0, height: -63), zoom: 1)
        try verify(abs(horizontalOnlyResize.width - 897) < 0.001
                   && (horizontalOnlyResize.height ?? 0) >= 1_316
                   && horizontalOnlyResize.position == startPosition
                   && verticalOnlyResize.width == 960 && verticalOnlyResize.position == startPosition,
                   "Horizontal edge drags must preserve a 1,316pt height while vertical drags preserve the 960pt width")
        let originalHeightPlan = CanvasPlan(direction: arrangementA)
        let minimumTextSize = CanvasBoardLayout.textContentBounds(in: originalHeightPlan)
        var heightLimitedCanvas = arrangementA
        heightLimitedCanvas.canvasHeight = Double(minimumTextSize.height)
        let boundedHeightResize = CanvasBoardLayout.resized(canvas: heightLimitedCanvas, artboardSize: CGSize(width: 960, height: CGFloat(minimumTextSize.height)), position: startPosition,
                                                            edge: .bottom, by: CGSize(width: 0, height: -10_000), zoom: 1)
        try verify((boundedHeightResize.height ?? 0) >= Double(minimumTextSize.height),
                   "Independent artboard height resize must retain all rendered text after an attempted shrink")
        let leftWidthClamp = CanvasBoardLayout.resized(canvas: arrangementA, artboardSize: baseArtboard, position: startPosition,
                                                       edge: .left, by: CGSize(width: -100_000, height: 0), zoom: 1)
        try verify(leftWidthClamp.width == 1_600 && abs(leftWidthClamp.position.x - (startPosition.x - (1_600 - arrangementA.width))) < 0.001,
                   "Left edge resize must keep the opposite side fixed after width clamping")
        let legacyHeightJSON = try JSONSerialization.data(withJSONObject: legacyArrangementJSON)
        let decodedLegacyHeight = try JSONDecoder().decode(TypeDirection.self, from: legacyHeightJSON)
        try verify(decodedLegacyHeight.canvasHeight == nil,
                   "Legacy canvas JSON without canvasHeight must decode without migration")
        let heightLimitedPlan = CanvasPlan(direction: heightLimitedCanvas)
        let heightLimitedText = heightLimitedPlan.elements.first { $0.text != nil }!
        let originalHeightText = originalHeightPlan.elements.first { $0.textID == heightLimitedText.textID }!
        try verify(Double(heightLimitedPlan.artboardSize.height) == minimumTextSize.height && Double(heightLimitedPlan.size.height) == minimumTextSize.height
                   && heightLimitedText.rect == originalHeightText.rect
                   && heightLimitedText.text?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == originalHeightText.text?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                   "An independent height override must preserve text geometry while keeping a safe text margin")
        let persistedHeightCanvas = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(heightLimitedCanvas))
        try verify(persistedHeightCanvas.canvasHeight == Double(minimumTextSize.height) && persistedHeightCanvas.isValid,
                   "Independent artboard height must persist and remain valid")
        var resizedImported = TypeDirection(name: "Imported frame")
        resizedImported.canvas = .imported; resizedImported.width = 100
        resizedImported.importedLayout = ImportedLayout(width: 100, height: 100,
            layers: [ImportedLayer(name: "Overflow", x: 0, y: 0, width: 150, height: 140, color: "222222")])
        let legacyOverflowCanvas = resizedImported
        let legacyExpandedImported = CanvasPlan(direction: resizedImported)
        resizedImported.canvasWidth = 100; resizedImported.canvasHeight = 90
        let explicitlyBoundImported = CanvasPlan(direction: resizedImported)
        try verify(legacyExpandedImported.artboardSize == CGSize(width: 150, height: 140)
                   && explicitlyBoundImported.artboardSize == CGSize(width: 100, height: 90),
                   "Legacy imported overflow must remain visible until the user saves explicit artboard bounds")
        let noMotionImportedResize = CanvasBoardLayout.resized(canvas: legacyOverflowCanvas, artboardSize: legacyExpandedImported.artboardSize,
                                                               position: startPosition, edge: .right, by: .zero, zoom: 1)
        try verify(noMotionImportedResize.importedWidth == 150,
                   "The first imported edge gesture must start from the rendered legacy width without jumping")
        let verticalLegacyImportedResize = CanvasBoardLayout.resized(canvas: legacyOverflowCanvas,
            artboardSize: legacyExpandedImported.artboardSize, position: startPosition,
            edge: .bottom, by: CGSize(width: 0, height: 20), zoom: 1)
        try verify(verticalLegacyImportedResize.importedWidth == 150 && verticalLegacyImportedResize.height == 160,
                   "Vertical resize must retain an imported legacy canvas's already-expanded rendered width")
        let persistedImportedFrame = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(resizedImported))
        try verify(persistedImportedFrame.canvasWidth == 100 && persistedImportedFrame.canvasHeight == 90,
                   "Independent imported artboard dimensions must survive JSON round-trip")
        var boundedExportBoard = TypeBoard(); boundedExportBoard.directions = [heightLimitedCanvas]
        let boundedFigma = (FigmaLayoutExporter.payload(board: boundedExportBoard)["frames"] as! [[String: Any]])[0]
        try verify((boundedFigma["width"] as? CGFloat) == 960 && (boundedFigma["height"] as? CGFloat) == CGFloat(minimumTextSize.height),
                   "Figma export must preserve independently resized artboard dimensions")
        let boundedAdobe = try AdobeTypeSystemExporter.script(directions: [heightLimitedCanvas], title: "Bounded", target: .illustrator)
        try verify(boundedAdobe.contains("\"width\":960") && boundedAdobe.contains("\"height\":\(Int(minimumTextSize.height))"),
                   "Adobe export must preserve independently resized artboard dimensions")
        let boundedView = CanvasNativeView(plan: heightLimitedPlan)
        let boundedPDF = boundedView.dataWithPDF(inside: boundedView.bounds)
        guard let boundedProvider = CGDataProvider(data: boundedPDF as CFData),
              let boundedDocument = CGPDFDocument(boundedProvider), let boundedPage = boundedDocument.page(at: 1) else {
            throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Resized canvas PDF could not be read"])
        }
        let boundedBox = boundedPage.getBoxRect(.mediaBox)
        try verify(Int(boundedBox.width) == 960 && Int(boundedBox.height) == Int(minimumTextSize.height),
                   "Preview PDF must use independently resized artboard dimensions")
        var scaledHeightCanvas = heightLimitedCanvas
        scaledHeightCanvas.canvasScale = 2
        try verify(Double(CanvasPlan(direction: scaledHeightCanvas).artboardSize.height) == minimumTextSize.height * 2,
                   "Corner scaling must continue to scale an independently sized artboard uniformly")
        var exportBoundCanvas = heightLimitedCanvas
        exportBoundCanvas.canvasWidth = nil
        exportBoundCanvas.canvasHeight = 10_000
        try verify(exportBoundCanvas.maximumCanvasScale <= 1 && exportBoundCanvas.isValid,
                   "The maximum corner scale must include an explicit artboard dimension in export safety bounds")
        var positionedTextCanvas = TypeDirection(name: "Positioned text")
        let positionedTextSource = CanvasPlan(direction: positionedTextCanvas).elements.first { $0.textID != nil }!
        positionedTextCanvas.textPositions = [positionedTextSource.textID!: CanvasTextPosition(x: 900, y: 5_000)]
        let positionedTextPlan = CanvasPlan(direction: positionedTextCanvas)
        let positionedTextBounds = CanvasBoardLayout.textContentBounds(in: positionedTextPlan)
        try verify(Double(positionedTextPlan.artboardSize.width) >= positionedTextBounds.width
                   && Double(positionedTextPlan.artboardSize.height) >= positionedTextBounds.height
                   && positionedTextPlan.elements.filter { $0.text != nil }.allSatisfy { $0.rect.minX >= 0 && $0.rect.maxX <= positionedTextPlan.artboardSize.width && $0.rect.maxY <= positionedTextPlan.artboardSize.height },
                   "Saved custom text positions near the right and bottom edges must remain inside the board")
        var longTokenCanvas = TypeDirection(name: "Long token")
        longTokenCanvas.styles[TypeRole.display.rawValue]!.size = 160
        longTokenCanvas.styles[TypeRole.display.rawValue]!.tracking = 12
        longTokenCanvas.styles[TypeRole.display.rawValue]!.indent = 200
        longTokenCanvas.styles[TypeRole.display.rawValue]!.alignment = .right
        let longTokenSource = CanvasPlan(direction: longTokenCanvas).elements.first { $0.role == .display && $0.textID != nil }!
        longTokenCanvas.textOverrides = [longTokenSource.textID!: String(repeating: "W", count: 32)]
        let longTokenPlan = CanvasPlan(direction: longTokenCanvas)
        let longTokenBounds = CanvasBoardLayout.textContentBounds(in: longTokenPlan)
        let longTokenElement = longTokenPlan.elements.first { $0.textID == longTokenSource.textID }!
        let unwrappedStorage = NSTextStorage(attributedString: longTokenElement.text!)
        let unwrappedLayout = NSLayoutManager()
        let unwrappedContainer = NSTextContainer(containerSize: CGSize(width: 100_000, height: 100_000))
        unwrappedContainer.lineFragmentPadding = 0
        unwrappedLayout.addTextContainer(unwrappedContainer); unwrappedStorage.addLayoutManager(unwrappedLayout)
        unwrappedLayout.ensureLayout(for: unwrappedContainer)
        let unwrappedWidth = Double(unwrappedLayout.usedRect(for: unwrappedContainer).width)
        try verify(unwrappedWidth + 200 <= Double(longTokenElement.rect.width) + 0.5
                   && Double(longTokenPlan.artboardSize.width) >= Double(longTokenElement.rect.maxX) + 12
                   && longTokenElement.rect.maxX <= longTokenPlan.artboardSize.width
                   && Double(longTokenPlan.artboardSize.height) >= longTokenBounds.height,
                   "Indented right-aligned unbreakable text must get a drawable frame wide enough for the complete token and remain inside the artboard")
        let verticalLongTokenResize = CanvasBoardLayout.resized(canvas: longTokenCanvas,
            artboardSize: longTokenPlan.artboardSize, position: startPosition,
            edge: .bottom, by: CGSize(width: 0, height: 20), zoom: 1)
        try verify(verticalLongTokenResize.warning == nil && verticalLongTokenResize.width == longTokenCanvas.width
                   && (verticalLongTokenResize.height ?? 0) >= longTokenPlan.artboardSize.height + 20,
                   "Vertical resize must preserve a content-expanded generated width for an unbreakable token")
        var longTokenBoard = TypeBoard(name: "Long token export")
        longTokenBoard.directions = [longTokenCanvas]
        let longTokenFigma = (FigmaLayoutExporter.payload(board: longTokenBoard)["frames"] as! [[String: Any]])[0]
        let exportedLongToken = (longTokenFigma["elements"] as! [[String: Any]]).first { $0["text"] as? String == longTokenElement.text?.string }!
        try verify((exportedLongToken["width"] as? CGFloat) == longTokenElement.rect.width,
                   "Figma export must use the expanded drawable text frame")
        let longTokenAdobe = try AdobeTypeSystemExporter.script(directions: [longTokenCanvas], title: "Long token", target: .illustrator)
        try verify(longTokenAdobe.contains("\"width\":\(Int(longTokenElement.rect.width.rounded()))"),
                   "Adobe export must use the expanded drawable text frame")
        let blockedLongTokenResize = CanvasBoardLayout.resized(canvas: longTokenCanvas, artboardSize: longTokenPlan.artboardSize,
                                                               position: startPosition, edge: .right, by: .zero, zoom: 1)
        try verify(blockedLongTokenResize.warning != nil && blockedLongTokenResize.width == longTokenCanvas.width,
                   "An over-cap unbreakable token must cancel resize with an explanatory warning")
        var negativeTextCanvas = TypeDirection(name: "Negative import text")
        negativeTextCanvas.canvas = .imported; negativeTextCanvas.width = 320
        negativeTextCanvas.importedLayout = ImportedLayout(width: 320, height: 200,
            layers: [ImportedLayer(name: "Outside", x: -20, y: -10, width: 180, height: 80, color: "222222",
                                   style: TypeStyle(fontName: "Helvetica", size: 24, text: "Outside"))])
        let negativeTextPlan = CanvasPlan(direction: negativeTextCanvas)
        let blockedNegativeTextResize = CanvasBoardLayout.resized(canvas: negativeTextCanvas, artboardSize: negativeTextPlan.artboardSize,
                                                                  position: startPosition, edge: .right, by: CGSize(width: 20, height: 0), zoom: 1)
        try verify(blockedNegativeTextResize.warning != nil && blockedNegativeTextResize.importedWidth == negativeTextCanvas.canvasWidth,
                   "Imported text beyond the left or top edge must block resize until repositioned")
        arrangementA.canvasScale = 2
        let scaledPlan = CanvasPlan(direction: arrangementA), basePlan = CanvasPlan(direction: TypeDirection(name: "Canvas 1"))
        let scaledText = scaledPlan.elements.first { $0.role == .display && $0.text != nil }!
        let baseText = basePlan.elements.first { $0.role == .display && $0.text != nil }!
        let scaledShape = scaledPlan.elements.first { $0.color != nil && $0.radius > 0 }!, baseShape = basePlan.elements.first { $0.color != nil && $0.radius > 0 }!
        try verify(scaledPlan.artboardSize.width == basePlan.artboardSize.width * 2
                   && scaledPlan.artboardSize.height == basePlan.artboardSize.height * 2
                   && abs(scaledText.rect.width - baseText.rect.width * 2) <= 2
                   && scaledText.style!.size == baseText.style!.size * 2
                   && scaledShape.rect.width == baseShape.rect.width * 2
                   && scaledShape.radius == baseShape.radius * 2,
                   "Canvas resize must scale the artboard, text, and artwork together: artboard \(basePlan.artboardSize) -> \(scaledPlan.artboardSize), text \(baseText.rect.width)/\(baseText.style!.size) -> \(scaledText.rect.width)/\(scaledText.style!.size), shape \(baseShape.rect.width)/\(baseShape.radius) -> \(scaledShape.rect.width)/\(scaledShape.radius)")
        try verify(CanvasProofing.renderedLines(for: scaledText)?.count == CanvasProofing.renderedLines(for: baseText)?.count,
                   "Proportional resize must preserve text wrapping")
        var scaledExportBoard = TypeBoard(); scaledExportBoard.directions = [arrangementA]
        let scaledFigmaFrame = (FigmaLayoutExporter.payload(board: scaledExportBoard)["frames"] as! [[String: Any]])[0]
        let scaledFigmaText = (scaledFigmaFrame["elements"] as! [[String: Any]]).first { $0["role"] as? String == TypeRole.display.rawValue }!
        try verify((scaledFigmaFrame["width"] as? CGFloat) == scaledPlan.artboardSize.width
                   && (scaledFigmaText["fontSize"] as? Double) == scaledText.style!.size,
                   "Figma export must use the rendered artboard and typography dimensions")
        let scaledAdobeScript = try AdobeTypeSystemExporter.script(directions: [arrangementA], title: "Scaled", target: .illustrator)
        try verify(scaledAdobeScript.contains("\"fontSize\":128") && scaledAdobeScript.contains("\"width\":1920"),
                   "Adobe export must use proportionally scaled text and canvas dimensions")
        var positioned = TypeDirection()
        let normalPlan = CanvasPlan(direction: positioned)
        let selectedFrame = normalPlan.elements.first { $0.role == .display && $0.textID != nil }!
        let frameID = selectedFrame.textID!
        positioned.textPositions = [frameID: CanvasTextPosition(x: 12, y: 34)]
        let positionedPlan = CanvasPlanCache.plan(for: positioned)
        try verify(positionedPlan.elements.first { $0.textID == frameID }!.rect.origin == CGPoint(x: 12,y: 34), "Text position did not reach the canvas plan")
        try verify(positionedPlan.size == normalPlan.size && positionedPlan.elements.filter { $0.textID != frameID }.map(\.rect) == normalPlan.elements.filter { $0.textID != frameID }.map(\.rect), "Aligning text moved unrelated frames or changed the artboard")
        let positionRoundTrip = try JSONDecoder().decode(TypeDirection.self, from: JSONEncoder().encode(positioned))
        try verify(positionRoundTrip == positioned && positionRoundTrip.isValid, "Text positioning did not persist")
        positioned.textPositions = nil
        try verify(CanvasPlanCache.plan(for: positioned).elements.first { $0.textID == frameID }!.rect == selectedFrame.rect, "Reset text position did not restore template layout")
        positioned.textPositions = [frameID: CanvasTextPosition(x: .infinity, y: 0)]
        try verify(!positioned.isValid, "Nonfinite canvas coordinates were accepted")
        let parsedSearch = FontSearchQuery("Helvetica #\"Client Work/Approved\" #!typefield/italic")
        try verify(parsedSearch.text == "Helvetica" && parsedSearch.tokens.count == 2)
        let regular = catalog.flatMap(\.faces).first { $0.name == "Helvetica" }!
        try verify(parsedSearch.matches(regular, tags: ["Client Work/Approved"]))
        try verify(!FontSearchQuery("#!\"Client Work\"").matches(regular, tags: ["Client Work/Approved"]))
        try verify(FontSearchQuery("#typefield/regular #typefield/upright").matches(regular, tags: []), "Current Typefield property filters must match")
        try verify(!FontSearchQuery("#typefield/italic #!typefield/regular").matches(regular, tags: []), "Current Typefield includes and exclusions must be applied")
        try verify(FontSearchQuery("#fontshelf/regular #typeface/upright").matches(regular, tags: []), "Saved FontShelf and typeface aliases must still match")
        try verify(!FontSearchQuery("#fontshelf/italic #typeface/upright").matches(regular, tags: []), "Saved aliases must still exclude unmatched faces")
        try verify(FontSearchQuery.token("Client Work", excluded: true) == "#!\"Client Work\"")
        try verify(FontSearchQuery.removing("#tag", from: "#tag #tagged") == "#tagged", "Removing a token changed a different token")
        if let emoji = catalog.flatMap(\.faces).first(where: { $0.name == "AppleColorEmoji" }) { try verify(emoji.facts.color && FontSearchQuery("#typefield/color").matches(emoji, tags: []) && FontSearchQuery("#fontshelf/color").matches(emoji, tags: [])) }
        var query = TagQuery(included: ["Client", "Editorial"], excluded: ["Client/Archived"], matchAll: true)
        try verify(query.matches(["Client/Current", "Editorial"]))
        try verify(!query.matches(["Client/Archived", "Editorial"]))
        try verify(!query.matches(["Client/Current"]))
        query.matchAll = false; try verify(query.matches(["Editorial"]))
        try verify(!query.matches(["Clients"]))
        try verify(TagQuery.hierarchy(["Client/Brand/Approved"]) == ["Client", "Client/Brand", "Client/Brand/Approved"])
        let nested = root.appendingPathComponent("watched/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let a = nested.appendingPathComponent("sample.ttf")
        try Data([1,2,3]).write(to: a)
        let first = FontFolderSnapshot.read([nested.deletingLastPathComponent().path])
        try verify(first.files.count == 1 && first.errors.isEmpty)
        try Data([1,2,3,4]).write(to: a)
        let second = FontFolderSnapshot.read([nested.deletingLastPathComponent().path])
        try verify(second.files != first.files, "Font replacement went undetected")
        try FileManager.default.moveItem(at: a, to: nested.appendingPathComponent("renamed.otf"))
        let renamed = FontFolderSnapshot.read([nested.deletingLastPathComponent().path])
        try verify(renamed.files.keys.first?.hasSuffix("renamed.otf") == true)
        try verify(!FontFolderSnapshot.contains("/fonts-other/a.ttf", root: "/fonts"))
        try verify(!FontFolderSnapshot.read([root.appendingPathComponent("missing").path]).errors.isEmpty)
        let font = CTFontCreateWithName("Helvetica" as CFString, 100, nil)
        let glyphs = GlyphCatalog.entries(font: font)
        let capitalA = glyphs.first { $0.scalar?.value == 65 }!
        try verify(capitalA.matches("U+0041") && capitalA.matches("LATIN CAPITAL LETTER A"))
        try verify(glyphs.count == CTFontGetGlyphCount(font) - 1)
        try verify(GlyphCatalog.svg(font: font, glyph: capitalA.glyph)?.contains("<path") == true)
        var plans = 0
        var formatSignatures: Set<String> = []
        let defaultFormats: Set<CanvasKind> = [.website, .product, .editorial, .poster, .specimen]
        for kind in CanvasKind.allCases {
            let widths: [Double] = defaultFormats.contains(kind) ? [320, 390, 768, 960, 1200] : [390, 768, 960, 1200]
            for width in widths {
                var d = TypeDirection(); d.canvas = kind; d.width = width
                let plan = CanvasPlan(direction: d)
                if width == 960, defaultFormats.contains(kind) { formatSignatures.insert(templateGeometrySignature(plan)) }
                try verify(plan.size.height.isFinite && plan.size.width == width,
                           "\(kind.rawValue) at \(Int(width)) px expanded unexpectedly to \(plan.size.width) px")
                let clipped = plan.elements.first { $0.rect.minX < 0 || $0.rect.maxX > width + 1 || $0.rect.minY < 0 || $0.rect.maxY > plan.size.height }
                try verify(clipped == nil, "\(kind.rawValue) at \(Int(width)) px clipped \(clipped?.textID ?? clipped?.sectionID ?? "unknown") at \(String(describing: clipped?.rect))")
                if defaultFormats.contains(kind) { try verifyTemplateTextGeometry(plan, kind: kind, width: width) }
                if kind == .website {
                    try verify(plan.elements.filter { $0.sectionID == "Website:features" && $0.role == .subheading }.count == 3,
                               "Website must retain all three feature stories at \(Int(width)) px")
                    let bag = plan.elements.first { $0.textID == "Website:navigation|Caption|1" }
                    try verify(bag?.text?.string == "Bag (0)" && bag?.style?.alignment == .right &&
                               abs((bag?.rect.maxX ?? 0) - (width - (width < 500 ? 24 : 56))) < 1,
                               "Website bag must align with the right content edge at \(Int(width)) px")
                }
                if kind == .product {
                    let save = plan.elements.first { $0.textID == "Product UI:command|Caption|1" }
                    try verify(save?.text?.string.contains("SAVE") == true,
                               "Product UI quick capture needs a visible save action at \(Int(width)) px")
                    let metricNumbers = plan.elements.filter { $0.sectionID == "Product UI:metrics" && $0.role == .heading }
                    try verify(metricNumbers.count == 3 &&
                               metricNumbers.map(\.rect.minY).max()! - metricNumbers.map(\.rect.minY).min()! < 1,
                               "Product UI metrics must share a baseline at \(Int(width)) px")
                }
                if kind == .editorial {
                    try verify(plan.elements.filter { $0.sectionID == "Editorial:article" && $0.role == .body }.count == 1,
                               "Editorial must render one continuous article body at \(Int(width)) px")
                    let proofSample = plan.elements.first { $0.sectionID == "Editorial:image" && $0.role == .display }
                    try verify(proofSample.flatMap { CanvasProofing.contrast(for: $0, in: plan) }?.overlaid == false,
                               "Editorial proof-sheet rules must clear the displayed letters at \(Int(width)) px")
                }
                if kind == .poster {
                    let title = plan.elements.first { $0.sectionID == "Poster:poster-field" && $0.role == .display }
                    let contrast = title.flatMap { CanvasProofing.contrast(for: $0, in: plan) }
                    try verify((contrast?.minimum ?? 0) >= 3, "Poster display title needs readable large-text contrast at \(Int(width)) px")
                    let program = plan.elements.first { $0.textID == "Poster:poster-field|Caption|0" }
                    try verify(program?.text?.string.contains("FRI  LIVE SETS") == true,
                               "Poster must retain its event program at \(Int(width)) px")
                }
                if kind == .specimen {
                    let figures = plan.elements.first { $0.textID == "Type system:Display|Caption|1" }
                    try verify(figures?.text?.string == "FIGURES / 12",
                               "Type system figures need a label at \(Int(width)) px")
                }
                plans += 1
                if let first = plan.sections.first, let last = plan.sections.last, first.id != last.id {
                    d.reorder(first.id, target: last.id, before: false, visible: plan.sections.map(\.id))
                    let reordered = CanvasPlan(direction: d)
                    try verify(reordered.sections.last?.id == first.id && reordered.elements.count == plan.elements.count)
                    try verify(reordered.elements.allSatisfy { $0.rect.minY >= 0 && $0.rect.maxY <= reordered.size.height }, "Reorder clipped content")
                    d.hiddenSections = [last.id]
                    try verify(!CanvasPlan(direction: d).elements.contains { $0.sectionID == last.id })
                    d.hiddenSections = nil
                    try verify(CanvasPlan(direction: d).elements.count == plan.elements.count)
                }
            }
        }
        var savedEditorial = TypeDirection(); savedEditorial.canvas = .editorial; savedEditorial.width = 960
        let continuationID = "Editorial:article|Body|1"
        savedEditorial.textPositions = [continuationID: CanvasTextPosition(x: 120, y: 1500)]
        let restoredContinuation = CanvasPlan(direction: savedEditorial).elements.first { $0.textID == continuationID }
        try verify(restoredContinuation != nil && abs(restoredContinuation!.rect.minX - 120) < 1,
                   "A saved position for the legacy Editorial second body frame must keep that frame visible")
        var savedWebsite = TypeDirection(); savedWebsite.canvas = .website; savedWebsite.width = 960
        savedWebsite.textOverrides = ["Website:navigation|Caption|0": "My saved navigation and bag"]
        let savedNavigation = CanvasPlan(direction: savedWebsite).elements.filter { $0.sectionID == "Website:navigation" && $0.role == .caption }
        try verify(savedNavigation.count == 1 && savedNavigation.first?.text?.string == "My saved navigation and bag",
                   "Older customized Website navigation must not gain a duplicate bag label")
        var darkRailPoster = TypeDirection(); darkRailPoster.canvas = .poster; darkRailPoster.width = 960
        darkRailPoster.accent = "222222"; darkRailPoster.ink = "222222"
        let darkRailPlan = CanvasPlan(direction: darkRailPoster)
        for role in [TypeRole.mono, .label] {
            let railDetail = darkRailPlan.elements.first { $0.sectionID == "Poster:poster-field" && $0.role == role }
            try verify(railDetail.flatMap { CanvasProofing.contrast(for: $0, in: darkRailPlan) }?.minimum ?? 0 >= 4.5,
                       "Poster date and venue must remain readable when the accent matches the ink")
        }
        try verify(formatSignatures.count == defaultFormats.count, "Default formats must differ in actual text-and-shape geometry, not only section names")
        var specimenDirection = TypeDirection(); specimenDirection.canvas = .specimen
        let specimenIDs = Set(CanvasPlan(direction: specimenDirection).elements.compactMap(\.textID))
        for role in TypeRole.allCases {
            let section = CanvasKind.specimen.rawValue + ":" + role.rawValue
            let metadataID = section + "|" + TypeRole.caption.rawValue + "|0"
            let sampleID = section + "|" + role.rawValue + "|" + (role == .caption ? "1" : "0")
            try verify(specimenIDs.contains(metadataID) && specimenIDs.contains(sampleID),
                       "Type system must retain editable metadata and sample IDs for \(role.rawValue) in saved Spaces")
        }
        for kind in defaultFormats {
            var direction = TypeDirection(); direction.canvas = kind; direction.width = 960
            let plan = CanvasPlan(direction: direction)
            let pdf = CanvasNativeView(plan: plan).dataWithPDF(inside: CGRect(origin: .zero, size: plan.size))
            let document = CGDataProvider(data: pdf as CFData).flatMap(CGPDFDocument.init)
            let mediaBox = document?.page(at: 1)?.getBoxRect(.mediaBox)
            try verify(document?.numberOfPages == 1 && mediaBox != nil &&
                       abs((mediaBox?.width ?? 0) - plan.size.width) < 1 &&
                       abs((mediaBox?.height ?? 0) - plan.size.height) < 1,
                       "\(kind.rawValue) Preview PDF must contain a valid, correctly sized canvas page")
        }
        let figmaData = try JSONSerialization.data(withJSONObject: FigmaLayoutExporter.payload(board: board))
        let figma = try JSONSerialization.jsonObject(with: figmaData) as! [String: Any]
        try verify(figma["format"] as? String == "fontshelf-figma" && (figma["frames"] as? [[String: Any]])?.count == 2)
        let frames = figma["frames"] as! [[String: Any]]
        let boundedInput = root.appendingPathComponent("bounded-input.json")
        try Data("abcd".utf8).write(to: boundedInput)
        let boundedData = try TypefieldInputFile.read(boundedInput, maximumBytes: 4)
        try verify(boundedData == Data("abcd".utf8), "A file at the input limit must remain readable")
        var rejectedOversizedInput = false
        do { _ = try TypefieldInputFile.read(boundedInput, maximumBytes: 3) }
        catch { rejectedOversizedInput = true }
        try verify(rejectedOversizedInput, "Input readers must stop at the byte limit")
        let linkedFiles = root.appendingPathComponent("linked-saved-files")
        try FileManager.default.createDirectory(at: linkedFiles, withIntermediateDirectories: true)
        let linkedFixtures: [(String, Data)] = [
            ("spaces.json", try JSONEncoder().encode(StudioState())),
            ("library.json", try JSONEncoder().encode(SavedLibrary())),
            ("font-lab.json", try JSONEncoder().encode(FontLabState()))
        ]
        for (name, original) in linkedFixtures {
            let target = linkedFiles.appendingPathComponent("original-" + name)
            let link = linkedFiles.appendingPathComponent(name)
            try original.write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            var rejectedLink = false
            do { _ = try TypefieldInputFile.read(link, maximumBytes: 1_000_000) }
            catch { rejectedLink = true }
            try verify(rejectedLink, "Imported files must reject symbolic links")
            switch name {
            case "spaces.json":
                let linkedStore = StudioStore(url: link)
                try verify(linkedStore.readBlocked && linkedStore.addSpace("Should fail") == nil, "Spaces must preserve a linked saved file")
            case "library.json":
                let linkedLibrary = Library(storageURL: link)
                try verify(linkedLibrary.librarySaveBlocked && !linkedLibrary.save(), "Library must preserve a linked saved file")
            default:
                let linkedStore = FontLabStore(url: link)
                try verify(linkedStore.readBlocked && !linkedStore.save(), "Letterform Editor must preserve a linked saved file")
            }
            let targetData = try Data(contentsOf: target)
            try verify(targetData == original, "A linked file target changed")
        }
        var excessiveFrame = frames[0]
        var excessiveTextLayer = (excessiveFrame["elements"] as! [[String: Any]]).first { $0["kind"] as? String == "text" }!
        excessiveTextLayer["text"] = String(repeating: "A", count: 200_000)
        excessiveFrame["elements"] = Array(repeating: excessiveTextLayer, count: 26)
        var excessiveFigma = figma
        excessiveFigma["frames"] = [excessiveFrame]
        let excessiveData = try JSONSerialization.data(withJSONObject: excessiveFigma)
        var rejectedExcessiveText = false
        do { _ = try FigmaLayoutImporter.board(data: excessiveData, fonts: []) }
        catch { rejectedExcessiveText = error.localizedDescription.contains("too much text") }
        try verify(rejectedExcessiveText, "Figma import must bound aggregate text before creating a board")
        var unsafeFrame = frames[0]
        var unsafeLayers = unsafeFrame["elements"] as! [[String: Any]]
        unsafeLayers[0]["section"] = String(repeating: "x", count: 257)
        unsafeFrame["elements"] = unsafeLayers
        var unsafeFigma = figma
        unsafeFigma["frames"] = [unsafeFrame]
        var rejectedUnsafeName = false
        do { _ = try FigmaLayoutImporter.board(data: JSONSerialization.data(withJSONObject: unsafeFigma), fonts: []) }
        catch { rejectedUnsafeName = error.localizedDescription.contains("invalid name") }
        try verify(rejectedUnsafeName, "Figma import must bound untrusted layer names")
        let bodyLayer = (frames[1]["elements"] as! [[String: Any]]).first { $0["role"] as? String == TypeRole.body.rawValue }!
        try verify(bodyLayer["alignment"] as? String == "RIGHT" && bodyLayer["lineHeight"] as? Double == 32 && bodyLayer["kerning"] as? Bool == false)
        try verify((bodyLayer["features"] as? [String: Int])?["kern"] == nil, "Figma export must keep kerning out of generic feature settings")
        let library = Library(storageURL: root.appendingPathComponent("library-state/library.json")); library.acceptCatalog(catalog)
        let sample = catalog.flatMap(\.faces).first { $0.name == "Helvetica" }!
        let pdf = SpecimenExporter.data(faces: [sample], library: library, sample: "Hamburgefontsiv 0123456789")
        try verify(CGDataProvider(data: pdf as CFData).flatMap { CGPDFDocument($0) }?.numberOfPages == 1)
        let longPDF = SpecimenExporter.data(faces: [sample], library: library, sample: String(repeating: "Long preview text with complete words. ", count: 100))
        try verify((CGDataProvider(data: longPDF as CFData).flatMap { CGPDFDocument($0) }?.numberOfPages ?? 0) > 1, "Long specimens must paginate")
        library.saved.collections["Keep"] = [catalog[0].name]
        let usageName = catalog[0].representative.name
        library.saved.fontUsage = [usageName: FontUsageRecord(lastAppliedAt: Date(timeIntervalSinceReferenceDate: 20), applicationCount: 4)]
        var importedLibrary = library.saved
        importedLibrary.fontUsage = [usageName: FontUsageRecord(lastAppliedAt: Date(timeIntervalSinceReferenceDate: 30), applicationCount: 2)]
        let fontLabProjectIDValue = library.fontLab.addProject(name: "Backup lettering")
        try verify(fontLabProjectIDValue != nil, "Could not create Letterform Editor backup fixture")
        let fontLabProjectID = fontLabProjectIDValue!
        let fontLabStroke = FontLabStroke(points: [FontLabPoint(x: 0.2, y: 0.2), FontLabPoint(x: 0.8, y: 0.8)], width: 0.03)
        var fontLabGlyph = FontLabGlyph(character: "A")
        fontLabGlyph.strokes = [fontLabStroke]
        library.fontLab.setGlyph(fontLabGlyph, in: fontLabProjectID, save: true)
        let backup = LibraryBackup(library: importedLibrary, pro: library.pro, spaces: store.state, fontLab: library.fontLab.state)
        let backupData = try JSONEncoder().encode(backup)
        var legacyBackupObject = try JSONSerialization.jsonObject(with: backupData) as! [String: Any]
        legacyBackupObject.removeValue(forKey: "fontLab")
        let legacyBackupData = try JSONSerialization.data(withJSONObject: legacyBackupObject)
        let legacyBackup = try JSONDecoder().decode(LibraryBackup.self, from: legacyBackupData)
        try verify(legacyBackup.fontLab == nil, "Pre-Font-Lab version-1 backups must remain decodable")
        try LibraryBackupTools.merge(backup, into: library)
        try verify(library.saved.collections["Keep"] == [catalog[0].name])
        try verify(library.saved.fontUsage?[usageName] == FontUsageRecord(lastAppliedAt: Date(timeIntervalSinceReferenceDate: 30), applicationCount: 4), "Backup merge must keep the newest use date without double-counting applications")
        try verify(library.studio.state.spaces[0].id != store.state.spaces[0].id)
        try verify(library.studio.state.spaces[0].boards[0].id != store.state.spaces[0].boards[0].id, "Backup merge must give copied typeboards independent identities")
        try verify(library.studio.state.spaces[0].boards[0].directions[0].id != store.state.spaces[0].boards[0].directions[0].id, "Backup merge must give copied canvases independent identities")
        let importedFontLabProject = library.fontLab.state.projects.first { $0.id != fontLabProjectID }
        try verify(importedFontLabProject?.name == "Backup lettering (imported)" && importedFontLabProject?.glyphs["A"] == fontLabGlyph, "Backup merge must preserve Letterform Editor artwork in an independent project copy")
        try verify(FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
        try checkBackupSafety(in: root)
        try checkBackupCrashRecovery(in: root)
        print("PASS: typography and legacy decoding, section reorder/removal, Figma layout payload, search tokens, independent directions and relaunch persistence, corrupt workspace preservation, nested AND/OR/NOT tags, recursive folder changes, Unicode lookup/SVG, \(plans) responsive canvases, specimen PDF and Library/Spaces/Letterform Editor backup merge.")
    }

    private static func checkSpacesSaveRollback(in root: URL) throws {
        let fm = FileManager.default
        let parent = root.appendingPathComponent("spaces-save-failure")
        let savedParent = root.appendingPathComponent("spaces-save-failure-preserved")
        let store = StudioStore(url: parent.appendingPathComponent("spaces.json"))
        let space = try { () throws -> UUID in
            guard let id = store.addSpace("Before") else { throw NSError(domain: "TypefieldCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create Spaces rollback fixture"]) }
            return id
        }()
        guard let boardID = store.addBoard(space: space) else { throw NSError(domain: "TypefieldCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create typeboard rollback fixture"]) }
        store.undoManager.groupsByEvent = false
        let initialBoard = store.state.spaces[0].boards[0]
        let successfulCheckpoint = StudioCheckpointSave.save(direction: initialBoard.directions[0], board: initialBoard) { proposed in
            _ = store.update(space: space, board: proposed, action: "Save Checkpoint")
            return store.state.spaces[0].boards[0]
        }
        try verify(successfulCheckpoint.saved && successfulCheckpoint.board.checkpoints?.count == 1 && store.state.spaces[0].boards[0] == successfulCheckpoint.board, "A checkpoint is successful only after it appears in persisted typeboard state")
        var retentionBoard = initialBoard
        var oldestRetentionID: UUID?
        for index in 0...StudioCheckpointSave.maximumCount {
            retentionBoard = StudioCheckpointSave.save(direction: initialBoard.directions[0], board: retentionBoard) { $0 }.board
            if index == 0 { oldestRetentionID = retentionBoard.checkpoints?.first?.id }
        }
        try verify(retentionBoard.checkpoints?.count == StudioCheckpointSave.maximumCount
                   && retentionBoard.checkpoints?.first?.id != oldestRetentionID,
                   "Checkpoint retention must keep only the latest 50 copies")
        store.undoManager.removeAllActions()
        let original = try Data(contentsOf: store.url)
        let originalBoard = store.state.spaces[0].boards[0]
        try fm.moveItem(at: parent, to: savedParent)
        defer {
            try? fm.removeItem(at: parent)
            try? fm.moveItem(at: savedParent, to: parent)
        }
        try Data("Save obstruction".utf8).write(to: parent)
        try verify(store.addSpace("Unsaved") == nil && store.state.spaces.count == 1, "Failed space creation must roll back")
        try verify(store.addBoard(space: space) == nil && store.state.spaces[0].boards.count == 1, "Failed typeboard creation must roll back")
        try verify(store.createBoard(in: nil, defaultSpaceName: "Unsaved project") == nil && store.state.spaces.count == 1, "Failed first typeboard creation must roll back its new space")
        try verify(!store.renameSpace(space, to: "Unsaved") && store.state.spaces[0].name == "Before", "Failed space rename must roll back")
        var edited = originalBoard; edited.name = "Unsaved typeboard"
        try verify(!store.update(space: space, board: edited, action: "Rename Typeboard") && store.state.spaces[0].boards[0] == originalBoard && !store.undoManager.canUndo, "Failed typeboard edit must roll back without adding undo")
        let failedCheckpoint = StudioCheckpointSave.save(direction: originalBoard.directions[0], board: originalBoard) { proposed in
            _ = store.update(space: space, board: proposed, action: "Save Checkpoint")
            return store.state.spaces[0].boards[0]
        }
        try verify(!failedCheckpoint.saved && failedCheckpoint.board == originalBoard && store.state.spaces[0].boards[0] == originalBoard, "A failed checkpoint save must return the persisted board and report failure")
        try verify(!store.removeBoard(space: space, id: boardID) && store.state.spaces[0].boards[0] == originalBoard && !store.undoManager.canUndo, "Failed typeboard deletion must roll back without adding undo")
        try verify(!store.removeSpace(space) && store.state.spaces[0].id == space, "Failed space deletion must roll back")
        let importedSpace = DesignSpace(name: "Unsaved import", boards: [TypeBoard()])
        try verify(!store.importSpace(importedSpace) && store.state.spaces.count == 1, "Failed space import must roll back")
        try verify(!store.importBoard(TypeBoard(), into: nil, defaultSpaceName: "Unsaved import") && store.state.spaces.count == 1, "Failed typeboard import must roll back its new space and board")
        try verify(!store.importBoard(TypeBoard(), into: space, defaultSpaceName: "Unused") && store.state.spaces[0].boards.count == 1, "Failed typeboard import must roll back in an existing space")
        try verify(!store.select(space: space, board: nil) && store.focusedSpace == space && store.focusedBoard == boardID, "Failed focus save must restore the prior focus")
        try verify(!store.error.isEmpty && store.savedAt != nil, "Failed Spaces save must report its error and retain the last successful save time")
        let retained = try Data(contentsOf: savedParent.appendingPathComponent("spaces.json"))
        try verify(retained == original, "Failed Spaces operations must preserve the saved file")
        print("PASS: failed Spaces creates, edits, deletions, imports and selection roll back memory and undo while preserving saved data.")
    }

    private static func checkBackupSafety(in root: URL) throws {
        let fm = FileManager.default
        let badData = Data("not valid JSON".utf8)
        for filename in ["library.json", "pro-library.json", "spaces.json", "font-lab.json"] {
            let folder = root.appendingPathComponent("backup-corrupt-" + filename)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(filename)
            try badData.write(to: file)
            let source = Library(storageURL: folder.appendingPathComponent("library.json"))
            var refused = false
            do { _ = try LibraryBackupTools.snapshot(source) }
            catch { refused = true }
            try verify(refused, "Backup export must refuse an unreadable \(filename)")
            let retained = try Data(contentsOf: file)
            try verify(retained == badData, "Backup export changed unreadable \(filename)")
        }

        let invalid = Library(storageURL: root.appendingPathComponent("backup-invalid/library.json"))
        invalid.studio.state.spaces = [DesignSpace(name: "Invalid", boards: [TypeBoard(directions: [])])]
        var invalidRefused = false
        do { _ = try LibraryBackupTools.snapshot(invalid) }
        catch { invalidRefused = true }
        try verify(invalidRefused, "Backup export must refuse invalid in-memory project state")

        let folder = root.appendingPathComponent("backup-rollback")
        let target = Library(storageURL: folder.appendingPathComponent("library.json"))
        target.saved.favorites = ["Before"]
        target.pro.tags["Before"] = ["keep"]
        var originalSpace = DesignSpace(); originalSpace.name = "Before"
        originalSpace.boards = [TypeBoard()]
        target.studio.state.spaces = [originalSpace]
        target.studio.focusedSpace = originalSpace.id
        target.studio.focusedBoard = originalSpace.boards[0].id
        try verify(target.save() && target.savePro() && target.studio.save(), "Could not create backup rollback fixture")
        let projectID = target.fontLab.addProject(name: "Before")
        try verify(projectID != nil, "Could not create Letterform Editor rollback fixture")
        let names = ["library.json", "pro-library.json", "spaces.json", "font-lab.json"]
        let bytesBefore = try Dictionary(uniqueKeysWithValues: names.map { name in
            (name, try Data(contentsOf: folder.appendingPathComponent(name)))
        })
        let stableEncoder = JSONEncoder()
        stableEncoder.outputFormatting = .sortedKeys
        let libraryBefore = try stableEncoder.encode(target.saved)
        let proBefore = try stableEncoder.encode(target.pro)
        let spacesBefore = try stableEncoder.encode(target.studio.state)
        let fontLabBefore = try stableEncoder.encode(target.fontLab.state)

        var incomingLibrary = target.saved
        incomingLibrary.favorites.insert("Imported")
        var incomingPro = target.pro
        incomingPro.tags["Imported"] = ["new"]
        var incomingSpaces = StudioState()
        incomingSpaces.spaces = [DesignSpace(name: "Imported", boards: [TypeBoard()])]
        let incoming = LibraryBackup(library: incomingLibrary, pro: incomingPro, spaces: incomingSpaces, fontLab: target.fontLab.state)
        var failed = false
        do {
            try LibraryBackupTools.merge(incoming, into: target) { data, url in
                if url.lastPathComponent == "spaces.json" {
                    throw NSError(domain: "Typefield.BackupTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Injected late write failure"])
                }
                try data.write(to: url, options: .atomic)
            }
        } catch { failed = true }
        try verify(failed, "A later backup write failure must be reported")
        for name in names {
            let retained = try Data(contentsOf: folder.appendingPathComponent(name))
            try verify(retained == bytesBefore[name], "Backup rollback changed \(name)")
        }
        let memoryPreserved = try stableEncoder.encode(target.saved) == libraryBefore &&
            stableEncoder.encode(target.pro) == proBefore &&
            stableEncoder.encode(target.studio.state) == spacesBefore &&
            stableEncoder.encode(target.fontLab.state) == fontLabBefore
        try verify(memoryPreserved, "Backup rollback left partial in-memory changes")
        let leftovers = try fm.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".typefield-backup-import-") }
        try verify(leftovers.isEmpty, "Successful rollback left staged import files")
        print("PASS: backup export rejects unreadable/invalid sources; late import failures restore every source file and live state.")
    }

    private static func checkBackupCrashRecovery(in root: URL) throws {
        let fm = FileManager.default
        let names = ["library.json", "pro-library.json", "spaces.json", "font-lab.json"]
        var beforeLibrary = SavedLibrary(); beforeLibrary.favorites = ["Before"]
        var afterLibrary = beforeLibrary; afterLibrary.favorites.insert("After")
        var beforePro = ProState(); beforePro.tags["Before"] = ["keep"]
        var afterPro = beforePro; afterPro.tags["After"] = ["new"]
        var beforeSpaces = StudioState(); beforeSpaces.spaces = [DesignSpace(name: "Before", boards: [TypeBoard()])]
        var afterSpaces = beforeSpaces; afterSpaces.spaces.append(DesignSpace(name: "After", boards: [TypeBoard()]))
        var beforeFontLab = FontLabState(); beforeFontLab.projects = [FontLabProject(name: "Before", characters: ["A"])]
        var afterFontLab = beforeFontLab; afterFontLab.projects.append(FontLabProject(name: "After", characters: ["B"]))
        let oldBytes = [
            try JSONEncoder().encode(beforeLibrary), try JSONEncoder().encode(beforePro),
            try JSONEncoder().encode(beforeSpaces), try JSONEncoder().encode(beforeFontLab)
        ]
        let newBytes = [
            try JSONEncoder().encode(afterLibrary), try JSONEncoder().encode(afterPro),
            try JSONEncoder().encode(afterSpaces), try JSONEncoder().encode(afterFontLab)
        ]
        func setup(_ label: String, missingLibrary: Bool = false) throws -> (URL, [(URL, Data)]) {
            let folder = root.appendingPathComponent("backup-interrupted-" + label)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in names.indices where !(missingLibrary && index == 0) {
                try oldBytes[index].write(to: folder.appendingPathComponent(names[index]))
            }
            return (folder, names.indices.map { (folder.appendingPathComponent(names[$0]), newBytes[$0]) })
        }
        func verifyFiles(_ folder: URL, expected: [Data], missingLibrary: Bool = false) throws {
            for index in names.indices {
                let file = folder.appendingPathComponent(names[index])
                if missingLibrary && index == 0 {
                    try verify(!fm.fileExists(atPath: file.path), "Interrupted import must remove a newly created Library file")
                } else {
                    let recovered = try Data(contentsOf: file)
                    try verify(recovered == expected[index], "Interrupted import recovered the wrong \(names[index])")
                }
            }
            try verify(!fm.fileExists(atPath: LibraryBackupTools.journalURL(in: folder).path), "Recovered import left its journal")
            let leftovers = try fm.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".typefield-backup-import-") }
            try verify(leftovers.isEmpty, "Recovered import left staged copies")
        }

        do {
            let (folder, replacements) = try setup("prepared")
            _ = try LibraryBackupTools.prepareImport(replacements, in: folder)
            try newBytes[0].write(to: replacements[0].0, options: .atomic)
            try newBytes[1].write(to: replacements[1].0, options: .atomic)
            let reopened = Library(storageURL: replacements[0].0)
            try verify(reopened.saved.favorites == ["Before"] && reopened.pro.tags["After"] == nil,
                       "Startup must roll back an uncommitted import before reading saved stores")
            try verify(reopened.studio.state.spaces.count == 1 && reopened.fontLab.state.projects.count == 1)
            try verifyFiles(folder, expected: oldBytes)
        }
        do {
            let (folder, replacements) = try setup("committed")
            let journal = try LibraryBackupTools.prepareImport(replacements, in: folder)
            try newBytes[0].write(to: replacements[0].0, options: .atomic)
            try LibraryBackupTools.markImportCommitted(journal, in: folder)
            let reopened = Library(storageURL: replacements[0].0)
            try verify(reopened.saved.favorites.contains("After") && reopened.pro.tags["After"] == ["new"],
                       "Startup must finish a committed import before reading saved stores")
            try verify(reopened.studio.state.spaces.count == 2 && reopened.fontLab.state.projects.count == 2)
            try verifyFiles(folder, expected: newBytes)
        }
        do {
            let (folder, replacements) = try setup("missing-original", missingLibrary: true)
            _ = try LibraryBackupTools.prepareImport(replacements, in: folder)
            try newBytes[0].write(to: replacements[0].0, options: .atomic)
            try newBytes[1].write(to: replacements[1].0, options: .atomic)
            let reopened = Library(storageURL: replacements[0].0)
            try verify(reopened.saved.favorites.isEmpty && reopened.pro.tags["After"] == nil,
                       "Startup must restore the absence of a pre-import file")
            try verifyFiles(folder, expected: oldBytes, missingLibrary: true)
        }
        do {
            let (folder, replacements) = try setup("damaged-stage")
            let journal = try LibraryBackupTools.prepareImport(replacements, in: folder)
            try newBytes[0].write(to: replacements[0].0, options: .atomic)
            try fm.removeItem(at: folder.appendingPathComponent(journal.stageName + "/old-pro-library.json"))
            let reopened = Library(storageURL: replacements[0].0)
            try verify(reopened.backupRecoveryError != nil && reopened.librarySaveBlocked && reopened.proSaveBlocked &&
                       reopened.studio.readBlocked && reopened.fontLab.readBlocked,
                       "Damaged recovery copies must block all saved stores")
            let retained = try Data(contentsOf: replacements[0].0)
            try verify(retained == newBytes[0] &&
                       fm.fileExists(atPath: LibraryBackupTools.journalURL(in: folder).path),
                       "Damaged recovery must preserve partial files and the journal for manual repair")
        }
        do {
            let (folder, replacements) = try setup("non-file-target", missingLibrary: true)
            _ = try LibraryBackupTools.prepareImport(replacements, in: folder)
            let obstruction = replacements[0].0
            try fm.createDirectory(at: obstruction, withIntermediateDirectories: false)
            try Data("Keep me".utf8).write(to: obstruction.appendingPathComponent("sentinel"))
            let reopened = Library(storageURL: obstruction)
            try verify(reopened.backupRecoveryError != nil &&
                       fm.fileExists(atPath: obstruction.appendingPathComponent("sentinel").path),
                       "Recovery must not recursively delete a directory at an originally absent file path")
        }
        do {
            let (folder, replacements) = try setup("cleanup-failure")
            let journal = try LibraryBackupTools.prepareImport(replacements, in: folder)
            try LibraryBackupTools.markImportCommitted(journal, in: folder)
            let marker = LibraryBackupTools.journalURL(in: folder)
            try fm.setAttributes([.immutable: true], ofItemAtPath: marker.path)
            defer { try? fm.setAttributes([.immutable: false], ofItemAtPath: marker.path) }
            let blocked = Library(storageURL: replacements[0].0)
            try verify(blocked.backupRecoveryError != nil && blocked.librarySaveBlocked && blocked.proSaveBlocked &&
                       blocked.studio.readBlocked && blocked.fontLab.readBlocked && fm.fileExists(atPath: marker.path),
                       "A committed journal that cannot be removed must keep all stores read-only")
            try fm.setAttributes([.immutable: false], ofItemAtPath: marker.path)
            let reopened = Library(storageURL: replacements[0].0)
            try verify(reopened.backupRecoveryError == nil && reopened.saved.favorites.contains("After"),
                       "Committed import must finish after journal cleanup becomes possible")
            try verifyFiles(folder, expected: newBytes)
        }
        print("PASS: interrupted backup imports roll back prepared writes, complete committed writes, restore missing files, and fail closed on damaged copies, non-file targets, or cleanup failure.")
    }
}
