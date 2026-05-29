`timescale 1ns/1ps
import UCIe_pkg::*;

module MBINIT_REPAIRMB_tb;

    ////////////////////////////////////////////////
    // CLOCK / RESET GENERATION
    ////////////////////////////////////////////////
    logic clk;
    logic rst_n;

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz clock in simulation

    ////////////////////////////////////////////////
    // CAPABILITY INTERFACES
    ////////////////////////////////////////////////
    ucie_mb_cap_if cap_if_master();
    ucie_mb_cap_if cap_if_partner();

    // Default setup
    assign cap_if_master.negotiated_speed  = 4'h1;
    assign cap_if_partner.negotiated_speed = 4'h1;

    // Registers to control use_x8_mode dynamically
    logic m_use_x8_mode;
    logic p_use_x8_mode;
    logic m_spmw;
    logic p_spmw;
    assign cap_if_master.use_x8_mode  = m_use_x8_mode;
    assign cap_if_partner.use_x8_mode = p_use_x8_mode;

    logic [3:0] m_width_status;
    logic [3:0] p_width_status;
    assign m_width_status = m_use_x8_mode ? 4'h1 : 4'h0;
    assign p_width_status = p_use_x8_mode ? 4'h1 : 4'h0;

    ////////////////////////////////////////////////
    // SIGNAL DEFINITIONS
    ////////////////////////////////////////////////
    logic m_enable, m_done, m_error;
    logic p_enable, p_done, p_error;

    // Sideband connection (Master TX to Partner RX, Partner TX to Master RX)
    logic         m_tx_valid;
    msg_no_e      m_tx_msg_id;
    logic [15:0]  m_tx_MsgInfo;
    logic [63:0]  m_tx_data_Field;

    logic         p_tx_valid;
    msg_no_e      p_tx_msg_id;
    logic [15:0]  p_tx_MsgInfo;
    logic [63:0]  p_tx_data_Field;

    // FIFO ready handshaking
    logic         m_ltsm_rdy;
    logic         p_ltsm_rdy;

    // d2cptest interface
    logic         m_tx_pt_en, p_tx_pt_en;
    logic [2:0]   m_d2c_pattern_setup, p_d2c_pattern_setup;
    logic [1:0]   m_d2c_data_pattern_sel, p_d2c_data_pattern_sel;
    logic         m_d2c_pattern_mode, p_d2c_pattern_mode;
    logic [1:0]   m_d2c_compare_setup, p_d2c_compare_setup;
    logic [15:0]  m_d2c_perlane_pass, p_d2c_perlane_pass;
    logic         m_test_d2c_done, p_test_d2c_done;
    logic         m_clear_error_req, p_clear_error_req;

    // Timer interface
    logic         m_timeout_repair_expired;
    logic         m_timeout_repair_enable;
    logic         p_timeout_repair_expired;
    logic         p_timeout_repair_enable;
    assign m_timeout_repair_enable = m_enable;
    assign p_timeout_repair_enable = p_enable;

    // PHY status signals (monitored)
    logic         m_tx_valid_status, m_tx_track_status, m_tx_clk_status, m_tx_data_status;
    logic         m_rx_valid_status, m_rx_track_status, m_rx_clk_status, m_rx_data_status;
    logic         p_tx_valid_status, p_tx_track_status, p_tx_clk_status, p_tx_data_status;
    logic         p_rx_valid_status, p_rx_track_status, p_rx_clk_status, p_rx_data_status;

    // Output lane masks
    logic [2:0]   m_mbinit_rx_data_lane_mask, m_mbinit_tx_data_lane_mask;
    logic [2:0]   p_mbinit_rx_data_lane_mask, p_mbinit_tx_data_lane_mask;

    ////////////////////////////////////////////////
    // TIMERS INSTANTIATION (EXTERNAL)
    ////////////////////////////////////////////////
    timeout_counter #(
        .CLK_FRQ_HZ(1000000), // Fast timeout for simulation
        .TIME_OUT(1)          // 1 ms (1000 clock cycles)
    ) master_timer (
        .clk(clk),
        .timeout_rst_n(rst_n),
        .enable_timeout(m_timeout_repair_enable),
        .timeout_expired(m_timeout_repair_expired)
    );

    timeout_counter #(
        .CLK_FRQ_HZ(1000000),
        .TIME_OUT(1)
    ) partner_timer (
        .clk(clk),
        .timeout_rst_n(rst_n),
        .enable_timeout(p_timeout_repair_enable),
        .timeout_expired(p_timeout_repair_expired)
    );

    ////////////////////////////////////////////////
    // DUT INSTANTIATIONS
    ////////////////////////////////////////////////
    MBINIT_REPAIRMB #(
        .CLK_FRQ_HZ(1000000)
    ) master (
        .clk(clk),
        .rst_n(rst_n),
        .Link_Width_enable_status(m_width_status),
        .SPMW(m_spmw),
        .mb_repairmb_enable(m_enable),
        .mb_repairmb_done(m_done),
        .mb_repairmb_error(m_error),

        // RX
        .sb_repairmb_rx_valid(p_tx_valid),
        .sb_repairmb_rx_msg_id(p_tx_msg_id),
        .sb_repairmb_rx_MsgInfo(p_tx_MsgInfo),
        .sb_repairmb_rx_data_Field(p_tx_data_Field),

        // TX
        .sb_repairmb_tx_valid(m_tx_valid),
        .sb_repairmb_tx_msg_id(m_tx_msg_id),
        .sb_repairmb_tx_MsgInfo(m_tx_MsgInfo),
        .sb_repairmb_tx_data_Field(m_tx_data_Field),

        // Timer
        .global_error(m_timeout_repair_expired),

        // FIFO ready
        .sb_ltsm_rdy(m_ltsm_rdy),

        // d2cptest
        .tx_pt_en(m_tx_pt_en),
        .d2c_pattern_setup(m_d2c_pattern_setup),
        .d2c_data_pattern_sel(m_d2c_data_pattern_sel),
        .d2c_pattern_mode(m_d2c_pattern_mode),
        .d2c_compare_setup(m_d2c_compare_setup),
        .d2c_perlane_pass(m_d2c_perlane_pass),
        .test_d2c_done(m_test_d2c_done),
        .clear_error_req(m_clear_error_req),
        .mbinit_rx_data_lane_mask(m_mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(m_mbinit_tx_data_lane_mask)
    );

    MBINIT_REPAIRMB #(
        .CLK_FRQ_HZ(1000000)
    ) partner (
        .clk(clk),
        .rst_n(rst_n),
        .Link_Width_enable_status(p_width_status),
        .SPMW(p_spmw),
        .mb_repairmb_enable(p_enable),
        .mb_repairmb_done(p_done),
        .mb_repairmb_error(p_error),

        // RX
        .sb_repairmb_rx_valid(m_tx_valid),
        .sb_repairmb_rx_msg_id(m_tx_msg_id),
        .sb_repairmb_rx_MsgInfo(m_tx_MsgInfo),
        .sb_repairmb_rx_data_Field(m_tx_data_Field),

        // TX
        .sb_repairmb_tx_valid(p_tx_valid),
        .sb_repairmb_tx_msg_id(p_tx_msg_id),
        .sb_repairmb_tx_MsgInfo(p_tx_MsgInfo),
        .sb_repairmb_tx_data_Field(p_tx_data_Field),

        // Timer
        .global_error(p_timeout_repair_expired),

        // FIFO ready
        .sb_ltsm_rdy(p_ltsm_rdy),

        // d2cptest
        .tx_pt_en(p_tx_pt_en),
        .d2c_pattern_setup(p_d2c_pattern_setup),
        .d2c_data_pattern_sel(p_d2c_data_pattern_sel),
        .d2c_pattern_mode(p_d2c_pattern_mode),
        .d2c_compare_setup(p_d2c_compare_setup),
        .d2c_perlane_pass(p_d2c_perlane_pass),
        .test_d2c_done(p_test_d2c_done),
        .clear_error_req(p_clear_error_req),
        .mbinit_rx_data_lane_mask(p_mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(p_mbinit_tx_data_lane_mask)
    );

    ////////////////////////////////////////////////
    // SAFETY CHECKS
    ////////////////////////////////////////////////
    logic expect_error;
    always @(posedge clk) begin
        if (rst_n && (m_error || p_error) && !expect_error) begin
            $error("ERROR: Unexpected error flag assertion! expect_error=%b", expect_error);
            $finish;
        end
    end

    ////////////////////////////////////////////////
    // SYSTEM RESET AND HELPER METHODS
    ////////////////////////////////////////////////
    task reset_system();
        rst_n = 1'b0;
        m_enable = 1'b0;
        p_enable = 1'b0;
        m_ltsm_rdy = 1'b1;
        p_ltsm_rdy = 1'b1;
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'hFFFF;
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;
        m_use_x8_mode = 1'b0;
        p_use_x8_mode = 1'b0;
        m_spmw = 1'b0;
        p_spmw = 1'b0;
        expect_error = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);
    endtask

    ////////////////////////////////////////////////
    // TEST SUITE
    ////////////////////////////////////////////////
    initial begin
        $display("==========================================================");
        $display("   STARTING MBINIT_REPAIRMB COMPREHENSIVE TEST SUITE      ");
        $display("==========================================================");

        // --------------------------------------------------------
        // SCN 1: Normal Happy Path (All PASS, x16 Mode)
        // --------------------------------------------------------
        $display("\n[SCN 1] Normal Happy Path (All PASS, x16 Mode)");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait for both sides to enter point test state (S2)
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST && partner.current_state == partner.MB_S2_D2C_POINT_TEST);
        $display("  -> Both sides entered Point Test S2.");
        repeat(5) @(posedge clk);

        // Set status and complete point test
        m_d2c_perlane_pass = 16'hFFFF; // Pass
        p_d2c_perlane_pass = 16'hFFFF; // Pass
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for completion
        wait (m_done && p_done);
        $display("  -> Happy path completed successfully! done=%b, error=%b", m_done, m_error);
        if (m_error || p_error) $error("ERROR: SCN 1 reported unexpected errors!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 2: Degrade to Lower x8 Mode & Retry PASS
        // --------------------------------------------------------
        $display("\n[SCN 2] Degrade to Lower x8 Mode & Retry PASS");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1: PASS lower 8 lanes, FAIL upper 8 lanes (16'h00FF -> Lower x8 operational)
        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'h00FF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry transition back to S2 (safely wait for leaving S2 first)
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! Returned to Point Test S2.");
        $display("  DEBUG: retry_done sticky flag is %b", master.retry_done);

        // S2 Run 2: Lower x8 lanes pass (but upper 8 lanes remain broken physically!)
        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'h00FF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to Lower x8 completed! done=%b, error=%b, Tx mask=%b", m_done, m_error, master.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Tx mask is not Lower x8!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 3: Degrade to Upper x8 Mode & Retry PASS
        // --------------------------------------------------------
        $display("\n[SCN 3] Degrade to Upper x8 Mode & Retry PASS");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1: PASS upper 8 lanes, FAIL lower 8 (16'hFF00 -> Upper x8 operational)
        m_d2c_perlane_pass = 16'hFF00;
        p_d2c_perlane_pass = 16'hFF00;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! S2 Run 2.");

        // S2 Run 2: Upper x8 lanes pass (lower 8 lanes remain broken physically!)
        m_d2c_perlane_pass = 16'hFF00;
        p_d2c_perlane_pass = 16'hFF00;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to Upper x8 completed! done=%b, error=%b, Tx mask=%b", m_done, m_error, master.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b010) $error("ERROR: Tx mask is not Upper x8!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 4: Advanced Degrade to x4 Mode & Retry PASS
        // --------------------------------------------------------
        $display("\n[SCN 4] Advanced Degrade to x4 Mode & Retry PASS");
        reset_system();
        m_use_x8_mode = 1'b1; // Start in x8 mode
        p_use_x8_mode = 1'b1;
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1: PASS lanes 0-3, FAIL others (16'h000F -> x4 map 3'b100)
        m_d2c_perlane_pass = 16'h000F;
        p_d2c_perlane_pass = 16'h000F;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! S2 Run 2 under x8_mode.");

        // S2 Run 2: Pass (lanes 4-15 remain broken physically!)
        m_d2c_perlane_pass = 16'h000F;
        p_d2c_perlane_pass = 16'h000F;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to x4 completed! done=%b, error=%b, Tx mask=%b", m_done, m_error, master.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b100) $error("ERROR: Tx mask is not x4!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        m_use_x8_mode = 1'b0;
        p_use_x8_mode = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 5: Double Failure Retry FAIL
        // --------------------------------------------------------
        $display("\n[SCN 5] Double Failure Retry FAIL");
        reset_system();
        expect_error = 1'b1; // We expect error to trigger (set AFTER reset_system clears it)
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1: PASS lower 8 lanes, FAIL upper 8 lanes (degrade to lower x8)
        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'h00FF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);

        // S2 Run 2: Fail again (all fail -> 16'h0000 -> no further degradation possible)
        m_d2c_perlane_pass = 16'h0000;
        p_d2c_perlane_pass = 16'h0000;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for error state
        wait (m_error && p_error);
        $display("  -> Double failure handled correctly! done=%b, error=%b", m_done, m_error);
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk); // Allow error status to settle/clear in IDLE first
        expect_error = 1'b0;      // Now safe to disable expect_error
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 6: FIFO Backpressure Handling (ltsm_rdy = 0)
        // --------------------------------------------------------
        $display("\n[SCN 6] FIFO Backpressure Handling (ltsm_rdy = 0)");
        reset_system();
        m_ltsm_rdy = 1'b0; // Block master sideband transmission
        m_enable = 1'b1;
        p_enable = 1'b1;

        repeat (20) @(posedge clk);
        if (master.current_state != master.MB_S1_READY_REQ_SEND) begin
            $error("ERROR: Master did not hold in READY_REQ_SEND state during backpressure!");
        end else begin
            $display("  -> Master successfully held in S1_READY_REQ_SEND.");
        end

        // Release backpressure
        m_ltsm_rdy = 1'b1;
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        $display("  -> Backpressure released, master advanced to S2.");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 7: Safety Watchdog Timeout
        // --------------------------------------------------------
        $display("\n[SCN 7] Safety Watchdog Timeout");
        reset_system();
        expect_error = 1'b1; // We expect error to trigger due to timeout
        m_enable = 1'b1; // Only enable master to force no response from partner
        p_enable = 1'b0;

        wait (master.current_state == master.MB_S1_READY_REQ_WAIT);
        $display("  -> Master is in READY_REQ_WAIT state. Waiting for timeout...");
        
        wait (m_error);
        $display("  -> Master safety timeout fired successfully! error=%b", m_error);
        m_enable = 1'b0;
        repeat(5) @(posedge clk); // Allow error to settle/clear in IDLE first
        expect_error = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 8: Clean Restart (Disable/Re-enable)
        // --------------------------------------------------------
        $display("\n[SCN 8] Clean Restart (Disable/Re-enable)");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Disabling training midway...");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(2) @(posedge clk); // Safely let it transition to IDLE

        if (master.current_state != master.MB_S0_IDLE || partner.current_state != partner.MB_S0_IDLE) begin
            $error("ERROR: FSMs did not return cleanly to S0_IDLE on disable!");
        end else begin
            $display("  -> Clean return to IDLE verified.");
        end

        // Re-enable and complete cleanly
        m_enable = 1'b1;
        p_enable = 1'b1;
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST); // Wait for leaving IDLE first
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'hFFFF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Clean restart run completed successfully!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 9: Force x8 Mode via SPMW & Degrade x4 Retry PASS
        // --------------------------------------------------------
        $display("\n[SCN 9] Force x8 Mode via SPMW & Degrade x4 Retry PASS");
        reset_system();
        m_spmw = 1'b1; // Force SPMW = 1
        p_spmw = 1'b1;
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1: PASS lanes 0-3, FAIL others (16'h000F -> x4 map 3'b100)
        m_d2c_perlane_pass = 16'h000F;
        p_d2c_perlane_pass = 16'h000F;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered under SPMW forced x8 mode!");

        // S2 Run 2: Pass at x4 width
        m_d2c_perlane_pass = 16'h000F;
        p_d2c_perlane_pass = 16'h000F;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to x4 via SPMW completed! done=%b, error=%b, Tx mask=%b", m_done, m_error, master.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b100) $error("ERROR: Tx mask is not x4!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        m_spmw = 1'b0;
        p_spmw = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 10: Spec Example Asymmetric Degrade (Master upper x8, Partner lower x8)
        // --------------------------------------------------------
        $display("\n[SCN 10] Spec Example Asymmetric Degrade (Master upper x8, Partner lower x8)");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1:
        // Master receives on lower x8, but has error on Lane 1 -> fails lower x8 (only upper operational -> 16'hFF00)
        m_d2c_perlane_pass = 16'hFF00;
        // Partner receives on upper x8, but has error on Lane 10 -> fails upper x8 (only lower operational -> 16'h00FF)
        p_d2c_perlane_pass = 16'h00FF;

        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! Asymmetric point test S2 Run 2.");

        // S2 Run 2:
        // Master's Rx listens to Partner's Tx (lower x8), which passes -> m_d2c_perlane_pass = 16'h00FF
        m_d2c_perlane_pass = 16'h00FF;
        // Partner's Rx listens to Master's Tx (upper x8), which passes -> p_d2c_perlane_pass = 16'hFF00
        p_d2c_perlane_pass = 16'hFF00;

        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_done && p_done);
        $display("  -> Asymmetric degrade completed! Master map (Tx)=%b, Partner map (Tx)=%b", master.mbinit_tx_data_lane_mask_r, partner.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b010) $error("ERROR: Master did not degrade to Upper x8!");
        if (partner.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Partner did not degrade to Lower x8!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 11: Retry Lane Map Mismatch (Must trigger error)
        // --------------------------------------------------------
        $display("\n[SCN 11] Retry Lane Map Mismatch (Must trigger error)");
        reset_system();
        expect_error = 1'b1; // We expect error to be asserted
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        m_d2c_perlane_pass = 16'hFF00; // Master Tx wants upper x8
        p_d2c_perlane_pass = 16'h00FF; // Partner Tx wants lower x8
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! Mismatch inject in Run 2.");

        // Force Partner's sideband message in retry to show a different map (e.g. 3'b010 instead of 3'b001)
        force partner.local_lane_map = 3'b010;

        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'hFF00;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        wait (m_error);
        $display("  -> Mismatch successfully triggered error! done=%b, error=%b", m_done, m_error);
        release partner.local_lane_map;
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);
        expect_error = 1'b0;

        // --------------------------------------------------------
        // SCN 12: Independent pair training (Master Tx = x16, Rx = lower x8; Partner Tx = lower x8, Rx = x16)
        // --------------------------------------------------------
        $display("\n[SCN 12] Independent pair training (Master Tx = x16, Rx = lower x8; Partner Tx = lower x8, Rx = x16)");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST && partner.current_state == partner.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1:
        // Master Rx has no errors -> m_d2c_perlane_pass = 16'hFFFF (Master Tx wants x16)
        m_d2c_perlane_pass = 16'hFFFF;
        // Partner Rx has error on Lane 10 -> p_d2c_perlane_pass = 16'h00FF (Partner Tx wants lower x8)
        p_d2c_perlane_pass = 16'h00FF;

        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Since Master Tx changed to match Partner Rx (from x16 to lower x8), both Master and Partner will retry!
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST && partner.current_state == partner.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered on both sides successfully!");
        $display("     Master Tx mask = %b, Rx mask = %b", master.mbinit_tx_data_lane_mask_r, master.mbinit_rx_data_lane_mask_r);
        $display("     Partner Tx mask = %b, Rx mask = %b", partner.mbinit_tx_data_lane_mask_r, partner.mbinit_rx_data_lane_mask_r);

        if (master.mbinit_tx_data_lane_mask_r != 3'b011) $error("ERROR: Master Tx mask should be 3'b011!");
        if (master.mbinit_rx_data_lane_mask_r != 3'b001) $error("ERROR: Master Rx mask should be 3'b001!");
        if (partner.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Partner Tx mask should be 3'b001!");
        if (partner.mbinit_rx_data_lane_mask_r != 3'b011) $error("ERROR: Partner Rx mask should be 3'b011!");

        // Drive S2 Run 2 for both Master and Partner:
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'hFFFF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Both sides finish training successfully
        wait (m_done && p_done);
        $display("  -> Independent pair training completed successfully! Master Tx mask = %b, Partner Tx mask = %b", 
                 master.mbinit_tx_data_lane_mask_r, partner.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Master final Tx map is not 3'b001!");
        if (partner.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Partner final Tx map is not 3'b001!");

        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 13: Independent pair training (Master Tx = lower x8, Rx = x16; Partner Tx = x16, Rx = lower x8)
        // --------------------------------------------------------
        $display("\n[SCN 13] Independent pair training (Master Tx = lower x8, Rx = x16; Partner Tx = x16, Rx = lower x8)");
        reset_system();
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST && partner.current_state == partner.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // S2 Run 1:
        // Master Rx has error on Lane 10 -> m_d2c_perlane_pass = 16'h00FF (Master Tx wants lower x8)
        m_d2c_perlane_pass = 16'h00FF;
        // Partner Rx has no errors -> p_d2c_perlane_pass = 16'hFFFF (Partner Tx wants x16)
        p_d2c_perlane_pass = 16'hFFFF;

        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Since Partner Tx changed to match Master Rx (from x16 to lower x8), both Master and Partner will retry!
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST && partner.current_state == partner.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered on both sides successfully!");
        $display("     Master Tx mask = %b, Rx mask = %b", master.mbinit_tx_data_lane_mask_r, master.mbinit_rx_data_lane_mask_r);
        $display("     Partner Tx mask = %b, Rx mask = %b", partner.mbinit_tx_data_lane_mask_r, partner.mbinit_rx_data_lane_mask_r);

        if (master.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Master Tx mask should be 3'b001!");
        if (master.mbinit_rx_data_lane_mask_r != 3'b011) $error("ERROR: Master Rx mask should be 3'b011!");
        if (partner.mbinit_tx_data_lane_mask_r != 3'b011) $error("ERROR: Partner Tx mask should be 3'b011!");
        if (partner.mbinit_rx_data_lane_mask_r != 3'b001) $error("ERROR: Partner Rx mask should be 3'b001!");

        // Drive S2 Run 2 for both Master and Partner:
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'hFFFF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Both sides finish training successfully
        wait (m_done && p_done);
        $display("  -> Independent pair training completed successfully! Master Tx mask = %b, Partner Tx mask = %b", 
                 master.mbinit_tx_data_lane_mask_r, partner.mbinit_tx_data_lane_mask_r);
        if (master.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Master final Tx map is not 3'b001!");
        if (partner.mbinit_tx_data_lane_mask_r != 3'b001) $error("ERROR: Partner final Tx map is not 3'b001!");

        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);

        // --------------------------------------------------------
        // SCN 14: Immediate Failure on First Run (Local Failure)
        // --------------------------------------------------------
        $display("\n[SCN 14] Immediate Failure on First Run (Local Failure)");
        reset_system();
        expect_error = 1'b1; // We expect error to trigger
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // Master and Partner fail all lanes in the first run (degrade not possible)
        m_d2c_perlane_pass = 16'h0;
        p_d2c_perlane_pass = 16'h0;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // FSM should transition immediately to S6 REPAIR_ERROR in S4 Degrade Verification
        wait (m_error && p_error);
        $display("  -> Immediate local failure on first trial handled correctly! done=%b, error=%b", m_done, m_error);
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);
        expect_error = 1'b0;

        // --------------------------------------------------------
        // SCN 15: Immediate Failure on First Run (Partner Failure)
        // --------------------------------------------------------
        $display("\n[SCN 15] Immediate Failure on First Run (Partner Failure)");
        reset_system();
        expect_error = 1'b1; // We expect error to trigger
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // Master passes all lanes, but Partner fails all lanes (sends 3'b000)
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'h0000;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // FSM should transition immediately to S6 REPAIR_ERROR in S4 Degrade Verification
        wait (m_error && p_error);
        $display("  -> Immediate partner failure on first trial handled correctly! done=%b, error=%b", m_done, m_error);
        m_enable = 1'b0;
        p_enable = 1'b0;
        repeat(5) @(posedge clk);
        expect_error = 1'b0;

        // --------------------------------------------------------
        // SCN 16: Watchdog Timeout on Second Trial (Retry)
        // --------------------------------------------------------
        $display("\n[SCN 16] Watchdog Timeout on Second Trial (Retry)");
        reset_system();
        expect_error = 1'b1; // We expect error to trigger due to timeout
        m_enable = 1'b1;
        p_enable = 1'b1;

        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        // First run fails upper 8 lanes (degrade to lower x8)
        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'h00FF;
        m_test_d2c_done = 1'b1;
        p_test_d2c_done = 1'b1;
        @(posedge clk);
        m_test_d2c_done = 1'b0;
        p_test_d2c_done = 1'b0;

        // Wait for retry transition back to S2
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! S2 Run 2 for Master. Disable partner to force timeout...");

        // Disable partner so it hangs and doesn't finish retry or send any messages
        p_enable = 1'b0;

        // Master should experience safety watchdog timeout in retry
        wait (m_error);
        $display("  -> Master safety timeout in retry fired successfully! error=%b", m_error);
        m_enable = 1'b0;
        repeat(5) @(posedge clk);
        expect_error = 1'b0;
        repeat(5) @(posedge clk);

        $display("\n==========================================================");
        $display("   ALL 16 TEST SCENARIOS PASSED SUCCESSFULLY!             ");
        $display("==========================================================");
        $finish;
    end
endmodule
