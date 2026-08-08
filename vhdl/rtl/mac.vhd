library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Single-cycle multiply-accumulate step:
--   acc_out = acc_in + (a * b)   where a,b are Qm.n and product is full width
-- Clear with clear='1' (loads bias<<FRAC into accumulator when bias_valid).
entity mac is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    clear      : in  std_logic;
    enable     : in  std_logic;
    a          : in  data_t;
    b          : in  data_t;
    bias       : in  data_t;
    load_bias  : in  std_logic;
    acc_out    : out acc_t;
    result     : out data_t
  );
end entity mac;

architecture rtl of mac is
  signal acc : acc_t := (others => '0');
begin
  process (clk)
    variable prod : signed(2 * DATA_WIDTH - 1 downto 0);
    variable next_acc : acc_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      else
        next_acc := acc;
        if clear = '1' then
          if load_bias = '1' then
            next_acc := resize(shift_left(resize(bias, ACC_WIDTH), FRAC_BITS), ACC_WIDTH);
          else
            next_acc := (others => '0');
          end if;
        end if;
        if enable = '1' then
          prod := a * b;
          next_acc := next_acc + resize(prod, ACC_WIDTH);
        end if;
        acc <= next_acc;
      end if;
    end if;
  end process;

  acc_out <= acc;
  result  <= acc_to_data(acc);
end architecture rtl;
