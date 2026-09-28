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
