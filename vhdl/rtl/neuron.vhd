library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Serial neuron: CLEAR → (MAC_HOLD → ADVANCE)×N → SETTLE → DONE
-- Ensures weight/input for index i are stable when MAC samples enable.
entity neuron is
  generic (
    N_INPUTS : integer := 784;
    USE_RELU : boolean := true
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;
    bias    : in  data_t;
    w_data  : in  data_t;
    x_data  : in  data_t;
    idx     : out integer range 0 to N_INPUTS;
    busy    : out std_logic;
    done    : out std_logic;
    y       : out data_t
  );
end entity neuron;

architecture rtl of neuron is
  type state_t is (IDLE, CLEAR_ST, MAC_HOLD, ADVANCE, SETTLE, DONE_ST);
  signal state : state_t := IDLE;
  signal i     : integer range 0 to N_INPUTS := 0;
  signal mac_clear     : std_logic := '0';
  signal mac_enable    : std_logic := '0';
  signal mac_load_bias : std_logic := '0';
  signal mac_result    : data_t;
  signal mac_acc       : acc_t;
  signal y_r    : data_t := (others => '0');
  signal done_r : std_logic := '0';
  signal busy_r : std_logic := '0';
begin
  u_mac : entity work.mac
    port map (
      clk       => clk,
      rst       => rst,
      clear     => mac_clear,
      enable    => mac_enable,
      a         => w_data,
      b         => x_data,
      bias      => bias,
      load_bias => mac_load_bias,
      acc_out   => mac_acc,
      result    => mac_result
    );

  idx  <= i;
  y    <= y_r;
  done <= done_r;
  busy <= busy_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        i <= 0;
        mac_clear <= '0';
        mac_enable <= '0';
        mac_load_bias <= '0';
        done_r <= '0';
        busy_r <= '0';
        y_r <= (others => '0');
      else
        mac_clear <= '0';
        mac_enable <= '0';
        mac_load_bias <= '0';
        done_r <= '0';

        case state is
          when IDLE =>
            busy_r <= '0';
            if start = '1' then
              busy_r <= '1';
              i <= 0;
              state <= CLEAR_ST;
            end if;

          when CLEAR_ST =>
            mac_clear <= '1';
            mac_load_bias <= '1';
            state <= MAC_HOLD;

          when MAC_HOLD =>
            -- idx=i stable; schedule enable so next edge accumulates w[i]*x[i]
            mac_enable <= '1';
            state <= ADVANCE;

          when ADVANCE =>
            -- This edge: MAC consumes previous enable with current idx data
            if i = N_INPUTS - 1 then
              state <= SETTLE;
            else
              i <= i + 1;
              state <= MAC_HOLD;
            end if;

          when SETTLE =>
            state <= DONE_ST;

          when DONE_ST =>
            if USE_RELU then
              y_r <= fix_relu(mac_result);
            else
              y_r <= mac_result;
            end if;
            done_r <= '1';
            busy_r <= '0';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
