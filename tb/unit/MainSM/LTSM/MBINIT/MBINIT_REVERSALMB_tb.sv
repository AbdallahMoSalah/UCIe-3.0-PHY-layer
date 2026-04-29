`timescale 1ns/1ps
import UCIe_pkg::*;

module MBINIT_REVERSALMB_tb;

////////////////////////////////////////////////////////
// CLOCK / RESET
////////////////////////////////////////////////////////
logic clk;
logic rst_n;

initial clk = 0;
always #500 clk = ~clk;

initial begin
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
end

////////////////////////////////////////////////////////
// INTERFACE
////////////////////////////////////////////////////////
ucie_mb_cap_if cap_if();

////////////////////////////////////////////////////////
// SIGNALS
////////////////////////////////////////////////////////
logic mb_reversal_enable;

logic mb_reversal_done;
logic mb_reversal_error;

logic mb_reversal_rx_valid;
msg_no_e mb_reversal_rx_msg_id;
logic [63:0] mb_reversal_rx_data_Field;

logic mb_reversal_tx_valid;
msg_no_e mb_reversal_tx_msg_id;

logic [15:0] mb_rx_perlane_err;
logic mb_rx_compare_done;

logic mb_lane_reversal_req;

////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////
MBINIT_REVERSALMB dut (
    .cap_if(cap_if),
    .clk(clk),
    .rst_n(rst_n),

    .mb_reversal_enable(mb_reversal_enable),

    .mb_reversal_done(mb_reversal_done),
    .mb_reversal_error(mb_reversal_error),

    .mb_reversal_rx_valid(mb_reversal_rx_valid),
    .mb_reversal_rx_msg_id(mb_reversal_rx_msg_id),
    .mb_reversal_rx_MsgInfo(),
    .mb_reversal_rx_data_Field(mb_reversal_rx_data_Field),

    .mb_reversal_tx_valid(mb_reversal_tx_valid),
    .mb_reversal_tx_msg_id(mb_reversal_tx_msg_id),
    .mb_reversal_tx_MsgInfo(),
    .mb_reversal_tx_data_Field(),

    .timeout_error(),

    .mb_tx_pattern_setup(),
    .mb_tx_data_pattern_sel(),
    .mb_rx_compare_setup(),

    .mb_tx_pattern_en(),
    .mb_rx_compare_en(),

    .mb_rx_perlane_err(mb_rx_perlane_err),
    .mb_rx_compare_done(mb_rx_compare_done),

    .mb_lane_reversal_req(mb_lane_reversal_req),
    .mb_x8_mode_req(),
    .clear_error_req(),

    .mb_tx_valid_status(),
    .mb_tx_track_status(),
    .mb_tx_clk_status(),
    .mb_tx_data_status(),

    .mb_rx_valid_status(),
    .mb_rx_track_status(),
    .mb_rx_clk_status(),
    .mb_rx_data_status()
);

////////////////////////////////////////////////////////
// CONFIG
////////////////////////////////////////////////////////
initial cap_if.use_x8_mode = 0; // x16

////////////////////////////////////////////////////////
// TASK
////////////////////////////////////////////////////////
task send_msg(input msg_no_e id, input [63:0] data = 0);
begin
    @(posedge clk);
    mb_reversal_rx_valid <= 1;
    mb_reversal_rx_msg_id <= id;
    mb_reversal_rx_data_Field <= data;

    @(posedge clk);
    mb_reversal_rx_valid <= 0;
end
endtask

////////////////////////////////////////////////////////
// TEST
////////////////////////////////////////////////////////
initial begin
    mb_reversal_enable = 0;
    mb_reversal_rx_valid = 0;
    mb_rx_perlane_err = 0;
    mb_rx_compare_done = 0;

    wait(rst_n);

    ////////////////////////////////////////
    // START
    ////////////////////////////////////////
    mb_reversal_enable = 1;

    ////////////////////////////////////////
    // S1
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S1_READINESS_HANDSHAKE_REQ);
    send_msg(MBINIT_REVERSALMB_init_req);

    wait(dut.current_state == dut.MB_S1_READINESS_HANDSHAKE_RSP);
    send_msg(MBINIT_REVERSALMB_init_resp);

    ////////////////////////////////////////
    // S2
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S2_ERROR_RESET_REQ);
    send_msg(MBINIT_REVERSALMB_clear_error_req);

    wait(dut.current_state == dut.MB_S2_ERROR_RESET_RSP);
    send_msg(MBINIT_REVERSALMB_clear_error_resp);

    ////////////////////////////////////////
    // S3 (FAIL → RETRY)
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S3_PATTERN_TRANSMISSION);

    $display("---- FIRST RUN (FAIL) ----");

    mb_rx_perlane_err = 16'h0000; // FAIL
    mb_rx_compare_done = 1;
    repeat(2) @(posedge clk);
    mb_rx_compare_done = 0;

    ////////////////////////////////////////
    // S4
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S4_RESULT_EXCHANGE_REQ);
    send_msg(MBINIT_REVERSALMB_result_req);

    wait(dut.current_state == dut.MB_S4_RESULT_EXCHANGE_RSP);
    send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000);

    ////////////////////////////////////////
    // RETRY (يرجع لـ S2)
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S2_ERROR_RESET_REQ);

    $display("---- RETRY STARTED ----");

    send_msg(MBINIT_REVERSALMB_clear_error_req);

    wait(dut.current_state == dut.MB_S2_ERROR_RESET_RSP);
    send_msg(MBINIT_REVERSALMB_clear_error_resp);

    ////////////////////////////////////////
    // S3 (PASS)
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S3_PATTERN_TRANSMISSION);

    $display("---- SECOND RUN (PASS) ----");

    mb_rx_perlane_err = 16'hFFFF; // PASS
    mb_rx_compare_done = 1;
    repeat(2) @(posedge clk);
    mb_rx_compare_done = 0;

    ////////////////////////////////////////
    // S4
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S4_RESULT_EXCHANGE_REQ);
    send_msg(MBINIT_REVERSALMB_result_req);

    wait(dut.current_state == dut.MB_S4_RESULT_EXCHANGE_RSP);
    send_msg(MBINIT_REVERSALMB_result_resp, 64'hFFFF);

    ////////////////////////////////////////
    // FINAL
    ////////////////////////////////////////
    wait(dut.current_state == dut.MB_S6_FINALIZE_HANDSHAKE_REQ);
    send_msg(MBINIT_REVERSALMB_done_req);

    wait(dut.current_state == dut.MB_S6_FINALIZE_HANDSHAKE_RSP);
    send_msg(MBINIT_REVERSALMB_done_resp);

    wait(mb_reversal_done);

    $display(" TEST PASSED: RETRY + DONE WORKING");

    $finish;
end

endmodule