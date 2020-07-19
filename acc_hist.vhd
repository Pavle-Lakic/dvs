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
	-- Sa njim moze da se vrsi i upis i citanje.
	--	____________________________
	--	| c_run | c_res | reserved |
	--	|   7   |   6   |   5..0   |

	signal control_reg : std_logic_vector(7 downto 0) := x"00";
	
	--	STATUS_REG
	-- Iz statusnog registra moze samo da se cita.
	--	 ______________________________
	--	| reserved | status_reg_state |
	--	|   7..3   |       2..0       |

	signal status_reg : std_logic_vector (7 downto 0) := x"00";
	
	-- oznacava da je statusni registar adresiran, i da je avs_control_write bit aktivan
	signal control_strobe : std_logic;
	
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
	
	signal nop_low_strobe : std_logic := '0';
	signal nop_middle_strobe : std_logic := '0';
	signal nop_high_strobe : std_logic := '0';

	-- pomocni signal koji omogucava citanje iz registra, za avs_control_waitrequest
	signal control_waitrq : std_logic;
	
	signal out_mux : std_logic_vector (7 downto 0);

	type state is (idle, 			-- cekanje softverskog starta, pre starta treba resetovati RAM							"000"
					reset_ram,		-- resetovanje ram-a 																	"001"
					wait_input,		-- nakon starta, cekanje da RAM bude spreman da primi podatak, i ulaz validan			"010"
					process_state, 	-- medjustanje 																			"011"
					wait_state,
					wait_output,	-- cekanje da izlazni DMA bude spreman da procita podatak								"100"
					output_read,	-- upis u izlazni DMA																	"101"
					done); 			-- stanje da je sve zavrseno, iz njega moze nazad samo soft ili hard resetom			"110"

	signal current_state, next_state : state;

	-- ulazni piksel, iz ulaznog DMA, ponasa se kao adresa u RAM-u u ovom modulu
	signal input_sample : std_logic_vector(7 downto 0);
	
	-- izlazni podatak, u izlazni DMA
	signal output_sample : std_logic_vector(15 downto 0);
	
	-- za sada se ne koristi, moze kasnije kao specificni ulazni podatak u RAM
	signal data_ram	: std_logic_vector(15 downto 0) := x"0000";
	
	-- signal dozvole za upis u RAM, za sada se ne koristi
	signal wren_ram : std_logic;
	
	-- signal da je spreman podatak na nekoj adresi da se procita iz RAM, za stanje output_read sluzi
	signal adrr_ready_ram : std_logic;
	
	-- signal za postavljanje svih podataka u RAM-u na 0
	signal c_clear : std_logic;
	
	-- signal koji sluzi da se na postavljenoj adresi podatak poveca za 1
	signal inc_ram : std_logic;
	
	-- oznacava da je RAM spreman da primi nov podatak
	signal in_ready_ram : std_logic;
	
	-- oznacava da je na izlaznom baferu u ramu validan podatak
	signal out_valid_ram : std_logic;
	
	-- izlazni podatak iz RAM-a
	signal q_ram : std_logic_vector (15 downto 0);
	
	-- softverski znak da modul treba da zapocne rad
	signal c_run : std_logic;
	
	-- softverski reset
	signal c_res : std_logic;
	
	-- prva 3 bita statusnog registra, oznacavaju stanje
	signal status_reg_state : std_logic_vector (2 downto 0);
	
	-- oznacava broj obradjenih piksela
	signal s_nopp : integer range 0 to 262144 := 0;
	
	signal read_reg : std_logic_vector ( 7 downto 0 );
	
	signal wait_signal : std_logic;
	signal address_ram : std_logic_vector (7 downto 0);
	
	signal ram_address : integer range 0 to 255 := 0;
	
	-- signal koji oznacava broj piksela koji treba da se obradi
	signal s_nop : unsigned (18 downto 0);	
	signal int_asi_in_ready : std_logic;
	signal small_cnt : integer range 0 to 2 := 0;
	
