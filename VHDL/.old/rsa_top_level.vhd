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

    -- FSM signals
    signal fsm_msgin_ready      : std_logic;
    signal fsm_msgout_valid     : std_logic;
    signal fsm_msgout_last_sig  : std_logic;
    signal fsm_mux_base_sel     : std_logic_vector(1 downto 0);
    signal fsm_demux_result_sel : std_logic;
    signal fsm_mux_exp_sel      : std_logic;
    signal fsm_shift_enable_fsm : std_logic;
    signal fsm_blakley_start_fsm: std_logic;
    signal fsm_exp_lsb          : std_logic;
    signal fsm_exp_zero         : std_logic;
    signal fsm_blakley_done_sig : std_logic;

    -- datapath registers
    signal base_reg    : std_logic_vector(255 downto 0) := (others => '0');
    signal result_reg  : std_logic_vector(255 downto 0) := (others => '0');
    signal exp_reg     : std_logic_vector(255 downto 0) := (others => '0');
    signal n_reg       : std_logic_vector(255 downto 0) := (others => '0');

    -- blakley interface
    signal bl_A        : std_logic_vector(255 downto 0);
    signal bl_B        : std_logic_vector(255 downto 0);
    signal bl_R_out    : std_logic_vector(255 downto 0);
    signal bl_busy     : std_logic;
    signal blakley_read_done : std_logic := '0';  -- consumer ack for blakley done

    -- <-- NEW handshake/latch signals -->
    signal blakley_op_sel_reg : std_logic_vector(1 downto 0) := (others => '0');
    signal blakley_done_prev  : std_logic := '0';
    signal blakley_read_ack   : std_logic := '0';

    -- RL interface
    signal rl_exp_done : std_logic;
    signal rl_data_out : std_logic_vector(255 downto 0);

