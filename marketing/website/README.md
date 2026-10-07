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
- Native dialog for the launch film; closing the film pauses playback.
- FAQ disclosures, reduced-motion support, keyboard focus states, and responsive layouts.
- One-action header navigation and a dedicated `/download/` page. The private beta uses a direct GitHub Release asset link and explains macOS's per-app Open Anyway flow.
- No public download, price, email collection, or invented signup backend.

## Assets

`typefield-film.mp4` and `film-poster.png` are the approved v16 launch assets from `marketing/launch/renders/`. The app screenshots are matched 2480 × 1764 Light mode captures from a disposable QA profile. Library uses only system fonts (Courier New, Georgia, Helvetica, and Times New Roman); Spaces uses the included Website canvas; Letterform Editor uses the app's synthetic handwriting example. Captures exclude the pointer and private projects. The site shows a focused crop on small screens.

`website-layout.png` and `website-layout.pdf` are a real export of the included Spaces Website canvas. The validated source is stored privately under `.context/qa-artifacts/spaces-template-polish-0594/previews/`. Only the sample PNG and PDF are published. The Figma compatibility mark follows Figma's public brand guidance; Adobe product names are text because third-party use of Adobe product icons requires permission. No proprietary font binaries are distributed; the page uses system font stacks.

## Hosting

The existing Site identity is in `.openai/hosting.json`. Keep it unchanged. The draft is owner-private. The future `typefield.app` domain is not connected.

The Sites workflow uses the ignored `.sites-checkout/` deployment mirror so it does not change this app repository's Git metadata. For later edits, open that same Site using its persisted ID, reconcile its source, and keep the canonical files here synchronized before publishing. Never create a second Site for this draft.

## V1 verification

- JavaScript syntax passed.
- Local HTTP and all referenced static assets checked.
- Desktop at 1440px and mobile at 390px visually inspected, with no horizontal document overflow.
- Workspace click and keyboard selection, type editing, face selection, spacing, reset, film playback/pause, film dialog/Escape, and FAQ expansion checked in the browser.

App runtime files and paused letterform experiments are unchanged. Native app tests are not applicable to this static website change.

## Typography and copy refinement

- Approved hero: “Quite the character.” Product description: “Organize your fonts. Try them in context. Make your own.”
- Removed the earlier headline and closing slogans from page copy and metadata. The launch film now uses revision 16, including the approved tagline.
- Enabled native font kerning; reduced excessive negative tracking, opened headline leading, and separated specimen pairs at narrow widths.
- Raised small secondary labels to 12px and improved mobile button/body spacing.
- Long live specimens now scale to remain visible; serif, sans, and mono controls retain independent tracking behavior.
- Inspected 320px, 390px, 820px, and 1440px layouts. No horizontal document overflow or clipped heading boxes. Verified long mono sample, spacing reset, and approved copy in the rendered DOM.

## Launch film revision 16

Before the soundtrack update, the site video and poster were byte-identical to the revision 16 delivery and end-card files in `marketing/launch/renders/`. Video metadata: 59.5 seconds, 1920 × 1080, H.264, 30 fps, silent. Versioned asset URLs prevent reuse of the previous cached film. The UI rounds the duration to one minute.

## Supporting-copy cleanup

Preserved every h1, h2, and h3 verbatim. Removed decorative eyebrow lines, redundant hero workspace labels, section mottos, playground filler, closing support copy, and the footer slogan. Retained feature descriptions, actual workspace identifiers, and useful control instructions. Use fewer subheaders going forward; each supporting label should identify something or explain an action.

## Player, motion, and soundtrack

The film opens in a near-viewport-width paper surface with no visible title or caption. Custom keyboard-accessible controls provide play/pause, seeking, mute, fullscreen, and close. Controls fade during playback and stay visible when paused or keyboard-focused. The native video controls remain the fallback before JavaScript enhancement. Playback begins only after a user action.

Motion takes inspiration from Graphical's changing type and responsive controls: staggered specimen entrance, spring-like hover/click movement, clickable typeface changes, workspace transitions, and one-time section entrances. It does not copy Graphical code or artwork. CSS and JavaScript both honor reduced motion. No endless scroll effects or automatic audio.

The film's visual stream is revision 16, unchanged. A separate music edit is generated at `marketing/launch/renders/Typefield-Launch-Landscape-v16-music-draft.mp4`; the approved silent delivery remains intact.

### Music provenance

