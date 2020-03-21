library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity diff is
	port
	(
		-- Input ports
		
		input	: in  std_logic;
		clk	: in std_logic;
		reset : in std_logic;
		-- Output ports
		
		output	: out std_logic
		
	);
end diff;

-- Library Clause(s) (optional)
-- Use Clause(s) (optional)

architecture diff_arch of diff is

type state_type is (idle, wait_state);
signal state_reg, next_state : state_type;

begin

state_transition : process(clk,reset) is
begin
	if (reset = '1') then
		state_reg <= idle;
	elsif(rising_edge(clk)) then
		state_reg <= next_state;
	end if;
end process;



next_state_logic : process (state_reg, input) is 
begin
	
	case (state_reg) is
	
		when idle =>
			if(input = '1') then
				next_state <= wait_state;
			else
				next_state <= state_reg;
			end if;	
			
		when wait_state =>
			if (input = '1') then
				next_state <= state_reg;
			else	
				next_state <= idle;
			end if;
	end case;
	
end process;

output_logic : process(state_reg, input) is
begin

	case (state_reg) is
		
		when idle =>
		
			if (reset = '1') then
				output <= '0';
			elsif (input = '1') then
				output <= '1';
			else
				output <= '0';
			end if;
		
		when wait_state =>
			
			output <='0';
		
	end case;
	
end process;

end diff_arch;
