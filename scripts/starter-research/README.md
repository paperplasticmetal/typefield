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
