# Typefield launch film — landscape revision 4

28 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v4.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v4.mp4`. Earlier local deliveries remain available. Revision 3 source is preserved in commit `2ba6b6e`.

## Direction and research

This cut replaces screenshot panels with animated typography, original drawings and dimensional paper planes. A selected Library specimen becomes a Spaces composition. A drawn letter then becomes an editable outline, joins a spaced word, contracts into a TrueType file, returns to Library and expands into another composition. The artwork carries the connections; short captions name the actual product steps.

Primary references consulted:

- [Ordinary Folk — Webflow, A New Era of No Code](https://www.ordinaryfolk.co/project/webflow-a-new-era-of-no-code). The project page and portions of the film were reviewed. The reference informed continuity between objects, changes in scale and spatial layering.
- [BUCK — Notion, Think it. Make it.](https://buck.co/work/notion-think-it-make-it). The campaign article informed telling the product story through creative material rather than a succession of interface panels.
- [Ordinary Folk — Process](https://www.ordinaryfolk.co/process). The published process reinforced resolving the story and visual language before animation polish.
- [Ordinary Folk — Procreate Dreams](https://www.ordinaryfolk.co/project/procreate-dreams). The project description informed the compact drawing-to-outcome story.

These are interpretations used to guide an original composition. No reference footage, artwork, music or other third-party media was copied into the film.

## Story

| Time | Action |
| --- | --- |
| 0–2.65 s | Library specimens enter in depth; Baskerville is the central choice. |
| 2.65–5.3 s | The same “Form” specimen expands into a Spaces editorial composition. |
| 5.3–8.5 s | A second layout arrives, then its large F carries the transition into a coral drawing field. |
| 8.5–11 s | Original p, o, p strokes draw on; import regions briefly identify the letters. |
| 11–14.5 s | The first p moves into a macro editing view; Bézier handles reshape its shoulder. It then shrinks toward its position in the word. |
| 14.5–16.65 s | The actual exported font demonstrates spacing and kerning. |
| 16.65–18.35 s | The word contracts into a TrueType file. |
| 18.35–20.15 s | The file unfolds into an Ink Library specimen. The explicit caption describes adding the exported folder. |
| 20.15–24 s | That specimen expands into a coral music poster in Spaces. |
| 24–28 s | Existing app icon, Typefield wordmark and “Your type, all together.” |

Short text reveals settle in 260 ms. Major object transformations have their own timing and continue across scene boundaries. The three workspace names are centered as one measured group, with equal gaps between the text bounds. There are no pills, dot separators or uppercase marketing labels. Core Text supplies native kerning; alignment uses glyph bounds and explicit baselines.

## Product accuracy and asset provenance

This is a stylized product film, not a screen recording or a pixel-accurate interface demonstration. The workflow was verified during revision 3 in the isolated Typefield Interaction QA application, version 0.59.6, with a separate data container: import original artwork, edit outlines, export TrueType, add the exported folder to Library and create a Spaces typeboard using that font. Revision 4 does not imply automatic font completion, automatic Library import or live synchronization.

The original artwork is `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. The animation follows its p and o strokes. The macro editing illustration uses smooth vector outlines derived from those original strokes, with an animated shoulder adjustment; it is an illustration of editing, not a capture of the app's exact imported nodes. The spacing, file, returned Library specimen and final poster render `assets/v3/Ink.ttf`, the actual app-generated export. That fixture contains n, o, p, i, j and a blank space, and the film only uses its supported letters. Its hand-drawn irregularity is retained. It is not a complete alphabet or a user's font. The renderer reads the file through Core Graphics without system-wide font registration.

Other specimens use the Mac's installed Helvetica Neue, Baskerville, Didot, Futura and Menlo. Marketing text uses Helvetica Neue. The end card uses the existing app icon from `Resources/Assets.xcassets/AppIcon.appiconset/`. The older screenshot assets remain for revision 3 reproducibility; this renderer does not load them.

## Reproduce

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits heading bounds and the centered navigation group, renders 30 composition/transition samples and a 60 fps master, creates the H.264/yuv420p 30 fps delivery, extracts an end-card poster and decodes the full delivery. Outputs are ignored by Git. Rendering is deterministic; no random seed applies.

For a particular frame, run `marketing/launch/renders/render --frame 12.2`. `--stills` renders the predefined review set; `--audit` performs the layout and font checks.

## Scope and validation

Marketing assets only. No app release or data migration is involved. Production Library data, app source, installed application and the paused research edits are outside this change. Website, vertical adaptation, music and public posting remain separate work.

Swift compilation, renderer audit, shell syntax and whitespace checks pass. Thirty still samples were generated; representative compositions and transition frames were inspected at full resolution, followed by eight decoded video samples. The export transition received a further contrast correction and the film was rendered and decoded again. The final delivery is 840 frames at 30 fps; the master is 1,680 frames at 60 fps. Both are 1920 × 1080 and exactly 28 seconds. The final delivery decodes without errors. The interrupted research diff remains byte-for-byte unchanged. Native app tests were not rerun because app code did not change. Visual approval remains with the user.
