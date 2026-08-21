library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;
use std.textio.all;

-- Mandatory course testbench: reads the 10 golden MNIST test images and
-- compares hardware classification against Python's Q8.8 golden output
-- (test_vectors/expected_classes.txt). Always instantiates the serial
-- baseline (N_PARALLEL_HIDDEN=1, N_PARALLEL_OUTPUT=1) explicitly, regardless
-- of mlp_top's own default generic values, so this stays the fixed reference
-- point. See tb_mlp_top_parallel.vhd for the same golden-vector check against
-- the full-width parallel-MAC configuration, and tb_serial_vs_parallel.vhd for
-- a self-consistency/speedup comparison between the two.
entity tb_mlp_top is
end entity tb_mlp_top;

architecture sim of tb_mlp_top is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal start, load_en, busy, done : std_logic := '0';
  signal load_data : data_t := (others => '0');
  signal class_out : unsigned(3 downto 0);
  signal finished : boolean := false;

  constant CLK_PERIOD : time := 10 ns;
begin
  clk <= not clk after CLK_PERIOD / 2 when not finished else '0';

  uut : entity work.mlp_top
    generic map (
      N_PARALLEL_HIDDEN => 1,
      N_PARALLEL_OUTPUT => 1
    )
    port map (
      clk => clk,
      rst => rst,
      start => start,
      load_en => load_en,
      load_data => load_data,
      busy => busy,
      done => done,
      class_out => class_out
    );

  process
    file f_in : text;
    file f_exp : text;
    variable L : line;
    variable hex : string(1 to 4);
    variable good : boolean;
    variable pixel : integer;
    variable expected : integer;
    variable n_pass : integer := 0;
    variable n_fail : integer := 0;
    variable exp_cls : integer;
    variable h : character;
    variable val : integer;
    variable digit : integer;

    -- Repo-relative path: run from results/ghdl_work via scripts/sim.sh
    constant INPUT_FILE : string := "../../test_vectors/inputs_all.mem";
    constant EXP_FILE   : string := "../../test_vectors/expected_classes.txt";
    constant NUM_FILE   : string := "../../test_vectors/num_samples.txt";
    variable n_samples : integer := 10;
  begin
    -- Read number of samples
    file_open(f_exp, NUM_FILE, read_mode);
    readline(f_exp, L);
    read(L, n_samples);
    file_close(f_exp);

    file_open(f_in, INPUT_FILE, read_mode);
    file_open(f_exp, EXP_FILE, read_mode);

    rst <= '1';
    wait for CLK_PERIOD * 2;
    rst <= '0';
    wait for CLK_PERIOD;

    for sample in 0 to n_samples - 1 loop
      readline(f_exp, L);
      read(L, expected);

      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      for i in 0 to INPUT_SIZE - 1 loop
        readline(f_in, L);
        -- parse 4 hex chars
        read(L, hex);
        val := 0;
        for c in 1 to 4 loop
          h := hex(c);
          if h >= '0' and h <= '9' then
            digit := character'pos(h) - character'pos('0');
          elsif h >= 'a' and h <= 'f' then
            digit := 10 + character'pos(h) - character'pos('a');
          elsif h >= 'A' and h <= 'F' then
            digit := 10 + character'pos(h) - character'pos('A');
          else
            digit := 0;
          end if;
          val := val * 16 + digit;
        end loop;
        if val >= 32768 then
          pixel := val - 65536;
        else
          pixel := val;
        end if;
        load_data <= to_signed(pixel, 16);
        load_en <= '1';
        wait until rising_edge(clk);
      end loop;
      load_en <= '0';

      wait until done = '1' for 50 ms;
      assert done = '1' report "Timeout waiting for done" severity failure;

      exp_cls := expected;
      if to_integer(class_out) = exp_cls then
        n_pass := n_pass + 1;
        report "sample " & integer'image(sample) & " PASS class=" & integer'image(exp_cls);
      else
        n_fail := n_fail + 1;
        report "sample " & integer'image(sample) & " FAIL got=" &
          integer'image(to_integer(class_out)) & " expected=" & integer'image(exp_cls)
          severity error;
      end if;

      wait until rising_edge(clk);
      wait until rising_edge(clk);
    end loop;

    file_close(f_in);
    file_close(f_exp);

    report "tb_mlp_top finished: pass=" & integer'image(n_pass) &
      " fail=" & integer'image(n_fail);
    assert n_fail = 0 report "Some samples failed" severity failure;

    finished <= true;
    wait;
  end process;
end architecture sim;
