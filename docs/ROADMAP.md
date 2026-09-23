# FontShelf outstanding work and competitor reference

Snapshot: **0.34.1 (45), 2026-09-21, application commit ebc0512**. This is a continuation checklist, not a promise to implement everything. No new product features were implemented for this inventory.

## How to use this list

- **P0 — next:** directly requested friction, reliability, or a prerequisite for the main workflow.
- **P1 — soon:** substantial usefulness or a major competitive gap once the basics feel reliable.
- **P2 — later:** professional depth, broader interoperability, or additional polish.
- **P3 — strategic:** large engineering/product investment; decide whether it belongs in FontShelf.
- **HOLD:** deliberately shelved; do not restart without a new product decision.
- **Partial** means a foundation ships, but the work described remains. **Missing** means the audited model/workflow does not provide it. **QA** means implementation exists but validation is incomplete. **Research** means validate feasibility or current coverage before implementing. Effort S/M/L/XL is relative, not a delivery estimate.

The inventory combines current source, current workflow documents, recorded QA limitations and proposed competitor-inspired extensions. Research rows are not confirmed bugs. Historical status entries describe earlier releases and must not override the current snapshot.

## What already exists — do not rebuild these

**Font Lab:** vector pen, cubic handles, primitives, node transforms, contour/counter and boolean operations, Objects/Nodes modes, corner resizing and Shift proportional scaling, preview ink, freehand pen width, artwork tracing and alphabet-sheet assignment, SVG and static TrueType export, project deletion/restoration. Components, independent masters, group kerning and reviewed trace smoothing all ship. Access them through **Components & masters** and **Smooth trace…**.

**Important limits:** components support translation/uniform scale; masters do not interpolate; kerning exports as legacy `kern`, not GPOS; smoothing is a reviewed operation on polygons, bounded to 6,000 points. Preview ink is not exported color. Pen width does not change filled vector outline weight. SVG import rasterizes and retraces. Procreate import reads an embedded preview, not native layers.

**Spaces:** multiple canvases, comparison/Quick A/B, typography roles, family/styles, axes/OpenType controls, direct text editing, paragraph alignment, basic editable list markers, canvas-relative frame alignment, aligned Text/Background/Accent color wells, imported editable text/simple shapes, checkpoints, PDF/type-system/developer handoff, and Figma/Adobe bridge workflows.

**Library:** catalog/search, favorites, collections, nested tag logic, shortlist, font overlays, Unicode inspection, variable/OpenType controls, local similarity/pairing/rediscovery, Google font previews/download workflow, watched folders, temporary activation, exact-duplicate detection, metadata, backups and Font Health. These are foundations to refine, not absent features.

## Recommended restart order

1. **FL-01 / FL-02:** make whole-object editing consistent; add a safe, previewed outline-weight tool.
2. **SP-01 / SP-02:** give shapes a proper appearance inspector and make selected-object versus shared-role edits explicit.
3. **FL-03 / FL-04:** preserve imported vectors and prove the artwork workflow with real Procreate/alphabet sheets.
4. **FL-05 / SP-03 / X-01:** make features discoverable and complete the critical interaction/Undo checks.
5. **FL-11 / FL-12:** improve component assembly and kerning/export reliability.
6. **LB-01 / LB-02:** finish activation/access reliability, then investigate document-triggered activation.
7. **SP-10 / SP-11:** improve text fidelity and real Adobe round-trip coverage.
8. Only then undertake interpolation, variable-font export, color-font formats or cloud collaboration.

Start each implementation task by reproducing the current behavior in a disposable fixture. Preserve real fonts/projects; follow the repository's test, version, commit, push and canonical-install workflow.

## Font Lab

