library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity micro_cpu is
    Port ( 
        clk   : in  STD_LOGIC;
        rst   : in  STD_LOGIC;
        out_bus : out STD_LOGIC_VECTOR(7 downto 0) -- For monitoring accumulator
    );
end micro_cpu;

architecture Behavioral of micro_cpu :

    -- 8-bit System CPU Registers
    signal PC  : unsigned(7 downto 0) := (others => '0');
    signal MAR : unsigned(7 downto 0) := (others => '0');
    signal IR  : std_logic_vector(7 downto 0) := (others => '0');
    signal ACC : unsigned(7 downto 0) := (others => '0');
    
    -- Internal Shared System Data Bus
    signal sys_bus : std_logic_vector(7 downto 0);
    
    -- Microcode Control Engine Signals
    signal uPC          : integer range 0 to 31 := 0;
    signal control_word : std_logic_vector(15 downto 0);
    
    -- Microcode Aliases for cleaner control logic mapping
    signal PC_out  : std_logic; signal PC_inc  : std_logic;
    signal MAR_in  : std_logic; signal RAM_out : std_logic;
    signal RAM_in  : std_logic; signal IR_in   : std_logic;
    signal ACC_in  : std_logic; signal ACC_out : std_logic;
    signal ALU_op  : std_logic_vector(1 downto 0);
    signal ALU_out : std_logic; signal uPC_rst : std_logic;
    signal uPC_jmp : std_logic;

    -- Dummy Internal RAM (Address 0 to 15)
    type ram_type is array (0 to 15) of std_logic_vector(7 downto 0);
    signal RAM : ram_type := (
        0 => "00010000", -- Instruction 0: LDA (Opcode "0001") from RAM location 0
        1 => "00001010", -- Operand for Address 0: (RAM address 10 contains value 0x0A)
        2 => "00100000", -- Instruction 1: ADD (Opcode "0010") from RAM location 1
        3 => "00001011", -- Operand for Address 1: (RAM address 11 contains value 0x05)
        4 => "00110000", -- Instruction 2: HALT / Reset uPC loop 
        others => "00000000"
    );

    -- Control ROM Configuration Type
    type control_rom_type is array (0 to 31) of std_logic_vector(15 downto 0);
    
    -- Microcode Memory Definition
    -- Opcode Mapping Layout: Fetch starts at 0. LDA executes at 4. ADD executes at 8.
    constant CONTROL_ROM : control_rom_type := (
        -- --- CYCLE 0 to 2: FETCH INSTRUCTION ---
        0 => "1010000000000000", -- [Step 0] PC_out, MAR_in (Move PC to Address pointer)
        1 => "0101010000000000", -- [Step 1] PC_inc, RAM_out, IR_in (Fetch Instruction to IR)
        2 => "0000000000001000", -- [Step 2] uPC_jmp (Evaluate Opcode & jump to microaddress)
        3 => "0000000000010000", -- [Step 3] Safety catch: Reset to 0
        
        -- --- LDA OPERATION (Opcode 0001xxxx -> Jumps to Microaddress 4) ---
        4 => "1010000000000000", -- [Step 4] PC_out, MAR_in (Fetch Operand Pointer)
        5 => "0101000000000000", -- [Step 5] PC_inc, RAM_out, MAR_in (Load target address)
        6 => "0000011000000000", -- [Step 6] RAM_out, ACC_in (Read variable value to Accumulator)
        7 => "0000000000010000", -- [Step 7] uPC_rst (Instruction complete, loop to Fetch)
        
        -- --- ADD OPERATION (Opcode 0010xxxx -> Jumps to Microaddress 8) ---
        8 => "1010000000000000", -- [Step 8] PC_out, MAR_in
        9 => "0101000000000000", -- [Step 9] PC_inc, RAM_out, MAR_in
        10=> "0000010001100000", -- [Step 10] RAM_out, ALU_op="01" (ADD), ALU_out, ACC_in
        11=> "0000000000010000", -- [Step 11] uPC_rst
        
        others => "0000000000010000"
    );

    -- Internal ALU Wire Signal
    signal alu_result : unsigned(7 downto 0);

begin

    -- Control Word Bit Vector Mapping
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

    -- Driving the Central Shared Tri-state Data Bus
    sys_bus <= std_logic_vector(PC) when PC_out = '1' else
               std_logic_vector(ACC) when ACC_out = '1' else
               RAM(to_integer(MAR)) when RAM_out = '1' else
               std_logic_vector(alu_result) when ALU_out = '1' else
               (others => 'Z');

    -- Arithmetic Logic Unit Combinational Logic
    process(ALU_op, ACC, sys_bus)
    begin
        case ALU_op is
            when "01" => 
                alu_result <= ACC + unsigned(sys_bus); -- ADD
            when "10" => 
                alu_result <= ACC - unsigned(sys_bus); -- SUB
            when others => 
                alu_result <= unsigned(sys_bus);       -- Pass-through
        end case;
    end process;

    -- Sequential Clocked Processing Core
    process(clk, rst)
    begin
        if rst = '1' then
            PC   <= (others => '0');
            MAR  <= (others => '0');
            IR   <= (others => '0');
            ACC  <= (others => '0');
            uPC  <= 0;
        elsif rising_edge(clk) then
            
            -- Handle register writes based on active control micro-operations
            if PC_inc = '1' then
                PC <= PC + 1;
            end if;
            
            if MAR_in = '1' then
                MAR <= unsigned(sys_bus);
            end if;
            
            if IR_in = '1' then
                IR <= sys_bus;
            end if;
            
            if ACC_in = '1' then
                ACC <= unsigned(sys_bus);
            end if;
            
            if RAM_in = '1' then
                RAM(to_integer(MAR)) <= sys_bus;
            end if;

            -- Microprogram Counter Sequencer Step Execution
            if uPC_rst = '1' then
                uPC <= 0;
            elsif uPC_jmp = '1' then
                -- Maps Instruction Opcode upper 4 bits to 
                -- explicit Control ROM entry zones (e.g. Opcode 0001 -> Block 4)
                uPC <= to_integer(unsigned(IR(7 downto 4))) * 4;
            else
                uPC <= uPC + 1;
            end if;
            
        end if;
    end process;

    -- Keep internal state observable
    out_bus <= std_logic_vector(ACC);

end Behavioral;

