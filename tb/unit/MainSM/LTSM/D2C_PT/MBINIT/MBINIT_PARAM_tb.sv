import UCIe_pkg::*;
`timescale 1ns/1ps
module tb_MBINIT_PARAM;
parameter int CLK_FRQ_HZ = 1000000;
////////////////////////////////////////////////////
//////////////////// CLOCK /////////////////////////
////////////////////////////////////////////////////

logic clk;
initial clk = 0;
always #500 clk = ~clk;   // 800 MHz clock

////////////////////////////////////////////////////
//////////////////// RESET /////////////////////////
////////////////////////////////////////////////////

logic rst_n;

////////////////////////////////////////////////////
//////////////// DUT SIGNALS ///////////////////////
////////////////////////////////////////////////////

logic mb_enable;

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

////////////////////////////////////////////////////
//////////////////// DUT ///////////////////////////
////////////////////////////////////////////////////

MBINIT_PARAM #(.CLK_FRQ_HZ(CLK_FRQ_HZ))
DUT(
    .clk(clk),
    .rst_n(rst_n),

    .mb_param_enable(mb_enable),

    .mb_param_done(mb_param_done),
    .mb_param_error(mb_param_error),

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

////////////////////////////////////////////////////
//////////// PARTNER CAPABILITIES //////////////////
////////////////////////////////////////////////////
/*
64'h0000_0000_0000_EA72
| Field         | value |
| ------------- | ----- |
| Max Speed     | 2     |
| Voltage swing | 7     |
| Clock mode    | 1     |
| Clock phase   | 0     |
| Module ID     | 2     |
| x32           | 1     |
| SBFE          | 1     |
| TARR          | 1     |
*/
logic [63:0] partner_param_cap;
initial begin
    // Partner capabilities example
    partner_param_cap = 64'h0000_0000_0000_EA72;
end

/*
64'h0000_0000_0000_001A
L2SPD = 1
PSPT = 1
SO = 0
PMO = 1
MTP = 0 
*/
logic [63:0] partner_sbfe_cap;
initial begin
    partner_sbfe_cap = 64'h0000_0000_0000_001A;
end

////////////////////////////////////////////////////
//////////////////// TASK //////////////////////////
////////////////////////////////////////////////////

task send_msg(
    input msg_no_e msg,
    input [15:0] info,
    input [63:0] data
);
begin
    @(posedge clk);
    mb_param_rx_valid      <= 1;
    mb_param_rx_msg_id     <= msg;
    mb_param_rx_MsgInfo    <= info;
    mb_param_rx_data_Field <= data;

    @(posedge clk);
    mb_param_rx_valid <= 0;
end
endtask

////////////////////////////////////////////////////
////////////////// TEST SEQUENCE ///////////////////
////////////////////////////////////////////////////

initial begin

    mb_param_rx_valid = 0;
    mb_enable = 0;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    //////////////////////////////////////////////////
    // Start MBINIT.PARAM
    //////////////////////////////////////////////////

    @(posedge clk);
    mb_enable = 1;

    //////////////////////////////////////////////////
    // Wait DUT configuration_req
    //////////////////////////////////////////////////

    wait(mb_param_tx_valid && 
         mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);

    $display("DUT sent configuration_req");

    //////////////////////////////////////////////////
    // Partner sends configuration_req
    //////////////////////////////////////////////////

    send_msg(
        MBINIT_PARAM_configuration_req,
        16'h0000,
        partner_param_cap
    );

    //////////////////////////////////////////////////
    // Wait DUT configuration_resp
    //////////////////////////////////////////////////

    wait(mb_param_tx_valid &&
         mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);

    $display("DUT sent configuration_resp");

    //////////////////////////////////////////////////
    // Partner sends configuration_resp
    //////////////////////////////////////////////////

    send_msg(
        MBINIT_PARAM_configuration_resp,
        16'h0000,
        64'h0000_0000_0000_2A52
    );

    //////////////////////////////////////////////////
    // Wait DUT SBFE_req
    //////////////////////////////////////////////////

    wait(mb_param_tx_valid &&
         mb_param_tx_msg_id == MBINIT_PARAM_SBFE_req);

    $display("DUT sent SBFE_req");

    //////////////////////////////////////////////////
    // Partner sends SBFE_req
    //////////////////////////////////////////////////

    send_msg(
        MBINIT_PARAM_SBFE_req,
        16'h0000,
        partner_sbfe_cap
    );

    //////////////////////////////////////////////////
    // Wait DUT SBFE_resp
    //////////////////////////////////////////////////

    wait(mb_param_tx_valid &&
         mb_param_tx_msg_id == MBINIT_PARAM_SBFE_resp);

    $display("DUT sent SBFE_resp");

    //////////////////////////////////////////////////
    // Partner sends SBFE_resp
    //////////////////////////////////////////////////

    send_msg(
        MBINIT_PARAM_SBFE_resp,
        16'h0000,
        64'h0000_0000_0000_0012
    );

    //////////////////////////////////////////////////
    // Wait DONE
    //////////////////////////////////////////////////

    wait(mb_param_done);

    $display("MBINIT.PARAM DONE");

    #100;
    $stop;

end

endmodule