| ID | Priority / state / effort | Outstanding work |
| --- | --- | --- |
| FL-01 | **P0 · Partial · M** | **Finish whole-object editing.** Consistent click/marquee selection, Shift add/remove, group/ungroup, explicit transform origin, numeric W/H and aspect lock, rotation handles, and clear handling of disconnected contours. Extend the experience to freehand artwork and linked components; current corner scaling operates on editable outline paths. Preserve counters and one-step Undo. |
| FL-02 | **P0 · Missing · L** | **Real vector weight / outline thickness.** Inset/outset filled contours with preview, optical review, counter-collapse detection and Undo; selected-object scope. Separate stroke width, expanding a stroke, and changing a glyph's weight. Current Pen width only edits freehand strokes. |
| FL-03 | **P0 · Partial · M–L** | **Lossless outlined-SVG import.** Read paths, transforms, compound contours and fill rules directly, retaining Bézier handles. Keep tracing as an explicit fallback for unsupported content. |
| FL-04 | **P0 · Partial + QA · M** | **Real artwork import quality.** Test actual Procreate-produced files and diverse alphabet sheets: stylized labels, detached accents/dots, overlapping regions, light ink, noisy scans and inconsistent baselines. Make preview-resolution limits, crop/assignment corrections and confidence clearer. Synthetic fixtures are not sufficient validation. |
| FL-05 | **P0 · Partial · S–M** | **Feature discoverability.** Contextual Components/Masters/Kerning entry points, useful empty states, disabled-control explanations, an editable starter/demo, and short workflows for imported artwork → correction → spacing → export. The renamed button is only the first improvement. |
| FL-06 | P1 · Partial · M | **Appearance controls.** Persist useful project/canvas preview choices; distinguish fill/stroke/background from exported font color. Per-object pen thickness, caps/joins and variable-width pen profiles need more work. Do not imply that changing preview ink produces a color font. |
| FL-07 | P1 · Partial · M | **Trace fitting workflow.** Optional import-stage fitting, batch processing with review, zoomable/difference previews, corner control, denser outlines, cancellation/progress and clearer failure feedback. Current fitting is per-glyph and can decline complex outlines. |
| FL-08 | P1 · Partial · M | **Drawing polish.** Persistent/custom guides, ruler units, angle snapping, alignment/distribution of whole shapes, robust join/split/scissors operations and better dense-path performance. Existing primitives/booleans are not a complete Illustrator-style drawing toolset. |
| FL-09 | P1 · Missing · M | **Background/reference layers.** Place and lock source artwork, control opacity, compare trace against source, and manage foreground/background layers without losing editability. |
| FL-10 | P1 · Partial · M | **Broader Undo/history.** Unify glyph, component, master, metrics and import edits; make history scope visible. Current glyph history resets across glyph/project changes and setup Undo depends on the saved snapshot still matching. |
| FL-11 | **P1 · Partial · L** | **Production components.** Named anchors, automatic accent attachment, mark positioning, rotation/mirroring, dependency navigation, replace source and batch composition. Existing linked references already update within a master; do not rebuild that foundation. |
| FL-12 | **P1 · Partial · L** | **Production kerning.** Visual pair editing in word context, editable group membership, pair search/filter/import/export, exception visibility, proofing strings, GPOS export and broader application testing. Current export expands to at most 10,000 legacy horizontal pairs. |
| FL-13 | P1 · Partial · M | **Spacing workflow.** Numeric font-unit bearings, linked metrics, spacing strings, multi-glyph adjustment, consistent advances and spacing proofs. Automatic spacing suggestions should be reviewable, not silently applied. |
| FL-14 | P1 · Partial · M–L | **Master management.** Rename/duplicate/delete safely, compare/overlay designs, propagate intended edits, and show compatibility problems. Current masters are independent designs with a 16-master limit. |
| FL-15 | P1 · Partial · M | **Export metadata and revision workflow.** Designer/license/version fields, family/subfamily/style linking, name validation, export presets and a clear install/update experience. Current content-derived identities intentionally create separate revisions rather than replacing a family in place. |
| FL-16 | P1 · Partial · M–L | **Glyph organization.** Names beyond a single character key, categories, Unicode/alternate assignment, search, filters, status/color labels, reusable glyph sets, batch renaming and safer repertoire changes. Adding Unicode characters already works. |
| FL-17 | P1 · Partial + QA · M | **Font QA and proofing.** Missing glyphs, contour direction, tiny segments, extrema, intersections, inconsistent metrics, clipping and overshoots; actionable per-glyph warnings and print/browser/app proof sheets. Core Text validation already exists but is not complete production-font QA. |
| FL-18 | P2 · Missing · L | **Compatible-master interpolation.** Match contour order/start points/nodes, validate topology, preview intermediate styles and define axes/instances. Independent master storage is not an interpolation engine. |
| FL-19 | P2 · Missing · XL | **Variable-font export.** Axis metadata, instances, variation tables, interpolated outlines/metrics/kerning and compatibility testing. Depends on FL-18; do not add a variable-font export button before the foundation works. |
| FL-20 | P2 · Missing · L–XL | **OpenType feature authoring.** Ligatures, alternates, small caps, stylistic sets, substitutions and positioning; feature compilation and testing. This is creation of font features, separate from Library/Spaces previewing existing features. |
| FL-21 | P2 · Missing · L–XL | **Complex-script and vertical design.** RTL kerning, mark-to-base/mark-to-mark, contextual forms, language systems, Indic shaping proofs, vertical metrics and contextual kerning. System text preview support does not provide these authoring capabilities. |
| FL-22 | P2 · Missing · L | **More export formats.** CFF/CFF2 OTF, WOFF/WOFF2 and controlled batch instances. Current installable output is OpenType with TrueType outlines in `.ttf`, not CFF `.otf`. |
| FL-23 | P2 · Missing · L | **Font-editor interchange.** UFO/designspace and native `.glyphs` exchange with clear fidelity reports; supported font-source import/edit workflows for user-owned material. This is separate from the shelved two-font generator. |
| FL-24 | P2 · Missing · L | **Hinting and raster quality.** Autohinting strategy, zones/stems and small-size proofing; manual TrueType hinting only if professional font production becomes a product goal. |
| FL-25 | P2 · Missing · XL | **Actual multicolor fonts.** Saved per-element colors/layers/palettes, then a chosen interoperable export format such as COLR/CPAL or SVG-in-OpenType. Gradients, compositing and bitmap strikes are separate scope. Preview ink is not this feature. |
| FL-26 | P2 · Partial + QA · M | **Tablet workflow.** Real Apple Pencil/Sidecar and vendor-tablet pressure tests, eraser behavior, tilt-aware nibs and calibration. Pressure capture exists; tilt is captured but not used to rotate the current nib. |
| FL-27 | P3 · Research · XL | **Native Procreate layer decoding.** Evaluate format access, resolution, compression, layer blending and maintenance cost. Current embedded-preview support is useful but not a native Procreate document editor; PNG export remains the practical high-resolution path. |
| FL-28 | P3 · Research · L–XL | **Advanced type-design automation.** Optical correction, smart corners/ink traps, advanced curve harmonization, smart/variable components, scripting/plugins and batch actions. Keep these behind foundational editing/export work. |
| FL-29 | P3 · Research · XL | **Optional generative assistance.** Only with a defined user-owned-artwork workflow, explicit consent and clear output provenance/quality checks. No decision to build a model service has been made. |
| FL-30 | **HOLD · Shelved** | **New from fonts / two-font combination.** Keep product entry points removed. Existing saved experiments remain readable. Reconsider only if the user explicitly changes this decision; do not silently revive it as an interpolation shortcut. |

