# Missing-letter fidelity: the path toward 90% shape overlap

The current assist constructs editable outlines procedurally. Version 0.58 adds a small trained width prior; it does not generate learned curves or calibrated confidence. Its nine-face audit supplies only H O n o p and compares the 47 hidden letters against their original outlines. The 0.52 mean was 46.5% sampled silhouette intersection-over-union (IoU). This is neither recognition accuracy nor a probability that a user will accept a suggestion.

## What 90% should mean

For shape similarity, measure the intersection divided by the union of generated and held-out ink in the same physical coordinate frame. Do not independently recenter or stretch the predicted letter to make the score look better. Track widths, side bearings, counters, disconnected parts, and editing-anchor counts separately. A mean of 90% must not conceal a style category with poor performance; publish per-style and per-character results as well as missing/failed output counts.

Import fidelity is a separate problem: its original outline is available, so constrained fitting can already retain over 97% ink overlap. Missing-letter inference has no target outline to copy. A single-storey or double-storey a/g, script joins, and distinctive terminals cannot always be determined from five unrelated letters.

## Development sequence

1. Fix systematic geometry errors and maximize reuse of supplied contours. The 0.53 work addresses clustered trace corners, unintended stem thickening during width fitting, e bowl reuse, and slant-aware reflections. Keep the existing holdout unchanged to expose regressions.
2. Measure reference coverage. Compare five, eight and twelve supplied letters on a common set of unseen target characters. Choose the next requested reference to resolve a specific ambiguity, rather than asking for more arbitrary drawings. Evaluate connected handwriting separately from disconnected marker lettering.
3. Benchmark learned vector generation alongside the procedural baseline. DeepVecFont-v2 accepts configurable reference glyphs and outputs SVG candidates, but its documented environment uses CUDA. DesigNet explicitly models continuity and alignment for editable SVG geometry. These are research candidates, not proof of 90% fidelity or confirmed native Mac integrations. Preserve compact Béziers throughout instead of rasterizing the generated output and tracing it again.
4. Use a licensed, family-disjoint corpus for training, tuning and final evaluation; include real scans, uneven markers, thick bubble counters and connected scripts. Never select a candidate against the hidden target during inference. Candidate ranking must use only the supplied references and learned priors. Reserve an untouched evaluation set after tuning on the present nine faces.
5. Ship only after both fidelity and editing checks pass. Measure at multiple raster resolutions; inspect proofs at small and large sizes; reject invalid contours. Report what percentage of missing letters reaches the 90% shape threshold, alongside the mean and worst categories. An uncertainty label should reflect measured reliability, not whether a contour happened to be reused.

No model download, training run, user-artwork upload or 90% achievement is implied by this plan.

Primary research implementations: [DeepVecFont-v2](https://github.com/yizhiwang96/deepvecfont-v2), [DesigNet](https://github.com/TomasGuija/DesigNet).

## 0.54 measured outcome

Further construction/bowl corrections reach 56.1% on the original five faces and 51.5% across nine. On a shared 40-letter target set, 5/8/12 references score 52.8%/52.9%/53.2%; supplying more drawings does not make the existing templates sufficiently style-aware. A source-calibrated stroke-contrast experiment was rejected after failing to improve the mean. These results strengthen the need for the vector-model and held-out-family experiments above; they do not establish that 90% is achievable with the present architecture. Suggestions are explicitly experimental and opt-in per letter. See [0.54 QA](QA_2026-09-27_0.54.md).

## 0.56 measured outcome

Source-stem reuse raises the unchanged nine-face development mean to 52.3% (52.4% at a finer grid), with a separate nine-face check improving 45.0% → 46.7%. The outline and stronger-prior experiments, rejected variants, and reproducible protocol are recorded in [0.56 QA](QA_2026-09-27_0.56.md). A research font-prior route reaches 60.9% on the audit grid; a different-resolution raster mixture reaches 65.3%, pending vector validation. The first pretrained vector-model adapter performs poorly and is not integrated. None establishes 85% confidence. The major remaining work is a style-diverse, licensed training/evaluation pipeline and reliable script/handwriting generation; isolated high-overlap letters do not resolve that gap.

## 0.57 measured outcome

H-stem reuse for K/M/N reaches 52.9% across the original nine faces (53.0% at the finer grid) and 47.3% on the additional nine. The source-curve and learned-prior experiments are documented in [0.57 QA](QA_2026-09-28_0.57.md). A local training trial now covers up to 1,213 distinct open-licensed faces across 360 families, but the resulting raster predictor remains around 62% and fails badly on connected script. The 85% target remains active and unachieved; no weaker metric, favorable subset or raster-only result is substituted for it.


## Width prior result (0.58)

A small learned width model improves native overlap to 53.6% / 48.3% across the existing two sets and 50.4% on ten additional faces. It preserves procedural curves, compact construction and source-only inference. It does not solve script anatomy, serif contrast or target-specific spacing. The 85% request remains open; see [0.58 QA](QA_2026-09-28_0.58.md).
