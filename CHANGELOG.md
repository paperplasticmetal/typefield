# Changelog

## 0.27.0 — 2026-09-20

- Replaced the small collapsed-sidebar restore control with a shared 52-by-64-point edge pull-tab across Library, Spaces and Font Lab, with a full rectangular hit target, a dedicated header lane, hover feedback and an accessible keyboard hint.
- Hard-clipped shared cards, glass sidebars and Font Lab's native drawing, metric-example and preview surfaces to their continuous rounded shapes so rectangular backgrounds no longer show beyond rounded borders.
- Expanded Font Lab's drawing toolbar with Pen and whole-stroke Eraser tools, adjustable pen/eraser size, Off/Gentle/Strong smoothing, pressure-sensitive round strokes and clear input status/help. Apple Pencil input arrives through macOS Sidecar and other tablets through their normal macOS drivers; FontShelf does not pair USB or Bluetooth hardware itself. Reported tilt is retained with each sample, but it does not yet rotate the round nib.
- Labeled baseline, x-height, cap height and both side bearings directly on the drawing guides, and added a live H/x metric example plus a beginner guide explaining what each measurement controls.
- Kept each in-progress stroke inside the native drawing view, publishing and saving it once at gesture completion instead of copying the full Font Lab project for every sampled point. Project-name, preview and metric edits now use coalesced saves.
- Added reusable catalog face/family/name indexes, single-pass Library sidebar count snapshots and lean first-pass pairing/similarity ranking so routine redraws and recommendations avoid repeated full-catalog work. Final release measurements are recorded after the verification run.

## 0.26.0 — 2026-09-20

- Added an explicit seven-role setup step whenever selected Library fonts, Favorites, a collection, Shortlist or a recommendation seeds a typeboard. FontShelf supplies a resettable first pass, while the user chooses the initial Display, Heading, Subheading, Body, UI, Caption and Monospace faces; every role remains freely editable afterward.
- Added local, explainable font-pairing suggestions inside Spaces. Safe, Balanced and Expressive modes rank compatible installed families for a chosen target role, preview both faces together, show the signals behind each result and apply the choice without replacing the source role.
- Added Illustrator and InDesign type-system builders beside PDF export. The generated JSX creates a new editable native `.ai` or `.indd` document with canvases/pages, live text, simple shapes, named styles and retained FontShelf metadata; fonts are referenced rather than bundled.
- Added the reverse Adobe bridge: export a document or selection from Illustrator/InDesign to bounded JSON, then import it as an editable FontShelf typeboard with source-aware units, transparent no-fill handling and per-layer fidelity warnings. Native proprietary files are not decoded directly and mixed styles, complex effects, variable axes and some OpenType settings still require review.
- Added Font Lab as a third top-level workspace. Its first foundation includes explicit project creation, per-glyph mouse/trackpad drawing, baseline/x-height/cap-height and side-bearing controls, drawn-glyph word previews, atomic local persistence, daily and portable backup coverage, confirmed clearing and real per-glyph SVG export.
- Marked Font Lab's SVG/PNG/Procreate tracing, multi-font blending and installable OTF generation honestly as planned or research work rather than presenting placeholder output as a finished font.
- Added deterministic checks for role seeding/editability, pairing scoring, Adobe script parsing and JSON round trips, Font Lab persistence/corrupt-data preservation/SVG output and backward-compatible Library backup merging, plus the new sources in the Xcode target.

## 0.25.0 — 2026-09-20

- Added a direct **Create typeboard** action to Shortlist, with checkboxes for choosing any subset and preservation of each selected font style.
- Made the Library header's typeboard action use selected families when present, so multi-selecting fonts in Favorites, a collection or any filtered Library view creates a populated typeboard immediately.
- Expanded initial role assignment from two-font pairing to up to six selected fonts across display, heading, subheading, body, UI/caption and monospace roles; every selected font remains available as a typeboard candidate.
- Added regression coverage for predictable two-font pairing and complete multi-font role seeding.

## 0.24.0 — 2026-09-20

- Unified the Library and Spaces sidebar header so the FontShelf mark and workspace switcher remain in exactly the same position when changing workspaces.
- Added a persistent collapsible workspace sidebar, a compact left-edge restore control and **View → Hide/Show Sidebar** (Control-Command-S), returning the complete 256-point sidebar footprint to the active workspace.
- Clarified the Font kerning control and made it the single canonical control for the OpenType `kern` feature, avoiding a contradictory duplicate feature selector while preserving legacy saved settings across rendering, web audits and exports.
- Added regression checks for expanded-by-default behavior, persisted collapse/expand state and exact reclaimed workspace width.

## 0.23.0 — 2026-09-20

