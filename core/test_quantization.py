"""Basic tests for Q8.8 helpers."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quantization import float_to_q88, q88_to_float  # noqa: E402
from config import SCALE  # noqa: E402


def test_roundtrip_unit():
    x = np.array([0.0, 1.0, -1.0, 0.5], dtype=np.float32)
    q = float_to_q88(x)
    assert q.tolist() == [0, SCALE, -SCALE, SCALE // 2]
    y = q88_to_float(q)
    assert np.allclose(y, x)


def test_saturate():
    q = float_to_q88(np.array([1000.0, -1000.0], dtype=np.float32))
    assert q[0] == 32767
    assert q[1] == -32768
