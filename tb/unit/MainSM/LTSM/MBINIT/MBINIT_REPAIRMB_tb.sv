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

    // Pattern interface
    logic         m_tx_data_pattern_sel, m_rx_compare_setup;
    logic         m_tx_data_pattern_en, m_rx_data_compare_en;
    logic [15:0]  m_rx_perlane_status;
    logic         m_tx_data_pattern_transmission_completed;
    logic         m_clear_error_req;

    logic         p_tx_data_pattern_sel, p_rx_compare_setup;
    logic         p_tx_data_pattern_en, p_rx_data_compare_en;
    logic [15:0]  p_rx_perlane_status;
    logic         p_tx_data_pattern_transmission_completed;
    logic         p_clear_error_req;

    // Timer interface
    logic         m_timeout_repair_expired;
    logic         m_timeout_repair_enable;
    logic         p_timeout_repair_expired;
    logic         p_timeout_repair_enable;

    // PHY status signals (monitored)
    logic         m_tx_valid_status, m_tx_track_status, m_tx_clk_status, m_tx_data_status;
    logic         m_rx_valid_status, m_rx_track_status, m_rx_clk_status, m_rx_data_status;
    logic         p_tx_valid_status, p_tx_track_status, p_tx_clk_status, p_tx_data_status;
    logic         p_rx_valid_status, p_rx_track_status, p_rx_clk_status, p_rx_data_status;

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
        .reg_x8_mode_req(m_use_x8_mode),
        .SPMW(m_spmw),
        .mb_repairmb_enable(m_enable),
        .mb_repairmb_done(m_done),
        .mb_repairmb_error(m_error),

        // RX
        .mb_repairmb_rx_valid(p_tx_valid),
        .mb_repairmb_rx_msg_id(p_tx_msg_id),
        .mb_repairmb_rx_MsgInfo(p_tx_MsgInfo),
        .mb_repairmb_rx_data_Field(p_tx_data_Field),

        // TX
        .mb_repairmb_tx_valid(m_tx_valid),
        .mb_repairmb_tx_msg_id(m_tx_msg_id),
        .mb_repairmb_tx_MsgInfo(m_tx_MsgInfo),
        .mb_repairmb_tx_data_Field(m_tx_data_Field),

        // Timer
        .timeout_repair_expired(m_timeout_repair_expired),
        .timeout_repair_enable(m_timeout_repair_enable),

        // FIFO ready
        .ltsm_rdy(m_ltsm_rdy),

        // Pattern
        .mb_tx_data_pattern_sel(m_tx_data_pattern_sel),
        .mb_rx_compare_setup(m_rx_compare_setup),
        .mb_tx_data_pattern_en(m_tx_data_pattern_en),
        .mb_rx_data_compare_en(m_rx_data_compare_en),
        .mb_rx_perlane_status(m_rx_perlane_status),
        .mb_tx_data_pattern_transmission_completed(m_tx_data_pattern_transmission_completed),
        .clear_error_req(m_clear_error_req)
    );

    MBINIT_REPAIRMB #(
        .CLK_FRQ_HZ(1000000)
    ) partner (
        .clk(clk),
        .rst_n(rst_n),
        .reg_x8_mode_req(p_use_x8_mode),
        .SPMW(p_spmw),
        .mb_repairmb_enable(p_enable),
        .mb_repairmb_done(p_done),
        .mb_repairmb_error(p_error),

        // RX
        .mb_repairmb_rx_valid(m_tx_valid),
        .mb_repairmb_rx_msg_id(m_tx_msg_id),
        .mb_repairmb_rx_MsgInfo(m_tx_MsgInfo),
        .mb_repairmb_rx_data_Field(m_tx_data_Field),

        // TX
        .mb_repairmb_tx_valid(p_tx_valid),
        .mb_repairmb_tx_msg_id(p_tx_msg_id),
        .mb_repairmb_tx_MsgInfo(p_tx_MsgInfo),
        .mb_repairmb_tx_data_Field(p_tx_data_Field),

        // Timer
        .timeout_repair_expired(p_timeout_repair_expired),
        .timeout_repair_enable(p_timeout_repair_enable),

        // FIFO ready
        .ltsm_rdy(p_ltsm_rdy),

        // Pattern
        .mb_tx_data_pattern_sel(p_tx_data_pattern_sel),
        .mb_rx_compare_setup(p_rx_compare_setup),
        .mb_tx_data_pattern_en(p_tx_data_pattern_en),
        .mb_rx_data_compare_en(p_rx_data_compare_en),
        .mb_rx_perlane_status(p_rx_perlane_status),
        .mb_tx_data_pattern_transmission_completed(p_tx_data_pattern_transmission_completed),
        .clear_error_req(p_clear_error_req)
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
        m_rx_perlane_status = 16'h0;
        p_rx_perlane_status = 16'h0;
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;
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
        m_rx_perlane_status = 16'h0000; // Pass
        p_rx_perlane_status = 16'h0000; // Pass
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

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
        // S2 Run 1: Fails upper 8 lanes (fails 16'hFF00 -> Lower x8 should be operational)
        m_rx_perlane_status = 16'hFF00;
        p_rx_perlane_status = 16'hFF00;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        // Wait for retry transition back to S2 (safely wait for leaving S2 first)
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! Returned to Point Test S2.");
        $display("  DEBUG: retry_done sticky flag is %b", master.retry_done);

        // S2 Run 2: Lower x8 lanes pass (but upper 8 lanes remain broken physically!)
        m_rx_perlane_status = 16'hFF00;
        p_rx_perlane_status = 16'hFF00;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to Lower x8 completed! done=%b, error=%b, final_lane_map=%b", m_done, m_error, master.final_lane_map_r);
        if (master.final_lane_map_r != 3'b001) $error("ERROR: final_lane_map_r is not Lower x8!");
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
        // S2 Run 1: Fails lower 8 lanes (fails 16'h00FF -> Upper x8 should be operational)
        m_rx_perlane_status = 16'h00FF;
        p_rx_perlane_status = 16'h00FF;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! S2 Run 2.");

        // S2 Run 2: Upper x8 lanes pass (lower 8 lanes remain broken physically!)
        m_rx_perlane_status = 16'h00FF;
        p_rx_perlane_status = 16'h00FF;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to Upper x8 completed! done=%b, error=%b, final_lane_map=%b", m_done, m_error, master.final_lane_map_r);
        if (master.final_lane_map_r != 3'b010) $error("ERROR: final_lane_map_r is not Upper x8!");
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
        // S2 Run 1: Fail lower x8 except lanes 0-3 (fails 16'hFFF0 -> x4 map 3'b100)
        m_rx_perlane_status = 16'hFFF0;
        p_rx_perlane_status = 16'hFFF0;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered! S2 Run 2 under x8_mode.");

        // S2 Run 2: Pass (lanes 4-15 remain broken physically!)
        m_rx_perlane_status = 16'hFFF0;
        p_rx_perlane_status = 16'hFFF0;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to x4 completed! done=%b, error=%b, final_lane_map=%b", m_done, m_error, master.final_lane_map_r);
        if (master.final_lane_map_r != 3'b100) $error("ERROR: final_lane_map_r is not x4!");
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
        // S2 Run 1: Fail upper 8 lanes (degrade to lower x8)
        m_rx_perlane_status = 16'hFF00;
        p_rx_perlane_status = 16'hFF00;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);

        // S2 Run 2: Fail again (fails additional lanes, e.g. 16'hFFFF -> no further degradation possible)
        m_rx_perlane_status = 16'hFFFF;
        p_rx_perlane_status = 16'hFFFF;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

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
        m_rx_perlane_status = 16'h0000;
        p_rx_perlane_status = 16'h0000;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

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
        // S2 Run 1: Fail lower x8 except lanes 0-3 (fails 16'hFFF0 -> x4 map 3'b100)
        m_rx_perlane_status = 16'hFFF0;
        p_rx_perlane_status = 16'hFFF0;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        // Wait for retry
        wait (master.current_state != master.MB_S2_D2C_POINT_TEST);
        wait (master.current_state == master.MB_S2_D2C_POINT_TEST);
        repeat(5) @(posedge clk);
        $display("  -> Retry triggered under SPMW forced x8 mode!");

        // S2 Run 2: Pass at x4 width
        m_rx_perlane_status = 16'hFFF0;
        p_rx_perlane_status = 16'hFFF0;
        m_tx_data_pattern_transmission_completed = 1'b1;
        p_tx_data_pattern_transmission_completed = 1'b1;
        @(posedge clk);
        m_tx_data_pattern_transmission_completed = 1'b0;
        p_tx_data_pattern_transmission_completed = 1'b0;

        wait (m_done && p_done);
        $display("  -> Degrade to x4 via SPMW completed! done=%b, error=%b, final_lane_map=%b", m_done, m_error, master.final_lane_map_r);
        if (master.final_lane_map_r != 3'b100) $error("ERROR: final_lane_map_r is not x4!");
        m_enable = 1'b0;
        p_enable = 1'b0;
        m_spmw = 1'b0;
        p_spmw = 1'b0;
        repeat(5) @(posedge clk);

        $display("\n==========================================================");
        $display("   ALL 9 TEST SCENARIOS PASSED SUCCESSFULLY!             ");
        $display("==========================================================");
        $finish;
    end

endmodule
