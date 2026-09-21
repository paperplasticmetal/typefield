import Foundation
import AppKit
import CoreText

enum StudioChecks {
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
        let folder = try DeveloperHandoff.write(title: board.name, boards: [board], catalog: catalog, parent: parent)
        func read(_ name: String) throws -> String { try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        try verify(files.count == 11 && files.contains("Typography.swift") && files.contains("Typography.kt"), "Complete handoff package")
        let fontFiles = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("fonts").path)
        try verify(fontFiles.isEmpty, "Never redistribute font binaries")
        let tokens = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("tokens.json"))) as! [String: Any]
        let styles = tokens["typography"] as! [String: [String: Any]]
        try verify(styles.count >= 14 && Set(styles.keys).count == styles.count, "All canvases, unique styles")
        let value = styles["b1-c1-display"]!["$value"] as! [String: Any]
        try verify((value["axes"] as? [String: Double])?["wght"] == 520, "Variable axes preserved")
        let html = try read("index.html"), css = try read("typography.css")
        try verify(!html.contains("<script>") && html.contains("&lt;script&gt;") && html.contains("café 🖋"), "HTML must escape sample text and retain Unicode")
        try verify(css.contains("clamp(") && css.contains("\"wght\" 520") && css.contains("font-display: swap") && css.contains("font-feature-settings: \"kern\" 0, \"liga\" 0") && css.contains("font-kerning: none"), "CSS carries axes, features, kerning and loading policy")
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
    static func integration(source: URL) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FontShelf-activation-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(source.lastPathComponent)
        let manager = ActivationManager(journal: root.appendingPathComponent("activation.json"))
        defer { manager.clear(restore: false); CTFontManagerUnregisterFontsForURL(target as CFURL, .process, nil); try? FileManager.default.removeItem(at: root) }
        func check(_ condition: Bool, _ message: String) throws { if !condition { throw NSError(domain: "FontShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
        let watcher = FolderWatcher()
        var initialized = false, changes = 0
        watcher.configure(roots: [root.path], initialized: { _ in initialized = true }) { _ in changes += 1 }
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
        let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(target as CFURL) as? [CTFontDescriptor])!.first!
        let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as! String
        let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--font-available", name]
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0, "Session font was not visible to a separate process")
        try manager.deactivate(target)
        try check(!manager.owns(target) && CTFontManagerGetScopeForURL(target as CFURL) == .process, "Deactivation did not restore preview scope")
        let prior = changes
        try FileManager.default.removeItem(at: target)
        try check(wait { changes > prior }, "Watcher did not detect deletion")
        FontCatalog.reconcileFolders([root.path])
        try check(FontCatalog.registeredFiles[target.path] == nil, "Removed font remained registered")
        withExtendedLifetime(watcher) {}
        print("PASS: live recursive watcher, original-file preview, temporary activation visible to a separate process, deactivation and removal reconciliation.")
    }
    static func run(catalog: [Family]) throws {
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
        visible.remove(canvasA)
        try verify(CanvasVisibility.prune(visible, valid: [canvasA, canvasC], selected: canvasC) == [canvasC] && CanvasVisibility.solo(canvasB) == [canvasB], "Canvas hide, prune and solo state")
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
        var inserted = TypeDirection(); let beforeInsert = CanvasPlan(direction: inserted)
        let insertedID = inserted.insert(.heading, target: beforeInsert.sections[1].id, before: true, visible: beforeInsert.sections.map(\.id))
        let afterInsert = CanvasPlan(direction: inserted)
        try verify(afterInsert.sections.map(\.id).firstIndex(of: insertedID) == 1, "Dragged type role was not inserted at its drop position")
        try verify(afterInsert.elements.contains { $0.sectionID == insertedID && $0.role == .heading && $0.text?.string == inserted.style(.heading).text }, "Dragged role must carry its saved style and sample text")
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
        try verify(importedFirst.importedLayout?.layers.first?.style?.fontName == "Helvetica", "Imported font mapping failed")
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
        restored.focusedSpace = space; restored.focusedBoard = edited.id
        restored.state.spaces.removeAll { $0.id == space }
        try verify(restored.save(), "Deleting a space should save a normalized selection")
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
        let shape = ImportedLayer(name: "Shape", x: 0, y: 0, width: 100, height: 100, color: "FFFFFF")
        let text = ImportedLayer(name: "Text", x: 0, y: 0, width: 100, height: 40, color: "000000", style: TypeStyle(fontName: "Helvetica", size: 18, text: "Text"))
        let importedLayout = ImportedLayout(width: 100, height: 100, layers: [shape, text])
        try verify(importedLayout.textLayerIndex(selectedID: shape.id) == nil && importedLayout.textLayerIndex(selectedID: nil) == 1, "Selecting an imported shape must not redirect to the first text layer")
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
        let parsedSearch = FontSearchQuery("Helvetica #\"Client Work/Approved\" #!fontshelf/italic")
        try verify(parsedSearch.text == "Helvetica" && parsedSearch.tokens.count == 2)
        let regular = catalog.flatMap(\.faces).first { $0.name == "Helvetica" }!
        try verify(parsedSearch.matches(regular, tags: ["Client Work/Approved"]))
        try verify(!FontSearchQuery("#!\"Client Work\"").matches(regular, tags: ["Client Work/Approved"]))
        try verify(FontSearchQuery("#fontshelf/regular #typeface/upright").matches(regular, tags: []))
        try verify(!FontSearchQuery("#fontshelf/italic #fontshelf/upright").matches(regular, tags: []))
        try verify(FontSearchQuery.token("Client Work", excluded: true) == "#!\"Client Work\"")
        try verify(FontSearchQuery.removing("#tag", from: "#tag #tagged") == "#tagged", "Removing a token changed a different token")
        if let emoji = catalog.flatMap(\.faces).first(where: { $0.name == "AppleColorEmoji" }) { try verify(emoji.facts.color && FontSearchQuery("#fontshelf/color").matches(emoji, tags: [])) }
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
        for kind in CanvasKind.allCases {
            for width in [390.0, 768, 960, 1200] {
                var d = TypeDirection(); d.canvas = kind; d.width = width
                let plan = CanvasPlan(direction: d)
                if width == 960, ![CanvasKind.custom, .imported].contains(kind) { formatSignatures.insert(plan.sections.map(\.title).joined(separator: "|")) }
                try verify(plan.size.height.isFinite && plan.size.width == width)
                try verify(plan.elements.allSatisfy { $0.rect.minX >= 0 && $0.rect.maxX <= width + 1 && $0.rect.minY >= 0 && $0.rect.maxY <= plan.size.height }, "Canvas clipped content")
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
        try verify(formatSignatures.count == 5, "Website, product UI, editorial, poster and type-system compositions must remain distinct")
        let figmaData = try JSONSerialization.data(withJSONObject: FigmaLayoutExporter.payload(board: board))
        let figma = try JSONSerialization.jsonObject(with: figmaData) as! [String: Any]
        try verify(figma["format"] as? String == "fontshelf-figma" && (figma["frames"] as? [[String: Any]])?.count == 2)
        let frames = figma["frames"] as! [[String: Any]]
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
        try verify(fontLabProjectIDValue != nil, "Could not create Font Lab backup fixture")
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
        let importedFontLabProject = library.fontLab.state.projects.first { $0.id != fontLabProjectID }
        try verify(importedFontLabProject?.name == "Backup lettering (imported)" && importedFontLabProject?.glyphs["A"] == fontLabGlyph, "Backup merge must preserve Font Lab artwork in an independent project copy")
        try verify(FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
        print("PASS: typography and legacy decoding, section reorder/removal, Figma layout payload, search tokens, independent directions and relaunch persistence, corrupt workspace preservation, nested AND/OR/NOT tags, recursive folder changes, Unicode lookup/SVG, \(plans) responsive canvases, specimen PDF and Library/Spaces/Font Lab backup merge.")
    }
}
