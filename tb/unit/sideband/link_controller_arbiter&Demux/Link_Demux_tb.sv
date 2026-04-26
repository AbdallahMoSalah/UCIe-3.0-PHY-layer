`timescale 1ns/1ps

module Link_Demux_tb;

import sb_pkg::*;

logic [127:0] msg_word_rcvd;
logic         word_valid_r;

logic [127:0] adapter_msg_rcvd;
logic         Adapter_valid_r;
logic [127:0] trn_msg_rcvd;
logic         LINK_valid_r;

int pass_cnt = 0;
int fail_cnt = 0;

////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////

LINK_Demux u_LINK_Demux(
    .msg_word_rcvd(msg_word_rcvd),
    .word_vld_rcvd(word_valid_r),
    .adapter_msg_rcvd(adapter_msg_rcvd),
    .adapter_vld_rcvd(Adapter_valid_r),
    .trn_msg_rcvd(trn_msg_rcvd),
    .trn_vld_rcvd(LINK_valid_r)
);

////////////////////////////////////////////////////
// Reference Model
////////////////////////////////////////////////////

task automatic reference_model(
    input  logic [127:0] in_msg,
    input  logic         in_valid,
    output logic [127:0] exp_link_msg,
    output logic         exp_link_valid,
    output logic [127:0] exp_adapter_msg,
    output logic         exp_adapter_valid
);

    exp_link_msg     = '0;
    exp_link_valid   = 0;
    exp_adapter_msg  = '0;
    exp_adapter_valid= 0;

    if(in_msg[58:56] == REMOTE_PHY) begin
        exp_link_msg   = in_msg;
        exp_link_valid = in_valid;
    end
    else begin
        exp_adapter_msg   = in_msg;
        exp_adapter_valid = in_valid;
    end

endtask

////////////////////////////////////////////////////
// Checker
////////////////////////////////////////////////////

task automatic check_result;

    logic [127:0] exp_link_msg;
    logic exp_link_valid;
    logic [127:0] exp_adapter_msg;
    logic exp_adapter_valid;

    reference_model(
        msg_word_rcvd,
        word_valid_r,
        exp_link_msg,
        exp_link_valid,
        exp_adapter_msg,
        exp_adapter_valid
    );

    if( trn_msg_rcvd    !== exp_link_msg     ||
        LINK_valid_r     !== exp_link_valid   ||
        adapter_msg_rcvd !== exp_adapter_msg  ||
        Adapter_valid_r  !== exp_adapter_valid )
    begin
        $display("❌ FAIL @ %0t", $time);
        fail_cnt++;

        $display("Expected LINK_valid=%0d Adapter_valid=%0d",
                  exp_link_valid, exp_adapter_valid);
        $display("Got      LINK_valid=%0d Adapter_valid=%0d",
                  LINK_valid_r, Adapter_valid_r);
    end
    else begin
        pass_cnt++;
        $display("✅ PASS @ %0t", $time);
    end

endtask

////////////////////////////////////////////////////
// Stimulus
////////////////////////////////////////////////////

task automatic send_msg(
    input logic [127:0] msg,
    input logic         valid
);

    msg_word_rcvd = msg;
    word_valid_r  = valid;

    #1;
    check_result();

endtask

////////////////////////////////////////////////////
// Test Sequence
////////////////////////////////////////////////////

initial begin

    $display("==== LINK Demux Self Checking TB ====");

    //--------------------------------------
    // Directed tests
    //--------------------------------------

    send_msg({69'b0,REMOTE_PHY,56'h123456789ABC},1); // LINK
    send_msg({69'b0,3'b000,56'h555555},1);            // Adapter
    send_msg({69'b0,REMOTE_PHY,56'hAAAAAA},0);        // valid=0

    //--------------------------------------
    // Random tests
    //--------------------------------------

    repeat(50) begin
        send_msg($urandom, $urandom_range(0,1));
    end

    //--------------------------------------
    // Summary
    //--------------------------------------

    $display("================================");
    $display("PASS = %0d", pass_cnt);
    $display("FAIL = %0d", fail_cnt);
    $display("================================");

    if(fail_cnt == 0)
        $display("🎉 ALL TESTS PASSED");
    else
        $display("⚠️ SOME TESTS FAILED");

    $finish;

end

endmodule