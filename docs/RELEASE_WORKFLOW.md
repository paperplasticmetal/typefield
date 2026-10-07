# Typefield app and website releases

Every completed app fix or feature includes the matching public beta download. A source push alone does not finish a release. Documentation-only changes do not require rebuilding an unchanged app.

1. Preserve user fonts, saved Library/Spaces/Letterform data and unrelated work. Record saved-data hashes before installation.
2. Bump `Resources/Info.plist` and `Resources/Info-Store.plist` together. Update `CHANGELOG.md`, `docs/STATUS.md` and focused QA notes.
3. Run relevant native checks and `node tests/figma-import.test.js`. For window changes, run `dist/Typefield.app/Contents/MacOS/Typefield --window-self-test` in a GUI session and use `--window-qa` for disposable live projects.
4. Run `./install-local.sh` to build/test/install the single canonical `/Applications/Typefield.app`. Verify its version, strict signature, binary equality with `dist/Typefield.app`, and unchanged user-data hashes.
5. Run `bash package-beta-dmg.sh`. Verify the image with `hdiutil verify`, mount read-only, and compare the enclosed app version, signature and executable hash. Keep DMGs out of source control.
6. Commit the verified source and notes, and push to `origin`. Create a versioned prerelease in the **public** `paperplasticmetal/typefield-feedback` repository, upload `Typefield-VERSION-beta.dmg` and its SHA-256 file, and verify the release asset. Never publish the private app source to that repository.
7. Read `marketing/website/.openai/hosting.json` and use the Sites hosting skill to open/reconcile the existing Site. Update the canonical `marketing/website/dist/` download links, version, build, requirements and signing status, and synchronize the deployment checkout. Link the exact versioned public GitHub release asset. Preserve the existing Site identity and audience.
8. Check website JavaScript and download-link/version consistency. Commit and push the website changes to `origin`, then publish through Sites and wait for a successful deployment. Report the version and live website/release links. If any upload or publication is blocked, report that the app is ready locally but distribution is incomplete.

Current beta requirements: Apple silicon, macOS 13 or later. The app is ad hoc signed, without Developer ID notarization. Keep the download instructions honest about macOS first-open approval until signing changes.
