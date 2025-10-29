library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_top_level_tb is
end entity;

architecture sim of rsa_top_level_tb is
    -- parameterize bus width to match rsa_top_level signals
    constant WIDTH : integer := 256;

    -- clock and reset
    signal clk   : std_logic := '0';
    signal reset : std_logic := '0';
    signal exp_zero_out : std_logic := '0';

    -- AXIS-like input interface (to DUT)
    signal msgin_valid : std_logic := '0';
    signal msgin_ready : std_logic := '0';  -- driven by DUT
    signal msgin_last  : std_logic := '0';
    signal msgin_data  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

    -- AXIS-like output interface (from DUT)
    signal msgout_valid : std_logic := '0'; -- driven by DUT
    signal msgout_ready : std_logic := '0';
    signal msgout_last  : std_logic := '0'; -- driven by DUT
    signal msgout_data  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

    -- Key / control registers
    signal key_e      : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal key_n      : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

    -- status register (as declared in rsa_top_level.vhd)
    signal rsa_status : std_logic_vector(31 downto 0) := (others => '0');
begin
    DUT: entity work.rsa_top_level
    port map (
        exp_zero_out => exp_zero_out,
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

    -- 20 ns clock period (10 ns high / 10 ns low)
    clk <= not clk after 10 ns;

    process
    begin
        -- apply synchronous reset
        reset <= '1'; wait for 30 ns;
        reset <= '0'; wait for 20 ns;

        -- wait until DUT indicates it's ready to accept input
        msgin_valid <= '0';
    --    wait until msgin_ready = '1';

        -- provide inputs (ensure widths are provided)
        msgin_data <= std_logic_vector(to_unsigned(10, WIDTH));
        key_e <= std_logic_vector(to_unsigned(14, WIDTH));
        key_n <= std_logic_vector(to_unsigned(17, WIDTH));

        -- assert msgin_valid for one beat to indicate valid input
        wait for 50 ns;
        msgin_valid <= '1';
        wait for 100 ns;
        msgin_valid <= '0';

        -- allow some time for DUT processing
        wait for 100 ns;

        -- indicate we are ready to accept output
        msgout_ready <= '1';
        wait until msgout_valid = '1';
        wait for 10 ns;

        -- stop simulation
        report "Testbench finished" severity note;
        wait;
    end process;
end architecture;