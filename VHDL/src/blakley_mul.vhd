-- blakley_mul.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blakley_mul is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        A      : in  std_logic_vector(WIDTH-1 downto 0);
        B      : in  std_logic_vector(WIDTH-1 downto 0);
        N      : in  std_logic_vector(WIDTH-1 downto 0);
        busy   : out std_logic;
        done   : out std_logic;
        R_out  : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity;

architecture rtl of blakley_mul is
    signal a_reg, b_reg, n_reg : unsigned(WIDTH-1 downto 0);
    signal r_reg               : unsigned(WIDTH-1 downto 0);
    signal bit_index           : integer range 0 to WIDTH;
    signal running             : std_logic := '0';
begin
    process(clk, rst)
        variable tmp : unsigned(WIDTH downto 0);
    begin
        if rst = '1' then
            a_reg     <= (others => '0');
            b_reg     <= (others => '0');
            n_reg     <= (others => '0');
            r_reg     <= (others => '0');
            bit_index <= 0;
            running   <= '0';
            busy      <= '0';
            done      <= '0';
        elsif rising_edge(clk) then
            done <= '0';

            -- Start signal initializes multiplication
            if start = '1' and running = '0' then
                a_reg     <= unsigned(A);
                b_reg     <= unsigned(B);
                n_reg     <= unsigned(N);
                r_reg     <= (others => '0');
                bit_index <= WIDTH - 1;
                running   <= '1';
                busy      <= '1';

            elsif running = '1' then
                -- 1. Shift left: r = (r << 1) % n
                tmp := shift_left(r_reg, 1);
                if tmp >= resize(n_reg, WIDTH+1) then
                    tmp := tmp - resize(n_reg, WIDTH+1);
                end if;
                r_reg <= tmp(WIDTH-1 downto 0);

                -- 2. If current bit of b is 1: r = (r + a) % n
                if b_reg(bit_index) = '1' then
                    tmp := resize(r_reg, WIDTH+1) + resize(a_reg, WIDTH+1);
                    if tmp >= resize(n_reg, WIDTH+1) then
                        tmp := tmp - resize(n_reg, WIDTH+1);
                    end if;
                    r_reg <= tmp(WIDTH-1 downto 0);
                end if;

                -- 3. Decrement bit index
                if bit_index = 0 then
                    running <= '0';
                    busy    <= '0';
                    done    <= '1';
                else
                    bit_index <= bit_index - 1;
                end if;
            end if;
        end if;
    end process;

    R_out <= std_logic_vector(r_reg);
end architecture;
