library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Unit testbench for argmax.vhd (combinational, no clock).
-- Covers: a clear winner, a tie (must resolve to the lowest index, matching
-- the original sequential-scan semantics), and an all-negative case (Q8.8
-- values are signed, so "largest" is not "largest magnitude").
entity tb_argmax is
end entity tb_argmax;

architecture sim of tb_argmax is
  signal v0, v1, v2, v3, v4, v5, v6, v7, v8, v9 : data_t;
  signal cls : unsigned(3 downto 0);
begin
  uut : entity work.argmax
    port map (
      v0 => v0, v1 => v1, v2 => v2, v3 => v3, v4 => v4,
      v5 => v5, v6 => v6, v7 => v7, v8 => v8, v9 => v9,
      cls => cls
    );

  process
  begin
    -- Case 1: clear winner at index 7
    v0 <= to_signed(1, 16);  v1 <= to_signed(2, 16);
    v2 <= to_signed(3, 16);  v3 <= to_signed(4, 16);
    v4 <= to_signed(5, 16);  v5 <= to_signed(6, 16);
    v6 <= to_signed(7, 16);  v7 <= to_signed(10, 16);
    v8 <= to_signed(8, 16);  v9 <= to_signed(9, 16);
    wait for 1 ns;
    assert cls = to_unsigned(7, 4)
      report "case 1 (clear winner) failed: expected 7 got " & integer'image(to_integer(cls))
      severity failure;

    -- Case 2: tie between index 3 and index 6 -> lower index (3) must win
    v0 <= to_signed(50, 16); v1 <= to_signed(50, 16);
    v2 <= to_signed(50, 16); v3 <= to_signed(100, 16);
    v4 <= to_signed(50, 16); v5 <= to_signed(50, 16);
    v6 <= to_signed(100, 16); v7 <= to_signed(50, 16);
    v8 <= to_signed(50, 16); v9 <= to_signed(50, 16);
    wait for 1 ns;
    assert cls = to_unsigned(3, 4)
      report "case 2 (tie) failed: expected 3 got " & integer'image(to_integer(cls))
      severity failure;

    -- Case 3: tie between index 0 and index 9 (the two round-1 pair winners
    -- that meet last, at round 4) -> lower index (0) must win
    v0 <= to_signed(100, 16); v1 <= to_signed(1, 16);
    v2 <= to_signed(1, 16);   v3 <= to_signed(1, 16);
    v4 <= to_signed(1, 16);   v5 <= to_signed(1, 16);
    v6 <= to_signed(1, 16);   v7 <= to_signed(1, 16);
    v8 <= to_signed(1, 16);   v9 <= to_signed(100, 16);
    wait for 1 ns;
    assert cls = to_unsigned(0, 4)
      report "case 3 (tie at final round) failed: expected 0 got " & integer'image(to_integer(cls))
      severity failure;

    -- Case 4: all negative -- the "largest" is the least negative (index 9)
    v0 <= to_signed(-10, 16); v1 <= to_signed(-9, 16);
    v2 <= to_signed(-8, 16);  v3 <= to_signed(-7, 16);
    v4 <= to_signed(-6, 16);  v5 <= to_signed(-5, 16);
    v6 <= to_signed(-4, 16);  v7 <= to_signed(-3, 16);
    v8 <= to_signed(-2, 16);  v9 <= to_signed(-1, 16);
    wait for 1 ns;
    assert cls = to_unsigned(9, 4)
      report "case 4 (all negative) failed: expected 9 got " & integer'image(to_integer(cls))
      severity failure;

    report "tb_argmax PASS";
    wait;
  end process;
end architecture sim;