- Added direct canvas text editing on double-click, with Command-Return to save and Escape to cancel; hardened empty, oversized and focus-changing edits so they cannot crash the canvas or overwrite a newer selection.
- Added a selected-canvas web-font cost audit with exact WOFF2 file weights, known download totals, character/script coverage provenance, compatible variable-versus-static comparisons, fallback x-height/wrapping/control-width probes and removable-style estimates.
- Made missing and ambiguous web assets explicit and excluded them from exact byte totals instead of substituting unrelated desktop data; serialized and debounced analysis so stale work cannot replace the current selection.
- Added local-only **Find similar** recommendations with explainable visual/metadata signals and **Rediscover** suggestions biased toward fonts that have not been used recently.
- Stopped watched folders with missing or revoked security-scoped bookmarks from repeatedly probing protected locations, eliminated the resulting macOS permission-prompt loop, and deduplicated reauthorization notices per launch.
- Aligned each comparison header's **Only this** and close controls with its canvas edge across all Spaces canvas formats.
- Made the active Library **A/B** reference button a true toggle: clicking it again ends the overlay comparison.
- Made canvas clicks target the exact heading, caption or display text under the pointer, with a tight selection/editor outline instead of selecting the full section.
- Removed the watcher's redundant startup refresh while preserving live add, replacement and deletion detection.
- Extended validation for canvas editing limits, local intelligence, web-cost calculations, protected-folder recovery and responsive canvas layouts.

## 0.22.0 — 2026-09-20

- Removed an unnecessary second installed-font catalog scan from ordinary cold launches and skipped the post-registration rescan when watched folders made no catalog changes.
- Reused variable-font facts already collected during catalog reads and original-family classifications during regrouping instead of reopening every style.
- Added bounded caches for immutable Core Text fonts and rendered canvas plans, with invalidation whenever the font catalog changes and size limits for unusually large imported layouts.
- Reduced repeated full-library filtering and chosen-face resolution during SwiftUI redraws, and cached Core Text line layout between sizing and drawing passes.
- Avoided rebuilding canvas accessibility summaries on every selection or zoom update and bounded the summary size for very large imported layouts.
- Added a read-only `--performance-audit` covering catalog scan, library filtering and cold-versus-cached canvas planning.

## 0.21.0 — 2026-09-20

- Added per-typeboard canvas selection to typography summaries, with every canvas selected initially and a checkbox row for choosing any subset.
- Combined the selected canvases in plain-text, Markdown and clipboard summary output while preserving each canvas's name and format.
- Added multi-page type-system PDF export, with one generated specimen page per selected canvas using that canvas's fonts, axes, OpenType features, colors and typography scale.
- Added regression coverage for multi-canvas summary scope, generated specimen settings and PDF page count.
- Standardized local releases on `/Applications/FontShelf.app` through `install-local.sh` so verified builds update one stable app instead of producing numbered copies.
- Completed and regression-tested the focused fixes from the September 19–20 Luna QA pass.

## 0.20.0 — 2026-09-19

- Added Font Health to Library tools plus per-family **Inspect font file…** access and a File-menu entry.
- Added local checks for SFNT headers/directories, required tables, table bounds and overlap, checksums, name-table storage, empty/exact-duplicate/conflicting records, required IDs and PostScript-name validity.
- Added clearly separated compatibility notes for legacy RIBBI subfamilies and version formatting, so valid modern fonts are not labeled broken.
- Added individually selectable conservative fixes, full SFNT rebuilding, checksum adjustment, Core Text validation, repaired-copy export, and confirmed in-place repair with a side-by-side backup for writable user files.
- Kept system fonts, multi-font TTC/OTC containers, unsupported formats and ambiguous identity repair read-only; repairs never synthesize or guess missing identity records.
- Added deterministic regression coverage for a legacy malformed name table, proposal selection, repaired naming, duplicate removal and whole-font checksum validity.

## 0.19.0 — 2026-09-19

- Replaced implicit canvas comparison state with an explicit visible-canvas set. Selecting canvases builds a stable comparison; per-canvas Hide, Only this, Show all and the checkmarked Shown menu make returning to a single canvas immediate.
- Added a Fonts used summary for the active canvas with font-only, role mapping and full typography levels, plus clipboard, plain-text and Markdown handoff.
- Added collection creation from the fonts used on one canvas, across a typeboard, or throughout a project. Used styles deduplicate to Library font families and never overwrite an existing collection.
- Linked type-role selection to its first visible canvas use and made roles draggable onto the active canvas with their saved sample text and typography settings.
- Redesigned website, product UI, editorial and poster canvases as distinct, purpose-specific compositions while retaining rearrangeable sections and responsive widths.
- Added regression coverage for canvas visibility continuity, role-drop placement and payload validation, typography summary exports and template distinctness.

## 0.18.0 — 2026-09-16

- Added one-click developer handoff packages with CSS, fluid scales, preload guidance, Tailwind configuration, design-token JSON, SwiftUI, Android Compose and printable HTML output.
- Made space, typeboard and collection names directly editable by clicking their text, with keyboard save/cancel and duplicate-name protection.

## 0.17.0 — 2026-09-16

