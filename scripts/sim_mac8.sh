#!/usr/bin/env bash
# Simulation runner for Dynamic Precision MAC (mac8.vhd)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/vhdl/rtl"
TB="$ROOT/vhdl/tb"
WORK="$ROOT/results/ghdl_work"
mkdir -p "$WORK"
cd "$WORK"

GHDL="${GHDL:-ghdl}"

echo "=== Compiling Dynamic Precision MAC Modules ==="
$GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
$GHDL -a --std=08 "$RTL/mac8.vhd"
$GHDL -a --std=08 "$TB/tb_mac8.vhd"

echo "=== Elaborating and Running tb_mac8 ==="
$GHDL -e --std=08 tb_mac8
$GHDL -r --std=08 tb_mac8

echo "=== tb_mac8 Simulation Finished Successfully ==="
