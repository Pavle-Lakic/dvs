-- contrast_acc.vhd

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
	--  Sa njim moze da se vrsi i upis i citanje.
	--	__________________________________________________
	--	| c_run | c_res | c_conf   | c_process |reserved |
	--	|-------|-------|----------|-----------|---------|
	--	|   7   |   6   |   5      |     4     |   3..0  |
	--	--------------------------------------------------

	signal control_reg : std_logic_vector(7 downto 0) := x"00";
	
	--	STATUS_REG
	--  Iz statusnog registra moze samo da se cita.
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
				configuration_wait_input,
				configuration_wait_state,
				configuration_process,
				configuration_done,
				processing_wait_input,
				process_input,
				wait_output,
				full_process,
				wait_output_and_process
				); 	
	signal current_state, next_state : state;
	
	constant NOP_LOW_ADDR		: std_logic_vector(2 downto 0) := "010";
	constant NOP_MIDDLE_ADDR	: std_logic_vector(2 downto 0) := "011";
	constant NOP_HIGH_ADDR		: std_logic_vector(2 downto 0) := "100";
	
	signal nop_low	: std_logic_vector ( 7 downto 0) := x"00";
	signal nop_middle : std_logic_vector (7 downto 0 ) := x"00";
	signal nop_high : std_logic_vector ( 7 downto 0) := x"00";
	
	signal nop_low_strobe : std_logic := '0';
	signal nop_middle_strobe : std_logic := '0';
	signal nop_high_strobe : std_logic := '0';

	-- pomocni signal koji omogucava citanje iz registra, za avs_control_waitrequest
	signal control_waitrq : std_logic;
	
	signal out_mux : std_logic_vector (7 downto 0);
	
	-- prva 3 bita statusnog registra, oznacavaju stanje
	signal status_reg_state : std_logic_vector (1 downto 0);
	signal state_machine_state : std_logic_vector (3 downto 0);
	
	-- softverski znak da modul treba da zapocne rad
	signal c_run : std_logic;
	
	-- softverski reset
	signal c_res : std_logic;
	
	--bit koji oznacava start konfiguracije
	signal c_conf : std_logic;
	
	--bit koji oznacava start procesiranja
	signal c_process : std_logic;
	
	-- oznacava broj obradjenih piksela
	signal s_nopp : integer range 0 to 262144 := 0;
	
	signal s_nop : unsigned (18 downto 0);
	signal wait_signal : std_logic;
	
	signal address_lut : std_logic_vector (7 downto 0) := x"00";
	signal data_lut : std_logic_vector ( 7 downto 0) := x"00";
	signal wren_lut : std_logic := '0';
	signal q_lut : std_logic_vector ( 7 downto 0) := x"00";
	signal lut_address : integer range 0 to 255 := 0;
	signal small_cnt : integer range 0 to 2 := 0;
	signal int_asi_in_ready : std_logic := '0';

