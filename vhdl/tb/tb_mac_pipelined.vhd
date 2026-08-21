library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Unit Testbench for Pipelined MAC Architecture (Bonus Feature)
-- Verifies 2-stage pipeline latency and Q8.8 fixed-point arithmetic execution.
entity tb_mac_pipelined is
end entity tb_mac_pipelined;

architecture sim of tb_mac_pipelined is
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal clear     : std_logic := '0';
  signal enable    : std_logic := '0';
  signal load_bias : std_logic := '0';
  signal a, b, bias, result : data_t := (others => '0');
  signal acc       : acc_t;
  signal done_flag : boolean := false;

  constant CLK_PERIOD : time := 10 ns;
begin
  -- Clock Generator (100 MHz)
  clk <= not clk after CLK_PERIOD / 2 when not done_flag else '0';

  -- Unit Under Test (UUT) Instantiation
  uut : entity work.mac_pipelined
    port map (
      clk       => clk,
      rst       => rst,
      clear     => clear,
      enable    => enable,
      a         => a,
      b         => b,
      bias      => bias,
      load_bias => load_bias,
      acc_out   => acc,
      result    => result
    );

  -- Stimulus Process
  process
    constant A_Q    : data_t := to_signed(16#0180#, 16); -- 1.5 in Q8.8
    constant B_Q    : data_t := to_signed(16#0200#, 16); -- 2.0 in Q8.8
    constant BIAS_Q : data_t := to_signed(16#0100#, 16); -- 1.0 in Q8.8
  begin
    -- Reset Sequence
    rst <= '1';
    wait for 20 ns;
    wait until rising_edge(clk);
    rst <= '0';

    -- Step 1: Load Initial Bias
    bias      <= BIAS_Q;
    clear     <= '1';
    load_bias <= '1';
    enable    <= '0';
    wait until rising_edge(clk);
    clear     <= '0';
    load_bias <= '0';
    wait until rising_edge(clk); -- Advance stage 1 pipeline for bias load

    -- Step 2: Multiply and Accumulate (1.5 * 2.0)
    a      <= A_Q;
    b      <= B_Q;
    enable <= '1';
    wait until rising_edge(clk);
    enable <= '0';
    wait until rising_edge(clk); -- Advance product from stage 1 to stage 2 accumulator

    -- Step 3: Verify Output Result (Expected: 1.0 + (1.5 * 2.0) = 4.0 -> 0x0400 in Q8.8)
    wait until rising_edge(clk);
    assert result = to_signed(16#0400#, 16)
      report "Pipelined MAC test failed: Expected 0x0400 (4.0 in Q8.8)"
      severity failure;

    report "=== tb_mac_pipelined PASS ===";
    done_flag <= true;
    wait;
  end process;

end architecture sim;
