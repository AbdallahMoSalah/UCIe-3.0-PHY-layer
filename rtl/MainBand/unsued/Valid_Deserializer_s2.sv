`timescale 1ns/1ps
// =============================================================================
// Module  : Valid_Deserializer_s2
// Project : UCIe 3.0 Main-Band Physical Layer (RX side)
// Purpose : Solution 2: 32-bit DDR deserializer with history-clear functionality.
// =============================================================================
module Valid_Deserializer_s2 #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_data_in,
    input  wire                   i_clear,       // clears old bits when match is found

    output wire [DATA_WIDTH-1:0]  o_shift_reg
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

// Shift right on negedge pll_clk; clear older 30 bits if i_clear is active
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        if (i_clear) begin
            shift_reg <= {ser_data_in, r_data_pos, 30'b0};
        end else begin
            shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
        end
    end
end

assign o_shift_reg = shift_reg;

endmodule
