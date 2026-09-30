# Changelog

## 0.59.1 — 2026-09-30

- Tighten Library cards for short previews, keep style counts readable, center empty-state guidance, and clarify compact search and icon-only controls.
- Improve Spaces at narrow window widths with clearer selection outlines, a responsive toolbar, a contrast-aware work area, and breathing room around canvases in Fit width.
- Make Letterform Editor usable at the 980-point window minimum: compact the empty word proof, arrange drawing and selection controls in two rows without horizontal scrolling, keep Clear and Simplify visible, and place metrics in an expandable panel. Strengthen selected glyph and artwork-import outlines for increased contrast.

## 0.59.0 — 2026-09-29

- Refine Library selection and filtering: saved searches restore their preview text, the metadata table respects style and tag filters, batch actions show the families and styles affected, and Replace selection with visible makes its scope explicit. Empty collections and unavailable recent imports have distinct next steps; clearing filters keeps the current Library section.
- Make collection actions visible in the sidebar and header, confirm deletion with its family count, and show persistent success feedback for collection changes and exports. Backup import now previews what will be merged before confirmation. Library tools use a task menu with sizes suited to each task; Google Fonts downloads show license/source progress and retry guidance, and Font Health explains when original-file repair is unavailable.
- Clarify Spaces editing and handoff: show whether typography changes affect a role or one imported layer, make Space deletion undoable, expose the 50-checkpoint retention limit, and show scope, missing fonts, omitted artwork and format limits before exports. Imports report their canvas, text-layer, font and warning counts.
- Improve Letterform Editor navigation and proofing with drawn/empty character filters, character jump, a resizable word-proof strip and Edit-menu Undo/Redo for the current glyph. Export review identifies the exact SVG or TrueType scope and skipped glyphs; SVG import explains that its artwork is traced into new editable outlines.
- Missing-letter suggestions remain hidden as of 0.58.1. Their local code and research evidence remain available for future work; no suggestion-quality target is claimed by this release.

## 0.58.1 — 2026-09-29

- Pause missing-letter generation in the app: remove its Characters action, practice-gallery output, metrics-guide prompt and generated-glyph badges. Existing saved outlines remain editable and exportable.
- Keep the local suggestion engine, regression checks and private research artifacts for a future quality campaign. Practice examples now open only their original imported artwork.

## 0.58.0 — 2026-09-28

- Estimate proportional suggestion widths from H/O/n/o/p with a small local width prior trained on open-licensed font measurements. Keep compact procedural curves, source padding, monospaced spacing and safe fallback behavior. No model download or artwork upload is needed.
- Improve the nine-face development mean from 52.9% to 53.6%, the additional set from 47.3% to 48.3%, and a ten-face prospective check from 48.5% to 50.4%. Some individual styles regress; handwriting and script remain weak. These are silhouette-overlap scores, not confidence, and the 85% target remains unmet.
- Add reproducible numeric-only width training tools, a third audit set and a width-prior ablation option.

## 0.57.0 — 2026-09-28

- Reuse supplied H stems for eligible K/M/N suggestions, adding compact editable diagonals without stretching the copied stems. K follows H's ink width instead of inheriting a wider O; monospaced M retains its previous construction.
- Raised the original nine-style development mean from 52.3% to 52.9% (53.0% at the finer grid), and the additional nine-style mean from 46.7% to 47.3%. Handwriting and script remain unresolved; the requested 85% target has not been reached.
- Kept unsuccessful bowl-reuse, learned-vector and locally trained raster experiments out of production. Added regression checks for diagonal provenance, physical stem placement, compact contours, monospaced spacing and export.

## 0.56.0 — 2026-09-27

- Reuse eligible H stems and terminals for D/E/F/I/L, preserving physical stroke weight and source ink placement. D combines the H stem with the supplied O curve; rounded/irregular stems and monospaced I retain the previous construction. Suggestions remain experimental.
- Improved the unchanged nine-face development mean from 51.5% to 52.3% overlap (52.4% at the finer grid). Nine additional faces improve from 45.0% to 46.7%; script and handwriting still need substantial work. These are silhouette comparisons, not confidence estimates.
- Added finer-grid, additional-font and source-stem ablation audits, explicit incomplete-font reporting, and aggregate/worst-style/85%-threshold coverage. Kept font-retrieval research separate from the app; no borrowed font outlines or model dependencies are added to production.

## 0.55.0 — 2026-09-27

- Fixed Objects-mode alignment collapsing outlines. Alignment and distribution now move complete objects with their handles and counters; a single object cannot be aligned to itself.
- Kept counters open in narrow, heavy bubble A suggestions and merged overlapping construction strokes into closed outlines. Suggestions remain experimental and require review.
- Made eligible 30,000-anchor imports recoverable through Simplify outline, with bounded polygon reduction, cancellable fitting, and checks against the full original silhouette and contour topology.
- Removed repeated paragraph scans and excessive template-copy repetition from long Spaces articles, and reused bounded layout plans across the canvas and inspector.
- Kept canvas headings on one line at small Fit scales, with full names available in hover text, accessibility and canvas tabs.
- Bounded Library card previews to three lines and added Expand preview for the full text, preserving stored preview content.

## 0.54.0 — 2026-09-27

- Added contour splitting, endpoint joining, exact segment midpoints, and horizontal/vertical node distribution to the Letterform Editor.
- Preserved bounded undo/redo histories while switching glyphs, included side-bearing edits, and removed the unsafe fallback that deleted saved strokes when no undo history existed.
- Improved source-bowl reuse for G/Q, i/j proportions, and validation of temporary construction geometry. The unchanged five-face/nine-face means rise to 56.1%/51.5%. Suggestions remain experimental, run off the UI thread, and require explicit selection before applying.
- Added common-target 5/8/12-reference measurements and an optional HTML overlay report. More references alone produce little gain; the current procedural approach is not ready for automatic font completion.

