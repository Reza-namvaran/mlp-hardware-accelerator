"""Q8.8 fixed-point quantization and software reference inference."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    ACC_WIDTH,
    FLOAT_WEIGHTS_NPZ,
    FRAC_BITS,
    Q_MAX,
    Q_MIN,
    QUANT_WEIGHTS_NPZ,
    RESULTS_DIR,
    SCALE,
    WEIGHTS_DIR,
)
from mnist_loader import load_mnist
from model import MLP


def float_to_fixed(x: np.ndarray, frac_bits: int = FRAC_BITS, data_width: int = 16) -> np.ndarray:
    """Convert float to signed Qm.n int16 with saturation."""
    scale = 1 << frac_bits
    q_min = -(1 << (data_width - 1))
    q_max = (1 << (data_width - 1)) - 1
    q = np.rint(x * scale).astype(np.int32)
    q = np.clip(q, q_min, q_max)
    return q.astype(np.int16)


def float_to_q88(x: np.ndarray) -> np.ndarray:
    """Convert float to signed Q8.8 int16 with saturation."""
    return float_to_fixed(x, frac_bits=FRAC_BITS, data_width=16)


def q88_to_float(q: np.ndarray) -> np.ndarray:
    return q.astype(np.float32) / SCALE


def quantize_params(
    params: dict[str, np.ndarray], frac_bits: int = FRAC_BITS
) -> dict[str, np.ndarray]:
    return {k: float_to_fixed(v, frac_bits=frac_bits) for k, v in params.items()}


def quantize_model(model: MLP, frac_bits: int = FRAC_BITS) -> dict[str, np.ndarray]:
    return quantize_params(model.numpy_parameters(), frac_bits=frac_bits)


def load_quant_params(path: Path = QUANT_WEIGHTS_NPZ) -> dict[str, np.ndarray]:
    data = np.load(path)
    return {k: data[k] for k in ("w1", "b1", "w2", "b2")}


def _mac_row(weights: np.ndarray, bias: np.int16, x_q: np.ndarray) -> np.int16:
    """
    Serial MAC matching VHDL: acc += w*x (full product), then
    acc += bias << FRAC_BITS, then truncate by >> FRAC_BITS with saturation.
    weights: (in,), x_q: (in,)
    """
    acc = np.int64(0)
    # Product of two Q8.8 is Q16.16 in the lower 32 bits conceptually;
    # we keep int64 and shift by FRAC once at the end (same as summing w*x then >> FRAC).
    for i in range(weights.shape[0]):
        acc += np.int64(weights[i]) * np.int64(x_q[i])
    acc += np.int64(bias) << FRAC_BITS
    # Truncate fractional bits of the Q16.16-style sum back to Q8.8
    shifted = acc >> FRAC_BITS
    # Saturate to int16
    if shifted > Q_MAX:
        return np.int16(Q_MAX)
    if shifted < Q_MIN:
        return np.int16(Q_MIN)
    return np.int16(shifted)


def fixed_point_forward(qparams: dict[str, np.ndarray], x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """
    Fixed-point inference for a batch.
    Returns (logits_q int16[N,10], hidden_q int16[N,H]).
    """
    x_q = float_to_q88(x)
    n = x_q.shape[0]
    h = qparams["w1"].shape[0]
    o = qparams["w2"].shape[0]
    hidden = np.zeros((n, h), dtype=np.int16)
    logits = np.zeros((n, o), dtype=np.int16)

    for ni in range(n):
        for hi in range(h):
            z = _mac_row(qparams["w1"][hi], qparams["b1"][hi], x_q[ni])
            hidden[ni, hi] = z if z > 0 else np.int16(0)
        for oi in range(o):
            logits[ni, oi] = _mac_row(qparams["w2"][oi], qparams["b2"][oi], hidden[ni])
    return logits, hidden


def fixed_point_infer(qparams: dict[str, np.ndarray], x: np.ndarray) -> np.ndarray:
    logits, _ = fixed_point_forward(qparams, x)
    return np.argmax(logits, axis=1)


def main() -> None:
    if not FLOAT_WEIGHTS_NPZ.exists():
        raise SystemExit(f"Missing {FLOAT_WEIGHTS_NPZ}; run python/train.py first")

    data = np.load(FLOAT_WEIGHTS_NPZ)
    model = MLP(hidden_size=int(data["w1"].shape[0]))
    model.load_numpy_parameters({k: data[k] for k in ("w1", "b1", "w2", "b2")})

    qparams = quantize_model(model)
    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    np.savez(QUANT_WEIGHTS_NPZ, **qparams)

    x_test, y_test = load_mnist("test")
    float_pred = model.predict(x_test)
    float_acc = float((float_pred == y_test).mean())

    # Full test set fixed-point can be slow (serial MAC in Python) — use subset + full via vectorized path
    # Vectorized Q8.8 approximation for full-set reporting (same truncate policy):
    x_q = float_to_q88(x_test).astype(np.int32)
    w1 = qparams["w1"].astype(np.int32)
    b1 = qparams["b1"].astype(np.int32)
    # (N,H) = x @ W.T  with Q8.8*Q8.8 → shift
    z1 = ((x_q @ w1.T) + (b1.astype(np.int64) << FRAC_BITS)) >> FRAC_BITS
    z1 = np.clip(z1, Q_MIN, Q_MAX).astype(np.int32)
    a1 = np.maximum(z1, 0)
    w2 = qparams["w2"].astype(np.int32)
    b2 = qparams["b2"].astype(np.int32)
    z2 = ((a1.astype(np.int64) @ w2.T) + (b2.astype(np.int64) << FRAC_BITS)) >> FRAC_BITS
    z2 = np.clip(z2, Q_MIN, Q_MAX)
    quant_pred = np.argmax(z2, axis=1)
    quant_acc = float((quant_pred == y_test).mean())

    report = {
        "format": "Q8.8",
        "frac_bits": FRAC_BITS,
        "acc_width": ACC_WIDTH,
        "float_acc": float_acc,
        "quant_acc": quant_acc,
        "accuracy_drop": float_acc - quant_acc,
    }
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / "quantization_report.json"
    out.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    print(f"Saved quantized weights → {QUANT_WEIGHTS_NPZ}")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
