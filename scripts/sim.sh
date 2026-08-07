#!/usr/bin/env bash
# GHDL simulation helper for MLP FPGA accelerator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/sim.sh"
RTL="$ROOT/vhdl/rtl"
TB="$ROOT/vhdl/tb"
WORK="$ROOT/results/ghdl_work"
mkdir -p "$WORK"
cd "$WORK"

GHDL="${GHDL:-ghdl}"
WAVE="${WAVE:-0}"

analyze_common() {
  $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
  $GHDL -a --std=08 "$RTL/pkg_weights.vhd"
  $GHDL -a --std=08 "$RTL/mac.vhd"
  $GHDL -a --std=08 "$RTL/relu.vhd"
  $GHDL -a --std=08 "$RTL/neuron.vhd"
  $GHDL -a --std=08 "$RTL/rom_weights.vhd"
  $GHDL -a --std=08 "$RTL/dense_layer.vhd"
  $GHDL -a --std=08 "$RTL/argmax.vhd"
  $GHDL -a --std=08 "$RTL/controller.vhd"
  $GHDL -a --std=08 "$RTL/mlp_top.vhd"
}

run_tb() {
  local entity="$1"
  local tb_file="$2"
  shift 2
  $GHDL -a --std=08 "$TB/$tb_file"
  $GHDL -e --std=08 "$entity"
  if [[ "$WAVE" == "1" ]]; then
    $GHDL -r --std=08 "$entity" --wave="${entity}.ghw" "$@"
    echo "Waveform: $WORK/${entity}.ghw"
  else
    $GHDL -r --std=08 "$entity" "$@"
  fi
}

usage() {
  echo "Usage: $0 {mac|relu|unit|top|all} [--wave]"
  exit 1
}

TARGET="${1:-all}"
if [[ "${2:-}" == "--wave" ]]; then
  WAVE=1
fi

case "$TARGET" in
  mac)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac.vhd"
    run_tb tb_mac tb_mac.vhd
    ;;
  relu)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/relu.vhd"
    run_tb tb_relu tb_relu.vhd
    ;;
  unit)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac.vhd"
    $GHDL -a --std=08 "$RTL/relu.vhd"
    run_tb tb_mac tb_mac.vhd
    run_tb tb_relu tb_relu.vhd
    ;;
  top)
    analyze_common
    run_tb tb_mlp_top tb_mlp_top.vhd
    ;;
  all)
    "$SCRIPT" unit
    "$SCRIPT" top
    ;;
  *)
    usage
    ;;
esac

echo "OK: $TARGET"
