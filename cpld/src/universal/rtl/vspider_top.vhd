-- --------------------------------------------------------------------
-- Vspider firmware
-- (c) 2026 Andy Karpov
-- --------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity vspider_top is
generic (
    -- global configuration
    enable_divmmc       : boolean := false;   -- enable DivMMC
    enable_zcontroller  : boolean := true;  -- enable Z-Controller
    enable_trdos        : boolean := true;  -- enable TR-DOS
    enable_service_boot : boolean := true   -- boot into the service rom (when z-controller and tr-dos are enabled)
);
port(
    -- Clock
    CLK14               : in std_logic;

    -- CPU signals
    CLK_CPU             : out std_logic := '1';
    N_RESET             : in std_logic;
    N_INT               : out std_logic := '1';
    N_RD                : in std_logic;
    N_WR                : in std_logic;
    N_IORQ              : in std_logic;
    N_MREQ              : in std_logic;
    N_M1                : in std_logic;
    A                   : in std_logic_vector(15 downto 0);
    D                   : inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
    N_NMI               : out std_logic := 'Z';
    
    -- RAM 
    MA                  : out std_logic_vector(18 downto 0);
    MD                  : inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
    N_MRD               : out std_logic := '1';
    N_MWR               : out std_logic := '1';
    
    -- ROM
    N_ROMCS             : out std_logic := '1';
    ROM_A14             : out std_logic := '0';
    ROM_A15             : out std_logic := '0';
    ROM_SW              : out std_logic := '0'; -- ROM A16
    
    -- ZX BUS signals
    BUS_N_IORQGE        : in std_logic  := '0';
    BUS_N_ROMCS         : in std_logic  := '0';
    CLK_BUS             : out std_logic := '1';

    -- Video
    VIDEO_CSYNC         : out std_logic;
    VIDEO_R             : out std_logic := '0';
    VIDEO_G             : out std_logic := '0';
    VIDEO_B             : out std_logic := '0';
    VIDEO_I             : out std_logic := '0';

    -- Interfaces 
    TAPE_IN             : in std_logic;
    TAPE_OUT            : out std_logic := '1';
    BEEPER              : out std_logic := '1';

    -- AY
    CLK_AY              : out std_logic; -- not used by Atmega8
    AY_BC1              : out std_logic;
    AY_BDIR             : out std_logic;
    AY_A8_1             : out std_logic := '0'; -- todo
    AY_A8_2             : out std_logic := '1'; -- todo

    -- SD card
    SD_CLK              : out std_logic := '0';
    SD_DI               : out std_logic;
    SD_DO               : in std_logic;
    SD_N_CS             : out std_logic := '1';
    
    -- Keyboard
    KB                  : in std_logic_vector(4 downto 0) := "11111";

    -- Config switch
    SW                  : in std_logic_vector(2 downto 0) := "111";

    -- kempston joy port
    KEMPSTON_CS_N       : out std_logic := '1'; -- todo

    -- something unknown on the ZX Edge slot
    DRD                 : out std_logic := '0'; -- Y
    DWR                 : out std_logic := '0'; -- U
    MTR                 : out std_logic := '0'; -- V

    -- Magic button
    BTN_NMI             : in std_logic := '1'
);
end vspider_top;

