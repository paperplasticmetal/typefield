# Typefield 0.59.29 performance pass — 2026-10-08

Baseline: `5473e6a57c47d23c00caf9489cef706926d6c596` (0.59.28, build 108). Candidate: 0.59.29, build 109. Three performance workers investigated Spaces navigation, canvas layout, and Letterform creation/edit/export independently. The coordinator integrates, performs live QA, and owns the build/install/release queue. Existing language, Spaces toolbar and Letterform editing refinements are retained. Missing-letter research remains paused.

## Scope and method

Optimized native probes use production source extracted from the frozen revision and candidate, on the same Apple silicon Mac. Fixtures are synthetic, with system fonts and deterministic geometry; no personal font or project data enters a benchmark. Timings are milliseconds, with median and nearest-rank p95; first runs and cold-cache results are retained separately. These are measured operation costs, not end-to-end input latency or frame-rate guarantees. Filesystem reads are normally warm; clearing a layout cache does not flush macOS caches. Lightweight compiler activity can introduce timing noise.

Private probes, source hashes, raw results, and logs are preserved under `.context/qa-artifacts/performance-round2-2026-10-08/` in the primary checkout. They are deliberately excluded from Git. Production regression checks and disposable live fixture construction are committed.

## Spaces navigation

Selecting a project or canvas previously validated, encoded, backed up and rewrote the complete Spaces document. Navigation now writes a bounded sibling `spaces.json.navigation` snapshot, bound to the exact saved document's device/inode/size/modification stamp. Content edits keep the original full-save transaction. A successful content save supersedes the sidecar; directly changed in-memory content uses the full-save path. Backup import acceptance refreshes the saved stamp only after its journal commits.

| Board-selection fixture | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| 2 boards × 3 canvases | 1.900 / 2.413 | 0.861 / 1.227 |
| 5 boards × 2 canvases, 87,807-byte document | 2.159 / 2.487 | 0.983 / 1.119 |
| 200 boards × 3 canvases | 23.655 / 24.260 | 2.198 / 2.585 |
| 2 boards × 200 canvases | 15.892 / 16.801 | 0.881 / 1.314 |
| 10 boards × 3 canvases, 37.7 MB embedded artwork | 80.227 / 102.569 | 0.966 / 1.751 |

Canvas selection on the artwork fixture changes from 80.750 / 88.393 to 0.862 / 0.979 ms. Navigation tests use 31 samples, or 15 for artwork. Initial document decoding and content saves are not made faster by this change. No-op selection remains about 0.0014 ms.

Regression coverage: exact focus/canvas reopen including nil; unchanged document and content-backup bytes; undo/redo and deletion; failed write rollback/retry and coalescing; direct unsaved edits; replaced documents sharing IDs; complete unique identifiers; bounded counts/bytes; preservation of corrupt, future, partial, oversized, directory and symlink sidecars; portable backup snapshots; committed import and failed-import recovery followed by navigation/reopen.

Compatibility: older Typefield versions or tools reading only `spaces.json` see focus from the last content save. Content remains in the existing schema; portable backup export uses current in-memory focus. A restored/replaced document intentionally ignores the old sidecar. Interrupted-import recovery can therefore restore focus from the last content save while preserving all document content.

## Many-canvas layout

The prior rendered-plan cache held 16 canvases. Computing board positions visited every canvas, including hidden ones, repeatedly evicting plans on boards above that limit. Separate bounded dimensions avoid that churn. Full plans now have a 64-entry / 16,000-element ceiling, retaining the existing per-plan and aggregate text/image limits. A font-catalog invalidation generation prevents an old in-flight calculation from repopulating cleared caches.

The final comparison includes positions, committed width, extents and visible-plan reads, excluding painting/SwiftUI/accessibility. Three cold and five warm trials; p95 is therefore the maximum of this small sample and should be treated as a focused algorithm comparison.

