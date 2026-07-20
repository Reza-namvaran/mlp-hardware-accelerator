"""Shared architecture and fixed-point constants for SW/HW co-design."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Network architecture (frozen for HW)
INPUT_SIZE = 784
HIDDEN_SIZE = 16
OUTPUT_SIZE = 10

# Q8.8 signed fixed-point
DATA_WIDTH = 16
FRAC_BITS = 8
ACC_WIDTH = 32

SCALE = 1 << FRAC_BITS  # 256
Q_MIN = -(1 << (DATA_WIDTH - 1))
Q_MAX = (1 << (DATA_WIDTH - 1)) - 1

# Paths
DATA_DIR = ROOT / "data"
WEIGHTS_DIR = ROOT / "weights"
RESULTS_DIR = ROOT / "results"
TEST_VECTORS_DIR = ROOT / "test_vectors"
VHDL_RTL_DIR = ROOT / "vhdl" / "rtl"

CHECKPOINT_PATH = WEIGHTS_DIR / "mlp_float.npz"
FLOAT_WEIGHTS_NPZ = WEIGHTS_DIR / "float_weights.npz"
QUANT_WEIGHTS_NPZ = WEIGHTS_DIR / "quant_weights.npz"
METADATA_JSON = WEIGHTS_DIR / "metadata.json"
