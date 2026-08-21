"""Dynamic-precision bonus: sweep weight storage width, measure accuracy/ROM-size trade-off.

Activations, bias, and the 32-bit accumulator stay fixed at the baseline Q8.8
policy (matches vhdl/rtl/pkg_fixed.vhd + mac.vhd). Only the *weight* values are
re-quantized to fewer total bits at the same FRAC_BITS=8 scale, mirroring the
narrower vhdl/rtl/mac8.vhd multiplier path. This models "8-bit weights, 32-bit
accumulator" (course bonus §3) as an actual experiment instead of just
re-describing the existing Q8.8 baseline.

Self-contained (no `model`/`quantization`/`evaluate` imports): those pull in
PyTorch just to instantiate a model we don't need here, since
weights/float_weights.npz already holds plain NumPy w1/b1/w2/b2 arrays. The
quantize/infer logic below is the same policy as quantization.py's
float_to_fixed + evaluate.py's eval_quant_fast, just reimplemented without the
torch-import chain.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import (  # noqa: E402
    FLOAT_WEIGHTS_NPZ,
    FRAC_BITS,
    HIDDEN_SIZE,
    INPUT_SIZE,
    OUTPUT_SIZE,
    RESULTS_DIR,
)
from mnist_loader import load_mnist  # noqa: E402

WEIGHT_WIDTHS = (16, 12, 10, 9, 8, 7, 6)


def float_to_fixed(x: np.ndarray, frac_bits: int, data_width: int) -> np.ndarray:
    """Same policy as quantization.float_to_fixed: scale, round, saturate to Qm.n."""
    scale = 1 << frac_bits
    q_min = -(1 << (data_width - 1))
    q_max = (1 << (data_width - 1)) - 1
    q = np.rint(x * scale).astype(np.int64)
    return np.clip(q, q_min, q_max)


def eval_quant_fast(qparams: dict[str, np.ndarray], x: np.ndarray, y: np.ndarray) -> float:
    """Same vectorized policy as evaluate.eval_quant_fast (activations always int16)."""
    q_min, q_max = -(1 << 15), (1 << 15) - 1
    x_q = np.clip(np.rint(x * (1 << FRAC_BITS)), q_min, q_max).astype(np.int64)
    z1 = ((x_q @ qparams["w1"].T) + (qparams["b1"] << FRAC_BITS)) >> FRAC_BITS
    a1 = np.clip(z1, q_min, q_max)
    a1 = np.maximum(a1, 0)
    z2 = ((a1 @ qparams["w2"].T) + (qparams["b2"] << FRAC_BITS)) >> FRAC_BITS
    z2 = np.clip(z2, q_min, q_max)
    pred = np.argmax(z2, axis=1)
    return float((pred == y).mean())


def rom_bits(weight_width: int) -> int:
    n_weights = INPUT_SIZE * HIDDEN_SIZE + HIDDEN_SIZE * OUTPUT_SIZE
    return n_weights * weight_width


def main() -> None:
    if not FLOAT_WEIGHTS_NPZ.exists():
        raise SystemExit(f"Missing {FLOAT_WEIGHTS_NPZ}; run python/train.py first")

    params = np.load(FLOAT_WEIGHTS_NPZ)
    x_test, y_test = load_mnist("test")

    # Bias/activation policy never changes: full 16-bit Q8.8, only weight width sweeps.
    b1_q = float_to_fixed(params["b1"], frac_bits=FRAC_BITS, data_width=16)
    b2_q = float_to_fixed(params["b2"], frac_bits=FRAC_BITS, data_width=16)

    rows = []
    baseline_bits = rom_bits(16)
    for width in WEIGHT_WIDTHS:
        w1_q = float_to_fixed(params["w1"], frac_bits=FRAC_BITS, data_width=width)
        w2_q = float_to_fixed(params["w2"], frac_bits=FRAC_BITS, data_width=width)
        qparams = {"w1": w1_q, "b1": b1_q, "w2": w2_q, "b2": b2_q}
        acc = eval_quant_fast(qparams, x_test, y_test)
        bits = rom_bits(width)
        row = {
            "weight_width": width,
            "accuracy": acc,
            "rom_bits": bits,
            "rom_bytes": bits // 8,
            "rom_size_vs_baseline": round(bits / baseline_bits, 4),
        }
        rows.append(row)
        print(row)

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / "bitwidth_sweep.json"
    out.write_text(json.dumps(rows, indent=2))
    print(f"Wrote {out}")

    try:
        import matplotlib.pyplot as plt

        widths = [r["weight_width"] for r in rows]
        plt.figure(figsize=(6, 4))
        plt.plot(widths, [r["accuracy"] for r in rows], "o-")
        plt.xlabel("weight width (bits, FRAC_BITS=8 fixed)")
        plt.ylabel("test accuracy (Q8.8 activations)")
        plt.gca().invert_xaxis()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(RESULTS_DIR / "bitwidth_sweep.png", dpi=120)
        plt.close()
        print("Saved results/bitwidth_sweep.png")
    except ImportError:
        pass


if __name__ == "__main__":
    main()