## 0.53.0 — 2026-09-27

- Fixed clustered pixel corners in traced outlines. Straight spans use endpoints instead of unnecessary cubic handles; rounded corners remain curves. **Simplify outline…** defaults to the editable preview, and dense existing glyphs show their point count with a direct simplification action. Applying remains undoable.
- Fixed dark seams in glyph previews by compositing translucent ink once across overlapping strokes.
- Fixed SVG reimport rejecting the metadata written by Typefield’s own glyph exporter.
- Added an in-app **Try handwriting & bubble examples…** gallery with slanted handwriting, irregular bubble counters, and a rounded A. Source imports and suggestions are visible before opening a separate editable practice project.
- Starter construction calibrates stroke-weight fitting against supplied control letters, uses letter-specific proportions and optical spacing, and distinguishes plain stems. Source-derived e reuses o curves; reflected bowls and stems compensate for the measured slant, and h extensions attach to the drawn n stem. All suggestions remain provisional and require review. The original five-face holdout improves from 48.0% to 54.7% mean overlap; the nine-face mean is 50.1%, with small handwriting regressions documented in QA.

## 0.52.0 — 2026-09-26

- Replaced dense trace smoothing with compact cubic fitting that retains sharp corners and checks boundary deviation, winding, counters, crossings, and filled-ink agreement. New imports use a source-resolution-aware fit; dense existing curves can also be reduced in **Smooth trace…**, including a reviewed **Editable · 5 units** option. Unsafe fits keep the original artwork.
- Added original handwriting and bubble-letter import fixtures. Slanted handwriting dots just outside a stem’s horizontal bounds now stay attached to their letter. Regression checks cover silhouette fidelity, counters, dots, node reduction, persistence, and TrueType export.
- Starter suggestions now account for construction margins, inset stems, measured lean, and shared advances. Compatible stem/bowl partners retain the source join, and n/u reflection preserves the measured lean; dense copied outlines are fitted before reuse, and the review displays editing-anchor counts.
- Expanded the read-only holdout audit from five to nine installed faces, including handwriting, marker, and connected script. Original five-face mean overlap improved from 44.6% to 48.0%; the handwriting and bubble import fixtures use 93.9% and 98.1% fewer anchors, respectively. Scores measure sampled silhouette overlap, not prediction confidence; suggestions still require visual review.

## 0.51.0 — 2026-09-26

- Improved **Suggest missing letters…** so compatible letters reuse independent, editable copies of the user's actual contours. The assist can open an O/o for C/c, reuse bowls and add stems or tails, reflect compatible letters, and repeat a drawn n for m. It also measures source widths, side bearings, terminal shape, and descender depth for the remaining constructed letters. Added stems now follow the copied bowl's weight, while tight S curves use a lighter optical stroke; very thin traced strokes remain measurable.
- The review sheet now distinguishes reused outlines from constructed templates in its counts, rows, and detail preview. **Select → Only reused outlines** makes it easy to apply just the suggestions with source contours. Existing artwork and partial-font export remain preserved.
- Added a disposable five-letter holdout audit against installed typefaces so future changes can be compared for shape overlap, width, and complete glyph coverage without opening saved projects. These measurements guide development; suggested letters still need visual and spacing review.

## 0.50.0 — 2026-09-25

- Added **Suggest missing letters…** to Letterform Editor. The local assist proposes editable uppercase and lowercase Latin starter outlines from a partial set of drawn letters, adapts compatible source curves where possible, and uses measured provisional constructions for the rest. A review sheet shows each proposed letter, its source and method before any artwork is saved.
- Suggestions fill only empty glyphs in the active master. Existing user drawings stay intact; the accepted batch can be undone while its project snapshot is current. Partial fonts continue to export without suggestions, omitting characters with no artwork.

## 0.49.0 — 2026-09-25

- Added independent left, right, top and bottom edge resizing for Spaces canvases, with centered corner handles for proportional scaling and border dragging for moving. Resizing checks the resulting text layout, preserves opposite-edge anchoring, cancels unsafe changes with an explanation, and keeps PDF/Figma/Adobe canvas dimensions aligned with the artboard.
- Added Focus Selection to the Letterform Editor to zoom and center selected contours or nodes.
- Added source regression coverage for legacy canvas decoding, resize bounds and anchoring, saved custom text positions, unbreakable text, imported negative text coordinates, and PDF/Figma/Adobe dimension parity. The final native suite and Figma bridge tests pass. Focus Selection frames selected Bézier control handles along with their anchors, keeping curves that overshoot selected nodes in view without pulling in unrelated contours; the regression uses control points at (-1.5, -1.0) and (2.5, 2.0) and checks 31-point viewport margins. `./install-local.sh` completed with exit 0 for canonical `/Applications/Typefield.app` 0.49.0 (69); strict signature verification passes and installed/dist executable SHA-256 matches (`baa567697045f468277ff05d79cff88126acd709cdb5949a4bac887b4418d2c0`). The pre-copy native test passed 21,260 layouts, 778 families / 4,252 styles; installed-app self-test passed 2,640 layouts, 180 families / 528 styles, and all listed suites passed. Final targeted UI QA used only the disposable `QA Backup Fixture` and separate `Font experiment 1`. In Spaces, right-edge resize changed 927 × 1,335 → 884 × 1,335 (width only); proportional corner resize changed 884 × 1,335 → 865 × 1,307; top-edge resize changed 865 × 1,307 → 865 × 1,280 (height only); bottom resizing clamped at the text-fit limit of 865 × 1,277; left-edge resize changed 865 × 1,277 → 825 × 1,277 (width only). Moving the outline kept size at 825 × 1,277, all sample text stayed in bounds, and interactions remained responsive without a crash. Letterform Editor contour Focus Selection framed a temporary four-node contour at 161% zoom from 100%. In Nodes mode, focusing the selected bottom-right node (accessibility X=521, Y=0) also reached 161% and kept the node inside the framed contour. Undo/Redo removed and restored the contour, and quitting/relaunching preserved the contour and 825 × 1,277 canvas; the “Stay curious.” footer and newsletter caption remained inside after relaunch. This was targeted interaction QA, not a check of every app interaction. See the current status entry for provenance and release validation state.

