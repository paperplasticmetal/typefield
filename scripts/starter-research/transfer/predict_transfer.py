#!/usr/bin/env python3
"""Infer reference-only exemplar transfer from H O n o p masks.

Inputs are local research artifacts. The inference path never opens target outlines,
benchmark font names, or a scoring file.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
from scipy.ndimage import distance_transform_edt
from scipy.spatial.distance import cdist
from torch import nn
from torch.nn import functional as F


def signed_distance(mask):
    return np.clip(distance_transform_edt(~mask) - distance_transform_edt(mask), -6, 6) / 6


class Conv(nn.Module):
    def __init__(self, a, b):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(a, b, 3, padding=1), nn.GroupNorm(8, b), nn.SiLU(),
            nn.Conv2d(b, b, 3, padding=1), nn.GroupNorm(8, b), nn.SiLU(),
        )

    def forward(self, x):
        return self.net(x)


class Transport(nn.Module):
    def __init__(self):
        super().__init__()
        self.a, self.b, self.c, self.d = Conv(11, 32), Conv(32, 64), Conv(64, 96), Conv(96, 128)
        self.u, self.v, self.w = Conv(224, 96), Conv(160, 64), Conv(96, 32)
        self.out = nn.Conv2d(32, 1, 1)

    def forward(self, x):
        a = self.a(x)
        b = self.b(F.avg_pool2d(a, 2))
        c = self.c(F.avg_pool2d(b, 2))
        d = self.d(F.avg_pool2d(c, 2))
        y = self.u(torch.cat([F.interpolate(d, size=c.shape[-2:], mode="bilinear", align_corners=False), c], 1))
        y = self.v(torch.cat([F.interpolate(y, size=b.shape[-2:], mode="bilinear", align_corners=False), b], 1))
        y = self.w(torch.cat([F.interpolate(y, size=a.shape[-2:], mode="bilinear", align_corners=False), a], 1))
        return (x[:, 10:11] + torch.tanh(self.out(y))).clamp(-1, 1)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--references", required=True, help="float/bool (faces,5,72,92), character order HOnop")
    p.add_argument("--metadata", required=True, help="training-corpus metadata JSON")
    p.add_argument("--masks", required=True, help="training masks uint8, face x 52 x 72 x 92")
    p.add_argument("--sdf", required=True, help="training float16 SDF cache, same dimensions")
    p.add_argument("--checkpoint", required=True, help="transport state_dict; loaded weights_only")
    p.add_argument("--output", required=True, help="signed-distance NPY, faces x 47 x 72 x 92")
    p.add_argument("--device", choices=("cpu", "mps"), default="cpu")
    args = p.parse_args()

    torch.set_num_threads(4)
    refs_mask = np.load(args.references, mmap_mode="r", allow_pickle=False)
    if refs_mask.ndim != 4 or refs_mask.shape[1:] != (5, 72, 92):
        raise SystemExit(f"references must have shape (faces,5,72,92), got {refs_mask.shape}")
    metadata = json.loads(Path(args.metadata).read_text())
    records, chars = metadata["records"], metadata["characters"]
    if [chars.index(c) for c in "HOnop"] != sorted(chars.index(c) for c in "HOnop"):
        raise SystemExit("metadata character ordering is inconsistent")
    letters = [i for i, c in enumerate(chars) if c not in "HOnop"]
    if len(letters) != 47 or len(records) != 1343:
        raise SystemExit(f"unexpected training corpus dimensions: {len(records)} faces, {len(letters)} targets")
    shape = (len(records), 52, 72, 92)
    masks = np.memmap(args.masks, dtype=np.uint8, mode="r", shape=shape)
    sdf = np.memmap(args.sdf, dtype=np.float16, mode="r", shape=shape)
    if Path(args.masks).stat().st_size != int(np.prod(shape)):
        raise SystemExit("training mask file size does not match its declared corpus shape")
    if Path(args.sdf).stat().st_size != int(np.prod(shape)) * 2:
        raise SystemExit("training SDF file size does not match its declared corpus shape")

    # This is the original deterministic family split: held-out selection families are
    # excluded from retrieval; the benchmark identities are never supplied to this code.
    train = np.array([
        i for i, row in enumerate(records)
        if int(hashlib.sha256(row["family"].encode("utf-8")).hexdigest()[:8], 16) % 5 != 0
    ])
    ref_ids = [chars.index(c) for c in "HOnop"]
    train_refs = np.asarray(sdf[:, ref_ids], dtype=np.float32)
    features = train_refs[:, :, ::2, ::2].reshape(len(records), -1)
    query_refs = np.stack([
        np.stack([signed_distance(np.asarray(refs_mask[i, j]) > 0) for j in range(5)])
        for i in range(len(refs_mask))
    ]).astype(np.float32)
    neighbors = train[cdist(query_refs[:, :, ::2, ::2].reshape(len(query_refs), -1), features[train], metric="sqeuclidean").argmin(1)]

    device = torch.device(args.device)
    model = Transport().to(device)
    state = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model.load_state_dict(state, strict=True)
    model.eval()
    predictions = []
    with torch.inference_mode():
        for face, neighbor in enumerate(neighbors):
            face_predictions = []
            for start in range(0, len(letters), 24):
                ids = np.asarray(letters[start:start + 24])
                batch = np.concatenate([
                    np.repeat(query_refs[face:face + 1], len(ids), axis=0),
                    np.repeat(train_refs[neighbor:neighbor + 1], len(ids), axis=0),
                    np.asarray(sdf[neighbor, ids], dtype=np.float32)[:, None],
                ], axis=1)
                y = model(torch.from_numpy(batch).to(device))[:, 0].cpu().numpy()
                face_predictions.append(y)
            predictions.append(np.concatenate(face_predictions))
    result = np.stack(predictions).astype(np.float32)
    np.save(args.output, result, allow_pickle=False)
    print(json.dumps({
        "outputs": list(result.shape), "device": args.device,
        "retrieval": "nearest HOnop reference SDF among family-hash training split",
        "benchmarkTargetsRead": False, "benchmarkNamesRead": False,
        "retrievedFaceCount": int(len(neighbors)),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
