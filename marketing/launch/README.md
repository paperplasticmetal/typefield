# Typefield launch film — landscape review cut

26 seconds, 1920 × 1080 (16:9), silent. The 60 fps master retains smooth motion for editing; the 30 fps H.264 delivery is intended for review and social posting after approval. The music bed is deliberately empty. No website, portrait adaptation, posting, or app release is included.

## Creative direction

Warm porcelain, charcoal, sage, and a small orange editing accent. Large typography, an original geometric lowercase **a**, animated Bézier controls, gently moving compositions, and the existing Typefield app icon. The same letter travels from the opening into the editor and into its Library card. A final three-workspace view makes the relationship explicit before the icon/wordmark close.

The interfaces are simplified motion illustrations of existing capabilities, not screen recordings or pixel-exact replicas. **Atelier** is a fictional demonstration project, not a shipped font or an AI-generated font claim. Its original glyph artwork is created by this renderer. Helvetica Neue, Baskerville, and Menlo are rendered through the local system; no font binaries are copied or distributed. No private project, font list, screenshot, or user library data is used in the film.

## Edit map

| Time | Message | Motion / product evidence |
| --- | --- | --- |
| 0–3.3 s | Good type. Starts here. | Large geometric letter, typographic reveal, editing guides |
| 3.3–8.3 s | Make it yours. | Letter moves into the illustrated Letterform Editor; curve controls move; drawing, import, nodes, spacing and kerning |
| 8.3–12.7 s | Every font. In its place. | Letter moves into the fictional Atelier card; collection cards arrive; explicit Export .ttf → Add to Library |
| 12.7–18.3 s | Type comes to life. | Website and poster typeboards, Atelier font selection, real-layout context |
| 18.3–22.1 s | Three spaces. One creative flow. | Letterform Editor → Library → Spaces; animated connecting line |
| 22.1–26 s | Typefield. Make type. Make it yours. | Existing app icon, wordmark, Made for Mac close |

## Reproduce

From the repository root, run:

```sh
bash marketing/launch/render.sh
```

Requires macOS, Apple Swift/AppKit/CoreText, and the existing Homebrew FFmpeg installation at `/opt/homebrew/bin/ffmpeg`. No added packages, fonts, network services, or generative models are required. The renderer uses deterministic analytic animation, no random seed, and writes only `marketing/launch/renders/` plus the temporary Swift module cache. Run `marketing/launch/renders/render --stills` to regenerate ten review frames after compiling.

Generated media and the renderer executable stay in the ignored `renders/` directory. `Typefield-Launch-Landscape.mp4` is the delivery; `Typefield-Launch-Master-1080p60.mp4` is the editable-timeline source master. Make timing, copy, palette and scene changes in `render.swift`.

## Scope and validation

Based on the capabilities in repository revision `7067e6d` / installed Typefield 0.59.6. No missing-letter synthesis, automatic font installation, variable-font export, live cross-app synchronization, or public-release availability is advertised. The export/add step is explicit because creating a glyph does not automatically register a new Library font.

Validation covers Swift compilation, ten storyboard frames, decoded transition samples, complete FFmpeg decode, 16:9 dimensions, 26-second duration, frame counts, H.264/yuv420p output, and an end-card hold. App builds and installation are unrelated to this media-only change and are not run. Existing paused-research edits are preserved.
