"""Train float32 MLP on MNIST with PyTorch."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    CHECKPOINT_PATH,
    FLOAT_WEIGHTS_NPZ,
    HIDDEN_SIZE,
    RESULTS_DIR,
    WEIGHTS_DIR,
)
from mnist_loader import load_mnist
from model import MLP


def make_loader(
    x: np.ndarray, y: np.ndarray, batch_size: int, shuffle: bool
) -> DataLoader:
    xt = torch.from_numpy(x.astype(np.float32))
    yt = torch.from_numpy(y.astype(np.int64))
    return DataLoader(TensorDataset(xt, yt), batch_size=batch_size, shuffle=shuffle)


@torch.no_grad()
def evaluate(model: MLP, loader: DataLoader, device: torch.device) -> tuple[float, float]:
    model.eval()
    criterion = nn.CrossEntropyLoss(reduction="sum")
    total_loss = 0.0
    correct = 0
    n = 0
    for xb, yb in loader:
        xb, yb = xb.to(device), yb.to(device)
        logits = model(xb)
        total_loss += float(criterion(logits, yb))
        correct += int((logits.argmax(1) == yb).sum())
        n += yb.size(0)
    return total_loss / n, correct / n


def train_epoch(
    model: MLP,
    loader: DataLoader,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
) -> tuple[float, float]:
    model.train()
    criterion = nn.CrossEntropyLoss(reduction="sum")
    total_loss = 0.0
    correct = 0
    n = 0
    for xb, yb in loader:
        xb, yb = xb.to(device), yb.to(device)
        optimizer.zero_grad(set_to_none=True)
        logits = model(xb)
        loss = criterion(logits, yb)
        loss.backward()
        optimizer.step()
        total_loss += float(loss.detach())
        correct += int((logits.argmax(1) == yb).sum())
        n += yb.size(0)
    return total_loss / n, correct / n


def main() -> None:
    parser = argparse.ArgumentParser(description="Train MNIST MLP (PyTorch)")
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--hidden", type=int, default=HIDDEN_SIZE)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--device", type=str, default="cpu")
    args = parser.parse_args()

    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    device = torch.device(args.device)

    # Prefer local IDX under data/ (offline-friendly); torchvision optional later
    x_train, y_train = load_mnist("train")
    x_test, y_test = load_mnist("test")
    train_loader = make_loader(x_train, y_train, args.batch_size, shuffle=True)
    test_loader = make_loader(x_test, y_test, 512, shuffle=False)

    model = MLP(hidden_size=args.hidden).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    history: list[dict] = []
    print(f"Training MLP 784-{args.hidden}-10 for {args.epochs} epochs (PyTorch/{device})...")
    for epoch in range(1, args.epochs + 1):
        tr_loss, tr_acc = train_epoch(model, train_loader, optimizer, device)
        te_loss, te_acc = evaluate(model, test_loader, device)
        history.append(
            {
                "epoch": epoch,
                "train_loss": float(tr_loss),
                "train_acc": float(tr_acc),
                "test_loss": float(te_loss),
                "test_acc": float(te_acc),
            }
        )
        print(
            f"epoch {epoch:02d}  train_loss={tr_loss:.4f} train_acc={tr_acc:.4f}  "
            f"test_loss={te_loss:.4f} test_acc={te_acc:.4f}"
        )

    params = model.numpy_parameters()
    np.savez(FLOAT_WEIGHTS_NPZ, **params)
    torch.save({"state_dict": model.state_dict(), "hidden": args.hidden}, CHECKPOINT_PATH)

    (RESULTS_DIR / "train_history.json").write_text(json.dumps(history, indent=2))

    try:
        import matplotlib.pyplot as plt

        epochs = [h["epoch"] for h in history]
        plt.figure(figsize=(8, 4))
        plt.subplot(1, 2, 1)
        plt.plot(epochs, [h["train_loss"] for h in history], label="train")
        plt.plot(epochs, [h["test_loss"] for h in history], label="test")
        plt.xlabel("epoch")
        plt.ylabel("loss")
        plt.legend()
        plt.subplot(1, 2, 2)
        plt.plot(epochs, [h["train_acc"] for h in history], label="train")
        plt.plot(epochs, [h["test_acc"] for h in history], label="test")
        plt.xlabel("epoch")
        plt.ylabel("accuracy")
        plt.legend()
        plt.tight_layout()
        plt.savefig(RESULTS_DIR / "train_curves.png", dpi=120)
        plt.close()
        print(f"Saved plot → {RESULTS_DIR / 'train_curves.png'}")
    except ImportError:
        pass

    print(f"Saved weights → {FLOAT_WEIGHTS_NPZ}")
    print(f"Saved checkpoint → {CHECKPOINT_PATH}")
    print(f"Final test accuracy: {history[-1]['test_acc']:.4f}")


if __name__ == "__main__":
    main()
