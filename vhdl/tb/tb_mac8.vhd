library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Unit Testbench for Dynamic Precision MAC Architecture (mac8)
-- Verifies 8-bit Q0.8 weight multiplication with 16-bit Q8.8 activation and 32-bit accumulation.
entity tb_mac8 is
end entity tb_mac8;

architecture sim of tb_mac8 is
  constant WEIGHT_WIDTH : integer := 8;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal clear     : std_logic := '0';
  signal enable    : std_logic := '0';
  signal load_bias : std_logic := '0';
  signal a         : data_t := (others => '0');
  signal w         : signed(WEIGHT_WIDTH - 1 downto 0) := (others => '0');
  signal bias      : data_t := (others => '0');
  signal result    : data_t;
  signal acc       : acc_t;
  signal done_flag : boolean := false;

  constant CLK_PERIOD : time := 10 ns;
begin
  -- Clock Generator (100 MHz)
  clk <= not clk after CLK_PERIOD / 2 when not done_flag else '0';

  -- Unit Under Test Instantiation
  uut : entity work.mac8
    generic map (
      WEIGHT_WIDTH => WEIGHT_WIDTH
    )
    port map (
      clk       => clk,
      rst       => rst,
      clear     => clear,
      enable    => enable,
      a         => a,
      w         => w,
      bias      => bias,
      load_bias => load_bias,
      acc_out   => acc,
      result    => result
    );

  -- Stimulus Process
  process
    constant A_Q    : data_t := to_signed(16#0180#, 16);                      -- 1.5 in Q8.8
    constant W_8    : signed(WEIGHT_WIDTH - 1 downto 0) := to_signed(64, 8);  -- 0.25 in Q0.8
    constant BIAS_Q : data_t := to_signed(16#0100#, 16);                      -- 1.0 in Q8.8
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

    -- Step 2: Multiply 16-bit Activation (1.5) by 8-bit Weight (0.25) and Accumulate
    a      <= A_Q;
    w      <= W_8;
    enable <= '1';
    wait until rising_edge(clk);
    enable <= '0';

    wait until rising_edge(clk);

    -- Step 3: Verify Output Result (Expected: 1.0 + (1.5 * 0.25) = 1.375 -> 0x0160 in Q8.8)
    assert result = to_signed(16#0160#, 16)
      report "tb_mac8 test failed: Expected 0x0160"
      severity failure;

    report "=== tb_mac8 PASS ===";
    done_flag <= true;
    wait;
  end process;

end architecture sim;
