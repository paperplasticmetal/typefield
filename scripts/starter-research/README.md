# Missing-letter research harness

`reference-retrieval.swift` is an **offline research experiment**, not an app generation backend. It reads locally installed outlines, matches only H O n o p, and applies the chosen font's reference-fitted width, x-height, lean and weight to unseen letters. No user project is loaded or saved. No fonts or model weights are bundled.

```sh
swiftc -O -module-cache-path /tmp/typefield-study-cache scripts/starter-research/reference-retrieval.swift -o /tmp/typefield-reference-study
/tmp/typefield-reference-study
```

The nine development families and their known name-prefix lineages are excluded from the candidate catalog before fitting. Other families can still contain closely related Latin designs, so this is **not proof of generalization to novel handwriting**. Candidate availability depends on the local installed catalog; the recorded experiment used 3,994 candidates. A missing required target face fails the experiment rather than substituting another face.

The top candidate is chosen using reference letters only. The script prints the top three for diagnosis, but its aggregate uses **rank 1 only**; never choose among them using the hidden-target score. Final overlap uses the application's 92 × 72 sample positions in a fixed 1,400 × 1,000 frame. The research harness uses direct Core Text outlines; the application audit additionally validates and normalizes its editable glyph representation. Do not treat these pipelines as identical, and do not call either overlap score calibrated confidence.

A high match to supplied references is insufficient: the reference-matching prototype scored 60.9% overall, and its most difficult style remained below 15%. An optional bearing-calibration trial and separate-case selection both regressed. A distance-field mixture gave 65.3% at a different 128 × 128 raster resolution (single-candidate comparator 63.6%); it has **not** passed the editable-vector or app-integration checks. These are development results, not an 85% achievement.

Any future product use of retrieved outlines must show their installed-font provenance instead of describing them as a user's original drawing. Research code does not change the current source-only, editable suggestion workflow.

## Compact reference export

`build-reference-exporter.py` compiles a temporary copy of the application sources with an additional research CLI. It does not add that CLI to the application or modify its sources. The exporter reads only the eight supplied characters **H a b e g m r u** from the nine development faces. It never exports the hidden alphabet or loads a saved project.

```sh
python3 scripts/starter-research/build-reference-exporter.py --output /tmp/typefield-reference-exporter
/tmp/typefield-reference-exporter --export-model-references /tmp/typefield-eight-refs.json --units 3
```

The reversible fitting frame preserves physical aspect ratio. Unsafe fits retain the complete original outline rather than truncating it to a model's command budget. The JSON includes raw-em paths, bounds, advance widths, font guide heights and before/after node counts. Keep generated files local; this repository does not distribute font outlines. The build command currently targets Apple Silicon macOS 13 or later, matching the application.

Verification on 72 references at 384 × 384 samples per outline found a minimum source/fitted IoU of **97.31%** and maximum bounding-box deviation below **0.001 em**. The largest contour still has 60 commands; compacting does not guarantee compatibility with a 32-command model. Invalid fit tolerances fail before writing output.

The DesigNet experiment used these compact references with strict pretrained-weight loading, canonical path ordering, and the model's documented **even-odd fill rule**. Input positional capacity was extended analytically; decoder capacity and learned weights were unchanged. Reference-only size/weight calibration reached **36.0%** across its 44 withheld letters per face. Its official continuity/alignment refinement regressed to **33.9%**. This eight-reference experiment is not comparable to the production five-reference task and is not included in the application. See the [official model implementation](https://github.com/TomasGuija/DesigNet).

A separate smooth deformation of the distance-field mixture, selected by leave-one-supplied-reference-out validation, reached **65.6%** versus the same-raster mixture's **65.3%**. It still has no validated editable-vector output. Neither experiment reaches the requested 85% target.

## Local learned-prior trials

Further local experiments used installed faces whose font metadata explicitly names the Open Font License. All 18 development/additional benchmark family lineages were excluded. Exact duplicate alphabet masks were removed, at most six styles per family were retained, and a deterministic family hash reserved roughly one fifth of the families for model selection. Only H O n o p entered test-time prediction; test targets were scored after predictions were frozen.

| Research variant | Original nine faces | Additional nine faces |
| --- | ---: | ---: |
| Signed-distance kernel predictor, 1,036 faces / 289 families | 62.8% | 61.4% |
| Separate normalized-shape and bounding-box prediction, same corpus | 59.9% | 60.2% |
| Expanded predictor including overflow ascenders/descenders, 1,213 faces / 360 families | 62.3% | 61.6% |

These trials used direct Core Text rasterization at 92 × 72, not the app's point-in-path sampler and validated editable geometry. The normalized experiment's raster-coordinate convention was checked by a source-only round trip and corrected before reporting results. Entire-family separation and exact-mask deduplication do not eliminate related designs or near clones across families. The models still failed badly on cursive and did not replace the application generator. No raster/vector-generator weights, font masks or font outlines are distributed here; private experiment scripts, logs and proofs are retained with local QA evidence.


