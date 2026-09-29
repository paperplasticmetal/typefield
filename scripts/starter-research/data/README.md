# Letterform corpus validation and data contract

`validate-corpus.py` hashes a frozen mask corpus, checks its fixed alphabet and frame, confirms face-to-index order and validates the optional float16 SDF length. `--verify-face-hashes` recomputes each face's SHA-256 over all 52 character masks. `--source-manifest` checks each downloaded source/license file against its recorded SHA-256. Manifests may contain font-family names and stay under `.context/qa-artifacts/`; do not commit them.

The current recovered artifact is the historical 92×72 `typefield-diverse-letters` corpus: 1,591 faces, 716 families, 52 characters, excluding Flow Block, Flow Circular, Flow Rounded and Redacted Script. Its exporter added Google Fonts sources pinned to `23e54b51ddffbc7713c583748e3bd86f62b1fa4a`; 274 accepted candidate families had OFL metadata, license text and source-font hashes checked before rendering. The base 1,207 records retain mask hashes, but their original-font provenance is not fully joined in the recovered metadata. Do not represent the whole corpus as license-verified at the source-font level.

This corpus already participated in expanded training and validation. It is useful for reproducing those studies, but it cannot serve as the campaign's blind holdout. Its historical family split is `int(first 8 hex chars of SHA256(UTF-8 family), 16) % 5 == 0` for validation. Family-level partitioning prevents face variants from crossing that split; it does not catch related families or near-clones. Add a reviewed lineage/exclusion list before training and retrieval. The evaluator must own a reserved holdout family file; pass that file as `--reserved-families` and reject any family overlap before producing worker corpora.

Example validation:

```sh
python3 scripts/starter-research/data/validate-corpus.py \
  --metadata /private/tmp/typefield-diverse-letters-font-masks.json \
  --masks /private/tmp/typefield-diverse-letters-font-masks.bin \
  --sdf /private/tmp/typefield-diverse-letters-conv-sdf.f16 \
  --source-manifest /private/tmp/typefield-diverse-training-fonts/manifest.json \
  --verify-face-hashes \
  --output /private/tmp/typefield-diverse-letters-manifest.json
```

For learned and transfer workers, the frozen inference contract is: five supplied references H, O, n, o, p; exactly 47 output letters; no benchmark target outlines or benchmark font identities at inference. Training and selection use only licensed training-family material. Keep generation artifacts separated from scoring. Freeze a whole-font family split and any near-clone exclusions before model selection; use the evaluator's separately reserved holdout only once for promotion evidence.

## Coverage findings

The 716-family metadata name scan finds 14 families containing “Script,” 7 containing “Hand,” 3 containing “Brush,” and 2 containing “Bubble.” These are search hints, not reviewed style labels. The training metadata has no style taxonomy or direct thin-stroke measurements. Existing native trials explicitly report handwriting and script as weak; bubble lettering is sparsely named. Coverage should therefore be audited from rendered shape features and a human-reviewed style roster, especially connected-script joins, thin hairlines, handwriting irregularity, outlined/bubble counters and small detached marks. Do not oversample based only on family-name substrings.

Next corpus revision should attach, per source face, the canonical family, repository path and pinned revision, source file hash, license identifier and license text hash, variable-axis coordinates, glyph availability, source lineage, and style tags with evidence. Keep families intact across splits, collapse exact duplicate masks, review normalized-shape near-duplicates across families, and exclude all previously seen benchmark, challenge and development lineages. Do not use benchmark masks to construct features or labels.
