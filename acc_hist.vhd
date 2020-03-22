-- acc_hist.vhd

-- This file was auto-generated as a prototype implementation of a module
-- created in component editor.  It ties off all outputs to ground and
-- ignores all inputs.  It needs to be edited to make it do something
-- useful.
-- 
-- This file will not be automatically regenerated.  You should check it in
-- to your version control system if you want to keep it.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity acc_hist is
	port (
		clk                     : in  std_logic                     := '0';             --       clock.clk
		reset                   : in  std_logic                     := '0';             --       reset.reset
		avs_control_address     : in  std_logic                     := '0';             -- avs_control.address
		avs_control_read        : in  std_logic                     := '0';             --            .read
		avs_control_readdata    : out std_logic_vector(31 downto 0);                    --            .readdata
		avs_control_write       : in  std_logic                     := '0';             --            .write
		avs_control_writedata   : in  std_logic_vector(31 downto 0) := (others => '0'); --            .writedata
		avs_control_waitrequest : out std_logic;                                        --            .waitrequest
		asi_in_data             : in  std_logic_vector(7 downto 0)  := (others => '0'); --      asi_in.data
		asi_in_ready            : out std_logic;                                        --            .ready
		asi_in_valid            : in  std_logic                     := '0';             --            .valid
		asi_in_eop              : in  std_logic                     := '0';             --            .endofpacket
		asi_in_sop              : in  std_logic                     := '0';             --            .startofpacket
		aso_out_data            : out std_logic_vector(15 downto 0);                    --     aso_out.data
		aso_out_ready           : in  std_logic                     := '0';             --            .ready
		aso_out_valid           : out std_logic;                                        --            .valid
		aso_out_eop             : out std_logic;                                        --            .endofpacket
		aso_out_sop             : out std_logic;                                        --            .startofpacket
		aso_out_empty           : out std_logic                                         --            .empty
	);
end entity acc_hist;

architecture rtl of acc_hist is

component ram_controler is 
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
end component;

component diff is
	port
	(
		-- Input ports
		
		input	: in  std_logic;
		clk	: in std_logic;
		reset : in std_logic;
		-- Output ports
		
		output	: out std_logic
		
	);
end component;

	signal control_reg : std_logic_vector(31 downto 0);
	signal status_reg : std_logic_vector (31 downto 0);
	signal control_strobe : std_logic;
	--signal status_strobe  : std_logic;
	constant CONTROL_ADDR : std_logic := '1';
	constant STATUS_ADDR  : std_logic := '0';

	signal control_waitrq : std_logic;

	type state is (idle, 		-- waiting for input data, no valid data in output register, no valid data in input register
				  wait_input,
				  process_state, -- waiting for input to be processed, valid data in input register, no valid data in output register
				  wait_output,
				  output_read); -- waiting for someone to receive data from output register, valid data in output register, no valid data in input register)

	signal current_state, next_state : state;

	signal input_sample : std_logic_vector(7 downto 0);
	signal output_sample : std_logic_vector(15 downto 0);
	signal data_ram	: std_logic_vector(15 downto 0);
	signal wren_ram : std_logic;
	signal adrr_ready_ram : std_logic;
	signal reset_ram : std_logic;
	signal clear_ram : std_logic;
	signal inc_ram : std_logic;
	signal in_ready_ram : std_logic;
	signal out_valid_ram : std_logic;
	signal q_ram : std_logic_vector (15 downto 0);
	signal c_nop : unsigned (18 downto 0);	
	signal c_run : std_logic;
	signal c_res : std_logic;
	signal c_run_diff : std_logic;
	
	signal status_reg_state : std_logic_vector (2 downto 0);
	
	signal s_nopp : natural range 0 to 262144;
	signal s_cnt  : natural range 0 to 256;
	
	--signal int_asi_in_ready : std_logic;
	
	-- treba adrese da se rese u output masini stanja
	-- i za input masinu stanja.

begin
RAM: ram_controler port map(
		address => input_sample,
		clk => clk,
		data => data_ram,
		wren => wren_ram,
		addr_ready => adrr_ready_ram,
		reset => reset_ram,
		clear => clear_ram,
		inc => inc_ram,
		in_ready => in_ready_ram,
		out_valid => out_valid_ram,
		q => q_ram
);

