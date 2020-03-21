library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ram_controler is 
	port
	(
		address		: in std_logic_vector (7 DOWNTO 0);
		clk			: in std_logic;
		data			: in std_logic_vector (15 DOWNTO 0);
		wren			: in std_logic;
		addr_ready	: in std_logic;
		reset			: in std_logic;
		clear			: in std_logic;
		inc			: in std_logic;
		in_ready		: out std_logic;
		out_valid	: out std_logic;
		q				: out std_logic_vector (15 DOWNTO 0)	
	);
end ram_controler;

architecture ram_controler_arch of ram_controler is

component ram_8 is
	port
	(
		address		: in std_logic_vector (7 DOWNTO 0);
		clock			: in std_logic;
		data			: in std_logic_vector (15 DOWNTO 0);
		wren			: in std_logic;
		q				: out std_logic_vector (15 DOWNTO 0)
	);
end component;

component diff is
	port
	(
		
		input	: in  std_logic;
		clk	: in std_logic;
		reset : in std_logic;
		
		output	: out std_logic
		
	);
end component;

signal reg_address     : std_logic_vector (7 downto 0);
signal out_q       : std_logic_vector (15 downto 0);
signal reg_data	 : std_logic_vector(15 downto 0);
constant ADDRESS_LIMIT : natural := 256;
signal wren_help : std_logic;
signal inc_tmp : std_logic;
signal addr_ready_tmp : std_logic;
signal address_cnt : natural range 0 to ADDRESS_LIMIT;

type state_type is (ready, inc1_state, inc2_state,inc3_state,read_temp, init_state, tmp_state, wr_state, cnt_state);
signal state_reg, next_state : state_type;

begin
RAM: ram_8 port map(
		address => reg_address,
		clock => clk,
		data => reg_data,
		wren => wren_help,
		q => out_q
	);	
	
DIFF_1: diff port map(
		input => inc,
		clk => clk,
		reset => reset,
		output => inc_tmp	
	);
	
DIFF_2: diff port map(
		input => addr_ready,
		clk => clk,
		reset => reset,
		output => addr_ready_tmp
	);

state_transition: process (clk) is
begin
	if (reset = '1') then
		state_reg <= ready;
	elsif (rising_edge(clk)) then
		state_reg <= next_state;
	end if;	
end process;

out_valid <= '1' when (next_state = ready) and (state_reg = ready) else 
				 '0';
				 
in_ready <= '1' when (next_state = ready) and (state_reg = ready) else
				'0';

next_state_logic: process (state_reg, clear, inc_tmp, addr_ready_tmp) is
begin
	case (state_reg) is
		when ready =>
			if (clear = '1') then
				next_state <= init_state;
			elsif (inc_tmp = '1') then
				next_state <= inc1_state;
			elsif (addr_ready_tmp = '1') then
				next_state <= read_temp;
			else
				next_state <= state_reg;	
			end if;
		
		when inc1_state =>
		
			next_state <= inc2_state;
		
		when inc2_state =>
		
			next_state <= inc3_state;
			
		when inc3_state =>
		
			next_state <= ready;
			
		when read_temp =>
			
			next_state <= ready;
			
		when init_state =>
			
			next_state <= tmp_state;			
		
		when tmp_state =>

			next_state <= wr_state;
		
		when wr_state =>
		
			next_state <= cnt_state;
		
		when cnt_state =>		
		
			if address_cnt = ADDRESS_LIMIT then
				next_state <= ready;
			else
				next_state <= tmp_state;
			end if;	
			
	end case;
end process;

output_logic: process (state_reg, wren, address, data, out_q) is
begin
	case (state_reg) is
		when ready =>
			wren_help <= wren;
			reg_address <= address;
			reg_data <= data;
			address_cnt <= 0;
			q <= out_q;
--			in_ready <= '1';
--			out_valid <= '1';

		when inc1_state =>
			wren_help <= '0';
			reg_data <= out_q;
			reg_address <= address;
			address_cnt <= 0;
			q <= out_q;
--			in_ready <= '0';
--			out_valid <= '0';
			
		when inc2_state =>
			wren_help <= '1';
			reg_address <= address;
			reg_data <= std_logic_vector( unsigned(out_q) + 1 );
			address_cnt <= 0;
			q <= out_q;
--			in_ready <= '0';
--			out_valid <= '0';
		
		when inc3_state =>
			wren_help <= '0';
			reg_address <= address;
			reg_data <= out_q;
			address_cnt <= 0;
			q <= out_q;
--			in_ready <= '0';
--			out_valid <= '0';
		
		when read_temp =>
		
			wren_help <= '0';
			reg_address <= address;
			reg_data <= out_q;
			address_cnt <= 0;
			q <= out_q;
--			in_ready <= '0';
--			out_valid <= '0';
		
		when init_state =>
		
			wren_help <= '0';
			reg_address<= x"00";
			reg_data <= x"0000";
			q <= x"0000";
			address_cnt <= 0;
--			in_ready <= '0';
		
		when tmp_state =>

			wren_help <= '1';
			reg_address <= reg_address;
			reg_data <= x"0000";
			q <= x"0000";
			address_cnt <= address_cnt;
--			in_ready <= '0';
		
		when wr_state =>
		
			wren_help <= '1';
			reg_address <= reg_address;
			reg_data <= x"0000";
			q <= x"0000";
			address_cnt <= address_cnt;
--			in_ready <= '0';
		
		when cnt_state =>
		
			wren_help <='0';
			if (address_cnt = 256) then
				reg_address <= x"00";
				address_cnt <= 0;
			else
				address_cnt <= address_cnt + 1;
				reg_address <= std_logic_vector( unsigned(reg_address) + 1 );
			end if;
			reg_data <= x"0000";
			q <= x"0000";
--			in_ready <= '0';
			
	end case;

end process;


end ram_controler_arch;