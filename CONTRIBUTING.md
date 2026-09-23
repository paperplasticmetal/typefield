# Contributing

## Before changing code

Check existing issues. For a larger change, describe the problem and proposed behavior before implementing it. Keep changes focused; do not commit fonts, private library data, signing certificates, account identifiers, or build products.

This repository currently has no open-source license. Discuss contribution and licensing terms with the maintainer before submitting code intended for incorporation.

## Development checks

1. Use Xcode 26+ on Apple Silicon.
2. Run `./build.sh`; the build treats Swift warnings as errors and runs regression checks.
3. For UI changes, check light/dark mode, keyboard access, narrow windows, and previews at small and large sizes. Ensure long text remains visible.
4. For file/network changes, exercise the sandbox build and failure paths. Use temporary fixtures, not a user's library.
5. Update the changelog and relevant documentation. Keep the displayed app name **Typefield** and preserve legacy saved-data and interchange identifiers. Use versions in bundle metadata.

## Pull requests

Explain the problem, resulting behavior, and verification performed. Include screenshots for visual changes and list any untested scenarios. Add regression coverage for real bugs; avoid tests that merely restate implementation details.

## Bug reports

Include app version, macOS version, hardware, steps to reproduce, expected/actual behavior, and whether sandboxing is involved. Redact personal paths and data. Do not upload proprietary font binaries; share the font name or a freely licensed minimal example when possible.

Be respectful, direct, and specific in issues and reviews.
