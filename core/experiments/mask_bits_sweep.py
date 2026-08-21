"""Approximate-arithmetic bonus: sweep LSB-mask width, measure accuracy impact.

Mirrors vhdl/rtl/mac_approx.vhd's technique exactly: before every multiply, the
lower MASK_BITS bits of *both* operands (activation and weight) are cleared
with a bitmask; bias, accumulation, shift, and saturation are all untouched
(same as the VHDL). MASK_BITS=0 reproduces the exact baseline (93.8%).

Self-contained (no torch import) for the same reason as bitwidth_sweep.py:
weights/float_weights.npz already holds plain NumPy arrays.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import FLOAT_WEIGHTS_NPZ, FRAC_BITS, RESULTS_DIR  # noqa: E402
from mnist_loader import load_mnist  # noqa: E402

MASK_WIDTHS = (0, 2, 4, 6, 8, 10)


def float_to_fixed(x: np.ndarray, frac_bits: int, data_width: int) -> np.ndarray:
    scale = 1 << frac_bits
    q_min = -(1 << (data_width - 1))
    q_max = (1 << (data_width - 1)) - 1
    q = np.rint(x * scale).astype(np.int64)
    return np.clip(q, q_min, q_max).astype(np.int16)


def apply_mask(x: np.ndarray, mask_bits: int) -> np.ndarray:
    """Clear the lower mask_bits bits of each element (same op as mac_approx.vhd)."""
    if mask_bits <= 0:
        return x
    keep_mask = np.int32(~((1 << mask_bits) - 1))
    return (x.astype(np.int32) & keep_mask).astype(np.int16)


def masked_forward(w1, b1, w2, b2, x_q, mask_bits: int) -> np.ndarray:
    q_min, q_max = -(1 << 15), (1 << 15) - 1
    x_m = apply_mask(x_q, mask_bits)
    w1_m = apply_mask(w1, mask_bits)
    z1 = ((x_m.astype(np.int64) @ w1_m.T.astype(np.int64)) + (b1.astype(np.int64) << FRAC_BITS)) >> FRAC_BITS
    z1 = np.clip(z1, q_min, q_max).astype(np.int32)
    a1 = np.maximum(z1, 0).astype(np.int16)

    a1_m = apply_mask(a1, mask_bits)
    w2_m = apply_mask(w2, mask_bits)
    z2 = ((a1_m.astype(np.int64) @ w2_m.T.astype(np.int64)) + (b2.astype(np.int64) << FRAC_BITS)) >> FRAC_BITS
    z2 = np.clip(z2, q_min, q_max)
    return np.argmax(z2, axis=1)


def main() -> None:
    if not FLOAT_WEIGHTS_NPZ.exists():
        raise SystemExit(f"Missing {FLOAT_WEIGHTS_NPZ}; run python/train.py first")

    params = np.load(FLOAT_WEIGHTS_NPZ)
    w1 = float_to_fixed(params["w1"], FRAC_BITS, 16)
    b1 = float_to_fixed(params["b1"], FRAC_BITS, 16)
    w2 = float_to_fixed(params["w2"], FRAC_BITS, 16)
    b2 = float_to_fixed(params["b2"], FRAC_BITS, 16)

    x_test, y_test = load_mnist("test")
    x_q = float_to_fixed(x_test, FRAC_BITS, 16)

    rows = []
    for mask_bits in MASK_WIDTHS:
        pred = masked_forward(w1, b1, w2, b2, x_q, mask_bits)
        acc = float((pred == y_test).mean())
        row = {"mask_bits": mask_bits, "accuracy": acc}
        rows.append(row)
        print(row)

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / "mask_bits_sweep.json"
    out.write_text(json.dumps(rows, indent=2))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
