#!/usr/bin/env python3
"""One bounded clipped-SDF auxiliary-supervision pilot for thin strokes.

Starts from the frozen family-balanced SDF CNN. Adds ridge and radius heads,
supervised from local maxima of the corpus's clipped SDF while retaining the
baseline SDF output and inference contract. The clipped SDF saturates at six
pixels, so these are approximate ridge targets, not a full medial-axis or
topology reconstruction. No benchmark target enters model selection or
inference. Checkpoint selection uses one representative per historical
validation family from the 1,591-face corpus.
"""
import argparse
import hashlib
import json
import random
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F


ROOT = Path("/private/tmp")
SEED = 2909
MAX_SECONDS = 900
torch.set_num_threads(4)


class Block(nn.Module):
    def __init__(self, a, b, stride=1):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(a, b, 3, stride, padding=1), nn.GroupNorm(8, b), nn.SiLU(),
            nn.Conv2d(b, b, 3, padding=1), nn.GroupNorm(8, b), nn.SiLU(),
        )

    def forward(self, x):
        return self.net(x)


class Completion(nn.Module):
    def __init__(self):
        super().__init__()
        self.encoder = nn.Sequential(Block(5, 32, 2), Block(32, 64, 2), Block(64, 96, 2),
                                     nn.AdaptiveAvgPool2d((3, 4)), nn.Flatten(),
                                     nn.Linear(96 * 3 * 4, 256), nn.SiLU())
        self.letter = nn.Embedding(52, 64)
        self.project = nn.Sequential(nn.Linear(320, 512), nn.SiLU(),
                                     nn.Linear(512, 64 * 9 * 12), nn.SiLU())
        self.blocks = nn.ModuleList([Block(64, 64), Block(64, 32), Block(32, 16)])
        self.out = nn.Conv2d(16, 1, 1)
        self.modulation = nn.ModuleList([nn.Linear(320, 2 * k) for k in [64, 32, 16]])
        for layer in self.modulation:
            nn.init.zeros_(layer.weight)
            nn.init.zeros_(layer.bias)
        # Auxiliary channels describe the medial ridges and their local half-width.
        self.skeleton = nn.Conv2d(16, 1, 1)
        self.radius = nn.Conv2d(16, 1, 1)

    def features(self, x, c):
        x = F.pad(x, (0, 4, 0, 0), value=1)
        z = self.encoder(x)
        z = torch.cat([z, self.letter(c)], 1)
        y = self.project(z).reshape(-1, 64, 9, 12)
        for b, mod in zip(self.blocks, self.modulation):
            y = b(F.interpolate(y, scale_factor=2, mode="bilinear", align_corners=False))
            gain, bias = mod(z).chunk(2, dim=1)
            y = y * (1 + .1 * gain[:, :, None, None]) + .1 * bias[:, :, None, None]
        return y[..., :92]

    def forward(self, x, c):
        y = self.features(x, c)
        return torch.tanh(self.out(y)), self.skeleton(y), torch.sigmoid(self.radius(y)) * 6


def split(records):
    is_val = [int(hashlib.sha256(r["family"].encode()).hexdigest()[:8], 16) % 5 == 0
              for r in records]
    train = np.flatnonzero(np.logical_not(is_val))
    # Preserve whole families and choose their first record deterministically.
    val, families = [], set()
    for i, r in enumerate(records):
        if is_val[i] and r["family"] not in families:
            val.append(i)
            families.add(r["family"])
    return train, np.asarray(val, dtype=np.int64)