## Production width prior (0.58)

`export-width-training.swift` exports only numeric width features and targets, plus family names and exact-alphabet raster hashes. It reads installed fonts whose metadata explicitly names the Open Font License, excludes the 18 benchmark family lineages, caps each family at six faces and deduplicates exact alphabet masks. It does not save outlines or raster masks. The original supported-frame cohort contains 1,036 faces / 289 families.

`train-width-prior.py` needs NumPy. It uses eight dimensionless log ratios from H O n o p to predict log widths for 47 other letters. A deterministic family split (822 selection-training faces, 214 validation faces from 59 families) selects ridge regularization; frozen normalization and ridge 0.1 are then used to refit all 1,036 faces. Held-family log-width MSE is 0.015688125. The generated constants reproduce the research coefficients within floating-point roundoff. The dataset SHA-256 is recorded in the model and generated source. Catalog-dependent regeneration may produce a different cohort and must be reevaluated.

```sh
swiftc -O -warnings-as-errors -module-cache-path /tmp/typefield-study-cache scripts/starter-research/export-width-training.swift -o /tmp/typefield-width-export
/tmp/typefield-width-export /tmp/typefield-width-training.json
python3 scripts/starter-research/train-width-prior.py --dataset /tmp/typefield-width-training.json --output /tmp/typefield-width-prior.json --swift-constants /tmp/typefield-width-constants.swift
```

The app embeds only the small numeric model in `FontLabWidthPrior.swift`. There is no Python dependency, downloaded checkpoint, font lookup or source-outline retrieval at runtime. Missing references, out-of-range standardized features, monospaced projects and unsupported output geometry keep the previous construction. Full predicted ink widths are not reduced again by H's stem-row insets; real drawing padding is retained in the side bearing. The four-standard-deviation fallback is a domain guard, not confidence calibration. Exact family exclusions do not rule out related designs in other families.

Frozen width parameters were also checked prospectively on Palatino, Gill Sans, Optima, Rockwell, Bodoni 72, Didot, Futura, Copperplate, Brush Script and Chalkduster: 48.5% → 50.4%. None of those family names occurs in the width-training cohort. These faces have now been observed and are no longer an untouched final evaluation set. Use `--starter-challenge-set` for this set, `--starter-validation-set` for the earlier additional nine and `--starter-disable-width-prior` to reproduce the 0.57 construction. To disable both width adaptation and all cap-stem reuse, pass both ablation flags.

A subsequent DesigNet convention check made every contour, including holes, positive-winding before even-odd filling, matching the upstream demo. Reference-only calibration reached 38.9%, still unsuitable. A local conditional convolutional pilot reached 60.8% / 57.9% on the two raster sets; its held-family validation selected the checkpoint before target scoring. It also remains research-only.


