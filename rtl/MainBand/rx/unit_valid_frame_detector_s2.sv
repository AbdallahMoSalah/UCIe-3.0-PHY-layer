`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_frame_detector_s2
// Purpose : Solution 2: 32-bit combinational valid-frame pattern detector.
// =============================================================================
module unit_valid_frame_detector_s2 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,
    output wire                   o_valid_frame_pulse
);

assign o_valid_frame_pulse = (i_shift_reg == VALID_PATTERN);

endmodule
