# Micro_Spartan6

**μCPU-8** is a minimal 8-bit accumulator CPU written in VHDL. A 16-bit microcode control ROM sequences every instruction instead of hardwired decode logic. It targets Xilinx Spartan-6 FPGAs with **ISE 14.7 WebPACK** and is tested on the Digilent **Nexys 3**. The CPU steps about three times per second, so you can watch a program run on the board's LEDs.

## Features

- **Microcoded control unit**: a 32 × 16-bit control ROM drives the fetch, decode and execute steps.
- **Multiplexed internal bus**: a priority mux replaces internal tri-states (`'Z'`), which Spartan-6 does not support.
- **Single clock domain**: everything runs on the 100 MHz oscillator. A 25-bit counter produces a one-cycle clock enable (~3 Hz) that advances the CPU, so there is no derived clock.
- **Synthesizable RTL**: standard synchronous VHDL-93 with no vendor primitives.

## Repository layout

| File | Description |
| :--- | :--- |
| `spartan6_micro_cpu.vhd` | Top-level CPU (datapath, ALU, control ROM, sequencer) |
| `nexys3.ucf` | Pin and timing constraints for the Nexys 3 |

## Architecture

```text
                   +------------------------------------+
                   |            CONTROL UNIT            |
                   |  +------+  opcode  +------------+  |
                   |  |  IR  |--------->|  uPC  ->   |  |
                   |  +------+          | Control ROM|  |
                   |     ^              +------------+  |
                   +-----|--------------------|---------+
                         |                    | 16-bit control word
                         |                    v (to every block)
    ======================================================  sys_bus (8-bit mux)
       |    ^        |          ^                 ^    |
       v    |        v          |                 |    v
     +--------+   +-----+   +-------+   +-----+   +-------+
     |   PC   |   | MAR |-->|  RAM  |-->| ALU |<--|  ACC  |--> LEDs
     +--------+   +-----+   | 16x8  |   +-----+   +-------+
                            +-------+
```

The ALU takes its second operand directly from RAM, not from the bus. This keeps the ALU output from feeding back into its own input (no combinational loop).

### Bus sources (priority order)

`PC_out` > `ACC_out` > `RAM_out` > `ALU_out`. If no source is asserted, the bus is `0x00`.

### 16-bit control word

| Bit(s) | Signal | Function |
| :--- | :--- | :--- |
| 15 | `PC_out` | Drive the program counter onto the bus |
| 14 | `PC_inc` | Increment the program counter |
| 13 | `MAR_in` | Load the bus into the memory address register |
| 12 | `RAM_out` | Drive `RAM[MAR]` onto the bus |
| 11 | `RAM_in` | Write the bus into `RAM[MAR]` |
| 10 | `IR_in` | Load the bus into the instruction register |
| 9 | `ACC_in` | Load the bus into the accumulator |
| 8 | `ACC_out` | Drive the accumulator onto the bus |
| 7–6 | `ALU_op` | `00` = pass, `01` = ADD, `10` = SUB |
| 5 | `ALU_out` | Drive the ALU result onto the bus |
| 4 | `uPC_rst` | Return the micro-PC to 0 (next fetch) |
| 3 | `uPC_jmp` | Jump to the instruction's microroutine (`opcode × 4`) |
| 2 | `HALT` | When this is the only bit set, the sequencer branches to step 12 (halt loop) |
| 1–0 | — | Unused |

## Instruction set

Each instruction is two bytes: an opcode byte (opcode in bits 6–4, lower nibble ignored) followed by an address byte. The jump only uses opcode bits 6–4, so bit 7 is ignored and each opcode's microroutine starts at `opcode × 4`.

| Opcode | Mnemonic | Operation | Microcode steps |
| :--- | :--- | :--- | :--- |
| `0001` | `LDA addr` | `ACC ← RAM[addr]` | 4–7 |
| `0010` | `ADD addr` | `ACC ← ACC + RAM[addr]` | 8–11 |
| `0011` | `HALT` | Stop (loop in microcode) | 12–15 |
| `0000`, `0100`–`0111` | — | No operation (returns to fetch) | — |

**Common fetch (steps 0–3):** `MAR ← PC`, then `IR ← RAM[MAR], PC ← PC + 1`, then jump to `opcode × 4`.

The ALU also implements SUB (`ALU_op = 10`). Adding a `SUB` instruction only takes a new microroutine in the control ROM.

## Demo program

| Address | Contents | Meaning |
| :--- | :--- | :--- |
| 0–1 | `0x10`, `0x0A` | `LDA [10]` |
| 2–3 | `0x20`, `0x0B` | `ADD [11]` |
| 4 | `0x30` | `HALT` |
| 10 | `0x0A` | Data: 10 |
| 11 | `0x05` | Data: 5 |

Result: `ACC = 10 + 5 = 15` (`0x0F`).

## Building with ISE 14.7

1. Create a new project with these device settings (Nexys 3):
   - Family `Spartan6`, device `XC6SLX16`, package `CSG324`, speed `-3`
   - Synthesis tool: XST, preferred language: VHDL
2. Add `spartan6_micro_cpu.vhd` and `nexys3.ucf`, and set `spartan6_micro_cpu` as the top module.
3. Run **Generate Programming File**.
4. Program the board with iMPACT or Digilent Adept.

### Pin constraints (Nexys 3)

`nexys3.ucf` contains the following:

```ucf
NET "clk" LOC = "V10" | IOSTANDARD = "LVCMOS33";
NET "clk" TNM_NET = "sys_clk_pin";
TIMESPEC "TS_sys_clk_pin" = PERIOD "sys_clk_pin" 100 MHz HIGH 50%;

NET "rst" LOC = "B8" | IOSTANDARD = "LVCMOS33";   # BTNS (center button)

NET "out_bus<0>" LOC = "U16" | IOSTANDARD = "LVCMOS33";
NET "out_bus<1>" LOC = "V16" | IOSTANDARD = "LVCMOS33";
NET "out_bus<2>" LOC = "U15" | IOSTANDARD = "LVCMOS33";
NET "out_bus<3>" LOC = "V15" | IOSTANDARD = "LVCMOS33";
NET "out_bus<4>" LOC = "M11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<5>" LOC = "N11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<6>" LOC = "R11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<7>" LOC = "T11" | IOSTANDARD = "LVCMOS33";
```

### Other Spartan-6 boards

The VHDL is portable, but the UCF is for the Nexys 3 only. On another board, such as the Atlys (`XC6SLX45-3CSG484`), change the device settings and take the pin locations from that board's master UCF. Check the reset button's polarity too: this design expects an active-high reset.

## Expected behavior on the board

1. Press **BTNS**. All LEDs turn off (`00000000`).
2. After about 2 seconds, `LDA` completes: LD3 and LD1 light up (`00001010` = 10).
3. After about 2 more seconds, `ADD` completes: the LEDs show `00001111` (15).
4. The CPU enters the `HALT` loop and holds 15 on the LEDs until the next reset.

## Simulation

To simulate in ISim, temporarily tie `tick` to `'1'` so the CPU advances every clock cycle instead of every 2²⁵ cycles. Watch `uPC`, `PC`, `MAR`, `IR` and `ACC`. `ACC` should reach `0x0F` within about 20 clock cycles.

## Limitations

- RAM is 16 bytes. Only `MAR(3 downto 0)` is used for addressing.
- There are no flags, conditional jumps, or I/O instructions yet.
- The program is set by the RAM initializer in the VHDL. Changing it requires re-synthesizing.

## License

Add a license of your choice (for example MIT) in a `LICENSE` file.
