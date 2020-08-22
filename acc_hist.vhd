-- acc_hist.vhd

-- This file represents hardware solution for caluculating histogram of input image.
-- Inputs are pixels of input image, where the output is calculated histogram. Module
-- consists of two SGDMA and 1 memory mapped interface. One SGDMA is memory to stream,
-- whose purpose is to transfer pixels of input image to module. Second SGDMA transfers
-- histogram from module back to software. Memory mapped register consists out of five
-- different registers: control, status and three more 8 bit register which combined
-- represent number of pixels to be processed.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity acc_hist is
	port (
		clk                     : in  std_logic                     := '0';             --      clock.clk
		reset                   : in  std_logic                     := '0';             --      reset.reset
		avs_control_address     : in  std_logic_vector(2 downto 0)  := (others => '0'); -- 		avs_control.address
		avs_control_read        : in  std_logic                     := '0';             --      	.read
		avs_control_readdata    : out std_logic_vector(7 downto 0);                     --      	.readdata
		avs_control_write       : in  std_logic                     := '0';             --      	.write
		avs_control_writedata   : in  std_logic_vector(7 downto 0)  := (others => '0'); --      	.writedata
		avs_control_waitrequest : out std_logic;                                        --      	.waitrequest
		asi_in_data             : in  std_logic_vector(7 downto 0)  := (others => '0'); --      asi_in.data
		asi_in_ready            : out std_logic;                                        --      	.ready
		asi_in_valid            : in  std_logic                     := '0';             --       	.valid
		asi_in_eop              : in  std_logic                     := '0';             --      	.endofpacket
		asi_in_sop              : in  std_logic                     := '0';             --     		.startofpacket
		aso_out_data            : out std_logic_vector(15 downto 0);                    --     	aso_out.data
		aso_out_ready           : in  std_logic                     := '0';             --         	.ready
		aso_out_valid           : out std_logic;                                        --          .valid
		aso_out_eop             : out std_logic;                                        --          .endofpacket
		aso_out_sop             : out std_logic;                                        --          .startofpacket
		aso_out_empty           : out std_logic                                         --          .empty
	);
end entity acc_hist;

architecture rtl of acc_hist is

	component ram_8 is
		PORT
		(
			address			: in STD_LOGIC_VECTOR (7 DOWNTO 0);
			clock			: in STD_LOGIC;
			data			: in STD_LOGIC_VECTOR (15 DOWNTO 0);
			wren			: in STD_LOGIC ;
			q				: out STD_LOGIC_VECTOR (15 DOWNTO 0)
		);
	end component;

	--	CONTROL_REG
	-- Can be read and written to.
	--	____________________________
	--	| c_run | c_res | reserved |
	--	|   7   |   6   |   5..0   |

	signal control_reg : std_logic_vector(7 downto 0) := x"00";
	
	--	STATUS_REG
	-- Can only be read from
	--	 ______________________________
	--	| reserved | status_reg_state |
	--	|   7..3   |       2..0       |

	signal status_reg : std_logic_vector (7 downto 0) := x"00";
	

	
	-- adresa statusnog registra
	constant STATUS_ADDR  		: std_logic_vector(2 downto 0) := "000";
	
	-- adresa kontrolnog registra
	constant CONTROL_ADDR 		: std_logic_vector(2 downto 0) := "001";
	
	constant NOP_LOW_ADDR		: std_logic_vector(2 downto 0) := "010";
	constant NOP_MIDDLE_ADDR	: std_logic_vector(2 downto 0) := "011";
	constant NOP_HIGH_ADDR		: std_logic_vector(2 downto 0) := "100";
	
	signal nop_low	: std_logic_vector ( 7 downto 0) := x"00";
	signal nop_middle : std_logic_vector (7 downto 0 ) := x"00";
	signal nop_high : std_logic_vector ( 7 downto 0) := x"00";
	
	-- Signal strobes: active when register is addressed and write signal is active
	signal control_strobe : std_logic := '0';
	signal nop_low_strobe : std_logic := '0';
	signal nop_middle_strobe : std_logic := '0';
	signal nop_high_strobe : std_logic := '0';

	-- Needed so it can be properly read from MM registers
	signal control_waitrq : std_logic;
	
	signal out_mux : std_logic_vector (7 downto 0);

	type state is (idle, 			-- this state must be entered before any processing, so RAM can be reset				"000"
					reset_ram,		-- RAM reset state 																		"001"
					wait_input,		-- waits for input pixel to be valid													"010"
					wait_state,		-- waits for value in output RAM buffer to be valid										"011"
					process_state,	-- output buffer of RAM is valid in this state, update counters							"100"
					wait_output,	-- waits for stream to memory SGDMA to be ready to transmit data back to software		"101"
					output_read,	-- once valid, write to output SGDMA buffer												"110"
					done); 			-- processing is complete																"111"

	signal current_state, next_state : state;

	-- Pixel of input image.
	signal input_sample : std_logic_vector(7 downto 0);
	
	-- Output sample, used for output SGDMA.
	signal output_sample : std_logic_vector(15 downto 0);
	
	-- This is value that is sent to data bus of RAM.
	signal data_ram	: std_logic_vector(15 downto 0) := x"0000";
	
	-- Write enable for RAM.
	signal wren_ram : std_logic;
	
	-- Output RAM buffer.
	signal q_ram : std_logic_vector (15 downto 0);
	
	-- Software run bit.
	signal c_run : std_logic;
	
	-- Software reset bit.
	signal c_res : std_logic;
	
	-- State in which machine is in.
	signal status_reg_state : std_logic_vector (2 downto 0);
	
	-- Number of processed pixels.
	signal s_nopp : integer range 0 to 262144 := 0;
	
	-- Needed to be properly read from MM registers.
	signal wait_signal : std_logic;
	
	-- Used for RAM address control.
	signal address_ram : std_logic_vector (7 downto 0);
	
	-- address_ram is controled through this signal when in reset_ram or wait_output.
	signal ram_address : integer range 0 to 255 := 0;
	
	-- Combined from nop_low, nop_middle, nop_high, represents total number of pixels to be processed.
	signal s_nop : unsigned (18 downto 0);	
	
	-- Used as wait signal for valid value in RAM output buffer.
	signal small_cnt : integer range 0 to 2 := 0;
	
	-- Control of asi_in_ready.
	signal int_asi_in_ready : std_logic := '0';
	
	-- Control of asi_in_data.
	signal int_asi_in_data : std_logic_vector ( 7 downto 0) := (others => '0');
	
	
