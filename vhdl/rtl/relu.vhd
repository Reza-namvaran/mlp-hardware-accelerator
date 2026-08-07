library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_fixed.all;

entity relu is
  port (
    x : in  data_t;
    y : out data_t
  );
end entity relu;

architecture rtl of relu is
begin
  y <= fix_relu(x);
end architecture rtl;
