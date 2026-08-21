"""Configurable MLP: Input → Hidden (ReLU) → Output (logits) — PyTorch."""

from __future__ import annotations

import numpy as np
import torch
import torch.nn as nn

from config import HIDDEN_SIZE, INPUT_SIZE, OUTPUT_SIZE


class MLP(nn.Module):
    def __init__(
        self,
        input_size: int = INPUT_SIZE,
        hidden_size: int = HIDDEN_SIZE,
        output_size: int = OUTPUT_SIZE,
    ) -> None:
        super().__init__()
        self.input_size = input_size
        self.hidden_size = hidden_size
        self.output_size = output_size
        self.fc1 = nn.Linear(input_size, hidden_size)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(hidden_size, output_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.fc2(self.relu(self.fc1(x)))

    @torch.no_grad()
    def predict(self, x: torch.Tensor | np.ndarray) -> np.ndarray:
        self.eval()
        if isinstance(x, np.ndarray):
            x = torch.from_numpy(x.astype(np.float32))
        logits = self.forward(x)
        return logits.argmax(dim=1).cpu().numpy()

    def numpy_parameters(self) -> dict[str, np.ndarray]:
        """Export weights in VHDL/export layout: (out, in) row-major."""
        return {
            "w1": self.fc1.weight.detach().cpu().numpy().astype(np.float32),
            "b1": self.fc1.bias.detach().cpu().numpy().astype(np.float32),
            "w2": self.fc2.weight.detach().cpu().numpy().astype(np.float32),
            "b2": self.fc2.bias.detach().cpu().numpy().astype(np.float32),
        }

    def load_numpy_parameters(self, params: dict[str, np.ndarray]) -> None:
        with torch.no_grad():
            self.fc1.weight.copy_(torch.from_numpy(params["w1"].astype(np.float32)))
            self.fc1.bias.copy_(torch.from_numpy(params["b1"].astype(np.float32)))
            self.fc2.weight.copy_(torch.from_numpy(params["w2"].astype(np.float32)))
            self.fc2.bias.copy_(torch.from_numpy(params["b2"].astype(np.float32)))

    # Back-compat aliases used by quantization/evaluate
    @property
    def w1(self) -> np.ndarray:
        return self.fc1.weight.detach().cpu().numpy().astype(np.float32)

    @property
    def b1(self) -> np.ndarray:
        return self.fc1.bias.detach().cpu().numpy().astype(np.float32)

    @property
    def w2(self) -> np.ndarray:
        return self.fc2.weight.detach().cpu().numpy().astype(np.float32)

    @property
    def b2(self) -> np.ndarray:
        return self.fc2.bias.detach().cpu().numpy().astype(np.float32)
