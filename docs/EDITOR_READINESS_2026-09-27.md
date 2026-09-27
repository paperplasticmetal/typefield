# Letterform Editor readiness review

This is a capability and workflow review, not a claim of parity with Glyphs or a complete accessibility audit. Typefield's Library/Glyphs, Spaces and Letterform Editor serve different tasks. Improvements in 0.54 are local development changes; the suggestion engine remains experimental.

## What the editor now supports

Editable cubic contours, handles and smooth/corner points; whole-object or node selection; snapping, guides, zoom/focus, transforms and numeric positions; exact subdivision; splitting/joining; contours and counters; Boolean operations; bounded trace fitting; per-glyph undo/redo; proof text, side bearings and pair/group kerning; nested components; independent static masters; SVG and static TrueType export. Small normal projects have meaningful automated and live coverage. These capabilities do not establish readiness at extreme project sizes.

## Work needed before claiming a full professional font editor

| Priority | Gap | Why it matters | Concrete next milestone |
| --- | --- | --- | --- |
| Release gate | Missing-letter inference | Nine-style mean is only 51.5%; ambiguous structures and connected script remain weak. | Family-disjoint licensed evaluation and an evaluated vector-generation model. Track worst style, per-letter acceptance, invalid contours and editable anchors alongside mean IoU. |
| High | Direct vector artwork import | SVG artwork currently goes through the artwork raster/trace pipeline. A precise source curve can acquire trace error and extra nodes. | Parse a bounded safe path subset into exact cubic contours; compare exported/reimported geometry, transforms, fill rules and counters. |
| High | Reliable topology and editing under load | Normal curve operations need adversarial testing for touching contours, near-coincident handles and dense traced sources. | The six original audit findings have targeted fixes in 0.55. Extend coverage to touching/intersecting contours, actual UI latency distributions and shape-preserving delete/dissolve before expanding the tool set. |
| High | Spacing and proofing workflow | Current bearings and per-pair/group controls are separate from a full text-driven glyph-editing workflow. | Editable multi-glyph proof context, consistent undo for project metrics, overhang/negative-bearing design, and explicit overset/missing-glyph indicators. |
| High | Mark anchors and layout | Components support translation and uniform scale; there are no attachment anchors or automatic combining-mark placement. | Named anchors, mark components, decomposition invariants, and shaping tests for accented/combining sequences. |
| High | Modern OpenType layout export | Kerning exports a bounded legacy `kern` table; there is no GPOS/GSUB feature authoring or contextual shaping export. | GPOS pair positioning first, then explicit feature support with HarfBuzz/Core Text cross-checks. |
| High | Interpolation and variable export | Masters are independent static designs; there is no compatibility validation, interpolation or variable font export. | Outline correspondence diagnostics and intermediate-instance validation before attempting variable export. |
| Medium | Navigation and discoverability | Essential controls are divided between Paths, Transform, metrics and the Components & masters sheet. | Task-based inspector grouping, visible selection semantics, a searchable glyph list, and consistent keyboard/accessibility actions. |
| Medium | Export preflight and interoperability | Static TTF and SVG cover only part of a professional production workflow. | Clear preflight for open/degenerate/self-crossing contours and unsupported tables; tested CFF/OTF/WOFF2 only after those exporters exist. |

The comparison is based on Typefield's current implementation and the official Glyphs handbook's [path editing](https://handbook.glyphsapp.com/editing-paths/), [components](https://www.handbook.glyphsapp.com/components/), [kerning](https://handbook.glyphsapp.com/kerning/) and [interpolation](https://handbook.glyphsapp.com/interpolation/) workflows. No Glyphs implementation or assets are used.

## Whole-app review priorities

- **Library / Glyphs:** keep a large catalog searchable and responsive; collections and tags need usable navigation at large counts. Corrupt fonts and missing watched folders must fail locally without losing the saved library. Batch actions must make scope visible.
- **Spaces:** stress large layer lists and many canvases, preserve exact undo/save behavior, and make text overflow/export limits explicit. Accessible canvas actions should remain practical on large boards.
- **Letterform Editor:** keep source fidelity separate from suggestion fidelity; show experimental status, preserve independent editing histories, and decline impossible operations with clear feedback. Large glyph sets and dense nodes need limits that preserve a responsive UI.

See the [adversarial audit](STRESS_AUDIT_2026-09-27_0.54.md) for actual reproduced failures. Proposed improvements in this table are not implemented or verified features.