## 0.48.2 — 2026-09-25

- Fixed temporary font deactivation when CoreText reports a process registration while the same file also has a session registration. Deactivation now attempts the owned session-scope cleanup directly and keeps its activation record if CoreText cannot confirm cleanup.
- Activation now checks that the process registration was removed before registering the file for the session. Failed activation-history writes retain cleanup ownership if CoreText cannot confirm rollback.

## 0.48.1 — 2026-09-25

- Improved Spaces checkpoint save feedback and corrected imported Type system PDF behavior.
- Fixed Library Shortlist and Inspector rollback after failed saves.
- Fixed Letterform Editor master-weight font export and project rollback after failed saves.

## 0.48.0 — 2026-09-23

- Added file picker and Finder drag-and-drop for SVG, PNG and other common image artwork on individual Spaces canvases. Artwork is embedded in saved typeboards and appears in canvas previews and PDFs. Editable Figma and Adobe handoffs explain when they omit image artwork.
- Paused local-build watches that include Desktop, Documents or Downloads at launch, so Typefield no longer probes those protected folders automatically. A protected watch also stops polling after an access error instead of repeating macOS permission prompts. Live Folders keeps the saved locations and offers an explicit Resume watching action.

## 0.47.1 — 2026-09-23

- Gave the Appearance accents Indian-inspired color directions: Turmeric, Indigo, Neem, Jamun and Rose. The chooser shows richer pigment swatches while light and dark control shades keep selection text readable on neutral surfaces. Existing saved choices retain their IDs.
- Made the workspace header and About preview update immediately when the Dock icon design or its Light/Dark setting changes in Settings.

## 0.47.0 — 2026-09-23

- Added a durable backup-import journal and next-launch recovery for interrupted changes to Library, Spaces, advanced settings and Letterform Editor projects. Editing stays blocked if recovery cannot verify or finish the saved copies.
- Added stroke color and width for selected imported shapes, with persistence, canvas and PDF rendering, and supported Figma/Adobe bridge round trips. InDesign preserves separate fill and stroke opacity; Illustrator reports when its object-opacity limit needs review.
- Corrected watched-folder access in local builds, distinguished unavailable folders from expired permission, and made Choose Folder Again replace the old saved location while retaining its activation choice.

## 0.46.1 — 2026-09-23

- Fixed the Appearance pane remaining light after choosing System while macOS is dark. Settings and the main window now inherit the same live AppKit appearance.

## 0.46.0 — 2026-09-23

- Let Spaces canvases be arranged freely by dragging their borders, with selection outlines aligned to the actual canvas edge.
- Added proportional corner resizing for the complete canvas, preserving text layout while scaling type and artwork together in previews and exports.
- Added direct hex entry beside the color wells for typography, canvas and imported shape colors, with validation before saving.

## 0.45.3 — 2026-09-23

- Audited current app copy, README, migration instructions, and integration notes for the Typefield name. Historical release records and versioned compatibility identifiers retain the former name where needed to describe or open existing data.
- New Library search suggestions use `#typefield/` while saved `#fontshelf/` and `#typeface/` searches still work. New Spaces exports, font-repair backups, remixed-project provenance, and generated font identifiers use Typefield names.
- Clarified migration prompts so Typefield is identified as the destination and the earlier FontShelf folder and preferences file remain identifiable as sources.

## 0.45.2 — 2026-09-23

- Replaced Ink Sketch's pooled shapes with Bodoni-family italic lettering and restrained ink-pressure detail, keeping the serif monogram recognizable.
- Removed stray confetti from Paper Play and aligned Type Study's guides and measurement points with the letter bounds.

## 0.45.1 — 2026-09-23

- Reworked Ink Sketch as blue-black ink on warm paper. The shared Tf letterforms now carry a visible broad-nib entry, a pooled tapered exit and dry strokes within the thick stems; the design remains legible at small Dock sizes.

## 0.45.0 — 2026-09-23

- Exposed Spaces sections, text and imported layers, plus Letterform contours and nodes, as selectable VoiceOver objects with edit, move and delete actions where appropriate. Added keyboard selection, section reorder and imported-layer nudging without a drag.
- Clarified Saved searches, search chips, preview sliders, Library navigation selection and artwork-region controls for assistive technology.
- Let Library filters wrap in compact windows and Settings navigation grow with text; Reduce Transparency now gives the Settings sidebar an opaque surface.
- Added visible keyboard focus and selection feedback to drawing canvases, and stopped animated artwork-region scrolling when Reduce Motion is on.
- Applied shared depth roles to cards, canvases and floating surfaces in light and dark appearances.
- Expanded Spaces proofing to count rendered lines and sample saved fills beneath text, with explicit warnings for later overlapping artwork and approximate contrast.

## 0.44.1 — 2026-09-23

- Brought Ink Sketch back into the shared Tf icon family, retaining the same serif letterforms and proportions with restrained calligraphic ink detail.

## 0.44.0 — 2026-09-23

- Refined Ink Sketch into a calligraphic treatment with deliberate pen strokes instead of scattered specks.
- Simplified the icon chooser to one preview per design. Clarified that the Dock icon can follow the app or stay Light or Dark independently of app and macOS appearance.

