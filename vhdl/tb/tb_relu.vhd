library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

entity tb_relu is
end entity tb_relu;

architecture sim of tb_relu is
  signal x, y : data_t;
begin
  uut : entity work.relu port map (x => x, y => y);

  process
  begin
    x <= to_signed(100, 16);
    wait for 1 ns;
    assert y = to_signed(100, 16) report "ReLU positive failed" severity failure;

    x <= to_signed(-50, 16);
    wait for 1 ns;
    assert y = to_signed(0, 16) report "ReLU negative failed" severity failure;

    x <= to_signed(0, 16);
    wait for 1 ns;
    assert y = to_signed(0, 16) report "ReLU zero failed" severity failure;

    report "tb_relu PASS";
    wait;
  end process;
end architecture sim;
