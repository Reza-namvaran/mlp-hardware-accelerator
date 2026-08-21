library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Compute one dense layer: N_NEURONS split into groups of N_PARALLEL neurons.
-- Each group runs N_PARALLEL independent neuron/MAC instances simultaneously
-- (parallel-MAC bonus); groups themselves are still processed one after another.
-- N_PARALLEL = 1 reproduces the original fully serial one-neuron-at-a-time walk
-- exactly (same states, same cycle count) so the existing testbench keeps passing.
--
-- Lockstep note: every active lane's neuron shares the same `start` pulse and
-- the same generics (N_INPUTS/USE_RELU), and neuron.vhd's FSM has no
-- data-dependent branches, so all active lanes finish on the identical cycle.
-- That lets the group FSM below watch a single lane (lane 0) for `done`.
entity dense_layer is
  generic (
    N_INPUTS   : integer := 784;
    N_NEURONS  : integer := 16;
    USE_RELU   : boolean := true;
    N_PARALLEL : integer := 1
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    start    : in  std_logic;
    w_addr   : out addr_array_t;
    w_data   : in  data_array_t;
    b_addr   : out addr_array_t;
    b_data   : in  data_array_t;
    x_idx    : out integer range 0 to N_INPUTS;
    x_data   : in  data_t;
    out_we   : out we_array_t;
    out_addr : out addr_array_t;
    out_data : out data_array_t;
    busy     : out std_logic;
    done     : out std_logic
  );
end entity dense_layer;

architecture rtl of dense_layer is
  constant N_GROUPS : integer := (N_NEURONS + N_PARALLEL - 1) / N_PARALLEL;

  -- Bounded by N_NEURONS (always >= N_GROUPS for any N_PARALLEL >= 1), not by
  -- N_GROUPS itself: N_GROUPS can degenerate to 1 (e.g. N_NEURONS=N_PARALLEL=16),
  -- giving group_idx a size-1 declared range. Some synthesis tools (Vivado
  -- 2019.1 included) check "group_idx <= group_idx + 1" against group_idx's own
  -- declared range without proving the guarding if/else makes the increment
  -- unreachable at that bound, and reject it as a false "out of range" -- even
  -- though GHDL simulation never exercises that unreachable path. A wider,
  -- fixed range sidesteps the check without changing behavior.
  signal group_idx  : integer range 0 to N_NEURONS := 0;
  signal neur_start : std_logic := '0';
  signal neur_idx   : integer range 0 to N_INPUTS := 0;
  signal neur_done  : std_logic;

  signal lane_y    : data_array_t;
  signal lane_idx  : addr_array_t;
  signal lane_done : we_array_t;

  signal busy_r   : std_logic := '0';
  signal done_r   : std_logic := '0';
  signal we_pulse : std_logic := '0';

  type st_t is (IDLE, FIRE, WAIT_N, NEXT_N, FINISH);
  signal state : st_t := IDLE;
begin
  neur_idx  <= lane_idx(0);
  neur_done <= lane_done(0);
  x_idx     <= neur_idx;
  busy      <= busy_r;
  done      <= done_r;

  gen_active_lanes : for lane in 0 to N_PARALLEL - 1 generate
  begin
    u_neuron : entity work.neuron
      generic map (
        N_INPUTS => N_INPUTS,
        USE_RELU => USE_RELU
      )
      port map (
        clk    => clk,
        rst    => rst,
        start  => neur_start,
        bias   => b_data(lane),
        w_data => w_data(lane),
        x_data => x_data,
        idx    => lane_idx(lane),
        busy   => open,
        done   => lane_done(lane),
        y      => lane_y(lane)
      );

    w_addr(lane) <= (group_idx * N_PARALLEL + lane) * N_INPUTS + neur_idx
                       when (group_idx * N_PARALLEL + lane) < N_NEURONS else 0;
    b_addr(lane) <= (group_idx * N_PARALLEL + lane)
                       when (group_idx * N_PARALLEL + lane) < N_NEURONS else 0;
    out_addr(lane) <= group_idx * N_PARALLEL + lane;
    out_data(lane) <= lane_y(lane);
    out_we(lane)   <= we_pulse when (group_idx * N_PARALLEL + lane) < N_NEURONS else '0';
  end generate gen_active_lanes;

  gen_idle_lanes : for lane in N_PARALLEL to MAX_PARALLEL - 1 generate
  begin
    w_addr(lane)   <= 0;
    b_addr(lane)   <= 0;
    out_addr(lane) <= 0;
    out_data(lane) <= (others => '0');
    out_we(lane)   <= '0';
  end generate gen_idle_lanes;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        group_idx <= 0;
        neur_start <= '0';
        busy_r <= '0';
        done_r <= '0';
        we_pulse <= '0';
      else
        neur_start <= '0';
        done_r <= '0';
        we_pulse <= '0';

        case state is
          when IDLE =>
            busy_r <= '0';
            if start = '1' then
              group_idx <= 0;
              busy_r <= '1';
              state <= FIRE;
            end if;

          when FIRE =>
            neur_start <= '1';
            state <= WAIT_N;

          when WAIT_N =>
            if neur_done = '1' then
              we_pulse <= '1';
              state <= NEXT_N;
            end if;

          when NEXT_N =>
            if group_idx = N_GROUPS - 1 then
              state <= FINISH;
            else
              group_idx <= group_idx + 1;
              state <= FIRE;
            end if;

          when FINISH =>
            done_r <= '1';
            busy_r <= '0';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
