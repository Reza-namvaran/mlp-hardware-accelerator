# Simulation Report

HDL simulator: GHDL 4.1.0 (`--std=08`)
Clock: 100 MHz (period 10 ns)
Generated: 2026-08-08

## Setup

All analyses are performed from `results/ghdl_work/` via `scripts/sim.sh`.
Source files are analyzed from `vhdl/rtl/` and testbenches from `vhdl/tb/`.
Test vectors are read from `test_vectors/` (10 MNIST samples exported by
`core/export.py`).

## Unit tests

Run with: `./scripts/sim.sh unit`

| Testbench | Unit under test | Result |
|---|---|---|
| `tb_mac`   | MAC (1.5 x 2.0 + 1.0 = 4.0 in Q8.8) | PASS |
| `tb_relu`  | ReLU (positive / negative / zero)    | PASS |

No failures.

## Top-level test

Run with: `./scripts/sim.sh top`

Feeds the full 784-pixel image serially through `load_en`/`load_data`,
asserts `start`, and compares the top-level `class_out` with the golden
class stored in `test_vectors/expected_classes.txt`.

| Sample | Golden | HW class | Result |
|---|---|---|---|
| 0  | 0 | 0 | PASS |
| 1  | 1 | 1 | PASS |
| 2  | 2 | 2 | PASS |
| 3  | 3 | 3 | PASS |
| 4  | 4 | 4 | PASS |
| 5  | 6* | 6 | PASS |
| 6  | 6 | 6 | PASS |
| 7  | 7 | 7 | PASS |
| 8  | 8 | 8 | PASS |
| 9  | 9 | 9 | PASS |

Summary: **pass=10 fail=0**.

\* Golden for sample 5 (digit 5) is 6 because the quantized model itself
misclassifies it; the hardware reproduces the software golden exactly,
which is the correctness criterion for this project.

## MAC cross-check

`scripts/gen_mac_vectors.py` generates random Q8.8 MAC cases
(`results/mac_test_vectors.json`) so the MAC unit result can be compared
against the Python reference implementation.
