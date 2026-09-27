# Missing-letter fidelity: the path toward 90% shape overlap

The current assist is a deterministic outline generator, not a trained model. Its nine-face audit supplies only H O n o p and compares the 47 hidden letters against their original outlines. The 0.52 mean was 46.5% sampled silhouette intersection-over-union (IoU). This is neither recognition accuracy nor a probability that a user will accept a suggestion.

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