begin

	RAM_MEMORY:ram_8
	port map
	(
		address =>	address_ram,
		clock	=>	clk,
		data	=>	data_ram,
		wren	=>	wren_ram,
		q		=>	q_ram
	);

	-- za upis u kontrolni registar
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
	
	status_reg(2 downto 0) <= status_reg_state;
	
	--za izlazni DMA
	aso_out_data <= q_ram;
	
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
	
	-- proces za upis u kontrolni registar
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
		if (reset = '1') then
			control_reg <= (others => '0');
		elsif(rising_edge(clk)) then
			if (control_strobe = '1') then
				control_reg <= avs_control_writedata;
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
	
	-- menjanje brojaca
	ram_address_counter_control: process(clk, reset, c_res)
	begin 
		if (reset = '1' or c_res = '1') then
			ram_address <= 0;
		elsif (rising_edge(clk)) then
			if (current_state = reset_ram or (current_state = output_read)) then
				ram_address <= ram_address + 1;
			elsif (current_state = wait_input or current_state =  idle) then
				ram_address <= 0;
			end if;
		end if;
	end process;
	
	ram_address_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			address_ram <= x"00";
		elsif (rising_edge(clk)) then
			if ((current_state = process_state or current_state = wait_input  or current_state = wait_state) and (s_nop > to_unsigned(s_nopp, 19))) then
				address_ram <= asi_in_data;
			elsif (current_state = done) then
				address_ram <= x"E0";
			else
				address_ram <= std_logic_vector(to_unsigned(ram_address, 8));
			end if;
		end if;
	end process;
	
	s_nopp_control: process(clk, reset, c_res)
	begin
		if (reset = '1' or c_res = '1') then
			s_nopp <= 0;
			small_cnt <= 0;
		elsif(rising_edge(clk)) then
			if (current_state = process_state) then
				s_nopp <= s_nopp + 1;
			elsif (current_state = wait_state) then
				small_cnt <= small_cnt + 1;
			end if;	
		end if;
	end process;
	
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
	
	-- nova logika masine stanja
	streaming_protocol: process(current_state, asi_in_valid, aso_out_ready, c_run) -- mozda ce da fali jos nesto kasnije u senz listi
	begin
		case current_state is
			when idle =>		
				if (c_run = '1') then
					next_state <= reset_ram;
				else
					next_state <= idle;
				end if;
				
			when reset_ram =>
				if (ram_address = 255) then	
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
				if (s_nop = to_unsigned(s_nopp - 1, 19)) then
					next_state <= wait_output;
				elsif (small_cnt = 2) then
					next_state <= process_state;
				else
					next_state <= wait_state;
				end if;	
				
			when process_state =>	
				if (s_nop = to_unsigned(s_nopp - 1, 19)) then
					next_state <= wait_output;
				else
					next_state <= wait_input;
				end if;	
	
								
			when wait_output =>
				if (ram_address = 255) then
					next_state <= done;
				elsif (aso_out_ready = '1') then
					next_state <= output_read;
				else
					next_state <= wait_output;
				end if;
				
			when output_read =>
				next_state <= wait_output;
				
			when done =>
				next_state <= done;
				
		 end case;
	 end process;
	
	-- na osnovu stanja postavlja izlaze
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
				status_reg_state <= "111";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';	
			
			when process_state =>	
				status_reg_state <= "011";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
	
			when wait_output =>				
				status_reg_state <= "100";
				aso_out_valid <= '1';
				int_asi_in_ready <= '0';
				
			when output_read =>	
				status_reg_state <= "101";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
			
			when done =>
				status_reg_state <= "110";
				aso_out_valid <= '0';
				int_asi_in_ready <= '0';
				
		end case;
	end process;
	
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty<= '0';
	
	-- da bi moglo da se cita iz registra
	avs_control_waitrequest <= avs_control_read and wait_signal;

end architecture rtl; -- of acc_hist
