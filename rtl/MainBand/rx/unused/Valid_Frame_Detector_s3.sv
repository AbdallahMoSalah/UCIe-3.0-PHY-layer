`timescale 1ns/1ps
// =============================================================================
// Module  : Valid_Frame_Detector_s3
// Purpose : Solution 3: Gated valid-frame pattern detector.
// =============================================================================
module Valid_Frame_Detector_s3 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,
    input  wire                   i_state,       // 0=IDLE, 1=RUNNING
    input  wire [3:0]             i_count,       // 0..15

    output wire                   o_valid_frame_pulse
);

// Gated combinational match: only high at the exact 16th DDR shift cycle of the frame
assign o_valid_frame_pulse = (i_state == 1'b1 && i_count == 4'd15) && (i_shift_reg == VALID_PATTERN);

endmodule