## Spaces

| ID | Priority / state / effort | Outstanding work |
| --- | --- | --- |
| SP-01 | **P0 · Missing/partial · M** | **A real shape appearance inspector.** Fill, stroke, stroke width, opacity, corner radius and eventually gradients. Imported shapes store color/opacity/radius, but the current inspector hides Text color for a selected shape and does not expose a proper shape-color replacement. Aligned color wells did not solve shape styling. |
| SP-02 | **P0 · Partial · M** | **Explicit editing scope.** Clearly show whether a change affects one selected text object, a shared typography role or the whole canvas; support local style overrides and reset. Template objects currently share role styling while imported text has independent styles. |
| SP-03 | **P0 · Partial + QA · M** | **Selection and transform consistency.** Clear selected-object bounds, discoverable move/resize controls, robust click targeting, keyboard nudging, predictable Undo and consistent behavior across template and imported canvases. Audit before expanding the drawing toolset. |
| SP-04 | P1 · Partial · M | **Multi-object selection and alignment.** Align/distribute relative to selection, key object or canvas; group/ungroup, lock/hide and joint movement. Current Align controls position one selected frame relative to the canvas. |
| SP-05 | P1 · Partial · M | **Text-frame controls.** Auto width/height versus fixed boxes, frame padding, vertical alignment, overflow indicators and clear resizing behavior; avoid accidental text clipping and implicit template constraints. |
| SP-06 | P1 · Missing · L | **Mixed inline text styling.** Different families, weights, colors, links, superscripts or emphasis within one text block. Current TypeStyle describes a whole text item, not styled ranges. |
| SP-07 | P1 · Partial · M–L | **Paragraph and list depth.** Real list models, hanging indents, nested lists, numbering continuation, tabs/stops, left/right indents, space before and configurable paragraph rules. Existing list markers are ordinary editable text. |
| SP-08 | P1 · Partial · M | **Type controls and units.** Clear px/pt/em conversion, optional thousandths-of-em tracking, baseline shift, decoration options and more usable contextual OpenType/alternate selection. Existing tracking uses canvas units; Metrics/Off kerning exists, optical kerning does not. |
| SP-09 | P1 · Partial · M–L | **Reusable styles and overrides.** Named text/color styles across canvases, linked updates, local overrides, reset/detach and explicit style differences. Role presets and exported tokens are a foundation, not a complete shared design-system editor. |
| SP-10 | **P1 · Partial + QA · M–L** | **Export fidelity.** Check wrapping, leading, kerning, axes, OpenType settings, shapes and alignment in actual destination apps. Make approximations/losses visible. Developer handoff is currently a typography reference, not a pixel-perfect production layout export. |
| SP-11 | **P1 · Partial + QA · M** | **Live Adobe bridge verification.** Execute Illustrator/InDesign builders and returns in supported app versions with real documents, edits, missing fonts and unsupported content. Generated-JSX/parser tests do not establish live Adobe compatibility. |
| SP-12 | P1 · Partial · M | **Figma plugin delivery.** Package/document the already-working local bridge for ordinary users, resolve fonts cleanly, and broaden fidelity tests. Publishing a plugin is outstanding; outbound/inbound JSON already exists. |
| SP-13 | P1 · Research · M | **Proofing utilities.** Contrast checks, missing-glyph/fallback warnings, line-length/readability inspection and useful export preflight. Inventory existing diagnostics before building duplicate checks. |
| SP-14 | P2 · Missing · L | **General layout system.** Constraints, responsive reflow, stacks/grids, spacing/padding and layout guides. Current template/custom-block layouts and imported positions are not general Figma auto layout. |
| SP-15 | P2 · Missing · L | **Reusable layout components.** Linked instances, variants and shared blocks. These are Spaces UI/layout components, distinct from Font Lab glyph components. |
| SP-16 | P2 · Missing · M–L | **Deeper vector and appearance tools.** Arbitrary paths, masks/clipping, blend modes, gradients, effects, images and richer shape types. Decide how much general illustration belongs in a typography app. |
| SP-17 | P2 · Missing · L | **Advanced typography.** Text on a path, columns, linked text frames, wrap around objects, hyphenation, optical margins, baseline grids and richer justification. Optical kerning needs its own algorithm/quality review. |
| SP-18 | P2 · Partial · M | **Presentation/review.** Better reusable specimen templates, annotations, comparison summaries, print/export presets and shareable review artifacts. PDFs and comparison views already exist. |
| SP-19 | P2 · Research · L | **Web output depth.** Responsive layout export, reliable browser rendering comparisons, richer token round trips and validated CSS/platform output. Font handoff must continue to avoid silently bundling licensed binaries. |
| SP-20 | P3 · Research · XL | **Native design-document support / live sync.** `.ai`, `.indd`, `.fig` decoding, richer round trips and live integrations require separate feasibility work. Script/JSON bridges remain the practical current route. |
| SP-21 | P3 · Missing · XL | **Team collaboration.** Shared projects, comments, permissions, simultaneous edits, history/conflict resolution and optional hosted review. This requires a service/security/product decision. |

