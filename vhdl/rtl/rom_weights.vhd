library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;

-- Combinational ROM wrappers over pkg_weights constants.
-- Ports are MAX_PARALLEL-wide address/data arrays so dense_layer can read
-- one weight/bias row per active parallel lane in the same cycle (parallel-MAC
-- bonus). Lanes beyond the layer's N_PARALLEL are simply tied to address 0 by
-- the caller and their data output is left unused; synthesis prunes them.
entity rom_weights is
  port (
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
  -- lane can read combinationally with no bounds checking needed here.
  gen_lanes : for i in 0 to MAX_PARALLEL - 1 generate
    w1_data(i) <= signed(W1(w1_addr(i)));
    b1_data(i) <= signed(B1(b1_addr(i)));
    w2_data(i) <= signed(W2(w2_addr(i)));
    b2_data(i) <= signed(B2(b2_addr(i)));
  end generate gen_lanes;
end architecture rtl;
