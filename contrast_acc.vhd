-- contrast_acc.vhd

-- This file represents hardware accelerator which purpose is to map intensity of pixeles
-- coming from input image to output image. Mapping is defined through array of 256 elements
-- of cumulative histogram which is stored in RAM. Module consists of two state machines,
-- one for configuration and one for process of input image pixels. During configuration state
-- cumulative histogram calculated in software is passed to module with memory to stream interface
-- and those values are stored as array of 8-bit elements in RAM. When configuration is done,
-- module is ready to enter process state (waits for software bit to be set) in which he maps 
-- input image pixels to output image using those values stored in RAM (acts as LUT). During
-- process state, output image pixels are returned to memory through stream to memory interface.
-- Module also has Memory Mapped interface which consists of control, and status register.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity contrast_acc is
	port (
		clk                     : in  std_logic                    := '0';             --       clock.clk
		reset                   : in  std_logic                    := '0';             --       reset.reset
		avs_control_address     : in  std_logic_vector(2 downto 0) := (others => '0'); -- 		avs_control.address
		avs_control_read        : in  std_logic                    := '0';             --            .read
		avs_control_readdata    : out std_logic_vector(7 downto 0);                    --            .readdata
		avs_control_write       : in  std_logic                    := '0';             --            .write
		avs_control_writedata   : in  std_logic_vector(7 downto 0) := (others => '0'); --            .writedata
		avs_control_waitrequest : out std_logic;                                       --            .waitrequest
		asi_in_data             : in  std_logic_vector(7 downto 0) := (others => '0'); --      	asi_in.data
		asi_in_ready            : out std_logic;                                       --            .ready
		asi_in_valid            : in  std_logic                    := '0';             --            .valid
		asi_in_sop              : in  std_logic                    := '0';             --            .startofpacket
		asi_in_eop              : in  std_logic                    := '0';             --            .endofpacket
		aso_out_data            : out std_logic_vector(7 downto 0);                    --     	aso_out.data
		aso_out_ready           : in  std_logic                    := '0';             --            .ready
		aso_out_valid           : out std_logic;                                       --            .valid
		aso_out_empty           : out std_logic;                                       --            .empty
		aso_out_sop             : out std_logic;                                       --            .startofpacket
		aso_out_eop             : out std_logic                                        --            .endofpacket
	);
end entity contrast_acc;

architecture rtl of contrast_acc is

