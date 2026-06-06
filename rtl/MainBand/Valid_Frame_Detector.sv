`timescale 1ns/1ps
// =============================================================================
// Module  : Valid_Frame_Detector
// Project : UCIe 3.0 Main-Band Physical Layer  (RX side)
// Purpose : Pure combinational detector for the valid-frame pattern in the
//           Valid-lane shift register.
//
//  Operation
//  ---------
//  - Receives the 32-bit shift register output from Valid_Deserializer.
//  - Checks whether the register contains the valid-frame pattern:
//      0x0F0F0F0F  (four repetitions of 8'h0F)
//    This matches the parallel word sent by VALID_TX
//    (assign o_TVLD_L = 32'h0F0F0F0F).
//  - Output `o_valid_frame_pulse` is a pure combinational wire — it goes
//    HIGH the instant the shift register holds the pattern and goes LOW
//    as soon as the next shift corrupts it. No clock, no registration.
//
//  Why combinational?
//  ------------------
//  The Valid_Deserializer and Data_Deserializer shift registers update on
//  the negedge of pll_clk. After negedge N the valid shift register holds
//  the pattern (via NBA update). The combinational match wire goes HIGH
//  immediately. At negedge N+1 the Data_Deserializer samples this wire
//  and captures its own shift_reg — which still holds the complete data
//  word (also set at negedge N). A registered detector would add one more
//  negedge of latency, causing the data shift register to have already
//  shifted by 2 extra bits → data loss.
// =============================================================================
module Valid_Frame_Detector #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F  // Expected valid-frame word
)(
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,          // from Valid_Deserializer
    output wire                   o_valid_frame_pulse   // HIGH when pattern matched
);

// =========================================================================
// Pure combinational match — no clock, no registration
// =========================================================================
assign o_valid_frame_pulse = (i_shift_reg == VALID_PATTERN);

endmodule
