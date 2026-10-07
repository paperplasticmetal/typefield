# Interactive onboarding refinement — 0.59.16 (96)

The tour is a local typography playground: a clickable type specimen, editable preview and three typefaces, two layouts using the same specimen, and a letter with a draggable bowl point and accessible width slider. Demo state lives only in the tour. It does not register fonts, create projects, or save specimen changes.

The four steps keep a fixed frame, use short eased transitions, and honor Reduce Motion. Navigation buttons expose their selected state, Return advances, Escape skips, and the curve has an accessible slider alternative to dragging. The tour is available again from Help → Getting Started Tour. Workspace opening waits for sheet dismissal and brings an already detached editor forward.

Removed the obsolete parallel About/Shortcuts sheet implementation; those menu actions continue to use Settings. Sidebar menu shortcuts now match the existing sidebar-button animation. Repeated Dock icon updates reuse the completed composite and skip assignment when the effective palette/appearance has not changed.

## Verification

- Standalone Swift compilation with warnings as errors passed for the tour. The icon change also passed standalone typechecking.
- Disposable live preview: all four steps, typeface change, custom specimen propagation, both layouts, navigation/back/state retention, long-input bounding, point drag, slider accessibility decrement, reset, Return, Select All/text entry, and Escape passed. The initial editorial demo clipped body copy; the corrected layout was recompiled and visually verified.
- Light and dark appearances inspected. A copied preview source substitutes the read-only Reduce Motion environment value for the reduced-motion check; the production view reads the actual SwiftUI accessibility environment. No system accessibility preference was changed. A live VoiceOver speech audit was not performed.
- Figma bridge mock checks passed.
- A narrow, unbundled AppKit microbenchmark measured 100 duplicate icon callbacks at 1,721.077 ms before and 0.077 ms after; initial rendering stayed near 30 ms. This measures repeated composite construction/assignment calls, not whole-app launch or visible Dock rendering.
- Independent source review caught the Help menu label and detached-editor destination behavior; both were corrected.

The full optimized native suite passed: 21,260 layouts, 778 families and 4,252 styles. Native multi-window checks passed. The compiled app passed first-run presentation, Library/Spaces/Letterform destinations, replay through Help and About, return to an already detached Letterform Editor, sidebar shortcuts, and completion persistence across quit/relaunch. About and Shortcuts continue to work in Settings. All 29 saved-data hashes and two research hashes matched after QA.

Final 0.59.16 validation integrates the released 0.59.14 Spaces fixes and 0.59.15 Letterform changes. The earlier duplicate 0.59.15 onboarding installer was explicitly cancelled before installation to preserve the other release. Canonical installation and public distribution of the combined 0.59.16 candidate are in progress.

Private starting diff, data/research hashes, preview and timing evidence: `.context/qa-artifacts/onboarding-refinement/` in the original working copy. Missing-letter research remains paused.
