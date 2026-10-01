# Typefield market positioning and release gates — 2026-10-01

This is a bounded review of current vendor descriptions and Typefield's documented **0.59.2 local build**, not a hands-on competitor audit or verification of every distribution path. Typefield's three workspaces are **Library** (find, organize, preview and manually activate fonts), **Spaces** (compose and compare visual typeboards), and **Letterform Editor** (draw or trace editable glyphs and export a static TrueType-outline font). See [production readiness](PRODUCTION_READINESS.md) and the [App Store checklist](APP_STORE.md) for the current release record.

## Is the combination first of its kind?

**No defensible “first of its kind” claim.** The reviewed products establish substantial overlap, and a bounded search cannot prove that no earlier or less visible product combined these capabilities. The closest category-level counterexample is [CorelDRAW Graphics Suite 2026](https://www.coreldraw.com/en/): Corel lists vector layout and typography alongside an included Corel Font Manager. Its [2026 Windows documentation](https://help.coreldraw.com/CorelDRAW/540111192/Documentation-Windows/CorelDRAW-en/CorelDRAW-TrueType-Font-TTF.html) also documents TrueType font export. This is a **suite**, and the cited font-export page is Windows-specific; it does not establish identical Mac functionality or the same workflow as Typefield.

| Product or workflow | Verified overlap from official sources | Positioning implication |
| --- | --- | --- |
| [Typeface](https://typefaceapp.com/) and [FontBase](https://fontba.se/) | Dedicated font browsing, organization and activation; Typeface also documents [automatic activation](https://typefaceapp.com/help/articles/auto-activation). | Typefield's Library competes in an established category. Do not call its basic font management novel or claim auto activation. |
| [FontLab 8](https://www.fontlab.com/font-editor/fontlab/) | Mature font creation, editing, proofing, comparison and export. | Typefield's Letterform Editor is an approachable static-font path, not a professional FontLab replacement. |
| [Adobe Fonts](https://helpx.adobe.com/creative-cloud/apps/integration-with-other-apps/manage-fonts/add-fonts.html) + Illustrator + [Fontself Maker](https://www.fontself.com/make-fonts-on-desktop) | Font browsing/activation, a design canvas and font creation can form a connected **multi-product** workflow. | “Only way to find, design with and make fonts” would be false. Typefield can describe the convenience of its own three-workspace Mac app. |

These links support the stated capabilities, not a claim that the products are equivalent or lack unlisted features. No competitor was installed or tested for this review.

## Usable public wording

> **Typefield brings font organization, visual typography exploration and letterform creation into one Mac app.** Browse and organize fonts in Library, compare them on Spaces typeboards, then draw or import your own letter artwork in Letterform Editor and export a static font.

Describe this as Typefield's connected workflow, not as the first, only, or most complete product. Qualify bridge exports as reviewed file handoffs rather than live Figma/Adobe sync. Do not advertise automatic missing-letter generation: it is hidden, its quality target has not been met, and no model is bundled. Do not imply SVG import preserves original Bézier nodes, or that independent masters produce interpolated or variable fonts.

## What remains before a public release

1. **Distribution identity and proof:** secure the Apple Developer team and production bundle ID; validate and upload a distribution-signed archive; test the TestFlight build on a clean second Mac and the declared macOS 13 minimum. The documented 0.59.2 install is local and ad hoc signed.
2. **Signed-build user journeys:** exercise all three workspaces with disposable projects, including migration from FontShelf, external-folder reauthorization, backup/recovery, activation and export. Complete keyboard/VoiceOver, contrast, denied-access and offline checks on that build.
3. **Interchange and artwork evidence:** run exported Figma and Adobe packages in their actual host applications, and proof representative real artwork imports and exported fonts in other apps. Mock bridge and synthetic fixture passes do not establish that fidelity.
4. **Storefront and support:** finish independent Typefield name clearance, support/privacy URLs, current screenshots and truthful feature copy, App Store listing/compliance details, and any agreements needed for the chosen price.

The [production readiness audit](PRODUCTION_READINESS.md) also identifies product-depth decisions: clearer selected-object versus shared-role editing in Spaces, better whole-object/weight editing and direct outlined-SVG import in Letterform Editor, and signed-sandbox folder/activation reliability in Library. Scope these against what the launch promises; professional variable-font production, document-triggered activation and cloud/team features are later product choices, not automatic prerequisites for a truthful first release. Recheck this list against the final candidate after the current branch changes settle.