| Warm fixture | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| 16 website canvases, all shown | 0.040 / 0.048 | 0.136 / 0.151 |
| 17 website canvases, all shown | 123.621 / 126.588 | 0.158 / 0.164 |
| 32 website canvases, one shown | 57.752 / 62.530 | 0.071 / 0.073 |
| 32 website canvases, all shown | 232.067 / 243.398 | 0.257 / 0.286 |
| One canvas with 80 mixed-script text layers | 0.003 / 0.004 | 0.124 / 0.125 |
| 17 dense-text canvases, all shown | 1558.847 / 1587.526 | 2.162 / 2.197 |
| 32 dense-text canvases, one shown | 712.153 / 768.962 | 1.104 / 1.140 |
| 32 dense-text canvases, all shown | 2852.183 / 2857.896 | 4.023 / 4.057 |

The candidate rebuilds no plans on these unchanged warm passes; each cold pass builds once per canvas. Cold all-visible website16 changes 28.519 → 27.082 ms, website32 228.986 → 54.705 ms, dense32 2843.880 → 706.966 ms. The first dense layout remains expensive. A dimension miss seeds spare full-plan capacity without evicting any other plan, avoiding duplicate cold work.

Both caches share conservative retained-source/rendered-element, text and image limits: 16,000 elements, 2,000,000 UTF-16 units and 128 MiB compressed/decoded-image accounting. Dimensions have at most 256 entries; full plans at most 64, with at most 1,000 rendered elements and 1,000,000 rendered text units per plan. Hidden source layers/artwork count too. Shared copy-on-write storage may be counted more than once deliberately.

A correctness regression test reproduced canonical Unicode equality reusing stale attributed text (`é` versus decomposed `e` + accent). Relevant rendered strings now require exact UTF-8 identity. This adds a small measured hot-hit cost on tiny/previously cached boards, shown above; the report does not claim every case got faster. Fresh/cached plans, positions, transformations, sections, elements, colors, effects, attributed text and accessibility output match. Cache limits, hidden canvases, same-ID edits/undo and clear-during-build all pass focused tests.

Cumulative probe process residency after the fixture sequence was 146.89 MiB baseline and 63.67 MiB candidate; this is not peak memory or whole-app RAM. Redraw/accessibility invalidation and dirty-rectangle painting remain possible follow-up work.

## Letterform export and editing

SVG coordinate formatting now reuses local POSIX formatters per export, with unchanged three/four-decimal rounding and byte output. Ordinary outline edits skip a node-to-stroke lookup when path identities already identify their strokes; new/split paths still perform that lookup. Each native node-drag event captures the current selection once instead of re-reading the published property inside both per-node loops. No shared mutable global formatter is used.

| SVG batch fixture | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| 26 letters × 48 anchors | 44.33 / 44.63 | 3.587 / 3.617 |
| 26 letters × 600 anchors | 499.43 / 504.16 | 20.965 / 21.657 |
| One 10,000-anchor glyph | 320.45 / 322.44 | 11.993 / 12.065 |

Complete SVG bytes match the frozen exporter for the three batches and five fixtures covering handwriting nibs, pressure, counters, cubic handles and open paths. Regression tests compare signed zero, tiny values, rounding boundaries, bounded large coordinates and seeded random values against the prior formatter, and reject invalid geometry through export validation. Stroke grouping, explicit compounds and new/split-path ownership remain covered.

A comparable synthetic 4.87 MB Letterform store measured a synchronous save at about 133 ms, an undo+redo pair at 273 ms, and empty-project creation at 134 ms before this change. Those transactional persistence paths are unchanged. TrueType generation already runs on a worker queue and is retained. Final real native drag callbacks (15 samples) improve at all three sizes:

| Anchors | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| 48 | 0.045 / 0.051 | 0.022 / 0.024 |
| 600 | 0.419 / 0.440 | 0.171 / 0.201 |
| 10,000 | 6.876 / 6.974 | 2.659 / 2.740 |

Tests cover single/multiple node and handle translation, unrelated geometry, selection refreshed on every event, unchanged status, one commit at mouse-up, exact Undo/Redo and cancellation. Export timings use seven samples. TrueType stays about 4 / 43 / 25 ms on the respective fixtures; no speedup is claimed. Final synchronous save/undo+redo/project-create timings remain about 131 / 269 / 131 ms. Live candidate editing and export checks passed as described below.

## Validation and release

