`timescale 1ns/1ps

module unit_LTSM_ctrl_tb;
    logic lclk;
    logic rst_n;
    logic [3:0] state_req;
    logic [3:0] state_status;
    logic timeout_timer_en;
    logic timeout_8ms_occured;
    logic mbtrain_en;
    logic mbtrain_done;

    internal_ltsm_if itf(lclk, rst_n);

    assign itf.state_req = state_req;
    // state_status is now assigned in the TB based on current_ltsm_state
    assign state_status = 4'(itf.current_ltsm_state);

    // In the real system, timeout_timer_en is driven by substates.
    // In this TB, we just monitor if the state matches what we expect for verification.
    assign timeout_timer_en = itf.timeout_timer_en;

    assign itf.timeout_8ms_occured = timeout_8ms_occured;

    assign mbtrain_en = itf.mbtrain_en;
    assign itf.mbtrain_done = mbtrain_done;

    unit_LTSM_ctrl dut (
        .itf(itf.ltsm_ctrl2states_mp)
    );

    // Handshake signals
    logic reset_done;
    logic sbinit_done;
    logic mbinit_done;
    logic linkinit_done;
    logic phyretrain_done;
    logic trainerror_done;

    assign itf.reset_done = reset_done;
    assign itf.sbinit_done = sbinit_done;
    assign itf.mbinit_done = mbinit_done;
    assign itf.linkinit_done = linkinit_done;
    assign itf.phyretrain_done = phyretrain_done;
    assign itf.trainerror_done = trainerror_done;

    // State definitions
    localparam RESET      = 4'd0;
    localparam SBINIT     = 4'd1;
    localparam MBINIT     = 4'd2;
    localparam MBTRAIN    = 4'd3;
    localparam LINKINIT   = 4'd4;
    localparam ACTIVE     = 4'd5;
    localparam PHYRETRAIN = 4'd6;
    localparam L1_L2      = 4'd7;
    localparam TRAINERROR = 4'd8;

    always #5 lclk = ~lclk;

    int error_count = 0;

    task check_state_and_outputs(input logic [3:0] exp_state, input logic exp_mbtrain_en);
        @(posedge lclk);
        #1;
        if (state_status !== exp_state) begin
            $display("ERROR @%0t: Expected state %0d, got %0d", $time, exp_state, state_status);
            error_count++;
        end
        if (mbtrain_en !== exp_mbtrain_en) begin
            $display("ERROR @%0t: Expected mbtrain_en %0b in state %0d, got %0b", $time, exp_mbtrain_en, exp_state, mbtrain_en);
            error_count++;
        end
    endtask

    initial begin
        lclk = 0;
        rst_n = 0;
        state_req = 0;
        timeout_8ms_occured = 0;
        mbtrain_done = 0;
        reset_done = 0;
        sbinit_done = 0;
        mbinit_done = 0;
        linkinit_done = 0;
        phyretrain_done = 0;
        trainerror_done = 0;

        $display("---------------------------------------------------------");
        $display("Test 1: Normal sequence to ACTIVE and beyond");

        #20;
        rst_n = 1;

        // In RESET state
        @(posedge lclk); #1;
        if (state_status !== RESET) begin
            $display("ERROR @%0t: Expected RESET state, got %0d", $time, state_status);
            error_count++;
        end
        reset_done = 1;

        // RESET -> SBINIT
        check_state_and_outputs(SBINIT, 0);
        reset_done = 0;
        mbinit_done = 1;

        // SBINIT -> MBINIT
        check_state_and_outputs(MBINIT, 0);
        mbinit_done = 0;
        mbtrain_done = 1;

        // MBINIT -> MBTRAIN
        check_state_and_outputs(MBTRAIN, 1);
        mbtrain_done = 0;

        // MBTRAIN -> LINKINIT (needs mbtrain_done again)
        mbtrain_done = 1;
        check_state_and_outputs(LINKINIT, 0);
        mbtrain_done = 0;

        // LINKINIT -> ACTIVE
        linkinit_done = 1;
        check_state_and_outputs(ACTIVE, 0);
        linkinit_done = 0;

        // ACTIVE -> PHYRETRAIN
        state_req = PHYRETRAIN;
        check_state_and_outputs(PHYRETRAIN, 0);

        // PHYRETRAIN -> MBTRAIN
        phyretrain_done = 1;
        check_state_and_outputs(MBTRAIN, 1);
        phyretrain_done = 0;

        // MBTRAIN -> LINKINIT -> ACTIVE
        mbtrain_done = 1;
        check_state_and_outputs(LINKINIT, 0);
        mbtrain_done = 0;
        linkinit_done = 1;
        check_state_and_outputs(ACTIVE, 0);
        linkinit_done = 0;

        // ACTIVE -> L1_L2
        state_req = L1_L2;
        check_state_and_outputs(L1_L2, 0);

        // L1_L2 -> MBTRAIN
        state_req = MBTRAIN;
        check_state_and_outputs(MBTRAIN, 1);

        $display("---------------------------------------------------------");
        $display("Test 2: Global timeout handling");

        timeout_8ms_occured = 1;
        check_state_and_outputs(TRAINERROR, 0);
        timeout_8ms_occured = 0;

        $display("---------------------------------------------------------");
        $display("Test 3: MBTRAIN Failure");
        // Reset to return to proper state
        rst_n = 0; #20; rst_n = 1;
        reset_done = 1; @(posedge lclk); reset_done = 0;
        mbinit_done = 1; @(posedge lclk); mbinit_done = 0;
        mbtrain_done = 1; @(posedge lclk); mbtrain_done = 0;
        check_state_and_outputs(MBTRAIN, 1);

        itf.trainerror_req = 1;
        check_state_and_outputs(TRAINERROR, 0);
        itf.trainerror_req = 0;

        $display("---------------------------------------------------------");
        $display("Test 4: Direct Request to TRAINERROR");
        rst_n = 0; #20; rst_n = 1;
        reset_done = 1; @(posedge lclk); reset_done = 0;
        state_req = TRAINERROR;
        check_state_and_outputs(TRAINERROR, 0);

        if (error_count > 0) begin
            $display("\nFAILED: %0d errors found in unit_LTSM_ctrl_tb\n\n", error_count);
            $stop;
        end else begin
            $display("\nPASSED: unit_LTSM_ctrl_tb completed successfully.\n\n");
        end
        // $finish;
        $stop;
    end
endmodule


