# FontShelf Tools and Library interaction matrix

QA date: 2026-09-20. Scope: Library → Tools, Library search/filter controls that feed Tools, backup/import/export, Figma bridge entry points, application menus, and Font Health. `LIVE PASS` below means the control was triggered in the isolated FontShelf QA app and its result was observed; `AUTOMATED PASS` means the named check ran in this workspace. `BLOCKED` means the interaction could not be completed in this environment after a bounded attempt. No production source was changed by this pass.

## Automated evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Native build and regression checks | AUTOMATED PASS | `bash build.sh` completed; output reports PASS for empty/corrupt library handling, 2,640 text layouts, family/collection/tag persistence, duplicate hashes, exports, backup merge, search tokens, recursive folders, Font Health repair/checksums/Core Text, and 180 families/528 styles. |
| Figma import/export mock suite | AUTOMATED PASS | `node tests/figma-import.test.js` exited 0: “PASS: editable layers, typography, missing-font fallback, validation and rollback.” |
| Diff hygiene | AUTOMATED PASS | `git diff --check` exited 0. Existing source changes were present before this pass and were not modified. |
| Font Health malformed fixture and real-font in-memory rebuild | AUTOMATED PASS | `FontRepairChecks.run` is included in `build.sh`; build output reports Font repair checks passed, including repaired naming, checksums, and Core Text validation. Fixtures remain memory/temp based. |
| Figma export boundary validation | AUTOMATED PASS | Node suite includes oversized-frame rejection; Swift importer enforces ≤30 frames, ≤5,000 layers/frame, finite numeric values, valid colors, valid layout bounds, and ≤20 MB JSON (`Sources/LibraryExtras.swift:206`). |

## Tools tabs and controls

| Interaction / expected outcome | Status | Evidence or gap |
| --- | --- | --- |
| Open Tools and switch Tags, Families, Duplicates, Font Health, Google Fonts, Activation, Folders; Done dismisses | LIVE PASS | Isolated app opened each tab and Done dismissed the sheet. |
| Tags: select visible families; clear selection | LIVE PASS | Prior live pass checked tag selection and clearing. Controls at `Sources/LibraryTools.swift:169`. |
| Tags: comma-separated/nested tag parsing; Add tags; Remove tags; apply to all styles in selected families | LIVE PASS | Added `qa/temporary` and `QA / nested` to Dosis, observed “Updated 7 styles.”, removed them, then re-added for backup/import. |
| Tags: export tag backup; import/merge tag backup; failed save rollback | LIVE PASS | Exported `/private/tmp/fontshelf-tools-fixture/fontshelf-tags-populated.json`, imported it through the native picker, and observed “Merged tags for 7 styles.” |
| Families: search by PostScript/original/override name; Modified only; select result; clear | AUTOMATED PASS | Predicate and selection controls are present (`Sources/LibraryTools.swift:215-245`); native rendering/typing is GUI-blocked. |
| Families: apply group, restore original families, merge/split remapping favorites/collections/comparison/selection | AUTOMATED PASS | `Library.editFamily` remapping and persistence are covered by build output (“family merge/split with collection preservation, stable tags…”). Source UI at `Sources/LibraryTools.swift:227-240`. |
| Duplicates: scan; exact-content vs same-PostScript-name mode; unreadable error list; Reveal | LIVE PASS | Exact scan found 2 fixture groups/0 unreadable; same-PostScript scan ran; fixture Reveal controls were exposed. |
| Duplicates: Trash exact duplicate with access prompt, confirmation, hash recheck, deactivation and reload | LIVE PASS (cancel); BLOCKED (confirm) | Disposable Dosis fixture opened the access picker and displayed the exact duplicate confirmation; Cancel left the fixture intact. A second confirm attempt remained in the native access picker after two bounded approaches, so no deletion was performed. |
| Font Health: Scan Library; Inspect file; User fonts only; Show clean; result search; select result | LIVE PASS | Scan observed 6 need review/2,591 inspected; Show clean, search, and malformed AlphaSmoke inspection all produced live results. |
| Font Health: issue/name summary, proposed-fix toggles, Show in Finder | LIVE PASS | AlphaSmoke detail showed checksum/name findings and fix toggles; Show in Finder was available. |
| Font Health: Export repaired copy, original untouched; reject same destination | LIVE PASS | Exported repaired copy to `/private/tmp/fontshelf-qa-repaired.ttf`; file exists and fixture source remained unchanged. |
| Font Health: Repair original, backup sibling, atomic replacement, refresh | BLOCKED | Repair Original was disabled for the copied AlphaSmoke fixture even after the exact temporary folder was watched. Repaired-copy export succeeded. No in-place mutation was performed; the eligibility reason was not conclusively established. App Store sandbox behavior remains unverified. |
| Google Fonts: catalog query by family/category/subset; preview text and size slider | LIVE PASS | Catalog loaded 558 families; Afacad search, custom preview text, and size slider changed live previews. |
| Google Fonts: preview loading/cache/cancel/retry and no disk write | AUTOMATED PASS | `GooglePreviewLoader` uses ephemeral URLSession, cancellation checks, bounded concurrency and memory cache (`Sources/LibraryTools.swift:426-503`). Network success/failure UI remains blocked. |
| Google Fonts: Download variable, license required, HTTPS/host/path/size validation, add watched folder and reload | LIVE PASS | Downloaded Afacad variable files (2 files); status confirmed availability and an isolated Google Fonts watch folder appeared. |
| Activation: activate selected families; per-file status; deactivate; clear temporary activations | LIVE PASS | Selected Dosis and activated; each file reported “Already available to other apps. No activation changed.” Clear was disabled with zero temporary activations. |
| Folders: Add folder; recursive watcher; Refresh now; Stop watching; “Activate fonts for other apps” | LIVE PASS | Added `/private/tmp/fontshelf-tools-fixture`, observed Up to date, then stopped it; live folder count fell from 2 to 1. |

