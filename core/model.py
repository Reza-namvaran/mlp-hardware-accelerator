from __future__ import annotations

import numpy as np

from config import HIDDEN_SIZE, INPUT_SIZE, OUTPUT_SIZE


class MLP:
    def __init__(
        self,
        input_size: int = INPUT_SIZE,
        hidden_size: int = HIDDEN_SIZE,
        output_size: int = OUTPUT_SIZE,
        rng: np.random.Generator | None = None,
    ) -> None:
        self.input_size = input_size
        self.hidden_size = hidden_size
        self.output_size = output_size
        rng = rng or np.random.default_rng(0)

        self.w1 = rng.normal(0, np.sqrt(2.0 / input_size), (hidden_size, input_size)).astype(np.float32)
        self.b1 = np.zeros(hidden_size, dtype=np.float32)
        self.w2 = rng.normal(0, np.sqrt(1.0 / hidden_size), (output_size, hidden_size)).astype(np.float32)
        self.b2 = np.zeros(output_size, dtype=np.float32)

    def forward(self, x: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Return (logits, hidden_pre_relu, hidden_post_relu). x: (N, input)."""
        z1 = x @ self.w1.T + self.b1
        a1 = np.maximum(z1, 0.0)
        z2 = a1 @ self.w2.T + self.b2
        return z2, z1, a1

    def predict(self, x: np.ndarray) -> np.ndarray:
        logits, _, _ = self.forward(x)
        return np.argmax(logits, axis=1)

    def parameters(self) -> dict[str, np.ndarray]:
        return {"w1": self.w1, "b1": self.b1, "w2": self.w2, "b2": self.b2}

    def load_parameters(self, params: dict[str, np.ndarray]) -> None:
        self.w1 = params["w1"].astype(np.float32)
        self.b1 = params["b1"].astype(np.float32)
        self.w2 = params["w2"].astype(np.float32)
        self.b2 = params["b2"].astype(np.float32)
