# Typefield identity and release plan

## Selected name

The app name is **Typefield**. The former FontShelf name overlaps with an existing font-organizing product, and FontLab is an established editor. The third workspace is called **Letterform Editor**. Internal `FontLab` models and `font-lab.json` remain in place so saved projects open unchanged.

Version 0.37.0 updates the visible name, icon, local development bundle ID, Xcode target, first-run tour, About/privacy sheet, Figma plugin presentation, export names, developer handoff names, documentation, and both GitHub repository names. Existing Library, Spaces and Letterform Editor files remain under `~/Library/Application Support/FontShelf` for a safe in-place local upgrade. Versioned Figma/Adobe JSON markers and Figma metadata namespace remain `fontshelf` so older handoffs still round-trip. The new local bundle reads known, unset preferences from `local.fontshelf.app.plist` on first launch when available. Store builds continue to offer explicit migration into their sandbox container.

Version 0.45.3 completes a follow-up naming pass: new search suggestions, Spaces export filenames, repair backups, remix provenance, and generated font identifiers use Typefield. Existing search tokens with `#fontshelf/` and `#typeface/` still match. Historical release notes and the persistence and interchange identifiers above retain their original spelling so saved data remains usable.

## Before public distribution

1. Search Typefield in the target countries' trademark registers, App Store listings, domains, and design products, then have a qualified reviewer assess it. The name choice and initial web search do not establish clearance.
2. Register the production bundle identifier with the Apple Developer team, sign and validate the archive through Xcode Organizer, and upload to App Store Connect. The local `local.typefield.app` identifier is for development only.
3. Test a clean install and an upgrade from a FontShelf build in a disposable macOS account, and test a signed TestFlight build on a second Mac and on macOS 13. Verify collections, Spaces, Letterform Editor projects, downloaded font licenses, external-folder reauthorization, backup import/export, and old Figma/Adobe handoffs.
4. Prepare final App Store screenshots, listing, support and privacy URLs, and metadata. Review the screenshots for personal fonts or projects before publishing them.
