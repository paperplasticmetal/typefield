#!/usr/bin/env python3
"""Validate a frozen Typefield glyph-mask corpus and write a private manifest.

The face hash in metadata covers that face's complete character-major uint8
mask block. Family splits use a stable SHA-256 rule, with evaluator-reserved
families excluded before assignment. This tool never opens benchmark outlines.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

EXPECTED_CHARACTERS = list("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
EXPECTED_WIDTH = 92
EXPECTED_HEIGHT = 72
EXPECTED_EXCLUDED = {"Flow Block", "Flow Circular", "Flow Rounded", "Redacted Script"}
FACE_BYTES = len(EXPECTED_CHARACTERS) * EXPECTED_WIDTH * EXPECTED_HEIGHT


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def family_bucket(family: str, validation_modulus: int = 5) -> str:
    """Reproduce the established 1-in-5 validation-family assignment."""
    number = int.from_bytes(hashlib.sha256(family.encode("utf-8")).digest()[:4], "big")
    return "validation" if number % validation_modulus == 0 else "train"


def normalized_family(family: str) -> str:
    return "".join(char.lower() for char in family if char.isalnum())


def read_family_file(path: Path | None) -> set[str]:
    if path is None:
        return set()
    data = json.loads(path.read_text())
    if isinstance(data, dict):
        data = data.get("families", [])
    if not isinstance(data, list) or not all(isinstance(x, str) for x in data):
        raise ValueError(f"{path}: expected a JSON array of family names or {{'families': [...]}}")
    return set(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--masks", required=True, type=Path)
    parser.add_argument("--sdf", type=Path, help="optional float16 signed-distance fields")
    parser.add_argument("--reserved-families", type=Path,
                        help="evaluator-owned JSON names excluded from all training splits")
    parser.add_argument("--source-manifest", type=Path, action="append", default=[],
                        help="Google Fonts download manifest; repeat for each corpus source")
    parser.add_argument("--output", required=True, type=Path,
                        help="private JSON manifest destination")
    parser.add_argument("--verify-face-hashes", action="store_true",
                        help="recompute every per-face mask digest; reads the full mask file")
    args = parser.parse_args()

    meta = json.loads(args.metadata.read_text())
    errors: list[str] = []
    records = meta.get("records")
    if not isinstance(records, list):
        raise ValueError("metadata.records must be an array")
    if meta.get("characters") != EXPECTED_CHARACTERS:
        errors.append("character order is not the fixed A-Z then a-z alphabet")
    if (meta.get("width"), meta.get("height")) != (EXPECTED_WIDTH, EXPECTED_HEIGHT):
        errors.append("mask dimensions differ from the established 92x72 frame")
    actual_excluded = set(meta.get("excludedPlaceholderFamilies", []))
    if actual_excluded != EXPECTED_EXCLUDED:
        errors.append(f"placeholder exclusion set differs: {sorted(actual_excluded)}")

    families: dict[str, list[dict]] = defaultdict(list)
    seen_hashes: dict[str, str] = {}
    for index, record in enumerate(records):
        if record.get("index") != index:
            errors.append(f"record {index}: index mismatch")
        family = record.get("family")
        name = record.get("name")
        digest = record.get("sha256")
        if not all(isinstance(x, str) and x for x in (family, name, digest)):
            errors.append(f"record {index}: missing family/name/sha256")
            continue
        families[family].append(record)
        if family in EXPECTED_EXCLUDED:
            errors.append(f"placeholder family remains in corpus: {family}")
        old_family = seen_hashes.get(digest)
        if old_family and old_family != family:
            errors.append(f"exact duplicate mask hash crosses families: {old_family} / {family}")
        seen_hashes[digest] = family

    expected_mask_bytes = len(records) * FACE_BYTES
    if args.masks.stat().st_size != expected_mask_bytes:
        errors.append(f"mask byte size {args.masks.stat().st_size} != expected {expected_mask_bytes}")
    if args.sdf:
        expected_sdf_bytes = len(records) * FACE_BYTES * 2
        if args.sdf.stat().st_size != expected_sdf_bytes:
            errors.append(f"SDF byte size {args.sdf.stat().st_size} != expected {expected_sdf_bytes}")

    if args.verify_face_hashes and args.masks.stat().st_size == expected_mask_bytes:
        with args.masks.open("rb") as stream:
            for index, record in enumerate(records):
                actual = hashlib.sha256(stream.read(FACE_BYTES)).hexdigest()
                if actual != record.get("sha256"):
                    errors.append(f"face hash mismatch at record {index} ({record.get('family')})")

    reserved = read_family_file(args.reserved_families)
    reserved_present = sorted(reserved & set(families))
    if reserved_present:
        errors.append("evaluator-reserved families occur in corpus: " + ", ".join(reserved_present))

    source_info = []
    for source_path in args.source_manifest:
        source = json.loads(source_path.read_text())
        results = source.get("results", [])
        files = source.get("files", [])
        accepted = {normalized_family(item.get("family", "")) for item in results if item.get("status") == "accepted"}
        broken: list[str] = []
        for item in files:
            local = Path(item.get("localPath", ""))
            if not local.is_file():
                broken.append(f"missing {item.get('path')}")
                continue
            if sha256_file(local) != item.get("sha256"):
                broken.append(f"hash mismatch {item.get('path')}")
        licenses = [item for item in files if item.get("path", "").endswith("/OFL.txt")]
        report = {
            "manifestPathName": source_path.name,
            "manifestSha256": sha256_file(source_path),
            "repository": source.get("repository"),
            "commit": source.get("commit"),
            "candidateFamilies": len(results),
            "acceptedFamilies": len(accepted) if results else None,
            "sourceFontFiles": sum(1 for item in files if item.get("path", "").lower().endswith((".ttf", ".otf"))),
            "licenseTextFiles": len(licenses),
            "localFileHashFailures": broken,
            "acceptedFamiliesMissingFromMaskRecords": sorted(accepted - {normalized_family(family) for family in families}),
        }
        source_info.append(report)
        if broken:
            errors.append(f"{len(broken)} source manifest files failed presence/hash checks in {source_path.name}")
        if results and len(licenses) != len(accepted):
            errors.append(f"accepted source families do not each have one recorded license text in {source_path.name}")

    histogram = Counter(family_bucket(family) for family in families)
    family_summary = {
        family: {
            "faces": len(items),
            "split": "reserved" if family in reserved else family_bucket(family),
            "recordIndices": [item["index"] for item in items],
            "maskHashes": [item["sha256"] for item in items],
        }
        for family, items in sorted(families.items())
    }
    manifest = {
        "schemaVersion": 1,
        "datasetId": "typefield-diverse-letters-92x72-v1",
        "status": "invalid" if errors else "validated",
        "sourceMetadata": {"pathName": args.metadata.name, "sha256": sha256_file(args.metadata)},
        "maskData": {"pathName": args.masks.name, "bytes": args.masks.stat().st_size, "sha256": sha256_file(args.masks)},
        "sdfData": None if not args.sdf else {"pathName": args.sdf.name, "bytes": args.sdf.stat().st_size, "sha256": sha256_file(args.sdf)},
        "shape": {"faces": len(records), "families": len(families), "characters": len(meta.get("characters", [])), "width": meta.get("width"), "height": meta.get("height"), "faceMaskBytes": FACE_BYTES},
        "splitContract": {"algorithm": "sha256(utf8(family))[0:4] as big-endian integer modulo 5; residue 0 is validation", "familyCounts": dict(histogram), "reservedFamilyFileSha256": None if not args.reserved_families else sha256_file(args.reserved_families)},
        "sourceProvenance": source_info,
        "knownLimitations": [
            "This historical corpus has already participated in expanded training/validation and is ineligible as a blind holdout.",
            "Per-face mask hashes bind pixels to metadata; only source manifests bind an original font file and license.",
            "A family-name split does not catch cross-family design lineages or near-clones; those require a separate reviewed exclusion manifest.",
        ],
        "families": family_summary,
        "errors": errors,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": manifest["status"], "faces": len(records), "families": len(families), "splits": dict(histogram), "reservedPresent": reserved_present, "source": source_info, "errors": errors}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"validate-corpus: {error}", file=sys.stderr)
        raise SystemExit(2)
