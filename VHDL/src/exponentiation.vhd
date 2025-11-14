library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blakley_mul is
    generic (
        C_block_size : integer := 256
    );
    port (
        -- input
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        start       : in  std_logic;
        a           : in  std_logic_vector(C_block_size-1 downto 0); -- A and B are what we multiply
        b           : in  std_logic_vector(C_block_size-1 downto 0); -- See above
        n           : in  std_logic_vector(C_block_size-1 downto 0); -- Then take modulo N of A*B
        result_read_done    : in  std_logic;

        -- output
        done        : out std_logic;  -- high when result is valid, stays high until result_read_done = 1
        result_out  : out std_logic_vector(C_block_size-1 downto 0)
    );
end entity;

architecture rtl of blakley_mul is
    signal a_reg : unsigned(C_block_size-1 downto 0);
    signal b_reg : unsigned(C_block_size-1 downto 0);
    signal n_reg : unsigned(C_block_size-1 downto 0);
    signal r_reg : unsigned(C_block_size-1 downto 0);
    signal running : std_logic := '0';
    signal result_valid : std_logic := '0';
begin
    process(clk, reset_n)
        variable tmp    : unsigned(C_block_size downto 0);
        variable r_next : unsigned(C_block_size-1 downto 0);
        variable a_next : unsigned(C_block_size-1 downto 0);
        variable b_next : unsigned(C_block_size-1 downto 0);
    begin
        if reset_n = '0' then
            a_reg <= (others => '0');
            b_reg <= (others => '0');
            n_reg <= (others => '0');
            r_reg <= (others => '0');
            running <= '0';
            result_valid <= '0';

        elsif rising_edge(clk) then
            -- Clear result_valid only when consumer acks
            if result_valid = '1' and result_read_done = '1' then
                result_valid <= '0';
            end if;

            -- Start new operation
            if start = '1' and running = '0' and result_valid = '0' then
                a_reg <= unsigned(a);
                b_reg <= unsigned(b);
                n_reg <= unsigned(n);
                r_reg <= (others => '0');  -- r = 0
                running <= '1';

            elsif running = '1' then
                r_next := r_reg;
                a_next := a_reg;
                b_next := shift_right(b_reg, 1);

                -- conditional add if current bit of b is 1: r = (r + a) % n
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

                -- write to regs
                r_reg <= r_next;
                a_reg <= a_next;
                b_reg <= b_next;

                -- finish when there are only 0's left in b, we are done
                if b_next = (b_next'range => '0') then
                    running <= '0';
                    result_valid <= '1';
                end if;
            end if;
        end if;
    end process;

    done  <= result_valid;
    result_out <= std_logic_vector(r_reg);
end architecture;

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
-- This entity does the exponentiation, dont confuse it with the "exponentiation" entity that handles
-- the multicore scheduling
entity rl_modexp is
    generic (
        C_block_size : integer := 256
    );
    port (
        -- Utility
        clk         : in  std_logic;
        reset_n     : in  std_logic;

        -- Input control
        valid_in    : in  std_logic;    -- This is the signal that makes it START
        ready_in    : out std_logic;    -- We signal that we are ready to recieve input

        -- Output control
        ready_out   : in std_logic;     -- outside says its ready to receive message (I think we can assume they have read the message here)
        valid_out   : out std_logic;    -- output that signals we are DONE processing

        -- Input data
        message     : in  std_logic_vector(C_block_size-1 downto 0);
        key         : in  std_logic_vector(C_block_size-1 downto 0);
        modulus     : in  std_logic_vector(C_block_size-1 downto 0);

        -- Output data
        result      : out std_logic_vector(C_block_size-1 downto 0)
    );
end entity;

architecture rl_binary of rl_modexp is
    -- states for modexp function
    type state_type is (START_PROCESSING, CHECK_EXP_BIT_MUL, SQUARE_MUL, WAIT_MUL_RB, WAIT_MUL_BB, MSG_DONE, REDUCE_BASE, WAIT_FOR_NEW_INPUT);
    signal state: state_type := WAIT_FOR_NEW_INPUT;
    signal bit_index: integer range 0 to C_block_size-1;

    --signals to handle control of the blakley instances
    signal blakley_reset_n : std_logic := '0';
    signal blakley_start : std_logic;
    signal blakley_a : std_logic_vector(C_block_size-1 downto 0);
    signal blakley_b : std_logic_vector(C_block_size-1 downto 0);
    signal blakley_result_read_done : std_logic;
    signal blakley_done : std_logic;
    signal blakley_result_out : std_logic_vector(C_block_size-1 downto 0);
    
    -- Needed this for making handshaking work well
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
        a => blakley_a,
        b => blakley_b,
        n => modulus,
        result_read_done => blakley_result_read_done,
        done => blakley_done,
        result_out => blakley_result_out
    );
    -- This process is used to make handshaking work well, its a little weird since it isnt in sync with the clock
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
                    blakley_result_read_done <= '0';
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
                    blakley_result_read_done <= '0';
                    if unsigned(key(C_block_size-1 downto bit_index)) = 0 then
                        state <= MSG_DONE;
                    elsif key(bit_index) = '1' then
                        -- if current bit of exponent is 1 then we multiply result and message
                        blakley_a <= std_logic_vector(temp_result);
                        blakley_b <= std_logic_vector(temp_message);
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
                -- do the squaring mutliplcation
            when SQUARE_MUL =>
                blakley_reset_n <= '1';
                blakley_result_read_done <= '0';
                blakley_a <= std_logic_vector(temp_message);
                blakley_b <= std_logic_vector(temp_message);
                blakley_start <= '1';
                state <= WAIT_MUL_BB;

                -- Waiting state for result*base calculation
            when WAIT_MUL_RB =>
                blakley_reset_n <= '1';
                if blakley_done = '1' then
                    -- Update temp_result with the result
                    temp_result := unsigned(blakley_result_out);
                    blakley_result_read_done <= '1';
                    blakley_start <= '0';
                    state <= SQUARE_MUL;
                else 
                    blakley_result_read_done <= '0';
                    blakley_start <= '0';
                end if;

                -- waiting state for base*base calculation, the two waiting states could be done in parallel
                -- but we havent implemented this
            when WAIT_MUL_BB =>
                blakley_reset_n <= '1';
                blakley_result_read_done <= '0';
                if blakley_done = '1' then
                    -- Update temp_message with the squared result
                    temp_message := unsigned(blakley_result_out);
                    blakley_result_read_done <= '1';
                    blakley_start <= '0';
                    -- Move to next bit
                    bit_index <= bit_index + 1;
                    state <= CHECK_EXP_BIT_MUL;
                else 
                    blakley_result_read_done <= '0';
                    blakley_start <= '0';
                end if;

                -- state for when message is done, sets valid out to 1 and waits for ready out.
            when MSG_DONE =>
                blakley_result_read_done <= '0';
                blakley_reset_n <= '0';
                result <= std_logic_vector(temp_result);
                valid_out <= '1';
                if ready_out = '1' then
                    state <= WAIT_FOR_NEW_INPUT;
                end if;
                
                -- Waits for new input
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

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

