library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blakley_mul is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        A           : in  std_logic_vector(WIDTH-1 downto 0);
        B           : in  std_logic_vector(WIDTH-1 downto 0);
        N           : in  std_logic_vector(WIDTH-1 downto 0);
        R_read_done : in  std_logic;  -- consumer ack: clear done when '1'

        busy        : out std_logic;
        done        : out std_logic;  -- high when result is valid, stays high until R_read_done
        R_out       : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity;

architecture rtl of blakley_mul is
    signal a_reg, b_reg, n_reg : unsigned(WIDTH-1 downto 0);
    signal r_reg               : unsigned(WIDTH-1 downto 0);
    signal running             : std_logic := '0';
    signal result_valid        : std_logic := '0';
begin
    process(clk, rst)
        variable tmp    : unsigned(WIDTH downto 0);
        variable n_ext  : unsigned(WIDTH downto 0);
        variable r_next : unsigned(WIDTH-1 downto 0);
        variable a_next : unsigned(WIDTH-1 downto 0);
        variable b_next : unsigned(WIDTH-1 downto 0);
    begin
        if rst = '1' then
            a_reg        <= (others => '0');
            b_reg        <= (others => '0');
            n_reg        <= (others => '0');
            r_reg        <= (others => '0');
            running      <= '0';
            result_valid <= '0';

        elsif rising_edge(clk) then
            -- Clear result_valid only when consumer acks
            if result_valid = '1' and R_read_done = '1' then
                result_valid <= '0';
            end if;

            -- Start new operation only if idle AND previous result consumed
            if start = '1' and running = '0' and result_valid = '0' then
                a_reg   <= unsigned(A);
                b_reg   <= unsigned(B);
                n_reg   <= unsigned(N);
                r_reg   <= (others => '0');  -- r = 0
                running <= '1';

            elsif running = '1' then
                -- LSB-first add-and-shift:
                -- if b(0)=1: r = (r + a) % n
                -- a = (2a) % n
                -- b = b >> 1
                n_ext := resize(n_reg, WIDTH+1);

                -- defaults
                r_next := r_reg;
                a_next := a_reg;
                b_next := shift_right(b_reg, 1);

                -- conditional add: r = (r + a) % n
                if b_reg(0) = '1' then
                    tmp := resize(r_reg, WIDTH+1) + resize(a_reg, WIDTH+1);
                    if tmp >= n_ext then
                        tmp := tmp - n_ext;
                    end if;
                    r_next := tmp(WIDTH-1 downto 0);
                end if;

                -- a = (2a) % n
                tmp := shift_left(resize(a_reg, WIDTH+1), 1);
                if tmp >= n_ext then
                    tmp := tmp - n_ext;
                end if;
                a_next := tmp(WIDTH-1 downto 0);

                -- commit
                r_reg <= r_next;
                a_reg <= a_next;
                b_reg <= b_next;

                -- finish when all bits of b consumed
                if b_next = (b_next'range => '0') then
                    running      <= '0';
                    result_valid <= '1';
                end if;
            end if;
        end if;
    end process;

    busy  <= running;
    done  <= result_valid;
    R_out <= std_logic_vector(r_reg);
end architecture;