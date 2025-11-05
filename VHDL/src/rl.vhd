library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity RL is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk         : in  std_logic;
        exp_reset   : in  std_logic;
        exp_enable  : in  std_logic;
        data_in     : in  std_logic_vector(WIDTH-1 downto 0);
        exp_done    : out std_logic;
        exp_lsb     : out std_logic;
        exp_zero    : out std_logic;
        data_out    : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity RL;

architecture Behavioral of RL is
    signal data_out_reg : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal exp_done_reg : std_logic := '0';
begin
    -- Drive combinational status from current input so FSM can sample immediately
    exp_lsb  <= data_in(0);
    exp_zero <= '1' when unsigned(data_in) = 0 else '0';

    -- Output ports driven from internal registers
    data_out <= data_out_reg;
    exp_done <= exp_done_reg;

    -- Synchronous shift operation: produce shifted data_out and pulse exp_done
    process(clk, exp_reset)
    begin
        if exp_reset = '1' then
            data_out_reg <= (others => '0');
            exp_done_reg <= '0';
        elsif rising_edge(clk) then
            if exp_enable = '1' then
                if unsigned(data_in) = 0 then
                    data_out_reg <= (others => '0');
                else
                    data_out_reg <= std_logic_vector(shift_right(unsigned(data_in), 1));
                end if;
                exp_done_reg <= '1';
            else
                exp_done_reg <= '0';
                -- keep data_out_reg stable until next shift
            end if;
        end if;
    end process;
end architecture Behavioral;
