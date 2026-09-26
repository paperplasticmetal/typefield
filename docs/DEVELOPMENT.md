# Development guidelines

## Source map

- `main.swift`: catalog/models, persistence, library UI, app lifecycle, menus, and test entry point.
- `PreviewLayout.swift`: adaptive widths, explicit Core Text line positioning, overlay rendering.
- `Appearance.swift`: palette, native popups, glass/fallback surfaces, sidebar sections.
- `FontInspector.swift`: family styles, variable tuning, OpenType, body layout and font context.
- `LibraryTools.swift`: tags, grouping, duplicates, activation UI, Google downloads/previews.
- `ProModels.swift`: metadata parsing, advanced filters, activation journal, duplicate hashing, exports.
- `FolderAccess.swift`: security-scoped bookmarks.
- `Features.swift`: script coverage probes, comparison and manual Adobe script export.
- `ProChecks.swift`: persistence and feature regressions.

## Invariants

- Preserve the user's font files and library data. Surface failures; do not overwrite unreadable state with defaults.
- Keep font size literal. Make space for text through wrapping/layout, not silent shrinking or clipping in library cards.
- Align actual baselines. Distinct ascenders, descenders and glyph shapes are not interchangeable with a view's top edge.
- Keep the toolbar readable and the sidebar's glass native. Use availability checks and respect accessibility preferences.
- UI copy must be concise and functional; no taglines or decorative filler.
- Preview downloads must not activate fonts or modify the library. Keep preview text on-device.
- Maintain sandbox compatibility and explicit user-selected file access. Adobe support is script export only.
- Update both version plists. App bundle display name is Typefield; preserve legacy data paths and versioned interchange formats.

## Local release workflow

- Use `/Applications/Typefield.app` as the single canonical local app. Do not create numbered Typefield app copies or ZIPs unless they are explicitly requested.
- For each completed fix or feature, run the relevant checks, commit the source and documentation, and push the commit to `origin` so GitHub remains the durable reference.
- For each user-visible build, update both version plists, the changelog and status notes, then run `./install-local.sh`. The script builds, runs the native regression suite and updates the canonical Applications copy.
- Never replace an unreadable library or workspace while installing a build. App data remains in Application Support and is separate from the app bundle.

Keep source-only changes separate from generated artifacts. The `.gitignore` excludes local output and private state. Use Xcode's complete bundle for distribution rather than relying on the source-only Swift package.

## Letterform Editor specimens

Run `dist/Typefield.app/Contents/MacOS/Typefield --font-lab-specimen /tmp/typefield-specimens` to render disposable comparison sheets and export validation fonts. This command does not open the user library or save projects. Fonts unavailable to the current process are skipped. Use normal macOS execution for the complete installed font catalog. Generated files are QA fixtures, not distribution artifacts.

Run `dist/Typefield.app/Contents/MacOS/Typefield --starter-quality-audit` to compare starter-letter suggestions with held-out outlines from nine installed faces, including Chalkboard SE, Noteworthy, Marker Felt, and Snell Roundhand. Each in-memory project sees only H, O, n, o, and p; the remaining Latin letters are used only as ground truth. The audit reports sampled silhouette overlap and design-width error by construction method, plus mean and maximum editing-anchor counts. It never reads or writes saved Letterform projects. This is a directional regression probe, not a probability of correct letter design or a quality score for arbitrary user handwriting or a substitute for visual proofing.
