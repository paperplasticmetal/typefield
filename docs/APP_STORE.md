# App Store checklist

- [x] Native macOS app and shared Xcode scheme.
- [x] Sandbox and hardened-runtime configuration.
- [x] Icon asset catalog and privacy manifest.
- [x] Local build and regression checks for previous development releases.
- [x] Run the 0.59.1 native suite and mocked Figma bridge, canonical install, ad hoc signature and installed-binary verification. The 980-point compact-window UI pass is complete; see [0.59.1 QA](QA_2026-09-30_0.59.1.md).
- [ ] Finish signed-build UI and permission testing with disposable projects and font fixtures.
- [ ] Active paid Apple Developer team and registered production bundle identifier.
- [ ] Final public version, distribution-signed archive, Organizer validation and App Store Connect upload.
- [ ] TestFlight/second-Mac testing and verification of the declared macOS 13 minimum (or a justified deployment-target change).
- [ ] Keyboard, VoiceOver, reduced transparency, increased contrast, denied-file-access and offline/download tests on the final distribution build.
- [ ] Public support/contact and privacy-policy URLs.
- [ ] Store screenshots, description, keywords, copyright, price and territories.
- [ ] Age rating, privacy, export-compliance, applicable EU trader-status and review-contact information.
- [ ] Applicable agreements/tax/banking setup if selling the app.
- [x] User-selected migration path and disposable regression fixtures for Library, Spaces, Letterform Editor and app-managed Google Fonts.
- [ ] Run the migration and external-folder reauthorization on a distribution-signed Store/TestFlight build, including a clean second-Mac install and recovery drill.
- [ ] Exercise exported Figma and Adobe packages in the actual host applications; local bridge fixtures alone do not establish host fidelity.

The screenshot set and privacy review are described in [SCREENSHOTS.md](SCREENSHOTS.md). Local tour and About-sheet screenshots were visually checked in an earlier build; final 0.59 captures require a clean fixture account and signed build. Do not show or promise the paused missing-letter suggestion workflow. Capture the current Library selection, Spaces handoff and Letterform Editor proofing UI only after candidate review.

The production bundle identifier must replace `local.typefield.app`. Never commit signing credentials or provisioning profiles. `archive-store.sh` takes `TEAM_ID` and `APP_BUNDLE_ID` from environment variables and runs `verify-store-archive.sh` on the team-signed archive. Xcode Organizer applies distribution signing during validation/upload; Xcode may use cloud-managed certificates. The script does not upload. Keep the production bundle ID stable after the first TestFlight upload.

## Migration from a local build

1. Quit the local Typefield app or an earlier FontShelf build. Keep its Application Support folder and font files in place.
2. On a fresh Store build, open **Library → Tools → Migrate FontShelf data to Typefield…**. In the file picker, use Command–Shift–G to choose `~/Library/Application Support/FontShelf` if the Library folder is hidden. Review the confirmation and choose **Copy and Quit**.
3. Reopen the Store app. Library collections, tags, Spaces, Letterform Editor projects and downloaded Google Fonts should be present. The old support folder remains untouched. In **Live folders**, choose each external font folder again to grant the Store app its own security scope. Rechoose external WOFF2 folders in the web-font audit. Saved paths remain listed until access is renewed.
4. Optionally choose **Tools → Import earlier preferences…** and select `~/Library/Preferences/local.fontshelf.app.plist`. This imports only known preferences that are not already set in the Store app. Reopen to refresh all screens.

Migration refuses an occupied Store container and invalid project files. Use **Export library backup…** first if the Store app already contains work; **Import library backup…** is a separate merge operation that imports Spaces and Letterform Editor projects as copies. Neither operation moves external fonts. The folder migration includes app-managed Google Font files and licenses. Validate this flow on a signed TestFlight build before offering it to users.

## Distribution runbook

1. Confirm Apple Developer team membership, registered bundle ID, App Store Connect app record and Xcode signing access for the team.
2. Run `bash build.sh`, `node tests/figma-import.test.js`, then `TEAM_ID=… APP_BUNDLE_ID=… ./archive-store.sh`. The script leaves the team-signed archive in `dist/Typefield.xcarchive` and checks its code signature, team, entitlements, version and privacy manifest.
3. In Xcode Organizer, run **Validate App**, then upload to App Store Connect. TestFlight and App Store builds do not need Developer ID notarization; direct-download releases require separate Developer ID signing and notarization.
4. Install the TestFlight build on a clean second Mac and the declared macOS 13 minimum. Check first launch, font listing, all three workspaces, folder denial/regrant, migration, export, activation cleanup, offline behavior and recovery from a corrupt saved file using disposable fixtures.

Session activation and font export should be checked with representative installed and imported fonts under the final signed entitlement set.

## Review notes draft

Typefield previews and organizes fonts available on the Mac and in user-selected folders. Browsing, organizing, exporting and backup import leave original font files in place. Font Health can repair an eligible original only after a separate confirmation and makes a sibling backup first. Google font browsing retrieves public preview font files from GitHub; explicit downloads store font files and their license locally. Preview text and the user's library are not uploaded. Temporary activation uses Core Text session registration and is cleared on normal quit. Export copies originals to a user-selected destination. Adobe support exports static JSX scripts for users to run manually; Typefield sends no Apple events. There are no accounts, in-app purchases, ads or analytics.

See [Apple's App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [submission guidance](https://developer.apple.com/app-store/submitting/). Successful local checks do not establish App Store approval.
