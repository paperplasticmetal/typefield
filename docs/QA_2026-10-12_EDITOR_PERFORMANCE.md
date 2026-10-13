# Letterform and Spaces refinement — 0.59.31

Validated build 111, based on app 0.59.30 and source `4259f25`. This pass addresses measured editing/save costs and reproduced image interactions; missing-letter synthesis research remains paused.

## Changes and checks

- Letterform object selection retains exact native containment results until glyph geometry changes. The bounded cache stores contour indices, preserving counters and the existing overlap rules. Checks compare against the pre-change oracle, including same-ID anchor/handle edits, contour order/closure, legacy contours, additive selection, native marquee cancellation and undo/redo.
- Letterform saves reuse encoded fragments for unchanged projects on the existing serial persistence queue. Per-project revision tokens avoid canonical-Unicode equality shortcuts. Saves still validate, finish synchronously when requested, rotate exact previous-file backups, and report failures. Checks cover byte-identical sorted JSON, escaped/decomposed text, masters, delete/restore, imports, same-ID backup replacement, failed writes/retry and deferred-save ordering. Retained cache limits are 32 MiB and 128 projects.
- Spaces chooses the closest resize handle inside its existing hit radius. Preview limits account for cumulative transforms across the selection, preserve the opposite edge/corner and discard invalidated snap guides. Pasting or duplicating returns to Auto so the new objects can be manipulated immediately.
- The opt-in disposable stress fixture now includes a 10,000-anchor outer contour/counter pair for live editing.

## Reproduced installed-app baseline

Actual CUA pointer tests on disposable 0.59.30 projects confirmed normal proportional resizing, pasted-image movement, canvas-edge snapping and undo. Extreme shrinking previewed a smaller image but restored its old size on release. Pasting from Canvas mode selected the new image while retaining Canvas mode. Geometry probes also found incorrect handles for 51 of 128 exact handle-center clicks across small sizes and zoom levels.

## Measured scope

Optimized native probes use disposable deterministic fixtures on the same machine. Values are milliseconds; save figures are medians and include synchronous validation, backup and atomic writes.

| Operation | Baseline | Candidate |
| --- | ---: | ---: |
| Repeated selection, 10,000-anchor outline plus counter | 116.265 | 0.432 |
| Unchanged 4.87 MB Letterform store save | 129.346 | 10.049 |
| One glyph edited in the 4.87 MB multi-project store | 132.039 | 58.058 |
| Create an empty project beside the same saved projects | 130.810 | 10.560 |
| Cold save of the same store | 131.010 | 134.128 |
| Edit/save one single 4.89 MB project | 133.394 | 134.970 |

First dense object classification still costs about 122 ms. Changed dense-overlay redraw remains about 28–30 ms. The save fixture has three active and eight deleted projects, with 15 warm samples and seven cold/single-project samples. The cache limit covers retained fragments, not total process memory. Cold saves add about 3 ms of cache assembly in this fixture; one very large modified project still requires full encoding of that project and shows no improvement. These are operation timings, not whole-app frame-rate claims. Physical Apple Pencil pressure testing remains for user hardware.

## Installed-app verification

The full native suite and window suite passed after `./install-local.sh` installed the canonical `/Applications/Typefield.app`. Its strict signature and executable match the built app. Figma bridge, localization, 14 updater checks and all eight website tests passed. The integrated native dense-selection check measured 115.543 ms cold and 0.424 ms warmed.

Actual CUA pointer/keyboard checks used disposable projects:

- Image import 320×160 → proportional resize 400×200 → extreme shrink 6.4×3.2 persisted. Dragging farther at the limit produced no extra undo step: one Undo restored 400×200 and Redo restored 6.4×3.2.
- The tiny bottom-right handle regrew the image to 86.4×43.2 while retaining the opposite anchor. Paste from Canvas mode returned to Auto with visible handles. Direct movement and edge stretching worked immediately, and undo/redo restored width 86.4↔136.4. Canvas size remained 640×480.
- Dense O object selection and marquee selected its outer contour and counter. A real drag applied one identical delta to all 10,000 anchors. Undo/redo/undo restored the whole saved project exactly. A Nodes drag changed one outer anchor and no counter nodes; subsequent object selection still grouped both contours, and Undo/quit restored the exact saved state.
- The native Go to Folder automation shortcut timed out in the macOS picker. A process sample showed the app idle in its normal event loop; selecting the visible fixture entry completed import and all subsequent tests. No app hang was established.

All 37 starting user JSON hashes and both paused research hashes remained unchanged after installation and live tests. Raw fixtures, timing samples, saved-state comparisons and diagnostic artifacts remain private under `.context/qa-artifacts/`.

## Distribution

Released as [0.59.31 beta 1](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.31-beta.1), build 111, from `55b0c68`. Both origin repositories received the source and verified assets. The existing Cloudflare Pages `typefield` project was deployed with its feedback Function; the latest website design was retained.

The canonical [download page](https://typefield.app/download/) and unauthenticated GitHub/website DMGs agree. DMG SHA-256: `82ad3c1adc4db10d591f7559d3df8729519692e7271e8fed60a5607f579b8b71`. The mounted app, archive checksum, signature and signed update feed passed validation. Public feed bytes exactly match the signed local feed, served as RSS with `Cache-Control: no-cache`. The feedback endpoint returns its configured public widget key.

The actual canonical app shows version 0.59.31 (111) and Check for Updates reports 0.59.31 is the newest available version. All 37 original user JSON hashes and both paused research files remained unchanged after this final check. A Python default-user-agent fetch received HTTP 403; standard curl downloads succeeded and provided the verified public bytes.
