"""Scholarship-oriented ablations: Q-format and hidden-size sweeps."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import INPUT_SIZE, OUTPUT_SIZE, RESULTS_DIR, WEIGHTS_DIR  # noqa: E402
from evaluate import eval_quant_fast  # noqa: E402
from mnist_loader import load_mnist  # noqa: E402
from model import MLP  # noqa: E402
from quantization import quantize_params  # noqa: E402


def make_loader(x, y, batch_size, shuffle):
    return DataLoader(
        TensorDataset(
            torch.from_numpy(x.astype(np.float32)),
            torch.from_numpy(y.astype(np.int64)),
        ),
        batch_size=batch_size,
        shuffle=shuffle,
    )


def train_hidden(
    hidden: int,
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_test: np.ndarray,
    y_test: np.ndarray,
    epochs: int = 5,
    seed: int = 42,
) -> tuple[MLP, float]:
    torch.manual_seed(seed)
    model = MLP(hidden_size=hidden)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    train_loader = make_loader(x_train, y_train, 128, True)
    criterion = nn.CrossEntropyLoss()
    model.train()
    for _ in range(epochs):
        for xb, yb in train_loader:
            opt.zero_grad(set_to_none=True)
            loss = criterion(model(xb), yb)
            loss.backward()
            opt.step()
    model.eval()
    with torch.no_grad():
        pred = model.predict(x_test)
    float_acc = float((pred == y_test).mean())
    return model, float_acc


def param_count(hidden: int) -> int:
    return INPUT_SIZE * hidden + hidden + hidden * OUTPUT_SIZE + OUTPUT_SIZE


def estimate_cycles(hidden: int) -> int:
    """Serial MAC model matching docs/fsm.md (HOLD+ADVANCE ≈ 2 cycles/input)."""
    load = INPUT_SIZE
    # per neuron: CLEAR + 2*N_INPUTS + SETTLE + DONE ≈ 2*N + 4
    hidden_cyc = hidden * (2 * INPUT_SIZE + 4)
    out_cyc = OUTPUT_SIZE * (2 * hidden + 4)
    overhead = 20
    return load + hidden_cyc + out_cyc + overhead


def main() -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    x_train, y_train = load_mnist("train")
    x_test, y_test = load_mnist("test")

    # --- Hidden-size sweep ---
    hidden_rows = []
    models: dict[int, MLP] = {}
    for h in (8, 16, 32):
        print(f"Training hidden={h}...")
        model, float_acc = train_hidden(h, x_train, y_train, x_test, y_test, epochs=5)
        models[h] = model
        qparams = quantize_params(model.numpy_parameters(), frac_bits=8)
        quant_acc = eval_quant_fast(qparams, x_test, y_test, frac_bits=8)
        row = {
            "hidden": h,
            "params": param_count(h),
            "float_acc": float_acc,
            "q88_acc": quant_acc,
            "est_cycles": estimate_cycles(h),
        }
        hidden_rows.append(row)
        print(row)
        # Save baseline H=16 weights for HW if this is the HW size
        if h == 16:
            WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
            np.savez(WEIGHTS_DIR / "float_weights.npz", **model.numpy_parameters())
            torch.save(
                {"state_dict": model.state_dict(), "hidden": 16},
                WEIGHTS_DIR / "mlp_float.pt",
            )

    (RESULTS_DIR / "ablation_hidden.json").write_text(json.dumps(hidden_rows, indent=2))

    # --- Q-format sweep on H=16 ---
    model16 = models[16]
    params = model16.numpy_parameters()
    q_rows = []
    for name, frac in (("Q8.8", 8), ("Q4.12", 12), ("Q2.14", 14)):
        qparams = quantize_params(params, frac_bits=frac)
        quant_acc = eval_quant_fast(qparams, x_test, y_test, frac_bits=frac)
        row = {"format": name, "frac_bits": frac, "quant_acc": quant_acc}
        q_rows.append(row)
        print(row)
    (RESULTS_DIR / "ablation_qformat.json").write_text(json.dumps(q_rows, indent=2))

    # --- Latency table ---
    lat_rows = [
        {
            "hidden": h,
            "est_cycles": estimate_cycles(h),
            "latency_ms_at_100mhz": estimate_cycles(h) / 1e5 * 1e3,
            "images_per_s_at_100mhz": 1e8 / estimate_cycles(h),
        }
        for h in (8, 16, 32)
    ]
    (RESULTS_DIR / "ablation_latency.json").write_text(json.dumps(lat_rows, indent=2))

    # Plots
    try:
        import matplotlib.pyplot as plt

        hs = [r["hidden"] for r in hidden_rows]
        plt.figure(figsize=(6, 4))
        plt.plot(hs, [r["float_acc"] for r in hidden_rows], "o-", label="float")
        plt.plot(hs, [r["q88_acc"] for r in hidden_rows], "s-", label="Q8.8")
        plt.xlabel("hidden size")
        plt.ylabel("test accuracy")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(RESULTS_DIR / "ablation_hidden.png", dpi=120)
        plt.close()

        fracs = [r["frac_bits"] for r in q_rows]
        plt.figure(figsize=(6, 4))
        plt.plot(fracs, [r["quant_acc"] for r in q_rows], "o-")
        plt.xticks(fracs, [r["format"] for r in q_rows])
        plt.ylabel("test accuracy")
        plt.xlabel("fixed-point format")
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(RESULTS_DIR / "ablation_qformat.png", dpi=120)
        plt.close()
        print("Saved ablation plots")
    except ImportError:
        pass

    print("Ablations written to results/")


if __name__ == "__main__":
    main()
