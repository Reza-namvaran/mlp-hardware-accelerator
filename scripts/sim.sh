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
  echo "Usage: $0 {mac|relu|mac8|mac_pipelined|mac_approx|unit|top|parallel|compare|all} [--wave]"
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
  mac8)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac8.vhd"
    run_tb tb_mac8 tb_mac8.vhd
    ;;
  mac_pipelined)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac_pipelined.vhd"
    run_tb tb_mac_pipelined tb_mac_pipelined.vhd
    ;;
  mac_approx)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac_approx.vhd"
    run_tb tb_mac_approx tb_mac_approx.vhd
    ;;
  argmax)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/argmax.vhd"
    run_tb tb_argmax tb_argmax.vhd
    ;;
  unit)
    $GHDL -a --std=08 "$RTL/pkg_fixed.vhd"
    $GHDL -a --std=08 "$RTL/mac.vhd"
    $GHDL -a --std=08 "$RTL/relu.vhd"
    $GHDL -a --std=08 "$RTL/mac8.vhd"
    $GHDL -a --std=08 "$RTL/mac_pipelined.vhd"
    $GHDL -a --std=08 "$RTL/mac_approx.vhd"
    $GHDL -a --std=08 "$RTL/argmax.vhd"
    run_tb tb_mac tb_mac.vhd
    run_tb tb_relu tb_relu.vhd
    run_tb tb_mac8 tb_mac8.vhd
    run_tb tb_mac_pipelined tb_mac_pipelined.vhd
    run_tb tb_mac_approx tb_mac_approx.vhd
    run_tb tb_argmax tb_argmax.vhd
    ;;
  top)
    analyze_common
    run_tb tb_mlp_top tb_mlp_top.vhd
    ;;
  parallel)
    analyze_common
    run_tb tb_mlp_top_parallel tb_mlp_top_parallel.vhd
    ;;
  compare)
    analyze_common
    run_tb tb_serial_vs_parallel tb_serial_vs_parallel.vhd
    ;;
  all)
    "$SCRIPT" unit
    "$SCRIPT" top
    "$SCRIPT" parallel
    "$SCRIPT" compare
    ;;
  *)
    usage
    ;;
esac

echo "OK: $TARGET"
