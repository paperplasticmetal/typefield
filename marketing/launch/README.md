# Typefield launch film — landscape revision 2

27 seconds, 1920 × 1080 (16:9), silent. `Typefield-Launch-Landscape-v2.mp4` is the 30 fps H.264 review delivery. `Typefield-Launch-Master-1080p60-v2.mp4` is the 60 fps master for subsequent editing. Both are generated in the ignored `renders/` directory. The first cut is retained locally in `renders/v1/`; its source is in commit `9e4deaa`.

## Revision direction

The second cut removes capsule-shaped feature labels, all-caps corner captions, faux window chrome, rounded UI cards, the website CTA, and the original all-caps closing subtitle. It uses a restrained porcelain/ink palette, a small rust editing accent, and a sage poster. The story is carried by one letterform rather than a sequence of disconnected cards.

The motion illustrations are not screen recordings. Atelier is a fictional demonstration project. Its consistent specimen is rendered from the Mac's Futura Medium: the same actual glyph outline, its actual control points, and naturally spaced word are reused throughout. This is a typographic stand-in, not an original font that was created or shipped in Typefield. Helvetica Neue and Baskerville provide the surrounding typography. No font binaries, personal fonts, user projects, or screenshots are bundled or read. The end uses the existing Typefield app icon.

## Typography and continuity

- Core Text's native pair kerning is retained; the previous universal `.kern` override is removed.
- Text uses explicit baselines and actual glyph-ink bounds for alignment. There is no font-size multiplier standing in for ascent or cap height.
- Main two-line phrases use 96 px type on 108 px baselines. Optical left edges align at x = 128; supporting text uses a small 3 px optical inset. Stage headings use 68 px. The wordmark uses 116 px medium.
- Specimen words retain their native glyph advances. The moving `a` is positioned from the very same font bounds and baseline as the other letters.
- One analytic outline trajectory spans opening, editing, Library, Spaces, workflow summary and icon handoff. Its joins have zero endpoint velocity. No wipe intersects a heading.
- Neighboring specimen letters appear after the `a` arrives. Surrounding artboards disappear before it leaves; the letter never has to pass through readable neighboring text.
- The closing icon and wordmark are centered from their visible bounds, with a stable final hold.

## Edit map

| Time | Story |
| --- | --- |
| 0–3.2 s | “It starts with a letter.” A large letter introduces the film; its control points appear. |
| 3.2–7.2 s | “Give it character.” A shoulder correction resolves into the final outline. Letterform Editor, curves, spacing and kerning are identified in sentence case. |
| 7.2–11.7 s | “Your font. Your library.” The letter settles into the Atelier specimen in a typographic Library list. Export/add steps remain explicit. |
| 11.7–19.5 s | “Put your type to work.” The same specimen moves onto a composition, then the camera pulls back for a second poster. A single caption identifies Spaces. |
| 19.5–22.8 s | “Three spaces. One flow.” The letter moves to the center with Letterform Editor → Library → Spaces beneath it. |
| 22.8–27 s | The letter gives way to the Typefield icon, wordmark, “Make it your own.” and “For Mac”. |

## Reproduce

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText, and the existing Homebrew FFmpeg installation at `/opt/homebrew/bin/ffmpeg`. No new packages or online services are needed. The source and its analytic animation are deterministic; no random seed applies. It writes only to `marketing/launch/renders/` and the temporary Swift module cache.

After compiling, `render --stills` produces 25 layout/transition frames, and `render --audit` verifies measured type bounds, all 1,620 outline positions, twelve trajectory joins, and the two native specimen-baseline matches. Edit copy, timing and composition in `render.swift`.

## Review and validation

The revision was checked through 25 storyboard/transition frames, larger views around specimen arrivals and departures, and decoded samples of the delivered video. This exposed and corrected a departing-letter collision and a Library baseline drift. The automated audit passes. FFmpeg decodes the complete delivery without errors; ffprobe confirms 1920 × 1080, H.264/yuv420p, 27 seconds and 810 frames at 30 fps. The master has 1,620 frames at 60 fps. These checks support geometry and encoding correctness; they do not replace the user's design approval.

Capabilities remain based on Typefield 0.59.6. No missing-letter synthesis, automatic font installation, live cross-app synchronization, variable-font export, or public availability is advertised. This is a marketing-only change: app code, versions and installation are unchanged. Existing paused research edits remain untouched. No website, vertical adaptation, music, or publishing action is included.