architecture rtl of vspider_top is

    signal clk_7        : std_logic := '0';
    signal clkcpu       : std_logic := '1';
    signal attr_r       : std_logic_vector(7 downto 0);
    signal rgb          : std_logic_vector(2 downto 0);
    signal i            : std_logic;
    signal vid_a        : std_logic_vector(13 downto 0);
    signal hcnt0        : std_logic;
    signal hcnt1        : std_logic;    
    signal border_attr  : std_logic_vector(2 downto 0) := "000";
    signal port_7ffd    : std_logic_vector(7 downto 0); -- D0-D2 - RAM page from address #C000
                                                        -- D3 - video RAM page: 0 - bank5, 1 - bank7 
                                                        -- D4 - ROM page A14: 0 - basic 128, 1 - basic48
                                                        -- D5 - 48k RAM lock, 1 - locked, 0 - extended memory enabled
                                                        -- D6 - not used
                                                        -- D7 - not used
                                                                      
    signal ram_do       : std_logic_vector(7 downto 0);
    signal ram_oe_n     : std_logic := '1';
    
    signal bdir         : std_logic;
    signal bc1          : std_logic;
	 signal ssg          : std_logic;
        
    signal vbus_mode    : std_logic := '0';
    signal vid_rd       : std_logic := '0';
    
    signal hsync        : std_logic := '1';
    signal vsync        : std_logic := '1';

    signal sound_out    : std_logic := '0';
    signal mic          : std_logic := '0';
    
    signal port_read    : std_logic := '0';
    signal port_write   : std_logic := '0';
    
    signal divmmc_do    : std_logic_vector(7 downto 0);    
    signal divmmc_ram   : std_logic;
    signal divmmc_rom   : std_logic;
    
    signal divmmc_disable_zxrom : std_logic;
    signal divmmc_eeprom_cs_n   : std_logic;
    signal divmmc_eeprom_we_n   : std_logic;
    signal divmmc_sram_cs_n     : std_logic;
    signal divmmc_sram_we_n     : std_logic;
    signal divmmc_sram_hiaddr   : std_logic_vector(5 downto 0);
    signal divmmc_sd_cs_n       : std_logic;
    signal divmmc_wr            : std_logic;
    signal divmmc_sd_di         : std_logic;
    signal divmmc_sd_clk        : std_logic;
    
    signal zc_do_bus     : std_logic_vector(7 downto 0);
    signal zc_wr         : std_logic :='0';
    signal zc_rd         : std_logic :='0';
    signal zc_sd_cs_n    : std_logic;
    signal zc_sd_di      : std_logic;
    signal zc_sd_clk     : std_logic;
    
    signal trdos         : std_logic :='0';    
