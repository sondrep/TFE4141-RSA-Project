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
    type state_type is (IDLE, CHECK_EXP_BIT_MUL, SQUARE_MUL, WAIT_MUL_RB, WAIT_MUL_BB, MSG_DONE, REDUCE_BASE);
    signal state: state_type := IDLE;
    signal bit_index: integer range 0 to C_block_size-1;

    signal blakley_reset_n : STD_LOGIC := '0';
    signal blakley_start : STD_LOGIC;
    signal blakley_A : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_B : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_r_read_done : STD_LOGIC;
    signal blakley_done : STD_LOGIC;
    signal blakley_R_out : STD_LOGIC_VECTOR(C_block_size-1 downto 0);

    signal result_valid_reg : STD_LOGIC;
    signal ready_out_reg : STD_LOGIC;
begin
    blakley_mul_inst: entity work.blakley_mul
     generic map(
        C_block_size => C_block_size
    )
     port map(
        clk => clk,
        reset_n => blakley_reset_n,
        start => blakley_start,
        A => blakley_A,
        B => blakley_B,
        N => modulus,
        R_read_done => blakley_r_read_done,
        done => blakley_done,
        R_out => blakley_R_out
    );

    process(clk, reset_n)
        variable temp_result: unsigned(C_block_size-1 downto 0);
        variable temp_message: unsigned(C_block_size-1 downto 0);
    begin
    if ready_out <= '1' then
            ready_out_reg <= '1';
    else
        ready_out_reg <= '0';
    end if;

    if reset_n = '0' then
        state <= IDLE;
        bit_index <= 0;
        temp_result := to_unsigned(1, C_block_size);
        temp_message := (others => '0');
        blakley_start <= '0';
        blakley_reset_n <= '0';
    elsif rising_edge(clk) then
        case state is
            when REDUCE_BASE =>
                    -- multi-cycle simple reduction: subtract modulus until base < modulus
                    if temp_message >= unsigned(modulus) then
                        temp_message := temp_message - unsigned(modulus);
                    else
                        state <= CHECK_EXP_BIT_MUL;
                    end if;
            
            when IDLE =>
                ready_in <= '1';
                if valid_in = '1' then
                    ready_out_reg <= '0';
                    valid_out <= '0';
                    result_valid_reg <= '0';
                    blakley_reset_n <= '1';
                    blakley_r_read_done <= '0';
                    state <= REDUCE_BASE;
                    bit_index <= 0;
                    blakley_start <= '0';
                    blakley_reset_n <= '1';
                    temp_result := to_unsigned(1, C_block_size);
                    temp_message := unsigned(message);
                end if;

            when CHECK_EXP_BIT_MUL =>
                blakley_reset_n <= '1';
                ready_in <= '0';
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
                blakley_reset_n <= '1';
                ready_in <= '0';
                blakley_r_read_done <= '0';
                blakley_A <= STD_LOGIC_VECTOR(temp_message);
                blakley_B <= STD_LOGIC_VECTOR(temp_message);
                blakley_start <= '1';
                state <= WAIT_MUL_BB;

            when WAIT_MUL_RB =>
                blakley_reset_n <= '1';
                ready_in <= '0';
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
                blakley_reset_n <= '1';
                ready_in <= '0';
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
                blakley_r_read_done <= '0';
                blakley_reset_n <= '0';
                ready_in <= '0';
                result <= STD_LOGIC_VECTOR(temp_result);
                if ready_out_reg = '1' then
                    valid_out <= '1';
                    result_valid_reg <= '1';
                end if;
                if result_valid_reg = '1' and ready_out = '1' then
                    state <= IDLE;
                end if;

        end case;
    end if;
end process;
end architecture;