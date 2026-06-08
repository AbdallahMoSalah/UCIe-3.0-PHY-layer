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
    input  wire [11:0]            i_max_error_threshold_per_lane,

    output wire                   o_valid_frame_pulse,
    output wire                   valid_pass
);

 PULSE_GEN  pulse_gen
 (
  .clk(i_clk),
  .rst(i_rst_n),
  .lvl_sig(i_count_16),
  .pulse_sig(synch_count_16)
 );


reg  [DATA_WIDTH-1:0] valid_frame_reg;
wire [DATA_WIDTH-1:0] mismatch;
always @(posedge i_clk or negedge i_rst_n)begin
    if (!i_rst_n) begin
        valid_frame_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        if (synch_count_16)
            valid_frame_reg <= i_shift_reg;
    end
end

assign mismatch = valid_frame_reg ^ VALID_PATTERN;
assign o_valid_frame_pulse = i_count_16 & (i_shift_reg == VALID_PATTERN);
assign result_count = popcount_w(mismatch);


function automatic [5:0] popcount_w(input [DATA_WIDTH-1:0] v);
    integer i;
    begin
        popcount_w = 5'd0;
        for (i = 0; i < DATA_WIDTH; i = i + 1)
                popcount_w = popcount_w + v[i];
        end
endfunction
endmodule
