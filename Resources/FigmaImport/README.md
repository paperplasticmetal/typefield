# Typefield ↔ Figma

This package contains an editable layout JSON file and a local Figma development importer. It makes no network requests, uploads no fonts and does not modify existing layers.

1. In Figma desktop, use Plugins → Development → Import plugin from manifest and select this folder's `manifest.json`.
2. Run Typefield Layout Importer. Choose `layout.typefield.json`, then Import layouts. No assigned plugin ID or public publication is required.
3. Each saved direction becomes a separate frame, with editable text and shapes. Review the importer report for missing fonts or unsupported settings.

Keep the original fonts available to Figma. Missing fonts fall back to Inter with an explicit warning. Typefield does not redistribute font files or licenses.

Original typography settings are kept as shared layer metadata under the historical `fontshelf` namespace so existing Figma handoffs remain compatible. Other plugins in that Figma document can read this metadata. No private notes, font files or local paths are stored in it.

Positions, sizes, colors, alignment, line height, tracking, paragraph spacing, indents and basic decorations are transferred. Variable axes are applied when supported by your Figma version. Word spacing, custom kerning and OpenType overrides are retained as layer metadata but require manual review. Figma's text shaping and wrapping may differ from macOS. This is a local handoff, not live sync or a published Figma integration.

## Bring a Figma design into Typefield

1. Select one or more frames in Figma, then click **Export selected frames** in this plugin.
2. Review the warnings and click **Save Typefield typeboard JSON**.
3. In Typefield choose **Spaces → Import → Figma typeboard…**, then open that JSON.
4. Each frame becomes a saved direction. Select text on the canvas or in the text-layer picker to edit its font, size, spacing, alignment and content. Drag layers directly to move them; use Arrangement to change stacking order. Undo is available for these edits.

This does not read native `.fig` files. Text and solid rectangles are supported. Auto-layout and components become fixed independent layers, not linked Figma objects. Images, vectors, masks, strokes, effects and rotated layers are not faithfully reproduced; the exporter reports omissions or approximations. Mixed text styling uses the first run where possible and is reported. Font fallback and platform text-shaping differences can change wrapping. Keep your original Figma document as the source of truth for unsupported content.
