from __future__ import annotations

from pathlib import Path

import numpy as np

from config import DATA_DIR


def _read_idx_images(path: Path) -> np.ndarray:
    raw = path.read_bytes()
    magic = int.from_bytes(raw[0:4], "big")
    if magic != 2051:
        raise ValueError(f"Bad image magic in {path}: {magic}")
    n = int.from_bytes(raw[4:8], "big")
    rows = int.from_bytes(raw[8:12], "big")
    cols = int.from_bytes(raw[12:16], "big")
    data = np.frombuffer(raw, dtype=np.uint8, offset=16)
    return data.reshape(n, rows * cols).astype(np.float32) / 255.0


def _read_idx_labels(path: Path) -> np.ndarray:
    raw = path.read_bytes()
    magic = int.from_bytes(raw[0:4], "big")
    if magic != 2049:
        raise ValueError(f"Bad label magic in {path}: {magic}")
    n = int.from_bytes(raw[4:8], "big")
    return np.frombuffer(raw, dtype=np.uint8, offset=8).copy()[:n]


def _resolve(name: str) -> Path:
    """Prefer flat IDX files, fall back to nested folders from dataset.zip."""
    flat = DATA_DIR / name
    if flat.is_file():
        return flat
    nested = DATA_DIR / name / name
    if nested.is_file():
        return nested
    raise FileNotFoundError(f"MNIST file not found: {name} under {DATA_DIR}")


def load_mnist(split: str = "train") -> tuple[np.ndarray, np.ndarray]:
    if split == "train":
        images = _read_idx_images(_resolve("train-images.idx3-ubyte"))
        labels = _read_idx_labels(_resolve("train-labels.idx1-ubyte"))
    elif split == "test":
        images = _read_idx_images(_resolve("t10k-images.idx3-ubyte"))
        labels = _read_idx_labels(_resolve("t10k-labels.idx1-ubyte"))
    else:
        raise ValueError(f"Unknown split: {split}")
    return images, labels
