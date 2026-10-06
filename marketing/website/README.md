# Typefield website / draft v1

A buildless, responsive marketing site. Canonical source is `dist/`; there is no install or build step.

## Local preview

```sh
cd marketing/website
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open `http://127.0.0.1:4173/`. Check JavaScript with `node --check dist/app.js`.

## Design and behavior

Use sentence-case headings and labels. Do not use all-caps headings, dot separators between text, or em dashes.

- Warm paper, charcoal, coral, large typography, generous campaign panels. Work Louder is the main reference for presentation quality, with editorial influences from Eames and Ableton.
- Three accessible workspace tabs with actual app views, arrow/Home/End keyboard support.
- Editable type study with system serif/sans/mono, letter spacing, and reset. This is a browser demonstration, not an embedded app.
- Native dialogs for the launch film and release status; closing the film pauses playback.
- FAQ disclosures, reduced-motion support, keyboard focus states, and responsive layouts.
- Honest prelaunch state: no public download, price, email collection, or invented signup backend.

## Assets

`typefield-film.mp4` and `film-poster.png` are the approved v16 launch assets from `marketing/launch/renders/`. App screenshots are the disposable v3 marketing fixtures, not private user libraries. The icon comes from the app asset catalog. No proprietary font binaries are distributed; the page uses system font stacks.

## Hosting

The existing Site identity is in `.openai/hosting.json`. Keep it unchanged. The draft is owner-private. The future `typefield.app` domain is not connected.

The Sites workflow uses the ignored `.sites-checkout/` deployment mirror so it does not change this app repository's Git metadata. For later edits, open that same Site using its persisted ID, reconcile its source, and keep the canonical files here synchronized before publishing. Never create a second Site for this draft.

## V1 verification

- JavaScript syntax passed.
- Local HTTP and all referenced static assets checked.
- Desktop at 1440px and mobile at 390px visually inspected, with no horizontal document overflow.
- Workspace click and keyboard selection, type editing, face selection, spacing, reset, film playback/pause, release dialog/Escape, and FAQ expansion checked in the browser.

App runtime files and paused letterform experiments are unchanged. Native app tests are not applicable to this static website change.

## Typography and copy refinement

- Approved hero: “Quite the character.” Product description: “Organize your fonts. Try them in context. Make your own.”
- Removed the earlier headline and closing slogans from page copy and metadata. The launch film now uses revision 16, including the approved tagline.
- Enabled native font kerning; reduced excessive negative tracking, opened headline leading, and separated specimen pairs at narrow widths.
- Raised small secondary labels to 12px and improved mobile button/body spacing.
- Long live specimens now scale to remain visible; serif, sans, and mono controls retain independent tracking behavior.
- Inspected 320px, 390px, 820px, and 1440px layouts. No horizontal document overflow or clipped heading boxes. Verified long mono sample, spacing reset, and approved copy in the rendered DOM.

## Launch film revision 16

The site video and poster are byte-identical to the revision 16 delivery and end-card files in `marketing/launch/renders/`. Video metadata: 59.5 seconds, 1920 × 1080, H.264, 30 fps, silent. Versioned asset URLs prevent reuse of the previous cached film. The UI rounds the duration to one minute.
