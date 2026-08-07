#!/usr/bin/env python3
"""Generate random Q8.8 MAC vectors for HW/SW cross-check."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core"))

from config import FRAC_BITS, Q_MAX, Q_MIN, RESULTS_DIR, SCALE  # noqa: E402


def mac_ref(weights: np.ndarray, bias: int, x: np.ndarray) -> int:
    acc = np.int64(0)
    for w, xi in zip(weights, x):
        acc += np.int64(w) * np.int64(xi)
    acc += np.int64(bias) << FRAC_BITS
    shifted = acc >> FRAC_BITS
    return int(np.clip(shifted, Q_MIN, Q_MAX))


def main() -> None:
    rng = np.random.default_rng(0)
    cases = []
    for n in (4, 16, 64):
        w = rng.integers(-128, 128, size=n, dtype=np.int16)
        x = rng.integers(0, 256, size=n, dtype=np.int16)  # pixels-ish
        b = int(rng.integers(-64, 64))
        y = mac_ref(w, b, x)
        cases.append(
            {
                "n": n,
                "bias": b,
                "weights": w.tolist(),
                "x": x.tolist(),
                "y": y,
            }
        )
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / "mac_test_vectors.json"
    out.write_text(json.dumps(cases, indent=2))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
