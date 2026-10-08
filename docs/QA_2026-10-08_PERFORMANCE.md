# Library responsiveness and background-work QA

Date: 2026-10-08 (Pacific). Starting revision: `7a0f393`, installed/public 0.59.24 (104).

Status: candidate under validation. Final integration, installation and public distribution are not yet complete.

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

Focused baseline/candidate harnesses and complete integrated results will be recorded here before release. Timing runs are local and sensitive to OS caching and concurrent work; microbenchmark gains are not whole-app speedups. Font Health cancellation can stop between files, while a current synchronous file read, Core Text operation or filesystem enumeration call may finish first. Recursive polling remains enabled. No second-Mac/macOS 13 run or universal frame-rate claim is implied.

Private evidence is under the primary checkout's `.context/qa-artifacts/performance-2026-10-08/` and `.context/qa-artifacts/performance/`. It must remain local and uncommitted.
