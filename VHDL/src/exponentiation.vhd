library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blakley_mul is
    generic (
        C_block_size : integer := 256
    );
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        start       : in  std_logic;
        A           : in  std_logic_vector(C_block_size-1 downto 0);
        B           : in  std_logic_vector(C_block_size-1 downto 0);
        N           : in  std_logic_vector(C_block_size-1 downto 0);
        R_read_done : in  std_logic;  -- consumer ack: clear done when '1'
        done        : out std_logic;  -- high when result is valid, stays high until R_read_done
        R_out       : out std_logic_vector(C_block_size-1 downto 0)
    );
end entity;

architecture rtl of blakley_mul is
    signal a_reg, b_reg, n_reg : unsigned(C_block_size-1 downto 0);
    signal r_reg               : unsigned(C_block_size-1 downto 0);
    signal running             : std_logic := '0';
    signal result_valid        : std_logic := '0';
begin
    process(clk, reset_n)
        variable tmp    : unsigned(C_block_size downto 0);
        variable r_next : unsigned(C_block_size-1 downto 0);
        variable a_next : unsigned(C_block_size-1 downto 0);
        variable b_next : unsigned(C_block_size-1 downto 0);
    begin
        if reset_n = '0' then
            a_reg        <= (others => '0');
            b_reg        <= (others => '0');
            n_reg        <= (others => '0');
            r_reg        <= (others => '0');
            running      <= '0';
            result_valid <= '0';

        elsif rising_edge(clk) then
            -- Clear result_valid only when consumer acks
            if result_valid = '1' and R_read_done = '1' then
                result_valid <= '0';
            end if;

            -- Start new operation only if idle AND previous result consumed
            if start = '1' and running = '0' and result_valid = '0' then
                a_reg   <= unsigned(A);
                b_reg   <= unsigned(B);
                n_reg   <= unsigned(N);
                r_reg   <= (others => '0');  -- r = 0
                running <= '1';

            elsif running = '1' then
                -- LSB-fireset_n add-and-shift:
                -- if b(0)=1: r = (r + a) % n
                -- a = (2a) % n
                -- b = b >> 1

                -- defaults
                r_next := r_reg;
                a_next := a_reg;
                b_next := shift_right(b_reg, 1);

                -- conditional add: r = (r + a) % n
                if b_reg(0) = '1' then
                    tmp := resize(r_reg, C_block_size+1) + resize(a_reg, C_block_size+1);
                    if tmp >= n_reg then
                        tmp := tmp - n_reg;
                    end if;
                    r_next := tmp(C_block_size-1 downto 0);
                end if;

                -- a = (2a) % n
                tmp := shift_left(resize(a_reg, C_block_size+1), 1);
                if tmp >= n_reg then
                    tmp := tmp - n_reg;
                end if;
                a_next := tmp(C_block_size-1 downto 0);

                -- commit
                r_reg <= r_next;
                a_reg <= a_next;
                b_reg <= b_next;

                -- finish when all bits of b consumed
                if b_next = (b_next'range => '0') then
                    running      <= '0';
                    result_valid <= '1';
                end if;
            end if;
        end if;
    end process;

    done  <= result_valid;
    R_out <= std_logic_vector(r_reg);
end architecture;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rl_modexp is
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

architecture rl_binary of rl_modexp is
    type state_type is (START_PROCESSING, CHECK_EXP_BIT_MUL, SQUARE_MUL, WAIT_MUL_RB, WAIT_MUL_BB, MSG_DONE, REDUCE_BASE, WAIT_FOR_NEW_INPUT);
    signal state: state_type := WAIT_FOR_NEW_INPUT;
    signal bit_index: integer range 0 to C_block_size-1;

    signal blakley_reset_n : STD_LOGIC := '0';
    signal blakley_start : STD_LOGIC;
    signal blakley_A : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_B : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
    signal blakley_r_read_done : STD_LOGIC;
    signal blakley_done : std_logic;
    signal blakley_R_out : std_logic_vector(C_block_size-1 downto 0);
    
    signal ready_out_reg : std_logic;
    signal valid_out_reg : std_logic;
	signal valid_in_reg : std_logic;
	signal ready_in_reg : std_logic;
    
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

    --process(ready_out, clk)
    --begin
    --    if ready_out = '1' and state = MSG_DONE and valid_out_reg = '1' then
    --        ready_out_reg <= '1';
    --        valid_out <= '1';
    --    else
    --        valid_out <= '0';
    --        ready_out_reg <= '0';
    --    end if;
    --end process;
    
    process(clk, valid_in)
    begin
		if (valid_in = '1' and state = WAIT_FOR_NEW_INPUT and ready_in_reg = '1') then
			valid_in_reg <= '1';
			ready_in <= '0';
		elsif state /= WAIT_FOR_NEW_INPUT then
			ready_in <= '0';
		else
			valid_in_reg <= '0';
			ready_in <= '1';
		end if;
        
    end process;

    process(all)
        variable temp_result: unsigned(C_block_size-1 downto 0);
        variable temp_message: unsigned(C_block_size-1 downto 0);
    begin


    if reset_n = '0' then
        state <= WAIT_FOR_NEW_INPUT;
        bit_index <= 0;
        temp_result := to_unsigned(1, C_block_size);
        temp_message := (others => '0');
        blakley_start <= '0';
        blakley_reset_n <= '0';
    elsif rising_edge(clk) then
        case state is
            when REDUCE_BASE =>
                    if temp_message >= unsigned(modulus) then
                        temp_message := temp_message - unsigned(modulus);
                    else
                        state <= CHECK_EXP_BIT_MUL;
                    end if;
            
            when START_PROCESSING =>
                valid_out <= '0';
                if valid_in = '1' then
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
                blakley_r_read_done <= '0';
                blakley_A <= STD_LOGIC_VECTOR(temp_message);
                blakley_B <= STD_LOGIC_VECTOR(temp_message);
                blakley_start <= '1';
                state <= WAIT_MUL_BB;

            when WAIT_MUL_RB =>
                blakley_reset_n <= '1';
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
                result <= STD_LOGIC_VECTOR(temp_result);
                valid_out <= '1';
                if ready_out = '1' then
                    state <= WAIT_FOR_NEW_INPUT;
                end if;
                
            when WAIT_FOR_NEW_INPUT =>
				ready_in_reg <= '1';
                valid_out <= '0';
                if valid_in_reg = '1' then
					ready_in_reg <= '0';
					state <= START_PROCESSING;
				end if;

        end case;
    end if;
end process;
end architecture;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity exponentiation is
    generic (
        C_block_size : integer := 256;
        NUM_CORES : integer := 10
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

        msgin_last : in STD_LOGIC;
        msgout_last : out STD_LOGIC;

        -- Output data
        result      : out STD_LOGIC_VECTOR(C_block_size-1 downto 0)
    );
end entity;

architecture expBehave of exponentiation is
    type state_type is (WAIT_FOR_NEW_INPUT, GIVE_CORE_INPUT, WAIT_RESULTS, ALL_MSG_DONE, NEXT_MSG_OUT);
    signal state : state_type := WAIT_FOR_NEW_INPUT;
    signal ready_out_reg : std_logic;
    signal valid_out_reg : std_logic;
	signal valid_in_reg : std_logic;
	signal ready_in_reg : std_logic;
    signal core_valid_in, core_ready_in, core_valid_out, core_ready_out : std_logic_vector(NUM_CORES-1 downto 0) := (others => '0');
    type core_vec is array (0 to NUM_CORES-1) of std_logic_vector(C_block_size-1 downto 0);
    signal core_message, core_result : core_vec;

    signal core_msg_last : std_logic_vector(NUM_CORES-1 downto 0) := (others => '0');

begin
    gen_cores : for i in 0 to NUM_CORES-1 generate
        core_i : entity work.rl_modexp
        generic map (C_block_size => C_block_size)
        port map (
            clk       => clk,
            reset_n   => reset_n,
            valid_in  => core_valid_in(i),
            ready_in  => core_ready_in(i),
            ready_out => core_ready_out(i),
            valid_out => core_valid_out(i),
            message   => core_message(i),
            key       => key,       -- same key for all
            modulus   => modulus,   -- same modulus for all
            result    => core_result(i)
        );
    end generate;

    process(clk)
    begin
            if ready_out = '1' and state = ALL_MSG_DONE and valid_out_reg = '1' then
                ready_out_reg <= '1';
                valid_out <= '1';
            else
                valid_out <= '0';
                ready_out_reg <= '0';
            end if;
    end process;
    
    process(clk, valid_in)
    begin
		if (valid_in = '1' and state = WAIT_FOR_NEW_INPUT and ready_in_reg = '1') then
			valid_in_reg <= '1';
			ready_in <= '0';
		elsif state /= WAIT_FOR_NEW_INPUT then
			ready_in <= '0';
		else
			valid_in_reg <= '0';
			ready_in <= '1';
		end if;
        
    end process;

    process(clk)
    variable core_counter : INTEGER := 0;
    variable msg_counter : INTEGER := 0;
    variable watchdog_counter : INTEGER := 0;
    variable core_valid_out_counter : INTEGER := 0;
    begin
        if reset_n = '0' then
            state <= WAIT_FOR_NEW_INPUT;
            valid_out_reg <= '0';
            ready_in_reg <= '1';
            core_valid_in <= (others => '0');
            core_ready_out <= (others => '0');
            core_counter := 0;
            result <= (others => '0');

        elsif rising_edge(clk) then
            case state is
            when WAIT_FOR_NEW_INPUT =>
                valid_out_reg <= '0';
		    	ready_in_reg <= '1';
                watchdog_counter := watchdog_counter + 1;
                core_counter := 0;
                if watchdog_counter = 20 then
                    state <= WAIT_RESULTS;
                    core_counter := 0;
                elsif valid_in_reg = '1' and msg_counter < NUM_CORES and message /= (message'range => '0') then
                    watchdog_counter := 0;
                    core_message(msg_counter) <= message;
                    core_valid_in(msg_counter) <= '1';
		    		ready_in_reg <= '0';
                    core_msg_last(msg_counter) <= msgin_last;
		    		state <= GIVE_CORE_INPUT;
		    	end if;

            when GIVE_CORE_INPUT =>
                watchdog_counter := 0;
                if msg_counter < NUM_CORES and message /= (message'range => '0') then
                    state <= WAIT_FOR_NEW_INPUT;
                    msg_counter := msg_counter + 1;
                end if;
                if msg_counter >= NUM_CORES then
                    state <= WAIT_RESULTS;
                end if;
                    

            when WAIT_RESULTS =>
                core_valid_in <= (others => '0');
                if msg_counter = 0 then
                    state <= WAIT_FOR_NEW_INPUT;
                    core_counter := 0;
                else 
                    for i in 0 to NUM_CORES-1 loop
                        if core_valid_out(i) = '1' then
                            core_valid_out_counter := core_valid_out_counter + 1;
                        end if;
                    end loop;
                end if;
                if core_valid_out_counter = msg_counter and msg_counter /= 0 then
                    state <= ALL_MSG_DONE;
                    result <= core_result(core_counter);
                    msgout_last <= core_msg_last(core_counter);
                    core_valid_out_counter := 0;
                else
                    core_valid_out_counter := 0;
                end if;

            when ALL_MSG_DONE =>
                core_valid_out_counter := 0;
                valid_out_reg <= '1';
                core_ready_out(core_counter) <= '1';
                if ready_out_reg = '1' then
                    state <= NEXT_MSG_OUT;
                end if;

            when NEXT_MSG_OUT =>
                valid_out_reg <= '0';
                if msg_counter = 0 then
                    core_counter := 0;
                    state <= WAIT_FOR_NEW_INPUT;
                    msg_counter := 0;
                else 
                    core_ready_out(core_counter) <= '0';
                    core_counter := core_counter + 1;
                    msg_counter := msg_counter - 1;
                    state <= WAIT_RESULTS;
                    msgout_last  <= '0';
                end if;
                
            end case;
        end if;

end process;
end architecture;