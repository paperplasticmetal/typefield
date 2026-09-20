# Build and verification status

Current source: **0.21.0, build 29**. Updated 2026-09-20.

| Check | Status |
| --- | --- |
| Local optimized Apple Silicon build, Swift warnings as errors | Passed |
| Built-in regression suite | Passed |
| Layout checks | 21,260 cases across 4,252 available styles on the release machine |
| Xcode Release build, 0.21.0 | Passed |
| Spaces and canvas regression checks | Passed: independent directions, checkpoints, imported layers, persistence and 28 canvas/viewport combinations |
| Live folder watcher and session activation | Passed with a temporary copy of an existing Google font; visibility checked in a separate process, then deactivated and removed |
| New designer UI | Website desktop/mobile comparison and Unicode lookup/metrics inspected locally |
| 0.16 interaction checks | Native canvas/sidebar dragging, Quick A/B, typeboard sidebar deletion/Undo, numeric Undo/Redo, saved divider width, opaque font chooser and header/toolbar spacing verified; see INTERACTION_AUDIT.md |
| 0.17 interaction checks | Canvas tabs/show-all, exact clicked-text editing/Undo, existing collection filtering, persistent unselected-board delete confirmation, live-folders shortcut, 200% zoom and return-to-Fit verified. Physical pinch/Command-scroll gestures still need hands-on verification. |
| 0.18 interaction checks | Developer handoff package contents/type-checking and inline project/typeboard/collection renaming verified. |
| 0.19 interaction checks | Stable multi-canvas visibility, one-action solo/hide, font-summary detail levels and role-to-canvas selection verified. Canvas/typeboard/project collection scopes, family deduplication and no-overwrite behavior are regression-tested. Role-drop model and payloads are regression-tested; the physical drag gesture still needs hands-on verification. |
| 0.20 font health | Local scanner UI and severity/fix workflow inspected across 2,624 user/watched files. Malformed-name fixture repair, duplicate removal, identity preservation, SFNT checksum rebuilding and in-memory Core Text validation of a real rebuilt font pass. No real user font was modified; App Store sandbox in-place-repair access remains unverified. |
| 0.21 typography exports | Automated checks cover selected-canvas combined summaries, generated type-system settings and one PDF page per selected canvas. Native picker and installed-app smoke check passed locally. |
| Figma bridge | Mocked API suite passed; live outbound editable frames and reverse selected-frame JSON import verified, including editing, movement/Undo and relaunch persistence |
| Unsigned archive and asset catalog, 0.12.3 | Passed; archive not checked into source |
| Sandbox/hardened-runtime clean launch and installed-font export, 0.12.3 | Passed |
| Google preview UI, 0.13.1 | Installed and remotely loaded samples verified |
| GitHub-hosted checks | See the live workflow badge; results are not inferred from local tests |
| Distribution signing / App Store Connect validation | Pending |
| macOS 13 and second-machine testing | Pending |
| Intel support | Not shipped |

Regression checks cover catalog/search/filtering, persistence and corrupt-data preservation, family merge/split and shortlist remapping, tags, variable settings, OpenType parsing and actual ligature changes, duplicate hashing, export collisions, and preview text integrity. Layout counts depend on fonts available on the machine. Tests do not download fonts or upload personal data.

Manual checks do not certify every font/script or failure case. Offline preview failure, denied folder access after relocation/revocation, broader accessibility testing and clean second-device testing remain on the release checklist. Rebuild the signed distribution archive before any submission.

The live activation check requires normal macOS execution outside the coding-tool sandbox. Session activation in the App Store sandbox has not been verified for 0.14.0. Watching runs only while the app is open. New tests also cover recursive folder replacements/removal, nested tag inclusion/exclusion, glyph SVG generation, long specimen pagination and backup merge. Test-runner crashes encountered during development were corrected; new studio checks report failures without intentionally trapping.

Not complete Typeface parity: direct Adobe integration, a published Figma plug-in, document-triggered activation, cloud collaboration and advanced color-font controls remain out of scope for this release. The local Figma bridge supports two-way JSON handoff with documented fidelity limits, not native `.fig` decoding or live sync. Custom template canvases use ordered blocks; imported Figma layouts retain independently movable layers. Font Health does not rewrite TTC/OTC collections, WOFF/WOFF2/dfont containers, outlines, hinting, layout tables or ambiguous/missing identity records.

Local bundles are ad-hoc signed. They are not notarized downloads and are not App Store packages. A passing CI run does not guarantee App Review approval.
