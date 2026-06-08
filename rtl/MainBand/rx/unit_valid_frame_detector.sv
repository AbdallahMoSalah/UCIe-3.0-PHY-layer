`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_frame_detector_s3
// Purpose : Solution 3: Gated valid-frame pattern detector.
// =============================================================================
module unit_valid_frame_detector_s3 #(
    parameter DATA_WIDTH   = 32,
    parameter VALID_PATTERN = 32'h0F0F0F0F
)(
    input  logic                   i_rst_n,
    input  logic                   i_clk,
    input  logic [DATA_WIDTH-1:0]  i_shift_reg,
    input  logic                   i_count_16, 

    output logic                   o_valid_frame_pulse,
    output logic [DATA_WIDTH-1:0]  o_valid_frame_data,
    output logic                   o_valid_frame_vld
);

 PULSE_GEN  pulse_gen
 (
  .clk(i_clk),
  .rst(i_rst_n),
  .lvl_sig(i_count_16),
  .pulse_sig(synch_count_16)
 );


logic  [DATA_WIDTH-1:0] valid_frame_reg;
logic valid_frame_vld;
always @(posedge i_clk or negedge i_rst_n)begin
    if (!i_rst_n) begin
        valid_frame_reg <= {DATA_WIDTH{1'b0}};
        valid_frame_vld <= 1'b0;
    end else begin
        if (synch_count_16) begin
            valid_frame_reg <= i_shift_reg;
            valid_frame_vld <= 1'b1;
        end else begin
            valid_frame_vld <= 1'b0;
        end
    end
end

assign o_valid_frame_data = valid_frame_reg;
assign o_valid_frame_vld = valid_frame_vld;


// This pulse indicates that the current cycle's deserialized word matches 
// the expected Valid-frame pattern (0x0F0F0F0F).
assign o_valid_frame_pulse = i_count_16 & (i_shift_reg == VALID_PATTERN);

endmodule