## 0.43.0 — 2026-09-23

- Tightened the standard Porcelain “Tf” icon and strengthened the f crossbar for small Dock sizes.
- Replaced five color-only icon alternatives with distinct paper-cut, type-study, ink-sketch, chalkboard, and pressed-type designs. Existing icon selections still resolve to their corresponding new styles.
- Updated the icon chooser to name and preview each design direction.

## 0.42.0 — 2026-09-23

- Kept the workspace on neutral Porcelain light and dark surfaces. Palette choices now change accents on controls, selections, and subtle hover states without tinting default font-preview backgrounds or saved typeboards.
- Redesigned the app icon with a more refined serif mark and simplified the icon chooser to compact previews.
- Replaced spaced uppercase headings with ordinary sentence-case labels in the app, new typeboard examples, and generated handoff specimens.

## 0.41.0 — 2026-09-23

- Added a persistent sidebar Settings window, available from the Typefield menu, ⌘ comma, and the Library gear button. Appearance, App Icon, Live Folders, Library, searchable Keyboard Shortcuts, Privacy & Permissions, and About share one home.
- Added six workspace palettes and six independent Dock-icon palettes, with Light, Dark, and Automatic icon appearance. Choices persist across launches; Finder uses the standard bundled light icon.
- Replaced the decorative icon spike and connected monogram with conventional, separated t/f outlines rendered directly at every size. The icon chooser includes small-size previews.
- Reused live-folder and backup workflows in Settings; folder removal and activation edits now roll back in-memory changes when saving fails. Added a visible path, access warning, and Finder action for each folder.
- Kept font previews and saved canvas colors independent of workspace palettes. Added palette/icon preferences to Store preference migration.

## 0.40.0 — 2026-09-23

- Audited current documentation and historical QA against the app, with a separate production-readiness list of confirmed release risks, external validation, and larger product gaps.
- Made backup export reject unreadable saved sources and made ordinary multi-file backup-import failures restore previous files and live state. Imported nested canvas/checkpoint IDs are regenerated.
- Restored prior Library and Spaces state when supported edits cannot be saved; covered the failure paths with disposable fixtures. Google Fonts updates now stage and validate the complete licensed folder before replacing the prior managed copy.
- Added direct fill, opacity, and corner-radius controls for selected imported shapes in Spaces. Corrected the visible Typefield name in developer handoff output while retaining compatible interchange markers.
- Hardened local interchange imports with bounded reads and stricter Figma payload validation. Added untrusted-input checks and expanded ignores for local credential files.
- Added newer Swift sources to the Xcode target so its archive compiles the same app as the script build. Updated release documentation and security applicability for this local-only app.

## 0.39.0 — 2026-09-22

- Moved the labeled Spaces inspector layout control beside the canvas selector so it remains visible in every docked layout.
- Added keyboard navigation for workspaces, canvases, inspector layouts and tabs, canvas focus, and Letterform Editor glyphs, modes, and drawing tools. Added a searchable shortcut reference in Help.
- Made the onboarding tour available from Help and About. Grouped context-specific menu actions, replaced the inert checked Window item with a Dock Inspector action, and corrected menu availability and full-screen labels.

## 0.38.0 — 2026-09-22

- Tightened Spaces font, number, and paragraph controls and reduced the typeboard header spacing.
- Added full, slim, hidden, and detachable inspector layouts. The slim rail opens the full controls on demand; the floating panel can be moved and resized while the canvas keeps its width.
- Added a canvas focus view that hides the Spaces chrome and sidebar, then restores the prior layout on exit. Docked inspector choices persist between launches.

## 0.37.1 — 2026-09-22

- Reorganized the Spaces typography inspector so font, size and leading remain easy to reach while detailed controls are grouped into compact sections. Simplified the canvas and role header and reduced the visual weight of secondary settings without removing their functions.

## 0.37.0 — 2026-09-22

- Rebranded the app, icon, project, bundle, menus and three-workspace header as Typefield. Kept existing library/project storage and versioned Figma/Adobe interchange identifiers compatible.
- Added a four-step, skippable first-run tour of Library, Spaces and Letterform Editor, plus a Help-menu replay and an About sheet with privacy and font/artwork rights guidance.
- Updated Figma plugin presentation, exported filenames, developer handoff labels and generated SwiftUI/Compose names. The local development bundle imports unset preferences from the former bundle identifier when available.
- Renamed the build/archive scripts, CI target and documentation for Typefield.
- Replaced the cramped three-way sidebar segment with full workspace labels and refreshed the sidebar mark to match the new icon. The Typefield window now starts with its own centered placement preference.
- Finished the Letterform Editor section heading and remaining Spaces error copy with the Typefield names.

## 0.36.0 — 2026-09-22

- Renamed the third workspace label to Letterform Editor while retaining the project format and internal storage keys. Documented a whole-app rebrand plan for review before public distribution.
- Added saved Library searches that restore compound filters and update results against the current catalog.
- Persisted preview ink per Letterform Editor project without changing monochrome font export.
- Added a Spaces proofing readout for saved ink/canvas contrast and entered line length, with an imported-layout approximation note.


## 0.35.0 — 2026-09-22

- Added a guided Store-container migration for Library, Spaces, Font Lab and app-managed Google Fonts, with validation, source preservation, collision protection and reauthorization guidance for external folders.
- Added optional import of local-build preferences into unset Store preferences.
- Added Store archive configuration checks and verification of its signature, bundle identity, entitlements, privacy manifest and version. Organizer distribution signing and App Store Connect validation are still required.

## 0.34.1 — 2026-09-21

