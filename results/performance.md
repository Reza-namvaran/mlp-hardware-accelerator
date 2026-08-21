# Performance Analysis

Measured from the GHDL simulation of `mlp_top` (`scripts/sim.sh top`),
clock period 10 ns (100 MHz), serial configuration (N_PARALLEL=1).

## Latency per image

One image is classified in **26,384 cycles = 263.84 us @ 100 MHz**.

Measured from the delta between consecutive `done` assertions:

| Sample | Done time (ns) | Delta (ns) | Cycles |
|---|---|---|---|
| 0 | 263,845  | —          | —      |
| 1 | 527,685  | 263,840    | 26,384 |
| 2 | 791,525  | 263,840    | 26,384 |
| 3 | 1,055,365| 263,840    | 26,384 |
| 4 | 1,319,205| 263,840    | 26,384 |
| 5 | 1,583,045| 263,840    | 26,384 |
| 6 | 1,846,885| 263,840    | 26,384 |
| 7 | 2,110,725| 263,840    | 26,384 |
| 8 | 2,374,565| 263,840    | 26,384 |
| 9 | 2,638,405| 263,840    | 26,384 |

## Cycle budget breakdown

| Stage | Operation | Cycles |
|---|---|---|
| Input | Serial pixel load (784 pixels x 1 cycle) | 784 |
| Layer 1 | 16 neurons x 784 MACs (serial) | 12,544 |
| Layer 2 | 10 neurons x 16 MACs (serial) | 160 |
| Control | FSM / pipeline overhead + argmax | ~12,896 |
| **Total** | | **26,384** |

The dominant cost is layer 1 (12,544 MAC cycles, 47.5%). The neuron
count (784 x 16 + 16 x 10) alone accounts for 12,704 cycles; the rest is
FSM scheduling overhead.

## Throughput

- 3,790 images/s at 100 MHz (serial).
- Doubling parallelism in layer 1 (`N_PARALLEL=2`) would roughly halve
  the layer-1 cost; this is left as a documented extension (bonus).

## Real FPGA synthesis (Vivado, xc7a100tcsg324-1)

The cycle counts above are simulation timing, independent of clock
frequency. Real achievable clock frequency, resource usage, and power come
from actual synthesis, not simulation -- see `docs/final_report.md` §6 and
`results/argmax_optimization.md` for the full numbers and the argmax
critical-path fix that raised the achievable frequency from ~39 MHz to
~66 MHz.
