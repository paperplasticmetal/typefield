# Typefield launch film — landscape revision 10

46 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v10.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v10.mp4`. Earlier local deliveries remain available. Revision 8 (40 seconds) is preserved in commit `e458bcc`; revision 9 (52 seconds) is preserved in `58d33ac`.

## Direction

A white stage carries the whole film. Neutral specimen cards, gray captions and coral artwork keep the palette restrained. Every opening specimen reads “Form” at the same point size, so the typeface itself supplies the variation. The opening now demonstrates sorting, named collections, shortlisting and A/B overlays before the selected font becomes a Spaces composition. A shared horizontal move takes the layouts into a drawing scene; the previous giant-F zoom and pause are removed. The drawn artwork becomes a PNG, an editable letter, a spaced word, an exported TrueType file, a Library specimen and a new Spaces poster.

The closing card contains only the existing app icon, Typefield, “Your type, all together” and “For Mac.” The platform line now sits closer to the tagline, and small optical corrections align the visible ink of all three text lines with the icon. The wordmark and tagline move 5 px left; “For Mac” moves 1 px right. The prior bounds-centered layout put their visual mass on different axes.

Primary references consulted for revision 4, retained as direction for this original composition:

- [Ordinary Folk — Webflow, A New Era of No Code](https://www.ordinaryfolk.co/project/webflow-a-new-era-of-no-code): continuity between objects, changes in scale and spatial layering.
- [BUCK — Notion, Think it. Make it.](https://buck.co/work/notion-think-it-make-it): telling the product story through creative material.
- [Ordinary Folk — Process](https://www.ordinaryfolk.co/process): resolving story and visual language before animation polish.
- [Ordinary Folk — Procreate Dreams](https://www.ordinaryfolk.co/project/procreate-dreams): a compact drawing-to-outcome story.

No reference footage, artwork, music or other third-party media was copied into the film.

## Story

| Time | Action |
| --- | --- |
| 0–3.3 s | Library specimens enter, sort alphabetically and hold for reading. |
| 3.3–6.3 s | Three specimens gather into an Editorial collection and settle. |
| 6.3–9.15 s | Two candidates move forward into a shortlist. |
| 9.15–12.45 s | Candidates merge into a same-baseline A/B overlay. The comparison holds for 1.9 seconds before the candidate clears. |
| 12.45–13.75 s | The same “Form” specimen expands into a Spaces editorial composition. |
| 13.75–17.8 s | The first composition holds before the second layout arrives; both then hold. |
| 17.8–18.9 s | The layouts move left as the drawing surface enters from the right. |
| 18.9–21.85 s | Pencil drawing runs for 2.12 seconds. The completed artwork holds for 0.68 seconds before export. |
| 21.85–25 s | The surface becomes Artwork.png. Fully visible import regions hold for 1.18 seconds before the file and other letters leave the first p in place. |
| 25–29.7 s | The p enters the editor. Its shoulder adjustment pauses for 0.5 seconds at the maximum bend, returns, then settles for 1.05 seconds before joining the word. |
| 29.7–32.7 s | Spacing and kerning retain their action speed. The finished word holds for 1.75 seconds. |
| 32.7–35.1 s | The word contracts into a TrueType file; the completed file holds for 1.7 seconds. |
| 35.1–37.75 s | The file unfolds into an Ink Library specimen and holds for 1.9 seconds. |
| 37.75–42 s | That specimen expands into the coral Spaces poster. |
| 42–46 s | The unchanged four-second end card settles by 42.58 s. |

Revision 10 is the pacing midpoint between revisions 8 and 9: each presentation-time knot is the arithmetic mean of the corresponding 40-second and 52-second cuts. It retains six seconds of added reading time over revision 8, trimming each added pause from revision 9 by half. Pencil drawing runs for 2.12 seconds instead of 1.82, and the curve return runs for 1.55 seconds instead of 1.35; these remain the only active-motion slowdowns. Title entrances and shared-object transfers retain their existing durations. Forward/inverse timing and every pacing boundary are checked by the renderer. Motion uses smooth quintic easing with zero endpoint velocity and acceleration. Headlines rise 22 px over 340 ms; the closing group rises 16 px. Paper shadows are compact. The artificial highlight stroke is removed from paper edges; the final specimen-to-coral transition uses one interpolated fill, eliminating the exposed white hairline. The pencil finishes each stroke before lifting and moving to the next. The drawn p keeps its original shape across the editor handoff before the visible adjustment begins. The specimen metadata persists through the Library-to-poster transition.

During app scenes, workspace names use equal 380 px columns centered at x=580, 960 and 1340. They are absent during the external drawing scene and on the final card. All three labels share a baseline and size. No pills, dot separators or uppercase marketing labels are used. Core Text supplies native kerning; alignment uses glyph bounds and explicit baselines. Transformed surfaces reserve the heading/subtitle area and stay above y=948 whenever navigation is visible.

## Product accuracy and asset provenance

This is a stylized product film, not a screen recording or an exact interface demonstration. The core import/edit/export/Library/Spaces round trip was verified during revision 3 in the isolated Typefield Interaction QA app, version 0.59.6, with separate data. Revision 6's Library claims were checked against the current implementation: Name A–Z/Z–A, Most styles and Category sorting; named collections; session shortlists; and same-baseline font overlays. The film does not claim that a shortlist automatically becomes a saved collection.

The drawing scene illustrates artwork made in an external drawing app using an iPad or a connected drawing tablet, exported as PNG and opened in the Mac Letterform Editor. PNG import is supported. These are examples of input tools, not an exclusive list of import sources. The film does not depict a Typefield iPad app, live synchronization or direct transfer of editable drawing-app layers.

Original artwork comes from `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. The macro editing illustration uses smooth outlines derived from its strokes, with an animated shoulder adjustment; it is not a capture of the exact imported nodes. The spacing, file, returned Library specimen and final poster render `assets/v3/Ink.ttf`, the actual app-generated export of the SVG fixture from revision 3. The PNG illustration is not a separately captured app export. That font contains n, o, p, i, j and space; the film only uses supported letters. It is not a complete alphabet or a user's font. Core Graphics reads it without system-wide font registration.