- Added whole-object selection, visible corner resize handles and Shift-constrained scaling in Font Lab. Objects keeps nested counters together; Nodes retains precise point editing. Added a visible Select all action.
- Added canvas preview ink color and width adjustment for existing freehand pen strokes. Export remains monochrome; vector outline weight changes remain future work.
- Renamed the Font design entry to Components & masters, with a tooltip identifying kerning groups and glyph-set controls. Smooth trace remains beside the editor switch.

## 0.34.0 — 2026-09-21

- Added Font design with live reusable glyph components, position/scale controls, source navigation and decomposition into independent editable outlines. Components resolve in previews, SVG and TrueType exports; cycles and invalid geometry are rejected.
- Added independently editable masters with preserved outlines, metrics and kerning, plus static font export for the active master. Added Unicode glyph-set expansion across masters and Undo setup.
- Added first/second-side kerning groups, group rules and glyph exceptions, including zero exceptions. Preview spacing and exported TrueType kern tables use the same precedence.
- Added automatic fitting of traced polygon contours into editable curves, with tolerance choices, larger before/after previews, counter/winding/deviation checks and Undo. Original artwork stays unchanged until applied.

## 0.33.1 — 2026-09-21

- Aligned Spaces Text, Background and Accent labels on the left and their color wells on a shared right edge.

## 0.33.0 — 2026-09-21

- Refined Spaces typography into Character, Paragraph, Bullets and numbering, and Align panels, with compact numeric entry, steppers, presets, family/style selection and one-click paragraph alignment. Type roles now collapse to keep the active controls easy to reach.
- Added editable bullet/numbered-list formatting and six canvas-frame alignment actions. Template text positions persist independently, can be reset, and feed previews and layout exports. Imported text and shape alignment uses the saved artboard bounds.
- Preserved shared role styling, explicit auto leading, Metrics/Off kerning, advanced font features and existing documents.

## 0.32.0 — 2026-09-21

- Made Font Lab vector-first, with saved cubic Bézier nodes/handles, a click/drag pen, rectangles, ellipses, smooth/corner editing, multi-node selection, exact segment splitting and keyboard nudging. Sketch tools remain available.
- Added contour closing/opening, direction reversal, Make counter, extrema insertion, overlap removal, subtraction/intersection, duplication and cross-glyph contour copy/paste. Added coordinate entry, alignment, mirroring, scaling and rotation.
- Added canvas zoom/pan, grid, metric/node snapping, fill toggle and Redo. Clicking a word-preview glyph now selects it for editing.
- Preserved original cubic curves in saved projects and SVG exports, and added adaptive curve conversion for TrueType. Open vector paths block font export rather than silently changing the outline. Legacy drawings and imported polygons remain compatible.
- Added geometry, persistence, export-identity and counter regressions. New from fonts remains shelved.

## 0.31.1 — 2026-09-21

- Shelved **New from fonts**: removed both creation buttons, generator presentation/source-selection wiring and the remix specimen CLI entry point. The generator screen is archived outside the application targets for possible future reconsideration.
- Focused Font Lab on drawing and importing your own artwork. Existing projects, source attribution, outline editing and exports are preserved.

## 0.31.0 — 2026-09-21

- Added **Import artwork** to Font Lab: trace PNG, JPEG, TIFF, HEIC and outlined SVG drawings into editable glyphs, individually or from alphabet sheets.
- Added automatic ink-region detection, local character-label suggestions, grid and single-letter modes, manual region boxes, letter-order assignment, threshold/light-ink controls and speck cleanup. Review the source regions and traced shapes before importing.
- Preserved counters and detached marks, proportional widths and shared sheet alignment. Import into a new project or an existing one; existing artwork is kept by default, replacement is explicit, and existing-project imports can be undone.
- Added bounded direct `.procreate` embedded-preview extraction with an explicit resolution notice. This does not decode Procreate layers; export PNG for full-resolution artwork.
- Added original alphabet, single-letter and dotted-letter test fixtures, plus regressions for tracing, persistence, safe replacement/Undo, archive validation and SVG/TrueType output.

## 0.30.0 — 2026-09-21

- Replaced perimeter-point morphing with aligned silhouette distance-field blending. Glyphs with incompatible counter positions, low shape overlap or damaged output topology keep a source shape fitted to the combined proportions; the preview reports exactly which glyphs use this fallback.
- Replaced Interleave’s repeated sinusoidal deformation with **Splice**, a single smooth transition from A’s lower shape to B’s upper shape. Existing saved projects remain intact.
- Fixed Alternate glyphs assigning nearly every Latin character to the same face. At 50% it now alternates A/B through the alphabet; other balances distribute B’s share evenly. Source assignments are stable between previews and full projects, visible in the preview and saved with provenance.
- Normalized source sizes using the actual Latin starter outlines, so large global descent metrics in multilingual fonts no longer shrink one source’s letters.
- Added an explicit incompatibility message for capital-only versus true-lowercase sources, and disabled creation until the current recipe has a successful preview.
- Expanded geometry regressions and disposable visual specimens to cover source distribution, counter positions, raster orientation, straight stems, width/weight contrasts and all three methods. This remains an editable starter generator; unrelated font designs cannot reliably become production-quality interpolated masters.

## 0.29.0 — 2026-09-21

- Rebuilt Font Lab combination around continuous filled contours instead of horizontal pen strips. Adaptive curve sampling, spatial contour matching and counter-aware fallback produce smoother edges, more stable stems and intact bowls. Incompatible glyph structures retain the dominant source and are identified in the preview.
- Preserved proportional glyph widths, source side bearings, consistent face scaling and exact source selection at 0% and 100%. Alternate glyphs now selects a whole source glyph; Interleave uses broad connected bands.
- Added a debounced live generated specimen, automatic source-based project naming that respects custom names, and visible descriptions for Clean, Soft, Poster and Kinetic. Clean is the neutral default; Soft rounds corners, Poster adds weight and width, and Kinetic adds forward slant.
- Added Reshape with draggable outline points and shared canvas/toolbar Undo. Continuous outlines and counters persist through saved projects, SVG and validated TrueType export; existing pen projects retain their original rendering.
- Added a visible Delete project action and sidebar context action. Deleted experiments can be restored from Deleted projects after relaunch; source fonts and exported files remain untouched.
- Added isolated regression coverage for source endpoints, whole-glyph alternation, proportional widths, counter/export fidelity, contour persistence and project deletion/restoration.

