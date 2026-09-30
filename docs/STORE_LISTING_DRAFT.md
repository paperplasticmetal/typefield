# Typefield Mac App Store listing draft

Prepared for the release polish pass. This is review copy, not a submitted listing. Confirm the public name, bundle ID, contact information, and product claims before uploading it.

## Core copy

**Name:** Typefield

**Short line:** Explore fonts. Build type systems. Draw letters.

**Description:**

Typefield brings your fonts, layout experiments, and original letterforms into one Mac workspace.

In **Library**, browse the fonts available on your Mac and in folders you choose. Preview real text, filter by style and language support, compare families, and organize favorites, tags, and collections. Inspect font files, export originals, and review conservative repair options while keeping backups of any original you choose to repair.

In **Spaces**, try fonts together on responsive typeboards. Tune seven type roles, compare directions side by side, proof text in context, and export specifications for designers and developers. Portable project files and optional Figma and Adobe handoffs help move a type decision into the rest of your workflow. Font files are never bundled with those handoffs.

In **Letterform Editor**, draw or import your own artwork, refine editable vector outlines, adjust spacing and metrics, and test letters in words. Export selected SVG artwork or a static TrueType font containing the glyphs you have drawn.

Your library, text, and projects stay on your Mac. Browsing Google Fonts retrieves public preview font files from GitHub; an explicit download saves the selected font and its license locally. Typefield does not upload your fonts or preview text.

**Keywords for review:** fonts, typography, type design, font organizer, typeboard, specimen, letterform, font comparison. Trim and localize to the limits shown in App Store Connect.

## Listing assets and owner inputs

- **Support URL:** owner to provide a public support destination.
- **Privacy policy URL:** owner to approve and publish a public policy based on [current privacy copy](PRIVACY.md). Apple requires a privacy-policy URL for App Store listings ([Apple App Privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/)).
- **Production bundle ID and Apple Developer team:** owner to provide the registered values. The local `local.typefield.app` identifier is for development only.
- **Mac screenshots:** capture Library, Spaces, and Letterform Editor on a clean account with licensed fixture fonts and dummy projects. Apple currently accepts 16:10 Mac screenshots at 1280×800, 1440×900, 2560×1600, or 2880×1800 pixels ([Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)). Review every image for personal font names, folder names, project text, and permission alerts before upload.
- **Final checks:** confirm name clearance, age rating, privacy answers, export compliance, territories, pricing, review contact, and distribution-signed/TestFlight behavior. The local development build and mocked bridges are not substitutes for those checks.

## Accuracy notes

Missing-letter generation is paused and hidden. Do not advertise it or imply that partial drawings automatically become a complete font. SVG import traces rendered artwork; it does not preserve every original Bézier control point. Typefield exports static TrueType outlines, not variable fonts. Figma and Adobe handoffs require their respective host applications and available fonts. Font licensing remains the user's responsibility.
