# DDR Serializer Design: Theory vs. Practice

This document explains the fundamental differences between the theoretical **DDR Serializer** design (commonly found in textbooks and academic diagrams) and the practical, glitch-free implementation used in the `MainBand_RD` serializer.

---

## 1. The Theoretical Design (Textbook DDR)

The classic textbook diagram represents the standard academic implementation of a Double Data Rate (DDR) serializer:

* **Architecture:**
  1. Two registers (Flip-Flops):
     - **Upper FF (Orange):** Triggered on the rising edge of the clock (`posedge CLK`).
     - **Lower FF (Blue):** Triggered on the falling edge of the clock (`negedge CLK`).
  2. A 2-to-1 Multiplexer (MUX) that selects between the outputs of the two FFs using the clock `CLK` directly as the select line:
     - When `CLK = 1`, the MUX selects the Upper FF.
     - When `CLK = 0`, the MUX selects the Lower FF.

* **Practical Issues (Why it is theoretical only):**
  This design suffers from a critical hardware issue called a **Race Condition** that occurs twice in every clock cycle:
  
  1. **At `posedge CLK`:**
     - The MUX select line transitions from `0` to `1` to select the Upper FF.
     - Simultaneously, the Upper FF captures a new value and its output changes.
     - Because the select line transitions at the exact same instant the data input to the MUX is changing, a **Race Condition** occurs, causing **glitches/spikes** on the output.
  
  2. **At `negedge CLK`:**
     - The MUX select line transitions from `1` to `0` to select the Lower FF.
     - Simultaneously, the Lower FF captures a new value and its output changes.
     - This causes another race condition and produces more glitches.

In high-speed physical layer protocols like **UCIe (Unified Chiplet Interconnect Express)**, which operate at multi-Gbps speeds, these glitches destroy signal integrity and make timing closure impossible.

---

## 2. The Practical Solution in `MainBand_RD` ([unit_mb_serializer.sv](file:///home/Local_Disk1/UCIe_Graduation_Project/GitHub-Repo/UCIe-3.0-PHY-layer/rtl/MainBand_RD/tx/unit_mb_serializer.sv))

To completely eliminate the race condition and produce a **glitch-free output**, the `MainBand_RD` implementation uses a technique called **Retiming**.

### Core Principle:
To prevent race conditions, the register selected by the MUX must be **perfectly stable** before the MUX switches to it. 
* The MUX selects the **Even Bits** when `CLK = 1`. Therefore, the register driving these bits must only update when the clock is `0` (`negedge CLK`).
* The MUX selects the **Odd Bits** when `CLK = 0`. Therefore, the register driving these bits must only update when the clock is `1` (`posedge CLK`).

### Retimed Hardware Implementation:
```systemverilog
// 1. Prepare data sources in the posedge domain
wire even_src = load_condition ? load_reg[0] : data_reg[0]; // Bit for HIGH phase
wire odd_src  = load_condition ? load_reg[1] : data_reg[1]; // Bit for LOW phase

reg even_q;     
reg odd_q;      
reg high_reg;   // Drives HIGH phase, retimed onto negedge
reg low_reg;    // Drives LOW phase, retimed onto posedge

// 2. Capture and align path latency on posedge
always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        even_q  <= 1'b0;
        odd_q   <= 1'b0;
        low_reg <= 1'b0;
    end else begin
        even_q  <= even_src;
        odd_q   <= odd_src;
        low_reg <= odd_q;      // Aligned to even_q latency, stable for negedge select
    end
end

// 3. Retime the High Phase onto the Negedge
always @(negedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        high_reg <= 1'b0;
    end else begin
        high_reg <= even_q;    // Updated on falling edge, stable for posedge select
    end
end

// 4. Glitch-Free MUX
assign SER_out = PLL_clk ? high_reg : low_reg;
```

---

## 3. Timing Trace Analysis

Assume we have parallel data `in_data = {..., D3, D2, D1, D0}` to serialize.

| Time (Cycles) | Clock Edge | Clock State (`PLL_clk`) | RTL Action | `low_reg` (Posedge Flop) | `high_reg` (Negedge Flop) | Output MUX `SER_out` (Selects `high_reg` if 1, `low_reg` if 0) | Stability & Race Analysis |
|---|---|---|---|---|---|---|---|
| **t = 0.0** | **Posedge** | `1` | `even_q` captures `D0`<br>`odd_q` captures `D1` | $low\_reg_{prev}$ | $high\_reg_{prev}$ | $high\_reg_{prev}$ (Old data) | **Stable:** `high_reg` does not change at posedge (it changes at negedge). No race. |
| **t = 0.5** | **Negedge** | `0` | `high_reg` captures `even_q` (`D0`) | $low\_reg_{prev}$ | `D0` | $low\_reg_{prev}$ (Old data) | **Stable:** `low_reg` does not change at negedge (it changes at posedge). No race. |
| **t = 1.0** | **Posedge** | `1` | `even_q` captures `D2`<br>`odd_q` captures `D3`<br>`low_reg` captures `odd_q` (`D1`) | `D1` | `D0` | `D0` (Even Bit 0) | **Stable:** `high_reg` holds `D0` and has been stable since `t = 0.5` (half-cycle setup). No glitches. |
| **t = 1.5** | **Negedge** | `0` | `high_reg` captures `even_q` (`D2`) | `D1` | `D2` | `D1` (Odd Bit 0) | **Stable:** `low_reg` holds `D1` and has been stable since `t = 1.0` (half-cycle setup). No glitches. |
| **t = 2.0** | **Posedge** | `1` | ... | `D3` | `D2` | `D2` (Even Bit 1) | **Stable:** `high_reg` holds `D2` and has been stable since `t = 1.5` (half-cycle setup). |

---

## 4. Design Comparison Summary

| Metric | Theoretical Design (Image) | Adopted `MainBand_RD` Design |
|---|---|---|
| **Register Clock Edges** | Pos-edge for Upper FF, Neg-edge for Lower FF. | Pipeline on pos-edge; even bit retimed on neg-edge, odd bit on pos-edge. |
| **Race Conditions** | Occurs twice per cycle (at both edges). | **None (Glitch-Free)**. |
| **Output Stability at MUX Switch** | MUX switches exactly when the selected FF is changing. | Selected data is stable for a full half-cycle before MUX selects it. |
| **ASIC/PHY Practicality** | Requires custom hard PHY cells (like ODDR) to avoid glitches. | **Fully synthesizable, standard cell-friendly, and safe for high-speed RTL.** |
