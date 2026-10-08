# Typefield direct-download updater

The direct `build.sh` build embeds Sparkle **2.10.0** and defines
`TYPEFIELD_DIRECT_DISTRIBUTION`. The separate App Store build does not include
Sparkle. `prepare-sparkle.sh` downloads only the official pinned release,
checks its 16,319,840-byte length and SHA-256 before extraction, and verifies
the framework's signature. The cache lives in `.build/sparkle/`; the framework
license is copied into the built app's Resources. Framework symlinks are
preserved, and nested code is signed from the inside out.

The canonical feed is `https://typefield.app/updates/appcast.xml`. Updates are
on the default Sparkle channel even while the GitHub release is marked as a
public beta. Each enclosure points to the exact immutable asset in the public
`paperplasticmetal/typefield` repository; it never uses GitHub's `latest` alias.
Only published release assets belong in this feed. The app requires both a
signed feed and an archive signature, verifies archives before extraction,
and immediately rejects feeds whose signatures fail.

## Generate the release feed

The release key belongs in the macOS Keychain under the dedicated account
`typefield-updates`. The release owner provisions that key once with Sparkle's
`generate_keys --account typefield-updates`, saves the public key in the direct
app's `SUPublicEDKey`, and arranges a secure backup outside this repository.
Never generate a replacement key for a routine update or put private key
material in source, release assets, shell arguments, or logs. The scripts below
only look up an existing key and fail if it is missing or does not match the
built app.

After building, testing and packaging the current app:

```sh
python3 scripts/updater/generate-appcast.py \
  --app dist/Typefield.app \
  --dmg marketing/website/dist/assets/Typefield-VERSION-beta.dmg \
  --output marketing/website/dist/updates/appcast.xml \
  --notes /path/to/plain-text-release-notes.txt \
  --published-at 2026-10-08T01:00:00Z
```

`--notes` and `--published-at` are optional; supply a fixed timestamp when
reproducibility matters. Existing output is verified and its older items are
preserved. `--previous-feed PATH` can name a separate previously published
feed. Builds must increase monotonically. Repeating a command for the same
build is allowed only when the existing signed feed already matches the app
and exact DMG. A new release must never reuse an old build number with altered
contents.

Before signing, the generator verifies the built bundle and mounted DMG's
code signatures and compares every packaged file and symlink with the provided
app. It checks the feed URL, public key, versions and verification policy, then
signs the DMG and complete feed. It verifies signatures with Sparkle and with
a public-key-only CryptoKit verifier before atomically writing the output.
Missing keys or any mismatch produce a nonzero exit without publishing an
unsigned fallback. Website/GitHub upload and deployment remain the release
workflow's responsibility; see `docs/RELEASE_WORKFLOW.md`.

## Validate without the release key

```sh
python3 scripts/updater/validate-appcast.py \
  --plist Resources/Info.plist \
  --dmg marketing/website/dist/assets/Typefield-VERSION-beta.dmg \
  --feed marketing/website/dist/updates/appcast.xml
python3 scripts/updater/test-appcast.py
```

Validation uses only the public key embedded in the plist and the macOS Swift
SDK's CryptoKit. No Python dependencies, credentials, or Keychain access are
needed. The small verifier is compiled into `.build/updater-tools/` as needed.
The validator rejects unsigned tails, incomplete signed byte ranges, missing
signatures, stale versions, duplicate/non-monotonic builds, altered archives,
and noncanonical download URLs. Previous archive metadata is covered by the
feed signature; the supplied current DMG receives full signature verification.

Tests use disposable files and the publicly documented RFC 8032 test vector
key, exclusively for fixtures. They do not access production signing keys,
installed applications, libraries or project data. If the pinned distribution
is available, a compatibility test also checks Sparkle's actual feed-signing
format against the independent verifier.
