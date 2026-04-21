`timescale 1ns/1ps
import UCIe_pkg::*;

module MBINIT_REPAIRCLK_tb;

////////////////////////////////////////////////////////
// SIGNALS
////////////////////////////////////////////////////////
logic clk;
logic rst_n;
logic mb_repairclk_enable;

logic mb_repairclk_done;
logic mb_repairclk_error;

logic mb_rx_valid;
msg_no_e mb_rx_msg_id;
logic [15:0] mb_rx_MsgInfo;
logic [63:0] mb_rx_data_Field;

logic mb_tx_valid;
msg_no_e mb_tx_msg_id;
logic [15:0] mb_tx_MsgInfo;
logic [63:0] mb_tx_data_Field;

logic timeout_error;

logic [2:0] mb_tx_pattern_setup;
logic [1:0] mb_tx_clk_pattern_sel;
logic [1:0] mb_rx_compare_setup;

logic mb_tx_pattern_en;
logic mb_rx_compare_en;

logic rtrk_pass, rckn_pass, rckp_pass;
logic mb_rx_compare_done;

////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////
MBINIT_REPAIRCLK dut (
    .clk(clk),
    .rst_n(rst_n),

    .mb_repairclk_enable(mb_repairclk_enable),

    .mb_repairclk_done(mb_repairclk_done),
    .mb_repairclk_error(mb_repairclk_error),

    .mb_repairclk_rx_valid(mb_rx_valid),
    .mb_repairclk_rx_msg_id(mb_rx_msg_id),
    .mb_repairclk_rx_MsgInfo(mb_rx_MsgInfo),
    .mb_repairclk_rx_data_Field(mb_rx_data_Field),

    .mb_repairclk_tx_valid(mb_tx_valid),
    .mb_repairclk_tx_msg_id(mb_tx_msg_id),
    .mb_repairclk_tx_MsgInfo(mb_tx_MsgInfo),
    .mb_repairclk_tx_data_Field(mb_tx_data_Field),

    .timeout_error(timeout_error),

    .mb_tx_pattern_setup(mb_tx_pattern_setup),
    .mb_tx_clk_pattern_sel(mb_tx_clk_pattern_sel),
    .mb_rx_compare_setup(mb_rx_compare_setup),

    .mb_tx_pattern_en(mb_tx_pattern_en),
    .mb_rx_compare_en(mb_rx_compare_en),

    .rtrk_pass(rtrk_pass),
    .rckn_pass(rckn_pass),
    .rckp_pass(rckp_pass),
    .mb_rx_compare_done(mb_rx_compare_done)
);

////////////////////////////////////////////////////////
// CLOCK
////////////////////////////////////////////////////////
always #500 clk = ~clk;

////////////////////////////////////////////////////////
// TASK: SEND MSG
////////////////////////////////////////////////////////
task send_msg(input msg_no_e id, input [15:0] info);
begin
    @(posedge clk);
    mb_rx_msg_id  = id;
    mb_rx_MsgInfo = info;
    mb_rx_valid   = 1;

    @(posedge clk);
    mb_rx_valid   = 0;
end
endtask

////////////////////////////////////////////////////////
// PARTNER BEHAVIOR (SMART)
////////////////////////////////////////////////////////
always @(posedge clk) begin
    if(mb_tx_valid) begin

        case(mb_tx_msg_id)

        //////////////////////////////////////////////////
        // S1
        //////////////////////////////////////////////////
        MBINIT_REPAIRCLK_init_req: begin
            send_msg(MBINIT_REPAIRCLK_init_req, 16'h0);
            send_msg(MBINIT_REPAIRCLK_init_resp, 16'h0);
        end

        //////////////////////////////////////////////////
        // S3
        //////////////////////////////////////////////////
        MBINIT_REPAIRCLK_result_req: begin
            send_msg(MBINIT_REPAIRCLK_result_req, 16'h0);
            send_msg(MBINIT_REPAIRCLK_result_resp, 16'h0007);
        end

        //////////////////////////////////////////////////
        // S4
        //////////////////////////////////////////////////
        MBINIT_REPAIRCLK_done_req: begin
            send_msg(MBINIT_REPAIRCLK_done_req, 16'h0);
            send_msg(MBINIT_REPAIRCLK_done_resp, 16'h0);
        end

        endcase
    end
end

////////////////////////////////////////////////////////
//PATTERN Done
////////////////////////////////////////////////////////
always @(posedge clk) begin
    if(mb_tx_pattern_en) begin
        repeat(8) @(posedge clk);
        mb_rx_compare_done <= 1;
        @(posedge clk);
        mb_rx_compare_done <= 0;
    end
    else 
        mb_rx_compare_done <= 0;
        
end

////////////////////////////////////////////////////////
// INITIAL
////////////////////////////////////////////////////////
initial begin

    clk = 0;
    rst_n = 0;
    mb_repairclk_enable = 0;

    mb_rx_valid = 0;
    mb_rx_msg_id = msg_no_e'(0);
    mb_rx_MsgInfo = 0;
    mb_rx_data_Field = 0;

    rtrk_pass = 1;
    rckn_pass = 1;
    rckp_pass = 1;

    ////////////////////////////////////////////////////
    // RESET
    ////////////////////////////////////////////////////
    #2000;
    rst_n = 1;

    #2000;
    mb_repairclk_enable = 1;

    ////////////////////////////////////////////////////
    // WAIT DONE
    ////////////////////////////////////////////////////
    wait(mb_repairclk_done == 1);

    $display("✅ TEST PASSED - DONE = 1");

    #10000;
    $stop;

end

endmodule