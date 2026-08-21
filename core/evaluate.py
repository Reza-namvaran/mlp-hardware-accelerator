"""Evaluate float (PyTorch) and quantized MLP accuracy."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    CHECKPOINT_PATH,
    FLOAT_WEIGHTS_NPZ,
    FRAC_BITS,
    QUANT_WEIGHTS_NPZ,
    RESULTS_DIR,
)
from mnist_loader import load_mnist
from model import MLP
from quantization import load_quant_params, quantize_model


def load_float_model() -> MLP:
    if CHECKPOINT_PATH.exists():
        ckpt = torch.load(CHECKPOINT_PATH, map_location="cpu", weights_only=False)
        hidden = int(ckpt.get("hidden", FLOAT_WEIGHTS_NPZ and np.load(FLOAT_WEIGHTS_NPZ)["w1"].shape[0]))
        model = MLP(hidden_size=hidden)
        model.load_state_dict(ckpt["state_dict"])
        return model
    if not FLOAT_WEIGHTS_NPZ.exists():
        raise SystemExit(f"Missing {CHECKPOINT_PATH} or {FLOAT_WEIGHTS_NPZ}; run train.py first")
    data = np.load(FLOAT_WEIGHTS_NPZ)
    model = MLP(hidden_size=int(data["w1"].shape[0]))
    model.load_numpy_parameters({k: data[k] for k in ("w1", "b1", "w2", "b2")})
    return model


@torch.no_grad()
def eval_float(model: MLP, x: np.ndarray, y: np.ndarray) -> float:
    model.eval()
    pred = model.predict(x)
    return float((pred == y).mean())


def eval_quant_fast(
    qparams: dict[str, np.ndarray],
    x: np.ndarray,
    y: np.ndarray,
    frac_bits: int = FRAC_BITS,
) -> float:
    """Vectorized fixed-point inference matching VHDL MAC truncate policy."""
    q_min = -(1 << 15)
    q_max = (1 << 15) - 1
    scale = 1 << frac_bits
    x_q = np.clip(np.rint(x * scale), q_min, q_max).astype(np.int32)
    w1 = qparams["w1"].astype(np.int32)
    b1 = qparams["b1"].astype(np.int32)
    z1 = ((x_q.astype(np.int64) @ w1.T) + (b1.astype(np.int64) << frac_bits)) >> frac_bits
    z1 = np.clip(z1, q_min, q_max).astype(np.int32)
    a1 = np.maximum(z1, 0)
    w2 = qparams["w2"].astype(np.int32)
    b2 = qparams["b2"].astype(np.int32)
    z2 = ((a1.astype(np.int64) @ w2.T) + (b2.astype(np.int64) << frac_bits)) >> frac_bits
    z2 = np.clip(z2, q_min, q_max)
    pred = np.argmax(z2, axis=1)
    return float((pred == y).mean())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quantize", action="store_true", help="Also report Q8.8 accuracy")
    args = parser.parse_args()

    model = load_float_model()
    x_test, y_test = load_mnist("test")
    float_acc = eval_float(model, x_test, y_test)
    print(f"Float32 test accuracy: {float_acc:.4f}")

    report = {"float_acc": float_acc, "framework": "pytorch"}

    if args.quantize or QUANT_WEIGHTS_NPZ.exists():
        if QUANT_WEIGHTS_NPZ.exists():
            qparams = load_quant_params(QUANT_WEIGHTS_NPZ)
        else:
            qparams = quantize_model(model)
        quant_acc = eval_quant_fast(qparams, x_test, y_test)
        drop = float_acc - quant_acc
        print(f"Q8.8 test accuracy:   {quant_acc:.4f}")
        print(f"Accuracy drop:        {drop:.4f}")
        report["quant_acc"] = quant_acc
        report["accuracy_drop"] = drop

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / "accuracy_report.json"
    out.write_text(json.dumps(report, indent=2))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
