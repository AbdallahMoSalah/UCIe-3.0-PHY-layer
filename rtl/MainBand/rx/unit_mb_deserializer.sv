`timescale 1ns/1ps
// =============================================================================
// Module : MB_DESERIALIZER   (SPEC-FIXED copy — lives in unsued/)
// =============================================================================
// Data-lane DDR deserializer. Mirrors MB_SERIALIZER: 2 bits per pll_clk cycle,
// LSB first, even bit word[2n] in the pll_clk HIGH phase, odd bit word[2n+1] in
// the LOW phase. Re-assembles the 32-bit parallel word and crosses pll_clk ->
// MB_clk via a toggle synchronizer.
//
// -----------------------------------------------------------------------------
// BUG IN THE PRODUCTION COPY (rtl/MainBand/MB_DeSerializer/unit_mb_deserializer.sv):
//   The shift ran on posedge and combined the CURRENT posedge bit with the
//   PREVIOUS negedge bit:
//        shift_reg <= {ser_data_in, r_data_neg, shift_reg[W-1:2]};
//   At posedge n this is {word[2n], word[2n-1]} — two bits from DIFFERENT DDR
//   cycles. Net effect: the captured word is the input shifted left by one bit
//   (word[31] dropped, a garbage/0 LSB inserted). E.g. 0x00000001 -> 0x00000002,
//   0x80000000 -> 0x00000000, 0xFFFFFFFF -> 0xFFFFFFFE. It never inverts the
//   serializer, so deserialize(serialize(x)) != x.
//
// FIX:
//   Pair the two bits that belong to the SAME pll_clk cycle. The even bit is
//   captured at the cycle's posedge (r_data_pos); the odd bit is on the line at
//   that cycle's negedge (ser_data_in). Do the shift on the NEGEDGE, when both
//   are valid for cycle n:
//        shift_reg <= {ser_data_in, r_data_pos, shift_reg[W-1:2]};
//                       \__odd 2n+1_/ \__even 2n_/
//   This yields save_data[j] == word[j] for all j (verified vs MB_SERIALIZER).
//   r_data_neg / r_data_det are no longer needed and were removed.
// =============================================================================
module unit_mb_deserializer #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_data_en,
    input  wire                   ser_data_in,
    input  wire                   enable_des_valid_frame,
    output reg  [DATA_WIDTH-1:0]  par_data_out,
    output reg                    de_ser_done
);

/* -------------------------------------------------- */
/* Internal Registers                                 */
/* -------------------------------------------------- */
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;
reg [5:0]            bit_cnt;

// Handshake registers for CDC (pll_clk -> MB_clk)
reg save_data_toggle;
reg sync1_toggle;
reg sync2_toggle;
reg sync3_toggle;
wire valid_pulse;

/* -------------------------------------------------- */
/* DDR Input Capture                                  */
/* -------------------------------------------------- */
// Even bit of the cycle is sampled on the rising edge.
reg r_data_pos;

always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else if (ser_data_en) begin
        r_data_pos <= ser_data_in;   // word[2n] (HIGH phase)
    end
end

/* -------------------------------------------------- */
/* Assemble word on the negedge (same-cycle pairing)  */
/* -------------------------------------------------- */
// At negedge n: r_data_pos = word[2n] (captured this cycle's posedge),
//               ser_data_in = word[2n+1] (LOW phase, live now).
// LSB first -> earlier (even) bit goes to the lower position of the pair.
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg        <= {DATA_WIDTH{1'b0}};
        bit_cnt          <= 6'd0;
        save_data        <= {DATA_WIDTH{1'b0}};
        save_data_toggle <= 1'b0;
    end else begin
        if (ser_data_en) begin
            shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};

            if (bit_cnt == (DATA_WIDTH/2) - 1) begin
                bit_cnt          <= 6'd0;
                save_data        <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
                save_data_toggle <= ~save_data_toggle; // Trigger CDC
            end else begin
                bit_cnt <= bit_cnt + 6'd1;
            end
        end else begin
            bit_cnt <= 6'd0;
        end
    end
end

/* -------------------------------------------------- */
/* Sync to MB_clk domain (Toggle Synchronizer)        */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sync1_toggle <= 1'b0;
        sync2_toggle <= 1'b0;
        sync3_toggle <= 1'b0;
    end else begin
        sync1_toggle <= save_data_toggle;
        sync2_toggle <= sync1_toggle;
        sync3_toggle <= sync2_toggle;
    end
end

assign valid_pulse = (sync2_toggle != sync3_toggle);

/* -------------------------------------------------- */
/* Load Output in MB_clk domain                       */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        par_data_out <= {DATA_WIDTH{1'b0}};
        de_ser_done  <= 1'b0;
    end else begin
        de_ser_done <= 1'b0; // Default off (pulse for 1 cycle)
        if (valid_pulse && enable_des_valid_frame) begin
            par_data_out <= save_data;
            de_ser_done  <= 1'b1;
        end
        else if (valid_pulse && !enable_des_valid_frame) begin
            par_data_out <= {DATA_WIDTH{1'b0}};
            de_ser_done  <= 1'b0;
        end
    end
end

endmodule