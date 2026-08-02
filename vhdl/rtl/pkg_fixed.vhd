LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- Fixed-point package for Qm.n arithmetic (default Q8.8).
-- Generics are expressed as package constants so all RTL shares one format.
PACKAGE pkg_fixed IS
    CONSTANT DATA_WIDTH : INTEGER := 16;
    CONSTANT FRAC_BITS : INTEGER := 8;
    CONSTANT ACC_WIDTH : INTEGER := 32;

    SUBTYPE data_t IS signed(DATA_WIDTH - 1 DOWNTO 0);
    SUBTYPE acc_t IS signed(ACC_WIDTH - 1 DOWNTO 0);

    -- Widest neuron fan-out used by the parallel-MAC bonus (dense_layer N_PARALLEL,
    -- rom_weights lane count). Sized to the largest layer (hidden = 16 neurons);
    -- narrower layers (e.g. output = 10) just leave the top lanes unused.
    CONSTANT MAX_PARALLEL : INTEGER := 16;

    TYPE data_array_t IS ARRAY (0 TO MAX_PARALLEL - 1) OF data_t;

    -- Plain "integer" defaults to integer'low at elaboration, which would index
    -- out of bounds on the very first delta cycle before any driver settles.
    -- Range-constrain so the default init is 0 (always a valid ROM address).
    SUBTYPE rom_addr_t IS INTEGER RANGE 0 TO 100000;
    TYPE addr_array_t IS ARRAY (0 TO MAX_PARALLEL - 1) OF rom_addr_t;
    TYPE we_array_t IS ARRAY (0 TO MAX_PARALLEL - 1) OF STD_LOGIC;

    -- Multiply two Qm.n values → product in Q(2m).(2n), then shift back to Qm.n
    -- with truncation toward zero (arithmetic shift right by FRAC_BITS).
    FUNCTION fix_mul(a, b : data_t) RETURN data_t;

    -- Saturating cast from accumulator to data_t (truncate FRAC, then saturate).
    FUNCTION acc_to_data(a : acc_t) RETURN data_t;

    -- ReLU: max(0, x)
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