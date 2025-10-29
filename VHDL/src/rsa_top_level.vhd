-- =============================================================================
-- rsa_top_level.vhd
-- top level utkast, blakley og bitshift moduler sine signaler kan endres på i portmappen nede
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Bare signalene inn og ut av RSA core, blodkopi fra word dokumentet sin figur 5, pluss clk og reset
entity rsa_top_level is
    port (
        clk            : in  std_logic;
        reset          : in  std_logic;
        exp_zero_out   : out std_logic;

        -- AXIS input (til/fra rsa_msgin)
        msgin_valid    : in  std_logic;
        msgin_ready    : out std_logic;
        msgin_last     : in  std_logic;
        msgin_data     : in  std_logic_vector(255 downto 0);

        -- AXIS output (til/fra rsa_msgout)
        msgout_valid   : out std_logic;
        msgout_ready   : in  std_logic;
        msgout_last    : out std_logic;
        msgout_data    : out std_logic_vector(255 downto 0);

        -- Signalene til/fra rsa_regio
        key_e          : in  std_logic_vector(255 downto 0);
        key_n          : in  std_logic_vector(255 downto 0);
        rsa_status     : out std_logic_vector(31 downto 0)
    );
end rsa_top_level;

architecture rtl of rsa_top_level is
    constant WIDTH : integer := 256;
    -------------------------------
    -- Interne kontrollsignaler
    -------------------------------
    signal blakley_start   : std_logic;
    signal blakley_done    : std_logic;
    signal shift_enable    : std_logic;
    signal shift_done      : std_logic;

    signal exp_lsb         : std_logic;
    signal exp_zero        : std_logic;

    -- Multiplexer kontrollsignaler
    signal mux_base_sel    : std_logic_vector(1 downto 0);
    signal demux_result_sel  : std_logic;
    signal mux_exp_sel     : std_logic;

    -- Interne data-registere
    signal base_reg        : std_logic_vector(255 downto 0);
    signal exp_reg_in      : std_logic_vector(255 downto 0);
    signal exp_reg_out     : std_logic_vector(255 downto 0);
    signal mod_n_reg       : std_logic_vector(255 downto 0);
    signal result_reg      : std_logic_vector(255 downto 0);

    -- Blakley resultat
    signal blakley_result  : std_logic_vector(255 downto 0);

begin
    ---------------------------------------------------------------
    -- FSM instansiering og portmap, signalene er forklart i rsa_fsm.vhd
    ---------------------------------------------------------------
    u_fsm : entity work.rsa_fsm                    -- tror ikke work. funker i VSCode, kanskje hvis vi lager ordentlig mappestruktur
        port map (
            clk           => clk,
            reset         => reset,

            -- Handshakes
            msgin_valid   => msgin_valid,
            msgin_ready   => msgin_ready,
            msgout_valid  => msgout_valid,
            msgout_ready  => msgout_ready,
            msgout_last   => msgout_last,

            -- Datapath feedback
            exp_lsb       => exp_lsb,
            exp_zero      => exp_zero,
            blakley_done  => blakley_done,

            -- Control outputs
            mux_base_sel  => mux_base_sel,
            demux_result_sel=> demux_result_sel,
            mux_exp_sel   => mux_exp_sel,
            shift_enable_fsm  => shift_enable,
            blakley_start_fsm => blakley_start
        );

    ---------------------------------------------------------------
    -- Blakley modul instansiering og portmap, hvis dere vil at signalene skal hete noe annet i deres moduler, endre venstre side
    ---------------------------------------------------------------
    u_blakley : entity work.blakley_mul
        generic map (WIDTH => WIDTH)
        port map (
            clk     => clk,
            rst     => reset,
            start   => blakley_start,
            A       => base_reg,
            B       => result_reg,
            N       => mod_n_reg,
            done    => blakley_done,
            R_out   => blakley_result
        );

    ---------------------------------------------------------------
    -- Bitshift modul instansiering og portmap, hvis dere vil at signalene skal hete noe annet i deres moduler, endre venstre side
    ---------------------------------------------------------------
    u_bitshift : entity work.RL
        generic map (WIDTH => WIDTH)
        port map (
            clk         => clk,
            exp_reset   => reset,
            exp_enable  => shift_enable,
            data_in     => exp_reg_in,
            data_out    => exp_reg_out,
            exp_lsb     => exp_lsb,
            exp_zero    => exp_zero,
            exp_done    => shift_done
        );

------------------------------------------------------------
-- Datapath register prosess
-- Kontrollerer base, eksponent, modulo, result, og output data
------------------------------------------------------------
process(clk, reset)
begin
--    if reset = '1' then                         -- asynkron reset, burde være der ved oppstart slik at man forsikrer seg at FSM går inn i IDLE ved power-up
--        base_reg     <= (others => '0');
--        exp_reg_in   <= (others => '0');
--        exp_reg_out  <= (others => '0');
--        mod_n_reg    <= (others => '0');
--        result_reg   <= (others => '0');
--        msgout_data  <= (others => '0');
--        rsa_status   <= (others => '0');

    if rising_edge(clk) then
        ------------------------------------------------
        -- 1. Last inn ny mld og nokler (LOAD)
        ------------------------------------------------
        if (msgin_valid = '1' and msgin_ready = '1') then
            -- Laster base (melding), eksponent, og modulo
            base_reg   <= msgin_data;
            exp_reg_in <= key_e;
            mod_n_reg  <= key_n;
        end if;

        ------------------------------------------------
        -- 2. Initialiser result = 1 (INIT)
        ------------------------------------------------
        if (demux_result_sel = '1') then
            result_reg <= (others => '0');
            result_reg(0) <= '1';               -- Setter result_reg til 1 slik at result * base ikke blir 0
        end if;

        ------------------------------------------------
        -- 3. Oppdaterer enten base eller result registeret etter blakley operasjon er utført (MULT_RESULT og SQUARE_BASE)
        ------------------------------------------------
        if (blakley_done = '1') then
            --blakley_start <= '0';
            -- FSM sier ifra hva slags operasjon som ble utført:
            -- mux_base_sel velger hvor resultatet skal lagres
            if mux_base_sel = "10" then
                -- SQUARE_BASE state --> oppdater base_reg
                base_reg <= blakley_result;
            elsif mux_base_sel = "01" then
                -- MULT_RESULT state --> oppdater result_reg
                result_reg <= blakley_result;
            end if;
        end if;

        ------------------------------------------------
        -- 4. Shifte eksponenten (SHIFT_EXP) (utført av bitshift.vhd)
        ------------------------------------------------
       -- if (shift_enable = '1') then
            --exp_reg_out <= std_logic_vector(shift_right(unsigned(exp_reg_in), 1));
       --     shift_enable <= '0';
       -- end if;
       exp_zero_out <= exp_zero;
        if (shift_done = '1') then
           -- shift_enable <= '0';
            exp_reg_in <= exp_reg_out;
            
        end if;

        ------------------------------------------------
        -- 5. Output final result (DONE)
        ------------------------------------------------
        if (msgout_valid = '1' and msgout_ready = '1') then
            msgout_data <= result_reg;
            rsa_status  <= (others => '0');  -- Denne brukes ikke enda, vet ikke helt hva vi skal med den? Den assignes for å unngå errors under synthesis
        end if;
    end if;
end process;


end rtl;
