# Signed Typefield updater QA — 2026-10-07

Implementation verified in an isolated worktree from `55a3aab`; final integration and distribution are pending. The canonical installation has not been changed by updater work.

- Direct-download builds embed pinned Sparkle 2.10.0; Settings → Updates and the Typefield menu offer Check for Updates. Daily checks default on, automatic downloading/installation defaults off, and both preferences use Sparkle’s persisted state. The Store build excludes Sparkle and direct-download controls.
- The native suite, complete Store source typecheck with warnings as errors, Figma bridge tests, 14 signed-feed regression cases, eight website tests and JavaScript syntax checks passed.
- Disposable UI verification showed the Updates pane, enabled manual check, automatic preference changes, dependent download control disabling/restoration, and both Settings/menu actions. The unpublished feed correctly produced a retrieval error, not a false up-to-date result. QA uses a separate updater defaults domain and temporary project data; installation is blocked before Sparkle can resume pending state.
- The unchanged official Sparkle 2.10 CLI installed a signed fixture update 1 → 2. Tampered feed and archive cases were rejected (errors 1000 and 4005), leaving original bundle hashes intact. A separate test using the actual compiled Typefield bundle and production signing key installed a 9,021,791-byte DMG, matched the complete candidate bundle including Sparkle, and left the original build unchanged. No fixture executable launched.
- Release-feed checks use the embedded public key only. They reject altered feeds/archives, wrong keys, unsigned tails, stale metadata, duplicate builds, and noncanonical download URLs. Signing keys stay in macOS Keychain; private keys are never published.

Evidence is private under `.context/qa-artifacts/updater/`, including the native/Store/website logs and `e2e/SUMMARY.json`. UI screenshots were inspected through the native computer-use tool. Tests used temporary fixtures and did not replace `/Applications/Typefield.app`.

Limits: The private installer tests verify download, authentication and bundle replacement, not a running Typefield process’s quit/relaunch or second-Mac behavior. App signing remains ad hoc; this feature does not claim Developer ID notarization. Existing pre-updater installations need one manual download.
