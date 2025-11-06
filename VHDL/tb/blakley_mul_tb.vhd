library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_blakley_mul is
end entity;

architecture sim of tb_blakley_mul is
    constant WIDTH : integer := 256;
    signal clk, rst, start, busy, done : std_logic := '0';
    signal ready_to_read : STD_LOGIC := '0';
    signal A, B, N, R : std_logic_vector(WIDTH-1 downto 0);
begin
    DUT: entity work.blakley_mul
        generic map (WIDTH => WIDTH)
        port map (
            clk     => clk, 
            rst     => rst, 
            start   => start,
            A       => A, 
            B       => B, 
            N       => N,
            busy    => busy, 
            done => done, 
            R_out   => R,
            R_read_done => ready_to_read
        );

    clk <= not clk after 1 ns;

    process
    begin
        rst <= '1'; wait for 25 ns;
        rst <= '0'; wait for 20 ns;

        A <= std_logic_vector(to_unsigned(10000, WIDTH));
        B <= std_logic_vector(to_unsigned(128000, WIDTH));
        N <= std_logic_vector(to_unsigned(65537, WIDTH));
        wait for 20 ns;

        start <= '1'; wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 100 ns;
        ready_to_read <= '1';
        wait for 100 ns;
        ready_to_read <= '0';
        report "Result: " & integer'image(to_integer(unsigned(R)));
        wait;
    end process;
end architecture;
