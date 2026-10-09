# Workspace headers, Letterform panels and drawing devices — 0.59.30 (110)

Based on the complete 0.59.29 release (`0f4c963`). Native and live integration verification passed. Installed with `./install-local.sh` at the canonical `/Applications/Typefield.app`; version 0.59.30 (110), strict signature and executable equality verified. Public distribution is complete: the website and GitHub serve the matching DMG, both public feed/archive signatures validate, and the installed Check for Updates reports 0.59.30 as current.

## Changes

- Library, Spaces and Letterform use one header layout, title scale and 36-point action style. Narrow windows wrap actions while preserving the same search, rename and menu instances.
- Letterform Import is a direct top-bar action beside Export. Project retains font setup/history. The empty workspace also exposes Import and device guidance.
- A visible iPad & tablet action explains Sidecar, compatible Pencil models and macOS tablet setup. Start sketching selects Sketch / Pen / Round nib / Pressure. Linked-component glyphs keep their existing Vector restriction.
- One retained session flag controls Metrics & spacing in wide, compact, Focus and detached layouts. Hiding a panel preserves its values and glyph editing state. Metrics start collapsed so the drawing area stays visible; View or the compact disclosure opens them.
- Character-list and proof-strip handles use window-coordinate pointer deltas, include the final release position, clamp to available space and remain visible at their limits. Drag previews are transient; preferences are saved on release only when the size changed. A stationary click or outward drag at a constrained limit preserves the preferred wider size. Escape cancels; double-click resets; keyboard and accessibility adjustments remain available. The Letterform content width stays bounded by its viewport.

## Verification

- Isolated native resize-event checks passed pointer movement while the handle moves, both axes, limits/reversal, window-constraint changes, release position, cancellation, focus loss, reset and keyboard/accessibility actions.
- New hosted tests cover real Letterform metrics visibility/state retention and shared header geometry, wrapping/localization and text-field identity/focus. All passed in the bundled full native suite. The final window integration suite also passed.
- Live disposable UI checks passed character-width dragging/clamping at wide and minimum window sizes, immediate inward movement from a constrained limit, proof-height dragging and double-click reset of both handles. The metrics command visibly collapsed its controls. The standalone Import action imported a synthetic A with its counter and 11 editable nodes; the device guide switched between iPad/tablet instructions and entered Sketch / Pen / Round / Pressure.
- Final live header checks passed in Library, Spaces and Letterform at wide/minimum widths. A real Library search retained text and editing focus through wrapping. Pointer clicks near the Spaces Board menu edge opened it. The character panel restored its saved 420-point width after shrinking the window, clicking the constrained divider without moving, and widening again. Wide View-menu metrics hide/show worked; detached metrics retained visibility, then remained hidden after redocking.
- Native menu edge-click checks caught the macOS borderless style dropping rich header labels to 18 points. The button/plain menu style retains all 36 points; all four edge clicks open its menu.
- Figma bridge mocks, all 14 signed-feed regression tests, all 8 website tests and localization completeness checks passed. The full native suite includes import/edit/undo/SVG/TrueType and the existing Spaces/Library regressions; final window integration passed.
- All 33 recorded saved-data files and both paused research edits are byte-identical after installation. Destructive/editing tests use disposable projects. Missing-letter research remains paused.

## iPad test path

1. Open Letterform → iPad & tablet. Follow the Sidecar steps, then move the Typefield window to iPad.
2. Use a disposable glyph. Choose Start sketching and draw with Apple Pencil. Check tool selection and stroke placement.
3. With a pressure-capable Pencil, compare a light-to-firm stroke with Pressure on and off. Check Brush settings for width and smoothing.
4. Undo/Redo a complete stroke, change glyphs and return, then reopen the project. Check the stroke remains intact.
5. Switch to Vector to test pen-based anchor/handle editing. Test the character-list and proof dividers on the iPad as well.

Apple's [Sidecar guide](https://support.apple.com/en-us/102597) and [iPad setup guide](https://support.apple.com/guide/ipad/ipad2b1aa3be/ipados) document the display/pen workflow. [Pencil compatibility](https://support.apple.com/en-us/108937) and [Pencil features](https://www.apple.com/apple-pencil/) explain model support, including the USB-C Pencil's lack of pressure sensitivity. These sources establish setup requirements; actual Typefield iPad, Pencil and pen-tablet input has not been physically verified in this pass. Detected pen input is a session event indicator, not a live connection or pressure check. Custom Pencil double-tap, squeeze and barrel-roll actions are not implemented.

## Public distribution

- Release source: `2dd14cae32fa6303df4a3b026447b8ca4790c3eb`, pushed to both configured repositories.
- [GitHub beta](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.30-beta.1), [public download](https://typefield.app/download/) and signed appcast all identify 0.59.30 (110). Cloudflare Pages deployment: `113fed9d`, including the feedback Function.
- DMG SHA-256: `9fdb64bbc7b0ca0bc2e9e86940ed6700a8bca9aaeec9f0f64548821a21167f4f`. Local, unauthenticated GitHub and website copies match. Read-only mounted app validation and strict signature/executable checks passed.
- Public appcast bytes match the locally signed feed, use RSS/no-cache headers, and validate against the downloaded public DMG. Feedback GET exposes its configured public widget key.
- About shows 0.59.30 (110); Check for Updates reports this as the newest release. All 33 saved-data hashes and both paused research hashes remain unchanged after final app verification.
