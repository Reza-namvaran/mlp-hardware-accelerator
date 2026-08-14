#!/usr/bin/env bash
# Master test suite runner script for the MLP hardware accelerator project.
# Compiles and executes all RTL modules, baseline top-level testbench, and
# available bonus testbenches using GHDL.

set -euo pipefail

# Determine repository root directory reliably
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/vhdl/rtl"
TB="$ROOT/vhdl/tb"
WORK="$ROOT/results/ghdl_work"

# Ensure output work directory exists
mkdir -p "$WORK"
cd "$WORK"

GHDL="${GHDL:-ghdl}"

# Terminal color output definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

run_testbench() {
    local test_name="$1"
    shift
    local src_files=("$@")

    echo "=================================================="
    echo "==> Running Testbench: ${test_name}"
    echo "=================================================="

    # Compile RTL and Testbench source files
    for src in "${src_files[@]}"; do
        if [ ! -f "$src" ]; then
            echo -e "${RED}[ERROR] Missing source file: ${src}${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
        $GHDL -a --std=08 "$src"
    done

    # Elaborate testbench entity
    $GHDL -e --std=08 "$test_name"

    # Run GHDL simulation
    if $GHDL -r --std=08 "$test_name"; then
        echo -e "${GREEN}[PASS] ${test_name}${NC}\n"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}[FAIL] ${test_name}${NC}\n"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo "=================================================="
echo " Starting Full MLP Accelerator Test Suite"
echo "=================================================="

# 1. Top-Level Accelerator System Simulation (Serial vs Parallel)
run_testbench "tb_mlp_top" \
    "$RTL/pkg_fixed.vhd" \
    "$RTL/pkg_weights.vhd" \
    "$RTL/mac.vhd" \
    "$RTL/relu.vhd" \
    "$RTL/argmax.vhd" \
    "$RTL/rom_weights.vhd" \
    "$RTL/neuron.vhd" \
    "$RTL/dense_layer.vhd" \
    "$RTL/controller.vhd" \
    "$RTL/mlp_top.vhd" \
    "$TB/tb_mlp_top.vhd"

# 2. Bonus Feature 1: Pipelined MAC Unit Testbench
if [ -f "$RTL/mac_pipelined.vhd" ] && [ -f "$TB/tb_mac_pipelined.vhd" ]; then
    run_testbench "tb_mac_pipelined" \
        "$RTL/pkg_fixed.vhd" \
        "$RTL/mac_pipelined.vhd" \
        "$TB/tb_mac_pipelined.vhd"
else
    echo -e "${YELLOW}[SKIP] Pipelined MAC testbench files not found.${NC}\n"
fi

# 3. Bonus Feature 2: Dynamic Precision 8-bit MAC Unit Testbench
if [ -f "$RTL/mac8.vhd" ] && [ -f "$TB/tb_mac8.vhd" ]; then
    run_testbench "tb_mac8" \
        "$RTL/pkg_fixed.vhd" \
        "$RTL/mac8.vhd" \
        "$TB/tb_mac8.vhd"
else
    echo -e "${YELLOW}[SKIP] Dynamic precision MAC testbench files not found.${NC}\n"
fi

# 4. Bonus Feature 3: Approximate Computing MAC Unit Testbench
if [ -f "$RTL/mac_approx.vhd" ] && [ -f "$TB/tb_mac_approx.vhd" ]; then
    run_testbench "tb_mac_approx" \
        "$RTL/pkg_fixed.vhd" \
        "$RTL/mac_approx.vhd" \
        "$TB/tb_mac_approx.vhd"
else
    echo -e "${YELLOW}[SKIP] Approximate MAC testbench files not found.${NC}\n"
fi

echo "=================================================="
echo " Final Execution Summary"
echo "=================================================="
echo -e " Total Passed : ${GREEN}${PASSED_TESTS}${NC}"
echo -e " Total Failed : ${RED}${FAILED_TESTS}${NC}"
echo "=================================================="

if [ "$FAILED_TESTS" -ne 0 ]; then
    exit 1
fi
