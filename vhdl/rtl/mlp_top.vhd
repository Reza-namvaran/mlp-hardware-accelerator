library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;

-- End-to-end MLP inference accelerator.
-- N_PARALLEL_HIDDEN / N_PARALLEL_OUTPUT (parallel-MAC bonus): how many neurons
-- of each layer compute simultaneously. Default 1/1 reproduces the original
-- fully serial baseline exactly; e.g. 16/10 runs every neuron of both layers
-- at once (one neuron/MAC unit per output, no group looping at all).
entity mlp_top is
  generic (
    N_PARALLEL_HIDDEN : integer := 1;
    N_PARALLEL_OUTPUT : integer := 1
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;
    -- Stream 784 Q8.8 pixels while start sequence is active (load_en)
    load_en   : in  std_logic;
    load_data : in  data_t;
    busy      : out std_logic;
    done      : out std_logic;
    class_out : out unsigned(3 downto 0)
  );
end entity mlp_top;

architecture rtl of mlp_top is
  -- Input / hidden / output buffers
  type in_mem_t  is array (0 to INPUT_SIZE - 1) of data_t;
  type hid_mem_t is array (0 to HIDDEN_SIZE - 1) of data_t;
  type out_mem_t is array (0 to OUTPUT_SIZE - 1) of data_t;

  signal in_mem  : in_mem_t := (others => (others => '0'));
  signal hid_mem : hid_mem_t := (others => (others => '0'));
  signal out_mem : out_mem_t := (others => (others => '0'));

  signal load_cnt : integer range 0 to INPUT_SIZE := 0;

  signal w1_addr : addr_array_t;
  signal w1_data : data_array_t;
  signal b1_addr : addr_array_t;
  signal b1_data : data_array_t;
  signal w2_addr : addr_array_t;
  signal w2_data : data_array_t;
  signal b2_addr : addr_array_t;
  signal b2_data : data_array_t;

  signal h_start, h_done, h_busy : std_logic;
  signal h_x_idx : integer range 0 to INPUT_SIZE;
  signal h_x_data : data_t;
  signal h_out_we : we_array_t;
  signal h_out_addr : addr_array_t;
  signal h_out_data : data_array_t;

  signal o_start, o_done, o_busy : std_logic;
  signal o_x_idx : integer range 0 to HIDDEN_SIZE;
  signal o_x_data : data_t;
  signal o_out_we : we_array_t;
  signal o_out_addr : addr_array_t;
  signal o_out_data : data_array_t;

  signal ctrl_h_start, ctrl_o_start : std_logic;
  signal ctrl_load_done : std_logic;
  signal argmax_cls : unsigned(3 downto 0);

  type top_state_t is (IDLE, LOAD, RUN_H, RUN_O, FINISH);
  signal state : top_state_t := IDLE;
  signal busy_r : std_logic := '0';
  signal done_r : std_logic := '0';
  signal class_r : unsigned(3 downto 0) := (others => '0');
begin
  busy <= busy_r;
  done <= done_r;
  class_out <= class_r;

  u_rom : entity work.rom_weights
    port map (
      clk     => clk,
      w1_addr => w1_addr,
      w1_data => w1_data,
      b1_addr => b1_addr,
      b1_data => b1_data,
      w2_addr => w2_addr,
      w2_data => w2_data,
      b2_addr => b2_addr,
      b2_data => b2_data
    );

  h_x_data <= in_mem(h_x_idx) when h_x_idx < INPUT_SIZE else (others => '0');
  o_x_data <= hid_mem(o_x_idx) when o_x_idx < HIDDEN_SIZE else (others => '0');

  u_hidden : entity work.dense_layer
    generic map (
      N_INPUTS   => INPUT_SIZE,
      N_NEURONS  => HIDDEN_SIZE,
      USE_RELU   => true,
      N_PARALLEL => N_PARALLEL_HIDDEN
    )
    port map (
      clk      => clk,
      rst      => rst,
      start    => h_start,
      w_addr   => w1_addr,
      w_data   => w1_data,
      b_addr   => b1_addr,
      b_data   => b1_data,
      x_idx    => h_x_idx,
      x_data   => h_x_data,
      out_we   => h_out_we,
      out_addr => h_out_addr,
      out_data => h_out_data,
      busy     => h_busy,
      done     => h_done
    );

  u_output : entity work.dense_layer
    generic map (
      N_INPUTS   => HIDDEN_SIZE,
      N_NEURONS  => OUTPUT_SIZE,
      USE_RELU   => false,
      N_PARALLEL => N_PARALLEL_OUTPUT
    )
    port map (
      clk      => clk,
      rst      => rst,
      start    => o_start,
      w_addr   => w2_addr,
      w_data   => w2_data,
      b_addr   => b2_addr,
      b_data   => b2_data,
      x_idx    => o_x_idx,
      x_data   => o_x_data,
      out_we   => o_out_we,
      out_addr => o_out_addr,
      out_data => o_out_data,
      busy     => o_busy,
      done     => o_done
    );

  u_argmax : entity work.argmax
    port map (
      v0 => out_mem(0), v1 => out_mem(1), v2 => out_mem(2), v3 => out_mem(3),
      v4 => out_mem(4), v5 => out_mem(5), v6 => out_mem(6), v7 => out_mem(7),
      v8 => out_mem(8), v9 => out_mem(9),
      cls => argmax_cls
    );

  -- Simplified integrated controller (also mirrored in controller.vhd for docs/TB)
  h_start <= ctrl_h_start;
  o_start <= ctrl_o_start;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        load_cnt <= 0;
        busy_r <= '0';
        done_r <= '0';
        ctrl_h_start <= '0';
        ctrl_o_start <= '0';
        class_r <= (others => '0');
        in_mem <= (others => (others => '0'));
        hid_mem <= (others => (others => '0'));
        out_mem <= (others => (others => '0'));
      else
        ctrl_h_start <= '0';
        ctrl_o_start <= '0';
        done_r <= '0';

        -- Up to N_PARALLEL_HIDDEN / N_PARALLEL_OUTPUT lanes finish a group in
        -- the same cycle (parallel-MAC bonus); write every lane that pulsed.
        for lane in 0 to MAX_PARALLEL - 1 loop
          if h_out_we(lane) = '1' then
            hid_mem(h_out_addr(lane)) <= h_out_data(lane);
          end if;
          if o_out_we(lane) = '1' then
            out_mem(o_out_addr(lane)) <= o_out_data(lane);
          end if;
        end loop;

        case state is
          when IDLE =>
            busy_r <= '0';
            if start = '1' then
              load_cnt <= 0;
              busy_r <= '1';
              state <= LOAD;
            end if;

          when LOAD =>
            if load_en = '1' then
              in_mem(load_cnt) <= load_data;
              if load_cnt = INPUT_SIZE - 1 then
                ctrl_h_start <= '1';
                state <= RUN_H;
              else
                load_cnt <= load_cnt + 1;
              end if;
            end if;

          when RUN_H =>
            if h_done = '1' then
              ctrl_o_start <= '1';
              state <= RUN_O;
            end if;

          when RUN_O =>
            if o_done = '1' then
              state <= FINISH;
            end if;

          when FINISH =>
            class_r <= argmax_cls;
            done_r <= '1';
            busy_r <= '0';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
