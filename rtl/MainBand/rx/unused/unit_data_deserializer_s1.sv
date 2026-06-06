`timescale 1ns/1ps
// =============================================================================
// Module  : unit_data_deserializer_s1
// Project : UCIe 3.0 Main-Band Physical Layer (RX side)
// Purpose : Solution 1: 8-bit shift register + 4-byte accumulation to 32-bit.
// =============================================================================
module unit_data_deserializer_s1 #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   mb_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_data_in,
    input  wire                   i_valid_frame_pulse,

    output reg  [DATA_WIDTH-1:0]  o_par_data,
    output reg                    o_data_valid
);

// 8-bit Shift Register & Capture
reg [7:0]  shift_reg;
reg        r_data_pos;

// Accumulation registers (pll_clk domain)
reg [31:0] accumulated_data;
reg [1:0]  byte_cnt;
reg [4:0]  idle_timer;

// FIFO signals
wire [DATA_WIDTH-1:0] fifo_rd_data;
wire                  rvalid;
wire                  wfull;
wire                  wready;
wire                  rempty;

// DDR Input Capture - Posedge
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else begin
        r_data_pos <= ser_data_in;
    end
end

// Shift and Accumulate - Negedge
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg        <= 8'd0;
        accumulated_data <= 32'd0;
        byte_cnt         <= 2'd0;
        idle_timer       <= 5'd0;
    end else begin
        // Free-running shift
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[7:2]};

        // Idle timer increments to prevent lockups due to noise/misalignment
        if (idle_timer < 5'd31) begin
            idle_timer <= idle_timer + 5'd1;
        end

        // If no pulse received for ~16 cycles of pll_clk, reset byte count
        if (idle_timer == 5'd31) begin
            byte_cnt <= 2'd0;
        end

        // Accumulate byte-by-byte
        if (i_valid_frame_pulse) begin
            idle_timer <= 5'd0;
            byte_cnt   <= byte_cnt + 2'd1;
            accumulated_data[8*byte_cnt +: 8] <= shift_reg;
        end
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
    .WINC    (i_valid_frame_pulse && (byte_cnt == 2'd3)),
    .WR_DATA ({shift_reg, accumulated_data[23:0]}),
    .WFULL   (wfull),
    .WREADY  (wready),
    .R_CLK   (mb_clk),
    .RRST_N  (i_rst_n),
    .RINC    (rvalid),
    .RD_DATA (fifo_rd_data),
    .REMPTY  (rempty),
    .RVALID  (rvalid)
);

// Output presentation in mb_clk domain
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_par_data   <= 32'd0;
        o_data_valid <= 1'b0;
    end else begin
        o_data_valid <= 1'b0;
        if (rvalid) begin
            o_par_data   <= fifo_rd_data;
            o_data_valid <= 1'b1;
        end
    end
end

endmodule
