library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Approximate MAC Architecture (Bonus Feature)
-- Applies LSB Truncation / Masking to input operands prior to multiplication.
-- Clears lower MASK_BITS bits to reduce logic switching activity and power consumption.
entity mac_approx is
  generic (
    -- MASK_BITS=4 costs ~25 accuracy points (93.8% -> 68.7%, measured in
    -- python/experiments/mask_bits_sweep.py) -- masking both multiply
    -- operands on every one of 784+16 MACs/inference compounds fast.
    -- MASK_BITS=2 is the usable operating point (93.8% -> 92.75%).
    MASK_BITS : integer := 2
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    clear     : in  std_logic;
    enable    : in  std_logic;
    a         : in  data_t;     -- Q8.8 activation (16-bit)
    b         : in  data_t;     -- Q8.8 weight (16-bit)
    bias      : in  data_t;     -- Q8.8 bias (16-bit)
    load_bias : in  std_logic;
    acc_out   : out acc_t;     -- Accumulator output (32-bit)
    result    : out data_t      -- Saturation Q8.8 result (16-bit)
  );
end entity mac_approx;

architecture rtl of mac_approx is
  signal acc : acc_t := (others => '0');
begin

  process (clk)
    variable mask     : signed(DATA_WIDTH - 1 downto 0);
    variable a_app    : data_t;
    variable b_app    : data_t;
    variable prod     : signed(2 * DATA_WIDTH - 1 downto 0);
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
          -- Generate bitmask to zero out lowest MASK_BITS
          mask := (others => '1');
          mask(MASK_BITS - 1 downto 0) := (others => '0');

          a_app := a and mask;
          b_app := b and mask;

          prod := a_app * b_app;
          next_acc := next_acc + prod;
        end if;
        acc <= next_acc;
      end if;
    end if;
  end process;

  acc_out <= acc;
  result  <= acc_to_data(acc);

end architecture rtl;
