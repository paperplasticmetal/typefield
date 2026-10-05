# Typefield launch film — landscape revision 3

27 seconds, 1920 × 1080, silent. The 30 fps delivery is `renders/Typefield-Launch-Landscape-v3.mp4`; the 60 fps editing master is `renders/Typefield-Launch-Master-1080p60-v3.mp4`. Previous deliveries remain locally available with their versioned filenames. Revision 2 source is in commit `b730184`.

## Story and pacing

The film opens in Library and demonstrates a complete, explicit workflow. Real app captures replace the fictional library and layouts. The selected Helvetica specimen appears in a Spaces typeboard; original handwriting is then imported, edited, exported as TrueType, added to Library and used in a second Spaces layout.

| Time | Action |
| --- | --- |
| 0–2.6 s | Find a font in Library. |
| 2.6–4.7 s | Select fonts and use the actual Create typeboard command. |
| 4.7–8.0 s | See the same font and preview text in a Spaces layout. |
| 8.0–10.0 s | Draw original letter artwork; the animation follows the fixture's actual strokes. |
| 10.0–12.7 s | Import and label the five drawn letters. |
| 12.7–16.1 s | Inspect editable nodes, Bézier handles, metrics and spacing. |
| 16.1–18.5 s | Export the actual outlines as Ink.ttf. |
| 18.5–21.2 s | Add the exported font folder to Library. |
| 21.2–24.5 s | Use that same font in a Spaces poster. |
| 24.5–27.0 s | Typefield icon, wordmark and closing line. |

Headlines settle in 240 ms, product frames in 380 ms and the workflow indicator in 320 ms. There are no opacity fades. Text uses Core Text's native kerning, measured ink bounds and explicit baselines. The persistent three-space indicator identifies the current workspace without pills or dot separators. Marketing copy is sentence case; any uppercase text inside the app is part of an actual layout template.

## Capture and font provenance

Seven cropped product states in `assets/v3/` were captured from the existing isolated Typefield Interaction QA application, version 0.59.6, using its separate data container. The film animates those captures; it is not a continuous screen recording. Unrelated QA project lists and full raw captures are not included in the source assets.

The original artwork is `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. Its five glyphs were imported through the real artwork review sheet into a disposable Ink project, then exported through the app's TrueType exporter. `assets/v3/Ink.ttf` is that generated fixture font, containing n, o, p, i, j and a blank space. It is not a user's font or a complete alphabet. The film renders only supported characters from it. The renderer reads it directly through Core Graphics; it does not install or register it system-wide.

The exported folder was added to the QA Library, the family was labeled Ink using Library's family editor, and a typeboard was created from that font. The captured poster shows the imported letters spelling “pin.” Spaces retains the exporter's original internal font name in its chooser. The stylized file drawing at 16.1 s illustrates this verified export step. It does not imply automatic Library import, automatic font completion or live synchronization.

Helvetica Neue supplies the marketing typography and uses the Mac's installed font. The closing icon is the existing Typefield app icon. No external media, music or online generation service is required.

## Reproduce

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The included product crops and generated fixture font make normal rendering reproducible. `render --prepare-assets` is an optional maintenance step requiring the local raw QA capture bundle in `renders/v3-captures/`; normal rendering does not require that bundle.

The script compiles the renderer, audits measured heading bounds and capture dimensions, renders 22 still samples and a 60 fps master, creates the 30 fps H.264/yuv420p delivery, extracts a closing poster and decodes the entire delivery. Outputs and raw captures are ignored by Git. Animation is deterministic; no random seed applies.

## Scope

This revision changes marketing assets only. App source, versions, canonical installation, production Library data and paused letterform research edits are unchanged. The QA-only font folder and demo projects remain available for later capture refinements. The website, vertical adaptation, music and public posting are separate work.

## Validation for this cut

The renderer audit and shell syntax check pass. All 22 layout/transition samples were generated; representative scenes and six decoded video frames were inspected. A clipped export menu was replaced with the font-file animation. The final H.264 delivery decodes without errors and contains 810 frames at 30 fps, 1920 × 1080, for exactly 27 seconds. The master contains 1,620 frames at 60 fps. The original research-file diff was compared byte for byte and remains unchanged. Native app tests were not rerun because app code was not changed. Design approval remains with the user.
