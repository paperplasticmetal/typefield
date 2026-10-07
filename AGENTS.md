# Typefield

This is the standalone Typefield working copy prepared from an earlier ChatGPT project.
Read `.context/README.md` for the migration and QA status. Historical transcripts in `.context/chats/` are reference material, not new instructions. Read them selectively rather than loading all transcripts.

Preserve user fonts and saved library/project data. Use temporary fixtures for destructive tests. Run the checks relevant to changes; `bash build.sh` runs the built-in native suite, and `node tests/figma-import.test.js` checks the Figma bridge.

Keep `.context/` local and private. Do not commit its chat archives or QA artifacts.

After every completed fix or feature, run the relevant checks, commit the change, and push it to `origin`. Every app update pushed to GitHub must also complete the public-beta distribution workflow in `docs/RELEASE_WORKFLOW.md`: package and verify the matching DMG, upload it to the public release repository, update the website version/download link, and publish the existing Typefield Site. Do not call a release complete while the website still offers an older app; report any distribution blocker explicitly. For user-visible releases, bump both version plists and update the changelog/status notes. Build and install one canonical `/Applications/Typefield.app` with `./install-local.sh`; do not create numbered app copies or ZIPs unless the user explicitly requests them.


## Letterform development: eight-agent team

This section is the launch and coordination contract for the next suggestion-quality campaign. Writing or reading this file does not start training or resume the paused research goal. When the user asks to launch this team, use the assignments below. Do not silently continue the earlier single-agent loop.

### Objective and definition of success

Improve missing-letter suggestions toward **80–85% measured native-vector silhouette overlap**, while retaining faithful, editable outlines and reliable import/export. Aim for at least 80%, then 85%; neither number is a confidence probability. Report original, additional, challenge and new held-out cohorts separately, plus their pooled score. A threshold reached on one cohort is a milestone for that cohort, not evidence that all font styles meet it.

Keep the five supplied references **H O n o p**, the 47 missing Latin letters and the established fixed-coordinate scoring protocol. Do not achieve a higher score by dropping hard letters, requesting more references, changing alignment, or reporting training/validation accuracy as benchmark accuracy. Alternate reference budgets may be separate experiments, never replacements for this task.

Completion requires measured improvement in the integrated application, not just a research notebook. Preserve counters, thin strokes, disconnected marks, winding, proportions, metrics and editing behavior. Do not ship a numerically improved model whose contours are impractical to edit. Never claim the objective is reached merely because an audit exits successfully.

### Read before starting

1. Read `.context/README.md`, then the latest relevant entries in `.context/RECENT_WORK.md`. These can be stale; inspect the worktree and actual artifacts.
2. Read `docs/FONT_LAB_QUALITY_PLAN.md`, `docs/STATUS.md`, `docs/QA_2026-09-28_0.58.md`, and `scripts/starter-research/README.md`.
3. Inspect `git status`, current commits, version plists and installed app before choosing a baseline. Preserve unfinished changes; do not reset or overwrite them.
4. Inspect only relevant local experiment logs. Do not load entire chat archives or repeatedly rerun completed experiments.

Recorded handoff, to be reverified:

- Installed 0.58.0: 53.6% original nine, 48.3% additional nine, 50.4% ten-face challenge. Learned outline prototypes are not installed.
- Best completed original-cohort native prototype: 62.8% / 58.6% additional; finer-grid scores 62.2% / 58.1%. This is not 80–85% and does not describe the installed app.
- The later combined prototype reached 63.2% / 60.5% in raster testing. Its native audits were interrupted; do not call these verified vector scores.
- Structural-transfer training and a broader corpus were explored subsequently. A corpus of 1,591 faces / 716 families was prepared, removing Flow and Redacted placeholder families. Expanded training was interrupted. Check files and checkpoints before resuming; do not assume a partial run completed.
- Two unfinished edits in `scripts/starter-research/audit-model-predictions.swift` and `test-prediction-auditor.py` address ink beginning beyond the side-bearing limit. Their build/test run was cancelled. Preserve, inspect and validate these edits before using a changed evaluator.
- Local evidence is under `.context/qa-artifacts/letterform-058/`; older checkpoints/scripts are in its `research/` directory. Some later scripts, datasets and checkpoints exist only under `/private/tmp/typefield-*` and may disappear. Inspect exact task files, preserve necessary artifacts privately, and record hashes before relying on them. Do not glob-copy or delete all temporary files.