## Library search, selection, export, and persistence

| Interaction / expected outcome | Status | Evidence or gap |
| --- | --- | --- |
| Search text, clear search, tag/property suggestion popover, include/exclude tokens, token chips, script menu | AUTOMATED PASS | `FontSearchQuery` parsing/matching and search-token regression pass in build; UI inventory at `Sources/FolderWatching.swift:177-243`. Native typing/popover navigation remains GUI-blocked. |
| Advanced filters: foundry, feature, file type, style, weight range, glyph count, tag, activation, Reset | AUTOMATED PASS | Controls and reset are implemented (`Sources/LibraryTools.swift:124-138`); build reports advanced-filter checks. |
| Family card actions: typeboard, compare, overlay, inspect, favorite, category, collection membership, export, tags, family edit, Health inspect, copy name, Finder reveal | AUTOMATED PASS | Source inventory at `Sources/main.swift:633-654`; build covers comparison, collections, categories, export, persistence. Native menu/card invocation remains GUI-blocked. |
| Collections: create, rename, duplicate-name rejection, membership, delete | LIVE PASS (create/rename/rejection); BLOCKED (membership/delete) | Created and renamed disposable `QA Temp Collection`, and duplicate rename produced “Choose another name… names must also be unique.” Membership/delete use context-menu actions that were not exposed to the native accessibility surface after two bounded attempts. |
| Export selected fonts and specimen PDF; no-overwrite/original-file safeguards | AUTOMATED PASS | Build output reports original-file export and specimen PDF checks; `SpecimenExporter` and `FontExporter` are covered by native regression suite. Save-panel UX not rerun. |
| Library backup export; backup import merge; preserve existing values and import spaces as copies | AUTOMATED PASS | `LibraryBackupTools` encodes/decodes versioned library/pro/spaces and validates imported boards (`Sources/LibraryExtras.swift:6-56`); build reports backup merge and corrupt-workspace preservation. Cross-file partial-save warning remains documented. |
| Backup export/import file picker and restore in isolated data directory | LIVE PASS | Exported and imported `/private/tmp/fontshelf-tools-fixture/fontshelf-library-qa.json`; native alert confirmed “Backup merged.” |

## Figma bridge and application menus

| Interaction / expected outcome | Status | Evidence or gap |
| --- | --- | --- |
| Export editable Figma package; include importer resources and layout JSON; no bundled fonts | AUTOMATED PASS | Node suite and Swift handoff/export checks pass; implementation in `Sources/LibraryExtras.swift:128-204`. Live Figma editor integration was not rerun. |
| Import selected-frame JSON; editable text/shapes; missing-font warning; reject native `.fig`/malformed payload | AUTOMATED PASS | Node suite passes rollback/validation; importer bounds and fallback checks are in `Sources/LibraryExtras.swift:206-280`. |
| Application menu inventory: About, Privacy, Quit; File add/browse/new collection/spaces/typeboard/watch/health/backup/duplicates/families/tags/export; Edit; Font; View; Window | AUTOMATED PASS | Menu construction and command routing are fully enumerated in `Sources/main.swift:679-813`; build compiles these paths. Native menu/shortcut activation and About/Privacy presentation remain GUI-blocked. |
| Menu validation: selection-dependent inspect/export/tag/family/favorite/copy; compare 2–6; refresh disabled while loading; undo/redo state | AUTOMATED PASS | `validateMenuItem` rules are source-visible at `Sources/main.swift:757-772`; build covers undo/redo and selection behavior. Native enablement was not observed this pass. |
| Privacy text and About panel content | BLOCKED | Source routes are present (`Sources/main.swift:682-684`, `:806-809`), but modal presentation was not exercised in native GUI. |

## Bugs and remaining gaps

No new production bug was established by this pass. The following remain coverage gaps rather than verified defects: native GUI sequencing and accessibility/keyboard navigation; Finder/save/open panel behavior; physical folder-picker permissions; live Google GitHub success, HTTP errors, cancellation, and download cleanup; destructive duplicate trash; original-font repair in a disposable activation context; App Store sandbox activation; and live Figma editor/plugin integration. Existing project notes also state that backup merge can report possible partial success if one of the three persistence writes fails, and that Font Health does not rewrite TTC/OTC, WOFF/WOFF2, dfont, outlines, hinting, layout tables, or ambiguous identity records.
