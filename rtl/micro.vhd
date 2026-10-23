library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spartan6_micro_cpu is
    Port ( 
        clk     : in  STD_LOGIC;  -- 100MHz onboard oscillator (Pin V10 on Nexys3)
        rst     : in  STD_LOGIC;  -- Pushbutton reset (Pin B8 on Nexys3)
        out_bus : out STD_LOGIC_VECTOR(7 downto 0) -- 8 LEDs for visual confirmation
    );
end spartan6_micro_cpu;

architecture Behavioral of spartan6_micro_cpu is

    -- Clock Divider Signal
    signal clk_div : unsigned(25 downto 0) := (others => '0');
    signal cpu_clk : std_logic;

    -- 8-bit System CPU Registers
    signal PC  : unsigned(7 downto 0) := (others => '0');
    signal MAR : unsigned(7 downto 0) := (others => '0');
    signal IR  : std_logic_vector(7 downto 0) := (others => '0');
    signal ACC : unsigned(7 downto 0) := (others => '0');
    
    -- Optimized Internal Multiplexer Bus
    signal sys_bus : std_logic_vector(7 downto 0);
    
    -- Microcode Control Engine Signals
    signal uPC          : integer range 0 to 31 := 0;
    signal control_word : std_logic_vector(15 downto 0);
    
    -- Control Word Decoders
    signal PC_out, PC_inc   : std_logic;
    signal MAR_in, RAM_out  : std_logic;
    signal RAM_in, IR_in    : std_logic;
    signal ACC_in, ACC_out  : std_logic;
    signal ALU_op           : std_logic_vector(1 downto 0);
    signal ALU_out, uPC_rst : std_logic;
    signal uPC_jmp          : std_logic;

    -- Internal RAM Program Space
    type ram_type is array (0 to 15) of std_logic_vector(7 downto 0);
    signal RAM : ram_type := (
        0 => "00010000", -- Instruction 0: LDA (Opcode 0001) from address 10
        1 => "00001010", -- Operand: RAM address 10
        2 => "00100000", -- Instruction 1: ADD (Opcode 0010) from address 11
        3 => "00001011", -- Operand: RAM address 11
        4 => "00110000", -- Instruction 2: HALT Trap state
        5 => "00000100", 
        
        10 => "00001010", -- Data Variable: 10 (0x0A)
        11 => "00000101", -- Data Variable: 5  (0x05)
        others => "00000000"
    );

    -- Control ROM Configuration Block
    type control_rom_type is array (0 to 31) of std_logic_vector(15 downto 0);
    constant CONTROL_ROM : control_rom_type := (
        -- --- FETCH CYCLE ---
        0 => "1010000000000000", -- PC_out = 1, MAR_in = 1
        1 => "0101010000000000", -- PC_inc = 1, RAM_out = 1, IR_in = 1
        2 => "0000000000001000", -- uPC_jmp = 1 (Evaluate instruction)
        3 => "0000000000010000", 
        
        -- --- LDA OPERATION ---
        4 => "1010000000000000", -- PC_out = 1, MAR_in = 1
        5 => "0101000000000000", -- PC_inc = 1, RAM_out = 1, MAR_in = 1
        6 => "0000011000000000", -- RAM_out = 1, ACC_in = 1
        7 => "0000000000010000", -- uPC_rst = 1
        
        -- --- ADD OPERATION ---
        8 => "1010000000000000", -- PC_out = 1, MAR_in = 1
        9 => "0101000000000000", -- PC_inc = 1, RAM_out = 1, MAR_in = 1
        10=> "0000010001100000", -- RAM_out = 1, ALU_op = "01" (ADD), ALU_out = 1, ACC_in = 1
        11=> "0000000000010000", -- uPC_rst = 1
        
        -- --- HALT TRAP ROUTINE ---
        12=> "0000000000000000", -- Stalls here indefinitely
        13=> "0000000000000000", 
        14=> "0000000000000000",
        15=> "0000000000000100", -- Forces uPC branch back to step 12
        
        others => "0000000000010000"
    );

    signal alu_result : unsigned(7 downto 0);
    signal ram_data   : std_logic_vector(7 downto 0);

begin

    -- 1. Hardware Clock Divider Process
    -- 100,000,000 Hz / 2^26 = ~1.49 Hz blink-rate pulse
    process(clk)
    begin
        if rising_edge(clk) then
            clk_div <= clk_div + 1;
        end if;
    end process;
    
    -- Extract the MSB to drive our system clock sequentially
    cpu_clk <= clk_div(25);

    -- 2. Bus Decode & Microcode Static Direct Wire Assignments
    control_word <= CONTROL_ROM(uPC);
    
    PC_out  <= control_word(15);
    PC_inc  <= control_word(14);
    MAR_in  <= control_word(13);
    RAM_out <= control_word(12);
    RAM_in  <= control_word(11);
    IR_in   <= control_word(10);
    ACC_in  <= control_word(9);
    ACC_out <= control_word(8);
    ALU_op  <= control_word(7 downto 6);
    ALU_out <= control_word(5);
    uPC_rst <= control_word(4);
    uPC_jmp <= control_word(3);

    ram_data <= RAM(to_integer(MAR));

    -- Clean MUX-Based Internal Datapath Bus Configuration
    process(PC_out, ACC_out, RAM_out, ALU_out, PC, ACC, ram_data, alu_result)
    begin
        if PC_out = '1' then
            sys_bus <= std_logic_vector(PC);
        elsif ACC_out = '1' then
            sys_bus <= std_logic_vector(ACC);
        elsif RAM_out = '1' then
            sys_bus <= ram_data;
        elsif ALU_out = '1' then
            sys_bus <= std_logic_vector(alu_result);
        else
            sys_bus <= (others => '0');
        end if;
    end process;

    -- ALU Core
    process(ALU_op, ACC, sys_bus)
    begin
        case ALU_op is
            when "01" => alu_result <= ACC + unsigned(sys_bus);
            when "10" => alu_result <= ACC - unsigned(sys_bus);
            when others => alu_result <= unsigned(sys_bus);
        end case;
    end process;

    -- 3. Core Synchronous Sequential Block running on slowed CPU Clock
    process(cpu_clk)
    begin
        if rising_edge(cpu_clk) then
            if rst = '1' then
                PC   <= (others => '0');
                MAR  <= (others => '0');
                IR   <= (others => '0');
                ACC  <= (others => '0');
                uPC  <= 0;
            else
                if PC_inc = '1' then PC <= PC + 1; end if;
                if MAR_in = '1' then MAR <= unsigned(sys_bus); end if;
                if IR_in = '1' then  IR <= sys_bus; end if;
                if ACC_in = '1' then ACC <= unsigned(sys_bus); end if;
                
                if RAM_in = '1' then
                    RAM(to_integer(MAR)) <= sys_bus;
                end if;

                -- Sequencer Execution Steps
                if uPC_rst = '1' then
                    uPC <= 0;
                elsif uPC_jmp = '1' then
                    uPC <= to_integer(unsigned(IR(7 downto 4))) * 4;
                elsif control_word = "0000000000000100" then
                    uPC <= 12; 
                else
                    uPC <= uPC + 1;
                end if;
            end if;
        end if;
    end process;

    -- Drive Board LEDs 
    out_bus <= std_logic_vector(ACC);

end Behavioral;
