library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Pipelined Multiply-Accumulate (MAC) Unit (2-Stage Pipeline)
-- Stage 1: Register inputs, control signals, and compute 32-bit signed multiplication product.
-- Stage 2: Accumulate product into 32-bit register and apply fixed-point Q8.8 truncation/saturation.
entity mac_pipelined is
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
end entity mac_pipelined;

architecture rtl of mac_pipelined is
  -- Pipeline Stage 1 Registers
  signal prod_reg : signed(2 * DATA_WIDTH - 1 downto 0) := (others => '0');
  signal en_reg   : std_logic := '0';
  signal clr_reg  : std_logic := '0';
  signal bias_reg : data_t := (others => '0');
  signal ldb_reg  : std_logic := '0';

  -- Pipeline Stage 2 Register (Accumulator)
  signal acc      : acc_t := (others => '0');
begin

  -- Stage 1 Process: Register inputs, compute product, and register control signals
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        prod_reg <= (others => '0');
        en_reg   <= '0';
        clr_reg  <= '0';
        bias_reg <= (others => '0');
        ldb_reg  <= '0';
      else
        prod_reg <= a * b;
        en_reg   <= enable;
        clr_reg  <= clear;
        bias_reg <= bias;
        ldb_reg  <= load_bias;
      end if;
    end if;
  end process;

  -- Stage 2 Process: 32-bit accumulation and status handling
  process (clk)
    variable next_acc : acc_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      else
        next_acc := acc;
        if clr_reg = '1' then
          if ldb_reg = '1' then
            next_acc := resize(shift_left(resize(bias_reg, ACC_WIDTH), FRAC_BITS), ACC_WIDTH);
          else
            next_acc := (others => '0');
          end if;
        elsif en_reg = '1' then
          next_acc := acc + resize(prod_reg, ACC_WIDTH);
        end if;
        acc <= next_acc;
      end if;
    end if;
  end process;

  -- Output assignments
  acc_out <= acc;
  result  <= acc_to_data(acc);

end architecture rtl;
