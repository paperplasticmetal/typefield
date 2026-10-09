# Language support, 0.59.28 (108)

## Scope

Language selection in the tour header and Settings → Language follows the Mac by default, accepts an explicit override, persists it, and updates the main window, detached editors, font browsers and inspectors without replacing their SwiftUI identity. AppKit application menus refresh at the same time. Choices use their own native names so English is not needed to find a language.

English, French, Spanish, German, Japanese, Hindi, Simplified Chinese, Traditional Chinese, Brazilian Portuguese, Italian and Korean. Chinese script/region matching and unsupported-language fallback are explicit and tested. Portuguese regions use the Brazilian translation. No network translation service or extra downloads.

The parallel catalog covers onboarding, Settings prose, common Library navigation/actions and core Spaces/Letterform controls. It is an initial localization release, not complete translation of every advanced workflow: some detailed editor help, advanced export/diagnostic text and shortcuts remain English. macOS panels and third-party updater UI follow system localization. Project names, font metadata, specimen text, user tags, keyboard shortcut keys and stored enum IDs remain unchanged. No native-speaker editorial review is claimed.

## Validation

- Full optimized native suite passed through `./install-local.sh`, including language resolution, isolated preference persistence, catalog parity and existing editor/import/export/persistence checks (779 families / 4,253 styles).
- Native window identity, detach/redock/close, independent browser lifetime and typed font payload checks passed. Figma bridge checks and all 14 updater tests passed.
- Generated tables contain 620 keys in each of 11 languages. Catalog parity/format placeholders, plist syntax, Xcode resource references, Swift Package manifest and whitespace checks passed.
- Rendered all four onboarding steps and Language settings in all 11 languages (55 images). Examined long German/French text, Hindi shaping/spacing and Japanese/Chinese layouts; fixed Hindi title tracking and increased tour space to avoid crowding.
- Disposable live QA verified Settings and AppKit menus switching immediately to Japanese, localized Library controls with unchanged font names/specimens, and Japanese onboarding opened after the change. Switching to Hindi on step four retained that step and its curve state. macOS presentation boundaries explicitly receive the live locale; this fixes sheets otherwise retaining English.
- Canonical `/Applications/Typefield.app` is 0.59.28 (108), with a valid strict ad hoc signature and a full bundle manifest identical to `dist/Typefield.app`. All 32 saved-data hashes and both paused research-file hashes remain unchanged after installation and disposable QA.
- The verified DMG was mounted read-only; its complete app manifest and signature match the installed build. The existing update key signed and verified the DMG and feed without exporting private key material.

## Distribution

- Source/assets commit `f62cc54` pushed to both configured origin repositories. [Public prerelease v0.59.28-beta.1](https://github.com/paperplasticmetal/typefield/releases/tag/v0.59.28-beta.1) contains the DMG and checksum.
- Cloudflare Pages deployment `dcbc4579` published the existing website and feedback Function. [The live download page](https://typefield.app/download/) offers 0.59.28 beta 1 (108), its same-origin DMG, the matching GitHub asset and checksum.
- Unauthenticated GitHub and website downloads have identical verified hashes. The public feed bytes equal the signed local feed and are served as RSS with `Cache-Control: no-cache`. Public feed/archive Ed25519 validation passed against both downloaded DMGs. The live feedback configuration endpoint returns its public widget key successfully.
- The canonical app's Settings → Updates → Check for Updates reports “Typefield 0.59.28 is currently the newest version available.” The real language preference remains System language, and Language settings is open for the user.
- Website syntax checks, all eight website tests and the version/checksum/feed release gate passed. Final verification still finds all 32 saved-data hashes and both paused research files unchanged.

DMG: `Typefield-0.59.28-beta.dmg`, 8,603,482 bytes. SHA-256: `a53012aa9673639e9aea9a7690c8e1544e9baf82db33ffc7a2020dada90e31f0`.

App executable SHA-256: `7a29e03b3f6cf64adb852a47314bf3bed2063aa7d25159c8867f3e8da8d071e9`.

## Reproduction

- `python3 scripts/localization/generate.py --check` checks catalog parity, formatting placeholders and generated native tables.
- `bash build.sh` includes isolated preference/system-matching/catalog regression checks with the existing native suite.
- `dist/Typefield.app/Contents/MacOS/Typefield --language-snapshots OUTPUT_DIRECTORY` renders the tour and language settings in all supported languages using an empty temporary Library.
- `--window-qa` isolates interactive projects and the language preference.
- `node tests/figma-import.test.js` covers the Figma bridge.

Private evidence: `.context/qa-artifacts/languages-05928/`. The two paused research edits are unrelated and remain preserved.