def eval_iou(model, ref, sdf, indices, target_letters, device, batch_size=32):
    model.eval()
    scores = []
    with torch.no_grad():
        for face in indices:
            for start in range(0, len(target_letters), batch_size):
                letters = target_letters[start:start + batch_size]
                x = torch.from_numpy(np.repeat(ref[face:face + 1], len(letters), axis=0)).to(device)
                c = torch.as_tensor(letters, device=device)
                pred = model(x, c)[0][:, 0].cpu().numpy() < 0
                truth = np.asarray(sdf[face, letters]) < 0
                scores.extend((pred & truth).sum((1, 2)) / np.maximum(1, (pred | truth).sum((1, 2))))
    model.train()
    return float(np.mean(scores))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output-dir", default="/private/tmp/typefield-skeleton-pilot")
    p.add_argument("--max-seconds", type=int, default=MAX_SECONDS)
    args = p.parse_args()
    random.seed(SEED)
    np.random.seed(SEED)
    torch.manual_seed(SEED)
    if not torch.backends.mps.is_available():
        raise SystemExit("MPS unavailable; do not silently substitute CPU")
    device = torch.device("mps")
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    meta_path = ROOT / "typefield-diverse-letters-font-masks.json"
    sdf_path = ROOT / "typefield-diverse-letters-conv-sdf.f16"
    ckpt_path = ROOT / "typefield-balanced-conv-best.pt"
    meta = json.loads(meta_path.read_text())
    records, chars = meta["records"], meta["characters"]
    if len(records) != 1591 or len(chars) != 52:
        raise SystemExit("unexpected corpus size or alphabet")
    refs = [chars.index(c) for c in "HOnop"]
    targets = np.asarray([i for i, c in enumerate(chars) if c not in "HOnop"], dtype=np.int64)
    sdf = np.memmap(sdf_path, dtype=np.float16, mode="r", shape=(1591, 52, 72, 92))
    reference_sdf = np.ascontiguousarray(sdf[:, refs], dtype=np.float32)
    train_ids, val_ids = split(records)
    device_note = {"torch": torch.__version__, "device": str(device), "seed": SEED,
                   "records": len(records), "train_faces": len(train_ids),
                   "validation_families": len(val_ids), "reference_letters": "HOnop",
                   "targets": len(targets), "corpus_sha256": hashlib.sha256(meta_path.read_bytes()).hexdigest(),
                   "sdf_sha256": hashlib.sha256(sdf_path.read_bytes()).hexdigest(),
                   "initial_checkpoint_sha256": hashlib.sha256(ckpt_path.read_bytes()).hexdigest()}
    (out / "pilot-inputs.json").write_text(json.dumps(device_note, indent=2) + "\n")

    model = Completion()
    baseline = torch.load(ckpt_path, map_location="cpu", weights_only=True)
    incompatible = model.load_state_dict(baseline, strict=False)
    if incompatible.missing_keys != ["skeleton.weight", "skeleton.bias", "radius.weight", "radius.bias"]:
        raise SystemExit(f"unexpected checkpoint mismatch: {incompatible}")
    model = model.to(device)
    # Baseline output remains the initialized occupancy head. Start auxiliary
    # heads at low confidence/width so early gradients are predictable.
    nn.init.zeros_(model.skeleton.weight)
    nn.init.constant_(model.skeleton.bias, -2.0)
    nn.init.zeros_(model.radius.weight)
    nn.init.constant_(model.radius.bias, -1.0)

    base_iou = eval_iou(model, reference_sdf, sdf, val_ids, targets, device)
    print(f"BASELINE_VALIDATION_IOU {base_iou:.8f}", flush=True)
    family_members = {f: np.asarray([i for i in train_ids if records[i]["family"] == f])
                      for f in sorted({records[i]["family"] for i in train_ids})}
    families = list(family_members)
    optim = torch.optim.AdamW(model.parameters(), lr=2e-5, weight_decay=1e-4)
    start, step, best, best_step = time.monotonic(), 0, base_iou, 0
    report = {**device_note, "hypothesis": "auxiliary ridge and radius supervision from clipped SDF fields improves thin-stroke and join prediction", "target_limitation": "SDF fields saturate at six pixels; targets are approximate ridges and do not establish full medial-axis or topology reconstruction", "baseline_validation_iou": base_iou, "history": [[0, base_iou]], "max_seconds": args.max_seconds, "status": "running"}
    best_path = out / "skeleton-radius-best.pt"
    torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()}, best_path)
    model.train()
    while time.monotonic() - start < args.max_seconds:
        fi = np.asarray([np.random.choice(family_members[f]) for f in np.random.choice(families, 32)])
        ci = np.random.randint(0, 52, 32)
        x = torch.from_numpy(reference_sdf[fi]).to(device)
        y = torch.from_numpy(np.asarray(sdf[fi, ci], dtype=np.float32)).unsqueeze(1).to(device)
        c = torch.as_tensor(ci, device=device)
        pred, skel_logits, radius = model(x, c)
        inside = (y < 0).float()
        # SDF inputs are stored in units of six pixels, so convert back to
        # local radius in pixels to match the radius head's [0, 6] output.
        rad = (-y).clamp(0, 1) * 6
        ridge = ((rad >= F.max_pool2d(rad, 3, stride=1, padding=1) - 0.06) & (inside > 0))
        # Clamp the radius regression target to the 3-pixel band around the
        # medial ridge; this avoids treating clipped exterior SDF as width.
        skeleton_target = ridge.float()
        skel_prob = torch.sigmoid(skel_logits)
        skel_loss = F.binary_cross_entropy_with_logits(skel_logits, skeleton_target)
        skel_dice = 1 - (2 * (skel_prob * skeleton_target).sum((1,2,3)) + 1) / (skel_prob.sum((1,2,3)) + skeleton_target.sum((1,2,3)) + 1)
        radius_loss = ((radius - rad).abs() * skeleton_target).sum() / skeleton_target.sum().clamp_min(1)
        near = 1 + 2 * (y.abs() < .75)
        sdf_loss = (F.smooth_l1_loss(pred, y, reduction="none") * near).mean()
        loss = sdf_loss + .03 * skel_loss + .03 * skel_dice.mean() + .02 * radius_loss
        optim.zero_grad(set_to_none=True)
        loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optim.step()
        step += 1
        if step % 100 == 0:
            print(f"TRAIN step={step} loss={float(loss.detach().cpu()):.5f} elapsed={time.monotonic()-start:.1f}", flush=True)
        if step % 400 == 0:
            score = eval_iou(model, reference_sdf, sdf, val_ids, targets, device)
            report["history"].append([step, score])
            print(f"VALIDATION step={step} iou={score:.8f}", flush=True)
            if score > best:
                best, best_step = score, step
                torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()}, best_path)
            report.update({"best_validation_iou": best, "best_step": best_step, "steps": step,
                           "elapsed_seconds": time.monotonic()-start})
            (out / "pilot-report.json").write_text(json.dumps(report, indent=2) + "\n")
            if step - best_step >= 1200:
                break
    report.update({"status": "complete", "steps": step, "best_validation_iou": best,
                   "best_step": best_step, "elapsed_seconds": time.monotonic()-start})
    (out / "pilot-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"FROZEN step={best_step} validation_iou={best:.8f} elapsed={time.monotonic()-start:.1f}", flush=True)


if __name__ == "__main__":
    main()
