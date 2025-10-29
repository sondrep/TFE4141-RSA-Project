----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.10.2025 16:56:59
-- Design Name: 
-- Module Name: RL - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity RL is
  Port (
    clk         : in std_logic;
    reset       : in std_logic;
    enable      : in std_logic;
    data_in     : in unsigned(7 downto 0);
    exp_lsb     : out std_logic;
    exp_zero    : out std_logic;
    data_out    : out unsigned(7 downto 0)
  );
end RL;

architecture Behavioral of RL is
    signal busy       : std_logic;
    signal exp_reg    : unsigned(7 downto 0);
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
                if exp_reg = 0 then
                
                    -- FINISHED
                    exp_zero <= '1';
                    
                else
                    -- LSB CHECK OF EXP
                    if exp_reg(0) = '1' then
                      exp_lsb <= '1';
                      
                    end if;
                    
                    data_out  <= shift_right(exp_reg, 1);
                    busy <= '0';
                    
                end if;
            end if;
        end if;
    end process;
end Behavioral;