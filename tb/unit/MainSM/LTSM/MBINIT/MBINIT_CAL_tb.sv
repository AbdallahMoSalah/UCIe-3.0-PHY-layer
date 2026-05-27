`timescale 1ns/1ps

import UCIe_pkg::*;

module tb_MBINIT_CAL;

///////////////////////////////////////////////////////
//////////////// CLOCK / RESET ////////////////////////
///////////////////////////////////////////////////////

logic clk;
logic rst_n;

initial clk = 0;
always #500 clk = ~clk;

initial begin
    rst_n = 0;
    #2000;
    rst_n = 1;
end

///////////////////////////////////////////////////////
//////////////// ENABLE ///////////////////////////////
///////////////////////////////////////////////////////

logic enable_A;
logic enable_B;

///////////////////////////////////////////////////////
//////////////// DEVICE A SIGNALS /////////////////////
///////////////////////////////////////////////////////

logic A_tx_valid;
msg_no_e A_tx_msg_id;
logic [15:0] A_tx_msginfo;
logic [63:0] A_tx_data;

logic A_rx_valid;
msg_no_e A_rx_msg_id;
logic [15:0] A_rx_msginfo;
logic [63:0] A_rx_data;

logic A_done;
logic A_error;

///////////////////////////////////////////////////////
//////////////// DEVICE B SIGNALS /////////////////////
///////////////////////////////////////////////////////

logic B_tx_valid;
msg_no_e B_tx_msg_id;
logic [15:0] B_tx_msginfo;
logic [63:0] B_tx_data;

logic B_rx_valid;
msg_no_e B_rx_msg_id;
logic [15:0] B_rx_msginfo;
logic [63:0] B_rx_data;

logic B_done;
logic B_error;

///////////////////////////////////////////////////////
//////////////// LINK CONNECTION //////////////////////
///////////////////////////////////////////////////////

assign B_rx_valid   = A_tx_valid;
assign B_rx_msg_id  = A_tx_msg_id;
assign B_rx_msginfo = A_tx_msginfo;
assign B_rx_data    = A_tx_data;

assign A_rx_valid   = B_tx_valid;
assign A_rx_msg_id  = B_tx_msg_id;
assign A_rx_msginfo = B_tx_msginfo;
assign A_rx_data    = B_tx_data;

///////////////////////////////////////////////////////
//////////////// DEVICE A /////////////////////////////
///////////////////////////////////////////////////////

MBINIT_CAL DUT_A (
    .clk(clk),
    .rst_n(rst_n),

    .mb_cal_enable(enable_A),

    .mb_cal_done(A_done),
    .mb_cal_error(A_error),

    .mb_cal_rx_valid(A_rx_valid),
    .mb_cal_rx_msg_id(A_rx_msg_id),
    .mb_cal_rx_MsgInfo(A_rx_msginfo),
    .mb_cal_rx_data_Field(A_rx_data),

    .mb_cal_tx_valid(A_tx_valid),
    .mb_cal_tx_msg_id(A_tx_msg_id),
    .mb_cal_tx_MsgInfo(A_tx_msginfo),
    .mb_cal_tx_data_Field(A_tx_data),

    .ltsm_rdy(1'b1),
    .timeout_cal_enable(),
    .timeout_cal_expired(1'b0)
);

///////////////////////////////////////////////////////
//////////////// DEVICE B /////////////////////////////
///////////////////////////////////////////////////////

MBINIT_CAL DUT_B (
    .clk(clk),
    .rst_n(rst_n),

    .mb_cal_enable(enable_B),

    .mb_cal_done(B_done),
    .mb_cal_error(B_error),

    .mb_cal_rx_valid(B_rx_valid),
    .mb_cal_rx_msg_id(B_rx_msg_id),
    .mb_cal_rx_MsgInfo(B_rx_msginfo),
    .mb_cal_rx_data_Field(B_rx_data),

    .mb_cal_tx_valid(B_tx_valid),
    .mb_cal_tx_msg_id(B_tx_msg_id),
    .mb_cal_tx_MsgInfo(B_tx_msginfo),
    .mb_cal_tx_data_Field(B_tx_data),

    .ltsm_rdy(1'b1),
    .timeout_cal_enable(),
    .timeout_cal_expired(1'b0)
);

///////////////////////////////////////////////////////
//////////////// TEST SEQUENCE ////////////////////////
///////////////////////////////////////////////////////

initial begin

    enable_A = 0;
    enable_B = 0;

    @(posedge rst_n);

    #4000;

    enable_A = 1;
    enable_B = 1;

    wait(A_done && B_done);

    $display("CAL handshake completed successfully");

    #2000;

    $finish;

end

endmodule