# Exemplar-transfer candidate

This directory makes the frozen transfer-plus-learned candidate reproducible. The training-family exemplar is selected by nearest H/O/n/o/p signed-distance fields; a small U-Net predicts the missing-letter signed-distance fields. The companion equal blend was selected once on 92 family-held-out validation families. Neither inference script nor blend/export scripts read benchmark target outlines or use benchmark face names to choose predictions.

## Recovered evidence and result

The selected transfer checkpoint was trained on the 1,343-face family-split corpus (1,070 face records in the training split; 92 held-out validation families represented by one face each). The selected checkpoint is step 11,000. Its validation score was 65.5621%; its step-zero retrieval baseline was 58.3619%. The family-held-out selection run chose an equal signed-distance blend with the learned latent candidate: 66.3655% validation overlap. The separate expanded-corpus continuation reached a 63.9588% retrieval baseline and 64.6759% at step 1,000, then was interrupted at about step 1,300. It is partial and not used here.

On the frozen native-vector audit, transfer alone scored 61.7% original and 59.6% additional, with 844 valid letters and two rejected Zapfino outputs counted as zero. The selected equal blend scored 63.1% original and 60.4% additional across all 846 letters, with zero rejects and 18 successful exports. Its mean/max anchor counts were 66.28/432; curve-fit retention was 98.8% mean and 96.7% minimum. The transport-only candidate had 77.30 mean and 528 maximum anchors, with two rejected letters. The prior 63.2%/60.5% report was raster-only and is not the native score. These repeatedly inspected faces are development data; no fresh campaign holdout has been scored. The 80–85% objective remains unmet.

The exact frozen blend and contour conversion reproduced the coordinator's vector file byte for byte: SHA-256 `b07e9e8b750658b53fce3a1084c26f447fd6466bf37d19c77944c2725126e8ed`. A CPU-only rerun of the transfer model from the preserved checkpoint and reference masks had maximum absolute signed-distance error `1.70e-5` and mean absolute error `9.20e-8` against its original raster artifact. The tiny CPU/MPS floating-point difference means the fresh model inference array is not byte-identical; the frozen original arrays remain the exact input for byte-identical candidate recreation.

## Inference input contract

`predict_transfer.py` takes only an array shaped `(faces, 5, 72, 92)` in H/O/n/o/p order. Values are binary reference masks in the fixed frame. It loads the training corpus, excludes corpus families whose SHA-256 prefix maps to validation (`int(first_8_hex, 16) % 5 == 0`), retrieves a training exemplar using reference fields only, then loads the checkpoint with PyTorch `weights_only=True`. It returns signed-distance fields shaped `(faces, 47, 72, 92)`. It does not accept face names, target glyph fields, target vectors or evaluator scores. The caller is responsible for rasterizing only the five supplied reference outlines into this input.

Runtime dependencies used for the CPU reproduction: Python 3.12, NumPy 2.5.3, SciPy 1.18.1, PyTorch 2.14.0, contourpy 1.4.0. On the recorded Apple Silicon host, all 18 faces completed CPU inference in roughly six seconds; this is an environment-specific measurement, not a product latency guarantee. The app has no dependency on these scripts or research artifacts.

Private preserved artifacts are under `.context/qa-artifacts/letterform-team-2026-09-29/transfer/`. The historical fit used Python/NumPy/PyTorch seeds `17/17/17`; the family split is the SHA-256 rule described above. Exact recovered runner sources are `train-transport-original.py` (SHA-256 `c25a5bbcf4251bba55b3b3dd43502b8532f2e01c1cac454606428cee3d7e1689`), its shared `train-aa-base-original.py` (SHA-256 `7038743b901a1cc2ae55dde7274798c7058a8629cfcab0bb3c14a385c95cd68e`), and `combine-transport-original.py` (SHA-256 `9e9d5460ea8ddee0afcb3d75c0928699f162f679ca6e8dd642eea850c84f911a`). These are preserved research evidence; the original trainer uses temporary-path conventions and requires MPS, so it is not the recommended inference entry point.

The 1,591-face later corpus has metadata SHA-256 `09d47203ed98878ab068d18cc05286bbfa3bfe0cee52e0a8054ac51eaf06d484`, masks SHA-256 `de20268a93cbdeb1eb0e7a40aaf7451b33100f7effc11de169a9ac96b58b03e2`, and SDF SHA-256 `c2240cd4c1b0a1d20d842ca62ceb8d641c0abbd660b5547703c3f14f7c37926e`. The corpus was already used in expanded training/validation and is not a blind holdout. The attempt to continue transfer training on it was interrupted around step 1,300; its recovered checkpoint is only a partial artifact and does not replace the selected 1,343-face checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `transport-best.pt` | `9bbba410e81d7f533d14242d587c54d3804464acf0c304a92202994d5334a35d` |
| `base-font-masks.json` | `d2b5bd1b6879f575f8d6fa0c382e9936bc8a6ca613f024c35dffcfa080b0ca41` |
| `base-font-masks.bin` | `965d5d77cfaa724df388710fd8af4db7b41971e982c58ac5abe4af0fc7f441bd` |
| `base-conv-sdf.f16` | `cd083652a6df8b39f5503aa62e4a154ac0421bc0bac5574aa33f64e0b5aca249` |
| `benchmark-reference-masks.npy` (HOnop only) | `648f4b819699580ea5eb83a149c0c5d31f2f87649be5a4ced8e860d6d4137cbd` |
| `film-latent-predictions.npy` | `2d09e6b148b49ca8bf1ddad6fdfb944e6c8caae5ce2e9f3a847a0ee41e41a983` |
| `transport-predictions.npy` | `5187dda7ae30a7fc9c2edd04ae0420ef374d6e565671a3fada3a87774fd34515` |
| `combined-selection-original.json` | `149a21be90cf9b8e141b3388fac5c9fcb973d2aedcdf721faf5a961f00b71ec9` |

The corpora are font-derived and stay private. The 1,343-face base-family source provenance is incomplete; do not describe every record as source-font-license verified. In the later 1,591-face dataset, pinned-repository sources have font/license hash checks, but earlier base records are not completely joined to source provenance. Do not describe every record as source-font-license verified.

## Reproduction

Use the local research environment that has the dependencies above. Set paths to the preserved private artifacts and provide only five-reference masks to model inference:

```sh
python3 scripts/starter-research/transfer/predict_transfer.py \
  --references /path/to/reference-masks.npy \
  --metadata /path/to/base-font-masks.json \
  --masks /path/to/base-font-masks.bin \
  --sdf /path/to/base-conv-sdf.f16 \
  --checkpoint /path/to/transport-best.pt \
  --output /tmp/transport-predictions.npy --device cpu
```

To recreate the independently frozen combination, use the preserved original prediction arrays. `--selection` writes a copy of the policy record; it does not select a weight:

```sh
python3 scripts/starter-research/transfer/combine_predictions.py \
  --latent /path/to/film-latent-predictions.npy \
  --transport /path/to/transport-predictions.npy \
  --output /tmp/combined-predictions.npy \
  --selection /tmp/combined-selection.json
python3 scripts/starter-research/transfer/raster_to_vectors.py \
  --predictions /tmp/combined-predictions.npy \
  --face-names /path/to/benchmark-reference-order.json \
  --output /tmp/combined-contours.json
```

The last file supplies labels in the already frozen evaluator order. It is never read by inference or selection. The candidate JSON has exactly 18 faces by 47 letters in the evaluator's fixed 1.4-by-1 em frame. Run it through the independent native auditor before any integration decision.
