# Signed Typefield updater QA — 2026-10-07

Typefield 0.59.24 (104) integrates the completed Spaces 0.59.22 and Letterform 0.59.23 releases, including both late Undo corrections. The final optimized native suite passed and `./install-local.sh` installed the canonical `/Applications/Typefield.app`. Public distribution and standard live update checks passed on 2026-10-08.

- Direct-download builds embed pinned Sparkle 2.10.0; Settings → Updates and the Typefield menu offer Check for Updates. Daily checks default on, automatic downloading/installation defaults off, and both preferences use Sparkle’s persisted state. The Store build excludes Sparkle and direct-download controls.
- The native suite, complete Store source typecheck with warnings as errors, Figma bridge tests, 14 signed-feed regression cases, eight website tests and JavaScript syntax checks passed.
- Disposable UI verification showed the Updates pane, enabled manual check, automatic preference changes, dependent download control disabling/restoration, and both Settings/menu actions. The unpublished feed correctly produced a retrieval error, not a false up-to-date result. QA uses a separate updater defaults domain and temporary project data; installation is blocked before Sparkle can resume pending state.
- The unchanged official Sparkle 2.10 CLI installed a signed fixture update 1 → 2. Tampered feed and archive cases were rejected (errors 1000 and 4005), leaving original bundle hashes intact. A separate test using the actual compiled Typefield bundle and production signing key installed a 9,021,791-byte DMG, matched the complete candidate bundle including Sparkle, and left the original build unchanged. No fixture executable launched.
- Release-feed checks use the embedded public key only. They reject altered feeds/archives, wrong keys, unsigned tails, stale metadata, duplicate builds, and noncanonical download URLs. Signing keys stay in macOS Keychain; private keys are never published.

Evidence is private under `.context/qa-artifacts/updater/`, including the native/Store/website logs and `e2e/SUMMARY.json`. UI screenshots were inspected through the native computer-use tool. Installer experiments used temporary fixtures. The final release installation preserves all 31 saved-data JSON hashes and both paused research-file hashes.

Limits: The private installer tests verify download, authentication and bundle replacement, not a running Typefield process’s quit/relaunch or second-Mac behavior. App signing remains ad hoc; this feature does not claim Developer ID notarization. Existing pre-updater installations need one manual download.

## Final integrated package

- All 78 Swift sources remain registered in Xcode and the frozen build inputs are unchanged. Native/window/Figma checks, JavaScript syntax, all eight website checks and signed website/feed validation passed. The complete Store source typecheck passed before integration; Store-specific updater code did not change afterward.
- Built and installed executable SHA-256: `81b85d3cf2079134c7224c2cd8c54679a87e84dff9700aa80016eb61c200006f`. Strict signatures pass. The read-only mounted DMG matches the complete built app file/symlink manifest.
- DMG: 8,279,531 bytes; SHA-256 `ae5381958cfcea0a020af759acd953df1add738325ef6cbd21dec8640ec9ec2b`. Both its archive signature and complete signed feed verify using the embedded public key.
- An independent final read-only review found no concrete blocker. Settings and the Typefield menu both reached Sparkle’s standard “You’re up to date!” dialog against the live signed feed, correctly naming Typefield 0.59.24. Daily checking is on and automatic downloads are off. The canonical app is left open at Settings → Updates.

## Published verification — 2026-10-08

Source/package commit `e8806f9` was pushed to both configured origin repositories. Public GitHub prerelease `v0.59.24-beta.1` and Cloudflare deployment `f4fcf370` independently serve the identical 8,279,531-byte DMG with the checksum above. Public feed bytes match the signed local feed and pass the public-key-only validator using the downloaded DMG. The feed has RSS content type and no-cache headers. The download page reports 0.59.24 (104); the feedback configuration endpoint returns its expected public site key. Saved-data/research hashes remain unchanged after the canonical app’s live update checks.

Private evidence includes `install-05924.log`, `final-source-manifest.json`, `public/verification.json`, `live-ui-verification.json` and `post-install-verification.json`. Initial Git HTTP transport failures were retried with per-command buffering; both main branches and the feature branch accepted the same commit without force-pushing.