- Track: Kraft Twerk, by Alejandro Magaña (A. M.).
- Source: https://mixkit.co/free-stock-music/electronic/
- Original asset: https://assets.mixkit.co/music/115/115.mp3
- License: Mixkit Stock Music Free License, https://mixkit.co/license/#musicFree
- Terms: https://mixkit.co/terms/
- Retrieved October 5, 2026, Pacific time.
- License permits use within commercial web/social video and online advertisements. Do not distribute this track as standalone stock music, register it in a rights-management service, or assume the same license permits games or broadcast use.
- Source SHA-256: `9de6760a1b3d36f8ea6e9e7106a05b5d63a9a4327ee888f9f396a6ed43c86295`.
- Music-edit SHA-256: `a78f92ee44ca96711675e0f0d020f133e283594642bb5a980337ba93abe399c0`.
- Raw music and saved license evidence remain local in `.context/qa-artifacts/website-motion/`. Only the music synchronized into the film is distributed with the site.

Reproduction from repository root, using the locally downloaded source:

```sh
/opt/homebrew/bin/ffmpeg -y -i marketing/launch/renders/Typefield-Launch-Landscape-v16.mp4 \
  -i .context/qa-artifacts/website-motion/music/kraft-twerk.mp3 \
  -map 0:v:0 -map 1:a:0 -t 59.5 -c:v copy \
  -af 'atrim=duration=59.5,asetpts=PTS-STARTPTS,loudnorm=I=-18:TP=-1.5:LRA=9,afade=t=in:st=0:d=0.35,afade=t=out:st=57:d=2.5' \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart \
  marketing/launch/renders/Typefield-Launch-Landscape-v16-music-draft.mp4
```

Validation: JavaScript syntax, complete media decode, 59.5-second H.264/AAC stream checks, desktop and mobile player layout, play/pause, mute, seeking, fullscreen entry/exit, close/pause behavior, specimen typeface switching, and workspace transition tested. Browser error log was empty. Music selection used the source's genre metadata; automated playback was verified, but subjective audio audition is left to the user.

## Website detail and Cloudflare deployment

The workspace tabs now list specific tasks, and the page explains the file-based Figma, Illustrator, InDesign, PDF, and developer handoffs. Motion reveals content within each section, with restrained hover and focus responses. JavaScript and CSS both respect reduced motion.

Cloudflare Pages project `typefield` is live at https://typefield.pages.dev/. It is deployed by direct upload from `marketing/website/dist` on the `codex/typefield-website` branch. Cloudflare has no Git connection to this repository. For updates, run the relevant checks, commit and push that branch, then upload the current `dist` folder to the same Pages project and verify the live site. The earlier owner-private Site remains a separate draft deployment. Connect `typefield.app` after the domain is purchased.

## Showcase refinement, October 6, 2026

- Replaced the three mismatched dark screenshots and synthetic window bar with matched Light mode captures. Mobile previews focus on the relevant app content.
- Kept the three workspace actions in equal-width columns with shorter, more useful copy. Small screens stack them with equal spacing.
- Added a real Spaces website-layout export as a full-size image preview with a separate vector PDF download, plus precise Figma, Illustrator, InDesign, PDF, and token handoff descriptions. The Figma importer and Adobe builder scripts are file-based workflows, not live sync.
- Kept the latest approved launch film unchanged.
- Verified JavaScript syntax, all static asset responses, responsive layout at 320px, 390px, and 1280px, no horizontal overflow, and workspace tab/caption/link behavior. Native app runtime files are unchanged.

## Private beta download

The header and closing action lead to `/download/`. The beta is an ad hoc signed macOS app distributed without Developer ID signing or notarization. The page links directly to its versioned private GitHub Release DMG and explains the first-open flow: try to open the installed app, then use System Settings → Privacy & Security → Open Anyway if macOS blocks it. Apple documents this per-app exception at https://support.apple.com/en-us/102445. The app itself has no account or license-key gate.

The `paperplasticmetal/typefield` GitHub repository is private. Invited testers must have GitHub access; a website link cannot bypass repository authentication. The feedback and bug-report links on the site open separate issue templates in that repository. For each new beta, update the download page with the exact asset URL and release details, then redeploy Cloudflare Pages. Verify the direct link while signed in as an invited tester, including on a clean Mac. Keep the release private; do not change repository visibility to make the asset downloadable without authentication.

## Social sharing preview

The 1200 × 630 `dist/assets/social-preview-v1.png` follows the supplied Typefield composition: paper background, upper-left wordmark, large two-line headline, and coral period. The image is generated with the system Helvetica Neue font; no font binary is bundled. To regenerate on macOS with Pillow installed, run `python3 marketing/website/render-social-preview.py` from the repository root.

Both the homepage and download page use absolute Open Graph and X large-card image URLs. The revisioned image filename helps when sharing services cache a previous preview. Update the image URLs and `og:url` values when `typefield.app` becomes the canonical domain.
