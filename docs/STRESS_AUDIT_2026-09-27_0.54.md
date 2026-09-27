# Typefield 0.54 adversarial audit

Audited 2026-09-27 on macOS 26.3, after the improvement phase. **These findings have not been fixed.** The user requested improvement first, then audit only for review before debugging.

Tested release: **0.54.0 (74)**, code commit `1f26834`. The QA and canonical installed executable SHA-256 were both `6b2f5fc58d8aab1a5c9f58d81dda768235a1b4635258bb6a20dce999c8c3f545`. The full native suite, mocked Figma bridge and Xcode Release checks had already passed; those checks do not cover all the failures below.

## Isolation and evidence

Five disposable file profiles covered routine examples, dense letterforms, overloaded Spaces, a large Library, and malformed saves. They were launched using `CFFIXED_USER_HOME`; all destructive edits used these fixtures. Synthetic fonts were registered in the QA process, not installed for the user. Four original saved files (`font-lab.json`, `spaces.json`, `library.json`, `pro-library.json`) remained byte-identical after the audit. App preferences were compared before/after and matched after restoring the preview text.

Screenshots, the fixture generator, shape overlay report and process sample are retained in the ignored local QA evidence directory, not committed. Evidence filenames below identify the originals. UI timings include accessibility/automation overhead; they are not frame-rate or main-thread benchmarks. The long-text hang has a separate sampled main-thread trace.

## Reproduced failures

### QA-01 — P1: Object alignment collapses the selected outline

1. Open the dense letterform fixture, select C: a closed ellipse with 1,000 anchors.
2. Choose **Objects**, select the contour, then **Transform → Align horizontally**.
3. The filled ellipse collapses to a horizontal line. The saved JSON has 1,000 anchors but only one distinct Y coordinate, `0.5`.

Object alignment should preserve each object's internal geometry, or the node-only command should be unavailable in this selection mode. Instead, `FontLabVectorEditor.align(horizontal:)` aligns the individual selected anchors. Undo restored the original outline and was exercised before leaving this fixture.

Evidence: `letterforms-before-object-align.png`, `letterforms-object-align-collapse.png`. This is a verified shape-destroying edit with working Undo, not a claim of irreversible data loss. Vertical alignment and multiple-object variants were not separately exercised.

### QA-02 — P1: Bubble-letter suggestions lose the A counter

1. Use the built-in **Practice: Bubble letters · irregular counters** example, with B and O as the supplied forms.
2. Generate the missing letters and inspect A.
3. The construction fills almost all the intended upper counter and overlaps several thick contours. It is visibly unlike a usable bubble A.

The same basic counter failure exists in the 0.53 output; this audit does not attribute it solely to the 0.54 changes. A read-only point-in-ink probe on old/new generated outlines corroborated the filled interior. The screenshot was captured before any editing operation touched the suggestion.

Evidence: `bubble-suggestion-filled-counter.png`. This reinforces the release gate on automatic completion even though the development-set mean improved. Mean silhouette overlap is not calibrated confidence.

### QA-03 — P1: Long Spaces paragraphs stall the main thread

1. Open **QA: maximum text**, an editorial canvas with a valid Body text value consisting of `Word ` repeated 40,000 times (200,000 ASCII characters).
2. The board fails to finish opening. UI state and screenshot requests time out, while the QA process remains at approximately 100% of one CPU core across subsequent checks.
3. A three-second process sample captured the main thread in `TypeBoardEditor.visibleFontCount → CanvasTypographySummary → CanvasPlan.expandTextFramesForUnbreakableContent → CanvasBoardLayout.minimumTextFrameWidth`, repeatedly executing `NSString.paragraphRange(for:)` inside the token loop.

Source inspection also finds paragraph-prefix extraction/trimming on every token. Repeated scans of the growing paragraph are a likely cause; the sample establishes a real UI-thread stall, not just slow accessibility enumeration. The process was still unresponsive more than a minute after selection and was terminated specifically by PID. No automatic recovery or exact completion time was established.

Evidence: `spaces-long-text-hang.sample.txt`, fixture generator, and `spaces-5000-layers.png` / `spaces-30-canvases.png` from before selecting the long-text board. **Both attempts to capture the hung window timed out; there is no claimed screenshot of the hung board.** This case needs a cancellable/bounded path and a performance regression check in the later fix round.

### QA-04 — P2: Dense-outline cleanup recommends an unavailable operation

1. Open A in the dense letterform fixture: one valid closed polygon with 30,000 anchors.
2. The editor recommends simplifying before editing individual nodes.
3. Open **Simplify outline…**. The sheet rejects the outline because it exceeds the 6,000-polygon-point preview limit, leaves both previews at 30,000 nodes, and disables Apply.

