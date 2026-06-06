// =============================================================================
// Module : unit_lfsr_serial
// Description : Bit-serial LFSR scrambler / PRBS pattern generator with
//               32-bit output aggregator.
//
// Reference   : UCIe Specification Rev 3.0
//               §4.4.1, Figure 4-30 (LFSR), Figure 4-31 (shared-tap variant),
//               Table 4-4 (seeds).
//
// Polynomial  : X^23 + X^21 + X^16 + X^8 + X^5 + X^2 + 1
//               Tap positions (feedback XOR): {22, 20, 15, 7, 4, 1} (0-indexed)
//               Shift direction: MSB (D[22]) out first; new feedback bit enters
//               D[0] after shift (Galois-equivalent of Figure 4-30).
//
// Modes       : mode=0 → Scramble  : data_out = data_in XOR feedback_bit
//               mode=1 → Pattern-gen: internal data_in forced to 0
//                         (data_out = feedback_bit = raw PRBS)
//
// Aggregator  : 32-bit Serial-In Parallel-Out register. The first output bit
//               (earliest in time) lands in agg_word[0] (LSB-first packing).
//               agg_valid pulses high for one cycle when all 32 bits are ready
//               (counter rolls 31 → 0). Shares shift_en gating with the LFSR.
//
// Reset       : Asynchronous active-low (i_rst_n). Clears LFSR state to all-0,
//               zeroes the aggregator, and resets the window counter.
//
// Seed Load   : When seed_load is asserted for one cycle, the LFSR state
//               register is parallel-loaded from the seed LUT indexed by
//               (lane_num % 8). seed_load has PRIORITY over shift_en.
//
// Determinism : After seed_load, the LFSR produces the identical bit stream
//               every time regardless of prior state. TX and RX instances
//               loaded with the same seed and driven with the same shift_en
//               sequence will produce bit-identical streams on every cycle.
//
// Scope       : This module implements only the serial LFSR + aggregator.
//               Per-lane error comparison, 16-bit error counters, UI-group
//               masking, and multi-module instantiation are out of scope.
// =============================================================================

module unit_lfsr_serial (
    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    input  logic        clk,        // Per-UI shift / datapath clock
    input  logic        rst_n,      // Asynchronous active-low reset

    // -------------------------------------------------------------------------
    // Control
    // -------------------------------------------------------------------------
    input  logic        shift_en,   // Gated advance; holds state when low
    input  logic        seed_load,  // Single-cycle parallel seed load (priority)
    input  logic [3:0]  lane_num,   // Logical lane number; seed = lane_num % 8
    input  logic        mode,       // 0 = scramble, 1 = pattern-gen (data_in=0)

    // -------------------------------------------------------------------------
    // Data
    // -------------------------------------------------------------------------
    input  logic        data_in,    // Bit to scramble (ignored when mode=1)
    output logic        data_out,   // Serial scrambled / PRBS output bit

    // -------------------------------------------------------------------------
    // 32-bit Aggregator
    // -------------------------------------------------------------------------
    output logic [31:0] agg_word,   // Aggregated 32-bit window (LSB = first bit)
    output logic        agg_valid   // Pulse when agg_word updates
);

    // =========================================================================
    // Seed LUT — Table 4-4, UCIe 3.0
    // Index = lane_num mod 8 (x8 mode: lanes 0–7 map direct)
    // =========================================================================
    logic [22:0] SEED_LUT [0:7];
    assign SEED_LUT[0] = 23'h1DBFBC;
    assign SEED_LUT[1] = 23'h0607BB;
    assign SEED_LUT[2] = 23'h1EC760;
    assign SEED_LUT[3] = 23'h18C0DB;
    assign SEED_LUT[4] = 23'h010F12;
    assign SEED_LUT[5] = 23'h19CFC9;
    assign SEED_LUT[6] = 23'h0277CE;
    assign SEED_LUT[7] = 23'h1BB807;

    // =========================================================================
    // 23-bit LFSR State Register
    // =========================================================================
    logic [22:0] lfsr_state;

    // =========================================================================
    // Feedback computation
    // Polynomial: X^23 + X^21 + X^16 + X^8 + X^5 + X^2 + 1
    // Tap positions (0-indexed bit numbers): 22, 20, 15, 7, 4, 1
    //
    // Per Figure 4-30 the LFSR shifts toward the MSB; the feedback bit is
    // the XOR of all tapped positions and re-enters at D[0].
    //
    // feedback_bit is also the raw PRBS output (= data_out when mode=1).
    // =========================================================================
    wire feedback_bit = lfsr_state[22] ^ lfsr_state[20] ^ lfsr_state[15]
                      ^ lfsr_state[7]  ^ lfsr_state[4]  ^ lfsr_state[1];

    // =========================================================================
    // Effective data_in: force to 0 in pattern-gen mode
    // =========================================================================
    wire eff_data_in = (mode == 1'b0) ? data_in : 1'b0;

    // =========================================================================
    // Combinational output: scrambled bit = data_in XOR feedback
    // In pattern-gen mode (data_in=0) this reduces to feedback_bit itself.
    // =========================================================================
    wire serial_out = eff_data_in ^ feedback_bit;

    // Combinational output: available in the same cycle as data_in.
    // The consuming logic (serializer, aggregator) registers this as needed.
    assign data_out = serial_out;

    // =========================================================================
    // LFSR State Update
    //
    // Priority: seed_load > shift_en > hold
    //
    // On shift: D[22:1] <= D[21:0]  (shift left)
    //           D[0]    <= feedback_bit
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state <= 23'b0;
        end else if (seed_load) begin
            lfsr_state <= SEED_LUT[lane_num[2:0]];   // lane_num mod 8
        end else if (shift_en) begin
            lfsr_state <= {lfsr_state[21:0], feedback_bit};
        end
        // else: hold state (shift_en deasserted)
    end

    // =========================================================================
    // 32-bit SIPO Aggregator
    //
    // Shifts data_out into agg_shift_reg on every enabled cycle.
    // Bit order: first bit output goes into bit 0 (LSB-first), matching the
    // consuming 32-bit datapath / config width convention used in LFSR_TX.
    //
    // A mod-32 counter (agg_counter) tracks the position within the current
    // window. When agg_counter reaches 31, the completed word is latched into
    // agg_word, agg_valid pulses for one cycle, and the counter rolls to 0 to
    // start the next window with no gap.
    // =========================================================================
    logic [31:0] agg_shift_reg;
    logic [4:0]  agg_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agg_shift_reg <= 32'b0;
            agg_counter   <= 5'b0;
            agg_word      <= 32'b0;
            agg_valid     <= 1'b0;
        end else if (seed_load) begin
            // Reset aggregator state on seed reload to align new sequence
            agg_shift_reg <= 32'b0;
            agg_counter   <= 5'b0;
            agg_word      <= 32'b0;
            agg_valid     <= 1'b0;
        end else if (shift_en) begin
            // Shift new bit into MSB; oldest bit stays in LSB
            // This packs bit N of the stream into agg_shift_reg[N % 32].
            agg_shift_reg <= {serial_out, agg_shift_reg[31:1]};
            
            if (agg_counter == 5'd31) begin
                // Window complete: latch and pulse
                agg_word  <= {serial_out, agg_shift_reg[31:1]};
                agg_valid <= 1'b1;
                agg_counter <= 5'd0;
            end else begin
                agg_valid   <= 1'b0;
                agg_counter <= agg_counter + 5'd1;
            end
        end else begin
            // shift_en deasserted: hold everything, clear valid pulse
            agg_valid <= 1'b0;
        end
    end

endmodule
