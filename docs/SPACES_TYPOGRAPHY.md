# Spaces typography inspector

The inspector separates **Character**, **Paragraph**, **Bullets and numbering**, and **Align**. Expand Type roles to select another role or drag it onto the canvas. A selected text item uses its role's shared font/spacing style; its content and frame position are independent. Imported text layers keep independent styles.

- **Character:** choose a font family and one of its installed styles. Size, leading and tracking accept typed values, arrow keys, steppers and presets. Return or leaving the field commits a typed value; Escape discards it. Auto leading follows the font size using the saved ratio. Metrics uses the font's kerning; Off disables it. Optical kerning is not implemented. Values use the canvas's px/pt units, including tracking, rather than Illustrator's thousandths-of-an-em tracking units.
- **Paragraph:** left, center, right or justified alignment changes text inside its frame. Space after, first-line indent and additional word spacing are editable separately. Underline, strike and case controls stay in Character.
- **Bullets and numbering:** format each nonempty paragraph. Existing bullet/number markers are replaced, empty paragraphs are preserved, and numbering restarts after a blank paragraph. Markers are ordinary editable text and survive existing exports; this is not a nested-list layout engine or automatic hanging-indent system.
- **Align:** move the selected text frame to the canvas's left/center/right or top/middle/bottom. On imported artboards, selected shapes also work. These actions move a frame, whereas Paragraph aligns text inside it. Template frames can return to their original layout with Reset frame position. Alignment is to the canvas, not to a multi-object selection. Moving a template's text does not move its surrounding graphics.

Changes use Spaces' existing save/Undo flow. Saved text positions feed the same CanvasPlan used by previews, PDF and Figma layout exports. Legacy documents need no migration.
