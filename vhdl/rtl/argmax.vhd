library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

-- Argmax over 10 Q8.8 logits (combinational).
entity argmax is
  port (
    v0, v1, v2, v3, v4, v5, v6, v7, v8, v9 : in  data_t;
    cls : out unsigned(3 downto 0)
  );
end entity argmax;

architecture rtl of argmax is
  type arr_t is array (0 to 9) of data_t;
begin
  process (v0, v1, v2, v3, v4, v5, v6, v7, v8, v9)
    variable vals : arr_t;
    variable best_i : integer;
    variable best_v : data_t;
  begin
    vals := (v0, v1, v2, v3, v4, v5, v6, v7, v8, v9);
    best_i := 0;
    best_v := vals(0);
    for i in 1 to 9 loop
      if vals(i) > best_v then
        best_v := vals(i);
        best_i := i;
      end if;
    end loop;
    cls <= to_unsigned(best_i, 4);
  end process;
end architecture rtl;