entity exponentiation is
    generic (
        C_block_size : integer := 256;
        NUM_CORES : integer := 12 -- change this to select number of cores
    );
    port (
        -- Utility
        clk         : in  std_logic;
        reset_n     : in  std_logic;

        -- Input control
        valid_in    : in  std_logic;    -- This is our START signal
        ready_in    : out std_logic;    -- We signal that we are ready to recieve input

        -- Output control
        ready_out   : in std_logic;     -- outside says its ready to receive message (I think we can assume they have read the message here)
        valid_out   : out std_logic;    -- output that signals we are DONE processing

        -- Input data
        message     : in  std_logic_vector(C_block_size-1 downto 0);
        key         : in  std_logic_vector(C_block_size-1 downto 0);
        modulus     : in  std_logic_vector(C_block_size-1 downto 0);

        msgin_last  : in std_logic;
        msgout_last : out std_logic;

        -- Output data
        result      : out std_logic_vector(C_block_size-1 downto 0)
    );
end entity;

architecture expBehave of exponentiation is
    type state_type is (WAIT_FOR_NEW_INPUT, GIVE_CORE_INPUT, WAIT_RESULTS, MSG_DONE, NEXT_MSG_OUT);
    signal state : state_type := WAIT_FOR_NEW_INPUT;
    signal ready_out_reg : std_logic;
    signal valid_out_reg : std_logic;
	signal valid_in_reg : std_logic;
	signal ready_in_reg : std_logic;

    -- signals for core control
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

        -- Needed these processes to make handshaking with upper level modules smooth
    process(clk)
    begin
            if ready_out = '1' and state = MSG_DONE and valid_out_reg = '1' then
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
    -- variables for counting
    variable core_counter : integer := 0; -- counter to know which state we are handling
    variable msg_counter : integer := 0; -- counts amount of messages that are processing
    -- The watchdog is kinda just here to handle when the amount of messages are
    -- not divisible by the number of cores, its a bit rough but it works
    variable watchdog_counter : integer := 0;
    variable core_valid_out_counter : integer := 0; -- counts how many cores have valid output
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
                -- Wait for input
            when WAIT_FOR_NEW_INPUT =>
                valid_out_reg <= '0';
		    	ready_in_reg <= '1';
                watchdog_counter := watchdog_counter + 1;
                core_counter := 0;
                if watchdog_counter = 20 then -- if more than 20 cycles go with no new input we assume we got all remaining messages
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

                -- Mostly just handles msg counting here
            when GIVE_CORE_INPUT =>
                watchdog_counter := 0;
                if msg_counter < NUM_CORES and message /= (message'range => '0') then
                    state <= WAIT_FOR_NEW_INPUT;
                    msg_counter := msg_counter + 1;
                end if;
                if msg_counter >= NUM_CORES then
                    state <= WAIT_RESULTS;
                end if;
                    
                -- Checks the core valid out signals
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
                    state <= MSG_DONE;
                    result <= core_result(core_counter);
                    msgout_last <= core_msg_last(core_counter);
                    core_valid_out_counter := 0;
                else
                    core_valid_out_counter := 0;
                end if;

                -- Says to the core that the message is ready out
            when MSG_DONE =>
                core_valid_out_counter := 0;
                valid_out_reg <= '1';
                core_ready_out(core_counter) <= '1';
                if ready_out_reg = '1' then
                    state <= NEXT_MSG_OUT;
                end if;

                -- increment and decrement variables here
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