## Library

| ID | Priority / state / effort | Outstanding work |
| --- | --- | --- |
| LB-01 | **P0 · Partial + QA · M** | **Folder access and activation reliability.** Diagnose the repeated access-renewal notice seen during local launches; distinguish valid permission renewal from avoidable repeated prompting. Test relocation, revocation, unavailable volumes and recovery without repeated scans. Verify session activation under final App Store sandbox entitlements. |
| LB-02 | **P1 · Missing · L–XL** | **Document-triggered activation.** Identify missing fonts requested by another app and activate the correct face/version. This is a major Typeface/Extensis workflow gap, distinct from current manual session activation and watched-folder refresh. Investigate supported macOS/app integration before promising broad coverage. |
| LB-03 | P1 · Missing · M–L | **Collection migration.** Import Font Book/Typeface/FontBase/legacy-manager organization where accessible, with mapping, duplicate/conflict review and source preservation. Reading font files is not importing another manager's collection database. |
| LB-04 | P1 · Research · M | **Saved searches / smart collections.** Save useful compound filters and automatically update membership. Nested tags and property tokens already exist; audit any partial persistence/UI before adding another parallel search system. |
| LB-05 | P1 · Partial · M | **License records and provenance.** User-supplied receipts/license documents, foundry/source, desktop/web/app permissions, notes and renewal fields with search/export. Existing license-file handling for downloads is not a full entitlement tracker. Do not present metadata as an automatic legal determination. |
| LB-06 | P1 · Partial · M–L | **Font identity/conflict management.** Explain duplicate binaries versus same-name/different-version faces, active copies, family merge/split and recovery. Exact-duplicate detection and basic family tools already exist. Prioritize safe resolution over aggressive automated deletion. |
| LB-07 | P1 · Partial + QA · M | **Large-library and bad-font resilience.** Test substantially beyond the current approximately 4,252-style machine: corrupt files, slow/network disks, missing volumes, cache invalidation, cancellation and responsive filtering. Existing timing measurements are not universal performance guarantees. |
| LB-08 | P1 · Partial · M | **Find/recommend quality.** Better ranking, visual explanations, user feedback and repeatable evaluation across scripts; metadata-based Find similar and pairing already ship. Do not label this screenshot recognition. |
| LB-09 | P1 · Research · M | **Coverage-first selection.** Make required-string/language/script coverage, fallback and OpenType capability filters easy to combine. Existing Unicode inspection, language/property filters and handoff coverage should be audited for usability before calling this missing. |
| LB-10 | P2 · Research · M–L | **Richer visual-property search.** Measured x-height, width, stroke contrast, slant and other shape characteristics; explain measured versus metadata-derived values. Existing category/tag filters are not full geometric search. |
| LB-11 | P2 · Partial · M | **Color-font inspection.** Palette selection and meaningful COLR/SVG/bitmap capability reporting; system rendering alone is not a palette editor. Typeface documents predefined COLRv0 palette selection. |
| LB-12 | P2 · Partial · M | **Comparison improvements.** Better multi-font proof strings, normalized comparison modes, script-aware examples and saved comparison sessions. Font overlays, shortlist and PDF specimens already exist. |
| LB-13 | P2 · Partial · M | **Font Health depth.** Broader table/format diagnostics and repair coverage, clearer nonrepairable cases and actual sandbox repair tests. Current repairs exclude several containers and do not repair outline/layout/hinting data. |
| LB-14 | P2 · Research · L | **Cross-device organization sync.** Collections, tags, favorites and metadata with conflict handling. A cloud-synced watched folder alone is not synchronization of the library database; font-file sharing permissions must remain explicit. |
| LB-15 | P2 · Missing · L | **Application sets and integrations.** App-scoped activation/deactivation sets, font panels and font-use/document tracking. Treat activation plugins for individual host apps as separately maintained integrations. |
| LB-16 | P2 · Research · M–L | **Store/provider integration.** Deeper catalog discovery, purchase/download handoff and source updates beyond the existing Google workflow; third-party provider access and licensing may limit automation. |
| LB-17 | P3 · Missing · L–XL | **Screenshot font identification.** Image segmentation/OCR, shape matching, confidence and alternatives. Requires its own dataset/evaluation and possibly external services; not a small extension to metadata similarity. |
| LB-18 | P3 · Missing · XL | **Shared team libraries and administration.** Roles, approved families, deployment, audit logs and license-assignment workflows. Extensis is a useful enterprise benchmark; this is a separate scale of product. |
| LB-19 | P3 · Research · XL | **Cross-platform clients / persistent background service.** Windows or other platforms, organization sync, and watching/activation when FontShelf is closed. Current watcher operates while the Mac app is open. |