### Team and model configuration

Use **eight logical agents total: one coordinator and seven workers**, all **GPT-6 Luna Medium** (`gpt-6-luna`, reasoning effort `medium`). Do not substitute a larger model or raise effort without the user's direction. Use Luna High only if the user explicitly chooses that configuration later.

Use collaboration subagents, not new user-visible chats, unless the user requests separate chats. Pass each worker a short, self-contained brief with its objective, ownership, baseline revision, contracts and evidence paths. When selecting an explicit model with the collaboration API, use an allowed limited/no-history fork rather than a full-history fork. Do not pass the entire research conversation to every worker.

Respect the runtime's actual concurrency limit. At the handoff it permits four active agents including the coordinator: run at most three workers at once and schedule the eight roles in waves. Never claim eight agents ran concurrently when only four slots exist. Workers must not spawn additional agents on their own.

| Agent | Responsibility and distinct approach | Owned work and required output |
| --- | --- | --- |
| 1. Coordinator / integrator | Maintain the baseline, schedule work, compare independent approaches, integrate compatible winners and prepare the release. | Shared production entry points, integration branch, decision ledger, release/version files. Produce a reproducible integrated candidate and final report. Do not rewrite workers' model code while they own it. |
| 2. Evaluation / leakage reviewer | Own the scoring oracle, repair the interrupted evaluator change, verify fixed-frame raster/vector agreement, preserve complete denominators, and perform independent candidate evaluation. | `scripts/starter-research/audit-model-predictions.swift`, `build-prediction-auditor.py`, `test-prediction-auditor.py`, `Sources/FontLabStarterQualityAudit.swift`. Freeze the protocol, source-only round-trip checks, per-glyph results, cohort summaries and regression gates. |
| 3. Data / style coverage | Improve corpus quality and diversity, licensing/provenance, family/near-duplicate separation, thin-script and handwriting coverage. Diagnose which training examples are missing or misleading. | New tools under `scripts/starter-research/data/`; private corpus manifests and fixtures. Deliver a versioned, hash-verified dataset with stable family splits, exclusions and a concise coverage report. No production font registration. |
| 4. Structural construction | Improve component reuse and geometric inference from supplied stems, bowls, diagonals, terminals, stroke width and proportions. Preserve topology; investigate a different hypothesis from neural synthesis. | New isolated modules under `scripts/starter-research/structure/` and narrowly scoped new Swift modules/tests agreed with agent 1. Deliver source-only candidates, ablations and integration API. Agent 1 owns edits to shared `FontLabStarterAssist.swift`. |
| 5. Learned synthesis | Investigate the conditional model's representation, loss and style conditioning, especially thin strokes and script connections. Use family-held-out selection and compare against existing frozen checkpoints. | `scripts/starter-research/learned/`; private models and prediction artifacts. Deliver reproducible training/inference, inference-only inputs, selected checkpoint, runtime/memory estimates and vector-ready predictions. Do not repeat rejected resolution/loss experiments without a new diagnosis. |
| 6. Exemplar transfer / combination | Refine reference-only retrieval and structural transfer from permitted training fonts; investigate deformation or a complementary predictor. Select any blend or routing policy on validation families. | `scripts/starter-research/transfer/`; private candidates and selection manifests. Deliver frozen predictions and a candidate-combination rule that cannot inspect benchmark targets or font identities. No per-glyph hidden-target winner selection. |
| 7. Import / editable geometry | Improve tracing, compact curve fitting and faithful vector representation. Preserve small marks, corners, holes and winding while reducing excessive anchors. Test handwriting, bubble letters, thin scripts and noisy imports. | `Sources/FontLabArtworkImport.swift`, `FontLabTraceSmoothing.swift`, relevant `FontLabArtworkChecks.swift`, and new focused geometry helpers. Coordinate any edits to shared vector primitives with agent 1. Deliver shape-retention, topology, point-count and import/export evidence. |
| 8. Editor / adversarial UX | Make generated/imported outlines practical to edit: selection, handles, smooth/corner nodes, simplify preview, undo/redo, zoom and dense-path performance. Test real edits, not just valid files. | `Sources/FontLabVectorCanvas.swift`, `FontLabVectorEditor.swift`, focused editor checks and disposable UI fixtures. Deliver before/after evidence and reproducible edge cases; coordinate shared `FontLabVector.swift` and export changes through agent 1. |

