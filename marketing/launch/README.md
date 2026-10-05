# Typefield launch film — landscape revision 5

30 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v5.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v5.mp4`. Earlier local deliveries remain available. Revision 4 source is preserved in commit `d4aecc2`.

## Direction and research

This cut retains revision 4's animated typography, original drawings, dimensional paper planes and storyline, with more time to read the key actions and a stricter layout and motion pass. A selected Library specimen becomes a Spaces composition. A drawn letter then becomes an editable outline, joins a spaced word, contracts into a TrueType file, returns to Library and expands into another composition. The artwork carries the connections; short captions name the actual product steps.

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
| 8.5–11.55 s | Original p, o, p strokes draw on; import regions remain visible long enough to read before the other letters exit. |
| 11.55–15.4 s | The first p moves into a macro editing view; Bézier handles reshape its shoulder. It then moves into the word and blends into the actual exported outline. |
| 15.4–17.9 s | The actual exported font demonstrates spacing and kerning, followed by a settled reading pause. |
| 17.9–19.95 s | The word contracts into a TrueType file; the file remains readable before the next step. |
| 19.95–22.15 s | The file unfolds into an Ink Library specimen. The explicit caption describes adding the exported folder. |
| 22.15–26 s | That specimen expands into a coral music poster in Spaces; its small details persist through the transition. |
| 26–30 s | Existing app icon, unchanged Typefield wordmark and “Your type, all together.” The full end card settles by 26.65 s. |

The extra two seconds are concentrated on drawing/import, editing, spacing, export and the Library return. The timing map preserves the original choreography while lengthening readable states and easing a few of the fastest moves. The opening and four-second end card retain their durations.

Headlines now rise only 22 px over 340 ms instead of emerging through a tall clipping mask. The end-card wordmark uses the same restrained entrance. The illustrated outline becomes the real exported outline before the spacing scene begins. The Library card's small labels and rule carry through to the poster transformation, eliminating the prior one-frame discontinuity.

The three workspace names use equal 380 px columns centered at x=580, 960 and 1340. Spaces is exactly on the frame's center axis, both during the film and on the end card. All three labels share a baseline and font size. There are no pills, dot separators or uppercase marketing labels. Core Text supplies native kerning; alignment uses glyph bounds and explicit baselines.

The opening and returning specimens enter above the navigation band. The secondary coral poster's position and scale keep it clear of both captions and navigation. Captions disappear before its deliberate full-screen expansion starts. Shadows are more compact, and the drawing scene has stronger text contrast and one explanatory caption rather than a repeated import label. Transformed-corner checks enforce a paper bottom no lower than y=948 whenever navigation is present; the subtitle scenes also reserve the top caption area.

## Product accuracy and asset provenance

This is a stylized product film, not a screen recording or a pixel-accurate interface demonstration. The workflow was verified during revision 3 in the isolated Typefield Interaction QA application, version 0.59.6, with a separate data container: import original artwork, edit outlines, export TrueType, add the exported folder to Library and create a Spaces typeboard using that font. The film does not imply automatic font completion, automatic Library import or live synchronization.

The original artwork is `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. The animation follows its p and o strokes. The macro editing illustration uses smooth vector outlines derived from those original strokes, with an animated shoulder adjustment; it is an illustration of editing, not a capture of the app's exact imported nodes. The spacing, file, returned Library specimen and final poster render `assets/v3/Ink.ttf`, the actual app-generated export. That fixture contains n, o, p, i, j and a blank space, and the film only uses its supported letters. Its hand-drawn irregularity is retained. It is not a complete alphabet or a user's font. The renderer reads the file through Core Graphics without system-wide font registration.

Other specimens use the Mac's installed Helvetica Neue, Baskerville, Didot, Futura and Menlo. Marketing text uses Helvetica Neue. The end card uses the existing app icon from `Resources/Assets.xcassets/AppIcon.appiconset/`. The older screenshot assets remain for revision 3 reproducibility; this renderer does not load them.

## Reproduce

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits heading bounds, equal navigation columns, timing and transformed card clearance across all 1,800 output frames, renders 33 composition/transition samples and a 60 fps master, creates the H.264/yuv420p 30 fps delivery, extracts an end-card poster and decodes the full delivery. Outputs are ignored by Git. Rendering is deterministic; no random seed applies.

For a particular frame, run `marketing/launch/renders/render --frame 12.2`. `--stills` renders the predefined review set; `--audit` performs the layout and font checks.

## Scope and validation

Marketing assets only. No app release or data migration is involved. Production Library data, app source, installed application and the paused research edits are outside this change. Website, vertical adaptation, music and public posting remain separate work.

Swift compilation, renderer audit, shell syntax and whitespace checks pass. All 1,800 output frame times pass the transformed-paper clearance check; the lowest checked edge is y=941.36, clear of the navigation text beginning near y=1006. Equal column spacing, center alignment, monotonic retiming and the four-second end card are checked. Thirty-three still samples were rendered; representative compositions and handoffs were inspected, with an independent read-only review of the source and four key stills. Six decoded final-video samples were also inspected. A delivery pixel-format typo was corrected before the successful final encode. The H.264/yuv420p delivery decodes without errors: 900 frames at 30 fps, 1920 × 1080, exactly 30 seconds. The master contains 1,800 frames at 60 fps. The interrupted research diff remains byte-for-byte unchanged. Native app tests were not rerun because app code did not change. Visual approval remains with the user.
