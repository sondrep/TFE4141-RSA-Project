library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity RL is
    generic (
        WIDTH : integer := 8
    );
  Port (
    clk         : in std_logic;
    reset       : in std_logic;
    enable      : in std_logic;
    data_in     : in std_logic_vector(WIDTH-1 downto 0);
    exp_lsb     : out std_logic;
    exp_zero    : out std_logic;
    data_out    : out std_logic_vector(WIDTH-1 downto 0)
  );
end RL;

architecture Behavioral of RL is
    signal busy       : std_logic;
    signal exp_reg    : std_logic_vector(WIDTH-1 downto 0);
begin
    process(clk, reset)
    begin
        if reset = '1' then
            exp_reg     <= (others => '0');
            busy        <= '0';
            exp_lsb     <= '0';
            exp_zero    <= '0';
        elsif rising_edge(clk) then
            if enable = '1' and busy = '0' then
                exp_reg     <= data_in;
                busy        <= '1';
                exp_lsb     <= '0';
                exp_zero    <= '0';
                
            elsif enable = '1' and busy = '1' then
                if to_integer(unsigned(exp_reg)) = 0 then
                
                    -- FINISHED
                    exp_zero <= '1';
                    
                else
                    -- LSB CHECK OF EXP
                    if exp_reg(0) = '1' then
                        exp_lsb <= '1';
                      
                    end if;
                    
                    data_out  <= std_logic_vector(shift_right(unsigned(exp_reg), 1));
                    busy <= '0';
                    
                end if;
            end if;
        end if;
    end process;
end Behavioral;