An expanded temporary corpus adds directly loaded OFL fixtures from the [Google Fonts repository](https://github.com/google/fonts), pinned at `23e54b51ddffbc7713c583748e3bd86f62b1fa4a`. Downloaded file hashes and per-family licenses were checked; no fonts were registered or installed. After exact alphabet-mask deduplication the combined corpus contains 1,343 faces / 466 families. A family-balanced convolutional trial, selected on 92 held-out families, reached **65.7% / 62.6%** on the existing raster sets. Reference-only latent adaptation, whose step count was also selected using those validation families, reached **66.6% / 63.6%**. An expanded kernel trial reached **63.6% / 62.3%**. None is a production-vector result or an 85% achievement; all test-time adaptation uses supplied H O n o p only.


### Native vector check and raster correction

The later low-learning-rate and reference-only latent trial reached 67.7% / 64.3% against the research rasters, but only **59.8% / 56.0%** after conversion to editable vectors and comparison with native outlines. The gap was investigated before any product integration. Core Graphics' no-antialias raster coverage differed substantially from the native point sampler: a source-only Helvetica round trip scored 79.4% before prediction. Antialiased rendering thresholded at 128 restored that round trip to **99.7%**. This is a conversion diagnostic, not model accuracy.

After regenerating the same 1,343-face corpus and retraining, held-family validation selected the checkpoint and 20 reference-only latent steps. Corrected raster scores were **62.3% / 58.8%**; native editable-vector scores were **62.2% / 58.7%**. Every one of the 846 outputs passed glyph validation and TrueType export. Curve fitting retained 98.6% mean / 96.9% minimum overlap against its unfitted prediction on the finer fixed grid, with 35.7 mean / 354 maximum anchors. This does not establish uniformly easy editing, and the finer 368 × 288 target-overlap check scores 61.6% / 58.0%. Handwriting and script remain weak.

A fixed hybrid that retained all existing `adapted` suggestions and used the learned model for the other letters regressed to **61.2% / 57.4%**. It was rejected; no per-target winner was selected against hidden truth. These models are private research artifacts, not shipped functionality. The installed 0.58 generator remains at **53.6% / 48.3%**, with the separate ten-face check at 50.4%.

The [official DeepVecFont-v2 implementation](https://github.com/yizhiwang96/deepvecfont-v2) was inspected at revision `de5f6e290a570ac5fd0a5858d0e2df48ccc6c51c`. Its public English checkpoint folder was accessible anonymously through the browser, but the download failed in browser tooling; checkpoint inference was not completed or scored. Do not describe that model as evaluated. The 85% objective remains unmet.


## Reproducible frozen-vector audit

`build-prediction-auditor.py` builds an isolated source snapshot with the research-only `--audit-frozen-predictions` entry point. The shipped app is unchanged. Its JSON input is an array of `{ "name": "Helvetica", "glyphs": [{ "character": "A", "contours": [[[x, y], ...], ...] }, ...] }` records. Coordinates are physical em units in the fixed x=0...1.4, y=0...1 frame, baseline 0.22 and cap height 0.82. They must come from frozen predictions; this evaluator performs no inference.

All original and additional 18 named faces must appear exactly once. Duplicate or unexpected characters and incomplete face sets are rejected. Missing, invalid or unsupported predictions count as zero across the full 846-target denominator. Valid contours pass through the existing three-unit curve fitter, preserving unfittable outlines, then through TrueType export. The report includes both set means, worst face, ≥85% coverage, invalid counts, anchor counts and finer-grid fit retention. A successful exit means measurement completed, not that quality passed 85%.

```sh
python3 scripts/starter-research/build-prediction-auditor.py --output /tmp/typefield-prediction-auditor
/tmp/typefield-prediction-auditor --audit-frozen-predictions /tmp/frozen-predictions.json
/tmp/typefield-prediction-auditor --audit-frozen-predictions /tmp/frozen-predictions.json --prediction-grid-scale 4
```

Keep prediction files and font-derived artifacts private. Do not recenter, rescale or choose individual predictions against the withheld target before invoking this audit.


### Higher-resolution trial

A 184 × 144 output trial reused the same 1,343-face / 466-family cohort and selected its checkpoint and reference-only latent refinement on the same 92 held-out families. Frozen editable predictions reached **62.6% / 58.2%** on the native 92 × 72 grid and **62.2% / 57.8%** on the 368 × 288 grid. All 846 letters validated and all 18 temporary faces exported. Mean anchors increased to **38.9**, with **892** in the worst glyph; mean/minimum fit retention was 98.7% / 96.2%. This is not a consistent accuracy improvement and worsens worst-case editability, so it is not retained for the application.

The reusable auditor reproduced the earlier corrected model's **62.2% / 58.7%**, including all 846 targets and 77 above 85% overlap. Its seven input/denominator regression cases pass. Run them with `python3 scripts/starter-research/test-prediction-auditor.py --binary /tmp/typefield-prediction-auditor`. Research-only compilation uses the current app sources with warnings as errors; it does not alter or install the app. The 85% objective remains unmet.


### Overlap loss, decoder conditioning and reference stroke calibration

Three subsequent trials used the same corpus and 92-family selection set. All benchmark predictions were frozen before native scoring. These repeatedly observed development sets are not a new untouched generalization test.

| Editable-vector variant | Original nine | Additional nine | Fine-grid original / additional | Mean / maximum anchors |
| --- | ---: | ---: | ---: | ---: |
| Overlap-focused training loss, 20 reference-only latent steps | 62.8% | 58.6% | 62.2% / 58.1% | 41.2 / 310 |
| Style modulation at every decoder stage, 20 reference-only latent steps | 62.5% | 58.8% | Not measured | 38.1 / 296 |
| Same decoder, stroke threshold fitted to supplied references | 62.4% | 58.9% | 61.9% / 58.2% | 37.5 / 318 |

Every row contains all 846 targets, zero rejected predictions and 18 successful temporary TrueType exports. The first variant has 77/846 glyphs above 85% overlap; the other two have 78/846. Stroke calibration selected its shared strength on the family-held-out set, while each face's threshold came only from H O n o p. No benchmark target selected a threshold, checkpoint, latent step count or per-letter winner. The overlap-loss selection score reached 63.4% before latent adaptation; stage-wise style modulation reached 64.1% after adaptation and 64.3% with stroke calibration. These selection scores are not benchmark results or confidence estimates.

The remaining errors include missing thin strokes, misplaced script connections and incorrect counters. None of these experiments meets 85%, and no learned-outline model was integrated or installed. The application remains 0.58.0; user project and library hashes remain unchanged.
