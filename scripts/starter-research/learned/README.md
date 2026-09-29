# Learned synthesis pilot

## Clipped-SDF ridge/radius auxiliary pilot

This one bounded experiment tested whether auxiliary ridge and local-radius
heads could improve the frozen SDF completion CNN. It did **not** test a full
medial-axis reconstruction: the recovered SDF corpus clips values at six
pixels, so wide interior regions can saturate and produce imprecise ridge
targets. Radius supervision was corrected to convert normalized SDF values
back to pixel units before the run.

The pilot started from the family-balanced checkpoint
`/private/tmp/typefield-balanced-conv-best.pt`, SHA-256
`4e28aad2ed07e0b12bb614021e03ed66de9d0f9a76cafdd46afb77dfe7f5d229`. Its
input corpus was `/private/tmp/typefield-diverse-letters-font-masks.json`
(1,591 faces / 716 families, SHA-256
`09d47203ed98878ab068d18cc05286bbfa3bfe0cee52e0a8054ac51eaf06d484`), with masks in
`/private/tmp/typefield-diverse-letters-font-masks.bin` (SHA-256
`de20268a93cbdeb1eb0e7a40aaf7451b33100f7effc11de169a9ac96b58b03e2`) and clipped SDF fields
in `/private/tmp/typefield-diverse-letters-conv-sdf.f16` (SHA-256
`c2240cd4c1b0a1d20d842ca62ceb8d641c0abbd660b5547703c3f14f7c37926e`). See
the data role's README for provenance limits: the source-font join for 1,207
base records is incomplete, and this corpus has already participated in
training and validation. It is not a new blind holdout.

Selection used the historical family hash split in the script, yielding
1,267 training faces and one representative from each of 143 held-out
families. The five reference fields H O n o p were the model inputs; the
47 other letters were scored only on those held-out training-corpus families.
No benchmark font identities or hidden benchmark targets entered training,
selection, or inference. This pilot did not generate benchmark predictions.

Reproduction on macOS with the existing private environment:

```sh
/private/tmp/typefield-ml-venv/bin/python scripts/starter-research/learned/skeleton_aux_pilot.py \
  --max-seconds 900 \
  --output-dir /private/tmp/typefield-skeleton-pilot
```

Dependencies: Python 3.12, PyTorch 2.14.0 with MPS, NumPy, and the frozen files
listed above. Seed: 2909. Checkpoint loading uses `weights_only=True`. The
script requires MPS and does not silently fall back to CPU.

The frozen SDF head scored 0.60615 mean validation IoU at step 0. Fine-tuning
with ridge/radius auxiliary losses scored 0.59656 at step 400, 0.59336 at step
800, and 0.58608 at step 1200. The no-improvement rule stopped the run after
1,200 steps / 113.6 seconds and retained step 0. Therefore the run produced
no learned improvement and no candidate for benchmark inference or native
vector evaluation. The step-zero checkpoint preserves the initial SDF weights;
the added auxiliary heads do not establish a usable prediction change.

The completed log, report, input hashes, and step-zero checkpoint are kept
privately under `.context/qa-artifacts/letterform-team-2026-09-29/learned/`.
The pilot is a negative result for this clipped-SDF auxiliary setup only. A
proper follow-up would need exact distance/skeleton targets derived from raw
binary masks, a newly authorized bounded run, and evaluator review before any
benchmark prediction.
