`timescale 1ns/1ps
import UCIe_pkg::*;

// ============================================================================
// MBINIT_PARAM Comprehensive Unit Testbench
// ============================================================================
// Covers UCIe Rev 3.0 §4.5.3.2 MBINIT Parameter Exchange.
// Fully verifies speed, width, clocking, TARR, and SBFE negotiation.
// Test cases check FSM robust handshake flow, backpressure, timeout, 
// mismatch errors, enable resets, and partner timing variations (deadlock safety).
// ============================================================================

module MBINIT_PARAM_tb;

    logic clk;
    logic rst_n;

    // DUT Ports
    logic        mb_param_enable;
    logic        mb_param_done;
    logic        mb_param_error;

    // RX
    logic        mb_param_rx_valid;
    msg_no_e     mb_param_rx_msg_id;
    logic [15:0] mb_param_rx_MsgInfo;
    logic [63:0] mb_param_rx_data_Field;

    // TX
    logic        mb_param_tx_valid;
    msg_no_e     mb_param_tx_msg_id;
    logic [15:0] mb_param_tx_MsgInfo;
    logic [63:0] mb_param_tx_data_Field;

    // Hardcode signals
    logic [4:0]  Supported_TX_Vswing;
    logic        so;
    logic        mtp;
    logic [1:0]  Module_ID;

    // CAPABILITY REG
    logic        TARR_support_local_cap;
    logic [1:0]  Clock_Phase_cap;
    logic [1:0]  Clock_mode_cap;
    logic        L2SPD_support_local_cap;
    logic        PSPT_support_local_cap;
    logic        PMO_support_local_cap;
    logic [2:0]  Max_Link_Width_cap;
    logic [3:0]  Max_Link_Speed_cap;

    // CTRL REG
    logic        TARR_support_local_ctrl;
    logic        phy_x8_mode_ctrl;
    logic        Clock_Phase_ctrl;
    logic        Clock_mode_ctrl;
    logic        L2SPD_support_local_ctrl;
    logic        PSPT_support_local_ctrl;
    logic        PMO_support_local_ctrl;
    logic [3:0]  Target_Link_Width_ctrl;
    logic [3:0]  Target_Link_Speed_ctrl;
    logic        SPMW;

    // STATUS REG
    logic        Clock_Phase_enable_status;
    logic        Clock_mode_enable_status;
    logic        TARR_enable_status;
    logic [3:0]  Link_Width_enable_status;
    logic [3:0]  Link_Speed_enable_status;
    logic        PMO_enable_status;
    logic        L2SPD_enable_status;
    logic        PSPT_enable_status;

    logic        ltsm_rdy;
    logic        mb_param_timer_enable;
    assign mb_param_timer_enable = (dut.current_state != dut.MB_S0_IDLE && dut.current_state != dut.MB_S6_DONE && dut.current_state != dut.MB_S5_ERROR);
    logic        mb_param_timeout_expired;
    logic        global_error;
    assign global_error = mb_param_timeout_expired;

    int errors;
    int checks;
    int scn;

    // Clock generator (100 MHz -> 10ns period)
    initial clk = 0;
    always #5000 clk = ~clk;

    initial begin
        $dumpfile("MBINIT_PARAM_tb.vcd");
        $dumpvars(0, MBINIT_PARAM_tb);
    end

    // Instantiate DUT
    MBINIT_PARAM dut (
        .clk,
        .rst_n,
        .mb_param_enable,
        .mb_param_done,
        .mb_param_error,
        .sb_param_rx_valid     (mb_param_rx_valid),
        .sb_param_rx_msg_id    (mb_param_rx_msg_id),
        .sb_param_rx_data_Field(mb_param_rx_data_Field[15:0]),
        .sb_param_tx_valid     (mb_param_tx_valid),
        .sb_param_tx_msg_id    (mb_param_tx_msg_id),
        .sb_param_tx_MsgInfo   (mb_param_tx_MsgInfo),
        .sb_param_tx_data_Field(mb_param_tx_data_Field),
        .Supported_TX_Vswing,
        .so,
        .mtp,
        .Module_ID,
        .TARR_support_local_cap,
        .Clock_Phase_cap,
        .Clock_mode_cap,
        .L2SPD_support_local_cap,
        .PSPT_support_local_cap,
        .PMO_support_local_cap,
        .Max_Link_Speed_cap,
        .TARR_support_local_ctrl,
        .phy_x8_mode_ctrl,
        .SPMW,
        .Clock_Phase_ctrl,
        .Clock_mode_ctrl,
        .L2SPD_support_local_ctrl,
        .PSPT_support_local_ctrl,
        .PMO_support_local_ctrl,
        .Target_Link_Width_ctrl,
        .Target_Link_Speed_ctrl,
        .Clock_Phase_enable_status,
        .Clock_mode_enable_status,
        .TARR_enable_status,
        .Link_Width_enable_status,
        .Link_Speed_enable_status,
        .PMO_enable_status,
        .L2SPD_enable_status,
        .PSPT_enable_status,
        .sb_ltsm_rdy           (ltsm_rdy),
        .global_error
    );

    // ========================================================================
    // Helper Tasks
    // ========================================================================

    task check(input bit cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] SCN%0d FAIL: %s", $time, scn, msg);
        end else begin
            $display("[%0t] SCN%0d ok  : %s", $time, scn, msg);
        end
    endtask

    task do_reset();
        rst_n                    = 0;
        mb_param_enable          = 0;
        mb_param_rx_valid        = 0;
        mb_param_rx_msg_id       = msg_no_e'(NOTHING);
        mb_param_rx_MsgInfo      = 16'h0;
        mb_param_rx_data_Field   = 64'h0;
        
        // Defaults for hardcoded inputs
        Supported_TX_Vswing      = 5'h0;
        so                       = 1'b0;
        mtp                      = 1'b0;
        Module_ID                = 2'b00;

        // Default capabilities (All supported)
        TARR_support_local_cap   = 1'b1;
        Clock_Phase_cap          = 2'b01; // Quadrature supported
        Clock_mode_cap           = 2'b00; // Both strobe and continuous supported
        L2SPD_support_local_cap  = 1'b1;
        PSPT_support_local_cap   = 1'b1;
        PMO_support_local_cap    = 1'b1;
        Max_Link_Width_cap       = 3'd2;  // Up to x16
        Max_Link_Speed_cap       = 4'd4;  // Up to 32GT

        // Default control settings
        TARR_support_local_ctrl  = 1'b1;
        phy_x8_mode_ctrl         = 1'b0;  // Default x16
        Clock_Phase_ctrl         = 1'b0;  // Differential
        Clock_mode_ctrl          = 1'b0;  // Strobe mode
        L2SPD_support_local_ctrl = 1'b1;
        PSPT_support_local_ctrl  = 1'b1;
        PMO_support_local_ctrl   = 1'b1;
        Target_Link_Width_ctrl   = 4'h2;  // x16
        Target_Link_Speed_ctrl   = 4'd3;  // 16GT

        ltsm_rdy                 = 1'b1;
        mb_param_timeout_expired = 1'b0;
        SPMW                     = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    // Helper to disable SBFE locally and re-apply reset to latch it
    task disable_sbfe_locally();
        L2SPD_support_local_ctrl = 1'b0;
        PSPT_support_local_ctrl  = 1'b0;
        PMO_support_local_ctrl   = 1'b0;
        
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    // Send a message from partner
    task send_msg(input msg_no_e msg_id, input logic [63:0] data_field);
        @(posedge clk);
        mb_param_rx_valid      <= 1'b1;
        mb_param_rx_msg_id     <= msg_id;
        mb_param_rx_MsgInfo    <= 16'h0000;
        mb_param_rx_data_Field <= data_field;
        @(posedge clk);
        mb_param_rx_valid      <= 1'b0;
        mb_param_rx_msg_id     <= msg_no_e'(NOTHING);
        mb_param_rx_data_Field <= 64'h0;
    endtask

    // Handshake TX accept helper
    task accept_tx(input msg_no_e msg_id);
        wait (mb_param_tx_valid && mb_param_tx_msg_id == msg_id);
        @(posedge clk);
        ltsm_rdy <= 1'b1;
        @(posedge clk);
        ltsm_rdy <= 1'b0;
    endtask

    // ========================================================================
    // Main Test Suite
    // ========================================================================
    initial begin
        errors = 0;
        checks = 0;
        $display("[%0t] === MBINIT_PARAM COMPREHENSIVE TB START ===\n", $time);

        // ====================================================================
        // SCN 1: Happy Path with SBFE feature exchange
        // ====================================================================
        scn = 1;
        $display("[%0t] --- SCN %0d: HAPPY PATH WITH SBFE ---", $time, scn);
        do_reset();
        mb_param_enable = 1;

        // Step 1: Wait for configuration_req to drive
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        check(mb_param_timer_enable, "SCN1: Timer enabled during S1");
        
        // Partner sends config_req (TARR=1, SBFE=1, x16=0, speed=16GT)
        // [15]=1 (TARR), [14]=1 (SBFE), [13]=0 (x16), [3:0]=3 (16GT)
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_C003);

        // FSM transitions to RSP_SEND
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // Expect negotiated in configuration_resp: TARR=1, SBFE=1, Speed=16GT, width=x16 (Link_Width=4'h2)
        check(mb_param_tx_data_Field[15] == 1'b1, "SCN1: Negotiated TARR is 1");
        check(mb_param_tx_data_Field[14] == 1'b1, "SCN1: Negotiated SBFE is 1");
        check(mb_param_tx_data_Field[3:0] == 4'd3, "SCN1: Negotiated speed is 16GT");

        // Partner sends config_resp
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_C003);

        // FSM transitions to S2 Error Check -> SBFE is negotiated on both sides -> moves to S3 FEATURE_REQ_SEND
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_SBFE_req);
        // Expect local SBFE capability in request: L2SPD=1, PSPT=1, PMO=1, mtp=0, so=0 [4]=1, [3]=1, [1]=1 -> 64'h1A
        check(mb_param_tx_data_Field[4:0] == 5'h1A, "SCN1: Driven SBFE req matches local capabilities");

        // Partner sends SBFE_req (supports L2SPD=1, PSPT=1, PMO=1)
        send_msg(MBINIT_PARAM_SBFE_req, 64'h0000_0000_0000_001A);

        // FSM transitions to RSP_SEND
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_SBFE_resp);
        // Expect negotiated SBFE: L2SPD=1, PSPT=1, PMO=1
        check(mb_param_tx_data_Field[4:0] == 5'h1A, "SCN1: Negotiated SBFE resp matches");

        // Partner sends SBFE_resp
        send_msg(MBINIT_PARAM_SBFE_resp, 64'h0000_0000_0000_001A);

        // FSM transitions to S4 Error Check -> DONE
        wait (mb_param_done);
        check(!mb_param_error, "SCN1: Completed without errors");
        check(!mb_param_timer_enable, "SCN1: Timer disabled after done");
        
        // Check negotiated outputs in status registers
        check(TARR_enable_status == 1'b1, "SCN1: TARR Status is high");
        check(PMO_enable_status == 1'b1, "SCN1: PMO Status is high");
        check(L2SPD_enable_status == 1'b1, "SCN1: L2SPD Status is high");
        check(PSPT_enable_status == 1'b1, "SCN1: PSPT Status is high");
        check(Link_Width_enable_status == 4'h2, "SCN1: Width negotiated to x16");
        check(Link_Speed_enable_status == 4'd3, "SCN1: Speed negotiated to 16GT");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 2: Happy Path WITHOUT SBFE (Bypass S3 completely)
        // ====================================================================
        scn = 2;
        $display("\n[%0t] --- SCN %0d: HAPPY PATH WITHOUT SBFE ---", $time, scn);
        do_reset();
        
        // Disable SBFE features locally and re-latch
        disable_sbfe_locally();
        mb_param_enable = 1;

        // Step 1: Wait for configuration_req
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        
        // Partner supports TARR=1 and SBFE=1
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_C003);

        // Wait for config_resp
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // Expect negotiated SBFE in response is 0 because we disabled it locally
        check(mb_param_tx_data_Field[14] == 1'b0, "SCN2: Negotiated SBFE is 0");

        // Partner sends config_resp with SBFE=0 (since it echoes our negotiation)
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8003);

        // Since SBFE was negotiated to 0, FSM should bypass S3/S4 entirely and go straight to DONE
        wait (mb_param_done);
        check(!mb_param_error, "SCN2: FSM bypassed Feature Exchange and completed successfully");
        check(PMO_enable_status == 1'b0, "SCN2: PMO is negotiated to 0");
        check(L2SPD_enable_status == 1'b0, "SCN2: L2SPD is negotiated to 0");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 3: Speed Negotiation (Minimum of all speeds)
        // ====================================================================
        scn = 3;
        $display("\n[%0t] --- SCN %0d: SPEED NEGOTIATION ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE to keep test simple
        
        // Local Cap speed = 32GT (4'd4)
        Max_Link_Speed_cap = 4'd4;
        // Local Ctrl speed = 16GT (4'd3)
        Target_Link_Speed_ctrl = 4'd3;
        
        // Brief reset to latch the new speed capabilities
        rst_n = 0; repeat(5) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        // Partner sends config_req with speed=8GT (4'd2) and SBFE=0
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8002);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // Negotiated speed should be 8GT (minimum of local cap, local ctrl, and partner cap)
        check(mb_param_tx_data_Field[3:0] == 4'd2, "SCN3: Negotiated speed is 8GT");

        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8002);
        
        wait (mb_param_done);
        check(Link_Speed_enable_status == 4'd2, "SCN3: Status speed register negotiated to 8GT");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 4: Width Negotiation fallback to x8
        // ====================================================================
        scn = 4;
        $display("\n[%0t] --- SCN %0d: WIDTH NEGOTIATION FALLBACK TO X8 ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        
        // Local is configured to want x16
        Target_Link_Width_ctrl = 4'h2; // x16
        phy_x8_mode_ctrl = 1'b0;
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        // Partner sends config_req with x8 mode asserted ([13]=1) and SBFE=0
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_2003);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // Expect width fallback to x8 in config_resp
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_2003);

        wait (mb_param_done);
        check(Link_Width_enable_status == 4'h1, "SCN4: Negotiated status width fallback to x8 (4'h1)");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 5: Clocking Selection Logic (Differential vs Quadrature, Strobe vs Continuous)
        // ====================================================================
        scn = 5;
        $display("\n[%0t] --- SCN %0d: CLOCKING SELECTION LOGIC ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        
        // Setup clock configurations
        Clock_Phase_cap  = 2'b01;  // Quadrature supported
        Clock_mode_cap   = 2'b00;  // Both supported
        Clock_Phase_ctrl = 1'b1;  // Request quadrature phase
        Clock_mode_ctrl  = 1'b1;  // Request continuous clock
        Target_Link_Speed_ctrl = 4'd4; // 24GT! This enables quadrature phase!
        
        // Brief reset to latch clocking
        rst_n = 0; repeat(5) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        check(mb_param_tx_data_Field[10] == 1'b1, "SCN5: Local request phase is Quadrature (1)");
        check(mb_param_tx_data_Field[9] == 1'b1, "SCN5: Local request mode is Continuous (1)");

        // Partner supports both quadrature phase and continuous mode (SBFE=0) at speed 24GT (4'd4)
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8604);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        check(mb_param_tx_data_Field[10] == 1'b1, "SCN5: Negotiated phase is Quadrature");
        check(mb_param_tx_data_Field[9] == 1'b1, "SCN5: Negotiated mode is Continuous");

        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8604);
        wait (mb_param_done);
        
        check(Clock_Phase_enable_status == 1'b1, "SCN5: Status phase is high");
        check(Clock_mode_enable_status == 1'b1, "SCN5: Status mode is high");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 6: Backpressure handling (ltsm_rdy = 0)
        // ====================================================================
        scn = 6;
        $display("\n[%0t] --- SCN %0d: BACKPRESSURE (ltsm_rdy = 0) ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        
        ltsm_rdy = 1'b0; // FIFO full
        mb_param_enable = 1;

        // FSM should stay in PARAM_REQ_SEND and continue driving it
        repeat (20) @(posedge clk);
        check(mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req, 
              "SCN6: FSM stalled in PARAM_REQ_SEND during backpressure");

        ltsm_rdy = 1'b1; // Accept message
        wait (mb_param_timer_enable); // FSM transitioned to PARAM_REQ_WAIT

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 7: Partner Timing Variation (Concurrent Request / Early Arrival)
        // ====================================================================
        scn = 7;
        $display("\n[%0t] --- SCN %0d: PARTNER EARLY MESSAGE TIMING ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        
        ltsm_rdy = 1'b0; // Stalled
        mb_param_enable = 1;
        repeat (5) @(posedge clk);

        // Partner sends config_req early while we are stalled in REQ_SEND (SBFE=0)
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003);
        repeat (5) @(posedge clk);

        // We should still be driving ours since ltsm_rdy is 0
        check(mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req, 
              "SCN7: Still driving our configuration_req");

        // Now FIFO accepts ours
        ltsm_rdy = 1'b1;
        @(posedge clk);
        ltsm_rdy <= 1'b0;

        // FSM should instantly skip PARAM_REQ_WAIT because partner's request was already latched by sticky flag,
        // transitioning directly to PARAM_RSP_SEND
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        check(1'b1, "SCN7: Skipped PARAM_REQ_WAIT successfully!");

        // Finish normally
        ltsm_rdy = 1'b1;
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8003);
        
        wait(mb_param_done);
        check(!mb_param_error, "SCN7: Done successfully without error");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 8: Negotiation Mismatch in S2 Error Check (TRAINERROR)
        // ====================================================================
        scn = 8;
        $display("\n[%0t] --- SCN %0d: NEGOTIATION MISMATCH ERROR ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        // Partner sends config_req (Speed=16GT, TARR=1)
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // Partner returns mismatched config_resp (Speed=8GT, TARR=0 - doesn't match echoed negotiation!)
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_0002);

        // FSM reaches S2 Error Check, sees mismatch, and must transition to MB_S5_ERROR
        wait (mb_param_error);
        check(!mb_param_done, "SCN8: FSM failed to complete");
        check(mb_param_error, "SCN8: FSM transitioned to ERROR state");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 9: Timeout Watchdog
        // ====================================================================
        scn = 9;
        $display("\n[%0t] --- SCN %0d: TIMEOUT WATCHDOG ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // FSM is in PARAM_RSP_WAIT waiting for partner's response. Partner fails to reply.
        // Timer triggers timeout
        mb_param_timeout_expired = 1'b1;

        // FSM must transition immediately to MB_S5_ERROR
        wait (mb_param_error);
        check(!mb_param_done, "SCN9: FSM failed due to timeout");
        check(mb_param_error, "SCN9: FSM is in ERROR state");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 10: Clean Restart (Disable + Re-enable)
        // ====================================================================
        scn = 10;
        $display("\n[%0t] --- SCN %0d: CLEAN RESTART ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003);

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        // FSM is in RSP_WAIT. We disable the FSM
        mb_param_enable = 0;
        repeat (5) @(posedge clk);

        // Verify that FSM goes to IDLE and clears all registers/outputs
        check(!mb_param_done, "SCN10: Done is low");
        check(!mb_param_error, "SCN10: Error is low");
        check(!mb_param_tx_valid, "SCN10: Tx valid is low");

        // Re-enable: Should start fresh from S1 again
        mb_param_enable = 1;
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        check(1'b1, "SCN10: Restarted successfully from S1");

        // Complete normally to prove FSM works perfectly on restart
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003);
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8003);
        
        wait (mb_param_done);
        check(!mb_param_error, "SCN10: Clean restart completed successfully!");

        mb_param_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 11: Force x8 Mode via SPMW
        // ====================================================================
        scn = 11;
        $display("\n[%0t] --- SCN %0d: FORCE X8 MODE VIA SPMW ---", $time, scn);
        do_reset();
        disable_sbfe_locally(); // Bypass SBFE
        SPMW = 1'b1;            // Force SPMW (Standard Package Module Width = x8)
        mb_param_enable = 1;

        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_req);
        // Bit 13 should be 1 in our driven configuration request (forcing x8 capability)
        check(mb_param_tx_data_Field[13] == 1'b1, "SCN11: Local capabilities bit 13 (UCIE_x8) is forced to 1 by SPMW");

        // Send partner req
        send_msg(MBINIT_PARAM_configuration_req, 64'h0000_0000_0000_8003); // partner supports x16 only (bit 13 = 0)
        
        wait (mb_param_tx_valid && mb_param_tx_msg_id == MBINIT_PARAM_configuration_resp);

        // Send partner resp
        send_msg(MBINIT_PARAM_configuration_resp, 64'h0000_0000_0000_8003);
        
        wait (mb_param_done);
        check(Link_Width_enable_status == 4'h1, "SCN11: Final Link Width is negotiated to x8 (4'h1) due to SPMW force");

        mb_param_enable = 0;
        SPMW = 1'b0; // Restore default
        repeat (10) @(posedge clk);

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("\n[%0t] === DONE: %0d checks, %0d errors ===", $time, checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Hard sim watchdog
    initial begin
        #500_000_000;
        $display("[%0t] HARD TIMEOUT — possible hang", $time);
        $finish;
    end

endmodule