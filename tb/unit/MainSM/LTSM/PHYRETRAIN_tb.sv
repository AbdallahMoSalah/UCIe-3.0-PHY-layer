// Testbench for rtl/MainSM/LTSM/PHYRETRAIN.sv against UCIe 3.0 §4.5.3.7 and
// Table 4-12 retrain-encoding resolution.
//
// Inline partner stub drives the DUT's RX with configurable timing and
// encoding.  SB FIFO is modeled as a single ltsm_rdy line driven by the TB;
// default high, can be pulled low to test back-pressure.
//
// Local encoding derives from registers (mirrors DUT's always_comb — Table 4-10):
//   rt_link_busy_status=0                         → TXSELFCAL (001)
//   rt_link_busy_status=1, ctrl[0]=0              → TXSELFCAL (001)
//   rt_link_busy_status=1, ctrl[0]=1, mask!=0     → REPAIR    (100)
//   rt_link_busy_status=1, ctrl[0]=1, mask==0     → SPEEDIDLE (010)  ← unrepairable path
// Scenario 1.9 exercises the new SPEEDIDLE-via-unrepairable path.

`timescale 1ns/1ps

module PHYRETRAIN_tb;
    import UCIe_pkg::*;

    localparam real CLK_PERIOD = 10.0;

    // Encoding constants (Table 4-11)
    localparam logic [2:0] ENC_TXSELFCAL = 3'b001;
    localparam logic [2:0] ENC_SPEEDIDLE = 3'b010;
    localparam logic [2:0] ENC_REPAIR    = 3'b100;

    // ---------------- DUT ports ----------------
    logic        clk;
    logic        rst_n;
    logic        phyretrain_enable;
    logic        phyretrain_done;
    logic        phyretrain_error;
    logic [63:0] rt_test_ctrl;
    logic        rt_link_busy_status;
    logic [2:0]  mbinit_tx_data_lane_mask;
    logic        global_error;
    logic [2:0]  resolved_retrain_enc;

    logic        tx_sb_msg_valid;
    msg_no_e     tx_sb_msg;
    logic [15:0] tx_msginfo;
    logic        ltsm_rdy;

    logic        rx_sb_msg_valid;
    msg_no_e     rx_sb_msg;
    logic [15:0] rx_msginfo;

    PHYRETRAIN dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .phyretrain_enable    (phyretrain_enable),
        .phyretrain_done      (phyretrain_done),
        .phyretrain_error     (phyretrain_error),
        .rt_test_ctrl              (rt_test_ctrl),
        .rt_link_busy_status       (rt_link_busy_status),
        .mbinit_tx_data_lane_mask  (mbinit_tx_data_lane_mask),
        .global_error              (global_error),
        .resolved_retrain_enc (resolved_retrain_enc),
        .tx_sb_msg_valid      (tx_sb_msg_valid),
        .tx_sb_msg            (tx_sb_msg),
        .tx_msginfo           (tx_msginfo),
        .ltsm_rdy             (ltsm_rdy),
        .rx_sb_msg_valid      (rx_sb_msg_valid),
        .rx_sb_msg            (rx_sb_msg),
        .rx_msginfo           (rx_msginfo)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    int errors = 0;
    task automatic check(input bit cond, input string msg);
        if (!cond) begin $error("[%0t] FAIL: %s", $time, msg); errors++; end
        else        $display("[%0t] PASS: %s", $time, msg);
    endtask

    function automatic string enc_name(input logic [2:0] e);
        case (e)
            ENC_TXSELFCAL: return "TXSELFCAL";
            ENC_SPEEDIDLE: return "SPEEDIDLE";
            ENC_REPAIR   : return "REPAIR";
            default      : return $sformatf("?%b", e);
        endcase
    endfunction

    function automatic logic [2:0] expected_resolved(input logic [2:0] a, input logic [2:0] b);
        if      (a == ENC_SPEEDIDLE || b == ENC_SPEEDIDLE) return ENC_SPEEDIDLE;
        else if (a == ENC_REPAIR    || b == ENC_REPAIR   ) return ENC_REPAIR;
        else                                                return ENC_TXSELFCAL;
    endfunction

    // Mirrors DUT's always_comb for local encoding (Table 4-10 / 4-11)
    // repairable = width can be degraded one more step: only x16 (011) and
    // lower-x8 (001). 010/100/101/000 are unrepairable.
    function automatic logic [2:0] local_enc_from_regs(
        input logic       rt_busy,
        input logic       apply_repair,
        input logic [2:0] mbinit_mask
    );
        if (!rt_busy || !apply_repair)        return ENC_TXSELFCAL;
        else if (mbinit_mask == 3'b011 ||
                 mbinit_mask == 3'b001)       return ENC_REPAIR;
        else                                  return ENC_SPEEDIDLE;
    endfunction

    // ---------------- Always-on TX observers ----------------
    // Reset per scenario via rst_n=0 in do_async_reset().
    logic       saw_tx_req;
    logic       saw_tx_rsp;
    logic [2:0] last_tx_req_enc;
    logic [2:0] last_tx_rsp_enc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_tx_req      <= 1'b0;
            saw_tx_rsp      <= 1'b0;
            last_tx_req_enc <= 3'b000;
            last_tx_rsp_enc <= 3'b000;
        end else if (tx_sb_msg_valid && ltsm_rdy) begin
            if (tx_sb_msg == PHYRETRAIN_retrain_start_req) begin
                saw_tx_req      <= 1'b1;
                last_tx_req_enc <= tx_msginfo[2:0];
            end
            if (tx_sb_msg == PHYRETRAIN_retrain_start_resp) begin
                saw_tx_rsp      <= 1'b1;
                last_tx_rsp_enc <= tx_msginfo[2:0];
            end
        end
    end

    // ---------------- Inline partner ----------------
    task automatic init_rx();
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
        rx_msginfo      = 16'h0000;
    endtask

    task automatic send_partner_req(input logic [2:0] enc);
        @(negedge clk);
        rx_sb_msg       = PHYRETRAIN_retrain_start_req;
        rx_msginfo      = {13'd0, enc};
        rx_sb_msg_valid = 1'b1;
        @(negedge clk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
        rx_msginfo      = 16'h0000;
    endtask

    task automatic send_partner_rsp(input logic [2:0] enc);
        @(negedge clk);
        rx_sb_msg       = PHYRETRAIN_retrain_start_resp;
        rx_msginfo      = {13'd0, enc};
        rx_sb_msg_valid = 1'b1;
        @(negedge clk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
        rx_msginfo      = 16'h0000;
    endtask

    task automatic do_async_reset();
        rst_n                    = 1'b0;
        phyretrain_enable        = 1'b0;
        rt_link_busy_status      = 1'b0;
        rt_test_ctrl             = 64'h0;
        mbinit_tx_data_lane_mask = 3'b001;  // default: repair resources available
        global_error             = 1'b0;
        ltsm_rdy            = 1'b1;
        init_rx();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---------------- One full handshake helper ----------------
    // rt_busy / apply_repair set the registers that compute local encoding.
    // local_enc_from_regs() mirrors DUT's combinational logic for golden checks.
    task automatic run_handshake(
        input logic       rt_busy,
        input logic       apply_repair,
        input logic [2:0] mbinit_mask,
        input logic [2:0] partner_enc,
        input string      label
    );
        logic [2:0] local_enc, expect_resolved;
        local_enc       = local_enc_from_regs(rt_busy, apply_repair, mbinit_mask);
        expect_resolved = expected_resolved(local_enc, partner_enc);

        do_async_reset();
        rt_link_busy_status      = rt_busy;
        rt_test_ctrl             = apply_repair ? 64'h1 : 64'h0;
        mbinit_tx_data_lane_mask = mbinit_mask;
        @(negedge clk) phyretrain_enable = 1'b1;

        repeat (2) @(posedge clk);
        send_partner_req(partner_enc);
        repeat (3) @(posedge clk);
        send_partner_rsp(expect_resolved);

        fork
            begin wait (phyretrain_done === 1'b1); end
            begin
                repeat (50) @(posedge clk);
                $error("[%s] timeout waiting for done", label);
                errors++;
            end
        join_any
        disable fork;

        check(phyretrain_done      === 1'b1,            $sformatf("%s: done asserted", label));
        check(resolved_retrain_enc === expect_resolved,
              $sformatf("%s: resolved enc = %s (expected %s) for local=%s partner=%s",
                        label, enc_name(resolved_retrain_enc), enc_name(expect_resolved),
                        enc_name(local_enc), enc_name(partner_enc)));
        check(saw_tx_req           === 1'b1,            $sformatf("%s: DUT sent req", label));
        check(last_tx_req_enc      === local_enc,       $sformatf("%s: req msginfo=%s", label, enc_name(last_tx_req_enc)));
        check(saw_tx_rsp           === 1'b1,            $sformatf("%s: DUT sent rsp", label));
        check(last_tx_rsp_enc      === expect_resolved, $sformatf("%s: rsp msginfo=%s", label, enc_name(last_tx_rsp_enc)));

        @(negedge clk) phyretrain_enable = 1'b0;
        @(posedge clk);
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== PHYRETRAIN_tb start ====");
        do_async_reset();
        check(phyretrain_done === 1'b0, "after rst_n: done low");

        // ---- Scenario 1: Table 4-12 — encoding resolution coverage ----
        // 1.0-1.2: busy=0          → TXSELFCAL
        // 1.3-1.5: busy=1,apply=1  → REPAIR
        // 1.6-1.8: busy=1,apply=0  → TXSELFCAL (third register path, same encoding)
        $display("\n-- Scenario 1: Table 4-12 resolution coverage --");
        run_handshake(0, 0, 3'b001, ENC_TXSELFCAL, "1.0: busy=0 -> 001 vs 001 -> 001");
        run_handshake(0, 0, 3'b001, ENC_REPAIR   , "1.1: busy=0 -> 001 vs 100 -> 100");
        run_handshake(0, 0, 3'b001, ENC_SPEEDIDLE, "1.2: busy=0 -> 001 vs 010 -> 010");
        run_handshake(1, 1, 3'b001, ENC_TXSELFCAL, "1.3: busy=1,apply=1,x8(001) repairable -> 100 vs 001 -> 100");
        run_handshake(1, 1, 3'b001, ENC_REPAIR   , "1.4: busy=1,apply=1,x8(001) repairable -> 100 vs 100 -> 100");
        run_handshake(1, 1, 3'b001, ENC_SPEEDIDLE, "1.5: busy=1,apply=1,x8(001) repairable -> 100 vs 010 -> 010");
        run_handshake(1, 0, 3'b001, ENC_TXSELFCAL, "1.6: busy=1,apply=0 -> 001 vs 001 -> 001");
        run_handshake(1, 0, 3'b001, ENC_REPAIR   , "1.7: busy=1,apply=0 -> 001 vs 100 -> 100");
        run_handshake(1, 0, 3'b001, ENC_SPEEDIDLE, "1.8: busy=1,apply=0 -> 001 vs 010 -> 010");
        // Repairability decode (Table 4-9): 011/001 repairable; 010/100/101/000 not.
        run_handshake(1, 1, 3'b011, ENC_TXSELFCAL, "1.9:  busy=1,apply=1,x16(011) repairable -> 100 vs 001 -> 100");
        run_handshake(1, 1, 3'b000, ENC_TXSELFCAL, "1.10: busy=1,apply=1,none(000) unrepairable -> 010 vs 001 -> 010");
        run_handshake(1, 1, 3'b010, ENC_TXSELFCAL, "1.11: busy=1,apply=1,x8-upper(010) unrepairable -> 010 vs 001 -> 010");
        run_handshake(1, 1, 3'b100, ENC_TXSELFCAL, "1.12: busy=1,apply=1,x4(100) unrepairable -> 010 vs 001 -> 010");
        run_handshake(1, 1, 3'b101, ENC_TXSELFCAL, "1.13: busy=1,apply=1,x4(101) unrepairable -> 010 vs 001 -> 010");

        // ---- Scenario 2: partner req arrives BEFORE DUT's req sent (sticky test) ----
        $display("\n-- Scenario 2: partner req-first (req sticky) --");
        do_async_reset();
        rt_link_busy_status = 1'b1;
        rt_test_ctrl        = 64'h1;        // REPAIR: busy=1, apply_repair=1
        ltsm_rdy = 1'b0;
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (2) @(posedge clk);
        // partner sends req while our req is still blocked by backpressure
        send_partner_req(ENC_SPEEDIDLE);    // partner SPEEDIDLE → resolved = SPEEDIDLE
        repeat (5) @(posedge clk);
        check(phyretrain_done === 1'b0, "2: still no done while our req unsent");
        // release back-pressure; DUT's req and rsp should both go out
        @(negedge clk) ltsm_rdy = 1'b1;
        repeat (5) @(posedge clk);
        send_partner_rsp(ENC_SPEEDIDLE);
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "2: done asserts after both sent + both received");
        check(resolved_retrain_enc === ENC_SPEEDIDLE, "2: resolved = SPEEDIDLE (local REPAIR vs partner SPEEDIDLE)");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 3: partner rsp delayed (arrives well after DUT reaches RSP_WAIT) ----
        $display("\n-- Scenario 3: delayed partner rsp --");
        do_async_reset();
        rt_link_busy_status = 1'b0;         // TXSELFCAL
        rt_test_ctrl        = 64'h0;
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_req(ENC_TXSELFCAL);
        // DUT will send rsp and reach RSP_WAIT; partner rsp arrives late
        repeat (10) @(posedge clk);
        send_partner_rsp(ENC_TXSELFCAL);
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "3: done asserts with delayed partner rsp");
        check(resolved_retrain_enc === ENC_TXSELFCAL, "3: resolved = TXSELFCAL");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 4: ltsm_rdy backpressure delays our req for many cycles ----
        $display("\n-- Scenario 4: long backpressure --");
        do_async_reset();
        rt_link_busy_status = 1'b1;
        rt_test_ctrl        = 64'h1;        // REPAIR
        ltsm_rdy = 1'b0;
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (40) @(posedge clk);
        check(phyretrain_done === 1'b0, "4: backpressure: no done");
        check(tx_sb_msg_valid && tx_sb_msg == PHYRETRAIN_retrain_start_req,
              "4: req msg held high under backpressure");
        @(negedge clk) ltsm_rdy = 1'b1;
        send_partner_req(ENC_TXSELFCAL);
        repeat (3) @(posedge clk);
        send_partner_rsp(ENC_REPAIR);
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "4: done asserts after release");
        check(resolved_retrain_enc === ENC_REPAIR, "4: resolved = REPAIR");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 5: done held until enable drops ----
        $display("\n-- Scenario 5: done held until enable drops --");
        run_handshake(0, 0, 3'b001, ENC_TXSELFCAL, "5.setup");
        do_async_reset();
        rt_link_busy_status = 1'b0;
        rt_test_ctrl        = 64'h0;
        @(negedge clk) phyretrain_enable = 1'b1;
        fork
            begin send_partner_req(ENC_TXSELFCAL); end
            begin repeat (4) @(posedge clk); send_partner_rsp(ENC_TXSELFCAL); end
        join
        wait (phyretrain_done === 1'b1);
        repeat (50) @(posedge clk);
        check(phyretrain_done === 1'b1, "5: done remains high in PR_DONE");
        @(negedge clk) phyretrain_enable = 1'b0;
        @(posedge clk); #1;
        check(phyretrain_done === 1'b0, "5: done drops after enable=0");

        // ---- Scenario 6: re-entry restarts handshake ----
        $display("\n-- Scenario 6: re-entry --");
        run_handshake(1, 1, 3'b001, ENC_SPEEDIDLE, "6.run1: REPAIR vs SPEEDIDLE -> SPEEDIDLE");
        run_handshake(1, 1, 3'b001, ENC_TXSELFCAL, "6.run2: REPAIR vs TXSELFCAL -> REPAIR");

        // ---- Scenario 7: async rst_n ----
        $display("\n-- Scenario 7: async rst_n --");
        do_async_reset();
        rt_link_busy_status = 1'b0;
        rt_test_ctrl        = 64'h0;
        @(negedge clk) phyretrain_enable = 1'b1;
        fork
            begin send_partner_req(ENC_TXSELFCAL); end
            begin repeat (4) @(posedge clk); send_partner_rsp(ENC_TXSELFCAL); end
        join
        wait (phyretrain_done === 1'b1);
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(phyretrain_done === 1'b0, "7: async rst_n -> done deasserts");
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Scenario 8: partner rsp carries wrong resolved encoding → phyretrain_error ----
        $display("\n-- Scenario 8: rsp encoding mismatch -> PR_ERROR --");
        do_async_reset();
        rt_link_busy_status = 1'b1;
        rt_test_ctrl        = 64'h1;        // local = REPAIR
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_req(ENC_TXSELFCAL);    // resolved = REPAIR (local REPAIR > partner TXSELFCAL)
        repeat (3) @(posedge clk);
        // partner sends rsp with wrong encoding (TXSELFCAL instead of correct REPAIR)
        send_partner_rsp(ENC_TXSELFCAL);
        repeat (5) @(posedge clk);
        check(phyretrain_error === 1'b1, "8: phyretrain_error asserts on encoding mismatch");
        check(phyretrain_done  === 1'b0, "8: done stays low on mismatch");
        @(negedge clk) phyretrain_enable = 1'b0;
        @(posedge clk); #1;
        check(phyretrain_error === 1'b0, "8: error clears after enable=0");

        $display("\n==== PHYRETRAIN_tb summary: %0d error(s) ====", errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    // Global watchdog
    initial begin
        #(CLK_PERIOD * 200000);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