- `./install-local.sh`: complete optimized warnings-as-errors native suite passed and installed canonical `/Applications/Typefield.app` 0.59.29 (109). This includes actual multi-file backup integration, previous history/failure tests, import/export geometry, all new cache/SVG/drag checks, 21,265 font layouts and 779 families / 4,253 styles.
- `--window-self-test`: editor host identity, detach/redock/close, fullscreen/resizable windows, independent browser and typed font payload passed.
- `node tests/figma-import.test.js`: editable layers, typography, fallback, validation and rollback passed (mocked Figma API; no live Figma test claimed).
- Localization consistency: 620 keys × 11 languages passed; existing language sources and resources retained.
- Xcode registration parsed: all four new files occur exactly once in file references, Sources group and Sources build phase. Direct Swift build passed; no separate Xcode archive is claimed.
- Canonical strict signature and executable equality with `dist/Typefield.app` passed. Source hashes remained frozen during compilation and live QA. All 32 pre-existing saved-data hashes and both paused research hashes remain unchanged.

Live tests used `--window-qa --workspace-stress-qa`: two spaces with 1/8/32-canvas boards, and synthetic 24/600/10,000-anchor glyph projects. The flag is reachable only inside a UUID-named temporary Library. Baseline was built from the frozen 0.59.28 sources with the same opt-in fixture; candidate used the installed executable in a private QA bundle. No user fonts were registered. Both QA apps were closed after testing.

Baseline and candidate opened 1/8/32-canvas boards, showed all 32 canvases, transitioned to the 10,000-anchor project, nudged and undid the outline, and exported SVG. Candidate additionally scrolled through canvases 25–32, switched between both spaces and all three workspaces, duplicated a canvas and verified explicit Undo/Redo plus active-window keyboard undo, exported TrueType, drew a new rectangle in empty B, verified drawing undo/redo, physically dragged a node and undid it, and created an empty Letterform project. The fixture's Times-Roman fallback notice was present in both builds because of the QA catalog; it was not a new missing-font regression.

The two live dense SVG exports are byte-for-byte identical (190,409 bytes, SHA-256 `cf704122e8222cf1a8322088e17d413261d8df787f798e258d7df4bd14273d8e`). The live candidate TrueType export passed the application's macOS validation and completed its save. These UI checks establish workflow correctness; automation round-trip durations and physical trackpad frame latency are not reported as performance measurements.

DMG packaging, `hdiutil verify`, read-only mounted full-app comparison, canonical/built bundle equality and signed appcast validation passed. Both app plists and website metadata/checksum match 0.59.29 (109). Website JavaScript syntax and all eight feedback/site tests passed. Public distribution verification passed.

- DMG: `Typefield-0.59.29-beta.dmg`, 8,712,258 bytes.
- DMG SHA-256: `d4963dae246b03ebcdbcaa98a992206799ad9cdec080e6f626d974a4ce781118`.
- Executable SHA-256: `cfe5c4b82599e88ca450669e3484dde7afad8faad47b1e25f6457b1798a799cd`.
- Ad hoc signed direct-download beta, Apple silicon / macOS 13+; no Developer ID notarization claim.


Public release verification completed:

- Release source/assets commit: `8d7962c66b98ba6a4bf9b04b162a875aa756e667`, pushed to both origin destinations on main and `codex/performance-cleanup`.
- [Public GitHub prerelease](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.29-beta.1) contains the immutable DMG and SHA-256 file.
- Existing Cloudflare Pages `typefield` project deployed with its Functions bundle: `https://2b9886b5.typefield.pages.dev`. The canonical `https://typefield.app/download/` advertises 0.59.29 (109), correct same-origin/GitHub assets and checksum. Design and removed website release history remain unchanged.
- Independently downloaded unauthenticated GitHub and website DMGs match the packaged hash above. Public feed bytes exactly match the signed local feed; feed/archive signature validation passed. RSS content type and no-cache headers are present. `/api/feedback` remains configured and healthy.
- Canonical About shows 0.59.29 (109). Check for Updates reports “Typefield 0.59.29 is currently the newest version available.” Settings was closed and the app left on the user's Library.
- Final post-launch verification again finds all 32 baseline saved files and both paused research edits unchanged. All raw evidence remains private under the round-two artifact directory.
