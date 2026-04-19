`timescale 1ns/1ps
import UCIe_pkg::*;

module MBINIT_REPAIRVAL_tb;

////////////////////////////////////////////////////////
// SIGNALS
////////////////////////////////////////////////////////
logic clk;
logic rst_n;
logic mb_repairval_enable;

logic mb_repairval_done;
logic mb_repairval_error;

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
logic [1:0] mb_tx_val_pattern_sel;
logic [1:0] mb_rx_compare_setup;

logic mb_tx_pattern_en;
logic mb_rx_compare_en;

logic RVLD_L_pass;
logic mb_rx_compare_done;

////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////
MBINIT_REPAIRVAL dut (
    .clk(clk),
    .rst_n(rst_n),

    .mb_repairval_enable(mb_repairval_enable),

    .mb_repairval_done(mb_repairval_done),
    .mb_repairval_error(mb_repairval_error),

    .mb_repairval_rx_valid(mb_rx_valid),
    .mb_repairval_rx_msg_id(mb_rx_msg_id),
    .mb_repairval_rx_MsgInfo(mb_rx_MsgInfo),
    .mb_repairval_rx_data_Field(mb_rx_data_Field),

    .mb_repairval_tx_valid(mb_tx_valid),
    .mb_repairval_tx_msg_id(mb_tx_msg_id),
    .mb_repairval_tx_MsgInfo(mb_tx_MsgInfo),
    .mb_repairval_tx_data_Field(mb_tx_data_Field),

    .timeout_error(timeout_error),

    .mb_tx_pattern_setup(mb_tx_pattern_setup),
    .mb_tx_val_pattern_sel(mb_tx_val_pattern_sel),
    .mb_rx_compare_setup(mb_rx_compare_setup),

    .mb_tx_pattern_en(mb_tx_pattern_en),
    .mb_rx_compare_en(mb_rx_compare_en),

    .RVLD_L_pass(RVLD_L_pass),
    .mb_rx_compare_done(mb_rx_compare_done)
);

////////////////////////////////////////////////////////
// CLOCK
////////////////////////////////////////////////////////
always #500 clk = ~clk;

////////////////////////////////////////////////////////
// SEND MSG
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
// PARTNER (نفس فكرة repairclk)
////////////////////////////////////////////////////////
always @(posedge clk) begin
    if(mb_tx_valid) begin

        case(mb_tx_msg_id)

        // S1
        MBINIT_REPAIRVAL_init_req: 
            send_msg(MBINIT_REPAIRVAL_init_req, 16'h0);
        
        MBINIT_REPAIRVAL_init_resp: 
            send_msg(MBINIT_REPAIRVAL_init_resp, 16'h0);
        

        // S3
        MBINIT_REPAIRVAL_result_req: 
            send_msg(MBINIT_REPAIRVAL_result_req, 16'h0);       
        MBINIT_REPAIRVAL_result_resp: 
            send_msg(MBINIT_REPAIRVAL_result_resp, 16'h0001); // pass
        

        // S4
        MBINIT_REPAIRVAL_done_req: 
            send_msg(MBINIT_REPAIRVAL_done_req, 16'h0);
        MBINIT_REPAIRVAL_done_resp: 
            send_msg(MBINIT_REPAIRVAL_done_resp, 16'h0);
        
        endcase
    end
end

////////////////////////////////////////////////////////
// PATTERN SIMULATION
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
    mb_repairval_enable = 0;

    mb_rx_valid = 0;
    mb_rx_msg_id = msg_no_e'(0);
    mb_rx_MsgInfo = 0;
    mb_rx_data_Field = 0;

    RVLD_L_pass = 1; // success

    mb_rx_compare_done = 0;

    ////////////////////////////////////////////////////
    // RESET
    ////////////////////////////////////////////////////
    #2000;
    rst_n = 1;

    #2000;
    mb_repairval_enable = 1;

    ////////////////////////////////////////////////////
    // WAIT DONE
    ////////////////////////////////////////////////////
    wait(mb_repairval_done == 1);

    $display("✅ REPAIRVAL PASSED");

    #2000;
    $stop;

end

endmodule