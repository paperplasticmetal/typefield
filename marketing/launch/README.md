# Typefield launch film — landscape revision 6

40 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v6.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v6.mp4`. Earlier local deliveries remain available. Revision 5 source is preserved in commit `e1fdaf5`.

## Direction

A single warm ochre stage carries the whole film. Cream specimens and coral artwork supply contrast without changing the full-screen background. The opening now demonstrates sorting, named collections, shortlisting and A/B overlays before the selected font becomes a Spaces composition. A shared horizontal move takes the layouts into an iPad drawing scene; the previous giant-F zoom and pause are removed. The drawn artwork becomes a PNG, an editable letter, a spaced word, an exported TrueType file, a Library specimen and a new Spaces poster.

The closing card contains only the existing app icon, Typefield, “Your type, all together.” and “For Mac.” Its centered group has been resized and spaced for the removal of the workspace labels.

Primary references consulted for revision 4, retained as direction for this original composition:

- [Ordinary Folk — Webflow, A New Era of No Code](https://www.ordinaryfolk.co/project/webflow-a-new-era-of-no-code): continuity between objects, changes in scale and spatial layering.
- [BUCK — Notion, Think it. Make it.](https://buck.co/work/notion-think-it-make-it): telling the product story through creative material.
- [Ordinary Folk — Process](https://www.ordinaryfolk.co/process): resolving story and visual language before animation polish.
- [Ordinary Folk — Procreate Dreams](https://www.ordinaryfolk.co/project/procreate-dreams): a compact drawing-to-outcome story.

No reference footage, artwork, music or other third-party media was copied into the film.

## Story

| Time | Action |
| --- | --- |
| 0–3 s | Library specimens enter and sort alphabetically. The caption also names style-count and category sorting. |
| 3–5.7 s | Three specimens gather into an Editorial collection. |
| 5.7–8.2 s | Two candidates move forward into a shortlist. |
| 8.2–11 s | The candidates share a plate and baseline for a teal/orange A/B overlay; Baskerville remains as the selection. |
| 11–12.3 s | The same “Form” specimen expands into a Spaces editorial composition. |
| 12.3–15.8 s | A second Spaces layout arrives and settles. |
| 15.8–16.9 s | Both layouts move left as the iPad drawing surface enters from the right. |
| 16.9–19.05 s | A visible pencil draws original p, o, p strokes on the tablet. |
| 19.05–21.6 s | The surface becomes Artwork.png; the caption explains exporting PNG and opening it in Letterform Editor. Import regions appear, then the file and other letters leave the first p in place. |
| 21.6–25.45 s | The p moves into an editing view. Handles arrive, its shoulder is adjusted, then the outline blends into the actual exported glyph. |
| 25.45–27.95 s | The exported font demonstrates spacing and kerning with a settled reading pause. |
| 27.95–30 s | The word contracts into a readable TrueType file. |
| 30–32.2 s | The file unfolds into an Ink Library specimen; the caption explicitly describes adding the exported folder. |
| 32.2–36 s | That specimen expands into a coral music poster in Spaces. |
| 36–40 s | The simplified Typefield end card settles by 36.58 s. |

Motion uses smooth quintic easing with zero endpoint velocity and acceleration. Headlines rise 22 px over 340 ms; the closing group rises 16 px. Paper shadows are compact. The pencil finishes each stroke before lifting and moving to the next. The drawn p keeps its original shape across the editor handoff before the visible adjustment begins. The specimen metadata persists through the Library-to-poster transition.

During app scenes, workspace names use equal 380 px columns centered at x=580, 960 and 1340. They are absent while drawing on iPad and on the final card. All three labels share a baseline and size. No pills, dot separators or uppercase marketing labels are used. Core Text supplies native kerning; alignment uses glyph bounds and explicit baselines. Transformed surfaces reserve the heading/subtitle area and stay above y=948 whenever navigation is visible.

## Product accuracy and asset provenance

This is a stylized product film, not a screen recording or an exact interface demonstration. The core import/edit/export/Library/Spaces round trip was verified during revision 3 in the isolated Typefield Interaction QA app, version 0.59.6, with separate data. Revision 6's Library claims were checked against the current implementation: Name A–Z/Z–A, Most styles and Category sorting; named collections; session shortlists; and same-baseline font overlays. The film does not claim that a shortlist automatically becomes a saved collection.

The iPad scene illustrates artwork drawn in an external drawing app, exported as PNG and opened in the Mac Letterform Editor. PNG import is supported. It does not depict a Typefield iPad app, live synchronization or direct transfer of editable drawing-app layers.

Original artwork comes from `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. The macro editing illustration uses smooth outlines derived from its strokes, with an animated shoulder adjustment; it is not a capture of the exact imported nodes. The spacing, file, returned Library specimen and final poster render `assets/v3/Ink.ttf`, the actual app-generated export of the SVG fixture from revision 3. The PNG illustration is not a separately captured app export. That font contains n, o, p, i, j and space; the film only uses supported letters. It is not a complete alphabet or a user's font. Core Graphics reads it without system-wide font registration.

Other specimens use the Mac's installed Helvetica Neue, Baskerville, Didot, Futura and Menlo. Marketing text uses Helvetica Neue. The end card uses the existing icon in `Resources/Assets.xcassets/AppIcon.appiconset/`. Older screenshot assets remain for revision 3 reproducibility; this renderer does not load them.

## Reproduce and validate

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits heading bounds, equal navigation columns, font glyph availability, timing and sampled composition clearance, renders 40 review frames and the 60 fps master, then creates the H.264/yuv420p 30 fps delivery. Actual transformed paper bounds are checked on every one of the 2,400 master frames. The script extracts an end-card poster and decodes the full delivery. Outputs are ignored by Git; rendering is deterministic.

For one frame, run `marketing/launch/renders/render --frame 21.6`. `--stills` renders the predefined review set; `--audit` performs layout and font checks. The completed delivery is 1,200 frames at 30 fps, exactly 40 seconds. The master is 2,400 frames at 60 fps. Representative compositions, transition endpoints and decoded delivery samples receive visual review, including an independent read-only review. Private evidence is kept under `.context/qa-artifacts/launch-film-v6/`.

## Scope

Marketing files only. No application release, installation or data migration. Native app tests are not applicable because app code did not change. Production Library data and paused research edits are preserved. Website, vertical adaptation, music and public posting remain separate work. Visual approval remains with the user.
