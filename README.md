# Typefield

[![macOS build](https://github.com/paperplasticmetal/typefield/actions/workflows/build.yml/badge.svg)](https://github.com/paperplasticmetal/typefield/actions/workflows/build.yml)

Native macOS workspace for organizing fonts, exploring typography in typeboards, and drawing editable letterforms.

## Download the beta

**Typefield 0.59.8 beta 1 (build 88)** is a free beta for Apple silicon Macs running macOS 13 or newer. No account, activation key, or purchase is required.

[Download from the website](https://typefield.pages.dev/download/) | [Download from GitHub](https://github.com/paperplasticmetal/typefield/releases/download/v0.59.8-beta.1/Typefield-0.59.8-beta.dmg) | [Release notes](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.8-beta.1)

The [source repository](https://github.com/paperplasticmetal/typefield) contains the app and build scripts; see [License](#license) for reuse terms.

1. Open the downloaded `.dmg` and drag **Typefield** into **Applications**.
2. Eject the disk image, then open Typefield from Applications. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** for Typefield.
3. Take the four-step tour to explore Library, Spaces and Letterform Editor. You can skip it and reopen it from **Help → Getting Started Tour…**.

See [build and verification status](docs/STATUS.md) for completed checks and remaining device coverage.

Share your experience in the [beta feedback tracker](https://github.com/paperplasticmetal/typefield-feedback/issues/new?template=beta_feedback.md), [report a bug](https://github.com/paperplasticmetal/typefield-feedback/issues/new?template=bug_report.md), or [browse existing reports](https://github.com/paperplasticmetal/typefield-feedback/issues). Redact personal paths and data; do not attach proprietary font files.

## Explore Typefield

- **Library:** Browse and organize installed fonts and selected folders; compare families, inspect styles and glyphs, and build collections and saved searches.
- **Spaces:** Try fonts in editable website, product UI, editorial, poster and type-system canvases; compare directions and export specifications or PDFs.
- **Letterform Editor:** Draw or import artwork, edit Bézier outlines and spacing, then export finished glyphs as SVG or a static TrueType font.

**Developer handoff:** In a typeboard, choose **Export → Developer handoff…** for all its canvases, or use the space actions menu to export the whole project. One folder contains `@font-face` declarations, axes/features, CSS variables and suggested fluid `clamp()` scales, fallback stacks, preload examples, font-display guidance, Tailwind v3/v4 setup, versioned token JSON, SwiftUI and Compose starter definitions, and a standalone printable HTML specimen. Font binaries are never bundled: supply licensed web/app assets at the manifest paths. The README documents defaults and native integration work; the specimen is a typography reference, not a pixel-perfect layout export.

**Rename:** Click a selected space, typeboard or collection name to edit it directly, in the sidebar or main header. Double-click an unselected name to rename it. Return saves; Escape cancels. Sidebar context menus also offer Rename. Collection renaming preserves membership and selection and prevents overwriting an existing collection.

**Create a typeboard from fonts:** Multi-select families anywhere in Library, including Favorites and collections, then choose **Batch actions → Create typeboard**. The selection bar shows how many families and styles are affected, including families outside the current filter. **Select visible** replaces the selection with the current results. In Shortlist, check any subset, choose each family's style and use **Create typeboard**. Before anything is created, Typefield shows all seven roles—Display, Heading, Subheading, Body, UI, Caption and Monospace—with a resettable suggested assignment. Every role remains editable in Spaces.

**Font pairing suggestions:** In a Spaces canvas, select a type role and choose **Pair this font with another role…**. Pick the target role, then compare Safe, Balanced and Expressive suggestions from the fonts already on this Mac. Typefield previews the source and candidate together, exposes language/proportion/role/contrast reasons and relative scoring signals, and applies the result to the target role without replacing the source. These are explainable starting points, not universal taste scores or cloud-generated answers.

**Roadmap:** [Prioritized outstanding work and competitor references](docs/ROADMAP.md), the [production readiness audit](docs/PRODUCTION_READINESS.md), and the [app rebrand plan](docs/REBRAND_PLAN.md).

**Spaces typography:** Compact Character, Paragraph, list and canvas-alignment controls make text editing easier to navigate. The inspector says whether a change affects every use of a role or only one imported text layer. [Controls and behavior](docs/SPACES_TYPOGRAPHY.md).

**Adobe round trip:** From a typeboard's typography summary, export an Illustrator or InDesign builder. Run the saved JSX inside Adobe to create a new editable native `.ai` or `.indd` document with artboards/pages, live text, simple shapes, named character/paragraph styles and hidden interchange metadata. To come back, export the Illustrator/InDesign return bridge from Spaces, run it on a document or selection, then import its JSON through **Spaces → Import → Adobe return JSON…**. Font files are never bundled. Native `.ai`/`.indd` decoding, live sync, mixed inline-style reconstruction, effects, clipping, rotation, columns, linked stories, variable-axis application and arbitrary OpenType fidelity are not promised; import notes identify what needs review.

**Letterform Editor:** Switch to the third workspace to draw from scratch or import your own letter artwork. Use **Vector** for Bézier drawing, node/handle editing, rectangles/ellipses, contour/counter operations, overlap removal, transforms and precision coordinates. Zoom, pan and snap to the grid and guides; use Undo/Redo for canvas edits. Click a letter in the word preview to edit it. **Sketch** retains freehand drawing and polygon Reshape. [Vector workflow and shortcuts](docs/FONT_LAB_VECTOR.md). **Delete** moves an experiment to **Deleted projects**, where it can be restored after relaunch. Draw with Round, Marker or Outline nibs or a whole-stroke Eraser, adjust tool size and Off/Gentle/Strong smoothing, resize the character rail to expand the canvas, tune shared vertical metrics and per-glyph side bearings, and preview completed glyphs in words. A font can be exported after drawing only some letters; undrawn characters are omitted. Export one, selected or all drawn glyphs as SVG, or build a uniquely identified installable OpenType font with TrueType outlines (`.ttf`) that Typefield validates through Core Text before saving. Choose **Import artwork** for PNG/JPEG/TIFF/HEIC, outlined SVG or a Procreate embedded preview. Import a single letter or a whole alphabet sheet, review suggested labels and traced shapes, or use grid/manual regions and supply the letter order. Counters and detached dots become editable contours. Existing glyphs are kept unless you choose replacement; **Undo import** restores an existing project. Procreate layers are not decoded: export PNG for full resolution. SVG is rendered and traced, so original Bézier control points are not retained. **Components & masters** adds linked components, separate editable masters, kerning groups/pair exceptions and additional Unicode characters. **Smooth trace…** fits imported polygon outlines into editable curves with a before/after preview. [Design controls and current limits](docs/FONT_LAB_DESIGN.md). Missing-letter generation is paused and hidden while the local research implementation is retained for future work. Two compatible masters can export as one variable weight TrueType font; mismatched contours, vertical metrics or kerning are rejected. Broader master interpolation and opt-in model-backed AI generation remain future work.

For longer projects, filter the character rail to **All**, **Drawn** or **Empty**, jump to a character, and resize or collapse the word-proof strip. The Edit menu follows the current glyph's Undo/Redo history. Before SVG or TrueType export, a review explains the exact scope; the TrueType result reports unsupported or empty characters it omits. SVG import creates traced outlines and does not retain the source file's original control points, groups or transforms.

Mouse and trackpad drawing work directly. For Apple Pencil, set up Apple's Sidecar and move or mirror the Typefield window onto the iPad; for another drawing tablet, use its normal macOS connection and driver. Typefield reads the standard tablet events macOS supplies rather than pairing USB or Bluetooth hardware itself. When Pressure is enabled, reported pressure changes the round pen's thickness. Reported tilt is captured with the stroke for future tools, but the current round nib does not rotate with tilt.

Spaces contain typeboards, and typeboards contain canvases. Selecting another canvas keeps the current comparison visible; use **Only this**, each comparison's close button, or the **Shown** menu to hide it again. **Show all** displays every canvas, while Quick A/B solos two same-size alternatives for rapid switching. **Add canvas** creates a blank canvas or duplicates the current one. Drag a canvas border to arrange canvases freely on the typeboard; drag a corner handle to resize the entire canvas proportionally, including its type and artwork. Double-click canvas text to edit it in place; Return inserts a line, Command-Return saves, and Escape cancels. Click text or a type role to locate its exact canvas use, or drag a role onto the active canvas to add its saved sample text and settings. The font chooser includes collections, favorites, categories (including your overrides), and #tag search. Pinch over the canvas viewport, or use ⌘ + mouse-wheel scrolling, to zoom; ordinary scrolling pans and the zoom menu returns to **Fit width**.

Choose **Artwork…** or drop an SVG, PNG, JPEG, TIFF, HEIC, BMP or GIF from Finder onto a canvas to place it there. Typefield embeds a normalized image in the typeboard, so the original file can move after import. Move, resize, reorder and hide artwork in Arrangement; canvas previews and PDFs include it. SVG artwork is rendered as an image on import, and editable Figma and Adobe exports omit embedded images with a warning.

Each canvas toolbar opens a typography summary for the typeboard. The currently shown canvas starts selected, and a visible checkbox row lets you include any subset before copying or exporting a compact font-only list, a font-and-role map, or full typography specifications with size, line height, tracking, variable axes and OpenType features. Export plain text or Markdown, or generate a multi-page type-system PDF whose specimen pages retain each selected canvas's chosen fonts and settings. The same panel can create a Library collection from the active canvas, its complete typeboard, or the entire project, deduplicated by font family. Website, product UI, editorial and poster formats use purpose-specific compositions rather than the same generic stack.

Before a Spaces export, a review identifies its scope, unavailable fonts, image layers a format omits, and any unsupported canvas selection. After a Figma, Adobe or Space JSON import, a report counts typeboards, canvases, text layers, missing fonts and import notes. Deleting a Space names the affected typeboards and can be undone with ⌘Z. Each typeboard keeps at most 50 saved checkpoints; the oldest is replaced when the limit is reached.

The typography summary also includes a **Web font cost** audit for the selected canvases and styles. It reports exact WOFF2 bytes only when a file maps unambiguously to the chosen face, labels coverage as exact-file, desktop-font-only or unavailable, totals known download weight, identifies selected styles that could be excluded, compares compatible variable and static payloads, and estimates fallback changes in x-height, line wrapping and control width. Missing or duplicate PostScript-name matches are shown explicitly instead of being counted as known web assets. Add licensed web-font folders from the panel when the installed desktop font is not itself a WOFF2 file.

**Saved searches:** Set Library search, category, tags, source, writing system, sorting or coverage filters, then choose **Tools → Organization → Save current search…**. Saved searches appear in the sidebar, restore their preview text, and recompute against the current catalog. Right-click one to delete it.

**Live folders:** Add font folder explains recursive watching in the picker, then opens the folder manager. **Live folders** is always accessible in the Library sidebar. Watching updates additions, replacements and removals while the app is open; activation for other apps remains a separate opt-in. An unavailable location is reported separately from expired permission. **Choose Folder Again** replaces the saved location and keeps its activation choice. Local development builds pause saved watches that include Desktop, Documents or Downloads on launch to avoid repeated macOS permission prompts; a protected watch also pauses if a later scan encounters an access error. **Resume watching…** lets you explicitly choose one again. Other readable folders do not require a sandbox security scope.

**Font health:** Open **Tools → Font Health** to scan user fonts and watched folders, or choose **Inspect font file…** from a family's action menu. Typefield checks SFNT structure, required tables, bounds, overlaps, checksums and common name-table failures, then separates actual warnings/errors from optional compatibility notes. Proposed fixes are individually reviewable. Export creates a new Core Text-validated copy; in-place repair is limited to eligible writable user or watched fonts, explains why the original cannot be repaired when disabled, requires a separate confirmation, and keeps a `.typefield-backup` beside the original. System fonts, TTC/OTC collections, unsupported containers and ambiguous identity conflicts remain inspection-only.

## Features

- Browse installed fonts and user-selected font folders; search, sort, and filter by source, category, script, weight, and OpenType features.
- Editable previews with adjustable size, adaptive grids, wrapping, and aligned baselines.
- View every style in a family, tune variable axes, inspect OpenType features, and preview body text layouts.
- Cyan/orange overlay comparison within a family or across the library; a six-family comparison shortlist.
- Favorites, collections, multi-tagging, family grouping, last import, and duplicate detection.
- Local-only **Find similar** recommendations based on font metadata and explainable visual signals, plus **Rediscover** suggestions that favor fonts you have not used recently. Screenshot matching is not part of this release.
- Google variable fonts with real previews before download. Preview text stays local; public font files are fetched from Google's repository on GitHub.
- Original-file export and temporary session activation. Adobe type-system and return-bridge JSX scripts create native documents or bounded interchange when run inside Adobe; Typefield does not remotely control Adobe applications.
- Neutral light/dark appearances, optional accent colors for controls and selections, and native Liquid Glass on supported macOS versions.
- Spaces separate from collections, pairing typeboards, saved directions and checkpoints. Tune seven type roles with font, variable axes, OpenType, spacing, text and color settings, including direct hex color entry, with explainable local pairing suggestions.
- Letterform Editor projects with reviewed image/SVG/Procreate-preview artwork import, live previews, cubic Bézier drawing and node/handle editing, contour operations, transforms, zoom/pan, Undo/Redo, recoverable deletion, Round/Marker/Outline drawing, erasing, smoothing, native tablet pressure, labeled metrics, a resizable character rail, partial-glyph SVG export and validated installable TrueType generation.
- Website, product UI, editorial, poster, type-system and ordered custom-layout canvases; responsive widths, side-by-side directions, PDF export and portable space files.
- Unicode/glyph browsing and search, metrics, outline previews, SVG export/drag, waterfall previews and paginated specimen PDFs.
- Nested tags with AND/OR inclusion and exclusion; font metadata table and individually confirmed exact-duplicate removal to Trash.
- Local font-health inspection with conservative name-table/checksum repairs, before/after identity summaries, repaired-copy export and backed-up in-place repair for writable user fonts.
- Recursive watched folders refreshed every three seconds while open, with opt-in temporary activation for other apps using original files. No copying into system font folders.
- Selected-canvas web-font cost audits with exact WOFF2 provenance, ambiguity reporting, Unicode/script coverage, compatible variable-versus-static comparisons, fallback-layout probes and removable-style estimates.
- Daily local state backups and merge-based backup import. An interrupted import is recovered from staged copies before saved projects open; if recovery cannot be verified, editing is blocked to preserve those files. Folder access permissions must be granted separately.

Library, Spaces and Letterform Editor share one stable workspace sidebar, including the same Typefield mark and three-way workspace switcher in the same position. Use the header control or **View → Hide Sidebar** (Control-Command-S) to reclaim the full window; the choice persists across workspace switches and relaunches, and a large connected pull-tab on the left edge restores it. Shared cards, glass sidebars and Letterform Editor's native canvases are clipped to their rounded outlines so their backgrounds stay inside the border. Spaces has a resizable inspector with alignment, kerning, exact line height, tracking, paragraph/word spacing, indents, case and decorations. **Font kerning** uses or suppresses the font designer's built-in pair spacing (for combinations such as AV or To); it is independent of the explicit Letter spacing value. Drag sections in the arrangement list or directly on the canvas. Choose an A/B partner with the same format and width, then use **Swap A/B** (Command-backslash). Fit zoom adapts to panel resizing.

With a Spaces canvas focused, arrow keys select its sections and text objects; Return edits selected text, Command-Option-Up/Down reorders a selected section or layer, and Option-arrow nudges imported layers. Letterform Editor uses Option-Left/Right to select the previous or next contour or node, with Shift to extend selection. VoiceOver exposes these objects and their available actions. Spaces proofing reports wrapped lines and samples saved background fills; overlapping artwork and actual glyph shapes can change the final contrast.

The 0.28 Letterform Editor persistence path keeps an active gesture local until mouse-up, coalesces stroke/selection/project edits, snapshots large generated projects and performs compact deterministic encoding and disk I/O on a serial utility queue. Catalog face/family indexes, one-pass Library sidebar counts and finalist-only pairing/similarity explanations remain in place. Exact machine-specific measurements live in the status page after release verification.

Search accepts `#tag`, `#!tag`, and quoted names such as `#"Client Work"`. Typing `#` opens tag and font-property suggestions. Built-ins include `#typefield/active`, `#typefield/user`, `#typefield/bold`, `#typefield/italic`, and `#typefield/feature/tnum`; `#fontshelf/` and `#typeface/` remain compatibility aliases for saved searches. Tokens combine with AND and match the same style. A parent tag includes its descendants. Removable search chips show active filters. Saved searches restore the visible preview text used by character-coverage filtering; the metadata table shows only matching styles. **Clear filters** keeps the current Library section selected.

**Figma round trip:** Use the typeboard's **Export** menu to create an editable Figma package. The bundled local plugin can also export selected Figma frames; import that JSON using **Spaces → Import → Figma typeboard…**. Imported text layers can be edited independently and moved directly on the canvas. Selected simple shapes support fill, corner radius, stroke color, stroke opacity and stroke width. Fonts must be available on each side. Native `.fig` files, live sync and full Figma fidelity are not supported; unsupported elements/settings are reported. See [bridge instructions](Resources/FigmaImport/README.md) and [interaction checks](docs/INTERACTION_AUDIT.md).

Current limits include native Adobe-file decoding and live sync, production-compatible master interpolation, advanced GPOS kerning export, model-backed font generation, a published Figma plug-in, document-triggered activation, third-party collection database import, screenshot-based font matching and cloud team collaboration. Session activation is verified in the local development build; App Store sandbox verification remains outstanding.

### Settings and icon designs

Open **Typefield → Settings…** (⌘,) or the Library sidebar gear. The workspace uses Porcelain's neutral light and dark surfaces. Choose Porcelain, Turmeric, Indigo, Neem, Jamun, or Rose as an accent for controls and selections. The App Icon pane offers six designs: clean Porcelain, layered Paper Play, typographic Type Study, pen-drawn Ink Sketch, textured Chalkboard, and dimensional Pressed Type. Each has one preview. The Dock icon can follow the app or stay Light/Dark independently of app and macOS appearance. Selections persist; Finder uses the bundled Porcelain light icon. Accent colors do not recolor font previews or saved typeboards.

Icon artwork is generated from native type outlines by `scripts/make-icon.swift`; its header documents the compilation command. The same renderer powers Settings previews and the Dock.

## Build from source

Requirements: an Apple silicon Mac running macOS 13 or newer, full **Xcode 26 or later** selected as the active developer directory, and its command-line tools. Intel binaries are not shipped.

```sh
git clone https://github.com/paperplasticmetal/typefield.git
cd typefield
./install-local.sh
open /Applications/Typefield.app
```

The installer builds, runs the native checks, and installs an ad hoc signed local app at `/Applications/Typefield.app`. Pass another destination path to `install-local.sh` if needed. No paid Apple account is required for a local build. To build and test without installing, run:

```sh
bash build.sh
node tests/figma-import.test.js
```

For Xcode, open `Typefield.xcodeproj` and select the shared **Typefield** scheme. Build without distribution credentials:

```sh
xcodebuild -project Typefield.xcodeproj -scheme Typefield \
  -configuration Release -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

`Package.swift` supports source-level development, but the scripts/Xcode target create the complete app bundle with icons, privacy manifest, and Google catalog.

## Sandbox and App Store

```sh
./build-sandbox.sh
```

This creates a separate sandbox/hardened-runtime development app in `dist/`. A Store release needs an active paid Developer team and a registered production bundle identifier:

```sh
TEAM_ID=YOUR_TEAM_ID APP_BUNDLE_ID=com.yourcompany.typefield ./archive-store.sh
```

That command archives only; it does not upload. Validate and distribute through Xcode Organizer. See [App Store readiness](docs/APP_STORE.md).

## Status and documentation

- [Build and verification status](docs/STATUS.md)
- [Changelog](CHANGELOG.md)
- [Contribution guidelines](CONTRIBUTING.md)
- [Security reporting](SECURITY.md)
- [Architecture and design guidelines](docs/DEVELOPMENT.md)
- [Privacy](docs/PRIVACY.md)
- [Third-party metadata](THIRD_PARTY_NOTICES.md)

The workflow badge reflects GitHub CI. Local checks and manual testing have narrower coverage than a complete device/OS test matrix; see the status page for limits.

## License

No open-source license has been granted at this time. All rights are reserved by the respective copyright holders, except as permitted by applicable law and GitHub's terms. Public visibility is not permission to redistribute the app or reuse its code. The repository includes one Typefield-generated launch fixture, [`Ink.ttf`](marketing/launch/assets/v3/Ink.ttf); it is not bundled in the beta app. Fonts you import retain their own licenses.