Other specimens use the Mac's installed Helvetica Neue, Baskerville, Didot, Futura and Menlo. Marketing text uses Helvetica Neue. The 88 px scene headlines now use Helvetica Neue Medium, increased from Regular; captions remain Regular. All scene headlines, artwork titles and the closing tagline omit trailing periods. The renderer verifies the resolved headline PostScript name is `HelveticaNeue-Medium` and audits widths using that actual face. The end card uses the existing icon in `Resources/Assets.xcassets/AppIcon.appiconset/`. Older screenshot assets remain for revision 3 reproducibility; this renderer does not load them.

## Reproduce and validate

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits heading bounds, equal navigation columns, font glyph availability, timing and sampled composition clearance, renders 40 review frames and the 60 fps master, then creates the H.264/yuv420p 30 fps delivery. Actual transformed paper bounds are checked on every one of the 2,760 master frames. The script extracts an end-card poster and decodes the full delivery. Outputs are ignored by Git; rendering is deterministic.

For one frame, run `marketing/launch/renders/render --frame 25`. `--stills` renders the predefined review set; `--audit` performs layout and font checks. The completed delivery is 1,380 frames at 30 fps, exactly 46 seconds. The master is 2,760 frames at 60 fps. Representative compositions, transition endpoints and decoded delivery samples receive visual review, including an independent read-only review. Revision 10 preserves the approved typography, layouts and white palette. Independent source review verified that all 40 timing knots are exact midpoints and that active transfers keep their duration. The full export passed duration, frame-count, no-audio, surface-clearance and decode checks. Eleven equivalent scene PNGs are byte-identical to revision 9. Six encoded frames were extracted, with representative comparison, editor and end-card compositions visually reviewed. Review stills are sampled at equivalent choreography positions with filenames showing their new presentation times. Private evidence is kept under `.context/qa-artifacts/launch-film-v10/`.

## Scope

Marketing files only. No application release, installation or data migration. Native app tests are not applicable because app code did not change. Production Library data and paused research edits are preserved. The user deferred music. Website, vertical adaptation and public posting remain separate work. Visual approval remains with the user.
