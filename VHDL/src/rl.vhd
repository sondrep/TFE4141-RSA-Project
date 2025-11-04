library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity RL is
    generic (
        WIDTH : integer := 8
    );
  Port (
    clk         : in std_logic;
    exp_reset   : in std_logic;
    exp_enable  : in std_logic;
    data_in     : in std_logic_vector(WIDTH-1 downto 0);
    exp_done    : out std_logic;
    exp_lsb     : out std_logic;
    exp_zero    : out std_logic;
    data_out    : out std_logic_vector(WIDTH-1 downto 0)
  );
end RL;

architecture Behavioral of RL is
    signal exp_reg    : std_logic_vector(WIDTH-1 downto 0);
begin
    process(clk, exp_reset)
    begin
        if exp_reset = '1' then
            exp_reg     <= (others => '0');
            exp_lsb     <= '0';
            exp_zero    <= '0';
            exp_done    <= '0';
            data_out    <= (others => '0');
        elsif rising_edge(clk) then
            if exp_enable = '1' then
                -- Use current input to derive outputs (no sticky signals)
                exp_reg <= data_in;
                if to_integer(unsigned(data_in)) = 0 then
                    exp_zero <= '1';
                    exp_lsb  <= '0';
                    data_out <= (others => '0');
                else
                    exp_zero <= '0';
                    exp_lsb  <= data_in(0);
                    data_out <= std_logic_vector(shift_right(unsigned(data_in), 1));
                end if;
                exp_done <= '1';
            else
                -- Clear status when not enabled
                exp_done <= '0';
                exp_lsb  <= '0';
                exp_zero <= '0';
                -- keep exp_reg stable (or optionally load 0)
            end if;
        end if;
    end process;
end Behavioral;