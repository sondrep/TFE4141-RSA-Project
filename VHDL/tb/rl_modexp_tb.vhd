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
    signal mod_exp_ready_in : STD_LOGIC := '0';
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
            ready_out       => rdy_for_msg,
            ready_in => mod_exp_ready_in
        );

    clk <= not clk after 2.5 ns;

    process
    begin
        rst <= '0'; wait for 10 ns;
        rst <= '1';
        msg_in <= (others => '0');
        wait until mod_exp_ready_in = '1';
        msg_in <= x"0000000011111111222222223333333344444444555555556666666677777777";
        key_n <=  x"99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d";
        key_e <=  x"0000000000000000000000000000000000000000000000000000000000010001";
        wait for 5 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        rdy_for_msg <= '1';  -- acknowledge
        wait until rising_edge(clk);
        rdy_for_msg <= '0';

        wait until mod_exp_ready_in = '1';
        msg_in <= result;
        key_n <= x"99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d";
        key_e <= x"0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9";
        wait for 20 ns;

        start <= '1';
        wait for 20 ns;
        start <= '0';

        wait until done = '1';
        wait for 20 ns;


    end process;
end architecture;