## 0.28.0 — 2026-09-21

- Added an offline Font Lab starter generator that remixes two installed faces into editable glyph strokes. Blend, Interleave and Alternate-glyph methods, an adjustable source balance and Clean/Soft/Poster/Kinetic presets provide playful starting points without copying source font binaries or presenting deterministic transforms as cloud AI.
- Persisted source-face provenance and derivative-license guidance with generated projects. Creation requires the user to confirm they have permission to modify both source fonts; remixed exports use conservative embedding permissions and carry source identifiers plus the licensing warning in the font name table.
- Added real installable TrueType export. FontShelf builds a validated OpenType font with TrueType outlines, `.notdef`, Unicode mappings, Font Lab metrics, collision-resistant install identity and round/marker/outline geometry, then checks it through Core Text before saving with the truthful `.ttf` extension.
- Added individual, selected and all-drawn SVG export. Font Lab now has an explicit multi-glyph selection mode and creates a collision-safe new export folder without overwriting—or cleaning up—unrelated files.
- Added persistent Round, Marker and Outline nib styles with matching pressure-aware drawing, preview, SVG and TrueType geometry while preserving legacy project decoding.
- Made the character rail resizable through a visible, bounded and accessible drag handle, so narrowing the list directly expands the drawing canvas; double-click resets its width.
- Standardized the Library, Spaces and Font Lab header title size, row height and padding so their title baselines remain aligned even beside the taller Library search field.
- Moved coalesced Font Lab snapshot encoding and file writes to a serial utility queue, switched large projects to compact deterministic JSON and stopped project switching or each completed stroke from synchronously rewriting the whole state on the main thread.

## 0.27.0 — 2026-09-20

- Replaced the small collapsed-sidebar restore control with a shared 52-by-64-point edge pull-tab across Library, Spaces and Font Lab, with a full rectangular hit target, a dedicated header lane, hover feedback and an accessible keyboard hint.
- Hard-clipped shared cards, glass sidebars and Font Lab's native drawing, metric-example and preview surfaces to their continuous rounded shapes so rectangular backgrounds no longer show beyond rounded borders.
- Expanded Font Lab's drawing toolbar with Pen and whole-stroke Eraser tools, adjustable pen/eraser size, Off/Gentle/Strong smoothing, pressure-sensitive round strokes and clear input status/help. Apple Pencil input arrives through macOS Sidecar and other tablets through their normal macOS drivers; FontShelf does not pair USB or Bluetooth hardware itself. Reported tilt is retained with each sample, but it does not yet rotate the round nib.
- Labeled baseline, x-height, cap height and both side bearings directly on the drawing guides, and added a live H/x metric example plus a beginner guide explaining what each measurement controls.
- Kept each in-progress stroke inside the native drawing view, publishing and saving it once at gesture completion instead of copying the full Font Lab project for every sampled point. Project-name, preview and metric edits now use coalesced saves.
- Added reusable catalog face/family/name indexes, single-pass Library sidebar count snapshots and lean first-pass pairing/similarity ranking so routine redraws and recommendations avoid repeated full-catalog work. Final release measurements are recorded after the verification run.

## 0.26.0 — 2026-09-20

- Added an explicit seven-role setup step whenever selected Library fonts, Favorites, a collection, Shortlist or a recommendation seeds a typeboard. FontShelf supplies a resettable first pass, while the user chooses the initial Display, Heading, Subheading, Body, UI, Caption and Monospace faces; every role remains freely editable afterward.
- Added local, explainable font-pairing suggestions inside Spaces. Safe, Balanced and Expressive modes rank compatible installed families for a chosen target role, preview both faces together, show the signals behind each result and apply the choice without replacing the source role.
- Added Illustrator and InDesign type-system builders beside PDF export. The generated JSX creates a new editable native `.ai` or `.indd` document with canvases/pages, live text, simple shapes, named styles and retained FontShelf metadata; fonts are referenced rather than bundled.
- Added the reverse Adobe bridge: export a document or selection from Illustrator/InDesign to bounded JSON, then import it as an editable FontShelf typeboard with source-aware units, transparent no-fill handling and per-layer fidelity warnings. Native proprietary files are not decoded directly and mixed styles, complex effects, variable axes and some OpenType settings still require review.
- Added Font Lab as a third top-level workspace. Its first foundation includes explicit project creation, per-glyph mouse/trackpad drawing, baseline/x-height/cap-height and side-bearing controls, drawn-glyph word previews, atomic local persistence, daily and portable backup coverage, confirmed clearing and real per-glyph SVG export.
- Marked Font Lab's SVG/PNG/Procreate tracing, multi-font blending and installable OTF generation honestly as planned or research work rather than presenting placeholder output as a finished font.
- Added deterministic checks for role seeding/editability, pairing scoring, Adobe script parsing and JSON round trips, Font Lab persistence/corrupt-data preservation/SVG output and backward-compatible Library backup merging, plus the new sources in the Xcode target.

## 0.25.0 — 2026-09-20

