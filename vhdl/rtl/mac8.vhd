library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Dynamic Precision MAC Unit (Bonus Feature)
-- Uses reduced bit-width weight input (default WEIGHT_WIDTH = 8) while
-- keeping full 16-bit Q8.8 activation input and 32-bit accumulator width.
entity mac8 is
  generic (
    WEIGHT_WIDTH : integer := 8
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    clear     : in  std_logic;
    enable    : in  std_logic;
    a         : in  data_t;                             -- Q8.8 activation (16-bit)
    w         : in  signed(WEIGHT_WIDTH - 1 downto 0);  -- narrow weight (8-bit Q0.8)
    bias      : in  data_t;                             -- Q8.8 bias (16-bit)
    load_bias : in  std_logic;
    acc_out   : out acc_t;                             -- Accumulator output (32-bit)
    result    : out data_t                              -- Saturation Q8.8 result (16-bit)
  );
end entity mac8;

architecture rtl of mac8 is
  signal acc : acc_t := (others => '0');
begin

  process (clk)
    variable prod     : signed(DATA_WIDTH + WEIGHT_WIDTH - 1 downto 0);
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
          prod := a * w;
          next_acc := next_acc + resize(prod, ACC_WIDTH);
        end if;
        acc <= next_acc;
      end if;
    end if;
  end process;

  acc_out <= acc;
  result  <= acc_to_data(acc);

end architecture rtl;
