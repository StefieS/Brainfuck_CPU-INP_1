-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
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
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0);  -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);   -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                     -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                     -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is


signal PC       : std_logic_vector(12 downto 0);
signal PC_INC   : std_logic;
signal PC_DEC   : std_logic;

signal PTR      : std_logic_vector(12 downto 0);
signal PTR_INC  : std_logic;
signal PTR_DEC  : std_logic;

signal TMP      : std_logic_vector(7 downto 0);
signal TMP_LD   : std_logic;

signal MX_1_SEL : std_logic;
signal MX_2_SEL : std_logic_vector(1 downto 0);

signal CNT      : std_logic_vector(7 downto 0);
signal CNT_INC  : std_logic;
signal CNT_DEC  : std_logic;
signal CNT_TO_ONE : std_logic;


type FSMstate is (idle, find_start, fetch, decode, 
                    execute_ptr_inc, execute_ptr_dec, execute_dereferenced_ptr_inc_rd,
                    execute_dereferenced_ptr_dec_rd, execute_dereferenced_ptr_inc_wr,
                    execute_dereferenced_ptr_dec_wr, execute_print_rd, execute_print_wr,
                    execute_wait_for_input, execute_take_input, execute_save_to_tmp_rd,
                    execute_save_to_tmp_wr, execute_tmp_to_wdata, execute_while_beg,
                    execute_while_beg_zero, execute_while_beg_jmp_rd, execute_while_beg_jmp_check,
                    execute_while_beg_cnt_check, execute_while_end, execute_while_end_zero,
                    execute_while_end_jmp_rd, execute_while_end_jmp_check, execute_while_end_cnt_check,
                    halt);
