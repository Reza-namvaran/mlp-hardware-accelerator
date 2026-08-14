library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Unit Testbench for Approximate MAC Architecture (mac_approx)
-- Verifies LSB truncation/masking behavior and Q8.8 accumulator output.
entity tb_mac_approx is
end entity tb_mac_approx;

architecture sim of tb_mac_approx is
  constant MASK_BITS : integer := 4;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal clear     : std_logic := '0';
  signal enable    : std_logic := '0';
  signal load_bias : std_logic := '0';
  signal a         : data_t := (others => '0');
  signal b         : data_t := (others => '0');
  signal bias      : data_t := (others => '0');
  signal result    : data_t;
  signal acc       : acc_t;
  signal done_flag : boolean := false;

  constant CLK_PERIOD : time := 10 ns;
begin
  -- Clock Generator (100 MHz)
  clk <= not clk after CLK_PERIOD / 2 when not done_flag else '0';

  -- Unit Under Test Instantiation
  uut : entity work.mac_approx
    generic map (
      MASK_BITS => MASK_BITS
    )
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
    -- Exact values:
    -- Activation A = 1.55078125 (0x018D = 397 in Q8.8)
    -- Weight B     = 2.05078125 (0x020D = 525 in Q8.8)
    -- Bias         = 1.0        (0x0100 = 256 in Q8.8)
    --
    -- Masked with MASK_BITS = 4 (clears lower 4 bits):
    -- Masked A = 0x0180 (1.5)
    -- Masked B = 0x0200 (2.0)
    --
    -- Expected Output = 1.0 + (1.5 * 2.0) = 4.0 -> 0x0400 in Q8.8
    constant A_EXACT : data_t := to_signed(16#018D#, 16);
    constant B_EXACT : data_t := to_signed(16#020D#, 16);
    constant BIAS_Q  : data_t := to_signed(16#0100#, 16);
  begin
    -- Reset Sequence
    rst <= '1';
    wait for 20 ns;
    wait until rising_edge(clk);
    rst <= '0';

    -- Step 1: Load Bias (1.0 in Q8.8)
    bias      <= BIAS_Q;
    clear     <= '1';
    load_bias <= '1';
    enable    <= '0';
    wait until rising_edge(clk);
    clear     <= '0';
    load_bias <= '0';

    -- Step 2: Multiply Approximate Inputs
    a      <= A_EXACT;
    b      <= B_EXACT;
    enable <= '1';
    wait until rising_edge(clk);
    enable <= '0';

    wait until rising_edge(clk);

    -- Step 3: Verify Output Result (Expected truncated output: 0x0400)
    assert result = to_signed(16#0400#, 16)
      report "tb_mac_approx test failed: Expected 0x0400"
      severity failure;

    report "=== tb_mac_approx PASS ===";
    done_flag <= true;
    wait;
  end process;

end architecture sim;
