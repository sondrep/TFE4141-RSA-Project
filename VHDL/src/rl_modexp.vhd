library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity exponentiation is
    generic (
        C_block_size : integer := 256
    );
    port (
        -- Utility
        clk         : in  STD_LOGIC;
        reset_n     : in  STD_LOGIC;

        -- Input control
        valid_in    : in  STD_LOGIC; -- This is our START signal pretty much 
        ready_in    : out STD_LOGIC;    -- We signal that we are ready to recieve input

        -- Output control
        ready_out   : in STD_LOGIC;     -- outside says its ready to receive message (I think we can assume they have read the message here)
        valid_out   : out STD_LOGIC;    -- output that signals we are DONE processing

        -- Input data
        message     : in  STD_LOGIC_VECTOR(C_block_size-1 downto 0);
        key         : in  STD_LOGIC_VECTOR(C_block_size-1 downto 0);
        modulus     : in  STD_LOGIC_VECTOR(C_block_size-1 downto 0);

        -- Output data
        result      : out STD_LOGIC_VECTOR(C_block_size-1 downto 0)
    );
end entity;

architecture expBehave of exponentiation is
    type state_type is (IDLE, CHECK_EXP_BIT_MUL, SQUARE_MUL, WAIT_MUL_RB, WAIT_MUL_BB, MSG_DONE);
    signal state: state_type;
    signal bit_index: integer range 0 to C_block_size-1;

    signal blakley_rst : STD_LOGIC;
    signal blakley_start : STD_LOGIC;
    signal blakley_A : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_B : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_r_read_done : STD_LOGIC;
    signal blakley_busy : STD_LOGIC;
    signal blakley_done : STD_LOGIC;
    signal blakley_R_out : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
begin
    blakley_mul_inst: entity work.blakley_mul
     generic map(
        C_block_size => C_block_size
    )
     port map(
        clk => clk,
        rst => blakley_rst,
        start => blakley_start,
        A => blakley_A,
        B => blakley_B,
        N => modulus,
        R_read_done => blakley_r_read_done,
        busy => blakley_busy,
        done => blakley_done,
        R_out => blakley_R_out
    );

    process(clk, reset_n)
        variable temp_result: unsigned(C_block_size-1 downto 0);
        variable temp_message: unsigned(C_block_size-1 downto 0);
    begin
    if reset_n = '0' then
        state <= IDLE;
        bit_index <= 0;
        temp_result := to_unsigned(1, C_block_size);
        temp_message := unsigned(message);
        blakley_start <= '0';
        blakley_rst <= '1';
    elsif rising_edge(clk) then
        case state is
            when IDLE =>
                if valid_in = '1' then
                    state <= CHECK_EXP_BIT_MUL;
                    bit_index <= 0;
                    blakley_start <= '0';
                    blakley_rst <= '0';
                    valid_out <= '0';
                    temp_result := to_unsigned(1, C_block_size);
                    temp_message := unsigned(message);
                    result <= (others => '0');
                end if;

            when CHECK_EXP_BIT_MUL =>
                if bit_index < C_block_size then
                    blakley_r_read_done <= '0';
                    if unsigned(key(C_block_size-1 downto bit_index)) = 0 then
                        state <= MSG_DONE;
                    elsif key(bit_index) = '1' then
                        -- Start Blakley multiplication
                        blakley_A <= STD_LOGIC_VECTOR(temp_result);
                        blakley_B <= STD_LOGIC_VECTOR(temp_message);
                        blakley_start <= '1';
                        state <= WAIT_MUL_RB;
                    else
                        -- No multiplication needed, move to next bit
                        state <= SQUARE_MUL;
                    end if;
                else
                    -- All bits processed
                    state <= MSG_DONE;
                end if;

            when SQUARE_MUL =>
                blakley_r_read_done <= '0';
                blakley_A <= STD_LOGIC_VECTOR(temp_message);
                blakley_B <= STD_LOGIC_VECTOR(temp_message);
                blakley_start <= '1';
                state <= WAIT_MUL_BB;

            when WAIT_MUL_RB =>
                if blakley_done = '1' then
                    -- Update temp_result with the result
                    temp_result := UNSIGNED(blakley_R_out);
                    blakley_r_read_done <= '1';
                    blakley_start <= '0';
                    state <= SQUARE_MUL;
                else 
                    blakley_r_read_done <= '0';
                    blakley_start <= '0';
                end if;

            when WAIT_MUL_BB =>
                blakley_r_read_done <= '0';
                if blakley_done = '1' then
                    -- Update temp_message with the squared result
                    temp_message := UNSIGNED(blakley_R_out);
                    blakley_r_read_done <= '1';
                    blakley_start <= '0';
                    -- Move to next bit
                    bit_index <= bit_index + 1;
                    state <= CHECK_EXP_BIT_MUL;
                else 
                    blakley_r_read_done <= '0';
                    blakley_start <= '0';
                end if;
            
            when MSG_DONE =>
                result <= STD_LOGIC_VECTOR(temp_result);
                valid_out <= '1';

        end case;
    end if;
end process;
end architecture;