#!/usr/bin/env python3
"""Apply the frozen family-validation blend to two signed-distance predictions."""
import argparse
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latent", required=True, help="film/learned signed-distance .npy")
    parser.add_argument("--transport", required=True, help="exemplar-transfer signed-distance .npy")
    parser.add_argument("--output", required=True, help="combined signed-distance .npy")
    parser.add_argument("--selection", help="write the frozen policy metadata here")
    args = parser.parse_args()

    latent = np.load(args.latent, mmap_mode="r", allow_pickle=False)
    transport = np.load(args.transport, mmap_mode="r", allow_pickle=False)
    if latent.shape != (18, 47, 72, 92) or transport.shape != latent.shape:
        raise SystemExit(f"expected two (18,47,72,92) arrays, got {latent.shape} and {transport.shape}")
    if not np.isfinite(latent).all() or not np.isfinite(transport).all():
        raise SystemExit("prediction arrays contain non-finite values")

    # Chosen once on 92 family-held-out training families; do not tune on benchmark targets.
    weight = 0.5
    combined = ((1.0 - weight) * latent + weight * transport).astype(np.float32)
    np.save(args.output, combined, allow_pickle=False)
    metadata = {
        "policy": "equal signed-distance blend",
        "transportWeight": weight,
        "validationIoU": 0.6636546029743318,
        "validationFamilies": 92,
        "shape": list(combined.shape),
        "references": "HOnop only",
        "benchmarkTargetsRead": False,
    }
    if args.selection:
        Path(args.selection).write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
    print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