begin

    divmmc_rom <= '1' when (divmmc_disable_zxrom = '1' and divmmc_eeprom_cs_n = '0') else '0';
    divmmc_ram <= '1' when (divmmc_disable_zxrom = '1' and divmmc_sram_cs_n = '0') else '0';
    
    BEEPER <= sound_out;
    
    N_NMI <= '0' when BTN_NMI = '0' else 'Z';
	 
	 -- AY
	process(CLK14, N_RESET)
	begin
		if (N_RESET = '0') then
			ssg <= '0';
		elsif (CLK14'event and CLK14 = '1') then
			if (D(7 downto 1) = "1111111" and bdir = '1' and bc1 = '1') then
				ssg <= D(0);
			end if;
		end if;
	end process;	 

	 bdir	<= '1' when (N_M1 = '1' and N_IORQ = '0' and N_WR = '0'  and A(15) = '1' and A(1) = '0') else '0';
	 bc1	<= '1' when (N_M1 = '1' and N_IORQ = '0' and A(15) = '1' and A(14) = '1' and A(1) = '0') else '0';	 
    AY_BC1 <= bc1;
    AY_BDIR <= bdir;
	 AY_A8_1 <= not(ssg);
	 AY_A8_2 <= ssg;
	 
	 -- kempston joy
	 KEMPSTON_CS_N <= '0' when (N_IORQ = '0' and N_RD = '0' and N_M1 = '1' and A(7 downto 0) = X"1F" and trdos = '0') else '1'; -- Joystick, port #1F
	
	 -- high rom bank related to SW[0]
	 ROM_SW <= SW(0);
	
    -- CPU clock 
    process( N_RESET, clk14, clk_7, hcnt0 )
    begin
        if clk14'event and clk14 = '1' then
            if clk_7 = '1' then
                clkcpu <= hcnt0;
            end if;
        end if;
    end process;
    
    CLK_CPU <= clkcpu;
    CLK_BUS <= not(clkcpu);
    CLK_AY    <= hcnt1;
    
    TAPE_OUT <= mic;
    
    port_write <= '1' when N_IORQ = '0' and N_WR = '0' and N_M1 = '1' else '0'; -- and vbus_mode = '0' else '0';
    port_read <= '1' when N_IORQ = '0' and N_RD = '0' and N_M1 = '1' and BUS_N_IORQGE = '0' else '0';
    
    -- read ports by CPU
    D(7 downto 0) <= 
        ram_do when ram_oe_n = '0' else -- #memory
        --'1' & TAPE_IN & '1' & kb(4 downto 0) when port_read = '1' and A(0) = '0' else -- #FE - keyboard 
		  '1' & TAPE_IN & '1' & kb(4) & sw(1) & kb(2 downto 0) when port_read = '1' and A(0) = '0' else -- #FE - keyboard 
        divmmc_do when enable_divmmc and divmmc_wr = '1' else -- divmmc
        zc_do_bus when enable_zcontroller and port_read = '1' and A(7 downto 6) = "01" and A(4 downto 0) = "10111" else -- ZC
        port_7ffd when trdos = '1' and port_read = '1' and A = x"7FFD" else -- #7FFD
        attr_r when port_read = '1' and A(7 downto 0) = x"FF" else -- #FF
        "ZZZZZZZZ";
		  
    -- z-controller 
    G_ZC_SIG: if enable_zcontroller generate
        zc_wr <= '1' when (N_IORQ = '0' and N_WR = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
        zc_rd <= '1' when (N_IORQ = '0' and N_RD = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
    end generate G_ZC_SIG;
    
    -- clocks
    process (clk14)
    begin 
        if (clk14'event and clk14 = '1') then 
            clk_7 <= not(clk_7);
        end if;
    end process;
    
    -- ports, write by CPU
    process( clk14, clk_7, N_RESET, A, D, port_write, port_7ffd, N_M1, N_MREQ )
    begin
        if N_RESET = '0' then
            port_7ffd <= "00000000";
            sound_out <= '0';
        elsif clk14'event and clk14 = '1' then 
            if port_write = '1' then

                 -- port #7FFD  
                if A(15)='0' and A(1) = '0' and port_7ffd(5) = '0' then -- short decoding #FD                    
                    port_7ffd <= D;
                end if;

                -- port #FE
                if A(0) = '0' then
                    border_attr <= D(2 downto 0); -- border attr
                    mic <= D(3); -- MIC
                    sound_out <= D(4); -- BEEPER
                end if;
                                    
            end if;
        end if;
    end process;    
    
    -- trdos flag
    G_TRDOS_FLAG: if enable_trdos generate    
        process(clk14, N_RESET, N_M1, N_MREQ)
        begin 
            if N_RESET = '0' then 
                if (enable_service_boot) then 
                    trdos <= '1'; -- 1 - boot into service rom, 0 - boot into 128 menu
                else 
                    trdos <= '0';
                end if;
            elsif clk14'event and clk14 = '1' then 
                if N_M1 = '0' and N_MREQ = '0' and A(15 downto 8) = X"3D" and port_7ffd(4) = '1' then 
                    trdos <= '1';
                elsif N_M1 = '0' and N_MREQ = '0' and A(15 downto 14) /= "00" then 
                    trdos <= '0'; 
                end if;
            end if;
        end process;
    end generate G_TRDOS_FLAG;

    -- memory manager
    U1: entity work.memory 
    generic map (
        enable_divmmc => enable_divmmc,
        enable_zcontroller => enable_zcontroller
    )
    port map ( 
        CLK14 => CLK14,
        CLK7  => CLK_7,
        HCNT0 => hcnt0,        
        BUS_N_ROMCS => BUS_N_ROMCS,
        
        -- cpu signals
        A => A,
        D => D,
        N_MREQ => N_MREQ,
        N_IORQ => N_IORQ,
        N_WR => N_WR,
        N_RD => N_RD,
        N_M1 => N_M1,

        -- ram 
        MA => MA,
        MD => MD,
        N_MRD => N_MRD,
        N_MWR => N_MWR,
        
        -- ram out to cpu
        DO => ram_do,
        N_OE => ram_oe_n,
        
        -- ram pages
        RAM_BANK => port_7ffd(2 downto 0),

        -- divmmc
        DIVMMC_A => divmmc_sram_hiaddr,
        IS_DIVMMC_RAM => divmmc_ram,
        IS_DIVMMC_ROM => divmmc_rom,

        -- video
        VA => vid_a,
        VID_PAGE => port_7ffd(3),

        -- video bus control signals
        VBUS_MODE_O => vbus_mode, -- video bus mode: 0 - ram, 1 - vram
        VID_RD_O => vid_rd, -- read bitmap or attribute from video memory
        
        -- TRDOS 
        TRDOS => trdos,
        
        -- rom
        ROM_BANK => port_7ffd(4),
        ROM_A14 => ROM_A14,
        ROM_A15 => ROM_A15,
        N_ROMCS => N_ROMCS        
    );
    
    -- divmmc interface
    G_DIVMMC: if enable_divmmc generate
        U2: entity work.divmmc
        port map (
            I_CLK        => clkcpu,
            I_CS        => '1',
            I_RESET        => not(N_RESET),
            I_ADDR        => A,
            I_DATA        => D,
            O_DATA        => divmmc_do,
            I_WR_N        => N_WR,
            I_RD_N        => N_RD,
            I_IORQ_N        => N_IORQ,
            I_MREQ_N        => N_MREQ,
            I_M1_N        => N_M1,
            
            O_WR                  => divmmc_wr,
            O_DISABLE_ZXROM => divmmc_disable_zxrom,
            O_EEPROM_CS_N      => divmmc_eeprom_cs_n,
            O_EEPROM_WE_N      => divmmc_eeprom_we_n,
            O_SRAM_CS_N      => divmmc_sram_cs_n,
            O_SRAM_WE_N      => divmmc_sram_we_n,
            O_SRAM_HIADDR     => divmmc_sram_hiaddr,
            
            O_CS_N        => divmmc_sd_cs_n,
            O_SCLK        => divmmc_sd_clk,
            O_MOSI        => divmmc_sd_di,
            I_MISO        => SD_DO);

        SD_N_CS <= divmmc_sd_cs_n;
        SD_CLK <= divmmc_sd_clk;
        SD_DI <= divmmc_sd_di;
    end generate G_DIVMMC;
        
    -- Z-Controller
    G_ZC: if enable_zcontroller generate
        U3: entity work.zcontroller 
        port map(
            RESET => not(N_RESET),
            CLK => clk_7,
            A => A(5),
            DI => D,
            DO => zc_do_bus,
            RD => zc_rd,
            WR => zc_wr,
            SDDET => '0',
            SDPROT => '0',
            CS_n => zc_sd_cs_n,
            SCLK => zc_sd_clk,
            MOSI => zc_sd_di,
            MISO => SD_DO
        );
        
        SD_N_CS <= zc_sd_cs_n;
        SD_CLK <= zc_sd_clk;
        SD_DI <= zc_sd_di;
    end generate G_ZC;
    
    -- video module
    U5: entity work.video 
    port map (
        CLK => CLK14,
        ENA7 => CLK_7,
        BORDER => border_attr,
        DI => MD,
        INT => N_INT,
        ATTR_O => attr_r, 
        A => vid_a,
        BLANK => open,
        RGB => rgb,
        I => i,
        HSYNC => hsync,
        VSYNC => vsync,
        VBUS_MODE => vbus_mode,
        VID_RD => vid_rd,
        HCNT0 => hcnt0,
        HCNT1 => hcnt1
    );
    
    VIDEO_R <= rgb(2);
    VIDEO_G <= rgb(1);
    VIDEO_B <= rgb(0);
    VIDEO_I <= i;
    VIDEO_CSYNC <= not (vsync xor hsync);
    
end;
