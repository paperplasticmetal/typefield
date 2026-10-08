# Letterform toolbar and responsiveness — 0.59.26 (106)

## Changes

Seven fixed-size tools replace the separate Objects/Nodes mode selector: Select (V), Nodes (A), Pen (P), Line (L), Rectangle (R), Ellipse (O), Hand (H). Each has a 44 × 44 point target, a visible shortcut, an accessible name/selected state and shortcut help. Paths and Transform sit beside the tools and wrap together in narrow editors. Contextual construction actions retain a fixed-height row; tool hints no longer resize the canvas. Tool presses restore keyboard focus to the drawing canvas.

Word Proof's disclosure sits beside its title. Its live geometry observes glyph changes instead of all editor state and resolves distinct proof letters against the complete component dictionary. Changes to tools, selection, zoom and pan no longer trigger complete-font proof resolution. Live source edits still update transitive components even when the source letter is absent from the proof.

Dense outlines reuse bounded editing overlays and normalized segment hit-test geometry. Caches include geometry, selection, viewport, scale and resolved appearance colors; live fill, gesture feedback and focus remain independently drawn. At most two four-megapixel overlays are retained.

## Evidence and status

- Isolated AppKit probe: unchanged 10,000-anchor redraw approximately 73.4 → 5.7 ms; segment hit test 1.01 → 0.16 ms. These are bounded canvas measurements, not whole-app or cold-open timings.
- New hosted-toolbar checks cover real 44-point accessible controls, nonoverlap, visible shortcut help, all seven activation/focus paths and stationary canvas/tool frames at widths 1100 and 440.
- New cache checks compare cached pixels with a fresh canvas and exercise geometry/handle, selection, tool, viewport, size and appearance changes. New proof checks cover visible equivalence, repeated/missing glyphs, legacy strokes, failure fallbacks, live transitive components, masters, Undo/cancellation and geometry-only publications.
- Final optimized native suite passed: 779 families / 4,253 styles, including all new hosted toolbar, dense-render and proof regressions, existing editing/persistence/TrueType checks and integrated Spaces checks. Native window checks, Figma bridge mocks and 14 signed-feed regression cases passed.
- Disposable live QA passed physical margin clicks on all seven tools, all shortcuts, text-input protection and focus return, A anchor/fill/proof edits with Undo/Redo, dense asymmetric 10,000-anchor switching/edit/Undo, rectangle/ellipse creation, saved-project reopening, docking and minimum-window resizing. The final Paths button also passed edge clicks, native menu dismissal, Manage contours and Outline stroke popovers. Idle Escape returns to Select with a fresh hint.
- Final native proof benchmark: 12 resolutions of a 256-glyph × 400-node fixture with three distinct proof letters took 75.325 ms for complete-font resolution and 0.878 ms for selective resolution. This compares the same visible geometry; UI-only editor changes trigger neither resolution path in the new proof subscription.
- Canonical `/Applications/Typefield.app` installed using `./install-local.sh`; strict signature and installed/dist executable equality pass. Executable SHA-256: `7d433d9c7f305b31180d30e2e42fb69ab197c260291b083b35a143e02416d5df`. Public distribution verification remains pending.
- All 31 saved-data hashes captured at the start of this pass and both pre-existing research-file hashes are unchanged. Spaces' earlier baseline captured a user Letterform change before this pass; the current saved file was preserved.

## Scope

This pass refines Letterform controls and the identified redraw/proof hotspots. Library search, catalog shaping and app-wide loading are owned by the parallel performance workstream. Physical trackpad feel, every font style and exhaustive interaction coverage are not claimed. Missing-letter research remains paused. User fonts and saved projects are preserved; disposable fixtures are used for edits.
