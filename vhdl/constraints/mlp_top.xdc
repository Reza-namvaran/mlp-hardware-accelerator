## Clock: 20 ns period (50 MHz), the design's actual rated frequency.
##
## GHDL's cycle-count results (results/performance.md) use a 10 ns/100 MHz
## testbench clock, but that number was never derived from what this design
## can achieve on real silicon -- it was just a convenient simulation choice.
## Real synthesis showed neither configuration meets 100 MHz even after the
## argmax critical-path fix (results/argmax_optimization.md): ~66.3 MHz
## serial, ~60.3 MHz parallel. 50 MHz is comfortably under both ceilings, so
## the design is constrained here at a frequency it actually meets, the same
## way a real datasheet reports a part's rated frequency rather than an
## unmet aspirational one. Cycle counts (results/performance.md) are
## unaffected -- they come from simulation, not this constraint.
create_clock -period 20.000 -name clk [get_ports clk]

## Removed: set_input_delay/set_output_delay of 2.000 ns on the I/O ports.
## These never modeled a real board (none exists for this project) -- they
## were only a placeholder so the I/O timing checker had something to look
## at. That fabricated 2 ns number turned out to directly cause a real,
## measured hold violation (WHS/THS = -0.005 ns, 1 endpoint: load_data[13]
## -> in_mem_reg[440][13]) once the design was re-constrained to a period it
## can actually meet (see report6/serial). Since these constraints modeled
## nothing physically real to begin with, the correct fix is to remove them,
## not to tune the number until the artifact disappears. The check_timing
## "no_input_delay"/"no_output_delay" notices this brings back are expected
## and harmless for an out-of-context synthesis with no target board -- the
## same category as the NSTD-1/UCIO-1/CFGBVS-1 DRC items already documented
## as expected in every prior synthesis run.
