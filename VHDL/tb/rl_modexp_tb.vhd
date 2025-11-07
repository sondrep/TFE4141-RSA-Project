library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rl_modexp is
end entity;

architecture sim of tb_rl_modexp is
    constant WIDTH : integer := 256;
    signal clk, rst, start, busy, done : std_logic := '0';
    signal rdy_for_msg : STD_LOGIC := '0';
    signal msg_in, key_e, key_n, result : std_logic_vector(WIDTH-1 downto 0);
begin
    DUT: entity work.mod_exp
        generic map (WIDTH => WIDTH)
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            base            => msg_in,
            exponent        => key_e,
            key_n           => key_n,
            result          => result,
            done            => done,
            rdy_for_msg     => rdy_for_msg
        );

    clk <= not clk after 10 ns;

    process
    begin
        rst <= '1'; wait for 20 ns;
        rst <= '0'; wait for 20 ns;
        
        rdy_for_msg <= '1'; wait for 20 ns;
        msg_in <= std_logic_vector(to_unsigned(2, WIDTH));
        key_e <= std_logic_vector(to_unsigned(2, WIDTH));
        key_n <= std_logic_vector(to_unsigned(7, WIDTH));
        wait for 5 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;

        rst <= '1'; wait for 5 ns;
        rst <= '0'; wait for 5 ns;
        
        rdy_for_msg <= '1'; wait for 5 ns;
        msg_in <= std_logic_vector(to_unsigned(2, WIDTH));
        key_e <= std_logic_vector(to_unsigned(4, WIDTH));
        key_n <= std_logic_vector(to_unsigned(7, WIDTH));
        wait for 20 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;
        
        rst <= '1'; wait for 20 ns;
        rst <= '0'; wait for 20 ns;
        
        rdy_for_msg <= '1'; wait for 20 ns;
        msg_in <= std_logic_vector(to_unsigned(6969, WIDTH));
        key_e <= std_logic_vector(to_unsigned(7172, WIDTH));
        key_n <= std_logic_vector(to_unsigned(65537, WIDTH));
        wait for 5 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;


    end process;
end architecture;