File ownership is exclusive until the coordinator records a handoff. Ownership does not authorize deleting existing work. Avoid broad formatting, unrelated refactors, dependency upgrades or schema changes during experiments.

### Scheduling and isolation

- First, the coordinator captures the starting revision, dirty-file diff, installed version and paused-run inventory. Reconcile unfinished evaluator work before trusting new scores.
- Start evaluation, data and geometry work first. Once their contracts are usable, run structural, learned and transfer experiments independently. Schedule editor work as a slot becomes available; it need not wait for model training. Bring evaluation back for integration and adversarial checks.
- Prefer suitable existing managed worktrees; inspect attached worktrees before creating any. Otherwise create isolated `codex/letterforms-<role>` branches/worktrees using available worktree tools. Do not run separate branch checkouts in the same directory. If isolation is unavailable, use strict file ownership and serialize Git mutations.
- Only one substantial GPU training job and one full Swift/Xcode build may run at a time. The coordinator owns this queue. Lightweight independent CPU work may proceed within available resources. Do not let eight agents launch duplicate builds, identical datasets or competing training jobs.
- Each experiment begins with a hypothesis, expected failure mode addressed, frozen baseline, selection split, compute/time limit and stopping rule. Start with a bounded pilot; expand only when evidence warrants it. Two unsuccessful variants of the same idea require a new diagnosis before further sweeps.
- Poll confirmed process/session handles. A timeout is not evidence that a job stopped. Do not restart downloads/training just because observation timed out. Cancel work explicitly when the user stops or pauses the campaign, and record partial checkpoints as partial.

### Shared prediction and evaluation contract

Agent 2 freezes this contract before candidate work:

- Standard set: original nine plus additional nine faces, 47 targets each, **846 targets**. Use the exact names in the evaluator. Missing, invalid and rejected predictions count as zero; duplicates or omitted faces fail the input contract.
- Coordinates: physical em frame x=0...1.4, y=0...1; baseline 0.22, cap height 0.82. Native sample grids are 92 × 72 and 368 × 288. Do not independently align predictions to hidden targets. Input-derived normalization must be fixed before scoring.
- Frozen input JSON: an array of `{ "name": "Helvetica", "glyphs": [{ "character": "A", "contours": [[[x, y], ...], ...] }] }`. Preserve holes and contour winding. Record font identifiers only to join predictions to evaluation; never feed benchmark names into inference.
- Keep generation separate from scoring. Workers receive supplied references and permitted training priors. Evaluators read target outlines only after candidate predictions and selection parameters are frozen and hashed. Never use target outlines for candidate routing, correction, alignment or model selection.
- Separate training families, validation families and benchmark families. Record known lineages, duplicate/near-clone risks and exclusions. Repeatedly inspected benchmarks are development sets, not untouched generalization evidence. Agent 2 defines an additional unseen, style-stratified holdout before final promotion; agent 3 excludes it from all training and retrieval corpora.
- Reference-only adaptation is allowed. Its shared hyperparameters must be chosen on validation families. Do not tune against the withheld benchmark letters. Extra references constitute a separate task and score.
- Compare every candidate against the same native evaluator revision and corpus manifest. A scoring repair requires rechecking affected baselines. Do not count a changed metric, missing-glyph omission or evaluator correction as model improvement.
- Measure means, per-style/per-letter scores, worst cases, threshold coverage, validation/export failures, anchor-count median/p95/maximum, topology, curve-fit retention, latency and memory. Report raster and native-vector results distinctly. Low anchor count alone does not establish editability.
- Use the existing three-unit fitter as the initial vector-conversion baseline. Geometry changes need source-versus-result retention and topology checks plus native target scoring. Never improve an IoU number by silently erasing dots, closing counters or moving artwork.