begin	

	LUT_MEMORY:lut
	port map
	(
		address =>	address_lut,
		clock	=>	clk,
		data	=>	data_lut,
		wren	=>	wren_lut,
		q		=>	q_lut
	);
	
	control_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = CONTROL_ADDR) else '0';
	nop_low_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_LOW_ADDR) else '0';
	nop_middle_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_MIDDLE_ADDR) else '0';
	nop_high_strobe <= '1' when (avs_control_write = '1') and (avs_control_address = NOP_HIGH_ADDR) else '0';
	
	out_mux <= control_reg when (avs_control_address = CONTROL_ADDR) else
			nop_low when (avs_control_address = NOP_LOW_ADDR) else
			nop_middle when (avs_control_address = NOP_MIDDLE_ADDR) else
			nop_high when (avs_control_address = NOP_HIGH_ADDR) else
			status_reg when (avs_control_address = STATUS_ADDR) else
			x"AA";
	
	s_nop (18 downto 16) <= unsigned(nop_high(2 downto 0));
	s_nop (15 downto 8)  <= unsigned(nop_middle);
	s_nop (7 downto 0)	<= unsigned(nop_low);
	
	c_run <= control_reg(7);
	c_res <= control_reg(6);
	c_conf <= control_reg(5);
	c_process <= control_reg(4);
	
	status_reg(1 downto 0) <= status_reg_state;
	status_reg(5 downto 2) <= state_machine_state;
	
	asi_in_ready <= int_asi_in_ready;
	
	aso_out_data <= q_lut;
	
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
	
	-- menjanje brojaca
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
	
	address_lut_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			address_lut <= x"00";
		elsif (rising_edge(clk)) then
			if (current_state = configuration_process or current_state = configuration_wait_input or current_state = configuration_wait_state) then
				address_lut <= std_logic_vector(to_unsigned(lut_address, 8));
			elsif (current_state = idle or current_state = configuration_done) then
				address_lut <= x"0C";
			else
				address_lut <= asi_in_data;
			end if;
		end if;
	end process;
	
	-- wren_control: process(clk, reset, c_res)
	-- begin
		-- if (reset = '1' or c_res = '1') then
			-- wren_lut <= '0';
		-- elsif (rising_edge(clk)) then
			-- if (current_state = configuration_process) then
				-- wren_lut <= '1';
			-- else
				-- wren_lut <= '0';
			-- end if;	
		-- end if;
	-- end process;
	
	small_cnt_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			small_cnt <= 0;
		elsif(rising_edge(clk)) then
			if (current_state = configuration_wait_state) then
				small_cnt <= small_cnt + 1;
			elsif (current_state = configuration_process) then
				small_cnt <= 0;	
			end if;	
		end if;
	end process;
	
	s_nopp_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1' or current_state = idle) then
			s_nopp <= 0;
		elsif(rising_edge(clk)) then
			if (((current_state = process_input) or ((current_state = full_process or current_state = wait_output_and_process) and aso_out_ready = '1'))) then
				s_nopp <= s_nopp + 1;
			end if;	
		end if;
	end process;
	
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
	
	-- ideja je Moore-ova masina stanja da se napravi
	control_fsm: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			current_state <= idle;
		elsif (rising_edge(clk)) then
			current_state <= next_state;
		end if;
	end process;
	
	streaming_protocol: process(current_state,c_conf, asi_in_valid, address_lut) -- mozda ce da fali jos nesto kasnije u senz listi
	begin
		case current_state is
		
			when idle =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
			
				if (c_conf = '1') then
					next_state <= configuration_wait_input;
				else	
					next_state <= idle;
				end if;	
			
			when configuration_wait_input =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';
			
				if (address_lut = x"ff") then
					next_state <= configuration_done;
				elsif (asi_in_valid = '1') then
					next_state <= configuration_wait_state;
				else
					next_state <= configuration_wait_input;
				end if;
			
			when configuration_wait_state =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';			
			
				if (small_cnt = 2) then
					next_state <= configuration_process;
				else
					next_state <= configuration_wait_state;
				end if;
			
			when configuration_process =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				
				next_state <= configuration_wait_input;
			
			when configuration_done =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
			
				if (c_process = '1') then
					next_state <= processing_wait_input;
				else
					next_state <= configuration_done;
				end if;
				
			when processing_wait_input =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';
			
				next_state <= processing_wait_input;
				
				if (asi_in_valid = '1') then
					next_state <= process_input;
				else
					next_state <= processing_wait_input;
				end if;

			when process_input =>
				aso_out_valid <= '0';
				int_asi_in_ready <= '1';
				
				if (asi_in_valid = '1') then
					next_state <= full_process;
				else
					next_state <= wait_output;
				end if;
				
			when wait_output =>
				aso_out_valid <= '1';
				int_asi_in_ready <= '1';
				
				if (aso_out_ready = '1') then
					if (s_nop > to_unsigned(s_nopp, 19)) then
						if (asi_in_valid = '1') then
							next_state <= process_input;
						else
							next_state <= processing_wait_input;
						end if;
					end if;
				else
					if (asi_in_valid = '1') then
						next_state <= wait_output_and_process;
					elsif (s_nop = to_unsigned(s_nopp, 19)) then
						next_state <= wait_output_and_process;
					else
						next_state <= wait_output;
					end if;
					
				end if;
			
			when full_process =>
				aso_out_valid <= '1';
				int_asi_in_ready <= '1';

				if (aso_out_ready = '1' and asi_in_valid = '1') then
					next_state <= full_process;
				elsif (aso_out_ready = '1' and asi_in_valid = '0') then
					next_state <= wait_output;
				else
					int_asi_in_ready <= '0';
					next_state <= wait_output_and_process;
				end if;
				
			when wait_output_and_process =>
				aso_out_valid <= '1';
				int_asi_in_ready <= '0';

				if (aso_out_ready = '1') then
					if (asi_in_valid = '1') then
						int_asi_in_ready <= '1';
						next_state <= full_process;
					else
						next_state <= wait_output;
					end if;
				else
					next_state <= wait_output_and_process;
				end if;
		end case;
	 end process;
	
	output_process: process(current_state) is
	begin
		case(current_state) is		
		
			when idle => 
				state_machine_state <= "0000";
				status_reg_state <= "00";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
			when configuration_wait_input =>
				state_machine_state <= "0001";
				status_reg_state <= "01";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '1';
				wren_lut <= '0';
				
			when configuration_wait_state =>
				state_machine_state <= "0010";
				status_reg_state <= "01";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
			when configuration_process =>
				state_machine_state <= "0011";
				status_reg_state <= "01";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '0';
				wren_lut <= '1';				
		
			when configuration_done =>
				state_machine_state <= "0100";
				status_reg_state <= "00";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '0';
				wren_lut <= '0';

			when processing_wait_input =>
				state_machine_state <= "0101";
				status_reg_state <= "10";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '1';
				wren_lut <= '0';
				
			when process_input =>
				state_machine_state <= "0110";
				status_reg_state <= "10";
--				aso_out_valid <= '0';
--				int_asi_in_ready <= '1';
				wren_lut <= '0';
			
			when wait_output =>
				state_machine_state <= "0111";
				status_reg_state <= "10";
--				aso_out_valid <= '1';
--				int_asi_in_ready <= '1';
				wren_lut <= '0';
			
			when full_process =>
				state_machine_state <= "1000";
				status_reg_state <= "10";
--				aso_out_valid <= '1';
--				int_asi_in_ready <= '1';
				wren_lut <= '0';
				
			when wait_output_and_process =>
				state_machine_state <= "1001";
				status_reg_state <= "10";
--				aso_out_valid <= '1';
--				int_asi_in_ready <= '0';
				wren_lut <= '0';
				
		end case;
	end process;
	
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty<= '0';
	
	
	-- da bi moglo da se cita iz registra
	avs_control_waitrequest <= avs_control_read and wait_signal;

end architecture rtl; -- of contrast_acc
