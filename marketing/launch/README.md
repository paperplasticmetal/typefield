# Typefield launch film — landscape revision 12

52 seconds, 1920 × 1080, silent. Delivery: `renders/Typefield-Launch-Landscape-v12.mp4` at 30 fps. Editing master: `renders/Typefield-Launch-Master-1080p60-v12.mp4`. Earlier local deliveries remain available. Revision 11 is preserved in commit `91b0267`.

## Direction

Typefield is a place to discover fonts, explore pairings and layouts, and develop your own type alongside your existing design tools. This revision replaces the finished-composition “Put it to work” section with a visible experiment: local body-font suggestions become three studies containing the same words. The studies initially share a Baskerville heading, then two heading faces change and one composition shifts to a left-aligned layout. The custom-font round trip returns to another pairing study, followed by an explicit layout-export handoff for Figma, Illustrator and InDesign.

The white stage, neutral cards, restrained coral artwork and native Core Text typography continue the approved visual direction. Every opening specimen reads “Form.” Headers use Helvetica Neue Medium at 88 px without trailing periods. Captions use Helvetica Neue Regular. Workspace names occupy equal 380 px columns centered at x=580, 960 and 1340, and disappear on the external drawing scene and final card. The end card preserves revision 11's shared x=960 center for the icon, wordmark, tagline and platform line.

Primary references consulted for revision 4, retained as direction for this original composition:

