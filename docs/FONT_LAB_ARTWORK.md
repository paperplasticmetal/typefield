# Import drawings into Letterform Editor

Choose **Letterform Editor → Import artwork**, then select a PNG, JPEG, TIFF, HEIC, outlined SVG or `.procreate` file.

1. Use **Detect letters** for separated drawings, **Grid sheet** for regularly spaced cells, or **Single letter** for one character. Use plain/transparent backgrounds; switch **Light ink** for white drawings. Adjust the threshold and speck cleanup, then **Rescan**.
2. Inspect the source boxes and traced shapes. Click a box to select its row. Remove incorrect boxes and drag new regions around touching letters or disconnected marks.
3. Correct the suggested character labels. For a known alphabet sheet, enter its order or use **A–Z**, **a–z** or **0–9**. Order runs left to right, top to bottom. Every included region needs one unique character; omit duplicate samples with the checkboxes.
4. Choose a new project or the current project. Existing glyphs are kept by default. Check replacement only when you intend to replace their artwork.
5. Confirm you reviewed the regions, labels and shapes, then import. Use **Reshape** for point edits and the existing SVG/TrueType exports. **Undo import** restores the prior existing-project snapshot until subsequent edits change it; new projects use normal recoverable Delete.

## Fidelity and limits

Tracing follows monochrome ink, preserving closed counters and detached marks. Shared sheet scale and estimated row baselines preserve relative proportions; guide and bearing adjustments may still be needed for irregular hand lettering. Decorative backgrounds, touching letters, worksheet rules and extreme size differences need manual regions or cleaner exports. OCR suggests labels, not geometry, and is not reliable for every style or language.

Raster input is read with orientation metadata and limited to 3,200 pixels on its longest side. SVG paths, shapes and strokes are rendered at 2,400 pixels then traced; original Bézier controls are not retained. Convert text/effects to outlines or export PNG. Color/layer information is not retained.

Direct Procreate import reads an available embedded flattened preview or thumbnail and displays its resolution. It does not decode the original Procreate layer data. Export PNG from Procreate for full-resolution source artwork, especially if the embedded thumbnail is small. The file limit is 256 MB; larger documents should be exported as flattened artwork. Stored and DEFLATE preview containers are tested with a synthetic fixture; real Procreate-version compatibility remains a manual check.

## Original test files

`tests/fixtures/font-lab-artwork/` contains original SVG artwork for a 26-letter sheet, a single O and detached i/j/! marks. Generate PNG versions and a clearly labeled synthetic Procreate preview container with:

```sh
dist/FontShelf.app/Contents/MacOS/FontShelf --font-lab-artwork-fixtures /tmp/font-lab-fixtures
```

The synthetic container is an importer test, not an editable Procreate document. No installed font outlines or user projects are used to create these fixtures.
