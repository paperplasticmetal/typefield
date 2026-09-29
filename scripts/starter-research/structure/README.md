# Structural construction pilot: an n-derived w

Baseline revision: `c82d271558462b69b1856cefe82c230e108a69f1`.

## Hypothesis

The generic lowercase `w` was among the weakest outputs in the existing native audits. Since supplied lowercase `n` already contains the same design's arch, reflect that outline around the project's baseline and x-height and place two copies side by side. The candidate reads only the supplied `n` and project guides. It does not inspect hidden glyphs, font identities, or benchmark targets. The reflection and duplication parameters were fixed before the validation audit.

The construction reuses the source vector paths, reverses winding after reflection, and preserves the source's physical stroke weight and italic lean. Its copies retain the source's editable nodes instead of tracing a raster.

## Reproduction

On Apple Silicon macOS with the repository's Swift sources and local fonts:

```sh
python3 scripts/starter-research/structure/pilot-inverted-n-for-w.py \
  --source-root "$PWD" \
  --output /private/tmp/typefield-structure-pilot-20260929
/private/tmp/typefield-structure-pilot-20260929/typefield-structure-pilot \
  --starter-quality-audit --starter-validation-set --starter-quality-details
```

The script uses only the Python standard library. It copies Swift sources to its output directory, applies the pilot there, and compiles with warnings as errors. The source checkout is left untouched. For the paired baseline, compile the unmodified `Sources/*.swift` with the same `swiftc -warnings-as-errors -swift-version 5 -O -target arm64-apple-macosx13.0` flags and run the same audit arguments. The audit uses only H O n o p at inference and scores all 47 targets for all nine validation faces.

## Result and decision

The candidate was rejected. On the nine validation faces (423 targets), its pooled mean fell from **48.3% to 48.1%**; no target was omitted. The `w` itself averaged **32.8% → 23.3%** across the nine faces: seven regressed, while Comic Sans improved 17.6% → 28.4% and Zapfino improved 8.5% → 11.0%. The other seven faces lost 6.5–21.3 points. The worst face remained Zapfino at 16.3% pooled glyph overlap.

| Validation face | Baseline `w` | Reflected `n` pair | Change |
| --- | ---: | ---: | ---: |
| Georgia | 42.7% | 27.4% | −15.3 pp |
| Verdana | 31.7% | 25.2% | −6.5 pp |
| Trebuchet MS | 42.7% | 23.3% | −19.4 pp |
| Baskerville | 33.2% | 24.4% | −8.8 pp |
| Cochin | 38.4% | 22.9% | −15.5 pp |
| American Typewriter | 43.7% | 31.1% | −12.6 pp |
| Comic Sans MS | 17.6% | 28.4% | +10.8 pp |
| Bradley Hand | 37.0% | 15.7% | −21.3 pp |
| Zapfino | 8.5% | 11.0% | +2.5 pp |

Every face returned all 47 valid candidates. The pilot's overall glyph count, mean anchors, and maximum anchors were respectively 47, 16.6–57.3, and at most 326 across faces; those counts include every glyph, so they do not establish a per-`w` editability result. Full TrueType export and the remaining benchmark cohorts were not run because the validation result rejected the approach. The old held-out sets are repeatedly observed development data, not blind evidence.

The isolated candidate and baseline binaries and logs were kept under `/private/tmp/typefield-structure-{pilot,baseline}-20260929`; they contain local-font-derived scores and are not repository artifacts. No production `Sources/` file changed.
