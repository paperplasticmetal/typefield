# Studio interaction matrix — 2026-09-19

Scope: native Studio UI in the isolated `/tmp/fontshelf-interaction-qa/dist/FontShelf.app` build. Source files under `sources/` are reference-only; this matrix records actual UI evidence separately from source inspection and model checks.

Status vocabulary: `LIVE PASS` means exercised in the isolated app; `AUTOMATED PASS` means covered by the built-in checks with a named assertion; `FAIL` means a reproducible defect; `PENDING` means not yet exercised; `BLOCKED` is reserved for a concrete environment or fixture blocker. Static/source review is never recorded as verification.

## Controls and checks

| Interaction | Expected result | Existing automated evidence | Status / live evidence |
|---|---|---|---|
| Switch Library ↔ Spaces | Studio opens and returns to Library without losing state | Store persistence covered by `StudioChecks.run` | PENDING |
| Create space | New space is focused and receives a typeboard | `StudioStore.addSpace` / `addBoard` exercised by `StudioChecks.run` | LIVE PASS — created `QA Studio Disposable`; sidebar and board appeared |
| Rename space (inline and menu) | Name updates and persists | No direct automated UI assertion | LIVE PASS — renamed to `QA Studio Renamed`; imported round-trip retained it |
| Delete space / cancel delete | Confirmation is safe; deletion clears focus and persists | Regression noted in `QA_2026-09-19.md` | LIVE PASS — opened confirmation, Cancel preserved space, Delete removed disposable space and its board |
| Create typeboard | Board appears under selected space and is focused | `StudioStore.addBoard` in `StudioChecks.run` | LIVE PASS — `QA Board Renamed` appeared and focused |
| Rename typeboard (inline and menu) | Name updates and persists | No direct automated UI assertion | LIVE PASS — renamed `QA Board Renamed` |
| Delete typeboard / undo restore | Confirmation deletes; undo restores board/focus | `StudioStore.removeBoard` model path in `StudioChecks.run` | LIVE PASS — confirmation deleted `Typeboard 2`; Cmd-Z restored it |
| Add blank canvas | New canvas is selected and visible | Canvas persistence and names in `StudioChecks.run` | LIVE PASS — added and selected Canvas 2 |
| Duplicate canvas | Copy receives a new id/name and retains settings | `TypeDirection.copy`, layout persistence in `StudioChecks.run` | BLOCKED — menu exposed action but CUA target became stale before activation; no duplicate evidence |
| Delete canvas / minimum-one guard | Deletes when ≥2; disabled at one | `CanvasVisibility` checks; no UI click | LIVE PASS — deleted disposable Canvas 2; single-canvas state disabled Only current |
| Rename canvas | Custom name appears in tabs and saves | No direct automated UI assertion | LIVE PASS — renamed `QA Canvas 2` |
| Select canvas tab / preserve comparison set | Selected canvas becomes editor; shown set remains | `CanvasVisibility.selecting` assertion in `StudioChecks.run` | PENDING |
| Show all / Only current / hide canvas | Visibility controls update preview | `CanvasVisibility.solo/prune` assertions | LIVE PASS — observed `Shown · 2`, `Shown · 1`, and `Show all` |
| A/B and swap | Matching canvas pair enters A/B; swap changes editor | No direct automated UI assertion | BLOCKED — Quick A/B submenu exposed but its duplicate/use-same-format actions were disabled in the disposable pair |
| Format selector | Website/Product UI/Editorial/Poster/Type system/Custom change layout | Layout cases in `StudioChecks.run`; no UI click | LIVE PASS — Website → Product UI, AX showed `Format Product UI` |
| Width selector | Mobile 390 / Tablet 768 / Desktop 1200 / Canvas 960 persist | Responsive layout checks in `StudioChecks.run` | LIVE PASS — Canvas 960 → Desktop 1200, AX showed `Width Desktop · 1200` |
| Zoom menu | Fit, 25–300% render and clamp safely | `CanvasZoomInput.clamped` assertion | LIVE PASS — selected 200%, then Fit; AX showed both |
| Inspector Typography ↔ Arrangement | Correct panel switches | No direct automated UI assertion | LIVE PASS — AX showed Typography then ARRANGEMENT |
| Role selection | Display/Heading/Subheading/Body/Label/Caption/Mono selects role text | `CanvasPlan` hit-test and role insertion checks | PENDING |
| Edit sample text | Text changes preview and survives relaunch | `textOverrides` encode/decode assertion | LIVE PASS — entered `Studio QA sample`, preview reflected it |
| Font chooser open/search/no-match/clear | Search filters styles; no-match feedback; clear restores | `StudioFontFilter` intersections/favorites checks | LIVE PASS — `zzz-no-match` showed 0; Clear filters restored 4,252 |
| Font chooser collection/category filters | Filters intersect; Favorites and saved collections work | `StudioChecks.run` filter assertions | PENDING |
| Choose font / pairing candidates | Selected style applies; candidate menu changes font | No direct automated UI assertion | LIVE PASS — selected `1797-COMPRESSED_V2`, button updated |
| Size and line height fields/sliders | Values clamp to valid range and save | Model validity checks; no UI click | PENDING |
| Tracking, paragraph/word spacing, indent | Numeric typography edits affect preview and save | Handoff and summary checks preserve values | LIVE PASS — word 1.2, paragraph 4, indent 8 visible in inspector |
| Alignment, kerning, case, underline, strike | Toggles/options affect rendered text and persist | Handoff CSS assertions cover axes/features/kerning; no full UI pass | LIVE PASS — Center selected; kerning, case, underline, strike exercised earlier |
| OpenType feature selectors | Default/Off/On/Alternate options persist | `StudioChecks.handoff` verifies features | LIVE PASS — feature menu exposed Default/Off/On/Alternate 2–9; On selected |
| Variable axes | Axis controls appear for variable fonts and persist | `StudioChecks.handoff` verifies `wght` 520 | PENDING |
| Text/background/accent colors | Color pickers update preview and save | No direct automated UI assertion | BLOCKED — AX `Show color panel` and visible-coordinate click produced no color panel or editable state |
| Drag sections / add role / restore removed sections | Arrangement changes order and restores hidden sections | `TypeDirection.reorder/insert` and drag payload checks | LIVE PASS — removed Application chrome; Restore removed sections restored it |
| Native canvas drag | Text/layer movement works within bounds | Imported layer bounds model check only | BLOCKED — coordinate drag on native preview produced no observable position/AX change |
| Typography summary popover/detail tabs | Roles/full/fonts details show actual used fonts | `CanvasTypographySummary` detail assertions | LIVE PASS — popover showed roles/fonts and Full settings option |
| Summary Copy | Clipboard receives selected detail | No automated clipboard assertion | LIVE PASS — clicked Copy; UI status reported `Typography summary copied` |
| Summary export plain text/Markdown | Chosen file is created with correct content | Markdown escaping checks; no native dialog pass | LIVE PASS — `/private/tmp/fontshelf-studio-summary-live.md` exists (389 bytes); status reported exported |
| Save/restore checkpoint | Checkpoint saves; restore creates a new canvas | Checkpoint model encoded through `TypeBoard` checks | LIVE PASS — restore created `QA Canvas 2 restored` |
| Add shortlist as candidates | Compared fonts merge into board candidates | No direct automated UI assertion | PENDING |
| Create font collection (canvas/board/project) | Collection prompt creates scoped family set | `StudioFontCollection` and collection checks | LIVE PASS — created `QA Studio Collection`; status reported 2 families and Library availability |
| Export Preview PDF | Destination file is written and opens/reports success | No direct native dialog pass | LIVE PASS — `/private/tmp/fontshelf-studio-preview-live.pdf` exists (27,721 bytes); save panel Where=`tmp`, filename-only entry |
| Export Editable Figma layout | Package folder contains importer/readme and no fonts | `StudioChecks.handoff`; Figma tests | LIVE PASS — `/private/tmp/FontShelf-Figma-C7AA11DC/` contains code.js/ui.html/README/manifest/layout |
| Export Developer handoff | Folder contains expected 11 files and safe escaping | `StudioChecks.handoff` PASS | LIVE PASS — `/private/tmp/FontShelf-Handoff-9DB29FA6/` created and status reported success |
| Space export/import JSON | File dialog round-trip creates fresh ids and valid boards | Import validation is code-covered; no UI round-trip | LIVE PASS — `/private/tmp/fontshelf-studio-space.json`; import added duplicate space/board |
| Figma typeboard import | JSON dialog imports valid board; invalid/oversize errors | Figma model tests and `QA_2026-09-19.md` regression | LIVE PASS — `/private/tmp/FontShelf-Figma-C7AA11DC/layout.fontshelf.json` imported board with `Format Figma layout` and imported text layers |
| Native .fig help | Alert explains bridge workflow and dismisses | No automated UI assertion | LIVE PASS — alert explained Figma Layout Importer bridge and dismissed with OK |
| App menu Undo/Redo | Typography edit undoes/redoes in Studio context | Existing QA live pass for 64→68→64→68 | LIVE PASS — isolated build reverted and restored `Studio QA sample` |
| Relaunch persistence | Space/board/canvas/style/filter edits survive relaunch | Store encode/decode checks | LIVE PASS — after closing/reopening isolated app, `QA Studio Renamed`, `QA Board Renamed`, Canvas 2, and Center alignment were present |

## Handoff protocol

The isolated GUI handoff from `/root/luna_library_verify` is complete. Remaining `PENDING` rows require live actions; use `BLOCKED` only for a concrete environment or fixture blocker. After completing Studio, pass the GUI to `/root/luna_tools_verify` and notify `/root`.
