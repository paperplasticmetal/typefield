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
