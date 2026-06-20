`timescale 1ns/1ps
// =============================================================================
// Module  : unit_data_deserializer_s3
// Purpose : Solution 3: 32-bit free-running DDR shift register + capture.
// =============================================================================
module unit_data_deserializer_s3 #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   mb_clk,
    input  logic                   pll_clk,
    input  logic                   i_rst_n,
    input  logic                   i_en,
    input  logic                   ser_data_in,
    input  logic                   i_valid_frame_pulse,

    output logic  [DATA_WIDTH-1:0]  o_par_data,
    output logic                    o_data_valid
);

logic [DATA_WIDTH-1:0] shift_reg;
logic                  r_data_pos;

// FIFO signals
logic [DATA_WIDTH-1:0] fifo_rd_data;
logic                  rvalid;
logic                  wfull;
logic                  wready;
logic                  rempty;

always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else if (i_en) begin
        r_data_pos <= ser_data_in;
    end
end

always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg   <= {DATA_WIDTH{1'b0}};
    end else if (i_en) begin
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
    end
end

// Asynchronous FIFO instantiation
fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (4),
    .ASYNC      (1)
) u_fifo (
    .W_CLK   (~pll_clk),
    .WRST_N  (i_rst_n),
    .WINC    (i_valid_frame_pulse && i_en),
    .WR_DATA (shift_reg),
    .WFULL   (wfull),
    .WREADY  (wready),
    .R_CLK   (mb_clk),
    .RRST_N  (i_rst_n),
    .RINC    (rvalid),
    .RD_DATA (fifo_rd_data),
    .REMPTY  (rempty),
    .RVALID  (rvalid)
);

// Read controller in mb_clk domain
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_par_data   <= {DATA_WIDTH{1'b0}};
        o_data_valid <= 1'b0;
    end else begin
        o_data_valid <= 1'b0;
        if (i_en && rvalid) begin
            o_par_data   <= fifo_rd_data;
            o_data_valid <= 1'b1;
        end
    end
end

endmodule
