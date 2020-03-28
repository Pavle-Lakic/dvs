-- Copyright (C) 2018  Intel Corporation. All rights reserved.
-- Your use of Intel Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Intel Program License 
-- Subscription Agreement, the Intel Quartus Prime License Agreement,
-- the Intel FPGA IP License Agreement, or other applicable license
-- agreement, including, without limitation, that your use is for
-- the sole purpose of programming logic devices manufactured by
-- Intel and sold by Intel or its authorized distributors.  Please
-- refer to the applicable agreement for further details.

-- ***************************************************************************
-- This file contains a Vhdl test bench template that is freely editable to   
-- suit user's needs .Comments are provided in each section to help the user  
-- fill out necessary details.                                                
-- ***************************************************************************
-- Generated on "03/14/2020 16:43:44"
                                                            
-- Vhdl Test Bench template for design  :  acc_hist
-- 
-- Simulation tool : ModelSim-Altera (VHDL)
-- 

LIBRARY ieee;                                               
USE ieee.std_logic_1164.all;                                

ENTITY acc_hist_vhd_tst IS
END acc_hist_vhd_tst;
ARCHITECTURE acc_hist_arch OF acc_hist_vhd_tst IS
-- constants                
constant clk_period: time := 20 ns;                                   
-- signals                                                  
SIGNAL asi_in_data : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00";
SIGNAL asi_in_eop : STD_LOGIC := '0';
SIGNAL asi_in_ready : STD_LOGIC := '0';
SIGNAL asi_in_sop : STD_LOGIC := '0';
SIGNAL asi_in_valid : STD_LOGIC := '0';
SIGNAL aso_out_data : STD_LOGIC_VECTOR(15 DOWNTO 0);
SIGNAL aso_out_empty : STD_LOGIC;
SIGNAL aso_out_eop : STD_LOGIC;
SIGNAL aso_out_ready : STD_LOGIC := '0';
SIGNAL aso_out_sop : STD_LOGIC:= '0';
SIGNAL aso_out_valid : STD_LOGIC;
SIGNAL avs_control_address : STD_LOGIC := '0';
SIGNAL avs_control_read : STD_LOGIC:= '0';
SIGNAL avs_control_readdata : STD_LOGIC_VECTOR(31 DOWNTO 0);
SIGNAL avs_control_waitrequest : STD_LOGIC;
SIGNAL avs_control_write : STD_LOGIC:= '0';
SIGNAL avs_control_writedata : STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00000000";
SIGNAL clk : STD_LOGIC := '0';
SIGNAL reset : STD_LOGIC := '0';
COMPONENT acc_hist
	PORT (
	asi_in_data : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
	asi_in_eop : IN STD_LOGIC;
	asi_in_ready : BUFFER STD_LOGIC;
	asi_in_sop : IN STD_LOGIC;
	asi_in_valid : IN STD_LOGIC;
	aso_out_data : BUFFER STD_LOGIC_VECTOR(15 DOWNTO 0);
	aso_out_empty : BUFFER STD_LOGIC;
	aso_out_eop : BUFFER STD_LOGIC;
	aso_out_ready : IN STD_LOGIC;
	aso_out_sop : BUFFER STD_LOGIC;
	aso_out_valid : BUFFER STD_LOGIC;
	avs_control_address : IN STD_LOGIC;
	avs_control_read : IN STD_LOGIC;
	avs_control_readdata : BUFFER STD_LOGIC_VECTOR(31 DOWNTO 0);
	avs_control_waitrequest : BUFFER STD_LOGIC;
	avs_control_write : IN STD_LOGIC;
	avs_control_writedata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
	clk : IN STD_LOGIC;
	reset : IN STD_LOGIC
	);
