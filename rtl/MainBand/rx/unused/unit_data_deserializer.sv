`timescale 1ns/1ps
// =============================================================================
// Module  : unit_data_deserializer
// Project : UCIe 3.0 Main-Band Physical Layer  (RX side)
// Purpose : Free-running DDR deserializer for a single data lane (RD_P[n]).
//
//  Operation
//  ---------
//  - Continuously shifts serial data into a 32-bit shift register using DDR
//    sampling (2 bits per pll_clk cycle, LSB first, same convention as
//    MB_SERIALIZER / MB_DESERIALIZER / Valid_Deserializer).
//  - NO counter, NO enable gating — the shift register runs freely.
//  - When `i_valid_frame_pulse` is asserted (single-cycle pulse from the
//    Valid_Frame_Detector), the current shift register value is captured
//    into a `save_data` register.
//  - The saved data is then crossed from the pll_clk domain into the
//    MB_clk (mb_clk) domain via a toggle synchroniser and presented on
//    `o_par_data` with a one-cycle `o_data_valid` pulse.
//
//  DDR bit pairing (matches MB_SERIALIZER)
//  ----------------------------------------
//   posedge n : capture even bit  word[2n]   → r_data_pos
//   negedge n : line carries odd  word[2n+1] → ser_data_in (live)
//   Shift on negedge:
//     shift_reg <= {ser_data_in, r_data_pos, shift_reg[31:2]}
// =============================================================================
module unit_data_deserializer #(
    parameter DATA_WIDTH = 32
)(
    // -------------------------------------------------------------------------
    // Clocks / Reset
    // -------------------------------------------------------------------------
    input  wire                   mb_clk,               // main-band local clock
    input  wire                   pll_clk,              // high-speed serialization clock
    input  wire                   i_rst_n,              // active-low async reset

    // -------------------------------------------------------------------------
    // Serial data input
    // -------------------------------------------------------------------------
    input  wire                   ser_data_in,          // serial data-lane input (RD_P[n])

    // -------------------------------------------------------------------------
    // Valid-frame pulse (from Valid_Frame_Detector, pll_clk domain)
    // -------------------------------------------------------------------------
    input  wire                   i_valid_frame_pulse,  // single-cycle capture trigger

    // -------------------------------------------------------------------------
    // Parallel output (mb_clk domain)
    // -------------------------------------------------------------------------
    output reg  [DATA_WIDTH-1:0]  o_par_data,           // deserialized parallel data
    output reg                    o_data_valid          // one-cycle pulse: o_par_data is fresh
);

// =========================================================================
// Internal registers
// =========================================================================
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;
reg                  r_data_pos;          // even-bit capture

// CDC toggle synchroniser registers (pll_clk → mb_clk)
reg save_toggle;      // toggled in pll_clk domain
reg sync1_toggle;     // 1st flop in mb_clk
reg sync2_toggle;     // 2nd flop in mb_clk
reg sync3_toggle;     // 3rd flop for edge detection

wire valid_pulse_mb;  // single-cycle pulse in mb_clk domain

// =========================================================================
// DDR Input Capture — posedge: capture even bit
// =========================================================================
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else begin
        r_data_pos <= ser_data_in;   // word[2n] — HIGH phase
    end
end

// =========================================================================
// Shift on negedge — pair even + odd from same cycle
// =========================================================================
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg   <= {DATA_WIDTH{1'b0}};
        save_data   <= {DATA_WIDTH{1'b0}};
        save_toggle <= 1'b0;
    end else begin
        // Free-running shift
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};

        // Capture on valid-frame pulse.
        // At this negedge, shift_reg still holds the COMPLETE data word
        // (set at the previous negedge via NBA, aligned with the valid frame).
        // We capture shift_reg — NOT the newly shifted value — to avoid
        // losing 2 bits due to the ongoing shift.
        if (i_valid_frame_pulse) begin
            save_data   <= shift_reg;
            save_toggle <= ~save_toggle;   // trigger CDC
        end
    end
end

// =========================================================================
// CDC: Toggle synchroniser (pll_clk → mb_clk)
// =========================================================================
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sync1_toggle <= 1'b0;
        sync2_toggle <= 1'b0;
        sync3_toggle <= 1'b0;
    end else begin
        sync1_toggle <= save_toggle;
        sync2_toggle <= sync1_toggle;
        sync3_toggle <= sync2_toggle;
    end
end

assign valid_pulse_mb = (sync2_toggle != sync3_toggle);

// =========================================================================
// Output register in mb_clk domain
// =========================================================================
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_par_data  <= {DATA_WIDTH{1'b0}};
        o_data_valid <= 1'b0;
    end else begin
        o_data_valid <= 1'b0;    // default: pulse for 1 cycle only
        if (valid_pulse_mb) begin
            o_par_data   <= save_data;
            o_data_valid <= 1'b1;
        end
    end
end

endmodule
