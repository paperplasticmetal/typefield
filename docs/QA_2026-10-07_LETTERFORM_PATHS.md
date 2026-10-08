# Letterform path construction refinement — 2026-10-07

Status: 0.59.23 (103) installed and publicly distributed. Native and live runtime validation passed; completed Spaces 0.59.22 retained. Baseline: `55a3aab`, public 0.59.21 (101). No suggestion-model research or scoring protocol changes.

## Interaction changes

- Line (L): drag a segment, Shift constrains physical angles to 45 degrees, connect to open endpoints. A click or a retracted drag creates no point and no undo entry.
- Pen (P): either-end continuation, point/handle preservation when reversing a path, endpoint joining, segment insertion, closure, and Return to finish. Hover rings and a next-segment preview communicate the action before clicking.
- Continue/Finish, Join, Close path and Outline stroke are visible beside the canvas. Command-J joins two selected endpoints without intercepting text input. Closing remains available after finishing a path with only its endpoint selected.
- Outline stroke previews round caps/joins at 2–200 physical font units and converts each selected open centerline into a compound filled outline. Counters stay attached; existing paths remain unchanged; out-of-bounds ink rejects atomically.
- Drawing transactions cancel on Escape and commit once. Return in Line does not secretly smooth the selected endpoint. Restoring closed geometry, duplicating, and switching tools clear stale drawing state.

## Comparison and scope

Compared primary documentation for [Illustrator Pen](https://helpx.adobe.com/illustrator/using/tool-techniques/pen-tool.html), [Illustrator path adjustment](https://helpx.adobe.com/illustrator/using/adjust-path-segments.html), and [FontLab Pen](https://help.fontlab.com/fontlab/7/manual/Pen-tool/). Endpoint continuation, visible joining, curve-preserving insertion and click/drag construction informed the changes. Typefield retains direct anchor dragging rather than adopting FontLab's destructive click-on-node behavior. Open centerlines are visibly unfinished font geometry; closing or outlining creates solid ink.

This is a targeted construction pass, not Illustrator/FontLab feature parity or a claim that every possible interaction is tested. Stroke cap/join options currently use round geometry. Mid-segment branch welding, live non-destructive stroke widths and pressure-width profiles remain outside this change.

## Validation record

The complete candidate native suite passed, including FontLabPathConstructionChecks, FontLabPathDrawingChecks and existing editor/import/export checks. The new checks cover all four endpoint orientations, straight and curved bridges, coincident merges, counters, curve samples, width across aspect ratios, invalid geometry, event transactions, undo/redo, saved-store reopening and TrueType/SVG export.

Figma bridge mock suite and native window self-test passed. Live UI and completed release verification are recorded below. Private evidence and original data hashes remain in `.context/qa-artifacts/letterform-paths-05922/`; that directory was named before concurrent release coordination and does not determine the shipped version.

## Live candidate checks

Disposable A was built from two connected Line segments and a separate crossbar. A 60-unit outline preview produced two closed contours with 15 total anchors; invalid width 0 disabled conversion. Undo restored both exact open centerlines and redo restored filled geometry. One anchor drag visibly changed both canvas fill and word proof; Undo and the Fill toggle behaved correctly.

Disposable B exercised corner/curve Pen placement, Return, first-end continuation with reversed node order, and Close after finishing with only one endpoint selected. C used three smooth Pen anchors; outlining generated one closed 13-node curve with rounded ends and an open letter counter.

All three glyphs exported through the real TrueType save workflow, installed via Font Book, and passed independent CoreText system-font lookup and outline rendering with no fallback. The exact temporary installed font was byte-verified, unregistered, and moved back into private QA artifacts. All 31 original saved-data hashes and both interrupted-research hashes remained unchanged at this check.

Live QA also reproduced canvas resizing while the first open path appeared. The open-path notice now overlays the canvas instead of consuming new layout height. A hosted SwiftUI/AppKit regression checks the canvas identity, frame and design rectangle during a provisional Line gesture at wide and compact sizes. Both hosted sizes passed in the complete native run. A subsequent live replay confirmed that the notice appears inside the canvas without shifting the grid or existing A. Undo removed the test segment.

The final candidate reopened the saved A/B/C project with identical saved glyph data and the same visible outlines and proof.

Initial native candidate compilation succeeded and geometry/existing editor checks passed. A new Pen crossbar fixture failed because its start point lay exactly on an existing diagonal, intentionally triggering point insertion; the separate-path fixture was moved into empty space while retaining the dedicated curve-insertion check.

Final review caught a continuation/Undo edge case before installation: undoing a Continue-from-first orientation reversal left Pen active at the opposite endpoint. Restoring reversed endpoints now finishes active construction while retaining selection; an unchanged commit echo retains drawing state. A focused event regression covers the next Pen click after Undo. The interrupted final build did not install an app; the corrected source passed a fresh full run, including the new regression and cleared stale continuation hint. The release build also passed the native window self-test.

## Release package

Canonical `/Applications/Typefield.app`: 0.59.23 (103), built and installed with `./install-local.sh`. The complete integrated native suite passed. Strict signatures and executable identity match the built app, canonical installation and read-only mounted DMG. All 31 saved-data hashes and both paused-research hashes remain unchanged.

DMG SHA-256: `c116d6ef045874079aa26f42e9c1ea1c1fc9003b2317e974dac8283e6310ce4a`. Public GitHub release `v0.59.23-beta.1` and the live website both serve this exact 7,226,864-byte DMG. The live download page advertises 0.59.23 (103), with matching direct/GitHub links and checksum. Cloudflare deployment `ddf5e872` includes the feedback Function; its public configuration endpoint is healthy. Both origin repositories contain the source/package release commit `f9af41a7b3667307308e769db1c9b6d093766839`. Eight website tests and JavaScript syntax checks passed.

The final live continuation replay selected the first endpoint, continued it, undid the orientation edit, then clicked empty space. The restored Continue button and independent one-node path confirmed the corrected behavior; Undo restored the original A. The stale continuation hint was subsequently cleared and covered by the passing final native regression.
