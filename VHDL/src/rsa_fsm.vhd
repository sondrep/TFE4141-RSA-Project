-- ============================================================
-- rsa_fsm.vhd
-- FSM idè
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_fsm is
    port (
        clk, reset        : in  std_logic;

        -- AXIS handshakes med moduler utenfra rsa_core
        msgin_valid       : in  std_logic;                      -- rsa_msgin sier at den har en mld klar til å hentes av rsa_core
        msgin_ready       : out std_logic;                      -- rsa_core sier den er klar til å motta mld fra rsa_msgin
        msgout_valid      : out std_logic;                      -- rsa_core sier at den har en mld klar til å hentes av rsa_msgout
        msgout_ready      : in  std_logic;                      -- rsa_msgout sier at den er klar til å lese mld fra rsa_core
        msgout_last       : out std_logic;                      -- flagg som må være høyt når meldinger skal sendes ut

        -- Datapath feedback fra submoduler
        exp_lsb           : in  std_logic;                      -- signal som sier hvilken verdi neste lsb i eksponenten er
        exp_zero          : in  std_logic;                      -- flagg som går høyt når hele eksponenten er null, altså meldingen er ferdig prosessert og kan sendes ut til rsa_msgout
        blakley_done      : in  std_logic;                      -- flagg som settes høyt av blakley.vhd når den har utført operasjonen

        -- Control outputs til rsa_top_level
        mux_base_sel      : out std_logic_vector(1 downto 0);   -- tobits vektor som sier om blakley operasjonen som skal utføres er base eller result
        demux_result_sel    : out std_logic;                      -- eeeeeeeeeeeeeeeehm
        mux_exp_sel       : out std_logic;                      -- kontrollsignal til bitshift MUX'en
        shift_enable_fsm      : out std_logic;                      -- signal som sier om bitshift skal utføres eller ikke
        blakley_start_fsm     : out std_logic                       -- signal som sier om blakley skal utøres eller ikke
    );
end rsa_fsm;

architecture behavioral of rsa_fsm is
    type state_type is (
        IDLE, LOAD, INIT, CHECK_BIT,
        MULT_RESULT, SQUARE_BASE, SHIFT_EXP,
        DONE, WAIT_READY
    );
    signal state, next_state : state_type;
begin
    ------------------------------------------------------------
    -- Prosess som kjører state machinen
    ------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ------------------------------------------------------------
    -- Next-state og output logikk
    ------------------------------------------------------------
    process(state, msgin_valid, msgout_ready, exp_lsb, exp_zero, blakley_done)
    begin
        -- Default outputs
        msgin_ready      <= '0';
        msgout_valid     <= '0';
        msgout_last      <= '0';
        mux_base_sel     <= "00";
        demux_result_sel   <= '0';
        mux_exp_sel      <= '0';
        shift_enable_fsm     <= '0';
        blakley_start_fsm    <= '0';
        next_state       <= state;

        case state is

            ------------------------------------------------
            -- IDLE: Venter på msgin_valid
            ------------------------------------------------
            when IDLE =>
                msgin_ready <= '1';                             -- sier ifra at vår enhet er klar til å motta signal
                if msgin_valid = '1' then                       -- triggres når msgin_valid blir 1, dette bestemmes av rsa_msgin
                    next_state <= LOAD;                         -- Kan teste å gå direkte til INIT, men det kan kan muligens skape glitches rundt msgin_valid? Fordi msgin_ready kan fremdeles være høy, og da kan dobbel-loading skje
                end if;

            ------------------------------------------------
            -- LOAD: Lar det gå en klokkesyklus før INIT begynner, for å unngå overlappende register-oppdateringer. Ingen annen funksjonalitet. Kan droppes?
            ------------------------------------------------
            when LOAD =>
                mux_base_sel <= "00";
                next_state   <= INIT;

            ------------------------------------------------
            -- INIT: Initialiserer result slik at result * base mod n != 0
            ------------------------------------------------
            when INIT =>
                demux_result_sel <= '1';
                next_state <= CHECK_BIT;

            ------------------------------------------------
            -- CHECK_BIT: Sjekker eksponent bitten
            ------------------------------------------------
            when CHECK_BIT =>
                if exp_lsb = '1' then                           -- sjekker om eksponent bitshiften er 1
                    next_state <= MULT_RESULT;                  -- om ja, gå inn i result * base mod n operasjonen
                else
                    next_state <= SQUARE_BASE;                  -- om nei, gå inn i vanlig base * base mod n operasjonen
                end if;

            ------------------------------------------------
            -- MULT_RESULT: result = result * base mod n
            ------------------------------------------------
            when MULT_RESULT =>
                blakley_start_fsm <= '1';                           -- sier til blakley.vhd at den skal starte result * base mod n operasjonen
                mux_base_sel  <= "01";                          -- dette signalet indikerer kun hvilken state den er i, kan ses på for feilsøking
                if blakley_done = '1' then                      -- venter på at blakley.vhd skal si den er ferdig
                    next_state <= SQUARE_BASE;
                end if;

            ------------------------------------------------
            -- SQUARE_BASE: base = base * base mod n
            ------------------------------------------------
            when SQUARE_BASE =>
                blakley_start_fsm <= '1';                           -- sier til blakley at den skal starte base * base mod n operasjonen
                mux_base_sel  <= "10";                          -- 10 indikerer vanlig base mod
                if blakley_done = '1' then                      -- venter på at blakley.vhd skal si den er ferdig
                    next_state <= SHIFT_EXP;
                end if;

            ------------------------------------------------
            -- SHIFT_EXP: bitshift state
            ------------------------------------------------
            when SHIFT_EXP =>
                shift_enable_fsm <= '1';                            -- Sier til bitshift.vhd at den skal utføre
                mux_exp_sel  <= '1';                            -- bitshift MUX'en settes til 1, slik at den repeater eksponenten tilbake etter den har blitt bitshifta
                if exp_zero = '1' then                          -- exp_zero sier at hele eksponenten har blitt bitshifta, som betyr at meldingen er ferdig prosessert. Går til DONE
                    next_state <= DONE;
                else
                    next_state <= CHECK_BIT;                    -- exp_zero sier at ikke hele eksponenten har blitt bitshifta, som betyr at meldingen ikke er ferdig prosessert enda. Går tilbake til CHECK_BIT.
                end if;

            ------------------------------------------------
            -- DONE: Output klar til å hentes
            ------------------------------------------------
            when DONE =>
                msgout_valid <= '1';                            -- Sier til rsa_msgout at msgout_data er klar til å hentes
                msgout_last  <= '1';                            -- Sier til rsa_msgout at dette er siste gyldige dataordet i en gitt pakke. Skal dras høy på samme klokkesyklus som 256-bit meldingen overføres.
                if msgout_ready = '1' then          
                    next_state <= IDLE;                         -- Hvis rsa_msgout er klar, kan FSM gå tilbake til IDLE for å kunne begynne med neste mld.
                else
                    next_state <= WAIT_READY;                   -- Hvis ikke så venter FSM'en på rsa_msgout
                end if;

            ------------------------------------------------
            -- WAIT_READY: Venter på at rsa_msgout skal bli klar
            ------------------------------------------------
            when WAIT_READY =>
                msgout_valid <= '1';                            -- msgout_data er fremdeles klar til å hentes
                msgout_last  <= '1';                            -- msgout_last er fremdeles høy, denne staten holder FSM'en til rsa_msgout har hentet meldingen
                if msgout_ready = '1' then
                    next_state <= IDLE;                         -- melding hentet, tilbake til start
                end if;

            when others =>
                next_state <= IDLE;
        end case;
    end process;
end behavioral;
