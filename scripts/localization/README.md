# Typefield localization

Edit `catalog.tsv` (UTF-8, pipe-separated columns in its declared order), then run:

```sh
python3 scripts/localization/generate.py
python3 scripts/localization/generate.py --check
```

The generator emits native `Localizable.strings` tables under `Sources/Localizations/`. Every declared entry must have every translation. Placeholder checks permit positional reordering while preserving argument types. Capitalization and terminal-ellipsis aliases are generated from source literals; no translation service is contacted. Review the generated diff, especially when adding an alias.

SwiftUI literal labels use native localization and the selected locale environment. App-owned labels supplied dynamically need `localizedKey(label)`. Each independent hosting root needs `.typefieldLocalized()`. Use `.typefieldSheet` and `.typefieldPopover` for presentations: macOS sheets do not reliably inherit the custom locale. Native AppKit labels use `TypefieldL10n.text` and require an explicit refresh if retained while the language changes. The main menu rebuild preserves command IDs, actions and keyboard shortcuts.

Never localize font/PostScript names, project/collection names, user tags, specimen text, persisted enum raw values, filenames, export schemas or command IDs. `ShelfPopup` localizes its choices only when its caller opts in with `localizesOptions: true`. Do not opt in for font styles or user collections.

English fallback is deliberate for missing keys. This first catalog covers the core UI, not every diagnostic, advanced tool explanation or keyboard-shortcut description. Do not claim complete localization based on catalog column parity. New workflows should add translations at their UI boundary. System panels and third-party updater UI use macOS localization.

`TypefieldLanguageChecks` verifies regional matching (including Chinese scripts), ordered language fallback, explicit overrides, preference persistence and noninterference using a disposable defaults suite. The native build checks all bundled tables. `--language-snapshots OUTPUT_DIRECTORY` renders onboarding and language settings in each locale using a disposable library. `--window-qa` uses an isolated language preference for interactive switching checks.
