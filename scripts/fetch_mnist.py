#!/usr/bin/env python3
"""Download MNIST IDX files into data/ (repo keeps data/ gitignored)."""

from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

FILES = (
    "train-images-idx3-ubyte",
    "train-labels-idx1-ubyte",
    "t10k-images-idx3-ubyte",
    "t10k-labels-idx1-ubyte",
)

MIRRORS = (
    "https://ossci-datasets.s3.amazonaws.com/mnist/{name}",
    "https://yann.lecun.com/exdb/mnist/{name}",
)


def main() -> None:
    data_dir = Path(__file__).resolve().parents[1] / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    for name in FILES:
        out = data_dir / name
        if out.exists() and out.stat().st_size > 0:
            print(f"skip  {name} (already present)")
            continue
        last_err: Exception | None = None
        for template in MIRRORS:
            url = template.format(name=name)
            try:
                print(f"fetch {url}")
                urllib.request.urlretrieve(url, out)
                print(f"  -> {out} ({out.stat().st_size} bytes)")
                last_err = None
                break
            except Exception as e:  # noqa: BLE001
                last_err = e
                print(f"  failed: {e}", file=sys.stderr)
        if last_err is not None:
            out.unlink(missing_ok=True)
            raise SystemExit(f"Could not download {name}: {last_err}")

    print("MNIST ready under data/")


if __name__ == "__main__":
    main()
