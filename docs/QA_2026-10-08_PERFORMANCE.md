# Library responsiveness and background-work QA

Date: 2026-10-08 (Pacific). Starting revision: `7a0f393`, installed/public 0.59.24 (104).

Status: integrated 0.59.27 (107) candidate passed native, window, Figma and disposable live checks. Canonical installation and public distribution are pending.

## Scope and coordination

The user identified Library typing/searching/scrolling and workspace/project navigation as the main problems. This pass uses an isolated `codex/performance-cleanup` worktree. Concurrent Spaces and Letterform work owns its editor, toolbar and canvas files; the performance release must integrate their completed releases before building the final app. Missing-letter model research remains paused.

Three workers reviewed Library state and ranking, font rendering, and background filesystem/Font Health work. The coordinator reviewed cross-cutting redraw costs, sidebar counts, navigation, changes and regression evidence. Tests use disposable files and projects; no user font registration or repair is part of this pass.

## Changes being validated

- Retain sidebar counts across search, preview and selection changes. Catalog, saved Library and advanced Library changes invalidate them.
- Reuse the current filter's matching styles for cards and metadata rows, and reuse the parsed query. Immutable family snapshot identities prevent a stale inspector from borrowing a replacement family's results. Live activation predicates bypass retained matches. Preview typing does not invalidate filtering when coverage checking is disabled.
- Retain body specimen TextKit views, storage and layout across unrelated inspector changes. This also preserves selected body text instead of resetting it while editing the headline. Text, width, typography, columns and colors still update.
- Reuse bounded, exact font/text/width measurements for Library preview rows. Catalog/font-cache invalidation also clears measurements; row baselines, mixed-script fallback, three-line limits and minimum heights remain unchanged.
- Precompute discovery sorting keys once per family, preserving ranking, seeded tie order, exclusions and usage metadata.
- Stop superseded recursive folder walks and reject their queued callbacks. Retain the three-second recursive polling fallback and detection of nested additions, replacements and removals. Explicit removal and re-addition of a failed protected root must resume its watcher even when intermediate configurations are superseded.
- Run selected-file and Library Font Health inspection on one cancellable background queue. Cancellation and closing the view discard obsolete results. Optimize SFNT checksum reads while preserving unaligned input, partial-word padding and wrapping addition.

## Starting measurements

The installed 0.59.24 full-catalog audit found 779 families / 4,253 styles. A fresh Library filter took 16.064 ms, repeated retained reads 0.000820 ms, and an uncached sidebar snapshot 3.693 ms. The catalog scan took 3,134 ms. These are individual path timings, not end-to-end input latency.

A five-second idle stack sample found the main thread waiting for events, approximately 324 MiB physical footprint and no continuous CPU loop. It does not rule out interaction stalls. Spaces disposable-store measurements were 0.12 / 2.12 / 8.59 ms median load for 2 / 50 / 200 boards; the 200-board selection save was 9.51 ms. No improvement to these unchanged persistence paths is claimed.

## Verification and limitations

Focused optimized native checks passed: 54,502 Library filter comparisons, 400 discovery ordering/metadata comparisons, 196 exact preview measurement cases, 896 original/candidate row aggregates, TextKit selection/layout cases, recursive watcher/cancellation cases and 2,050 checksum fixtures. Independent cross-reviews found no blocking issue. The integrated optimized build with warnings as errors passed the complete native suite (779 families / 4,253 styles), including background, preview, toolbar, proof, dense-outline, import/export and failed-persistence checks. The GUI window suite and mocked Figma bridge passed.

| Repeated path / fixture | Baseline | Candidate |
| --- | ---: | ---: |
| 60 preview face reads, text filter, synthetic 800-family / 4,800-style catalog | 0.510 ms | 0.056 ms |
| All matching metadata rows, same text filter | 6.465 ms | 0.347 ms |
| Discovery ranking, 800 families | 16.766 ms | 12.313 ms |
| Body specimen unchanged update | 0.483 ms | 0.00372 ms |
| 24 preview cards, long mixed text | 13.428 ms | 0.351 ms |
| Same cards with overlay | 23.819 ms | 0.643 ms |
| Twelve in-memory inspections of a synthetic 8 MiB SFNT font | 331.738 ms | 18.226 ms |

Cold filtering in the synthetic comparison adds 0.15–0.54 ms to retain matching styles; this tradeoff avoids repeated card/metadata scans. New font/text/width combinations still require shaping. These fixtures are deterministic, use the original algorithm as an oracle, and do not register fonts.

A native retained-host probe modeled the existing WorkspaceWindows ownership: ten published changes caused ten visible body evaluations and zero while the host was unmounted. Ordinary workspace changes already avoid persistence and preserve editor hosts. No speculative hidden-view suspension or navigation rewrite was added. The small live baseline fixture retained the Space, Letterform project and Library query across workspace switches without an observed hang; this does not establish dense-project latency.

Timing runs are local and sensitive to OS caching and concurrent work; microbenchmark gains are not whole-app speedups. Font Health cancellation can stop between files, while a current synchronous file read, Core Text operation or filesystem enumeration call may finish first. Recursive polling remains enabled. No second-Mac/macOS 13 run or universal frame-rate claim is implied.

Private evidence is under the primary checkout's `.context/qa-artifacts/performance-2026-10-08/` and `.context/qa-artifacts/performance/`. It must remain local and uncommitted.

## Integrated candidate and live checks

The complete Spaces 0.59.25 and Letterform 0.59.26 source changes are retained. An independent integration review verified all 84 Swift files are registered exactly once in Xcode and all added checks are connected to the native suite.

On the current 779-family catalog, repeated sidebar reads measured 0.000130 ms versus 3.643 ms to reconstruct counts; 24 mixed-script preview measurements measured 0.213 ms retained versus 26.099 ms fresh. Sixty preview face reads took 0.177 ms and all matching metadata 0.380 ms. Fresh filtering measured 17.004 ms (starting run 16.064 ms); retained filtering measured 0.019430 ms (starting run 0.000820 ms). These small added lookup costs accompany the removal of repeated style work; this is not a claim that the full filter computation became faster. Catalog scan and unchanged navigation timings remained similar: 200-board load median 8.668 ms and selection save median 9.181 ms.

A separately identified disposable app verified:

- Typing Helvetica returned two families / 20 styles; clearing it returned 779 / 4,253.
- Long Latin/Arabic/Devanagari/Japanese preview text retained all results with coverage off; enabling coverage used the latest text and returned one matching family/style. Disabling it restored ordinary search results.
- Scrolling long previews down and back, then switching Library → Spaces → Letterform → Library retained the Space, project and Helvetica query. No hang was observed in this fixture; no end-to-end timing claim is inferred from automation duration.
- Body specimen text remained selected after a headline-size change. Switching to three columns retained continuous text flow and selection, verified visually.
- Read-only Font Health inspection completed for 2,922 distinct files. Immediately dismissing a repeat scan returned to the correct Library query. The scan completed before the UI tool could observe its Cancel button; deterministic native tests verify cancellation and stale-result rejection. No repair was performed.

All 31 saved-data hashes still matched this pass's baseline before canonical installation. The two paused evaluator edits remain untouched.
