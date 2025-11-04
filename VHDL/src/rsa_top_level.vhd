library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_top_level is
    port (
        exp_zero_out    : out std_logic;
        clk             : in  std_logic;
        reset           : in  std_logic;

        -- AXIS-like input interface (to DUT)
        msgin_valid     : in  std_logic;
        msgin_ready     : out std_logic;
        msgin_last      : in  std_logic;
        msgin_data      : in  std_logic_vector(255 downto 0);

        -- AXIS-like output interface (from DUT)
        msgout_valid    : out std_logic;
        msgout_ready    : in  std_logic;
        msgout_last     : out std_logic;
        msgout_data     : out std_logic_vector(255 downto 0);

        -- Keys / status
        key_e           : in  std_logic_vector(255 downto 0);
        key_n           : in  std_logic_vector(255 downto 0);
        rsa_status      : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of rsa_top_level is
    -- simple internal registers for minimal behavior
    signal processing      : std_logic := '0';
    signal latched_data    : std_logic_vector(255 downto 0) := (others => '0');
    signal out_valid_reg   : std_logic := '0';
begin

    -- expose a simple exp_zero_out (unused here) and status
    exp_zero_out <= '0';
    rsa_status   <= (others => '0');


   ------------------------------------------------------------
    -- Datapath register prosess
    -- Kontrollerer base, eksponent, modulo, result, og output data
    ------------------------------------------------------------
   process(clk, reset)
    begin
        if reset = '1' then
            -- RESET STATE: sett alle registre til kjent verdi
            processing    <= '0';
            latched_data  <= (others => '0');
            out_valid_reg <= '0';
            msgin_ready   <= '0';
            msgout_last   <= '0';
        elsif rising_edge(clk) then

            -- DEFAULTS for this cycle
            msgin_ready <= '0';
            msgout_last <= '0';

            ------------------------------------------------
            -- IDLE / ACCEPT: Venter på ny input (ready høy)
            -- Merk: vi tester kun msgin_valid her - ikke msgin_ready
            -- fordi msgin_ready ble satt i denne prosessen og oppdateres etter klokken.
            ------------------------------------------------
            if processing = '0' then
                msgin_ready <= '1';
                if msgin_valid = '1' then
                    -- ta imot data (sample msgin_data)
                    latched_data  <= msgin_data;
                    processing    <= '1';
                    out_valid_reg <= '1';
                    msgout_last   <= msgin_last;
                end if;

            ------------------------------------------------
            -- PROCESSING / PRESENT: Presenter output til consumer tar den
            ------------------------------------------------
            else
                if out_valid_reg = '1' then
                    -- hold data på msgout_data til msgout_ready pulserer
                    if msgout_ready = '1' then
                        out_valid_reg <= '0';
                        processing    <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- OUTPUT ASSIGNMENTS: Alltid drevet fra interne registre
    msgout_valid <= out_valid_reg;
    msgout_data  <= latched_data;

end architecture;