library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Argmax over 10 Q8.8 logits (combinational), balanced tournament tree.
--
-- The original implementation compared sequentially (best_v vs v1, then
-- best_v vs v2, ...), a 9-deep dependency chain: comparison i cannot start
-- until comparison i-1 has resolved. Measured in Vivado (xc7a100tcsg324-1):
-- this was the design's critical path both with and without the
-- parallel-MAC bonus (~39-40 MHz either way), 33 logic levels / 14 CARRY4
-- chained through this one module.
--
-- A tournament tree resolves independent comparisons in parallel: round 1's
-- 5 comparisons don't depend on each other, so they settle simultaneously;
-- same for round 2's 2 comparisons. Depth drops from 9 to ceil(log2(10))=4.
--
-- Tie-breaking is preserved exactly: every comparison node only switches to
-- the higher-index candidate when it is STRICTLY greater (never on a tie),
-- so the smallest index among equal maxima always wins -- identical to the
-- original sequential scan's behavior. tb_argmax.vhd checks this explicitly.
entity argmax is
  port (
    v0, v1, v2, v3, v4, v5, v6, v7, v8, v9 : in  data_t;
    cls : out unsigned(3 downto 0)
  );
end entity argmax;

architecture rtl of argmax is
begin
  process (v0, v1, v2, v3, v4, v5, v6, v7, v8, v9)
    -- Round 1: 5 independent pairwise comparisons (even index vs odd index)
    variable r1v0, r1v1, r1v2, r1v3, r1v4 : data_t;
    variable r1i0, r1i1, r1i2, r1i3, r1i4 : integer;
    -- Round 2: 2 independent comparisons over 4 of the round-1 winners
    variable r2v0, r2v1 : data_t;
    variable r2i0, r2i1 : integer;
    -- Round 3: winner of {0..3} vs winner of {4..7}
    variable r3v : data_t;
    variable r3i : integer;
    -- Round 4 (final): winner of {0..7} vs winner of {8,9}
    variable best_v : data_t;
    variable best_i : integer;
  begin
    -- Round 1 -- ties favor the lower (earlier) index in every pair
    if v1 > v0 then r1v0 := v1; r1i0 := 1; else r1v0 := v0; r1i0 := 0; end if;
    if v3 > v2 then r1v1 := v3; r1i1 := 3; else r1v1 := v2; r1i1 := 2; end if;
    if v5 > v4 then r1v2 := v5; r1i2 := 5; else r1v2 := v4; r1i2 := 4; end if;
    if v7 > v6 then r1v3 := v7; r1i3 := 7; else r1v3 := v6; r1i3 := 6; end if;
    if v9 > v8 then r1v4 := v9; r1i4 := 9; else r1v4 := v8; r1i4 := 8; end if;

    -- Round 2 (r1v4/r1i4, the winner of {8,9}, carries forward to round 4)
    if r1v1 > r1v0 then r2v0 := r1v1; r2i0 := r1i1; else r2v0 := r1v0; r2i0 := r1i0; end if;
    if r1v3 > r1v2 then r2v1 := r1v3; r2i1 := r1i3; else r2v1 := r1v2; r2i1 := r1i2; end if;

    -- Round 3: winner of {0,1,2,3} vs winner of {4,5,6,7}
    if r2v1 > r2v0 then r3v := r2v1; r3i := r2i1; else r3v := r2v0; r3i := r2i0; end if;

    -- Round 4 (final): winner of {0..7} vs winner of {8,9}
    if r1v4 > r3v then best_v := r1v4; best_i := r1i4; else best_v := r3v; best_i := r3i; end if;

    cls <= to_unsigned(best_i, 4);
  end process;
end architecture rtl;
