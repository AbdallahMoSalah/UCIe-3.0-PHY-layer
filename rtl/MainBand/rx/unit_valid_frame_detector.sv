`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_frame_detector_s3
// Purpose : Solution 3: Gated valid-frame pattern detector.
// =============================================================================
module unit_valid_frame_detector_s3 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  logic [DATA_WIDTH-1:0]  i_shift_reg,
    input  logic                   i_count_16, 

    output logic                   o_valid_frame_pulse,
    output logic                   o_valid_pulse
);

// Latch the deserialized word on i_count_16 DIRECTLY (aligned), NOT through a
// PULSE_GEN-delayed copy. The deserializer shift register is free-running
// (2 bits per pll_clk), so a delayed capture rotates the aligned 0x0F0F0F0F into
// a wrong value (e.g. 0xC3C3C3C3 if 1 DDR cycle late). i_count_16 is high for
// exactly one pll_clk period, so a level-gated capture latches the aligned word
// exactly once per frame, matching the combinational o_valid_frame_pulse below.

assign o_valid_pulse = i_count_16 ;
// This pulse indicates that the current cycle's deserialized word matches 
// the expected Valid-frame pattern (0x0F0F0F0F).
assign o_valid_frame_pulse = i_count_16 & (i_shift_reg == VALID_PATTERN);

endmodule
