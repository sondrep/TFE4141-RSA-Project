library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mod_exp is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk         : in  STD_LOGIC;
        rst       : in  STD_LOGIC;
        start       : in  STD_LOGIC;
        base        : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        exponent    : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        key_n         : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        result      : out STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        done        : out STD_LOGIC;
        rdy_for_msg : out STD_LOGIC;
        busy        : out STD_LOGIC
    );
end entity;

architecture rtl of mod_exp is
    type state_type is (IDLE, CHECK_EXP_BIT_MUL, SQUARE_MUL, WAIT_MUL_RB, WAIT_MUL_BB, MSG_DONE);
    signal state: state_type;
    signal bit_index: integer range 0 to WIDTH-1;

    signal blakley_rst : STD_LOGIC;
    signal blakley_start : STD_LOGIC;
    signal blakley_A : STD_LOGIC_VECTOR(WIDTH-1 downto 0);
    signal blakley_B : STD_LOGIC_VECTOR(WIDTH-1 downto 0);
    signal blakley_r_read_done : STD_LOGIC;
    signal blakley_busy : STD_LOGIC;
    signal blakley_done : STD_LOGIC;
    signal blakley_R_out : STD_LOGIC_VECTOR(WIDTH-1 downto 0);
begin
    blakley_mul_inst: entity work.blakley_mul
     generic map(
        WIDTH => WIDTH
    )
     port map(
        clk => clk,
        rst => blakley_rst,
        start => blakley_start,
        A => blakley_A,
        B => blakley_B,
        N => key_n,
        R_read_done => blakley_r_read_done,
        busy => blakley_busy,
        done => blakley_done,
        R_out => blakley_R_out
    );

    process(clk, rst)
        variable temp_result: unsigned(WIDTH-1 downto 0);
        variable temp_base: unsigned(WIDTH-1 downto 0);
    begin
    if rst = '1' then
        state <= IDLE;
        bit_index <= 0;
        temp_result := to_unsigned(1, WIDTH);
        temp_base := unsigned(base);
        blakley_start <= '0';
        blakley_rst <= '1';
    elsif rising_edge(clk) then
        case state is
            when IDLE =>
                if start = '1' then
                    state <= CHECK_EXP_BIT_MUL;
                    bit_index <= 0;
                    blakley_start <= '0';
                    blakley_rst <= '0';
                    done <= '0';
                    temp_result := to_unsigned(1, WIDTH);
                    temp_base := unsigned(base);
                    result <= (others => '0');
                end if;

            when CHECK_EXP_BIT_MUL =>
                if bit_index < WIDTH then
                    blakley_r_read_done <= '0';
                    if unsigned(exponent(WIDTH-1 downto bit_index)) = 0 then
                        state <= MSG_DONE;
                    elsif exponent(bit_index) = '1' then
                        -- Start Blakley multiplication
                        blakley_A <= STD_LOGIC_VECTOR(temp_result);
                        blakley_B <= STD_LOGIC_VECTOR(temp_base);
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
                blakley_A <= STD_LOGIC_VECTOR(temp_base);
                blakley_B <= STD_LOGIC_VECTOR(temp_base);
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
                    -- Update temp_base with the squared result
                    temp_base := UNSIGNED(blakley_R_out);
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
                done <= '1';

        end case;
    end if;
end process;
end architecture;