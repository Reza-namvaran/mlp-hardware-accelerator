library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;
use work.pkg_weights.all;

-- Top-level MLP accelerator FSM / controller glue.
-- States: IDLE → LOAD_INPUT → HIDDEN → OUTPUT → ARGMAX → DONE
entity controller is
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    start        : in  std_logic;
    -- Input load: host writes pixel when load_en; addr auto-increments
    load_en      : in  std_logic;
    load_data    : in  data_t;
    load_done    : out std_logic;  -- high when 784 pixels accepted
    -- Layer kicks
    hidden_start : out std_logic;
    hidden_done  : in  std_logic;
    out_start    : out std_logic;
    out_done     : in  std_logic;
    -- Result
    class_in     : in  unsigned(3 downto 0);
    busy         : out std_logic;
    done         : out std_logic;
    class_out    : out unsigned(3 downto 0)
  );
end entity controller;

architecture rtl of controller is
  type state_t is (IDLE, LOAD_INPUT, HIDDEN, OUTPUT, ARGMAX_ST, DONE_ST);
  signal state : state_t := IDLE;
  signal load_cnt : integer range 0 to INPUT_SIZE := 0;
  signal class_r  : unsigned(3 downto 0) := (others => '0');
  signal busy_r   : std_logic := '0';
  signal done_r   : std_logic := '0';
  signal load_done_r : std_logic := '0';
  signal h_start_r : std_logic := '0';
  signal o_start_r : std_logic := '0';
begin
  busy      <= busy_r;
  done      <= done_r;
  class_out <= class_r;
  load_done <= load_done_r;
  hidden_start <= h_start_r;
  out_start    <= o_start_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        load_cnt <= 0;
        busy_r <= '0';
        done_r <= '0';
        load_done_r <= '0';
        h_start_r <= '0';
        o_start_r <= '0';
        class_r <= (others => '0');
      else
        h_start_r <= '0';
        o_start_r <= '0';
        done_r <= '0';

        case state is
          when IDLE =>
            busy_r <= '0';
            load_done_r <= '0';
            if start = '1' then
              load_cnt <= 0;
              busy_r <= '1';
              state <= LOAD_INPUT;
            end if;

          when LOAD_INPUT =>
            if load_en = '1' then
              if load_cnt = INPUT_SIZE - 1 then
                load_done_r <= '1';
                h_start_r <= '1';
                state <= HIDDEN;
              else
                load_cnt <= load_cnt + 1;
              end if;
            end if;

          when HIDDEN =>
            if hidden_done = '1' then
              o_start_r <= '1';
              state <= OUTPUT;
            end if;

          when OUTPUT =>
            if out_done = '1' then
              state <= ARGMAX_ST;
            end if;

          when ARGMAX_ST =>
            class_r <= class_in;
            state <= DONE_ST;

          when DONE_ST =>
            done_r <= '1';
            busy_r <= '0';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
