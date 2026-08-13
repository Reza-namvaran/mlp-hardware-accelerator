library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;

-- Top-level testbench for the MLP hardware accelerator.
-- Evaluates end-to-end inference execution, comparing serial baseline (N=1)
-- against fully parallel hardware configuration (N_hidden=16, N_output=10).
entity tb_mlp_top is
end entity tb_mlp_top;

architecture sim of tb_mlp_top is
  -- Clock and reset signals
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Serial baseline signals
  signal start     : std_logic := '0';
  signal load_en   : std_logic := '0';
  signal load_data : data_t := (others => '0');
  signal busy      : std_logic;
  signal done      : std_logic;
  signal class_out : unsigned(3 downto 0);

  -- Parallel accelerator signals
  signal start_p     : std_logic := '0';
  signal load_en_p   : std_logic := '0';
  signal load_data_p : data_t := (others => '0');
  signal busy_p      : std_logic;
  signal done_p      : std_logic;
  signal class_out_p : unsigned(3 downto 0);

  -- Clock definition (100 MHz)
  constant CLK_PERIOD : time := 10 ns;
  signal sim_finished : boolean := false;

  -- Test image array type
  type test_image_t is array (0 to INPUT_SIZE - 1) of data_t;

  -- Helper function to generate a test pattern (synthetic digit image)
  function gen_sample_image return test_image_t is
    variable img : test_image_t := (others => (others => '0'));
  begin
    -- Create an active 12x12 square in the center of the 28x28 grid
    for row in 8 to 19 loop
      for col in 8 to 19 loop
        img(row * 28 + col) := to_signed(16#0100#, DATA_WIDTH); -- 1.0 in Q8.8 fixed-point
      end loop;
    end loop;
    return img;
  end function;

  constant SAMPLE_IMG : test_image_t := gen_sample_image;

begin
  -- 100 MHz system clock generator
  clk <= not clk after CLK_PERIOD / 2 when not sim_finished else '0';

  -- Serial baseline accelerator instance (N_PARALLEL_HIDDEN = 1, N_PARALLEL_OUTPUT = 1)
  uut_serial : entity work.mlp_top
    generic map (
      N_PARALLEL_HIDDEN => 1,
      N_PARALLEL_OUTPUT => 1
    )
    port map (
      clk       => clk,
      rst       => rst,
      start     => start,
      load_en   => load_en,
      load_data => load_data,
      busy      => busy,
      done      => done,
      class_out => class_out
    );

  -- Fully parallel accelerator instance (N_PARALLEL_HIDDEN = 16, N_PARALLEL_OUTPUT = 10)
  uut_parallel : entity work.mlp_top
    generic map (
      N_PARALLEL_HIDDEN => 16,
      N_PARALLEL_OUTPUT => 10
    )
    port map (
      clk       => clk,
      rst       => rst,
      start     => start_p,
      load_en   => load_en_p,
      load_data => load_data_p,
      busy      => busy_p,
      done      => done_p,
      class_out => class_out_p
    );

  -- Stimulus and verification process
  stim_proc : process
    variable serial_cycles   : integer := 0;
    variable parallel_cycles : integer := 0;
  begin
    -- Reset sequence
    rst <= '1';
    wait for 20 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    --------------------------------------------------------------------
    -- Phase 1: Serial Baseline Execution
    --------------------------------------------------------------------
    report "--- Starting Serial Baseline Inference Run ---";

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Stream 784 Q8.8 pixel values into the buffer
    for i in 0 to INPUT_SIZE - 1 loop
      load_en   <= '1';
      load_data <= SAMPLE_IMG(i);
      wait until rising_edge(clk);
    end loop;
    load_en   <= '0';
    load_data <= (others => '0');

    -- Wait for completion and count execution cycles
    while done = '0' loop
      serial_cycles := serial_cycles + 1;
      wait until rising_edge(clk);
    end loop;

    report "Serial run finished.";
    report "Serial Latency: " & integer'image(serial_cycles) & " cycles";
    report "Predicted Class: " & integer'image(to_integer(class_out));

    assert class_out <= to_unsigned(9, 4)
      report "Error: Predicted class out of valid bounds [0..9]"
      severity failure;

    wait for 50 ns;
    wait until rising_edge(clk);

    --------------------------------------------------------------------
    -- Phase 2: Parallel Accelerator Execution
    --------------------------------------------------------------------
    report "--- Starting Parallel Accelerator Inference Run ---";

    start_p <= '1';
    wait until rising_edge(clk);
    start_p <= '0';

    -- Stream identical image pixels to the parallel unit
    for i in 0 to INPUT_SIZE - 1 loop
      load_en_p   <= '1';
      load_data_p <= SAMPLE_IMG(i);
      wait until rising_edge(clk);
    end loop;
    load_en_p   <= '0';
    load_data_p <= (others => '0');

    -- Wait for parallel unit completion and measure cycles
    while done_p = '0' loop
      parallel_cycles := parallel_cycles + 1;
      wait until rising_edge(clk);
    end loop;

    report "Parallel run finished.";
    report "Parallel Latency: " & integer'image(parallel_cycles) & " cycles";
    report "Predicted Parallel Class: " & integer'image(to_integer(class_out_p));

    -- Verify equivalence between serial and parallel models
    assert class_out_p = class_out
      report "Mismatch: Parallel classification output differs from serial output!"
      severity failure;

    report "==================================================";
    report "Top-Level System Verification Summary:";
    report "Speedup Factor: " & integer'image(serial_cycles / parallel_cycles) & "x faster";
    report "=== ALL TOP-LEVEL TESTS PASSED SUCCESSFULLY ===";
    report "==================================================";

    sim_finished <= true;
    wait;
  end process;

end architecture sim;