END COMPONENT;
BEGIN
	i1 : acc_hist
	PORT MAP (
-- list connections between master ports and signals
	asi_in_data => asi_in_data,
	asi_in_eop => asi_in_eop,
	asi_in_ready => asi_in_ready,
	asi_in_sop => asi_in_sop,
	asi_in_valid => asi_in_valid,
	aso_out_data => aso_out_data,
	aso_out_empty => aso_out_empty,
	aso_out_eop => aso_out_eop,
	aso_out_ready => aso_out_ready,
	aso_out_sop => aso_out_sop,
	aso_out_valid => aso_out_valid,
	avs_control_address => avs_control_address,
	avs_control_read => avs_control_read,
	avs_control_readdata => avs_control_readdata,
	avs_control_waitrequest => avs_control_waitrequest,
	avs_control_write => avs_control_write,
	avs_control_writedata => avs_control_writedata,
	clk => clk,
	reset => reset
	);
clk <= not clk after clk_period/2;                                          
always : PROCESS                                                                                
BEGIN                                                         
       wait for clk_period/2;
	reset <= '1';
	wait for clk_period;
	reset <= '0'; 
	wait for clk_period;
	avs_control_writedata <= x"00001000";
	avs_control_address <= '1';
	wait for clk_period;
	avs_control_write <= '1';
	wait for 10*clk_period;
	avs_control_write <= '0';
	wait for clk_period;
	avs_control_read <= '1';
	wait for clk_period;
	avs_control_read <= '0';
	wait for clk_period;
	avs_control_writedata <= x"40000000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 10*clk_period;
	avs_control_write <='0';
	wait for 3*clk_period;
	avs_control_writedata <= x"0EADBEEF";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 10*clk_period;
	avs_control_write <= '0';
	wait for clk_period;
	avs_control_writedata <= x"20000000";
	wait for 2*clk_period;
	wait for clk_period;
	avs_control_write <= '1';
	wait for 2*clk_period;
	avs_control_write <= '0';
	avs_control_writedata <= x"00000000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 2*clk_period;
	avs_control_write <= '0';
	wait for 20 us;
	avs_control_writedata <= x"80001000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 10*clk_period;
	avs_control_write <='0';
	wait for 5*clk_period;
	asi_in_data <= x"80";
	wait for clk_period;
	asi_in_valid <= '1';
	wait for clk_period;
	asi_in_valid <= '0';
	wait for 5*clk_period;
	asi_in_data <= x"80";
	wait for clk_period;
	asi_in_valid <= '1';
	wait for clk_period;
	asi_in_valid <= '0';
	wait for 5*clk_period;
	asi_in_data <= x"00";
	wait for clk_period;
	asi_in_valid <= '1';
	wait for clk_period;
	asi_in_valid <= '0';
	wait for 5*clk_period;
	asi_in_data <= x"80";
	wait for clk_period;
	asi_in_valid <= '1';
	wait for clk_period;
	asi_in_valid <= '0';
	avs_control_writedata <= x"40000000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 3*clk_period;
	avs_control_write <= '0';
	wait for 5*clk_period;
	reset <= '1';
	wait for clk_period;
	reset <= '0';
	wait for 5*clk_period;
	avs_control_writedata <= x"00000000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 3*clk_period;
	avs_control_write <= '0';
	wait for 4*clk_period;
	avs_control_writedata <= x"20000000";
	wait for clk_period;
	avs_control_write <= '1';
	wait for clk_period;
	avs_control_write <= '0';
	avs_control_writedata <= x"000000aa";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 4*clk_period;
	avs_control_write <= '0';
	wait for 4*clk_period;
	avs_control_writedata <= x"800000aa";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 4*clk_period;
	avs_control_write <= '0';
	wait for 4*clk_period;
	asi_in_data <= x"01";
	wait for clk_period;
	asi_in_valid <= '1';
	wait for 4*clk_period;
	avs_control_writedata <= x"000000aa";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 4*clk_period;
	avs_control_write <= '0';
	wait for 20 us;
	avs_control_writedata <= x"800000aa";
	wait for clk_period;
	avs_control_write <= '1';
	wait for 4*clk_period;
	avs_control_write <= '0';
	wait for 4*clk_period;
	aso_out_ready <= '1';
	
WAIT;                                                        
END PROCESS always;                                          
END acc_hist_arch;
