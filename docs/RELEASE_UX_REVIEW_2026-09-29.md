# Release UX review — 2026-09-29

Scope: Typefield 0.59.0 (build 80) across Library, Spaces and Letterform Editor. This review combines source inspection with earlier interaction matrices and the [0.59 local QA record](QA_2026-09-29_0.59.md). The changes below are implemented and installed locally; the public-release checks listed later remain open. Use disposable fonts and projects for the remaining hands-on checks.

## Recommendation

Keep the three-workspace product scope and prepare a release after the candidate checks. The current app covers the central path in each workspace: find and organize fonts, compare them in context, and draw or import editable letters for partial font export. I found no missing fourth workspace or large feature that must be added for this release. The primary risks are unclear action scope, format fidelity expectations, permission behavior, and incomplete current-version validation.

Missing-letter generation remains paused and hidden. Saved suggested outlines remain ordinary editable project artwork; the local implementation and research evidence remain available. No 80–85% native-vector quality claim belongs in the product or listing.

## Implemented in the 0.59.0 source candidate

| Area | Change | Why it helps |
| --- | --- | --- |
| Library search and filtering | Saved searches restore their preview text alongside coverage filters; cards and the metadata table use the same style-level match; the footer counts matching styles. **Clear filters** retains the selected section. | Results are easier to trust and an empty collection no longer looks like a failed search. |
| Library selection | Batch actions show selected families, styles affected and selections outside the current view. **Select visible** replaces the selection with the displayed families. | Export, tagging and typeboard creation reveal their true scope before acting. |
| Library organization | Collection actions are visible in the sidebar and collection header. Deletion names the collection and member count, requires confirmation and explains that font files stay in place. Saved changes and exports have persistent, dismissible results. | Reduces hidden context-menu reliance and uncertainty after an action. |
| Library tools and file safety | Tools are grouped by task and sized for their content. Backup import previews collection/favorite/project counts before merge. Google Fonts shows source/license progress and a retry path; Font Health explains original-repair ineligibility and rechecks the source before replacing it. Inspector Notes save after editing and restore the previous value on failure. | Makes consequential file operations and failure states more legible. |
| Spaces edit scope | The inspector identifies a shared native type role or a single imported text layer and describes which properties affect each. Role and layer controls have clearer counts and labels. | Helps users predict what will change before editing. |
| Spaces import/export | A preflight names the selected scope, unavailable fonts, omitted image layers and format limitations. Imports summarize typeboards, canvases, text layers, missing fonts and warnings; warnings remain available on the imported canvas. Export menus name their scope. | Makes a Figma, Adobe, PDF or developer handoff easier to choose and inspect. |
| Spaces recovery | Deleting a Space names its typeboard count and registers Undo/Redo for the current session; restoring it saves the Space again. Checkpoint UI shows the 50-snapshot retention limit. Zoom is labeled **Fit width**. | Prevents silent loss and makes persistence limits explicit. |
| Letterform Editor navigation | The character rail filters **All / Drawn / Empty**, supports character jump, and keeps the active character visible if a filter hides it. A resizable/collapsible word-proof strip gives more room to draw. The Edit menu reflects the active glyph's Undo/Redo history. | Speeds work on partial alphabets and keeps editing and proofing close together. |
| Letterform Editor import/export | A review explains the scope of single/batch SVG or TrueType export and reports empty or unsupported characters omitted from TrueType. SVG import states that it renders and traces new editable outlines instead of preserving original control points, groups and transforms. | Sets correct expectations about the artifact users receive. |
| First run and accessibility | The final tour step offers direct entry to Library, Spaces or Letterform Editor. Library card actions gain family-specific accessible names and state. | Lowers the first-action barrier and clarifies icon-only controls to assistive technology. |

Source entry points: [Library](../Sources/main.swift), [Library tools](../Sources/LibraryTools.swift), [backup and metadata](../Sources/LibraryExtras.swift), [family inspector](../Sources/FontInspector.swift), [Spaces views](../Sources/StudioView.swift), [Spaces models](../Sources/StudioModels.swift), [Letterform Editor](../Sources/FontLab.swift), [artwork import](../Sources/FontLabArtworkImportView.swift), and [TrueType export](../Sources/FontLabTrueTypeExport.swift).

## Current release validation, in priority order

These are gates for a public release, not requests for another feature campaign. The local build and saved-state checks in item 1 are complete; see the [0.59 QA record](QA_2026-09-29_0.59.md) for results and limits.

1. **Build and state safety.** Run the native suite, Figma bridge suite and release build; inspect the exact diff; install one canonical app; verify both version plists, signature and installed/tested binary identity. Compare saved Library, Spaces and Letterform Editor data before and after a read-only run. Do not touch the user's originals for destructive checks.
2. **Current-version interaction pass.** In a disposable account or fixture, run a realistic path through all three workspaces: search/filter/shortlist, collection and backup review, typeboard edit/Undo/handoff, artwork import, glyph edit/proof/export. Test cancellation and failed-save feedback. Check 980-point minimum width, taller/shorter windows, light/dark appearance, keyboard focus and VoiceOver labels. Earlier [Library](QA_LIBRARY_MATRIX.md), [Spaces](QA_STUDIO_MATRIX.md) and [Tools](QA_TOOLS_MATRIX.md) matrices are reference evidence, not a substitute for this candidate.
3. **File permissions and signed sandbox.** Test revoked or relocated watched folders, offline volumes, permission renewal, temporary activation and original-font repair with a disposable font under the final entitlement set. Exercise an actual backup restore/recovery on a clean install.
4. **Export fidelity outside Typefield.** Open the generated TrueType font in other apps. Run Figma and Adobe packages in their host applications and check text reflow, missing fonts, image omission, variable axes and OpenType settings. Local bridge fixtures do not prove host behavior.
5. **Distribution and public details.** Validate the declared macOS 13 minimum and an upgrade on a second Mac; complete team signing, production bundle ID, TestFlight/App Store validation, support/privacy URLs, current screenshots and final listing copy. The local candidate is not App Store approval evidence.

Record remaining outcomes in the 0.59 QA note. Do not mark an untested host-app, signed-sandbox or accessibility path complete from source inspection alone.

## Further polish after the release decision

| Priority | Proposal | Reason to defer or trigger |
| --- | --- | --- |
| Next small pass | Show which saved Library search is active and whether the user changed it after applying it; let users inspect a saved search's filters without guessing from scattered controls. | Useful organization polish, but the restored filter/preview correctness matters first. |
| Next small pass | Observe whether the Library's grid icons and nine-section family inspector cause hesitation in first-time use. If they do, simplify visible card actions and group inspector navigation without removing functions. | Tooltips and accessible names are now improved; test actual discoverability before redesigning. |
| Next small pass | Measure whether Spaces import/export preflight dialogs become repetitive in a complete handoff. If so, retain warnings and scope while shortening routine confirmations. | The candidate favors clarity; real workflow timing should decide density. |
| Larger later project | Preserve source SVG Bézier paths and transforms directly where safe, with fallback tracing only when needed. | Current tracing makes editable shapes but loses original control-point structure; this needs geometry and fidelity testing, not a label change. |
| Research later | Revisit missing-letter prediction with a separate benchmarked model or structural approach. | Current suggestions did not reach the 80–85% native-vector target and remain hidden. A hosted API key alone is not a quality plan. |

Advanced interpolation, variable-font export, cloud collaboration, live Adobe/Figma sync and document-triggered activation remain outside this release scope. Keep product and Store copy aligned with the formats and behaviors actually verified.
