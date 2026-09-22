# Font Lab design controls

Open a project and choose **Font design**. Changes are staged until **Apply**; Cancel preserves the current project. **Undo setup** restores the previous project while that applied setup is still the latest change.

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

## Smooth trace

Select a glyph containing imported closed polygons and choose **Smooth trace…**. The automatic fit offers Gentle (0.5), Balanced (1) and Loose (2 font units), side-by-side previews and node counts. **Apply smoothing** saves editable cubic curves; **Undo edit** restores the source polygons.

The fitter retains sharp corners, checks sampled deviation in both directions, preserves winding and contour containment, and rejects detected crossings. It leaves pen strokes and existing Bézier paths intact. Fitting is bounded to 6,000 polygon points and may decline complex outlines. Review the result at editing zoom: these conservative geometric checks do not replace optical judgment or provide a formal topology guarantee. Artwork is never silently smoothed during import.

## Verification and references

`FontLabDesignChecks` covers nested source propagation, cycle/bounds rejection, independent decomposed identities, SVG/TrueType equivalence to resolved outlines, master switching/persistence, group exceptions, actual Core Text kerning and smoothing of a noisy two-contour ring. Native disposable-project checks exercise the design sheet separately from user projects.

Workflow references: [Glyphs components](https://handbook.glyphsapp.com/components/) and [kerning](https://handbook.glyphsapp.com/kerning/). The binary pair table follows the [OpenType kern specification](https://learn.microsoft.com/en-us/typography/opentype/spec/kern). No Glyphs code or assets are included.
