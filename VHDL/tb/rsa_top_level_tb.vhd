library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_top_level_tb is
end entity;

architecture sim of rsa_top_level_tb is

begin
    DUT: entity work.rsa_top_level
    port map (
        clk         => clk,
        reset       => reset,

        msgin_valid => msgin_valid,
        msgin_ready => msgin_ready,
        msgin_last  => msgin_last,
        msgin_data  => msgin_data,

        msgout_valid    => msgout_valid,
        msgout_ready    => msgout_ready,
        msgout_last     => msgout_last,
        msgout_data     => msgout_data,

        key_e           => key_e,
        key_n           => key_n,
        rsa_status      => rsa_status
    );

    clk <= not clk after 10 ns;

    process
    begin
        rst <= '1'; wait for 30 ns;
        rst <= '0'; wait for 20 ns;

        msgin_valid <= '0';
        wait until msgin_ready = '1';

        msgin_data <= std_logic_vector(to_unsigned(10, WIDTH));
        key_e <= std_logic_vector(to_unsigned(14, WIDTH));
        key_n <= std_logic_vector(to_unsigned(17));
        wait for 100 ns;
        msgout_ready <= '1';
        wait until msgout_valid = '1';
        wait for 10 ns;

    end process;
end architecture;