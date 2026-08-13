#!/usr/bin/env bash
# Automated GHDL compilation and simulation script for top-level MLP accelerator

set -euo pipefail

# Find repository root directory
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/vhdl/rtl"
TB="$ROOT/vhdl/tb"
WORK="$ROOT/results/ghdl_work"

mkdir -p "$WORK"
cd "$WORK"

GHDL="${GHDL:-ghdl}"

echo "==> Compiling RTL source files..."
$GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
$GHDL -a --std=08 "$RTL/pkg_weights.vhd"
$GHDL -a --std=08 "$RTL/mac.vhd"
$GHDL -a --std=08 "$RTL/relu.vhd"
$GHDL -a --std=08 "$RTL/argmax.vhd"
$GHDL -a --std=08 "$RTL/rom_weights.vhd"
$GHDL -a --std=08 "$RTL/neuron.vhd"
$GHDL -a --std=08 "$RTL/dense_layer.vhd"
$GHDL -a --std=08 "$RTL/mlp_top.vhd"

echo "==> Compiling testbench..."
$GHDL -a --std=08 "$TB/tb_mlp_top.vhd"

echo "==> Elaborating top-level testbench..."
$GHDL -e --std=08 tb_mlp_top

echo "==> Running simulation..."
$GHDL -r --std=08 tb_mlp_top

echo "==> Top-level MLP simulation completed successfully."
