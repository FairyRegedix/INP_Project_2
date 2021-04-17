-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2020 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Demský Patrik (xdemsk00)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_WE    : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti 
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	--MUX
	signal mx_sel : std_logic_vector (1 downto 0) := (others => '0');
	signal mx_outp : std_logic_vector (7 downto 0) := (others => '0');

	--PC
	signal pc_out : std_logic_vector (11 downto 0);
	signal pc_inc : std_logic;
	signal pc_dec : std_logic;
	signal pc_ld  : std_logic;

	--RAS
	signal ras_out : std_logic_vector (11 downto 0);
	signal ras_push : std_logic;
	signal ras_pop : std_logic;

	--PTR
	signal ptr_out : std_logic_vector (9 downto 0);
	signal ptr_inc : std_logic;
	signal ptr_dec : std_logic;

	--STATES
	type states is (start,fetch,decode,s_pointer_inc,s_pointer_dec,s_val_inc,s_val_dec,s_val_end_inc,s_val_end_dec,s_val_mx_inc,
	s_val_mx_dec,s_while_start,s_while_check,s_while_loop,s_while_en,s_while_end,s_write_first,s_write,s_get_first,s_get,null_s);
	signal presentState : states := start;
	signal nextState : states;

begin

	--PC
	PC: process (CLK, RESET, pc_inc, pc_dec, pc_ld) is
	begin
		if RESET = '1' then
			pc_out <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (pc_ld = '1') then
				pc_out <= ras_out;
			elsif (pc_inc = '1') then
				pc_out <= pc_out + 1;
			elsif (pc_dec = '1') then
				pc_out <= pc_out - 1;
			else
			end if;
		end if;
	end process;
	CODE_ADDR <= pc_out;

	--RAS
	RAS: process (ras_push, ras_pop) is
	begin
		if (ras_pop = '1') then
			ras_out <= pc_out - 1;
		elsif (ras_push = '1') then
			ras_out <= pc_out;
		else
		end if;
	end process;
	

	--PTR
	PTR: process (CLK, RESET, ptr_inc, ptr_dec) is
	begin
		if RESET = '1' then
			ptr_out <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (ptr_inc = '1') then
				ptr_out <= ptr_out + 1;
			elsif (ptr_dec = '1') then
				ptr_out <= ptr_out - 1;
			else
			end if;
		end if;
	end process;
	DATA_ADDR <= ptr_out;


	--MUX
	MUX: process (CLK, RESET, mx_sel) is
	begin
		if RESET = '1' then
			mx_outp <= (others => '0');
		elsif (CLK'event) and (CLK = '1') then
			if (mx_sel = "00") then
				mx_outp <= IN_DATA;
			elsif (mx_sel = "10") then
				mx_outp <= DATA_RDATA + 1;
			elsif (mx_sel = "01") then
				mx_outp <= DATA_RDATA - 1;
			else
				mx_outp <= (others => '0');
			end if;
		end if;
	end process;
	DATA_WDATA <= mx_outp;


	--FSM
	state_logic: process (CLK, RESET, EN) is
	begin
		if RESET = '1' then
			presentState <= start;
		elsif (CLK'event) and (CLK = '1') then
			if (EN) = '1' then
				presentState <= nextState;
			end if;
		end if;
	end process;

	FSM: process (presentState, OUT_BUSY, IN_VLD, CODE_DATA, DATA_RDATA) is
	begin
		--init
		pc_inc <= '0';
		pc_dec <= '0';
		pc_ld <= '0';
		ras_pop <= '0';
		ras_push <= '0';
		ptr_inc <= '0';
		ptr_dec <= '0';

		mx_sel <= "00";

		CODE_EN <= '0';
		DATA_EN <= '0';
		DATA_WE <= '0';
		IN_REQ <= '0';
		OUT_WE <= '0';

		case presentState is
			when start =>
				nextState <= fetch;
			when fetch =>
				nextState <= decode;
				CODE_EN <= '1';
			when decode =>
				case CODE_DATA is
					when X"3E" => nextState <= s_pointer_inc;
					when X"3C" => nextState <= s_pointer_dec;
					when X"2B" => nextState <= s_val_inc;
					when X"2D" => nextState <= s_val_dec;
					when X"5B" => nextState <= s_while_start;
					when X"5D" => nextState <= s_while_end;
					when X"2E" => nextState <= s_write_first;
					when X"2C" => nextState <= s_get_first;
					when X"00" => nextState <= null_s;
					when others =>
						nextState <= fetch;
						pc_inc <= '1';
				end case;
			-- >
			when s_pointer_inc =>
				nextState <= fetch;
				pc_inc <= '1';
				ptr_inc <= '1';

			-- <
			when s_pointer_dec =>
				nextState <= fetch;
				pc_inc <= '1';
				ptr_dec <= '1';


			-- +
			when s_val_inc =>
				nextState <= s_val_mx_inc;
				DATA_EN <= '1';
				DATA_WE <= '0';

			when s_val_mx_inc =>
				nextState <= s_val_end_inc;
				mx_sel <= "10";

			when s_val_end_inc =>
				nextState <= fetch;
				DATA_EN <= '1';
				DATA_WE <= '1';
				pc_inc <= '1';

			-- -
			when s_val_dec =>
				nextState <= s_val_mx_dec;
				DATA_EN <= '1';
				DATA_WE <= '0';

			when s_val_mx_dec =>
				nextState <= s_val_end_dec;
				mx_sel <= "01";

			when s_val_end_dec =>
				nextState <= fetch;
				DATA_EN <= '1';
				DATA_WE <= '1';
				pc_inc <= '1';


			-- [ ]

			when s_while_start =>
				nextState <= s_while_check;
				pc_inc <= '1';
				DATA_EN <= '1';
				DATA_WE <= '0';

			when s_while_check =>
				ras_push <= '1';
				if DATA_RDATA /= "00000000" then
					nextState <= fetch;
				else
					nextState <= s_while_loop;
					CODE_EN <= '1';
				end if;

			when s_while_loop =>
				pc_inc <= '1';
				if CODE_DATA /= X"5D" then
					nextState <= s_while_en;
				else
					nextState <= fetch;
				end if;

			when s_while_en =>
				nextState <= s_while_loop;
				DATA_EN <= '1';

			when s_while_end =>
				if DATA_RDATA = "00000000" then
					nextState <= fetch;
					pc_inc <= '1';
				else
					nextState <= fetch;
					pc_ld <= '1';
				end if;

			-- .
			when s_write_first =>
				nextState <= s_write;

				DATA_EN <= '1';
				DATA_WE <= '0';
			when s_write =>
				if OUT_BUSY = '1' then
					nextState <= s_write;
					DATA_EN <= '1';
					DATA_WE <= '0';
				else
					nextState <= fetch;
					OUT_DATA <= DATA_RDATA;
					OUT_WE <= '1';
					pc_inc <= '1';
				end if;

	

			-- ,
			when s_get_first =>
				nextState <= s_get;
				IN_REQ <= '1';
				mx_sel <= "00";

			when s_get =>
				if IN_VLD = '1' then
					nextState <= fetch;
					DATA_EN <= '1';
					DATA_WE <= '1';
					pc_inc <= '1';
				else
					nextState <= s_get;
					IN_REQ <= '1';
					mx_sel <= "00";
				end if;

			-- null
			when null_s =>
				nextState <= null_s;

			

			-- others
			when others =>
				nextState <= fetch;
				pc_inc <= '1';
				
				
		end case;		
						  
	end process;
 
end behavioral;
 