DIFF_C_RUN: diff port map(
		input => c_run,
		clk => clk,
		reset => reset,
		output => c_run_diff
);

	control_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = CONTROL_ADDR) else '0';
	reset_ram <= c_res or reset;
	--aso_out_data <= output_sample;
	
	write_control_reg : process(clk, reset) is 
	begin
		if (reset = '1') then
			control_reg <= (others => '0');
			c_run <= '0';
			c_res <= '0';
			clear_ram <= '0';
			c_nop <= (others => '0');
		elsif(rising_edge(clk)) then
			if (control_strobe = '1') then
				control_reg(31 downto 0) <= avs_control_writedata;
				c_run <= control_reg(31);
				c_res <= control_reg(30);
				clear_ram <= control_reg(29);
				c_nop <= unsigned(control_reg(18 downto 0));
			end if;
		end if;
		
	end process;

	read_control_reg : process(clk, reset) is
	begin

		if (reset = '1' or c_res = '1') then
			avs_control_readdata <= x"ffffffff";
			control_waitrq <= '1';			
		elsif(rising_edge(clk)) then
			control_waitrq <= '1';
			if (avs_control_read = '1') then
				control_waitrq <= '0';
				if (avs_control_address = CONTROL_ADDR) then
					avs_control_readdata <= control_reg;
				else
					avs_control_readdata <= status_reg;
				end if;
			end if;
		end if;
		
	end process;

	avs_control_waitrequest <= avs_control_read and control_waitrq;
	
	process_sample : process(clk, reset)
	begin
		if (reset = '1'  or c_res = '1') then
			output_sample <= x"BEEF";
		elsif (rising_edge(clk)) then
			if ((current_state = wait_output) and aso_out_ready = '1') then
				output_sample (15 downto 0) <= q_ram;
			end if;
		end if;
	end process;
	
	aso_out_data <= output_sample;
	
	read_sample : process(clk, reset)
	begin
		if (reset = '1'  or c_res = '1') then
			input_sample <= x"00";
		elsif (rising_edge(clk)) then
			if (in_ready_ram = '1' and asi_in_valid = '1') then
				input_sample <= asi_in_data;
			end if;
		end if;
	end process;
	
	control_fsm: process(clk, reset)
	begin
		if (reset = '1'  or c_res = '1') then
			current_state <= idle;
		elsif (rising_edge(clk)) then
			current_state <= next_state;
		end if;
	end process;	
	
	streaming_protocol: process(current_state, asi_in_valid, aso_out_ready, c_run_diff, s_cnt)
	begin
		case current_state is

			when idle =>		
				if (c_run_diff = '1') then	
					next_state <= wait_input;
				else
					next_state <= idle;
				end if;

			when wait_input =>
				if (s_nopp = c_nop) then
					next_state <= wait_output;
				elsif (asi_in_valid = '1') then
					next_state <= process_state;
				else
					next_state <= wait_input;
				end if;
				
			when process_state =>
				next_state <= wait_input;
								
			when wait_output =>
				if (s_cnt = 256) then
					next_state <= idle;
				elsif (aso_out_ready = '1') then
					next_state <= output_read;
				end if;
				
			when output_read =>
				next_state <= wait_output;
				
		end case;
	end process;	
	
	status_reg_control: process(clk, reset) is
	begin
		if (reset = '1' or c_res = '1') then
			status_reg <= (others => '0');
		elsif (rising_edge(clk)) then
			status_reg(31 downto 29) <= status_reg_state;
			status_reg(27 downto 9) <= std_logic_vector(to_unsigned(s_nopp, 19));
			status_reg(8 downto 0) <= std_logic_vector(to_unsigned(s_cnt, 9));		
		end if;
	end process;
	
	output_process: process(current_state) is
	begin
		case(current_state) is			
			when idle =>
				asi_in_ready <= '0';
				inc_ram <= '0';
				s_nopp <= 0;
				s_cnt <= 0;
				
				status_reg_state <= "000";
				
			when wait_input =>
				asi_in_ready <= in_ready_ram;
				inc_ram <= '0';
				
				status_reg_state <= "001";
			
			when process_state =>	
			
				asi_in_ready <= in_ready_ram;
				inc_ram <= '1';
				s_nopp <= s_nopp + 1;
				
				status_reg_state <= "010";
	
			when wait_output =>
				asi_in_ready <= '0';
				inc_ram <= '0';
				aso_out_valid <= out_valid_ram;
				adrr_ready_ram <= '0';
				
				status_reg_state <= "011";
				
			when output_read =>
				asi_in_ready <= '0';
				inc_ram <= '0';
				aso_out_valid <= out_valid_ram;
				adrr_ready_ram <= '1';
				s_cnt <= s_cnt + 1;
				
				status_reg_state <= "100";

		end case;
	end process;
	
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty<= '0';

end architecture rtl; -- of acc_hist