- Added a direct **Create typeboard** action to Shortlist, with checkboxes for choosing any subset and preservation of each selected font style.
- Made the Library header's typeboard action use selected families when present, so multi-selecting fonts in Favorites, a collection or any filtered Library view creates a populated typeboard immediately.
- Expanded initial role assignment from two-font pairing to up to six selected fonts across display, heading, subheading, body, UI/caption and monospace roles; every selected font remains available as a typeboard candidate.
- Added regression coverage for predictable two-font pairing and complete multi-font role seeding.

## 0.24.0 — 2026-09-20

- Unified the Library and Spaces sidebar header so the FontShelf mark and workspace switcher remain in exactly the same position when changing workspaces.
- Added a persistent collapsible workspace sidebar, a compact left-edge restore control and **View → Hide/Show Sidebar** (Control-Command-S), returning the complete 256-point sidebar footprint to the active workspace.
- Clarified the Font kerning control and made it the single canonical control for the OpenType `kern` feature, avoiding a contradictory duplicate feature selector while preserving legacy saved settings across rendering, web audits and exports.
- Added regression checks for expanded-by-default behavior, persisted collapse/expand state and exact reclaimed workspace width.

## 0.23.0 — 2026-09-20

- Added direct canvas text editing on double-click, with Command-Return to save and Escape to cancel; hardened empty, oversized and focus-changing edits so they cannot crash the canvas or overwrite a newer selection.
- Added a selected-canvas web-font cost audit with exact WOFF2 file weights, known download totals, character/script coverage provenance, compatible variable-versus-static comparisons, fallback x-height/wrapping/control-width probes and removable-style estimates.
- Made missing and ambiguous web assets explicit and excluded them from exact byte totals instead of substituting unrelated desktop data; serialized and debounced analysis so stale work cannot replace the current selection.
- Added local-only **Find similar** recommendations with explainable visual/metadata signals and **Rediscover** suggestions biased toward fonts that have not been used recently.
- Stopped watched folders with missing or revoked security-scoped bookmarks from repeatedly probing protected locations, eliminated the resulting macOS permission-prompt loop, and deduplicated reauthorization notices per launch.
- Aligned each comparison header's **Only this** and close controls with its canvas edge across all Spaces canvas formats.
- Made the active Library **A/B** reference button a true toggle: clicking it again ends the overlay comparison.
- Made canvas clicks target the exact heading, caption or display text under the pointer, with a tight selection/editor outline instead of selecting the full section.
- Removed the watcher's redundant startup refresh while preserving live add, replacement and deletion detection.
- Extended validation for canvas editing limits, local intelligence, web-cost calculations, protected-folder recovery and responsive canvas layouts.

## 0.22.0 — 2026-09-20

- Removed an unnecessary second installed-font catalog scan from ordinary cold launches and skipped the post-registration rescan when watched folders made no catalog changes.
- Reused variable-font facts already collected during catalog reads and original-family classifications during regrouping instead of reopening every style.
- Added bounded caches for immutable Core Text fonts and rendered canvas plans, with invalidation whenever the font catalog changes and size limits for unusually large imported layouts.
- Reduced repeated full-library filtering and chosen-face resolution during SwiftUI redraws, and cached Core Text line layout between sizing and drawing passes.
- Avoided rebuilding canvas accessibility summaries on every selection or zoom update and bounded the summary size for very large imported layouts.
- Added a read-only `--performance-audit` covering catalog scan, library filtering and cold-versus-cached canvas planning.

## 0.21.0 — 2026-09-20

- Added per-typeboard canvas selection to typography summaries, with every canvas selected initially and a checkbox row for choosing any subset.
- Combined the selected canvases in plain-text, Markdown and clipboard summary output while preserving each canvas's name and format.
- Added multi-page type-system PDF export, with one generated specimen page per selected canvas using that canvas's fonts, axes, OpenType features, colors and typography scale.
- Added regression coverage for multi-canvas summary scope, generated specimen settings and PDF page count.
- Standardized local releases on `/Applications/FontShelf.app` through `install-local.sh` so verified builds update one stable app instead of producing numbered copies.
- Completed and regression-tested the focused fixes from the September 19–20 Luna QA pass.

## 0.20.0 — 2026-09-19

- Added Font Health to Library tools plus per-family **Inspect font file…** access and a File-menu entry.
- Added local checks for SFNT headers/directories, required tables, table bounds and overlap, checksums, name-table storage, empty/exact-duplicate/conflicting records, required IDs and PostScript-name validity.
- Added clearly separated compatibility notes for legacy RIBBI subfamilies and version formatting, so valid modern fonts are not labeled broken.
- Added individually selectable conservative fixes, full SFNT rebuilding, checksum adjustment, Core Text validation, repaired-copy export, and confirmed in-place repair with a side-by-side backup for writable user files.
- Kept system fonts, multi-font TTC/OTC containers, unsupported formats and ambiguous identity repair read-only; repairs never synthesize or guess missing identity records.
- Added deterministic regression coverage for a legacy malformed name table, proposal selection, repaired naming, duplicate removal and whole-font checksum validity.

## 0.19.0 — 2026-09-19

- Replaced implicit canvas comparison state with an explicit visible-canvas set. Selecting canvases builds a stable comparison; per-canvas Hide, Only this, Show all and the checkmarked Shown menu make returning to a single canvas immediate.
- Added a Fonts used summary for the active canvas with font-only, role mapping and full typography levels, plus clipboard, plain-text and Markdown handoff.
- Added collection creation from the fonts used on one canvas, across a typeboard, or throughout a project. Used styles deduplicate to Library font families and never overwrite an existing collection.
- Linked type-role selection to its first visible canvas use and made roles draggable onto the active canvas with their saved sample text and typography settings.
- Redesigned website, product UI, editorial and poster canvases as distinct, purpose-specific compositions while retaining rearrangeable sections and responsive widths.
- Added regression coverage for canvas visibility continuity, role-drop placement and payload validation, typography summary exports and template distinctness.

