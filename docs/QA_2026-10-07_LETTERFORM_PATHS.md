# Letterform path construction refinement — 2026-10-07

Status: candidate native and live runtime validation passed; final release integration and distribution pending. Baseline: `55a3aab`, public 0.59.21 (101). No suggestion-model research or scoring protocol changes.

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

Figma bridge mock suite passed. Live UI results are recorded below; final release verification remains pending. Private evidence and original data hashes remain in `.context/qa-artifacts/letterform-paths-05922/`; that directory was named before concurrent release coordination and does not determine the shipped version.

## Live candidate checks

Disposable A was built from two connected Line segments and a separate crossbar. A 60-unit outline preview produced two closed contours with 15 total anchors; invalid width 0 disabled conversion. Undo restored both exact open centerlines and redo restored filled geometry. One anchor drag visibly changed both canvas fill and word proof; Undo and the Fill toggle behaved correctly.

Disposable B exercised corner/curve Pen placement, Return, first-end continuation with reversed node order, and Close after finishing with only one endpoint selected. C used three smooth Pen anchors; outlining generated one closed 13-node curve with rounded ends and an open letter counter.

All three glyphs exported through the real TrueType save workflow, installed via Font Book, and passed independent CoreText system-font lookup and outline rendering with no fallback. The exact temporary installed font was byte-verified, unregistered, and moved back into private QA artifacts. All 31 original saved-data hashes and both interrupted-research hashes remained unchanged at this check.

Live QA also reproduced canvas resizing while the first open path appeared. The open-path notice now overlays the canvas instead of consuming new layout height. A hosted SwiftUI/AppKit regression checks the canvas identity, frame and design rectangle during a provisional Line gesture at wide and compact sizes. Both hosted sizes passed in the complete native run. A subsequent live replay confirmed that the notice appears inside the canvas without shifting the grid or existing A. Undo removed the test segment.

The final candidate reopened the saved A/B/C project with byte-for-byte equivalent JSON and the same visible outlines and proof.

Initial native candidate compilation succeeded and geometry/existing editor checks passed. A new Pen crossbar fixture failed because its start point lay exactly on an existing diagonal, intentionally triggering point insertion; the separate-path fixture was moved into empty space while retaining the dedicated curve-insertion check.