- Simplified vocabulary to Spaces → Typeboards → Canvases, with visible canvas tabs, a Show all canvases toggle and clearer New typeboard/Add canvas commands. Legacy generated labels display as Canvas 1, Canvas 2, etc. without rewriting saved names.
- Exposed recursive live folder watching during folder selection and opened its controls after adding a folder; added a permanent Library sidebar shortcut.
- Allowed adding folders during an existing library scan, queuing the first scan with an explicit status instead of disabling the picker.
- Kept every typeboard trash button visible and clickable without selecting or hovering.
- Added bounded trackpad-pinch and Command-scroll zoom over the canvas viewport, preserving normal scroll-to-pan behavior.
- Added collections, favorites, category overrides and tag queries to the typeboard font chooser.
- Fixed canvas text hit-testing to select the exact role/text, including fixed template labels, with per-element text edits that save and undo independently of shared typography.
- Added native .fig workflow guidance. Direct binary .fig import is still not supported; the tested Figma JSON bridge remains available.

## 0.16.0 — 2026-09-16

- Added selected-frame Figma import as editable, saved typeboards: independent text styling, solid shapes, original coordinates and canvas dragging, with explicit fidelity warnings. Uses the bundled JSON bridge, not native `.fig` decoding.
- Fixed clipped space titles and crowded icon menus throughout Library and Spaces; grouped comparison actions and surfaced Export directly.
- Added direct sidebar typeboard deletion with confirmation and Undo, plus descriptive Undo/Redo for design edits.
- Replaced unreliable drag sessions with native tracking for canvas and arrangement reordering, including insertion feedback.
- Remembered inspector width, top-aligned canvases and made the larger font chooser opaque and searchable immediately.
- Fixed the Figma development plugin's missing-ID metadata failure and text auto-height handling. Validated outbound editable frames and the reverse import in the live Figma desktop app.

## 0.15.0 — 2026-09-16

- Separated Library and Spaces into peer workspaces. Every space and typeboard is directly available in the Spaces sidebar; New pairing lives in the toolbar.
- Added resizable typography/canvas panels, fit-to-width previews, compact role controls and a larger searchable font chooser with actual font previews.
- Added numeric size, line height and spacing controls; alignment, font kerning, word/paragraph spacing, indents, case and decorations. Existing saved typography remains readable.
- Added draggable sections in template and custom canvases, arrangement-list drag ordering, removal/restoration and additional text blocks.
- Added quick A/B switching for directions with matching canvas type and width, alongside side-by-side comparison.
- Added #tag / #!tag search suggestions, removable chips and property filters for activation, source, weight, width, slant, x-height, variable/color/bitmap/monospaced fonts, scripts and OpenType support. Typeface-style built-in prefixes are accepted as aliases.
- Added editable Figma export packages with a network-free local importer. Text-rendering differences and unsupported typography settings are explicitly reported; no font files are bundled.
- Made installed fonts available before watched-folder scanning completes, so a slow folder does not leave the library or font picker empty.

## 0.14.0 — 2026-09-16

- Added Spaces, pairing typeboards, independently saved directions, checkpoints and side-by-side comparisons.
- Added responsive website, product UI, editorial, poster, type-system and custom ordered-block previews, with seven editable typography roles, PDF export and portable space import/export.
- Added searchable Unicode and unencoded glyph browsing, metrics and outline views, SVG export/drag, waterfall previews and paginated specimen PDFs.
- Added nested tags and AND/OR/NOT tag filtering, a metadata table and individually confirmed exact-duplicate removal to Trash.
- Added recursive folder watching and opt-in session activation from original files, including replacement/removal reconciliation.
- Added daily local backups, merge-based restore and corrupt-workspace preservation.
- Added regression coverage for workspaces, checkpoints, tags, folder snapshots, glyphs, responsive canvases, PDF pagination and backup merge; separate live folder/activation checks.
- Fixed two development test-runner crashes: headless PDFKit initialization and an incorrectly shared backup-test directory. PDF checks now use Core Graphics and new test failures exit with an error message.

## 0.13.1 — 2026-09-15

- Replaced the generic Serif and Sans Serif category symbols with compact letterform icons rendered in their corresponding type styles.

## 0.13.0 — 2026-09-15

- Actual Google Fonts previews before downloading, with editable sample text and size.
- Memory-only remote font rendering, a bounded cache, limited parallel loads, and retry controls.
- Updated in-app disclosure for preview network requests.

## 0.12.3 — 2026-09-15

- Corrected View menu layout checkmarks and shortlist membership after family regrouping.
- Required a saved license before persisting Google font files.
- Reported duplicate-scan subfolder errors and displayed export feedback inside the inspector.
- Expanded regression checks to include multilingual and unusual text layout.

## 0.12.2 — 2026-09-15

- Replaced font-dependent text-field spacing with explicit Core Text baselines shared across grid rows and overlay layers.

## 0.12.0–0.12.1 — 2026-09-15

- Adaptive preview widths, equal-height cards within rows, and larger controls.
- All family styles visible together; per-family and library-wide overlay comparisons.
- Visible shortlist entry in the sidebar.

## Earlier development

Installed/imported font browsing, script/category filters, collections, tags, last import, variable tuning, OpenType inspection, body layouts, duplicate detection, export, temporary activation, Adobe script export, native menus, and theme/glass refinements.