## Cross-product and release work

| ID | Priority / state / effort | Outstanding work |
| --- | --- | --- |
| X-01 | **P0 · QA · M** | Critical manual matrix: object selection, Shift resizing, Undo/Redo, clipboard, numeric focus/commit, color controls, pinch/scroll and real drag/drop. Include disabled states, small windows and accessibility. Automated tests are not a claim that every interaction was manually verified. |
| X-02 | **P0 before external release · Partial + QA · M–L** | Signed-archive preflight and bundle checks are implemented. Apple Distribution identity, Organizer/App Store Connect validation, TestFlight, final-entitlement checks on the signed build and clean second-Mac install/recovery remain. The local app is still ad-hoc signed. |
| X-03 | **P0 before Store migration · Partial + QA · M** | User-selected migration copies Library/Spaces/Font Lab data and managed Google Fonts into a fresh container, with source preservation and collision/corruption checks. External folder permissions must be granted again through Live folders; a signed Store-build migration test remains. |
| X-04 | P1 · QA · M | macOS 13 and second-machine testing, sleep/wake, offline behavior, inaccessible files, crash recovery, accessibility/VoiceOver and keyboard-only workflows. Intel is not shipped; decide support intentionally. |
| X-05 | P1 · Partial · S–M | Keep in-app help and docs aligned with releases; avoid calling shipped foundations missing or calling prototypes complete. Add a concise feature/status page and useful changelog. |
| X-06 | P1 before branding/release · Research · S | Review the workspace name **Font Lab** for confusion with the existing commercial **FontLab** product. This is a naming/product review, not a conclusion about trademark rights. |
| X-07 | P1 · Partial + QA · M | Backup/restore/migration stress tests across versions, corrupt files and large projects; accessible restore UI and export portability. Backups and preservation safeguards already exist. |
| X-08 | P2 · Research · M | Localization, documentation/examples, onboarding and support diagnostics that avoid collecting private fonts or project content by default. |
| X-09 | P3 · Research · XL | Cloud architecture, accounts, billing, team permissions and optional AI services only if those strategic directions are approved. Do not let these block local editing quality. |