## 0.18.0 — 2026-09-16

- Added one-click developer handoff packages with CSS, fluid scales, preload guidance, Tailwind configuration, design-token JSON, SwiftUI, Android Compose and printable HTML output.
- Made space, typeboard and collection names directly editable by clicking their text, with keyboard save/cancel and duplicate-name protection.

## 0.17.0 — 2026-09-16

- Simplified vocabulary to Spaces → Typeboards → Canvases, with visible canvas tabs, a Show all canvases toggle and clearer New typeboard/Add canvas commands. Legacy generated labels display as Canvas 1, Canvas 2, etc. without rewriting saved names.
- Exposed recursive live folder watching during folder selection and opened its controls after adding a folder; added a permanent Library sidebar shortcut.
- Allowed adding folders during an existing library scan, queuing the first scan with an explicit status instead of disabling the picker.
- Kept every typeboard trash button visible and clickable without selecting or hovering.
- Added bounded trackpad-pinch and Command-scroll zoom over the canvas viewport, preserving normal scroll-to-pan behavior.
- Added collections, favorites, category overrides and tag queries to the typeboard font chooser.
- Fixed canvas text hit-testing to select the exact role/text, including fixed template labels, with per-element text edits that save and undo independently of shared typography.
- Added native .fig workflow guidance. Direct binary .fig import is still not supported; the tested Figma JSON bridge remains available.

## 0.16.0 — 2026-09-16

- Added selected-frame Figma import as editable, saved typeboards: independent text styling, solid shapes, original coordinates and canvas dragging, with explicit fidelity warnings. Uses the bundled JSON bridge, not native `.fig` decoding.
- Fixed clipped space titles and crowded icon menus throughout Library and Spaces; grouped comparison actions and surfaced Export directly.
- Added direct sidebar typeboard deletion with confirmation and Undo, plus descriptive Undo/Redo for design edits.
- Replaced unreliable drag sessions with native tracking for canvas and arrangement reordering, including insertion feedback.
- Remembered inspector width, top-aligned canvases and made the larger font chooser opaque and searchable immediately.
- Fixed the Figma development plugin's missing-ID metadata failure and text auto-height handling. Validated outbound editable frames and the reverse import in the live Figma desktop app.

## 0.15.0 — 2026-09-16

- Separated Library and Spaces into peer workspaces. Every space and typeboard is directly available in the Spaces sidebar; New pairing lives in the toolbar.
- Added resizable typography/canvas panels, fit-to-width previews, compact role controls and a larger searchable font chooser with actual font previews.
- Added numeric size, line height and spacing controls; alignment, font kerning, word/paragraph spacing, indents, case and decorations. Existing saved typography remains readable.
- Added draggable sections in template and custom canvases, arrangement-list drag ordering, removal/restoration and additional text blocks.
- Added quick A/B switching for directions with matching canvas type and width, alongside side-by-side comparison.
- Added #tag / #!tag search suggestions, removable chips and property filters for activation, source, weight, width, slant, x-height, variable/color/bitmap/monospaced fonts, scripts and OpenType support. Typeface-style built-in prefixes are accepted as aliases.
- Added editable Figma export packages with a network-free local importer. Text-rendering differences and unsupported typography settings are explicitly reported; no font files are bundled.
- Made installed fonts available before watched-folder scanning completes, so a slow folder does not leave the library or font picker empty.

## 0.14.0 — 2026-09-16

- Added Spaces, pairing typeboards, independently saved directions, checkpoints and side-by-side comparisons.
- Added responsive website, product UI, editorial, poster, type-system and custom ordered-block previews, with seven editable typography roles, PDF export and portable space import/export.
- Added searchable Unicode and unencoded glyph browsing, metrics and outline views, SVG export/drag, waterfall previews and paginated specimen PDFs.
- Added nested tags and AND/OR/NOT tag filtering, a metadata table and individually confirmed exact-duplicate removal to Trash.
- Added recursive folder watching and opt-in session activation from original files, including replacement/removal reconciliation.
- Added daily local backups, merge-based restore and corrupt-workspace preservation.
- Added regression coverage for workspaces, checkpoints, tags, folder snapshots, glyphs, responsive canvases, PDF pagination and backup merge; separate live folder/activation checks.
- Fixed two development test-runner crashes: headless PDFKit initialization and an incorrectly shared backup-test directory. PDF checks now use Core Graphics and new test failures exit with an error message.

## 0.13.1 — 2026-09-15

- Replaced the generic Serif and Sans Serif category symbols with compact letterform icons rendered in their corresponding type styles.

## 0.13.0 — 2026-09-15

- Actual Google Fonts previews before downloading, with editable sample text and size.
- Memory-only remote font rendering, a bounded cache, limited parallel loads, and retry controls.
- Updated in-app disclosure for preview network requests.

## 0.12.3 — 2026-09-15

- Corrected View menu layout checkmarks and shortlist membership after family regrouping.
- Required a saved license before persisting Google font files.
- Reported duplicate-scan subfolder errors and displayed export feedback inside the inspector.
- Expanded regression checks to include multilingual and unusual text layout.

## 0.12.2 — 2026-09-15

- Replaced font-dependent text-field spacing with explicit Core Text baselines shared across grid rows and overlay layers.

## 0.12.0–0.12.1 — 2026-09-15

- Adaptive preview widths, equal-height cards within rows, and larger controls.
- All family styles visible together; per-family and library-wide overlay comparisons.
- Visible shortlist entry in the sidebar.

## Earlier development

Installed/imported font browsing, script/category filters, collections, tags, last import, variable tuning, OpenType inspection, body layouts, duplicate detection, export, temporary activation, Adobe script export, native menus, and theme/glass refinements.
