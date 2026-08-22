library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;

-- Synchronous (registered) ROM wrappers over pkg_weights constants.
--
-- Registered rather than combinational specifically so Vivado can infer
-- Block RAM: BRAM inference requires the read to be synchronous (address
-- captured on one clock edge, data valid the next), which a purely
-- combinational read can never map onto. Before this change the entire
-- ~203 Kbit weight table lived in LUT-based distributed logic (0/135 BRAM
-- tiles used) purely because of this.
--
-- This adds one cycle of latency between presenting an address and the
-- data being valid. That is safe with zero changes to neuron.vhd or
-- dense_layer.vhd: the calling FSM already holds every ROM address stable
-- for two full cycles (neuron.vhd's MAC_HOLD then ADVANCE) before mac.vhd
-- actually samples the data (at the edge ending ADVANCE, gated by
-- `enable`), and bias addresses are stable far longer than that (fixed for
-- an entire neuron's lifetime). One cycle of registered latency fits
-- inside that existing margin exactly -- see
-- results/bram_weight_rom.md for the full timing walkthrough.
--
-- Ports are MAX_PARALLEL-wide address/data arrays so dense_layer can read
-- one weight/bias row per active parallel lane in the same cycle
-- (parallel-MAC bonus). Lanes beyond the layer's N_PARALLEL are simply tied
-- to address 0 by the caller and their data output is left unused;
-- synthesis prunes them.
entity rom_weights is
  port (
    clk     : in  std_logic;
    -- Layer 1: address = neuron * INPUT_SIZE + input_idx
    w1_addr : in  addr_array_t;
    w1_data : out data_array_t;
    b1_addr : in  addr_array_t;
    b1_data : out data_array_t;
    -- Layer 2
    w2_addr : in  addr_array_t;
    w2_data : out data_array_t;
    b2_addr : in  addr_array_t;
    b2_data : out data_array_t
  );
end entity rom_weights;

architecture rtl of rom_weights is
begin
  -- Callers always drive unused lanes' address to 0 (valid index), so every
  -- lane can read with no bounds checking needed here.
  process (clk)
  begin
    if rising_edge(clk) then
      for i in 0 to MAX_PARALLEL - 1 loop
        w1_data(i) <= signed(W1(w1_addr(i)));
        b1_data(i) <= signed(B1(b1_addr(i)));
        w2_data(i) <= signed(W2(w2_addr(i)));
        b2_data(i) <= signed(B2(b2_addr(i)));
      end loop;
    end if;
  end process;
end architecture rtl;
