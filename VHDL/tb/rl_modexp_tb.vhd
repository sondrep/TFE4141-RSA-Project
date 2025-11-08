library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rl_modexp is
end entity;

architecture sim of tb_rl_modexp is
    constant C_block_size : integer := 256;
    signal clk, rst, start, busy, done : std_logic := '0';
    signal rdy_for_msg : STD_LOGIC := '0';
    signal msg_in, key_e, key_n, result : std_logic_vector(C_block_size-1 downto 0);
begin
    DUT: entity work.exponentiation
        generic map (C_block_size => C_block_size)
        port map (
            clk             => clk,
            reset_n         => rst,
            valid_in        => start,
            message         => msg_in,
            key             => key_e,
            modulus         => key_n,
            result          => result,
            valid_out       => done,
            ready_out       => rdy_for_msg
        );

    clk <= not clk after 10 ns;

    process
    begin
        rst <= '0'; wait for 20 ns;
        rst <= '1'; wait for 20 ns;
        
        rdy_for_msg <= '1'; wait for 20 ns;
        msg_in <= std_logic_vector(to_unsigned(2, C_block_size));
        key_e <= std_logic_vector(to_unsigned(2, C_block_size));
        key_n <= std_logic_vector(to_unsigned(7, C_block_size));
        wait for 5 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;

        rst <= '0'; wait for 5 ns;
        rst <= '1'; wait for 5 ns;
        
        rdy_for_msg <= '1'; wait for 5 ns;
        msg_in <= std_logic_vector(to_unsigned(2, C_block_size));
        key_e <= std_logic_vector(to_unsigned(4, C_block_size));
        key_n <= std_logic_vector(to_unsigned(7, C_block_size));
        wait for 20 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;
        
        rst <= '0'; wait for 20 ns;
        rst <= '1'; wait for 20 ns;
        
        rdy_for_msg <= '1'; wait for 20 ns;
        msg_in <= std_logic_vector(to_unsigned(6969, C_block_size));
        key_e <= std_logic_vector(to_unsigned(7172, C_block_size));
        key_n <= std_logic_vector(to_unsigned(65537, C_block_size));
        wait for 5 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;


    end process;
end architecture;
