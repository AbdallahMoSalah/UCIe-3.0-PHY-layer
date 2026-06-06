`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_frame_detector_s1
// Purpose : Solution 1: 8-bit combinational valid-frame pattern detector.
// =============================================================================
module unit_valid_frame_detector_s1 #(
    parameter DATA_WIDTH    = 8,
    parameter VALID_PATTERN = 8'h0F  // 8-bit valid-frame pattern (11110000 LSB first is 8'h0F)
)(
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,
    output wire                   o_valid_frame_pulse
);

assign o_valid_frame_pulse = (i_shift_reg == VALID_PATTERN);

endmodule
