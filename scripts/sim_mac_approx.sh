#!/usr/bin/env bash
# Simulation runner for Approximate MAC (mac_approx.vhd)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/vhdl/rtl"
TB="$ROOT/vhdl/tb"
WORK="$ROOT/results/ghdl_work"
mkdir -p "$WORK"
cd "$WORK"

GHDL="${GHDL:-ghdl}"

echo "=== Compiling Approximate MAC Modules ==="
$GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
$GHDL -a --std=08 "$RTL/mac_approx.vhd"
$GHDL -a --std=08 "$TB/tb_mac_approx.vhd"

echo "=== Elaborating and Running tb_mac_approx ==="
$GHDL -e --std=08 tb_mac_approx
$GHDL -r --std=08 tb_mac_approx

echo "=== tb_mac_approx Simulation Finished Successfully ==="