-- This component is 256x8 RAM where cumulative histogram values are stored.
component lut is
	port
	(
		address		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q			: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
end component;

	--	CONTROL_REG
	--  Control register can be read from, and written to.
	--	__________________________________________________
	--	| c_run | c_res | c_conf   | c_process |reserved |
	--	|-------|-------|----------|-----------|---------|
	--	|   7   |   6   |   5      |     4     |   3..0  |
	--	--------------------------------------------------
	signal control_reg : std_logic_vector(7 downto 0) := x"00";
	
	--	STATUS_REG
	--  Status register can only be read from, and is used to signal software
	--  in which state machine is.
	--	_____________________________________________________
	--	| reserved | state_machine_state | status_reg_state |
	--	|----------|---------------------|------------------|
	--	|   7..6   |		5..2		 |       1..0       |
	--	---------------------------------|-------------------
	signal status_reg : std_logic_vector (7 downto 0) := x"00";
	
	-- oznacava da je kontrolni registar adresiran, i da je avs_control_write bit aktivan
	signal control_strobe : std_logic;
	
	-- adresa statusnog registra
	constant STATUS_ADDR  		: std_logic_vector(2 downto 0) := "000";
	
	-- adresa kontrolnog registra
	constant CONTROL_ADDR 		: std_logic_vector(2 downto 0) := "001";
	
	type state is (idle, 			
				configuration_wait_input,					-- waits for cumulative histogram array elements
				configuration_wait_state,					-- waits for value in output buffer of RAM to be valid
				configuration_process,						-- respective counter values are updated in this state
				configuration_done,							-- configuration written to RAM
				processing_wait_input,						-- waits for input image pixels
				process_input,								-- waits for value in output buffer of RAM to be valid
				wait_output,								-- waits for stream to memory SGMDA to be ready to receive valid value
				done										-- done with processing
				); 	
	signal current_state, next_state : state;
	
	-- Number of pixels register addresses 
	constant NOP_LOW_ADDR		: std_logic_vector(2 downto 0) := "010";
	constant NOP_MIDDLE_ADDR	: std_logic_vector(2 downto 0) := "011";
	constant NOP_HIGH_ADDR		: std_logic_vector(2 downto 0) := "100";
	
	-- Number of pixels registers
	signal nop_low	: std_logic_vector ( 7 downto 0) := x"00";
	signal nop_middle : std_logic_vector (7 downto 0 ) := x"00";
	signal nop_high : std_logic_vector ( 7 downto 0) := x"00";
	
	-- Signals that number of pixels registers are addressed, and write signal is active
	signal nop_low_strobe : std_logic := '0';
	signal nop_middle_strobe : std_logic := '0';
	signal nop_high_strobe : std_logic := '0';

	-- Signal which is needed in order to read from registers.
	signal control_waitrq : std_logic;
	
	-- Output register multiplexer for MM registers.
	signal out_mux : std_logic_vector (7 downto 0);
	
	-- Status register bits declarations.
	signal status_reg_state : std_logic_vector (1 downto 0);
	signal state_machine_state : std_logic_vector (3 downto 0);
	
	-- Software run bit.
	signal c_run : std_logic;
	
	-- Software reset bit.
	signal c_res : std_logic;
	
	-- Software start configuration bit.
	signal c_conf : std_logic;
	
	-- Software start processing bit.
	signal c_process : std_logic;
	
	-- Number of finished pixels.
	signal s_nopp : integer range 0 to 262144 := 0;
	
	-- Total number of pixels, taken from MM registers.
	signal s_nop : unsigned (18 downto 0);
	
	-- Signal used for reading from MM registers.
	signal wait_signal : std_logic;
	
	-- RAM address.
	signal address_lut : std_logic_vector (7 downto 0) := x"00";
	
	-- RAM data.
	signal data_lut : std_logic_vector ( 7 downto 0) := x"00";
	
	-- RAM wren.
	signal wren_lut : std_logic := '0';
	
	-- RAM output buffer.
	signal q_lut : std_logic_vector ( 7 downto 0) := x"00";
	
	-- Signal used for RAM address control.
	signal lut_address : integer range 0 to 255 := 0;
	
	-- Signal used as wait for RAM output to be valid.
	signal small_cnt : integer range 0 to 2 := 0;
	
	-- Internal ready signal for input SGDMA.
	signal int_asi_in_ready : std_logic := '0';
	
	-- Used for aso_out_data control .
	signal output_sample : std_logic_vector (7 downto 0):= x"00";

begin	

	-- RAM bindings.
	LUT_MEMORY:lut
	port map
	(
		address =>	address_lut,
		clock	=>	clk,
		data	=>	data_lut,
		wren	=>	wren_lut,
		q		=>	q_lut
	);
	
	-- Strobe definitions.
	control_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = CONTROL_ADDR) else '0';
	nop_low_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_LOW_ADDR) else '0';
	nop_middle_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_MIDDLE_ADDR) else '0';
	nop_high_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_HIGH_ADDR) else '0';
	
	-- Output multiplexer definitions.
	out_mux <= control_reg when (avs_control_address = CONTROL_ADDR) else
			nop_low when (avs_control_address = NOP_LOW_ADDR) else
			nop_middle when (avs_control_address = NOP_MIDDLE_ADDR) else
			nop_high when (avs_control_address = NOP_HIGH_ADDR) else
			status_reg when (avs_control_address = STATUS_ADDR) else
			x"AA";
	
	-- Total number of pixels are stored in this buffer.
	s_nop (18 downto 16) <= unsigned(nop_high(2 downto 0));
	s_nop (15 downto 8)  <= unsigned(nop_middle);
	s_nop (7 downto 0)	<= unsigned(nop_low);
	
	-- Control register bits definitions.
	c_run <= control_reg(7);
	c_res <= control_reg(6);
	c_conf <= control_reg(5);
	c_process <= control_reg(4);
	
	-- Status register bits definitions.
	status_reg(1 downto 0) <= status_reg_state;
	status_reg(5 downto 2) <= state_machine_state;
	
	-- Control of asi_in_ready is done through int_asi_in_ready.
	asi_in_ready <= int_asi_in_ready;
	
	-- Control of aso_out_data is done through output_sample.
	aso_out_data <= output_sample;
	
	-- Process which controls reading from MM registers
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
	
	-- Process which controls writing to MM registers
	write_reg_process : process(clk, reset, avs_control_write) is 
	begin
		if (reset = '1' or c_res = '1') then
			nop_low <= (others => '0');
			nop_middle <= (others => '0');
			nop_high <= (others => '0');
			control_reg <= (others => '0');
		elsif(rising_edge(clk)) then
			if (nop_low_strobe = '1') then
				nop_low <= avs_control_writedata;	
			elsif (nop_middle_strobe = '1') then
				nop_middle <= avs_control_writedata;
			elsif (nop_high_strobe = '1') then
				nop_high <= avs_control_writedata;
			elsif (control_strobe = '1') then
				control_reg <= avs_control_writedata;
			end if;	
		end if;
	end process;
	
	-- RAM address counter for configuration state.
	lut_address_counter_control: process(clk, reset, c_res)
	begin 
		if (reset = '1' or c_res = '1') then
			lut_address <= 0;
		elsif (rising_edge(clk)) then
			if (current_state = configuration_process) then
				lut_address <= lut_address + 1;
			end if;
		end if;
	end process;
	
	-- RAM address control.
	address_lut_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			address_lut <= x"00";
		elsif (rising_edge(clk)) then
			if (current_state = configuration_process or current_state = configuration_wait_input or current_state = configuration_wait_state) then
				address_lut <= std_logic_vector(to_unsigned(lut_address, 8));
			elsif (current_state = idle or current_state = configuration_done) then
				address_lut <= x"0C";
			elsif (asi_in_valid = '1' and int_asi_in_ready = '1' ) then
				address_lut <= asi_in_data;
			end if;
		end if;
	end process;

	-- Process which controls counter needed for valid output of RAM, after the address was changed ( 2 ticks ).
	small_cnt_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			small_cnt <= 0;
		elsif(rising_edge(clk)) then
			if (current_state = configuration_wait_state or current_state = process_input) then
				small_cnt <= small_cnt + 1;
			elsif (current_state = configuration_process) then
				small_cnt <= 0;	
			end if;	
		end if;
	end process;
	
	-- Number of processed pixels control
	s_nopp_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1' or current_state = idle) then
			s_nopp <= 0;
		elsif(rising_edge(clk)) then
			if (aso_out_ready = '1' and current_state = wait_output) then
				s_nopp <= s_nopp + 1;
			end if;	
		end if;
	end process;
	
	--RAM data control
	data_lut_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			data_lut <= x"00";
		elsif(rising_edge(clk)) then
			if (current_state = configuration_wait_input) then
				data_lut <= asi_in_data;
			elsif (current_state = configuration_done or current_state = idle) then
				data_lut <= x"00";	
			end if;
		end if;
	end process;
	
	-- Process which controls stream to memory SGDMA buffer
	process_sample : process(clk, reset)
	begin
		if (reset = '1') then
			output_sample <= x"00";
		elsif (rising_edge(clk)) then
				output_sample <= q_lut;
		end if;
	end process;
	
	-- Moore machine state
	control_fsm: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			current_state <= idle;
		elsif (rising_edge(clk)) then
			current_state <= next_state;
		end if;
	end process;
	
	-- Transition between states are controled in this process
	streaming_protocol: process(current_state, asi_in_valid, aso_out_ready, s_nopp, s_nop)
	begin
		case current_state is
		
			when idle =>	
				if (c_conf = '1') then
					next_state <= configuration_wait_input;
				else	
					next_state <= idle;
				end if;	
			
			when configuration_wait_input =>
	
				if (address_lut = x"ff") then
					next_state <= configuration_done;
				elsif (asi_in_valid = '1') then
					next_state <= configuration_wait_state;
				else
					next_state <= configuration_wait_input;
				end if;
			
			when configuration_wait_state =>

				if (small_cnt = 2) then
					next_state <= configuration_process;
				else
					next_state <= configuration_wait_state;
				end if;
			
			when configuration_process =>

				next_state <= configuration_wait_input;
			
			when configuration_done =>
			
				if (c_process = '1') then
					next_state <= processing_wait_input;
				else
					next_state <= configuration_done;
				end if;
				
			when processing_wait_input =>
		
				if (asi_in_valid = '1') then
					next_state <= process_input;
				else
					next_state <= processing_wait_input;
				end if;

			when process_input =>
		
				if (small_cnt = 2) then
					next_state <= wait_output;
				else
					next_state <= process_input;
				end if;
				
			when wait_output =>

				if (aso_out_ready = '1') then
					next_state <= processing_wait_input;
				else
					next_state <= wait_output;
				end if;
				
			when done =>
				next_state <= done;

		end case;
	 end process;
	
	-- Output state machine ( Moore )
	output_process: process(current_state) is
	begin
		case(current_state) is		
		
			when idle => 
				state_machine_state <= "0000";
				status_reg_state <= "00";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
			when configuration_wait_input =>
				state_machine_state <= "0001";
				status_reg_state <= "01";
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';
				wren_lut <= '0';
				
			when configuration_wait_state =>
				state_machine_state <= "0010";
				status_reg_state <= "01";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
			when configuration_process =>
				state_machine_state <= "0011";
				status_reg_state <= "01";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '1';				
		
			when configuration_done =>
				state_machine_state <= "0100";
				status_reg_state <= "00";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '0';

			when processing_wait_input =>
				state_machine_state <= "0101";
				status_reg_state <= "10";
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';			
				wren_lut <= '0';
				
			when process_input =>
				state_machine_state <= "0110";
				status_reg_state <= "10";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '0';
			
			when wait_output =>
				state_machine_state <= "0111";
				status_reg_state <= "10";
				aso_out_valid <= '1';
				int_asi_in_ready <= '0';
				wren_lut <= '0';
					
			when done =>
				state_machine_state <= "1101";
				status_reg_state <= "10";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
		end case;
	end process;
	
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty<= '0';
	
	
	-- Needed to read from MM registers
	avs_control_waitrequest <= avs_control_read and wait_signal;

end architecture rtl; -- of contrast_acc