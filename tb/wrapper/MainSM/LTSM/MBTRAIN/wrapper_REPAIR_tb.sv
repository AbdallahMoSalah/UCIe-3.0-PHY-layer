`timescale 1ps/1ps
// ============================================================================
// wrapper_REPAIR_tb.sv — Testbench for wrapper_REPAIR (two-die simulation)
//
// TOPOLOGY: Two wrapper_REPAIR instances (DUT = Die A, PTN = Die B) connected
//           through a SB_DELAY-cycle shift-register channel to model cross-die
//           propagation latency.
//
// OWNERSHIP MODEL (matches RTL):
//   - PARTNER FSM is the sole decision-maker for final TX and RX lane masks.
//   - LOCAL FSM manages only the SB handshake + TRAINERROR detection.
//   - The "all-functional" code differs by module type:
//       X16 (rf_ctrl_target_link_width==4'h2): full_width_code = 3'b011
//       X8  (rf_ctrl_target_link_width==4'h1): full_width_code = 3'b001
//
// DECISION TABLE (verified by run_scenario):
//   Case A: remote == full_width_code → TX = our code,    RX = our code
//   Case B: ours   == full_width_code → TX = remote code, RX = remote code
//   Case C: both specific degrade     → TX = our code,    RX = remote code
//   Error:  either == 3'b000         → TRAINERROR
// ============================================================================

module wrapper_REPAIR_tb;

    import UCIe_pkg::*;

    parameter LCLK_PERIOD    = 1*1000;  // 1 ns in ps
    parameter SB_DELAY       = 20;      // SB propagation delay (cycles)
    parameter TIMEOUT_CYCLES = 1000;    // Watchdog guard

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    logic lclk = 0;
    logic rst_n = 0;

    always #(LCLK_PERIOD/2) lclk = ~lclk;

    task automatic assert_reset();
        rst_n = 0;
        #(LCLK_PERIOD * 5);
        rst_n = 1;
        #(LCLK_PERIOD * 5);
    endtask

    // =========================================================================
    // TB Interfaces
    // =========================================================================
    ltsm_tb_if dut_if (lclk, rst_n);
    ltsm_tb_if ptn_if (lclk, rst_n);

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES  (TIMEOUT_CYCLES),
        .ENABLE_LOOPBACK (1'b0)
    ) dut_attach (.intf(dut_if));

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES  (TIMEOUT_CYCLES),
        .ENABLE_LOOPBACK (1'b0)
    ) ptn_attach (.intf(ptn_if));

    // =========================================================================
    // SB Delay Queue  (Die A <-> Die B with SB_DELAY cycle latency)
    // =========================================================================
    reg [SB_DELAY-1:0] dut2ptn_valid_sr = 0;
    reg [7:0]  dut2ptn_msg_sr  [0:SB_DELAY-1];
    reg [15:0] dut2ptn_info_sr [0:SB_DELAY-1];
    reg [63:0] dut2ptn_data_sr [0:SB_DELAY-1];

    reg [SB_DELAY-1:0] ptn2dut_valid_sr = 0;
    reg [7:0]  ptn2dut_msg_sr  [0:SB_DELAY-1];
    reg [15:0] ptn2dut_info_sr [0:SB_DELAY-1];
    reg [63:0] ptn2dut_data_sr [0:SB_DELAY-1];

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            dut2ptn_valid_sr <= 0;
            ptn2dut_valid_sr <= 0;
            for (pi = 0; pi < SB_DELAY; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= 0;
                dut2ptn_info_sr[pi] <= 0;
                dut2ptn_data_sr[pi] <= 0;
                ptn2dut_msg_sr[pi]  <= 0;
                ptn2dut_info_sr[pi] <= 0;
                ptn2dut_data_sr[pi] <= 0;
            end
        end else begin
            // Shift queues
            dut2ptn_valid_sr <= {dut2ptn_valid_sr[SB_DELAY-2:0], dut_if.tb_muxed_tx_sb_msg_valid};
            ptn2dut_valid_sr <= {ptn2dut_valid_sr[SB_DELAY-2:0], ptn_if.tb_muxed_tx_sb_msg_valid};

            for (pi = 1; pi < SB_DELAY; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= dut2ptn_msg_sr[pi-1];
                dut2ptn_info_sr[pi] <= dut2ptn_info_sr[pi-1];
                dut2ptn_data_sr[pi] <= dut2ptn_data_sr[pi-1];
                ptn2dut_msg_sr[pi]  <= ptn2dut_msg_sr[pi-1];
                ptn2dut_info_sr[pi] <= ptn2dut_info_sr[pi-1];
                ptn2dut_data_sr[pi] <= ptn2dut_data_sr[pi-1];
            end

            dut2ptn_msg_sr[0]  <= dut_if.tb_muxed_tx_sb_msg;
            dut2ptn_info_sr[0] <= dut_if.tb_muxed_tx_msginfo;
            dut2ptn_data_sr[0] <= dut_if.tb_muxed_tx_data_field;
            ptn2dut_msg_sr[0]  <= ptn_if.tb_muxed_tx_sb_msg;
            ptn2dut_info_sr[0] <= ptn_if.tb_muxed_tx_msginfo;
            ptn2dut_data_sr[0] <= ptn_if.tb_muxed_tx_data_field;
        end
    end

    // Cross-connections
    assign ptn_if.rx_sb_msg_valid = dut2ptn_valid_sr[SB_DELAY-1] & ~ptn_if.tb_suppress_rx_sb;
    assign ptn_if.rx_sb_msg       = dut2ptn_msg_sr  [SB_DELAY-1];
    assign ptn_if.rx_msginfo      = dut2ptn_info_sr [SB_DELAY-1];
    assign ptn_if.rx_data_field   = dut2ptn_data_sr [SB_DELAY-1];

    assign dut_if.rx_sb_msg_valid = ptn2dut_valid_sr[SB_DELAY-1] & ~dut_if.tb_suppress_rx_sb;
    assign dut_if.rx_sb_msg       = ptn2dut_msg_sr  [SB_DELAY-1];
    assign dut_if.rx_msginfo      = ptn2dut_info_sr [SB_DELAY-1];
    assign dut_if.rx_data_field   = ptn2dut_data_sr [SB_DELAY-1];

    // =========================================================================
    // Shared configuration signals (same for both DUT and PTN in tests below)
    // =========================================================================
    logic        soft_rst_n = 1;
    logic [2:0]  mbinit_rx_data_lane_mask = 3'b000;
    logic [2:0]  mbinit_tx_data_lane_mask = 3'b000;
    ltsm_state_n_pkg::state_n_e dut_state_n_0 = ltsm_state_n_pkg::LOG_MBTRAIN_VALVREF;
    ltsm_state_n_pkg::state_n_e ptn_state_n_0 = ltsm_state_n_pkg::LOG_MBTRAIN_VALVREF;

    // unit_negotiated_lanes inputs (drive to control what degraded_tx_lane_map_code is)
    logic [15:0] dut_success_tx_lanes     = 16'h00FF;
    // logic [2:0]  dut_success_rx_enc       = 3'b001;
    logic        dut_rf_cap_SPMW          = 1'b0;
    logic [3:0]  dut_rf_ctrl_link_width   = 4'h2;
    logic        dut_param_UCIe_S_x8      = 1'b0;

    logic [15:0] ptn_success_tx_lanes     = 16'h00FF;
    // logic [2:0]  ptn_success_rx_enc       = 3'b001;
    logic        ptn_rf_cap_SPMW          = 1'b0;
    logic [3:0]  ptn_rf_ctrl_link_width   = 4'h2;
    logic        ptn_param_UCIe_S_x8      = 1'b0;

    // =========================================================================
    // DUT (Die A) instance
    // =========================================================================
    logic        dut_repair_en            = 0;
    logic        dut_repair_done;
    // logic        dut_local_txselfcal_req;
    // logic        dut_partner_txselfcal_req;
    logic        dut_trainerror_req;
    logic [2:0]  dut_mb_tx_data_lane_mask;
    logic [2:0]  dut_mb_rx_data_lane_mask;

    wrapper_REPAIR u_dut (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .soft_rst_n                 (soft_rst_n),
        .repair_en                  (dut_repair_en),
        .repair_done                (dut_repair_done),
        // .local_txselfcal_req        (dut_local_txselfcal_req),
        // .partner_txselfcal_req      (dut_partner_txselfcal_req),
        .trainerror_req             (dut_trainerror_req),
        .success_tx_lanes           (dut_success_tx_lanes),
        // .success_rx_lanes_encoding  (dut_success_rx_enc),
        .rf_cap_SPMW                (dut_rf_cap_SPMW),
        .rf_ctrl_target_link_width  (dut_rf_ctrl_link_width),
        .param_UCIe_S_x8            (dut_param_UCIe_S_x8),
        .mb_tx_data_lane_mask       (dut_mb_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (dut_mb_rx_data_lane_mask),
        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .state_n_0                  (dut_state_n_0),
        .tx_sb_msg_valid            (dut_if.tx_sb_msg_valid),
        .tx_sb_msg                  (dut_if.tx_sb_msg),
        .tx_msginfo                 (dut_if.tx_msginfo),
        .tx_data_field              (dut_if.tx_data_field),
        .rx_sb_msg_valid            (dut_if.rx_sb_msg_valid),
        .rx_sb_msg                  (dut_if.rx_sb_msg),
        .rx_msginfo                 (dut_if.rx_msginfo)
        // .rx_data_field              (dut_if.rx_data_field)
    );

    // =========================================================================
    // PTN (Die B) instance
    // =========================================================================
    logic        ptn_repair_en            = 0;
    logic        ptn_repair_done;
    // logic        ptn_local_txselfcal_req;
    // logic        ptn_partner_txselfcal_req;
    logic        ptn_trainerror_req;
    logic [2:0]  ptn_mb_tx_data_lane_mask;
    logic [2:0]  ptn_mb_rx_data_lane_mask;

    wrapper_REPAIR u_ptn (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .soft_rst_n                 (soft_rst_n),
        .repair_en                  (ptn_repair_en),
        .repair_done                (ptn_repair_done),
        // .local_txselfcal_req        (ptn_local_txselfcal_req),
        // .partner_txselfcal_req      (ptn_partner_txselfcal_req),
        .trainerror_req             (ptn_trainerror_req),
        .success_tx_lanes           (ptn_success_tx_lanes),
        // .success_rx_lanes_encoding  (ptn_success_rx_enc),
        .rf_cap_SPMW                (ptn_rf_cap_SPMW),
        .rf_ctrl_target_link_width  (ptn_rf_ctrl_link_width),
        .param_UCIe_S_x8            (ptn_param_UCIe_S_x8),
        .mb_tx_data_lane_mask       (ptn_mb_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (ptn_mb_rx_data_lane_mask),
        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .state_n_0                  (ptn_state_n_0),
        .tx_sb_msg_valid            (ptn_if.tx_sb_msg_valid),
        .tx_sb_msg                  (ptn_if.tx_sb_msg),
        .tx_msginfo                 (ptn_if.tx_msginfo),
        .tx_data_field              (ptn_if.tx_data_field),
        .rx_sb_msg_valid            (ptn_if.rx_sb_msg_valid),
        .rx_sb_msg                  (ptn_if.rx_sb_msg),
        .rx_msginfo                 (ptn_if.rx_msginfo)
        // .rx_data_field              (ptn_if.rx_data_field)
    );

    assign dut_if.timeout_timer_en = dut_repair_en;
    assign ptn_if.timeout_timer_en = ptn_repair_en;

    // =========================================================================
    // Test infrastructure
    // =========================================================================
    integer test_no      = 1;
    integer success_count = 0;
    integer fail_count   = 0;

    task automatic pass_test(input string name);
        $display("[PASS] T%0d: %s", test_no, name);
        success_count++;
        test_no++;
    endtask

    task automatic fail_test(input string name, input string reason);
        $display("[FAIL] T%0d: %s -- %s", test_no, name, reason);
        fail_count++;
        test_no++;
        $stop;
    endtask

    // =========================================================================
    // run_scenario — drives a full two-die handshake and verifies lane masks.
    // =========================================================================
    task automatic run_scenario(
            input string   name,
            input logic [15:0] dut_tx_l,
            // input logic [2:0]  dut_rx_e,
            input logic [15:0] ptn_tx_l,
            // input logic [2:0]  ptn_rx_e,
            input logic [3:0]  link_w,
            input logic        expect_err,
            input logic [2:0]  exp_dut_tx,
            input logic [2:0]  exp_dut_rx,
            input logic [2:0]  exp_ptn_tx,
            input logic [2:0]  exp_ptn_rx
        );

        assert_reset();

        dut_success_tx_lanes   = dut_tx_l;
        // dut_success_rx_enc     = dut_rx_e;
        dut_rf_ctrl_link_width = link_w;
        dut_rf_cap_SPMW        = 1'b0;
        dut_param_UCIe_S_x8    = 1'b0;

        ptn_success_tx_lanes   = ptn_tx_l;
        // ptn_success_rx_enc     = ptn_rx_e;
        ptn_rf_ctrl_link_width = link_w;
        ptn_rf_cap_SPMW        = 1'b0;
        ptn_param_UCIe_S_x8    = 1'b0;

        dut_repair_en         = 1;
        ptn_repair_en         = 1;

        fork
            begin
                if (expect_err) begin
                    wait(dut_trainerror_req || ptn_trainerror_req);
                end else begin
                    wait(dut_repair_done && ptn_repair_done);
                end
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
                $display("# ERROR [%s]: Simulation timeout guard fired!", name);
                $stop;
            end
        join_any
        disable fork;

        if (!expect_err) begin
            if (dut_mb_tx_data_lane_mask !== exp_dut_tx) begin
                $display("# FAIL [%s]: DUT TX mask got 3'b%03b, expected 3'b%03b",
                    name, dut_mb_tx_data_lane_mask, exp_dut_tx);
                fail_test(name, "DUT TX mask mismatch"); return;
            end
            if (dut_mb_rx_data_lane_mask !== exp_dut_rx) begin
                $display("# FAIL [%s]: DUT RX mask got 3'b%03b, expected 3'b%03b",
                    name, dut_mb_rx_data_lane_mask, exp_dut_rx);
                fail_test(name, "DUT RX mask mismatch"); return;
            end
            if (ptn_mb_tx_data_lane_mask !== exp_ptn_tx) begin
                $display("# FAIL [%s]: PTN TX mask got 3'b%03b, expected 3'b%03b",
                    name, ptn_mb_tx_data_lane_mask, exp_ptn_tx);
                fail_test(name, "PTN TX mask mismatch"); return;
            end
            if (ptn_mb_rx_data_lane_mask !== exp_ptn_rx) begin
                $display("# FAIL [%s]: PTN RX mask got 3'b%03b, expected 3'b%03b",
                    name, ptn_mb_rx_data_lane_mask, exp_ptn_rx);
                fail_test(name, "PTN RX mask mismatch"); return;
            end
        end

        dut_repair_en         = 0;
        ptn_repair_en         = 0;
        #(LCLK_PERIOD * 10);
        pass_test(name);
    endtask

    // =========================================================================
    // Test Scenarios
    // =========================================================================
    initial begin
        dut_if.tb_suppress_rx_sb = 0;
        ptn_if.tb_suppress_rx_sb = 0;

        $display("# =============================================================");
        $display("# Running wrapper_REPAIR_tb                                    ");
        $display("# =============================================================");

        // ------------------------------------------------------------------
        // X16 MODULE TESTS (rf_ctrl_target_link_width = 4'h2)
        //   full_width_code = 3'b011
        // ------------------------------------------------------------------

        // T1: Case A (X16) — remote all functional (3'b011), DUT x8-low degrade
        run_scenario(
            "T1 [X16] Case A: remote all-ok, DUT x8-low degrade",
            16'h00FF,           // DUT: low 8 TX ok
            16'hFFFF,           // PTN: all 16 TX ok
            4'h2, 0,
            3'b001, 3'b001,     // DUT: TX=3'b001, RX=3'b001
            3'b001, 3'b001      // PTN: TX=3'b001, RX=3'b001 (adopted DUT's code)
        );

        // T2: Case A (X16) — remote all functional, DUT x8-high degrade
        run_scenario(
            "T2 [X16] Case A: remote all-ok, DUT x8-high degrade",
            16'hFF00,           // DUT: high 8 TX ok
            16'hFFFF,           // PTN: all 16 TX ok
            4'h2, 0,
            3'b010, 3'b010,
            3'b010, 3'b010
        );

        // T3: Case B (X16) — DUT all functional, PTN x8-low degrade
        run_scenario(
            "T3 [X16] Case B: DUT all-ok, remote x8-low degrade",
            16'hFFFF,           // DUT: all 16 ok
            16'h00FF,           // PTN: low 8 ok
            4'h2, 0,
            3'b001, 3'b001,
            3'b001, 3'b001
        );

        // T4: Case C (X16) — DUT x8-low, PTN x8-high (independent halves)
        run_scenario(
            "T4 [X16] Case C: DUT x8-low, PTN x8-high (independent halves)",
            16'h00FF,           // DUT: low 8
            16'hFF00,           // PTN: high 8
            4'h2, 0,
            3'b001, 3'b010,     // DUT: TX=3'b001 (ours), RX=3'b010 (PTN's TX)
            3'b010, 3'b001      // PTN: TX=3'b010 (ours), RX=3'b001 (DUT's TX)
        );

        // T5: TRAINERROR (X16) — DUT cannot degrade
        run_scenario(
            "T5 [X16] TRAINERROR: DUT degrade not possible",
            16'h0000,
            16'h00FF,
            4'h2, 1,
            3'b0, 3'b0, 3'b0, 3'b0
        );

        // T6: TRAINERROR (X16) — PTN cannot degrade
        run_scenario(
            "T6 [X16] TRAINERROR: PTN degrade not possible",
            16'h00FF,
            16'h0000,
            4'h2, 1,
            3'b0, 3'b0, 3'b0, 3'b0
        );

        // T7: Both X16 full-width symmetric
        run_scenario(
            "T7 [X16] Both full-width: symmetric x16",
            16'hFFFF,
            16'hFFFF,
            4'h2, 0,
            3'b011, 3'b011,
            3'b011, 3'b011
        );

        // ------------------------------------------------------------------
        // X8 MODULE TESTS (rf_ctrl_target_link_width = 4'h1)
        //   full_width_code = 3'b001
        // ------------------------------------------------------------------

        // T8: Case A (X8) — PTN all functional (3'b001), DUT x4-low degrade
        run_scenario(
            "T8 [X8] Case A: remote all-ok, DUT x4-low degrade",
            16'h000F,           // DUT: low 4 TX ok
            16'h00FF,           // PTN: all 8 TX ok
            4'h1, 0,
            3'b100, 3'b100,
            3'b100, 3'b100
        );

        // T9: Case A (X8) — PTN all functional, DUT x4-high degrade
        run_scenario(
            "T9 [X8] Case A: remote all-ok, DUT x4-high degrade",
            16'h00F0,           // DUT: high 4 TX ok
            16'h00FF,           // PTN: all 8 ok
            4'h1, 0,
            3'b101, 3'b101,
            3'b101, 3'b101
        );

        // T10: Case B (X8) — DUT all functional, PTN x4-low degrade
        run_scenario(
            "T10 [X8] Case B: DUT all-ok, PTN x4-low degrade",
            16'h00FF,           // DUT: all 8 ok
            16'h000F,           // PTN: low 4 ok
            4'h1, 0,
            3'b100, 3'b100,
            3'b100, 3'b100
        );

        // T11: Case C (X8) — DUT x4-low, PTN x4-high (independent quarters)
        run_scenario(
            "T11 [X8] Case C: DUT x4-low, PTN x4-high (independent quarters)",
            16'h000F,           // DUT: low 4 TX ok
            16'h00F0,           // PTN: high 4 TX ok
            4'h1, 0,
            3'b100, 3'b101,     // DUT: TX=3'b100, RX=3'b101
            3'b101, 3'b100      // PTN: TX=3'b101, RX=3'b100
        );

        // T12: TRAINERROR (X8) — DUT degrade not possible
        run_scenario(
            "T12 [X8] TRAINERROR: DUT degrade not possible",
            16'h0000,
            16'h00FF,
            4'h1, 1,
            3'b0, 3'b0, 3'b0, 3'b0
        );

        // T13: Symmetric X8 both full-width
        run_scenario(
            "T13 [X8] Both full-width: symmetric x8",
            16'h00FF,
            16'h00FF,
            4'h1, 0,
            3'b001, 3'b001,
            3'b001, 3'b001
        );

        // ------------------------------------------------------------------
        // WATCHDOG TIMEOUT TEST (Commented out per updated specifications)
        // ------------------------------------------------------------------
        // begin : watchdog_test
        //     assert_reset();
        //     dut_success_tx_lanes   = 16'h00FF;
        //     // dut_success_rx_enc     = 3'b001;
        //     dut_rf_ctrl_link_width = 4'h2;
        //     dut_repair_en          = 1;
        //     ptn_if.tb_suppress_rx_sb = 1;
        //
        //     fork
        //         begin
        //             wait(dut_if.timeout_8ms_occured == 1);
        //             force dut_if.rx_sb_msg_valid = 1;
        //             force dut_if.rx_sb_msg = TRAINERROR_Entry_req;
        //             force dut_if.rx_msginfo = 16'h0;
        //             @(posedge lclk);
        //             release dut_if.rx_sb_msg_valid;
        //             release dut_if.rx_sb_msg;
        //             release dut_if.rx_msginfo;
        //         end
        //         begin
        //             wait(dut_trainerror_req);
        //             #(LCLK_PERIOD * 5);
        //         end
        //         begin
        //             #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
        //             $display("# ERROR [Watchdog]: Timeout guard fired!");
        //             $stop;
        //         end
        //     join_any
        //     disable fork;
        //
        //     ptn_if.tb_suppress_rx_sb = 0;
        //     dut_repair_en = 0;
        //     pass_test("T14: Watchdog Timeout triggers TRAINERROR");
        // end

        // ------------------------------------------------------------------
        // SUMMARY
        // ------------------------------------------------------------------
        $display("# =============================================================");
        $display("# wrapper_REPAIR_tb DONE: %0d PASSED, %0d FAILED", success_count, fail_count);
        $display("# =============================================================");
        if (fail_count == 0) begin
            $display("# ALL TESTS PASSED");
            $display("MBTRAIN_TB_RESULT: SUCCESS");
        end else begin
            $display("MBTRAIN_TB_RESULT: FAILURE");
        end
        $finish;
    end

endmodule
