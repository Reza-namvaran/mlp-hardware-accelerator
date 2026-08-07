library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

entity tb_mac is
end entity tb_mac;

architecture sim of tb_mac is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal clear, enable, load_bias : std_logic := '0';
  signal a, b, bias, result : data_t := (others => '0');
  signal acc : acc_t;
  signal done_flag : boolean := false;
begin
  clk <= not clk after 5 ns when not done_flag else '0';

  uut : entity work.mac
    port map (
      clk => clk, rst => rst, clear => clear, enable => enable,
      a => a, b => b, bias => bias, load_bias => load_bias,
      acc_out => acc, result => result
    );

  process
    -- 1.5 * 2.0 = 3.0 in Q8.8: 0x0180 * 0x0200 → product >> 8 = 0x0300
    constant A_Q : data_t := to_signed(16#0180#, 16);
    constant B_Q : data_t := to_signed(16#0200#, 16);
    constant BIAS_Q : data_t := to_signed(16#0100#, 16);  -- 1.0
    -- Expected: bias 1.0 + 3.0 = 4.0 → 0x0400
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';

    bias <= BIAS_Q;
    clear <= '1';
    load_bias <= '1';
    enable <= '0';
    wait until rising_edge(clk);
    clear <= '0';
    load_bias <= '0';

    a <= A_Q;
    b <= B_Q;
    enable <= '1';
    wait until rising_edge(clk);
    enable <= '0';
    wait until rising_edge(clk);

    assert result = to_signed(16#0400#, 16)
      report "MAC failed: expected 0x0400 got " & integer'image(to_integer(result))
      severity failure;

    report "tb_mac PASS";
    done_flag <= true;
    wait;
  end process;
end architecture sim;
