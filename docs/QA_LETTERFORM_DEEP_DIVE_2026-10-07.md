# Letterform Editor interaction deep dive — 2026-10-07

This pass covers editing, saving, import/export and the practical beta experience. Missing-letter model research remains paused. Native event replay and live application checks are reported separately; neither establishes that every possible interaction or hardware configuration has been tested.

## Current verification status

**Typefield 0.59.15 (95) is installed at `/Applications/Typefield.app`.** `install-local.sh` completed successfully, including the complete optimized native suite. All Letterform tests and 21,260 font-layout checks passed; the concurrent Spaces resize regression that stopped the first snapshot was repaired and also passed in the final run. The window self-test and Figma bridge test passed. The website passed its eight local tests and consistency checks.

The canonical app passed strict signature verification and matches the built executable. Its executable SHA-256 is `7e93bd66a657656bcfc660d292b1e27921cc250a6ecf79f1230df1817b38dea4`. The matching DMG passed verification and was mounted read-only; its app reports 0.59.15, has the identical executable and passes signature verification. DMG SHA-256: `6cf92245bdcd7b2bf4d91c2d5e7a27b32ec63313e35757aaac531f101243f212`.

Final live replay used that exact installed executable in a disposable QA bundle. It confirmed complete-object mode transitions, keyboard copy/paste immediately after glyph navigation, numeric error recovery and repaired Sketch Reshape for both vector outlines and pen strokes. Source commit `67c3b08` and website commit `b2d1e1e` were pushed to both origin destinations. The [GitHub prerelease](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.15-beta.1) and [public download](https://typefield.app/download/) are live. Unauthenticated downloads from both sources match the verified DMG byte for byte; the feedback public-configuration endpoint responds correctly. Final live export produced a 2,224-byte font containing three drawn characters plus space. Font Book installed it; independent Core Text lookup mapped ABC to glyphs 4/5/6 and rendered the expected two ellipses and pen stroke. Only the exact byte-verified installed fixture was unregistered and moved into private evidence. Distribution verification is complete.

Private evidence is under `.context/qa-artifacts/letterform-deep-dive/`, including `native-first.log`, the complete `install-0.59.15.log`, the installed-font proof and the saved-data/research comparisons. The latest comparison reports no changed hashes among 29 existing user-data files or the two interrupted research edits. Disposable QA projects and fonts were kept separate from the user's projects and fonts.

## Repairs verified in 0.59.15

- Object marquee selects the complete outline and its counter; Shift-click can deselect the complete object. A one-node unfinished path remains visible, selectable and movable in Objects mode.
- Group dragging stops at the design-box edge. Snapping follows the grabbed node, and Shift-constrained movement retains its locked axis.
- Smooth-handle dragging through its anchor retains the opposing handle length. Collapsed handles no longer intercept anchor dragging. Open-endpoint smoothing follows the adjacent segment rather than wrapping to the far endpoint.
- Retracting rectangle or ellipse creation to its origin removes the old preview. Bézier placement, node movement and resize gestures preserve a single undo boundary.
- Canvas focus loss and detachment finish pending edits. External glyph replacement discards stale gesture state. Transactions clear before callbacks, preventing duplicate commits during a view rebuild. Holding Space through key repeat continues panning.
- Vector fill and routine editing retain independently painted source strokes. Opposite-winding overlaps remain filled, while counters stay in their compound outlines. Split fragments retain their source group; copy and duplicate preserve groups. Make counter explicitly combines enclosing groups, and rejects contours crossing outside the proposed parent. Remove overlaps unions independent source fills and retains unselected sibling counters.
- Clipboard transfer preserves physical horizontal size, curve handles and baseline position across glyphs/projects. Invalid or oversized data leaves the destination unchanged; older clipboard arrays remain supported.
- Path commands reflect whether the selected nodes actually define eligible segments or open/closed contours. Invalid numeric transforms are rejected. Setup sheets retain rejected changes and recover valid picker selections after master/group changes; rejected simplification keeps its preview available.
- Sketch Escape restores the pre-gesture glyph. Undo/Redo, focus loss, tool changes and detachment finish the current transaction and ignore trailing pointer events. Replacing a glyph discards its unfinished preview.
- A completed failed background save remains eligible for retry after the destination becomes writable, including after the visible error is dismissed. Retry save is available for persistence errors. Rejected glyph mutations and failed synchronous Undo/Redo/clear saves preserve the applicable history.
- Artwork import trims labels consistently and checks cancellation during generation. Curve fitting runs away from the main UI thread; controls are held stable while import is running, and cancellation prevents a late result from applying.
- Simplification validates crossings, containment and filled shape within the original paint groups, preserving the union of independent strokes.
- Static TrueType export preserves independently painted fills, reversed outer contours and counters. Compatible variable masters retain corresponding points and group winding; ambiguous mixed outer winding is rejected. Dense pen export reserves both endpoints of every line, and refuses an impossible budget instead of reducing lines to dots. Unsupported/unlisted unfinished glyphs do not block mapped characters. Corrected outline conversion gets a fresh font-cache revision identity.

## Refinements completed after the first snapshot

The final native suite includes these refinements. Live confirmations are identified separately below.

- Clipboard coordinate conversion tolerates floating-point overflow of at most `1e-12` at exact design-box/handle boundaries, while the regression still rejects genuine overflow.
- Valid coordinate/transform submissions clear stale rejection text, including unchanged submissions without an undo entry. Operation-specific success messages remain visible. Final live replay confirmed invalid `nan` reset to 108, followed by a valid 109 submission that moved the object and cleared the error.
- Switching from Nodes to Objects expands a partial selection to complete compound shapes. Returning from Pen to Select also normalizes object selection; midpoint insertion enters Nodes mode to expose its selected nodes. Final live replay selected one ellipse node, changed to Objects, then moved all four selected nodes by one unit.
- Workspace copy/paste/select-all shortcuts cover the focus gap after choosing another glyph, while preserving text-field and sheet shortcuts. Final live replay copied, clicked B, and pasted immediately with Command-V.
- Sketch Reshape now exposes editable points for pen strokes, legacy contours and vector outlines. Native checks cover tablet metadata, relative curve handles, bounds, one-gesture history, Undo/Redo and Escape. Final live replay moved a vector anchor and undid it, then reshaped the endpoint of a fresh two-sample pen stroke.
- The three new Letterform check files were registered in the explicit Xcode source manifest. The final canonical build/install and full native suite passed.

## Interaction matrix

“Final native pass” refers to the 0.59.15 (95) full-suite run. “Live pass” covers the observed workflows; rows explicitly identify the critical interactions replayed with the exact final installed executable. Earlier live workflows are not presented as a second final-version replay.

| Interaction | Evidence and assertions | Status |
| --- | --- | --- |
| Objects and nodes | Native compound marquee/movement, individual-node marquee, whole-object Shift deselection, isolated-node selection/movement | Final native pass; final live mode transition and whole-object nudge pass |
| Node dragging | Native design-box edges, one commit, Shift plus guide snap, grabbed-node snapping in multiselection; live coordinate nudge and numeric movement | Final native pass; live pass |
| Bézier handles | Native new-node handles, smooth-handle zero crossing, Option break, collapsed-handle hit priority and endpoint tangent direction; live smooth-handle drag followed by Undo/Redo | Final native pass; live pass |
| Bézier lifecycle | Native successive placement, click-first-node closure, Escape during/between gestures and reverse twice | Final native pass |
| Shapes and resizing | Native rectangle/ellipse preview retraction, corner resize with/without Shift, opposite-corner retention and cancellation; live rectangle/ellipse creation, whole-ring corner resize and Undo | Final native pass; live pass |
| Gesture interruption | Native focus loss, same/different-character replacement, stale drag/mouse-up, reentrant commit and Escape restoration | Final native pass |
| Viewport | Native repeated-Space pan and Escape without glyph edits, focus bounds and zoom-dependent hit testing; live Focus at 209% | Final native pass; live focus pass; physical trackpad/pinch unverified |
| Sketch | Native pen, Escape, interrupted Undo/Redo, focus/tool/detach/replacement, eraser cancellation and empty eraser no-op; live draw, erase and Undo | Final native pass; live draw/erase/Undo pass; final live vector/pen Reshape pass |
| Saving and recovery | Native induced asynchronous failure, error dismissal, destination repair, flush and exact reload; atomic save, stale snapshot rejection, corruption preservation, delete/restore | Final native pass; final live save/reopen passed in isolated macOS app container |
| Clipboard and commands | Native physical units/baseline, independent identities, repeated paste, invalid/oversized input, legacy clipboard and command eligibility; live A-to-B transfer of two contours via Paths paste | Final native pass; live compound paste pass; final live immediate keyboard paste pass |
| Paint groups and counters | Native bitmap overlap, 9,600 fixed sample comparisons during movement, duplicate/paste, counter/overlap operations and split ownership; live hole/handle preservation through transfer and resize | Final native pass; live pass |
| Path operations | Native split/join, exact cubic midpoints, reversal, open/close, deletion, smooth/corner, alignment/distribution, extrema and Booleans | Final native pass; not every operation separately exercised live |
| Dense outlines and accessibility | Native 10,000-anchor caching/hit behavior, 10,600-anchor compound selection, bounded history and accessible selection/movement/deletion; 30,000-anchor curve-fit fixture | Final native pass; sustained live dense editing and real VoiceOver session unverified |
| Artwork import | Native sheet/single/grid tracing, detached dots, counters, source protection, persistence and export; live SVG ring plus two dots retained four contours/28 anchors and saved a new project | Final native pass; live pass |
| Font design | Native components, nesting/cycle/bounds rejection, master isolation, kerning groups/exceptions and design persistence | Final native pass; live four-tab review, staged edits and Cancel pass; every setup permutation not exhausted |
| SVG and TrueType | Native exact SVG curves, proportions/counters/identity, mapped open-contour rejection, static/variable fill agreement and bounded points; live initial export, Font Book install and Core Text resolution/rendering | Final native pass; initial and final live export/install/render passed |

## Live application evidence

Initial automation attempts in the main window failed with `windowNotFoundAtPosition`. Moving to the detached editor resolved desktop pointer delivery; physical mouse-driven curve and resize tests subsequently succeeded. The earlier delivery failure is not treated as a canvas defect.

| Workflow | Observed result |
| --- | --- |
| Practice handwriting project | Opened with 5 of 76 characters completed |
| Keyboard edit and history | X moved from 180 to 181; Undo restored 180 and Redo restored 181 |
| Draw and form a counter | Created a rectangle and ellipse; Make counter produced a visible hole |
| Handle edit and history | Dragged a smooth handle; Command-Z visually restored the ellipse and Shift-Command-Z restored the edited curve |
| Numeric rejection and recovery | Initial testing found stale rejection text after a valid move. Final live replay of 0.59.15 rejected `nan` and reset X to 108; entering 109 moved all selected nodes and cleared the error |
| Clipboard across characters | Copied two contours from A and pasted into B through Paths; the hole and curve handles were preserved. Final live replay also confirmed Command-C, click B, immediate Command-V without refocusing the canvas |
| Selection-mode transition | Final live replay changed a one-node ellipse selection to Objects; all four nodes became selected. Right Arrow moved all four by one unit |
| Compound resize | Focus displayed 209%; dragging a corner resized both outer contour and counter. Undo restored the original size |
| Sketch tools | Drew a stroke, removed it with Eraser, then restored it with Undo. Final live replay confirmed blue vector anchors in Reshape, a top-anchor drag that changed the outline, Undo restoration, and endpoint reshaping on a fresh two-sample pen stroke |
| Import | Imported the private SVG fixture containing a ring and two detached dots. All four contours and 28 anchors survived visibly; a new disposable project was saved |
| Font setup and Cancel | Visited Masters, Components, Kerning and Glyph set. Staged a Bold master, OV kerning and five accented characters; Cancel returned to the unchanged 76-character project |
| Docking | Docking retained the imported glyph's selected node and available Redo state |
| Initial TrueType export | Review showed five drawn glyphs plus space and 71 omitted characters; export produced a 4,992-byte file |
| Install and independent rendering | Font Book installed the fixture in the current user's scope. Core Text resolved its installed PostScript identity, mapped `ijnop` to five glyph IDs, and rendered a proof |
| Final TrueType export and install | Exported three edited characters plus space as a 2,224-byte file. Font Book installed it; Core Text system lookup resolved its exact installed URL and rendered ABC/CBA with the expected outlines |
| Quit and reopen | In a separate macOS sandbox container using the exact final executable, edited handwriting i from X 180 to 181, quit, relaunched and confirmed X 181 with all five glyphs intact |
| Fixture cleanup | Unregistered and moved only the two installed test fonts after their bytes matched the corresponding exports. No other installed font was removed |
| User-data preservation | The latest comparison reports unchanged hashes for all 29 pre-existing user-data files and both interrupted research edits |

## Verified persistence and remaining limits

- Final-version live save/reopen passed in the same executable signed into a disposable macOS sandbox container: the handwriting i node moved from X 180 to 181, the process quit, and reopening the saved project retained X 181 and all five drawn glyphs. Native atomic persistence, failure retry, stale snapshot rejection and reopen checks also passed.
- Sustained dense-outline editing, real tablet pressure/tilt, physical trackpad/pinch, VoiceOver navigation and a second-Mac/macOS 13 runtime pass remain unverified. All four setup tabs were visited and staged changes were cancelled successfully; every setup control/permutation was not exhausted live.
- Distribution checks passed: canonical app, matching DMG, both GitHub pushes, public release and website downloads, feedback configuration endpoint and final unchanged user-data/research hashes. No beta-report submission was sent.
- Object marquee retains anchor-hit selection semantics, expanded to a complete compound object. It does not promise selection for every rectangle that crosses a curve while containing none of its anchors.
- Normal edits and explicit design/import application retain the existing asynchronous persistence workflow. A successful in-memory application is not a synchronous durability guarantee; save failures retain the data and expose retry/recovery.

## Reproduction

Run `bash build.sh` for the optimized native suite. `FontLabStore.selfTest()` invokes `FontLabPersistenceChecks` and `FontLabEditorStateChecks`; `FontLabVectorChecks.run()` invokes `FontLabInteractionChecks`. Fixtures use disposable in-memory glyphs and temporary persistence destinations. Run `node tests/figma-import.test.js` for the Figma bridge regression suite. The release coordinator owns build scheduling, installation, release evidence and final status updates.
