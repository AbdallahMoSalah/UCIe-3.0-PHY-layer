`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_deserializer_s1
// Project : UCIe 3.0 Main-Band Physical Layer (RX side)
// Purpose : Solution 1: 8-bit Free-running DDR deserializer for the Valid lane.
// =============================================================================
module unit_valid_deserializer_s1 #(
    parameter DATA_WIDTH = 8
)(
    input  wire                   pll_clk,       // high-speed clock
    input  wire                   i_rst_n,       // active-low reset
    input  wire                   ser_data_in,   // serial valid input (RVLD_P)

    output wire [DATA_WIDTH-1:0]  o_shift_reg    // raw 8-bit shift register
);

reg [DATA_WIDTH-1:0] shift_reg;
reg                  r_data_pos;

// Capture even bit on posedge pll_clk
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else begin
        r_data_pos <= ser_data_in;
    end
end

// Shift right 2 bits on negedge pll_clk
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
    end
end

assign o_shift_reg = shift_reg;

endmodule
