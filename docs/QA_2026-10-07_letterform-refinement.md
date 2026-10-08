# Letterform outline editing and Spaces symmetry QA

## Reproduction and design

The reported A contains two closed contours forming the letter/counter and three open paths over them. In the old editor, closed and open paths had almost identical outline styling, and the Bézier tool could start a new path at an existing closed anchor. A private, fixed-frame AppKit reproduction found that moving an open overlay changed zero solid-fill pixels, while moving a closed anchor changed 3,013 pixels. This reproduction diagnoses the saved representation; the production-canvas regression separately verifies actual drag rendering.

The interaction design follows the explicit anchor/handle/segment targets documented by [Illustrator Direct Selection](https://helpx.adobe.com/illustrator/using/tool-techniques/direct-selection-tool.html) and [FontLab Contour editing](https://help.fontlab.com/fontlab/7/manual/Contour-tool/#modifying-segments). FontLab also exposes [filled glyph display while retaining nodes and handles](https://help.fontlab.com/fontlab/7/manual/View-panel/). Typefield deliberately uses segment reshaping with fixed endpoint anchors; glyph editors do not all use identical segment-drag semantics.

## Changes in 0.59.21 (101)

- Default to Nodes; selecting Objects/Nodes also enters the editing tool. Simplification returns to point editing with no multiselection, so the first anchor drag changes one anchor.
- Expose Fill and a contour list directly beside canvas controls. Distinguish open paths from closed outlines and explain why open paths do not fill. Keep all existing artwork until an explicit, undoable user edit.
- Resolve nearby anchors/handles by proximity; edit existing closed anchors when clicked with Bézier instead of silently creating overlays. Hide inactive endpoint handles.
- Drag a segment to bend it with fixed anchors. Keep smooth connections, allow Option to break smoothness, and preserve transaction cancellation/undo.
- Observe provisional geometry in the word proof without saving drag frames. Resolve components against that same provisional glyph.
- Detect mapped open contours before the static TrueType save dialog; preserve unfinished paths in project and SVG saves.
- Expose Spaces symmetry in its toolbar and selection inspector. Preserve exact mirrored placement instead of shifting an out-of-bounds mirror copy to fit.

## Validation

- The isolated optimized native suite passed. Production NSView rendering measured 4,056 changed solid-interior pixels after a simplified-A anchor drag (4,053 visibly matched the updated geometry), and 4,710 after a handle drag (all matched). Regression checks cover fixed-endpoint segment bending, nearby/overlapping targets, Pen editing existing anchors, inactive open-end handles, cancellation, one-commit history, bounds rejection, fill view state, component proof and partial-contour selection safety.
- Nine scaled Spaces mirror cases passed, including prior transforms, mixed text/shapes, groups, exact bounds, atomic rejection, persisted undo/redo and 149.4-pixel text frames. Cross-format clipboard and Figma bridge checks passed. Native window checks passed docking, detachment, close, resize, fullscreen and independent browser lifetime.
- In a separately sandboxed app, a disposable copy of the reported A reproduced the three open overlays. Fill off/on, selective removal of the three open paths, undo/redo, individual square-anchor movement, segment bending, handle editing and Pen editing existing anchors all worked visibly. Quit/relaunch retained the edited two-contour A and its exact anchor position. The live proof matched the edited silhouette; typing A/F in the proof field did not invoke canvas shortcuts.
- Dense B simplified from 428 to 22 nodes while retaining both counters. The first drag moved one anchor. Undo restored the node edit, then all 428 nodes; redo restored the simplified outline.
- TrueType export stopped before the save dialog while mapped A/G had open paths. Removing only those unfinished paths allowed export of 26 letters plus space. Font Book accepted and installed the resulting temporary font; CoreText verified the actual installed file and rendered edited ABC outlines. The byte-verified test font was then unregistered and removed from the font folder. User fonts were not modified.
- Live Spaces checks passed both flips, vertical/horizontal-axis copies and four-way symmetry through the inspector and toolbar. One Undo removed all three four-way copies; Redo restored them. Quit/relaunch retained all reflected coordinates and orientations, with complete saved JSON equality.
- The final warning-refresh replay passed in the disposable app: A/G warning → G-only warning immediately after repairing A → no warning immediately after repairing G. Native checks additionally cover save-error preservation and older projects with an implicit selection.
- All 30 recorded original saved-data files remained byte-identical. Two paused research edits remain untouched. Raw artwork and fixtures remain private under `.context/qa-artifacts/letterform-editor-2026-10-07/`.

The final integrated build adds the preflight-warning refresh and includes the separately released 0.59.20 onboarding changes. The final native suite and window self-test passed. `./install-local.sh` installed the canonical app; its version, strict signature and executable hash match the read-only mounted, verified DMG. The [public website](https://typefield.app/download/) and [GitHub prerelease](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.21-beta.1) both serve the same verified DMG without authentication. The live feedback API is healthy. This is bounded adversarial coverage, not a claim that every possible interaction has been tested.

Final executable SHA-256: `230c7135e2674778159e229f0839752e0a6025d75b73bd394aa7db969f8bd8a3`. DMG SHA-256: `2a4f801ddbfefd6cc9aae699aa0e3c5ac7beccf347bc219f582804b734acd77c`.
