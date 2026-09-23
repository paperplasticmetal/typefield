Letterform Editor artwork import fixtures

alphabet-A-Z.svg / .png — Original geometric A–Z artwork, left to right in four rows. Use Detect letters and Apply order → A–Z, or Grid sheet with 7 columns / 4 rows. Review all 26 outlines, then import into a new project.
single-O.svg / .png — A single letter with an open counter. Choose Single letter, label O and inspect the white hole.
detached-ij!.svg / .png — Tests detached dots and a descender. The order is ij!.
synthetic-preview.procreate — A synthetic ZIP container with Document.archive and an embedded flattened PNG, matching the supported Procreate preview layout. It is an importer fixture, not a document produced or editable by Procreate; it does not validate every Procreate version or native layer codec.

The SVG and PNG artwork here is original test geometry. No installed font outlines or user projects were used.
The repository contains the SVG originals. Generate PNG and synthetic Procreate fixtures with:
dist/Typefield.app/Contents/MacOS/Typefield --font-lab-artwork-fixtures /tmp/font-lab-fixtures
