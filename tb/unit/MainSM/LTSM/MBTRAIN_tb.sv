`timescale 1ns/1ps

module MBTRAIN_tb;
    logic lclk;
    logic rst_n;
    logic mbtrain_en;
    logic mbtrain_done;
    logic trainerror_req;

    internal_ltsm_if itf(lclk, rst_n);

    assign itf.mbtrain_en = mbtrain_en;
    assign mbtrain_done = itf.mbtrain_done;
    assign trainerror_req = itf.trainerror_req;

    MBTRAIN dut (
        .itf(itf.mbtrain_mp)
    );

    // Clock generation
    always #5 lclk = ~lclk;

    int error_count = 0;

    task set_all_done(input logic d);
        itf.valvref_done = d;
        itf.datavref_done = d;
        itf.speedidle_done = d;
        itf.txselfcal_done = d;
        itf.rxclkcal_done = d;
        itf.valtraincenter_done = d;
        itf.valtrainvref_done = d;
        itf.datatraincenter1_done = d;
        itf.datatrainvref_done = d;
        itf.rxdeskew_done = d;
        itf.datatraincenter2_done = d;
        itf.linkspeed_done = d;
        itf.repair_done = d;
    endtask

    task set_all_fail(input logic f);
        itf.datavref_fail_flag = f;
        itf.valtraincenter_fail_flag = f;
        itf.valtrainvref_fail_flag = f;
        itf.datatraincenter1_fail_flag = f;
        itf.rxdeskew_fail_flag = f;
        itf.datatraincenter2_fail_flag = f;
        itf.linkspeed_fail_flag = f;
        itf.repairmb_fail_flag = f; // MBINIT signal, but we can set it if it exists
        itf.trainerror_req = f;
    endtask

    task check_asserted(input logic sig, input string name);
        if (sig !== 1'b1) begin
            $display("ERROR @%0t: Expected %s to be asserted", $time, name);
            error_count++;
        end
    endtask

    task automatic test_fsm_transition(ref logic en_sig, ref logic done_sig, input string name, input int delay_cycles);
        check_asserted(en_sig, name);
        repeat(delay_cycles) @(posedge lclk);
        done_sig = 1;
        @(posedge lclk);
        #1;
        done_sig = 0;
    endtask

    task reset_dut;
        rst_n = 0;
        mbtrain_en = 0;
        set_all_done(0);
        set_all_fail(0);
        repeat(3) @(posedge lclk);
        rst_n = 1;
        repeat(2) @(posedge lclk);
    endtask

    initial begin
        lclk = 0;
        reset_dut();

        $display("---------------------------------------------------------");
        $display("Test 1: Full Normal Sequence to DONE");
        mbtrain_en = 1;
        @(posedge lclk); #1; // enter VALVREF
        test_fsm_transition(itf.valvref_en, itf.valvref_done, "valvref_en", 2);
        test_fsm_transition(itf.datavref_en, itf.datavref_done, "datavref_en", 1);
        test_fsm_transition(itf.speedidle_en, itf.speedidle_done, "speedidle_en", 3);
        test_fsm_transition(itf.txselfcal_en, itf.txselfcal_done, "txselfcal_en", 2);
        test_fsm_transition(itf.rxclkcal_en, itf.rxclkcal_done, "rxclkcal_en", 1);
        test_fsm_transition(itf.valtraincenter_en, itf.valtraincenter_done, "valtraincenter_en", 2);
        test_fsm_transition(itf.valtrainvref_en, itf.valtrainvref_done, "valtrainvref_en", 1);
        test_fsm_transition(itf.datatraincenter1_en, itf.datatraincenter1_done, "datatraincenter1_en", 2);
        test_fsm_transition(itf.datatrainvref_en, itf.datatrainvref_done, "datatrainvref_en", 1);
        test_fsm_transition(itf.rxdeskew_en, itf.rxdeskew_done, "rxdeskew_en", 2);
        test_fsm_transition(itf.datatraincenter2_en, itf.datatraincenter2_done, "datatraincenter2_en", 1);
        
        // Final transition in LINKSPEED
        check_asserted(itf.linkspeed_en, "linkspeed_en");
        itf.linkinit_req = 1;
        itf.linkspeed_done = 1;
        @(posedge lclk); #1;
        itf.linkinit_req = 0;
        itf.linkspeed_done = 0;

        check_asserted(mbtrain_done, "mbtrain_done");
        if (trainerror_req !== 1'b0) begin
            $display("ERROR @%0t: trainerror_req should be 0", $time);
            error_count++;
        end

        $display("---------------------------------------------------------");
        $display("Test 2: LINKSPEED Fail -> REPAIR -> DONE");
        reset_dut();
        mbtrain_en = 1;
        @(posedge lclk); #1;
        // Fast forward to LINKSPEED
        itf.valvref_done = 1; @(posedge lclk); itf.valvref_done = 0; #1;
        itf.datavref_done = 1; @(posedge lclk); itf.datavref_done = 0; #1;
        itf.speedidle_done = 1; @(posedge lclk); itf.speedidle_done = 0; #1;
        itf.txselfcal_done = 1; @(posedge lclk); itf.txselfcal_done = 0; #1;
        itf.rxclkcal_done = 1; @(posedge lclk); itf.rxclkcal_done = 0; #1;
        itf.valtraincenter_done = 1; @(posedge lclk); itf.valtraincenter_done = 0; #1;
        itf.valtrainvref_done = 1; @(posedge lclk); itf.valtrainvref_done = 0; #1;
        itf.datatraincenter1_done = 1; @(posedge lclk); itf.datatraincenter1_done = 0; #1;
        itf.datatrainvref_done = 1; @(posedge lclk); itf.datatrainvref_done = 0; #1;
        itf.rxdeskew_done = 1; @(posedge lclk); itf.rxdeskew_done = 0; #1;
        itf.datatraincenter2_done = 1; @(posedge lclk); itf.datatraincenter2_done = 0; #1;
        
        check_asserted(itf.linkspeed_en, "linkspeed_en");
        itf.repair_req = 1; 
        itf.linkspeed_done = 1;
        @(posedge lclk); #1;
        itf.repair_req = 0;
        itf.linkspeed_done = 0;
        
        check_asserted(itf.repair_en, "repair_en");
        itf.repair_done = 1;
        @(posedge lclk); #1;
        itf.repair_done = 0;
        
        // After REPAIR, it goes back to TXSELFCAL
        check_asserted(itf.txselfcal_en, "txselfcal_en");

        $display("---------------------------------------------------------");
        $display("Test 3: Early Failure -> TRAINERROR");
        reset_dut();
        mbtrain_en = 1;
        @(posedge lclk); #1;
        check_asserted(itf.valvref_en, "valvref_en");
        
        itf.trainerror_req = 1;
        @(posedge lclk); #1;
        
        // In MBTRAIN, if trainerror_req is high, it holds state. 
        // ltsm_ctrl should see trainerror_req and move the whole thing.
        // Our test checks if we are NOT done.
        if (mbtrain_done !== 1'b0) begin
            $display("ERROR @%0t: mbtrain_done should be 0 on failure", $time);
            error_count++;
        end

        if (error_count > 0) begin
            $display("FAILED: %0d errors found in MBTRAIN_tb", error_count);
            $stop;
        end else begin
            $display("PASSED: MBTRAIN_tb completed successfully.");
        end
        
        $finish;
    end
endmodule