signal PSTATE : FSMstate;
signal NSTATE : FSMstate;
begin
                                    
  P_PC : process (CLK, RESET, PC_INC, PC_DEC)
  begin
       if (RESET = '1') then
            PC <= (others => '0');
       elsif (rising_edge(CLK)) then
            if (PC_INC = '1') then
                 PC <= PC + 1;
            elsif (PC_DEC = '1') then
                 PC <= PC - 1;
            end if;
       end if;
  end process;

  P_PTR : process (CLK, RESET, PTR_INC, PTR_DEC)
  begin
        if (RESET = '1') then 
            PTR <= (others => '0');
        elsif (rising_edge(CLK)) then
            if (PTR_INC = '1') then
                    PTR <= PTR + 1;
            elsif (PTR_DEC = '1') then
                    PTR <= PTR - 1;
            end if;
        end  if;
  end process;

  P_TMP : process(CLK, RESET, TMP_LD, DATA_RDATA)
  begin
        if (RESET = '1') then 
            TMP <= (others => '0');
        elsif (rising_edge(CLK)) then
            if (TMP_LD = '1') then
                TMP <= DATA_RDATA;
            end if;
        end if;
  end process;

  P_MX_1 : process(PTR, PC, MX_1_SEL)
  begin
        case MX_1_SEL is
            when '0' => DATA_ADDR <= PTR;
            when '1' => DATA_ADDR <= PC; 
            when others => null;
        end case;
  end process;

  P_MX_2 : process(IN_DATA, TMP, MX_2_SEL, DATA_RDATA)
  begin
        case MX_2_SEL is
            when "00"   => DATA_WDATA <= IN_DATA;
            when "01"   => DATA_WDATA <= TMP;
            when "10"   => DATA_WDATA <= DATA_RDATA - 1;
            when "11"   => DATA_WDATA <= DATA_RDATA + 1;
            when others => null;
        end case;
  end process;

  P_CNT : process (CLK, RESET, CNT_INC, CNT_DEC, CNT_TO_ONE)
  begin
        if (RESET = '1') then
            CNT <= (others => '0');
        elsif (rising_edge(CLK)) then
            if (CNT_TO_ONE = '1') then 
                CNT <= x"01";
            elsif (CNT_INC = '1') then
                CNT <= CNT + 1;
            elsif (CNT_DEC = '1') then
                CNT <= CNT - 1;
            end if;
        end if;
  end process;

  P_PSTATE : process(CLK, RESET)
  begin
          if (RESET = '1') then
               PSTATE <= idle;
          elsif (rising_edge(CLK)) then
               PSTATE <= NSTATE;
          end if;
  end process;

  P_NSTATE : process(PSTATE, IN_VLD, OUT_BUSY, DATA_RDATA, EN)
  begin
        DATA_EN   <= '0';
        DATA_RDWR <= '0';
        IN_REQ    <= '0';
        OUT_WE    <= '0';
        OUT_DATA  <= X"00";
        PC_INC    <= '0';
        PC_DEC    <= '0';
        PTR_INC   <= '0';
        PTR_DEC   <= '0';
        MX_1_SEL  <= '0';
        MX_2_SEL  <= "00";
        TMP_LD <= '0';
        IN_REQ <= '0';
        OUT_WE <= '0';
        OUT_DATA <= (others => '0');
        CNT_INC <='0';
        CNT_DEC <='0';
        CNT_TO_ONE <= '0';
        OUT_INV <= '0';

        case PSTATE is
            
            when idle =>
                READY <= '0';
                DONE <= '0';
                if (EN = '1') then
                    NSTATE <= find_start; 
                else
                    NSTATE <= idle;                    
                end if;

            when find_start =>
                if (EN = '1') then
                    DATA_RDWR <= '1';
                    DATA_EN   <= '1'; 
                    if (DATA_RDATA = x"40") then
                        NSTATE <= fetch;
                        READY <= '1';
                    else
                        PTR_INC <= '1';
                        NSTATE <= find_start;
                    end if;
                end if;

            when fetch =>
                if (EN = '1') then                  
                    NSTATE  <= decode;
                    MX_1_SEL  <= '1';
                    DATA_RDWR <= '1'; 
                    DATA_EN   <= '1';   
                else
                    NSTATE <= idle;
                end if;

            when decode =>
                case (DATA_RDATA) is
                    when x"40" => NSTATE <= halt;
                    when x"3E" => NSTATE <= execute_ptr_inc;
                    when x"3C" => NSTATE <= execute_ptr_dec;
                    when x"2B" => NSTATE <= execute_dereferenced_ptr_inc_rd;
                    when x"2D" => NSTATE <= execute_dereferenced_ptr_dec_rd;
                    when x"2E" => NSTATE <= execute_print_rd;
                    when x"2C" => NSTATE <= execute_wait_for_input;
                    when x"24" => NSTATE <= execute_save_to_tmp_rd;
                    when x"21" => NSTATE <= execute_tmp_to_wdata;
                    when x"5B" => NSTATE <= execute_while_beg;
                    when X"5D" => NSTATE <= execute_while_end;
                    when others => 
                                    NSTATE <= fetch;
                                    PC_INC  <= '1';
                end case;  

            when execute_ptr_dec =>     
                PTR_DEC <= '1';      
                PC_INC  <= '1';
                NSTATE <= fetch;

            when execute_ptr_inc =>    
                PTR_INC <= '1';   
                PC_INC  <= '1';
                NSTATE <= fetch;
 
            when execute_dereferenced_ptr_inc_rd =>  
                DATA_RDWR <= '1';
                DATA_EN <= '1';
                NSTATE <= execute_dereferenced_ptr_inc_wr;

            when execute_dereferenced_ptr_inc_wr =>
                MX_2_SEL <= "11";   
                DATA_RDWR <= '0';
                DATA_EN <= '1';
                PC_INC  <= '1';
                NSTATE <= fetch;

            when execute_dereferenced_ptr_dec_rd =>
                DATA_EN <= '1';             
                DATA_RDWR <= '1';
                NSTATE <= execute_dereferenced_ptr_dec_wr;

            when execute_dereferenced_ptr_dec_wr =>
                DATA_EN <= '1';              
                DATA_RDWR <= '0';
                MX_2_SEL <= "10";
                PC_INC  <= '1';
                NSTATE <= fetch;

            when execute_print_rd =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                PC_INC  <= '1';
                NSTATE <= execute_print_wr;

            when execute_print_wr =>
                if (OUT_BUSY = '1') then
                    NSTATE <= execute_print_wr;
                else
                    OUT_WE <= '1';
                    OUT_DATA <= DATA_RDATA;
                    NSTATE <= fetch;
                end if;

            when execute_wait_for_input =>
                IN_REQ <= '1';
                if (IN_VLD = '0') then
                    NSTATE <= execute_wait_for_input;
                else 
                    NSTATE <= execute_take_input;
                end if;

            when execute_take_input =>
                PC_INC  <= '1';
                DATA_EN <= '1';
                NSTATE <= fetch;

            when execute_save_to_tmp_rd =>
                DATA_RDWR <= '1'; 
                DATA_EN <= '1';
                NSTATE <= execute_save_to_tmp_wr;

            when execute_save_to_tmp_wr =>
                TMP_LD <='1';
                PC_INC  <= '1';
                NSTATE <= fetch;

            when execute_tmp_to_wdata =>
                DATA_EN <= '1'; 
                DATA_RDWR <= '0';
                MX_2_SEL <= "01";
                PC_INC  <= '1';
                NSTATE <= fetch;
                
            when execute_while_beg =>
                DATA_RDWR <= '1'; 
                DATA_EN <= '1';
                PC_INC <= '1';
                NSTATE <= execute_while_beg_zero;

            when execute_while_beg_zero =>
                if (DATA_RDATA = x"00") then
                    CNT_TO_ONE <= '1';
                    NSTATE <= execute_while_beg_jmp_rd;
                else
                    NSTATE <= fetch;
                end if;
            
            when execute_while_beg_jmp_rd =>
                DATA_RDWR <= '1'; 
                DATA_EN <= '1';
                MX_1_SEL <= '1';
                NSTATE <= execute_while_beg_jmp_check;

            when execute_while_beg_jmp_check =>
                if (DATA_RDATA = x"5B") then
                    CNT_INC <= '1';
                elsif (DATA_RDATA = x"5D") then
                    CNT_DEC <= '1';
                end if;
                NSTATE <= execute_while_beg_cnt_check;

            when execute_while_beg_cnt_check =>
                if (CNT = x"00") then
                    NSTATE <= fetch;
                else
                    NSTATE <= execute_while_beg_jmp_rd; 
                end if;
                PC_INC <= '1';

            when execute_while_end =>
                DATA_RDWR <= '1'; 
                DATA_EN <= '1';
                NSTATE <= execute_while_end_zero;
                
            when execute_while_end_zero =>
                if (DATA_RDATA = x"00") then
                   PC_INC <= '1';
                   NSTATE <= fetch;
                else
                    PC_DEC <= '1';
                    CNT_TO_ONE <= '1';
                    NSTATE <= execute_while_end_jmp_rd;
                end if;

            when execute_while_end_jmp_rd =>
                DATA_RDWR <= '1'; 
                DATA_EN <= '1';
                MX_1_SEL <= '1';
                NSTATE <= execute_while_end_jmp_check;
            
            when execute_while_end_jmp_check =>
                if (DATA_RDATA = x"5B") then
                    CNT_DEC <= '1';
                elsif (DATA_RDATA = x"5D") then
                    CNT_INC <= '1';
                end if;
                NSTATE <= execute_while_end_cnt_check;
            
            when execute_while_end_cnt_check =>
                if (CNT = x"00") then
                    PC_INC <= '1';
                    NSTATE <= fetch;
                else
                    PC_DEC <= '1';
                    NSTATE <= execute_while_end_jmp_rd;
                end if;
            
            when halt =>
                DONE <= '1';
                NSTATE <= halt;
        end case;
  end process;
    

-- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

end behavioral;

