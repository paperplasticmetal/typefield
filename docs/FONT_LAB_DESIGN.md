# Letterform Editor design controls

Open a project and choose **Components & masters**. Changes are staged until **Apply**; Cancel preserves the current project. **Undo setup** restores the previous project while that applied setup is still the latest change.

## Starter letters

An installable TrueType font can already be exported with only the letters that have artwork. Undrawn characters are omitted from the font's character map. To get editable starting points for the missing Latin letters, draw or import at least one letter and choose **Suggest missing letters…** in the Characters panel. Drawing **H** and **O** helps establish capital strokes and curves; **x**, **n**, **o**, and **p** provide lowercase height, stems, bowls and descenders. These examples improve the suggestions but are not required to export a partial font.

The review sheet separates uppercase and lowercase suggestions. It identifies letters that reuse actual contours from the drawings and letters built as measured templates. Source-derived letters can open an O/o for C/c, add a feature to a copied bowl, reflect complete stem/bowl joins, mirror compatible forms, or repeat n arches for m. Templates inherit measured width, stem inset and lean, side bearings, terminal shape, stroke weight, and descender depth when sources are available; their contours are still new constructions. Choose individual letters or **Select → Only reused outlines**; Cancel leaves the project untouched. Apply fills only empty glyphs in the active master, keeps every existing drawing, and offers **Undo suggestions** while that project snapshot is current. Suggested outlines are independent editable vector paths. Dense polygons and generated curves receive a bounded two- to three-unit cubic fit when it preserves the outline; the review shows the resulting anchor count. References with a consistent advance retain monospaced template widths, including the repeated m. Inspect them at editing zoom, adjust their curves and bearings, and proof words before distributing a font. A few sample letters cannot determine every design choice in an alphabet, so this is a starter workflow rather than automatic type design or model-backed generation.

## Components

Choose the destination glyph, then Components → Source glyph → Insert component. Adjust X/Y in font units or Scale in percent. Editing a source updates its uses in the active master. Linked geometry appears teal in the vector canvas; edit the source or choose **Decompose** to obtain independent nodes in the destination. Decomposition gives every copied path and node a new editing identity.

Components can nest, with cycle, depth, geometry and expansion limits. The destination keeps its own width and bearings. References are retained in saved projects and resolved into outlines for preview, SVG and static TrueType export. This first version supports translation and uniform scale, not anchors, automatic mark attachment, rotation or TrueType composite-glyph encoding.

## Masters

**Duplicate current as master** creates a separately editable design. The first duplication also preserves a Regular master. **Switch** saves the current outlines, components, metrics and kerning before loading the selected master. Names are editable. Export uses the active master and includes its name in the font family.

These are independent static designs. They do not interpolate, generate intermediate weights, form a style-linked font family, or export a variable font. Up to 16 masters are supported. Glyph-set additions create empty glyphs in every master without replacing existing artwork.

## Kerning

Choose a first and second glyph, enter an adjustment and choose **Set pair**. Negative values tighten spacing; units use a 1,000-unit em. Create groups for the first or second side of a pair, then choose those groups in the pair controls. A glyph may belong to one group per side.

Specific glyph pairs override group rules, including a zero-valued exception. One-sided exceptions override group-to-group rules; if both one-sided exceptions match, the explicit first-glyph rule wins. Remove a group to remove its dependent rules. The word preview and export share this precedence. Groups are stored per master.

TrueType export expands rules into horizontal legacy `kern` format 0 pairs and validates the result through Core Text. It currently supports at most 10,000 expanded pairs and does not emit GPOS, contextual or vertical kerning. Applications that ignore legacy `kern` may not display these adjustments. SVG glyph exports contain outlines, not pair layout rules.

## Simplify outline

Select a glyph containing imported closed polygons or dense closed curves (more than 32 anchors per contour) and choose **Simplify outline…**. The automatic fit offers Gentle (0.5), Balanced (1) Loose (2 font units), and Editable (5 font units), side-by-side previews and node counts. **Apply simplified outline** saves compact editable cubic curves; **Undo edit** restores the source outlines. Fitting uses a physical font-unit tolerance, preserves corners, winding and counter containment, and rejects crossings, filled-area changes, or excess deviation. Simple existing curves stay intact. New artwork imports receive a fit of 1–3 font units automatically, based on 1.5 source pixels; failed fits retain the original traced polygons.

The fitter retains sharp corners, checks sampled deviation in both directions, preserves winding and contour containment, and rejects detected crossings. It leaves pen strokes and existing Bézier paths intact. Fitting is bounded to 6,000 polygon points and may decline complex outlines. Review the result at editing zoom: these conservative geometric checks do not replace optical judgment or provide a formal topology guarantee. Artwork is never silently smoothed during import.

## Verification and references

`FontLabDesignChecks` covers nested source propagation, cycle/bounds rejection, independent decomposed identities, SVG/TrueType equivalence to resolved outlines, master switching/persistence, group exceptions, actual Core Text kerning and smoothing of a noisy two-contour ring. Native disposable-project checks exercise the design sheet separately from user projects.

Workflow references: [Glyphs components](https://handbook.glyphsapp.com/components/) and [kerning](https://handbook.glyphsapp.com/kerning/). The binary pair table follows the [OpenType kern specification](https://learn.microsoft.com/en-us/typography/opentype/spec/kern). No Glyphs code or assets are included.


## Practice examples and dense imports (0.53)

Use **Try handwriting & bubble examples…** in the Letterform Editor sidebar. The gallery shows original practice imports and suggested letters separately. **Open editable example** creates a new practice project with the source artwork and suggestions; it does not modify another project. Examples cover slanted handwriting with detached dots, irregular bubble counters, and a rounded A.

Existing projects keep their saved outlines when the app updates. A glyph with more than 100 anchors now shows a direct **Simplify outline…** action and its point count. The sheet starts with **Editable · 5 units** and compares the original with the proposed curve fit. Apply only after reviewing the preview; **Undo edit** restores the previous glyph. Straight spans become lines, clustered pixel corners are consolidated, and open pen paths remain unchanged.

See [the shape-similarity plan](FONT_LAB_QUALITY_PLAN.md) for the separate missing-letter inference target. Import fidelity and prediction similarity are different measurements.