## Competitor reference and scope

These are category benchmarks, not a claim that every competitor supports every proposed row. Priorities above are FontShelf product judgments based on the user's requests. Vendor pages establish feature categories; they do not prove implementation quality or exact round-trip fidelity.

- **Professional font creation:** Glyphs documents [multiple-master setup](https://glyphsapp.com/learn/multiple-masters-part-1-setting-up-masters), while its [Glyphs 3 introduction](https://glyphsapp.com/news/glyphs-3-make-things-you-love) describes variable/color workflows and feature editing. These are the reference for moving beyond independent static masters.
- **Advanced font-editor depth:** [FontLab 8](https://www.fontlab.com/font-editor/fontlab/) describes thickness editing, component/anchor workflows, interpolation, automatic spacing/kerning, color-font formats, broader file interchange and scripting. FontShelf should approach those as separate projects, not one parity checkbox.
- **Object/stroke editing:** Illustrator's [Width tool](https://helpx.adobe.com/illustrator/using/tool-techniques/width-tool.html) supports variable-width strokes. Its [Paragraph panel](https://helpx.adobe.com/illustrator/desktop/design-with-text/edit-format-text/paragraph-panel-overview.html) and [character spacing](https://helpx.adobe.com/illustrator/using/line-character-spacing.html) documentation provide text-inspector references. A mature illustration app is a workflow benchmark, not an appropriate short-term scope target.
- **Layout/text tooling:** [Figma text properties](https://help.figma.com/hc/en-us/articles/360039956634-Explore-text-properties) covers richer text formatting and frame behavior. Figma is an adjacent benchmark for Spaces, not a font-creation competitor.
- **Mac library workflow:** [Typeface](https://typefaceapp.com/) documents organization, comparison, coverage and color-palette tools. Its [auto-activation documentation](https://typefaceapp.com/help/articles/auto-activation) describes responding to fonts requested by other apps. FontShelf already overlaps much of the browsing/organization baseline; activation and workflow finish are more useful gaps than recreating those basics.
- **Another library baseline:** [FontBase](https://fontba.se/) and its [variable-font tutorial](https://fontba.se/learn/variable-fonts) are useful browsing/variable-preview references. FontShelf already has variable-font preview; that is not outstanding merely because a competitor advertises it.
- **Enterprise font management:** [Extensis font management](https://www.extensis.com/font-management-software) and [current Connect release notes](https://www.extensis.com/support/connect/release-notes) describe activation, team sharing and license/risk-management workflows. Those inform strategic Library rows, not commitments to build enterprise infrastructure.

## Definition of the next sensible milestone

A user can import their own artwork, correct it, select/scale complete shapes, adjust weight deliberately, space a short alphabet, export a usable static font, and try it in Spaces with obvious object-level styling. They can find and activate the fonts they need without getting lost in permissions or hidden controls. Finish that loop before pursuing professional variable/color-font parity or collaborative design-platform scope.
