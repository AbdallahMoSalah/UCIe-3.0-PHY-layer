`timescale 1ns/1ps

import UCIe_pkg::*;

module MBINIT_PARAM_tb;

////////////////////////////////////////////////////////
// CLOCK / RESET
////////////////////////////////////////////////////////
logic clk;
logic rst_n;

initial clk = 0;
always #5 clk = ~clk; // 100MHz

initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
end

////////////////////////////////////////////////////////
// INTERFACE
////////////////////////////////////////////////////////
ucie_mb_cap_if cap_if();

////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////
logic mb_param_enable;
logic mb_param_done;
logic mb_param_error;

logic mb_param_rx_valid;
msg_no_e mb_param_rx_msg_id;
logic [15:0] mb_param_rx_MsgInfo;
logic [63:0] mb_param_rx_data_Field;

logic mb_param_tx_valid;
msg_no_e mb_param_tx_msg_id;
logic [15:0] mb_param_tx_MsgInfo;
logic [63:0] mb_param_tx_data_Field;

logic timeout_error;

// PHY (مش مهم قوي هنا)
logic mb_tx_valid_status, mb_tx_track_status, mb_tx_clk_status, mb_tx_data_status;
logic mb_rx_valid_status, mb_rx_track_status, mb_rx_clk_status, mb_rx_data_status;

MBINIT_PARAM dut (
    .clk(clk),
    .rst_n(rst_n),
    .mb_param_enable(mb_param_enable),

    .cap_if(cap_if),

    .mb_param_done(mb_param_done),
    .mb_param_error(mb_param_error),

    .mb_tx_valid_status(mb_tx_valid_status),
    .mb_tx_track_status(mb_tx_track_status),
    .mb_tx_clk_status(mb_tx_clk_status),
    .mb_tx_data_status(mb_tx_data_status),

    .mb_rx_valid_status(mb_rx_valid_status),
    .mb_rx_track_status(mb_rx_track_status),
    .mb_rx_clk_status(mb_rx_clk_status),
    .mb_rx_data_status(mb_rx_data_status),

    .mb_param_rx_valid(mb_param_rx_valid),
    .mb_param_rx_msg_id(mb_param_rx_msg_id),
    .mb_param_rx_MsgInfo(mb_param_rx_MsgInfo),
    .mb_param_rx_data_Field(mb_param_rx_data_Field),

    .mb_param_tx_valid(mb_param_tx_valid),
    .mb_param_tx_msg_id(mb_param_tx_msg_id),
    .mb_param_tx_MsgInfo(mb_param_tx_MsgInfo),
    .mb_param_tx_data_Field(mb_param_tx_data_Field),

    .timeout_error(timeout_error)
);

////////////////////////////////////////////////////////
// LOCAL CONFIG (simulate register file)
////////////////////////////////////////////////////////
initial begin
    cap_if.local_is_x8      = 0; // X16
    cap_if.local_max_speed  = 4'd3; // 16GT
    cap_if.local_sbfe       = 1;
    cap_if.local_tarr       = 1;

    cap_if.local_l2spd = 1;
    cap_if.local_pspt  = 0;
    cap_if.local_so    = 0;
    cap_if.local_pmo   = 1;
    cap_if.local_mtp   = 1;
end

////////////////////////////////////////////////////////
// TASKS
////////////////////////////////////////////////////////

// send S1 request from partner
task send_partner_s1(input logic is_x8, input logic [3:0] speed, input logic sbfe);
    begin
        @(posedge clk);
        mb_param_rx_valid <= 1;
        mb_param_rx_msg_id <= MBINIT_PARAM_configuration_req;
        mb_param_rx_data_Field <= 64'b0;
        mb_param_rx_data_Field[14] <= sbfe;
        mb_param_rx_data_Field[13] <= is_x8;
        mb_param_rx_data_Field[3:0] <= speed;

        @(posedge clk);
        mb_param_rx_valid <= 0;
    end
endtask

// send S1 response from partner
task send_partner_s1_rsp(input logic is_x8, input logic [3:0] speed, input logic sbfe);
    begin
        @(posedge clk);
        mb_param_rx_valid <= 1;
        mb_param_rx_msg_id <= MBINIT_PARAM_configuration_resp;
        mb_param_rx_data_Field <= 64'b0;
        mb_param_rx_data_Field[14] <= sbfe;
        mb_param_rx_data_Field[13] <= is_x8;
        mb_param_rx_data_Field[3:0] <= speed;

        @(posedge clk);
        mb_param_rx_valid <= 0;
    end
endtask

// send S2 request
task send_partner_s2(input logic l2spd, pmo);
    begin
        @(posedge clk);
        mb_param_rx_valid <= 1;
        mb_param_rx_msg_id <= MBINIT_PARAM_SBFE_req;
        mb_param_rx_data_Field <= 64'b0;
        mb_param_rx_data_Field[4] <= l2spd;
        mb_param_rx_data_Field[1] <= pmo;

        @(posedge clk);
        mb_param_rx_valid <= 0;
    end
endtask

// send S2 response
task send_partner_s2_rsp(input logic l2spd, pmo);
    begin
        @(posedge clk);
        mb_param_rx_valid <= 1;
        mb_param_rx_msg_id <= MBINIT_PARAM_SBFE_resp;
        mb_param_rx_data_Field <= 64'b0;
        mb_param_rx_data_Field[4] <= l2spd;
        mb_param_rx_data_Field[1] <= pmo;

        @(posedge clk);
        mb_param_rx_valid <= 0;
    end
endtask

////////////////////////////////////////////////////////
// TEST SEQUENCE
////////////////////////////////////////////////////////
initial begin
    mb_param_enable = 0;
    mb_param_rx_valid = 0;
    mb_param_rx_msg_id = msg_no_e'(0);
    mb_param_rx_MsgInfo = 0;
    mb_param_rx_data_Field = 0;

    wait(rst_n);

    // start
    #20;
    mb_param_enable = 1;

    //////////////////////////////////////////////////////
    // TEST 1: X16 local vs X8 partner
    //////////////////////////////////////////////////////
    #30;
    send_partner_s1(1, 4'd1, 1); // partner X8, 8GT, sbfe=1
    #20;
    send_partner_s1_rsp(1, 4'd1, 1);
    #30;

    // CHECK
    if(cap_if.use_x8_mode !== 1)
        $error("❌ WIDTH negotiation failed");
    else if(cap_if.negotiated_speed !== 4'd1)
        $error("❌ SPEED negotiation failed");
    else
        $display("✅ S1 negotiation PASS");

    //////////////////////////////////////////////////////
    // TEST 2: SBFE negotiation
    //////////////////////////////////////////////////////
    #20;
    send_partner_s2(1, 0); // partner supports L2SPD only
    #20;
    send_partner_s2_rsp(1, 0);

    #30;

    if(cap_if.negotiated_l2spd !== 1)
        $error("❌ L2SPD failed");
    else if(cap_if.negotiated_pmo !== 0)
        $error("❌ PMO failed");
    else
        $display("✅ S2 negotiation PASS");

    //////////////////////////////////////////////////////
    // FINISH
    //////////////////////////////////////////////////////
    #100;

    if(mb_param_done)
        $display("✅ MBINIT DONE");
    else
        $error("❌ MBINIT not completed");

    $finish;
end

endmodule