begin

	-- 256x8 bit RAM
	RAM_MEMORY:ram_8
	port map
	(
		address =>	address_ram,
		clock	=>	clk,
		data	=>	data_ram,
		wren	=>	wren_ram,
		q		=>	q_ram
	);

	-- Strobe control.
	control_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = CONTROL_ADDR) else '0';
	nop_low_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_LOW_ADDR) else '0';
	nop_middle_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_MIDDLE_ADDR) else '0';
	nop_high_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_HIGH_ADDR) else '0';
	
	-- Output multiplexer control.
	out_mux <= control_reg when (avs_control_address = CONTROL_ADDR) else
			nop_low when (avs_control_address = NOP_LOW_ADDR) else
			nop_middle when (avs_control_address = NOP_MIDDLE_ADDR) else
			nop_high when (avs_control_address = NOP_HIGH_ADDR) else
			status_reg when (avs_control_address = STATUS_ADDR) else
			x"AA";
	
	-- Combination of pixel buffer, result is total number of pixels passed to module.
	s_nop (18 downto 16) <= unsigned(nop_high(2 downto 0));
	s_nop (15 downto 8)  <= unsigned(nop_middle);
	s_nop (7 downto 0)	<= unsigned(nop_low);
	
	-- Software run and reset assign.
	c_run <= control_reg(7);
	c_res <= control_reg(6);
	
	-- Status assign
	status_reg(2 downto 0) <= status_reg_state;
	
	-- Output value of SGMDA assign.
	aso_out_data <= q_ram;

	-- Process which controls reading from MM registers.
	read_regs: process(clk, reset)
	begin
		if (reset = '1' or c_res = '1') then
			wait_signal <= '1';
		elsif (rising_edge(clk)) then
			avs_control_readdata <= (others => '0');
			wait_signal <= '1';
			if (avs_control_read = '1') then
				wait_signal <= '0';
				avs_control_readdata <= out_mux;
			end if;	
		end if;
	end process;
	
	-- Writing to MM registers control
	write_reg_process : process(clk, reset, avs_control_write) is 
	begin
		if (reset = '1' or c_res = '1') then
			nop_low <= (others => '0');
			nop_middle <= (others => '0');
			nop_high <= (others => '0');
		elsif(rising_edge(clk)) then
			if (nop_low_strobe = '1') then
				nop_low <= avs_control_writedata;
			end if;	
			if (nop_middle_strobe = '1') then
				nop_middle <= avs_control_writedata;
			end if;	
			if (nop_high_strobe = '1') then
				nop_high <= avs_control_writedata;
			end if;
		end if;
	end process;
	
	write_control_reg : process(clk, reset, avs_control_write) is
	begin
		if (reset = '1' or c_res = '1') then
			control_reg <= (others => '0');
		elsif(rising_edge(clk)) then
			if (control_strobe = '1') then
				control_reg <= avs_control_writedata;
			end if;
		end if;	
	end process;
	
	-- Moore machine state.
	control_fsm: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			current_state <= idle;
		elsif (rising_edge(clk)) then
			current_state <= next_state;
		end if;
	end process;	
	
	-- ram_address counter control.
	ram_address_counter_control: process(clk, reset, c_res)
	begin 
		if (reset = '1' or c_res = '1') then
			ram_address <= 0;
		elsif (rising_edge(clk)) then
			if (current_state = reset_ram or (current_state = wait_output and aso_out_ready = '1' )) then
				ram_address <= ram_address + 1;
			elsif (current_state = process_state or current_state = wait_input or current_state =  idle) then
				ram_address <= 0;
			end if;
		end if;
	end process;
	
	address_ram_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			address_ram <= x"00";
		elsif (rising_edge(clk)) then
			if (current_state = wait_input) then
				address_ram <= asi_in_data;
			elsif (current_state = reset_ram or current_state = wait_output or current_state = output_read) then
				address_ram <= std_logic_vector(to_unsigned(ram_address, 8));
			end if;
		end if;
	end process;
	
	-- Control of when pixel is processed.
	s_nopp_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			s_nopp <= 0;
			small_cnt <= 0;
		elsif(rising_edge(clk)) then
			if (current_state = process_state) then
				s_nopp <= s_nopp + 1;
				small_cnt <= 0;
			elsif (current_state = wait_state or current_state = output_read) then
				small_cnt <= small_cnt + 1;
			end if;	
		end if;
	end process;
	
	-- RAM data control, all zeroes in reset state, or add one to current value of output buffer in process_state
	data_ram_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			data_ram <= x"0000";
		elsif(rising_edge(clk)) then
			if (current_state = reset_ram) then
				data_ram <= x"0000";
			elsif (current_state = process_state) then
				data_ram <= std_logic_vector(to_unsigned((to_integer(unsigned(q_ram)) + 1), 16));	
			end if;
		end if;
	end process;
	
	wren_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			wren_ram <= '0';
		elsif (rising_edge(clk)) then
			if (current_state = reset_ram or current_state = process_state) then
				wren_ram <= '1';
			else
				wren_ram <= '0';
			end if;	
		end if;
	end process;
	
	asi_in_ready <= int_asi_in_ready;
	
	-- Machine state control.
	streaming_protocol: process(current_state, asi_in_valid, aso_out_ready, c_run)
	begin
		case current_state is
			when idle =>		
				if (c_run = '1') then
					next_state <= reset_ram;
				else
					next_state <= idle;
				end if;
				
			when reset_ram =>
				if (address_ram = x"ff") then	
					next_state <= wait_input;
				else
					next_state <= reset_ram;
				end if;
		
			when wait_input =>
				if (s_nop = to_unsigned(s_nopp, 19)) then
					next_state <= wait_output;
				elsif (asi_in_valid = '1') then
					next_state <= wait_state;
				else
					next_state <= wait_input;
				end if;
			
			when wait_state =>
				if (small_cnt = 2) then
					next_state <= process_state;
				else
					next_state <= wait_state;
				end if;	
				
			when process_state =>	
					next_state <= wait_input;

			when wait_output =>
				if (ram_address = 255 and aso_out_ready = '1') then
					next_state <= done;
				elsif (aso_out_ready = '1') then
					next_state <= output_read;
				else
					next_state <= wait_output;
				end if;
				
			when output_read =>
				if (small_cnt = 2) then
					next_state <= wait_output;
				else
					next_state <= output_read;
				end if;	

			when done =>
				next_state <= done;
				
		 end case;
	 end process;
	
	-- Output machine state.
	output_process: process(current_state) is
	begin
		case(current_state) is			
			when idle =>
				status_reg_state <= "000";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				
			when reset_ram =>
				status_reg_state <= "001";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				
			when wait_input =>
				status_reg_state <= "010";
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';
				
			when wait_state =>	
				status_reg_state <= "011";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';	
			
			when process_state =>	
				status_reg_state <= "100";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
	
			when wait_output =>				
				status_reg_state <= "101";
				aso_out_valid <= '1';
				int_asi_in_ready <= '0';
				
			when output_read =>	
				status_reg_state <= "110";
				aso_out_valid <='0';
				int_asi_in_ready <= '0';
			
			when done =>
				status_reg_state <= "111";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';	
		end case;
	end process;
	
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty<= '0';
	
	-- Needed to properly read from MM registers.
	avs_control_waitrequest <= avs_control_read and wait_signal;

end architecture rtl; -- of acc_hist
