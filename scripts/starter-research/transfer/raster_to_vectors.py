#!/usr/bin/env python3
"""Turn frozen 92x72 signed-distance predictions into evaluator vector JSON."""
import argparse
import json
from pathlib import Path

import contourpy
import numpy as np

CHARS = [c for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" if c not in "HOnop"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--predictions", required=True, help="(18,47,72,92) signed-distance .npy")
    parser.add_argument("--face-names", required=True, help="JSON array in the frozen evaluator face order")
    parser.add_argument("--output", required=True, help="frozen prediction vector JSON")
    args = parser.parse_args()

    pred = np.load(args.predictions, mmap_mode="r", allow_pickle=False)
    names = json.loads(Path(args.face_names).read_text())
    if pred.shape != (18, 47, 72, 92):
        raise SystemExit(f"expected (18,47,72,92) predictions, got {pred.shape}")
    if len(names) != 18 or any(not isinstance(face.get("name"), str) for face in names):
        raise SystemExit("face-name file must contain exactly 18 objects with string 'name' fields")
    if len({face["name"] for face in names}) != 18:
        raise SystemExit("face names must be unique")
    if not np.isfinite(pred).all():
        raise SystemExit("prediction array contains non-finite values")

    # Grid positions follow the fixed 1.4 x 1 em frame; no target-driven alignment occurs here.
    x = (np.arange(94) - 0.5) * 1.4 / 92
    y = (np.arange(74) - 0.5) / 72
    faces = []
    for i, face in enumerate(names):
        glyphs = []
        for j, character in enumerate(CHARS):
            z = np.pad(pred[i, j], 1, constant_values=1.0)
            lines = contourpy.contour_generator(x=x, y=y, z=z, line_type="Separate").lines(0)
            contours = []
            for line in lines:
                if len(line) < 4:
                    continue
                line[:, 0] = np.clip(line[:, 0], 0, 1.4)
                line[:, 1] = np.clip(1 - line[:, 1], 0, 1)
                if np.allclose(line[0], line[-1]):
                    line = line[:-1]
                contours.append(line.tolist())
            glyphs.append({"character": character, "contours": contours})
        faces.append({"name": face["name"], "glyphs": glyphs})
    Path(args.output).write_text(json.dumps(faces, separators=(",", ":")))
    print(f"Wrote {len(faces)} faces x {len(CHARS)} vector predictions; no targets were read.")


if __name__ == "__main__":
    main()