- [Ordinary Folk — Webflow, A New Era of No Code](https://www.ordinaryfolk.co/project/webflow-a-new-era-of-no-code): continuity between objects and spatial layering.
- [BUCK — Notion, Think it. Make it.](https://buck.co/work/notion-think-it-make-it): product stories told through creative material.
- [Ordinary Folk — Process](https://www.ordinaryfolk.co/process): resolving story and visual language before animation polish.
- [Ordinary Folk — Procreate Dreams](https://www.ordinaryfolk.co/project/procreate-dreams): a compact drawing-to-outcome story.

No reference footage, artwork, music or other third-party media was copied into the film.

## Story

| Time | Action |
| --- | --- |
| 0–3.3 s | Library specimens enter and sort alphabetically. |
| 3.3–6.3 s | Three specimens gather into an Editorial collection. |
| 6.3–9.15 s | Two candidates move into a shortlist. |
| 9.15–12.45 s | A same-baseline A/B overlay reveals differences in letterforms. |
| 12.45–16.45 s | The selected Baskerville specimen becomes an editorial study beside body-font suggestions from the Library. Helvetica Neue is highlighted as its partner. |
| 16.45–23 s | Three studies compare the same content with Helvetica Neue, Futura and Menlo body text. All start with Baskerville headings. B visibly changes its heading to Didot, C to Helvetica Neue, then B changes alignment. The final combinations hold together for over two seconds. |
| 23–24.1 s | The studies leave as the drawing surface enters in the same horizontal move. |
| 24.1–27 s | Artwork is drawn with an iPad or connected drawing tablet. |
| 27–29.8 s | The drawing becomes a PNG with identified letter regions; the first p remains for editing. |
| 29.8–33.7 s | An editable outline gains handles, changes shoulder curvature, then joins the word. |
| 33.7–36.2 s | Spacing and kerning adjust, followed by a reading hold. |
| 36.2–38.1 s | The word becomes an installable TrueType file. |
| 38.1–40.35 s | The exported font returns as a Library specimen. |
| 40.35–44.15 s | The custom font appears alongside supporting type in a coral poster study: “Your font, in good company.” |
| 44.15–48 s | A restrained selection outline precedes a layout-export file. Copy names Figma, Illustrator and InDesign and explains that text and shapes remain editable. |
| 48–52 s | The approved four-second end card: icon, Typefield, “Your type, all together” and “For Mac.” |

The Library retains revision 11's reading time. The new 10.55-second pairing passage replaces the 5.35-second composition passage. The drawing-to-Library loop is slightly tighter, and a 3.85-second export beat clarifies Typefield's place in a broader workflow. The longer runtime adds content rather than extending pauses. Quintic easing, shared object continuity and short title entrances remain. The timing map is monotonic and invertible; the renderer checks scene boundaries and transformed surface clearance.

## Product accuracy

This is a stylized product film, not a screen recording or a pixel-exact interface demonstration. Revision 12's claims were independently reviewed against the implementation at `91b0267`:

- **Library:** sorting by name, style count and category; named collections; session shortlists; same-baseline overlays. A shortlist is not presented as automatically becoming a saved collection.
- **Pairing suggestions:** the local catalog supplies role-aware candidates with Safe, Balanced and Expressive modes and explained rankings. A suggestion can be applied to a heading/body role. The film's candidate fonts are illustrative choices, not a recorded ranking or match percentages. See `Sources/FontPairingSuggestions.swift`, `Sources/FontPairing.swift` and `Sources/StudioView.swift`.
- **Comparison:** Spaces supports multiple canvases, duplication, layout editing and Quick A/B between compatible canvases. A/B/C in the film names three illustrative studies, not a separate formal A/B/C feature. The same content makes the pairing differences legible; visible later changes show manual experimentation.
- **Figma:** Editable Figma Layout exports all canvases in a typeboard as a package with JSON and a local development importer. Running the importer creates editable frames, text and rectangle shapes. See `Sources/LibraryExtras.swift` and `Resources/FigmaImport/README.md`.
- **Illustrator and InDesign:** selected canvases can export builder scripts, run manually in the target application to create editable documents. See `Sources/AdobeTypeSystem.swift` and the Typography Summary export controls in `Sources/StudioView.swift`.

The export scene represents a file handoff, not live synchronization or one-click direct transfer. It does not claim preserved nested object groups. Fonts must be available in the destination; editable exports omit image artwork and can reflow text. The pictured poster uses text and vector shapes rather than embedded image artwork. No Spaces SVG-export claim is made.

The drawing scene illustrates an external drawing app using an iPad or a connected drawing tablet, exported as PNG and opened in the Mac Letterform Editor. These are examples of input tools, not an exclusive list. It does not imply a Typefield iPad app or live tablet synchronization.

## Asset provenance

Original drawing artwork comes from `tests/fixtures/font-lab-artwork/handwriting-nopij.svg`. The editing macro uses smooth outlines derived from those strokes; it does not reproduce exact imported nodes. The spacing, file, returned Library specimen and poster render `assets/v3/Ink.ttf`, an actual app-generated export from the revision 3 isolated QA round trip. That font supports n, o, p, i, j and space; the film only uses supported letters. The PNG illustration is not a separate captured app export. No user font or production library data was used.

Other specimens use installed Helvetica Neue, Baskerville, Didot, Futura and Menlo. Core Graphics loads the fixture font without system-wide registration. The icon is the existing asset in `Resources/Assets.xcassets/AppIcon.appiconset/`. Earlier screenshot assets remain for revision 3 reproducibility; this renderer does not use them.

## Reproduce and validate

```sh
bash marketing/launch/render.sh
```

Requires macOS, Swift/AppKit/CoreText and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The script compiles the renderer, audits font resolution, heading widths, equal navigation columns, fixture glyph availability, forward/inverse timing and sampled surface clearance. It renders 43 review frames, then the 60 fps master and H.264/yuv420p 30 fps delivery, extracts an end-card poster and decodes the complete delivery. Every master frame enforces heading/footer surface clearance. Outputs are ignored by Git.

For a single frame: `marketing/launch/renders/render --frame 19.5`. `--stills` renders the review set and `--audit` performs the renderer checks. Verified master: 3,120 frames at 60 fps. Delivery: 1,560 frames at 30 fps. Both are exactly 52 seconds, 1920 × 1080 and silent. Compilation, renderer checks, all-frame surface clearance, full delivery decode, frame counts and no-audio checks passed. Ten encoded samples were extracted and the new pairing/comparison/export compositions visually reviewed. Independent source and still review found no remaining blockers. Adjacent surface samples at the suggestion-to-studies and studies-to-tablet boundaries were pixel-identical; the poster-to-export boundary differed by only 0.0013 mean channel values out of 255. Private product-claim, visual and export evidence is kept under `.context/qa-artifacts/launch-film-v12/`.

## Scope

Marketing files only. No application release, installation or data migration. Native app tests are not applicable because app code did not change. Production Library data and paused research edits are preserved. Music remains deferred; website, vertical adaptation and public posting are separate work.
