# Typefield launch film — landscape revision 9

52 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v9.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v9.mp4`. Earlier local deliveries remain available. Revision 8 source is preserved in commit `e458bcc`.

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
| 0–3.6 s | Library specimens enter, sort alphabetically and hold for reading. |
| 3.6–6.9 s | Three specimens gather into an Editorial collection and settle. |
| 6.9–10.1 s | Two candidates move forward into a shortlist. |
| 10.1–13.9 s | Candidates merge into a same-baseline A/B overlay. The comparison holds for 2.4 seconds before the candidate clears. |
| 13.9–15.2 s | The same “Form” specimen expands into a Spaces editorial composition. |
| 15.2–19.8 s | The first composition has more reading time before the second layout arrives; both then hold. |
| 19.8–20.9 s | The layouts move left as the drawing surface enters from the right. |
| 20.9–24.65 s | Pencil drawing is moderately slower. The completed artwork holds for 1.18 seconds before export. |
| 24.65–28.4 s | The surface becomes Artwork.png. Fully visible import regions hold for 1.78 seconds before the file and other letters leave the first p in place. |
| 28.4–33.95 s | The p enters the editor. Its shoulder adjustment pauses at the maximum bend, returns more slowly, then settles for 1.45 seconds before joining the word. |
| 33.95–37.45 s | Spacing and kerning retain their action speed. The finished word holds for 2.25 seconds. |
| 37.45–40.2 s | The word contracts into a TrueType file; the completed file holds for 2.05 seconds. |
| 40.2–43.3 s | The file unfolds into an Ink Library specimen and holds for 2.35 seconds. |
| 43.3–48 s | That specimen expands into the coral Spaces poster, with a longer final hold. |
| 48–52 s | The unchanged four-second end card settles by 48.58 s. |

Revision 9 adds 12 seconds of reading time through a monotonic presentation-time map over the approved choreography. Added holds occur after actions finish, rather than stretching transitions. Pencil drawing runs for 2.42 seconds instead of 1.82, and the curve return runs for 1.75 seconds instead of 1.35; these are the only active-motion slowdowns. Title entrances and shared-object transfers retain their existing durations. Forward/inverse timing and every pacing boundary are checked by the renderer. Motion uses smooth quintic easing with zero endpoint velocity and acceleration. Headlines rise 22 px over 340 ms; the closing group rises 16 px. Paper shadows are compact. The artificial highlight stroke is removed from paper edges; the final specimen-to-coral transition uses one interpolated fill, eliminating the exposed white hairline. The pencil finishes each stroke before lifting and moving to the next. The drawn p keeps its original shape across the editor handoff before the visible adjustment begins. The specimen metadata persists through the Library-to-poster transition.

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

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits heading bounds, equal navigation columns, font glyph availability, timing and sampled composition clearance, renders 40 review frames and the 60 fps master, then creates the H.264/yuv420p 30 fps delivery. Actual transformed paper bounds are checked on every one of the 3,120 master frames. The script extracts an end-card poster and decodes the full delivery. Outputs are ignored by Git; rendering is deterministic.

For one frame, run `marketing/launch/renders/render --frame 28.4`. `--stills` renders the predefined review set; `--audit` performs layout and font checks. The completed delivery is 1,560 frames at 30 fps, exactly 52 seconds. The master is 3,120 frames at 60 fps. Representative compositions, transition endpoints and decoded delivery samples receive visual review, including an independent read-only review. Revision 9 preserves the approved typography, layouts and white palette. Independent source review confirmed that every added hold is in a settled state and that the scene-time mapping preserves transfers and title entrances. The full export passed duration, frame-count, no-audio, surface-clearance and decode checks. Eleven equivalent scene samples are byte-identical PNGs to revision 8, confirming the visual composition is preserved. Six encoded samples of held states were extracted for review. Review stills are sampled at equivalent choreography positions with filenames showing their new presentation times. Private evidence is kept under `.context/qa-artifacts/launch-film-v9/`.

## Scope

Marketing files only. No application release, installation or data migration. Native app tests are not applicable because app code did not change. Production Library data and paused research edits are preserved. The user deferred music. Website, vertical adaptation and public posting remain separate work. Visual approval remains with the user.