The protective limit itself works. The workflow nevertheless leaves the user with an enormous outline and an unusable recommended remedy. Provide a practical staged cleanup/import route, or explain the limit before recommending Simplify.

Evidence: `letterforms-30000-points.png`, `letterforms-simplify-limit.png`. No crash was reproduced here.

### QA-05 — P2: Canvas headings become unreadable at Fit with many canvases

1. Open the Spaces fixture containing 30 canvases.
2. Choose **1 shown → Show every canvas**, leaving zoom at **Fit**.
3. The boards render and the app remains responsive, but names, Editing/Click to edit labels and dimensions wrap into narrow vertical stacks above each canvas.

The heading width follows the zoomed artboard width while its text retains its UI font size. Canvas identification and selection become difficult. This was reproduced in a wide window, not only at an unusually narrow window size.

Evidence: `spaces-30-canvases.png`. The first canvas contains 5,000 layers; the other 29 are normal template canvases.

### QA-06 — P2 usability: Long Library previews make comparison impractical

1. With 750 filtered synthetic font families in grid view, set preview text to `ABO ` repeated 2,500 times (10,000 characters), at 26 pt.
2. The first preview card expands far beyond the viewport. Other families are pushed below it, preventing useful side-by-side comparison.
3. Setting the preview back to a short string restores the grid immediately.

This is an unbounded-preview usability limit, not a crash or data-corruption failure. A bounded card with an explicit expanded preview would preserve browsing at large text sizes.

Evidence: `library-long-preview.png`, with baseline `library-750-fonts.png`.

## Stress cases that held up

| Area | Load or edge case | Observed result |
| --- | --- | --- |
| Letterform Editor | 2,000 glyph slots and 101 projects; 30,000-, 6,000- and 1,000-anchor outlines | Project/sidebar opened and glyph switching worked. Dense cleanup and alignment failures are listed above. |
| Editor history | Edit A, switch to B and back, Undo; no history on B | A's independent history survived; Undo restored its original X coordinate; B's Undo remained disabled. |
| Contour editing | Split then join a closed ten-node curve | Eleven open nodes after split, ten closed nodes after joining coincident endpoints; live appearance preserved. Exact cubic invariants also passed native checks. |
| Spaces | 5,000 layers including 500 text layers, 30 canvases, 100 spaces and 52 boards in the first space | Dense board opened; showing all canvases remained responsive. Labels failed as described above. Not every one of the 100 spaces was manually opened. |
| Library | 750 valid synthetic TTFs plus a malformed font, yielding 1,528 families / 5,002 styles | All synthetic families were searchable; malformed input did not crash loading. No claim of exhaustive malformed-font fuzzing. |
| Library navigation | 1,000 saved collections plus synthetic tag/note metadata | Sidebar scrolled to collection 0999 and remained usable. Not every collection/tag operation was exercised. |
| Glyphs inspector | PingFang HK: 49,532 entries | Grid opened; search for U+9FFF returned its glyph and selecting it enabled outline export. Export itself was not executed in this stress case. |
| Glyphs inspector | Sparse synthetic font and unsupported U+10FFFF | Existing A/B/O entries selected; unsupported search returned “No matching glyphs.” |
| Corrupt saves | Malformed Library, Spaces and Letterform JSON | Library alert, Spaces warning with disabled creation/import, and editor warning with saving disabled. All three damaged fixtures remained byte-identical. |

Additional pass evidence: `editor-join-verified.png`, `glyphs-cjk-coverage.png`, `library-1000-collections.png`, `corrupt-library-protection.png`, `corrupt-spaces-protection.png`, `corrupt-letterforms-protection.png`.

## What this audit does not establish

This is an adversarial sample of the three workspaces, not exhaustive QA. It does not certify full Glyphs parity, a full VoiceOver workflow, all export formats under these extreme loads, storage-full/network-volume behavior, arbitrary corrupt font safety, or external Adobe/Figma services. The regular bridge check used a mock API. UI latency below the severe long-text stall needs instrumented measurements before performance targets are claimed.

The next debugging round should first address object-mode transform semantics and the Spaces main-thread stall, then contour/counter validity and recovery for dense imports. The other workflow limits should receive explicit product decisions. No production code was changed during this audit phase.

See [0.54 improvement measurements](QA_2026-09-27_0.54.md), [editor readiness gaps](EDITOR_READINESS_2026-09-27.md), and [the shape-quality plan](FONT_LAB_QUALITY_PLAN.md).