begin
    -- expose status pins (simple)
    exp_zero_out <= fsm_exp_zero;
    rsa_status   <= (others => '0');

    -- connect top-level handshake ports to FSM
    msgin_ready  <= fsm_msgin_ready;
    msgout_valid <= fsm_msgout_valid;
    msgout_last  <= fsm_msgout_last_sig;
    blakley_read_done <= blakley_read_ack;  -- drive output port to multiplier from registered ack
    msgout_data  <= result_reg;    -- always present computed result on the bus

    ----------------------------------------------------------------
    -- Instantiate rsa_fsm (control)
    ----------------------------------------------------------------
    FSM_inst : entity work.rsa_fsm
        port map (
            clk               => clk,
            reset             => reset,
            msgin_valid       => msgin_valid,
            msgin_ready       => fsm_msgin_ready,
            msgout_valid      => fsm_msgout_valid,
            msgout_ready      => msgout_ready,
            msgout_last       => fsm_msgout_last_sig,
            exp_lsb           => fsm_exp_lsb,
            exp_zero          => fsm_exp_zero,
            blakley_done      => fsm_blakley_done_sig,
            mux_base_sel      => fsm_mux_base_sel,
            demux_result_sel  => fsm_demux_result_sel,
            mux_exp_sel       => fsm_mux_exp_sel,
            shift_enable_fsm  => fsm_shift_enable_fsm,
            blakley_start_fsm => fsm_blakley_start_fsm
        );

    ----------------------------------------------------------------
    -- Instantiate RL (exponent right-shift unit)
    ----------------------------------------------------------------
    RL_inst : entity work.RL
        generic map ( WIDTH => 256 )
        port map (
            clk        => clk,
            exp_reset  => reset,
            exp_enable => fsm_shift_enable_fsm,
            data_in    => exp_reg,
            exp_done   => rl_exp_done,
            exp_lsb    => fsm_exp_lsb,
            exp_zero   => fsm_exp_zero,
            data_out   => rl_data_out
        );

    ----------------------------------------------------------------
    -- Instantiate blakley multiplier
    ----------------------------------------------------------------
    BL_inst : entity work.blakley_mul
        generic map ( WIDTH => 256 )
        port map (
            clk   => clk,
            rst   => reset,
            start => fsm_blakley_start_fsm,
            A     => bl_A,
            B     => bl_B,
            N     => n_reg,
            busy  => bl_busy,
            done  => fsm_blakley_done_sig,
            R_out => bl_R_out,
            R_read_done => blakley_read_done   -- consumer ack: clear done when '1'
        );

    ----------------------------------------------------------------
    -- Select inputs to blakley based on FSM mux_base_sel
    ----------------------------------------------------------------
    bl_mux_proc : process(fsm_mux_base_sel, result_reg, base_reg)
    begin
        case fsm_mux_base_sel is
            when "01" =>   -- MULT_RESULT: A = result, B = base
                bl_A <= result_reg;
                bl_B <= base_reg;
            when "10" =>   -- SQUARE_BASE: A = base, B = base
                bl_A <= base_reg;
                bl_B <= base_reg;
            when others =>
                bl_A <= (others => '0');
                bl_B <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------------------
    -- Datapath sequential behaviour (capture inputs, update regs)
    ----------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            base_reg   <= (others => '0');
            result_reg <= (others => '0');
            exp_reg    <= (others => '0');
            n_reg      <= (others => '0');
            blakley_op_sel_reg <= (others => '0');
            blakley_done_prev  <= '0';
            blakley_read_ack   <= '0';
        elsif rising_edge(clk) then

            -- sample done one cycle (edge-detect)
            blakley_done_prev <= fsm_blakley_done_sig;

            -- latch which operation we started when FSM asserts start
            if fsm_blakley_start_fsm = '1' then
                blakley_op_sel_reg <= fsm_mux_base_sel;
            end if;

            -- Capture message / keys on handshake (FSM drives fsm_msgin_ready)
            if fsm_msgin_ready = '1' and msgin_valid = '1' then
                base_reg <= msgin_data;
                exp_reg  <= key_e;
                n_reg    <= key_n;
            end if;

            -- INIT: if FSM requests demux_result_sel, initialize result := 1
            if fsm_demux_result_sel = '1' then
                result_reg <= std_logic_vector(to_unsigned(1, 256));
            end if;

            -- When we observed blakley done on previous cycle, consume R_out now
            if blakley_done_prev = '1' and blakley_read_ack = '0' then
                if blakley_op_sel_reg = "01" then
                    result_reg <= bl_R_out;
                elsif blakley_op_sel_reg = "10" then
                    base_reg <= bl_R_out;
                end if;
                blakley_read_ack <= '1';  -- assert ack for exactly one clock
            elsif blakley_read_ack = '1' then
                blakley_read_ack <= '0';
            end if;

            -- When RL finishes a shift, update exponent register
            if rl_exp_done = '1' then
                exp_reg <= rl_data_out;
            end if;

        end if;
    end process;

        monitor_proc : process(clk)
    begin
        if rising_edge(clk) then
            if fsm_msgin_ready = '1' and msgin_valid = '1' then
                report "CAPTURE input: base(7:0)=" & integer'image(to_integer(unsigned(msgin_data(7 downto 0))))
                       severity note;
            end if;

            if fsm_demux_result_sel = '1' then
                report "FSM: INIT result := 1" severity note;
            end if;

            if fsm_blakley_start_fsm = '1' then
                report "FSM: blakley_start asserted, mux=" & to_string(fsm_mux_base_sel) severity note;
            end if;

            if fsm_blakley_done_sig = '1' then
                report "BL_DONE: R_out[7:0]=" & integer'image(to_integer(unsigned(bl_R_out(7 downto 0))))
                       & "  base[7:0]=" & integer'image(to_integer(unsigned(base_reg(7 downto 0))))
                       & "  result[7:0]=" & integer'image(to_integer(unsigned(result_reg(7 downto 0))))
                       severity note;
            end if;

            if msgout_valid = '1' then
                report "MSGOUT valid: result[7:0]=" & integer'image(to_integer(unsigned(result_reg(7 downto 0)))) severity note;
            end if;
        end if;
    end process;

end architecture;