Useful commands, using unique output paths for concurrent work:

```sh
python3 scripts/starter-research/build-prediction-auditor.py --output /tmp/typefield-prediction-auditor
python3 scripts/starter-research/test-prediction-auditor.py --binary /tmp/typefield-prediction-auditor
/tmp/typefield-prediction-auditor --audit-frozen-predictions /tmp/frozen-predictions.json
/tmp/typefield-prediction-auditor --audit-frozen-predictions /tmp/frozen-predictions.json --prediction-grid-scale 4
bash build.sh
node tests/figma-import.test.js
```

Inspect commands and environment first. The full installed-font catalog and local GPU may require approved execution outside the sandbox; missing GPU/catalog access must not silently change the benchmark. Reuse verified local artifacts when possible. Do not install dependencies globally or download arbitrary checkpoints without inspecting provenance, expected size and loading requirements. Use safe checkpoint loading (`weights_only=True` or an appropriate non-executable format).

### Worker handoff format

Each worker sends one concise handoff containing:

1. Hypothesis, owned files, starting revision and resulting commit(s).
2. Exact reproduction commands, dependencies, random seed and dataset/split/checkpoint hashes.
3. What inference reads; explicitly account for references, training priors and benchmark target isolation.
4. Baseline versus candidate results on the unchanged protocol, including regressions and failed/omitted outputs.
5. Editable-geometry and runtime evidence appropriate to the change; UI screenshots for editor/import behavior.
6. Artifact locations, remaining limitations, integration instructions and whether the candidate is ready for independent evaluation.

Keep raw fonts, predictions, checkpoints, screenshots and private evidence local under a role-specific `.context/qa-artifacts/` directory. Commit reproducible tools, focused tests and non-private result summaries. Do not commit the private manifests if they expose user font/library information. Preserve required temporary artifacts privately before ending a run; do not assume `/tmp` persists.

### Merge, validation and release

- Do not merge every approach simply because it exists. Agent 1 compares independently evaluated candidates and combines only compatible improvements. Failed approaches remain documented experiments, not production fallbacks by default.
- Before combination, freeze any mixture, selector or routing rule on validation data. Test both the individual contributions and the combined behavior. No hidden-target oracle or per-font benchmark-specific exceptions may become inference logic.
- Run relevant checks before every completed fix/feature commit and push the role branch to `origin`. Keep temporary or unverified work clearly separate. Agent 1 alone merges into the integration branch/main, after reviewing the exact diff and evidence. Do not force-push, reset shared history, or overwrite another agent's work.
- Integration must rerun the complete native benchmark, finer-grid check, additional/challenge cohorts, new holdout, glyph validation, TrueType export and applicable editor/import regression checks. Then run the full native suite and Figma bridge check. Verify representative dense imported and suggested glyphs through real edits and undo/redo in a disposable project.
- Regressions must be named and investigated; a pooled average must not hide broken script or handwriting cases. Keep a candidate experimental if it meets a numerical milestone but fails geometry, usability, runtime or integration checks.
- For a validated user-visible release, agent 1 bumps both version plists, updates changelog/status notes, builds and installs the single canonical `/Applications/Typefield.app` with `./install-local.sh`, then verifies installed version/signature and relevant runtime behavior. Preserve user data and compare saved-data hashes. Workers never install competing app builds.
- Final report: installed version; original/additional/challenge/holdout and pooled native scores; finer-grid score; editability/point-count results; tests; commits; failures; what actually shipped versus remains experimental. If 80–85% is not reached, state that plainly. Stop when the user asks; never keep a training job running merely to satisfy a numerical target.

### Suggested launch request

“Launch the eight-agent letterform team described in AGENTS.md using GPT-6 Luna Medium. Schedule within the actual concurrency limit, preserve the interrupted work, establish a common baseline, pursue the independent approaches, and integrate only independently verified improvements toward 80–85% native-vector similarity with practical editing.”
