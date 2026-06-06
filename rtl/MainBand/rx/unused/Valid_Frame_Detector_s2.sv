`timescale 1ns/1ps
// =============================================================================
// Module  : Valid_Frame_Detector_s2
// Purpose : Solution 2: 32-bit combinational valid-frame pattern detector.
// =============================================================================
module Valid_Frame_Detector_s2 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,
    output wire                   o_valid_frame_pulse
);

assign o_valid_frame_pulse = (i_shift_reg == VALID_PATTERN);

endmodule
