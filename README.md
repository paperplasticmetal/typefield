# FontShelf

[![macOS build](https://github.com/paperplasticmetal/fontshelf/actions/workflows/build.yml/badge.svg)](https://github.com/paperplasticmetal/fontshelf/actions/workflows/build.yml)

Native macOS font browsing, previews, and organization, built with SwiftUI, AppKit, and Core Text.

**Current version: 0.22.0 (build 30).** Development release for Apple Silicon. App Store submission is in preparation; this is not an App Store-approved or notarized release.

**Developer handoff:** In a typeboard, choose **Export → Developer handoff…** for all its canvases, or use the space actions menu to export the whole project. One folder contains `@font-face` declarations, axes/features, CSS variables and suggested fluid `clamp()` scales, fallback stacks, preload examples, font-display guidance, Tailwind v3/v4 setup, versioned token JSON, SwiftUI and Compose starter definitions, and a standalone printable HTML specimen. Font binaries are never bundled: supply licensed web/app assets at the manifest paths. The README documents defaults and native integration work; the specimen is a typography reference, not a pixel-perfect layout export.

**Rename:** Click a selected space, typeboard or collection name to edit it directly, in the sidebar or main header. Double-click an unselected name to rename it. Return saves; Escape cancels. Sidebar context menus also offer Rename. Collection renaming preserves membership and selection and prevents overwriting an existing collection.

Spaces contain typeboards, and typeboards contain canvases. Selecting another canvas keeps the current comparison visible; use **Only this**, each comparison's close button, or the **Shown** menu to hide it again. **Show all** displays every canvas, while Quick A/B solos two same-size alternatives for rapid switching. **Add canvas** creates a blank canvas or duplicates the current one. Click text or a type role to locate and edit its exact canvas use; drag a role onto the active canvas to add its saved sample text and settings. The font chooser includes collections, favorites, categories (including your overrides), and #tag search. Pinch over the canvas viewport, or use ⌘ + mouse-wheel scrolling, to zoom; ordinary scrolling pans and the zoom menu returns to Fit.

Each canvas toolbar opens a typography summary for the typeboard. Every canvas starts selected, and a visible checkbox row lets you include any subset before copying or exporting a compact font-only list, a font-and-role map, or full typography specifications with size, line height, tracking, variable axes and OpenType features. Export plain text or Markdown, or generate a multi-page type-system PDF whose specimen pages retain each selected canvas's chosen fonts and settings. The same panel can create a Library collection from the active canvas, its complete typeboard, or the entire project, deduplicated by font family. Website, product UI, editorial and poster formats use purpose-specific compositions rather than the same generic stack.

**Live folders:** Add font folder explains recursive watching in the picker, then opens the folder manager. **Live folders** is always accessible in the Library sidebar. Watching updates additions, replacements and removals while the app is open; activation for other apps remains a separate opt-in.

**Font health:** Open **Tools → Font Health** to scan user fonts and watched folders, or choose **Inspect font file…** from a family's action menu. FontShelf checks SFNT structure, required tables, bounds, overlaps, checksums and common name-table failures, then separates actual warnings/errors from optional compatibility notes. Proposed fixes are individually reviewable. Export creates a new Core Text-validated copy; in-place repair is limited to writable user fonts, requires a separate confirmation, and keeps a `.fontshelf-backup` beside the original. System fonts, TTC/OTC collections, unsupported containers and ambiguous identity conflicts remain inspection-only.

## Features

- Browse installed fonts and user-selected font folders; search, sort, and filter by source, category, script, weight, and OpenType features.
- Editable previews with adjustable size, adaptive grids, wrapping, and aligned baselines.
- View every style in a family, tune variable axes, inspect OpenType features, and preview body text layouts.
- Cyan/orange overlay comparison within a family or across the library; a six-family comparison shortlist.
- Favorites, collections, multi-tagging, family grouping, last import, and duplicate detection.
- Google variable fonts with real previews before download. Preview text stays local; public font files are fetched from Google's repository on GitHub.
- Original-file export and temporary session activation. Adobe integration exports JSX scripts for manual use, not direct application control.
- Light/dark appearances, India yellow accents, and native Liquid Glass on supported macOS versions.
- Spaces separate from collections, pairing typeboards, saved directions and checkpoints. Tune seven type roles with font, variable axes, OpenType, spacing, text and color settings.
- Website, product UI, editorial, poster, type-system and ordered custom-layout canvases; responsive widths, side-by-side directions, PDF export and portable space files.
- Unicode/glyph browsing and search, metrics, outline previews, SVG export/drag, waterfall previews and paginated specimen PDFs.
- Nested tags with AND/OR inclusion and exclusion; font metadata table and individually confirmed exact-duplicate removal to Trash.
- Local font-health inspection with conservative name-table/checksum repairs, before/after identity summaries, repaired-copy export and backed-up in-place repair for writable user fonts.
- Recursive watched folders refreshed every three seconds while open, with opt-in temporary activation for other apps using original files. No copying into system font folders.
- Daily local state backups and merge-based backup import. Folder access permissions must be granted separately.

Spaces is a separate workspace with its own project/typeboard sidebar. Its resizable inspector includes alignment, kerning, exact line height, tracking, paragraph/word spacing, indents, case and decorations. Drag sections in the arrangement list or directly on the canvas. Choose an A/B partner with the same format and width, then use **Swap A/B** (Command-backslash). Fit zoom adapts to panel resizing.

Search accepts `#tag`, `#!tag`, and quoted names such as `#"Client Work"`. Typing `#` opens tag and font-property suggestions. Built-ins include `#fontshelf/active`, `#fontshelf/user`, `#fontshelf/bold`, `#fontshelf/italic`, and `#fontshelf/feature/tnum`; `#typeface/` is accepted as an alias. Tokens combine with AND and match the same style. A parent tag includes its descendants. Removable search chips show active filters.

**Figma round trip:** Use the typeboard's **Export** menu to create an editable Figma package. The bundled local plugin can also export selected Figma frames; import that JSON using **Spaces → Import → Figma typeboard…**. Imported text layers can be edited independently and moved directly on the canvas. Fonts must be available on each side. Native `.fig` files, live sync and full Figma fidelity are not supported; unsupported elements/settings are reported. See [bridge instructions](Resources/FigmaImport/README.md) and [interaction checks](docs/INTERACTION_AUDIT.md).

This is not complete Typeface feature parity. Direct Adobe integration, a published Figma plug-in, document-triggered activation and cloud team collaboration are not implemented. Session activation is verified in the local development build; App Store sandbox verification remains outstanding.

## Build and run

Requirements: an Apple Silicon Mac, full **Xcode 26 or later** selected as the active developer directory, and its command-line tools. The app declares macOS 13 as its minimum; older-OS testing remains outstanding. Intel binaries are not shipped.

```sh
git clone https://github.com/paperplasticmetal/fontshelf.git
cd fontshelf
./install-local.sh
open /Applications/FontShelf.app
```

The installer builds and verifies an ad-hoc-signed local app, then updates the stable `/Applications/FontShelf.app` copy. This avoids accumulating numbered app bundles; opening FontShelf from Applications launches the latest installed build. Pass another destination path to `install-local.sh` when needed. No paid Apple account is required for this local build. To run the checks again:

```sh
dist/FontShelf.app/Contents/MacOS/FontShelf --self-test
```

For Xcode, open `FontShelf.xcodeproj` and select the shared **FontShelf** scheme. Build without distribution credentials:

```sh
xcodebuild -project FontShelf.xcodeproj -scheme FontShelf \
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
TEAM_ID=YOUR_TEAM_ID APP_BUNDLE_ID=com.yourcompany.fontshelf ./archive-store.sh
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

No open-source license has been granted at this time. All rights are reserved by the respective copyright holders, except as permitted by applicable law and GitHub's terms. Public visibility is not permission to redistribute the app or reuse its code. Font files retain their own licenses; no font binaries are bundled in this repository.
