# Micro_Spartan6
Microprocesor based on microcode in Spartan 6

## μCPU-8: A Microcoded 8-Bit Microprocessor in VHDL

A minimal, fully functional 8-bit accumulator-based microprocessor architecture designed entirely in VHDL. This processor replaces complex hardwired combinational decoding networks with a **16-bit Microcode Control Word Memory (Control ROM)**. 

This project is tailored specifically for vintage **Xilinx Spartan-6 FPGAs** (such as Digilent's **Nexys 3** or **Atlys** development boards) using the legacy **Xilinx ISE 14.7 WebPACK** design suite. It features an onboard clock divider so you can watch your CPU execute instructions step-by-step using physical LEDs.

---

## 🚀 Key Features
* **Microcoded Engine:** A 32x16 Control ROM manages the entire fetch/execute sequence.
* **Internal Multiplexer Bus:** Optimized for Spartan-6 slices instead of unsupported internal tristate (`'Z'`) logic.
* **Onboard Logic Monitor:** Includes a 26-bit clock divider to step down a 100MHz master crystal to a highly visible ~1.5Hz execution clock.
* **Fully Synthesizable:** Written using pure synchronous register-transfer level (RTL) semantics compatible with standard ISE/PlanAhead toolchains.

---

## 📐 Architecture Block Diagram

```text
          +--------------------------------------------+

          |               CONTROL UNIT                 |
          |  +--------+    +-------------+             |
          |  |   IR   |--->| Control ROM |             |
          |  +--------+    +-------------+             |
          |                       | (16-bit Control    |
          |                       v  Word)             |
          +-----------------------|--------------------+
                                  | 
    +-----------------------------v--------------------+

    | DATAPATH                    |                    |
    |  +----+    +-----+    +-----------+    +------+  |
===>| PC |    | MAR |    |    ALU    |    |  ACC |==> Onboard 
Bus |    |    |     |    | (ADD/SUB) |    |      |  | LEDs
    +----+    +-----+    +-----------+    +------+  |
```

### 16-Bit Control Word Layout

| Bits | Label | Function |
| :--- | :--- | :--- |
| **15** | `PC_out` | Asserts Program Counter onto internal shared bus |
| **14** | `PC_inc` | Increments Program Counter register value by 1 |
| **13** | `MAR_in` | Latches system bus value into Memory Address Register |
| **12** | `RAM_out`| Loads memory contents at current MAR index onto bus |
| **11** | `RAM_in` | Writes current system bus data into RAM array |
| **10** | `IR_in`  | Latches system bus value into the Instruction Register |
| **9**  | `ACC_in` | Latches system bus data directly into the Accumulator |
| **8**  | `ACC_out`| Asserts Accumulator value onto the internal shared bus |
| **7..6**| `ALU_op` | ALU function selection: `00`=Pass, `01`=ADD, `10`=SUB |
| **5**  | `ALU_out`| Asserts Arithmetic Logic Unit output onto system bus |
| **4**  | `uPC_rst`| Forces Microprogram Counter back to `0` (Reset to Instruction Fetch) |
| **3**  | `uPC_jmp`| Commands micro-sequencer to branch based on Opcode upper nibble |
| **2..0**| *RFU* | Reserved for Future Use |

---

## 💾 Hardcoded Demo Program

The internal synchronous RAM contains an embedded mini-routine executing the following algorithm:

1. **`LDA [10]`**: Load value from memory address `10` (`0x0A` / Decimal 10) into Accumulator.
2. **`ADD [11]`**: Add value from memory address `11` (`0x05` / Decimal 5) to Accumulator.
3. **`HALT`**: Traps execution endlessly to preserve calculation results.

---

## 🛠️ Synthesizing on Xilinx ISE 14.7

### Target Device Settings
* **Nexys 3 Board:** Family: `Spartan6` | Device: `XC6SLX16` | Package: `CSG324` | Speed: `-3`
* **Atlys Board:** Family: `Spartan6` | Device: `XC6SLX45` | Package: `CSG484` | Speed: `-3`

### Physical Pins Pinout Constraints (`pins.ucf`)
Add the following to your User Constraints File to connect the core directly to the onboard hardware:

```config
# Master System Clock Input (100 MHz Oscillator)
NET "clk" LOC = "V10" | IOSTANDARD = "LVCMOS33";

# Central Core Reset Input (Center Pushbutton Switch)
NET "rst" LOC = "B8"  | IOSTANDARD = "LVCMOS33";

# 8 Output Diagnostic Line Map to Onboard Display LEDs
NET "out_bus<0>" LOC = "U16" | IOSTANDARD = "LVCMOS33";
NET "out_bus<1>" LOC = "V16" | IOSTANDARD = "LVCMOS33";
NET "out_bus<2>" LOC = "U15" | IOSTANDARD = "LVCMOS33";
NET "out_bus<3>" LOC = "V15" | IOSTANDARD = "LVCMOS33";
NET "out_bus<4>" LOC = "M11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<5>" LOC = "N11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<6>" LOC = "R11" | IOSTANDARD = "LVCMOS33";
NET "out_bus<7>" LOC = "T11" | IOSTANDARD = "LVCMOS33";
```

---

## 👀 Expected Hardware Behavior

Once flashed onto your physical Spartan-6 target hardware:
1. Press the **Reset Switch (B8)**. All diagnostic LEDs immediately switch off (`00000000`).
2. After ~5 seconds, the microcode transitions into the `LDA` phase, loading the value `10`. LEDs 3 and 1 turn on (`00001010`).
3. After ~5 more seconds, the microcode processes the `ADD` state. It pulls value `5` out of memory and performs addition. 
4. The LEDs update to showcase the final computation result: **`0x0F`** (`00001111`).
5. The CPU locks into its hardware trap loop, holding the correct total on the LEDs.

---



