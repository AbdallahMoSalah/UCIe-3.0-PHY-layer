`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;

module sideband_analog_hard_macro #(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)(
    input  logic rst_sb_n,
    output logic clk_sb,

    input logic pattern_mode,
    input logic pmo_en,

    output logic [63:0]  des_data_rcvd,
    output logic         des_vld_rcvd,

    input  logic [63:0]   ser_data_send,
    input  logic          ser_vld_send,
    output logic          ser_rdy,
    
    input  logic         RXDATASB,
    output logic         TXDATASB,

    input  logic RXCKSB,
    output logic TXCKSB
);

    logic sb_pll_clock;
    //===========================================================================================
    //sideBand
    //===========================================================================================
    sb_pll u_sb_pll (
        .en           (1'b1),
        .clk          (sb_pll_clock),
        .local_period ()
    );

    ClkDiv #(
        .RangeWidth (8)
    ) u_clk_div_sb (
        .i_ref_clk   (sb_pll_clock),
        .i_rst_n     (rst_sb_n),
        .i_clk_en    (1'b1),
        .i_div_ratio (8'd8),
        .o_div_clk   (clk_sb)
    );

        // =========================================================================
    // SerDes Modules
    // =========================================================================

    logic ser_pmo_en;
    assign ser_pmo_en = pattern_mode ? 1'b0 : pmo_en;
    sb_serializer #(
        .DATA_WIDTH (DATA_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sb_serializer (
        .clk_parallel     (clk_sb),
        .clk_serial       (sb_pll_clock),
        .rst_n            (rst_sb_n),
        .pmo_en           (ser_pmo_en),
        .tx_parallel_data (ser_data_send),
        .tx_data_valid    (ser_vld_send),
        .tx_rdy           (ser_rdy),
        .TXDATASB         (TXDATASB),
        .TXCKSB           (TXCKSB)
    );

    logic RXCKSB_forward = 0;
    always @(RXCKSB) RXCKSB_forward <= #(SERDES_CLK/2) RXCKSB;

    sb_deserializer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_sb_deserializer (
        .RXCKSB               (RXCKSB_forward),
        .clk_parallel         (clk_sb),
        .rst_n                (rst_sb_n),
        .RXDATASB              (RXDATASB),
        .rx_parallel_data_out (des_data_rcvd),
        .rx_data_vld          (des_vld_rcvd)
    );
    //===========================================================================================
    //MainBand
    //===========================================================================================
endmodule
