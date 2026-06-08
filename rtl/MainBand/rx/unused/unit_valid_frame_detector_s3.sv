`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_frame_detector_s3
// Purpose : Solution 3: Gated valid-frame pattern detector.
// =============================================================================
module unit_valid_frame_detector_s3 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  wire                   i_rst_n,
    input  wire                   i_clk,
    input  wire [DATA_WIDTH-1:0]  i_shift_reg,
    input  wire                   i_count_16, //

    output wire                   o_valid_frame_pulse
);

reg  [DATA_WIDTH-1:0] valid_frame_reg;

always @(posedge i_clk or negedge i_rst_n)begin
    if (!i_rst_n) begin
        valid_frame_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        if (i_count_16)
            valid_frame_reg <= i_shift_reg;
    end
end


assign o_valid_frame_pulse = i_count_16 & (!prev_count_16) & (i_shift_reg == VALID_PATTERN);

endmodule
