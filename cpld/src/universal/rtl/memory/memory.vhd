library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity memory is
port (
    CLK14              : in std_logic;
    CLK7               : in std_logic;
    HCNT0              : in std_logic;
    BUS_N_ROMCS        : in std_logic;

    A                  : in std_logic_vector(15 downto 0); -- address bus
    D                  : in std_logic_vector(7 downto 0);
    N_MREQ             : in std_logic;
    N_IORQ             : in std_logic;
    N_WR               : in std_logic;
    N_RD               : in std_logic;
    N_M1               : in std_logic;
    
    DO                 : out std_logic_vector(7 downto 0);
    N_OE               : out std_logic;
    
    MA                 : out std_logic_vector(18 downto 0);
    MD                 : inout std_logic_vector(7 downto 0);
    N_MRD              : out std_logic;
    N_MWR              : out std_logic;
    
    RAM_BANK           : in std_logic_vector(2 downto 0);
	 RAM_EXT            : in std_logic_vector(1 downto 0) := "00";
    
    DIVMMC_EN          : in std_logic;
    AUTOMAP            : in std_logic;
    REG_E3             : in std_logic_vector(7 downto 0);
	 ROM_SW				  : out std_logic;
	 TEST					  : in std_logic;
    
    TRDOS              : in std_logic;
    
    VA                 : in std_logic_vector(13 downto 0);
    VID_PAGE           : in std_logic := '0';
    
    VBUS_MODE_O        : out std_logic;
    VID_RD_O           : out std_logic;
    
    ROM_BANK           : in std_logic := '0';
    ROM_A14            : out std_logic;
    ROM_A15            : out std_logic;
    N_ROMCS            : out std_logic
);
end memory;

architecture RTL of memory is

    signal buf_md      : std_logic_vector(7 downto 0) := "11111111";
    signal is_buf_wr   : std_logic := '0';
    
    signal is_rom      : std_logic := '0';
    signal is_ram      : std_logic := '0';
	 
    signal is_romDIVMMC: std_logic := '0';
    signal is_ramDIVMMC: std_logic := '0';
    
    signal rom_page    : std_logic_vector(2 downto 0) := "000";
    signal ram_page    : std_logic_vector(4 downto 0) := "00000";

    signal vbus_req    : std_logic := '1';
    signal vbus_mode   : std_logic := '1';    
    signal vbus_rdy    : std_logic := '1';
    signal vid_rd      : std_logic := '0';
    signal vbus_ack    : std_logic := '1';
begin

	---DIVMMC signaling when we must map rom or ram of DIVMMC interface to Z80 adress space
	is_romDIVMMC <= '1' when DIVMMC_EN = '1' and N_MREQ = '0' and (AUTOMAP ='1' or REG_E3(7) = '1') and A(15 downto 13) = "000" else '0';
	is_ramDIVMMC <= '1' when DIVMMC_EN = '1' and N_MREQ = '0' and (AUTOMAP ='1' or REG_E3(7) = '1') and A(15 downto 13) = "001" else '0';
	
	is_rom <= '1' when N_MREQ = '0' and A(15 downto 14) = "00" else '0';
	is_ram <= '1' when N_MREQ = '0' and is_rom = '0' else '0';
    
    -- 000 - bank 0, GLUK
    -- 001 - bank 1, TRDOS
    -- 010 - bank 2, Basic-128 (pent)
    -- 011 - bank 3, Basic-48 (pent)
	 -- 100 - bank 4, ESXDOS
	 -- 101 - bank 5, DiagROM
	 -- 110 - bank 6, Basic-128 (classic)
	 -- 111 - bank 7, Basic-48 (classic)
	 rom_page <= 
		"101" when TEST = '1' else -- DiagROM
		'0' & (not(TRDOS)) & ROM_BANK when DIVMMC_EN = '0' else -- gluk romset
		"100" when is_romDIVMMC = '1' else -- ESXDOS 
		"11" & ROM_BANK; -- classic basics
        
    ROM_A14 <= rom_page(0);
    ROM_A15 <= rom_page(1);
	 ROM_SW <= rom_page(2);
    N_ROMCS <= '0' when (is_rom = '1' or is_romDIVMMC = '1') and is_ram = '0' and is_ramDIVMMC = '0' and N_RD = '0' and BUS_N_ROMCS = '0' else '1';

    vbus_req <= '0' when ( N_MREQ = '0' or N_IORQ = '0' ) and ( N_WR = '0' or N_RD = '0' ) else '1';
    vbus_rdy <= '0' when (CLK7 = '0' or HCNT0 = '0') else '1';

    VBUS_MODE_O <= vbus_mode;
    VID_RD_O <= vid_rd;
    
    N_MRD <= '0' when (vbus_mode = '1' and vbus_rdy = '0') or (vbus_mode = '0' and N_RD = '0' and N_MREQ = '0' and (is_ram = '1' or is_ramDIVMMC = '1')) else '1';  
    N_MWR <= '0' when vbus_mode = '0' and (is_ram = '1' or is_ramDIVMMC = '1') and N_WR = '0' and HCNT0 = '0' else '1';

    is_buf_wr <= '1' when vbus_mode = '0' and HCNT0 = '0' else '0';
    
    DO <= buf_md;
    N_OE <= '0' when (is_ram = '1' or is_ramDIVMMC = '1') and N_RD = '0' else '1';
        
    -- memory map for RAM = 128k
    ram_page(2 downto 0) <=    
		 "000" when A(15) = '0' and A(14) = '0' else
		 "101" when A(15) = '0' and A(14) = '1' else
		 "010" when A(15) = '1' and A(14) = '0' else
		 RAM_BANK(2 downto 0);

    -- pentagon-512 when in ZC mode		 
	 ram_page(4 downto 3) <= RAM_EXT when divmmc_en = '0' else "00";
    
    MA(13 downto 0) <= 
        REG_E3(0) & A(12 downto 0) when vbus_mode = '0' and is_ramDIVMMC = '1' else -- DIVMMC ram
        A(13 downto 0) when vbus_mode = '0' else -- spectrum ram
        VA; -- video ram

	 MA(18 downto 14) <= 
		"10" & REG_E3(3 downto 1) when is_ramDIVMMC = '1' and vbus_mode = '0' else -- DIVMMC ram 128 kB from #X180000 SRAM
		ram_page(4 downto 0) when vbus_mode = '0' else 
		"001" & VID_PAGE & '1' when vbus_mode = '1' else -- spectrum screen
		"00000";
    
    MD(7 downto 0) <= 
        D(7 downto 0) when vbus_mode = '0' and ((is_ram = '1' or is_ramDIVMMC = '1' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0') else 
        (others => 'Z');
        
    -- fill memory buf
    process(is_buf_wr)
    begin 
        if (is_buf_wr'event and is_buf_wr = '0') then  -- high to low transition to lattch the MD into BUF
            buf_md(7 downto 0) <= MD(7 downto 0);
        end if;
    end process;    
    
    -- video mem
    process( CLK14, CLK7, HCNT0, vbus_mode, vid_rd, vbus_req, vbus_ack )
    begin
        -- lower edge of 7 mhz clock
        if CLK14'event and CLK14 = '1' then 
            if (HCNT0 = '1' and CLK7 = '0') then
                if vbus_req = '0' and vbus_ack = '1' then
                    vbus_mode <= '0';
                else
                    vbus_mode <= '1';
                    vid_rd <= not vid_rd;
                end if;
                vbus_ack <= vbus_req;
            end if;
        end if;        
    end process;
        
end RTL;

