LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE pkg_fixed IS
    CONSTANT DATA_WIDTH : INTEGER := 16;
    CONSTANT FRAC_BITS : INTEGER := 8;
    CONSTANT ACC_WIDTH : INTEGER := 32;

    SUBTYPE data_t IS signed(DATA_WIDTH - 1 DOWNTO 0);
    SUBTYPE acc_t IS signed(ACC_WIDTH - 1 DOWNTO 0);

    FUNCTION fix_mul(a, b : data_t) RETURN data_t;
    FUNCTION acc_to_data(a : acc_t) RETURN data_t;
    FUNCTION fix_relu(x : data_t) RETURN data_t;
END PACKAGE pkg_fixed;

PACKAGE BODY pkg_fixed IS
    FUNCTION fix_mul(a, b : data_t) RETURN data_t IS
        VARIABLE prod : signed(2 * DATA_WIDTH - 1 DOWNTO 0);
    BEGIN
        prod := a * b;
        RETURN resize(shift_right(prod, FRAC_BITS), DATA_WIDTH);
    END FUNCTION;

    FUNCTION acc_to_data(a : acc_t) RETURN data_t IS
        VARIABLE shifted : signed(ACC_WIDTH - 1 DOWNTO 0);
        CONSTANT MAX_V : INTEGER := (2 ** (DATA_WIDTH - 1)) - 1;
        CONSTANT MIN_V : INTEGER := - (2 ** (DATA_WIDTH - 1));
    BEGIN
        shifted := shift_right(a, FRAC_BITS);
        IF shifted > to_signed(MAX_V, ACC_WIDTH) THEN
            RETURN to_signed(MAX_V, DATA_WIDTH);
        ELSIF shifted < to_signed(MIN_V, ACC_WIDTH) THEN
            RETURN to_signed(MIN_V, DATA_WIDTH);
        ELSE
            RETURN resize(shifted, DATA_WIDTH);
        END IF;
    END FUNCTION;

    FUNCTION fix_relu(x : data_t) RETURN data_t IS
    BEGIN
        IF x < 0 THEN
            RETURN (OTHERS => '0');
        ELSE
            RETURN x;
        END IF;
    END FUNCTION;
END PACKAGE BODY pkg_fixed;