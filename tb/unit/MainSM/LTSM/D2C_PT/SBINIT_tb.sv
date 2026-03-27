`timescale 1ns/1ps
import UCIe_pkg::*;
module SBINIT_tb;
//Parameters
parameter int CLK_FRQ_HZ = 1000000; //1 MHz clock frequency for simulation purposes.

//Signals
logic clk, rst_n;
logic sb_enable ;

logic sb_rx_valid ;
msg_no_e sb_rx_msg_id ;

logic sb_tx_valid ;
msg_no_e sb_tx_msg_id ;

logic sb_done, sb_error ;

logic sb_det_pattern_req;
logic sb_det_pattern_rcvd;

logic sb_4_iterations_done;

logic timeout_error;

// Instantiate the SBINIT module
SBINIT #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) 
sbinit_inst (
    .clk(clk),
    .rst_n(rst_n),
    .sb_enable(sb_enable),
    .sb_done(sb_done),
    .sb_error(sb_error),
    .sb_rx_valid(sb_rx_valid),
    .sb_rx_msg_id(sb_rx_msg_id),
    .sb_tx_valid(sb_tx_valid),
    .sb_tx_msg_id(sb_tx_msg_id),
    .sb_det_pattern_req(sb_det_pattern_req),
    .sb_det_pattern_rcvd(sb_det_pattern_rcvd),
    .timeout_error(timeout_error)
);

// Clock generation
initial clk = 0;
always #500 clk = ~clk; // 1 MHz clock (period = 1000 ns)
task apply_reset();
begin
    rst_n = 0;
    sb_enable = 0;
    sb_rx_valid = 0;
    sb_rx_msg_id = SBINIT_Out_of_Reset;
    sb_det_pattern_rcvd = 0;
    sb_4_iterations_done = 0;

    repeat(5) @(posedge clk);
    rst_n = 1;
end
endtask

// ===============================
// Partner Message Sender
// ===============================
task send_partner_msg(input msg_no_e msg);
begin
    @(posedge clk);
    sb_rx_valid  <= 1'b1;
    sb_rx_msg_id <= msg;

    @(posedge clk);
    sb_rx_valid  <= 1'b0;
    //sb_rx_msg_id <= 8'h00;
end
endtask

// ===============================
// Real Sideband Flow Task
// ===============================
task run_real_sideband_flow();
begin
    $display("=====================================");
    $display(" START REAL SIDEBAND FLOW TEST ");
    $display("=====================================");

    sb_enable <= 1;

    // -------------------------------
    // S1: DET_PATTERN
    // -------------------------------
    wait (sb_det_pattern_req == 1);
    repeat(5) @(posedge clk);
    sb_det_pattern_rcvd <= 1;
    @(posedge clk);
    sb_det_pattern_rcvd <= 0;

    repeat(5) @(posedge clk);
    sb_det_pattern_rcvd <= 1;
    @(posedge clk);
    sb_det_pattern_rcvd <= 0;

    // -------------------------------
    // S2: LINK_SYNCH
    // wait some cycles for S2 pattern send
    //------------------------------------------------
    repeat(20) @(posedge clk);

    //------------------------------------------------
    // S3 : receive Out_of_Reset from partner
    //------------------------------------------------
    repeat(5) @(posedge clk);

    wait (sb_tx_valid && sb_tx_msg_id == msg_no_e'(8'h00));

    // Partner يرد Out_Of_Reset
    send_partner_msg(msg_no_e'(8'h00));

    // -------------------------------
    // S4: DONE Handshake
    // -------------------------------

    // استنى Done_req
    wait (sb_tx_valid && sb_tx_msg_id == msg_no_e'(8'h01));

    // Partner يبعت Done_req
    send_partner_msg(msg_no_e'(8'h01));
	
	// ??? ????: ??? ??? ????
	//repeat(10) @(posedge clk);

    // استنى DUT يبعث Done_rsp
    wait (sb_tx_valid && sb_tx_msg_id == msg_no_e'(8'h02));

    // Partner يبعث Done_rsp
    send_partner_msg(msg_no_e'(8'h02));

    // -------------------------------
    // Final Check
    // -------------------------------
    wait (sb_done == 1);

    $display(" SIDEBAND FLOW COMPLETED SUCCESSFULLY ");
    $display("=====================================");

    //sb_enable <= 0;

end
endtask

// ===============================
// Simulation Start
// ===============================
initial begin
    apply_reset();
    run_real_sideband_flow();

    #10000;
    $stop;
end

endmodule
