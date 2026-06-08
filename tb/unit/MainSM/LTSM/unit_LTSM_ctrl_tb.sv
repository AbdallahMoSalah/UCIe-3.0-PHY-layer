`timescale 1ns/1ps

module unit_LTSM_ctrl_tb;
    import UCIe_pkg::msg_no_e;
    import LTSM_state_pkg::*;
    import ltsm_state_n_pkg::state_n_e;
    import ltsm_state_n_pkg::LOG_RESET;
    import ltsm_state_n_pkg::ltsm_ctrl_state_e;
    import ltsm_state_n_pkg::CTRL_ACTIVE;
    import ltsm_state_n_pkg::CTRL_NOP;

    logic lclk;
    logic rst_n;
    logic [3:0] state_req;
    logic [3:0] state_status;
    logic timeout_timer_en;
    logic link_training_retraining;
    logic timeout_8ms_occured;
    logic mbtrain_en;
    logic mbtrain_done;

    // Handshake signals
    logic reset_done;
    logic sbinit_done;
    logic mbinit_done;
    logic linkinit_done;
    logic phyretrain_done;
    logic trainerror_done;

    // Enum variables for controller ports
    state_n_e current_ltsm_state_n;
    state_n_e mbinit_state_n_tb;
    state_n_e mbtrain_state_n_tb;
    ltsm_ctrl_state_e active_next_ltsm_state_tb;
    logic active_error_tb;

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

    assign itf.reset_done = reset_done;
    assign itf.sbinit_done = sbinit_done;
    assign itf.mbinit_done = mbinit_done;
    assign itf.linkinit_done = linkinit_done;
    assign itf.phyretrain_done = phyretrain_done;
    assign itf.trainerror_done = trainerror_done;

    // Instantiate new ltsm_controller
    ltsm_controller dut (
        .clk(lclk),
        .rst_n(rst_n),
        .state_req(state_req),
        .reset_req(itf.reset_req),
        .phyretrain_req(itf.phyretrain_req),
        .trainerror_req(itf.trainerror_req),
        .mbtrain_speedidle_req(itf.mbtrain_speedidle_req),
        .active_next_ltsm_state(active_next_ltsm_state_tb),
        .active_error(active_error_tb),
        .current_ltsm_state(itf.current_ltsm_state),
        .current_ltsm_state_n(current_ltsm_state_n),
        .link_training_retraining(link_training_retraining),
        
        .reset_en(itf.reset_en),
        .reset_done(reset_done),
        
        .sbinit_en(itf.sbinit_en),
        .sbinit_done(sbinit_done),
        
        .mbinit_en(itf.mbinit_en),
        .mbinit_done(mbinit_done),
        .mbinit_error(1'b0),
        
        .mbtrain_en(itf.mbtrain_en),
        .mbtrain_done(mbtrain_done),
        .mbtrain_error(1'b0),
        
        .linkinit_en(itf.linkinit_en),
        .linkinit_done(linkinit_done),
        
        .active_en(itf.active_en),
        
        .phyretrain_en(itf.phyretrain_en),
        .phyretrain_done(phyretrain_done),
        
        .l1_en(),
        .l1_done(1'b0),
        
        .l2_en(),
        .l2_done(1'b0),
        
        .trainerror_en(itf.trainerror_en),
        .trainerror_done(trainerror_done),
        
        .timeout_timer_en(itf.timeout_timer_en),
        .timer_rst_n(),
        .timeout_8ms_occured(timeout_8ms_occured),
        
        // Unused Sideband and Mainband ports
        .sb_tx_valid(),
        .sb_tx_msg_id(),
        .sb_tx_MsgInfo(),
        .sb_tx_data_Field(),
        .sbinit_tx_valid(1'b0),
        .sbinit_tx_msg_id(msg_no_e'(0)),
        .sbinit_tx_MsgInfo(16'b0),
        .sbinit_tx_data_Field(64'b0),
        .mbinit_tx_valid(1'b0),
        .mbinit_tx_msg_id(msg_no_e'(0)),
        .mbinit_tx_MsgInfo(16'b0),
        .mbinit_tx_data_Field(64'b0),
        .mbtrain_tx_valid(1'b0),
        .mbtrain_tx_msg_id(msg_no_e'(0)),
        .mbtrain_tx_MsgInfo(16'b0),
        .mbtrain_tx_data_Field(64'b0),
        
        .mb_tx_pattern_en(),
        .mb_tx_pattern_setup(),
        .mb_tx_data_pattern_sel(),
        .mb_tx_val_pattern_sel(),
        .mb_rx_compare_en(),
        .mb_rx_compare_setup(),
        .clear_error_req(),
        .mb_lane_reversal_req(),
        
        .mbinit_mb_tx_pattern_en(1'b0),
        .mbinit_mb_tx_pattern_setup(3'b0),
        .mbinit_mb_tx_data_pattern_sel(2'b0),
        .mbinit_mb_tx_val_pattern_sel(1'b0),
        .mbinit_mb_rx_compare_en(1'b0),
        .mbinit_mb_rx_compare_setup(2'b0),
        .mbinit_clear_error_req(1'b0),
        .mbinit_mb_lane_reversal_req(1'b0),
        
        .mbtrain_mb_tx_pattern_en(1'b0),
        .mbtrain_mb_tx_pattern_setup(3'b0),
        .mbtrain_mb_tx_data_pattern_sel(2'b0),
        .mbtrain_mb_tx_val_pattern_sel(1'b0),
        .mbtrain_mb_rx_compare_en(1'b0),
        .mbtrain_mb_rx_compare_setup(2'b0),
        .mbtrain_clear_error_req(1'b0),
        .mbtrain_mb_lane_reversal_req(1'b0),
        
        .local_tx_pt_en(),
        .partner_tx_pt_en(),
        .d2c_pattern_setup(),
        .d2c_data_pattern_sel(),
        .d2c_pattern_mode(),
        .d2c_compare_setup(),
        
        .mbinit_local_tx_pt_en(1'b0),
        .mbinit_partner_tx_pt_en(1'b0),
        .mbinit_d2c_pattern_setup(3'b0),
        .mbinit_d2c_data_pattern_sel(2'b0),
        .mbinit_d2c_pattern_mode(1'b0),
        .mbinit_d2c_compare_setup(2'b0),
        
        .mbtrain_local_tx_pt_en(1'b0),
        .mbtrain_partner_tx_pt_en(1'b0),
        .mbtrain_d2c_pattern_setup(3'b0),
        .mbtrain_d2c_data_pattern_sel(2'b0),
        .mbtrain_d2c_pattern_mode(1'b0),
        .mbtrain_d2c_compare_setup(2'b0),
        
        .reg_Max_Link_Width_cap(3'b000),
        
        .reg_Clock_Phase_enable_status(),
        .reg_Clock_mode_enable_status(),
        .reg_TARR_enable_status(),
        .reg_Link_Width_enable_status(),
        .reg_Link_Speed_enable_status(),
        .reg_PMO_enable_status(),
        .reg_L2SPD_enable_status(),
        .reg_PSPT_enable_status(),
        
        .mbinit_Clock_Phase_enable_status(1'b0),
        .mbinit_Clock_mode_enable_status(1'b0),
        .mbinit_TARR_enable_status(1'b0),
        .mbinit_Link_Width_enable_status(4'b0),
        .mbinit_Link_Speed_enable_status(4'b0),
        .mbinit_PMO_enable_status(1'b0),
        .mbinit_L2SPD_enable_status(1'b0),
        .mbinit_PSPT_enable_status(1'b0),
        
        .mbinit_state_n(mbinit_state_n_tb),
        .mbtrain_state_n(mbtrain_state_n_tb),
        
        .log0_state_n(),
        .log0_lane_reversal(),
        .log0_width_degrade(),
        .log0_state_n_minus_1(),
        .log0_state_n_minus_2(),
        .log1_state_n_minus_3(),
        
        .log0_state_n_valid(),
        .log0_lane_reversal_valid(),
        .log0_width_degrade_valid(),
        .log0_state_n_minus_1_valid(),
        .log0_state_n_minus_2_valid(),
        .log1_state_n_minus_3_valid(),
        
        .log1_state_timeout_occ(),
        .log1_sideband_timeout_occ(),
        .log1_remote_link_error(),
        .log1_internal_error(),
        
        .log1_state_timeout_occ_valid(),
        .log1_sideband_timeout_occ_valid(),
        .log1_remote_link_error_valid(),
        .log1_internal_error_valid()
    );

    // State definitions mapping local params to same names
    localparam RESET_VAL      = 4'd0;
    localparam SBINIT_VAL     = 4'd1;
    localparam MBINIT_VAL     = 4'd2;
    localparam MBTRAIN_VAL    = 4'd3;
    localparam LINKINIT_VAL   = 4'd4;
    localparam ACTIVE_VAL     = 4'd5;
    localparam PHYRETRAIN_VAL = 4'd6;
    localparam TRAINERROR_VAL = 4'd7;
    localparam L1_VAL         = 4'd8;
    localparam L2_VAL         = 4'd9;

    always #5 lclk = ~lclk;

    int error_count = 0;

    task check_state_and_outputs(input logic [3:0] exp_state, input logic exp_mbtrain_en);
        logic exp_training_retraining;
        exp_training_retraining = (exp_state == SBINIT_VAL) ||
                                  (exp_state == MBINIT_VAL) ||
                                  (exp_state == MBTRAIN_VAL) ||
                                  (exp_state == LINKINIT_VAL) ||
                                  (exp_state == PHYRETRAIN_VAL);
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
        if (link_training_retraining !== exp_training_retraining) begin
            $display("ERROR @%0t: Expected link_training_retraining %0b in state %0d, got %0b", $time, exp_training_retraining, exp_state, link_training_retraining);
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
        itf.trainerror_req = 0;
        itf.reset_req = 0;
        itf.phyretrain_req = 0;
        itf.mbtrain_speedidle_req = 0;
        mbinit_state_n_tb = LOG_RESET;
        mbtrain_state_n_tb = LOG_RESET;
        active_next_ltsm_state_tb = CTRL_ACTIVE;
        active_error_tb = 1'b0;

        $display("---------------------------------------------------------");
        $display("Test 1: Normal sequence to ACTIVE and beyond");

        #20;
        rst_n = 1;

        // In RESET state
        @(posedge lclk); #1;
        if (state_status !== RESET_VAL) begin
            $display("ERROR @%0t: Expected RESET state, got %0d", $time, state_status);
            error_count++;
        end
        if (link_training_retraining !== 1'b0) begin
            $display("ERROR @%0t: Expected link_training_retraining 0 in RESET, got %0b", $time, link_training_retraining);
            error_count++;
        end
        reset_done = 1;

        // RESET -> SBINIT
        check_state_and_outputs(SBINIT_VAL, 0);
        reset_done = 0;
        sbinit_done = 1;

        // SBINIT -> MBINIT
        check_state_and_outputs(MBINIT_VAL, 0);
        sbinit_done = 0;
        mbinit_done = 1;

        // MBINIT -> MBTRAIN
        check_state_and_outputs(MBTRAIN_VAL, 1);
        mbinit_done = 0;

        // MBTRAIN -> LINKINIT
        mbtrain_done = 1;
        check_state_and_outputs(LINKINIT_VAL, 0);
        mbtrain_done = 0;

        // LINKINIT -> ACTIVE
        linkinit_done = 1;
        check_state_and_outputs(ACTIVE_VAL, 0);
        linkinit_done = 0;

        // ACTIVE -> PHYRETRAIN
        state_req = PHYRETRAIN;
        check_state_and_outputs(PHYRETRAIN_VAL, 0);

        // PHYRETRAIN -> MBTRAIN
        phyretrain_done = 1;
        check_state_and_outputs(MBTRAIN_VAL, 1);
        phyretrain_done = 0;
        state_req = NO_OP;

        // MBTRAIN -> LINKINIT -> ACTIVE
        mbtrain_done = 1;
        check_state_and_outputs(LINKINIT_VAL, 0);
        mbtrain_done = 0;
        linkinit_done = 1;
        check_state_and_outputs(ACTIVE_VAL, 0);
        linkinit_done = 0;

        // ACTIVE -> L1
        state_req = L1;
        check_state_and_outputs(L1_VAL, 0);

        // L1 -> MBTRAIN
        state_req = MBTRAIN;
        check_state_and_outputs(MBTRAIN_VAL, 1);
        state_req = NO_OP;

        $display("---------------------------------------------------------");
        $display("Test 2: Global timeout handling");

        timeout_8ms_occured = 1;
        check_state_and_outputs(TRAINERROR_VAL, 0);
        timeout_8ms_occured = 0;

        $display("---------------------------------------------------------");
        $display("Test 3: MBTRAIN Failure");
        // Reset to return to proper state
        rst_n = 0; #20; rst_n = 1;
        reset_done = 1; @(posedge lclk); reset_done = 0;
        sbinit_done = 1; @(posedge lclk); sbinit_done = 0;
        mbinit_done = 1; @(posedge lclk); mbinit_done = 0;
        check_state_and_outputs(MBTRAIN_VAL, 1);

        itf.trainerror_req = 1;
        check_state_and_outputs(TRAINERROR_VAL, 0);
        itf.trainerror_req = 0;

        $display("---------------------------------------------------------");
        $display("Test 4: Direct Request to TRAINERROR");
        rst_n = 0; #20; rst_n = 1;
        reset_done = 1; @(posedge lclk); reset_done = 0;
        state_req = TRAINERROR;
        check_state_and_outputs(TRAINERROR_VAL, 0);

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
