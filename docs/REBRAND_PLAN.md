# App naming plan

## Current finding

The current **FontShelf** name overlaps with [Fontshelf™](https://fontshelf.com/collections/all), a font-organizing product for Adobe Photoshop and Illustrator. [FontLab](https://www.fontlab.com/font-editor/fontlab/) is an established font editor. The third workspace is therefore labeled **Letterform Editor** in the app. Internal `FontLab` types, filenames, and saved-data keys remain unchanged so existing projects continue to open.

The whole app remains FontShelf until a replacement name is selected and checked. Web search is an initial collision check, not a trademark or App Store clearance opinion.

## Selection and release sequence

1. Choose a distinctive app name that covers font organization, typeboards, and letterform editing. Check Apple App Store listings, relevant trademark registers, domains, GitHub, and adjacent font/design products in launch territories. Keep a short record of the exact spelling and search date.
2. Have a qualified trademark reviewer assess the finalist before public distribution. Secure the desired domain and product handles, then decide whether the existing bundle identifier can remain as a stable technical identifier.
3. Update the display name, bundle name, icon, About screen, onboarding, help, website, screenshots, privacy copy, Figma plugin presentation, export labels, and developer handoff wording together. Keep versioned JSON formats and internal data directories compatible; new branding should not strand existing libraries or projects.
4. Test a clean install and an upgrade from a FontShelf build in a disposable macOS user account. Verify Library collections, Spaces, Letterform Editor projects, downloaded font licenses, external-folder access renewal, backup import/export, and old-format Figma/Adobe handoffs.
5. Use the final name for the signed TestFlight/App Store archive only after the above checks. Review the listing, metadata, privacy responses, and screenshots in App Store Connect before submission.

## Decision needed

Select a finalist app name and target launch regions. Until then, keep the app identity and support paths stable; the Letterform Editor workspace label can ship independently.
