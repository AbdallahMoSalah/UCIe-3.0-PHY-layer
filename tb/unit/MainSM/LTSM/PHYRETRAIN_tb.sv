// Testbench for rtl/MainSM/LTSM/PHYRETRAIN.sv against UCIe 3.0 §4.5.3.7 and
// Table 4-12 retrain-encoding resolution.
//
// Inline partner stub drives the DUT's RX with configurable timing and
// encoding.  SB FIFO is modeled as a single ltsm_rdy line driven by the TB;
// default high, can be pulled low to test back-pressure.

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
    logic [2:0]  local_retrain_enc;
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
        .local_retrain_enc    (local_retrain_enc),
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

    // ---------------- Always-on TX observers (modules-level stickies) ----------------
    // Reset per scenario via clear_tx_observers().  Capture the encoding carried
    // in the most recent DUT-sent req/resp.
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
            // only count acceptance (ltsm_rdy=1), mirrors DUT's sticky semantics
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

    // (TX observers cleared automatically by rst_n=0 inside do_async_reset.)

    // ---------------- Inline partner ----------------
    // Drive RX inputs. send_partner_req / send_partner_rsp tasks pulse the
    // RX side with the chosen encoding/message.
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
        rst_n             = 1'b0;
        phyretrain_enable = 1'b0;
        local_retrain_enc = ENC_TXSELFCAL;
        ltsm_rdy          = 1'b1;
        init_rx();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---------------- One full handshake helper ----------------
    // Runs from cold IDLE: enable; partner sends req with partner_enc, then rsp;
    // checks resolved encoding == expected; checks done asserts and tx msgs OK.
    task automatic run_handshake(input logic [2:0] local_enc,
                                 input logic [2:0] partner_enc,
                                 input string      label);
        logic [2:0] expect_resolved;
        expect_resolved = expected_resolved(local_enc, partner_enc);

        do_async_reset();                                // clears TX-observer stickies
        local_retrain_enc = local_enc;
        @(negedge clk) phyretrain_enable = 1'b1;

        // Partner driving runs serially (no race with the observer).
        repeat (2) @(posedge clk);
        send_partner_req(partner_enc);
        repeat (3) @(posedge clk);
        send_partner_rsp(expect_resolved);

        // Wait for done with a bounded watchdog.
        fork
            begin wait (phyretrain_done === 1'b1); end
            begin
                repeat (50) @(posedge clk);
                $error("[%s] timeout waiting for done", label);
                errors++;
            end
        join_any
        disable fork;

        check(phyretrain_done    === 1'b1,            $sformatf("%s: done asserted", label));
        check(resolved_retrain_enc === expect_resolved,
              $sformatf("%s: resolved enc = %s (expected %s) for local=%s partner=%s",
                        label, enc_name(resolved_retrain_enc), enc_name(expect_resolved),
                        enc_name(local_enc), enc_name(partner_enc)));
        check(saw_tx_req         === 1'b1,            $sformatf("%s: DUT sent req", label));
        check(last_tx_req_enc    === local_enc,       $sformatf("%s: req msginfo=%s", label, enc_name(last_tx_req_enc)));
        check(saw_tx_rsp         === 1'b1,            $sformatf("%s: DUT sent rsp", label));
        check(last_tx_rsp_enc    === expect_resolved, $sformatf("%s: rsp msginfo=%s", label, enc_name(last_tx_rsp_enc)));

        @(negedge clk) phyretrain_enable = 1'b0;
        @(posedge clk);
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== PHYRETRAIN_tb start ====");
        do_async_reset();
        check(phyretrain_done === 1'b0, "after rst_n: done low");

        // ---- Scenario 1: Table 4-12 — all 9 (local, partner) combinations ----
        $display("\n-- Scenario 1: Table 4-12 resolution coverage --");
        run_handshake(ENC_TXSELFCAL, ENC_TXSELFCAL, "1.0: 001 vs 001 -> 001");
        run_handshake(ENC_TXSELFCAL, ENC_REPAIR   , "1.1: 001 vs 100 -> 100");
        run_handshake(ENC_TXSELFCAL, ENC_SPEEDIDLE, "1.2: 001 vs 010 -> 010");
        run_handshake(ENC_REPAIR   , ENC_TXSELFCAL, "1.3: 100 vs 001 -> 100");
        run_handshake(ENC_REPAIR   , ENC_REPAIR   , "1.4: 100 vs 100 -> 100");
        run_handshake(ENC_REPAIR   , ENC_SPEEDIDLE, "1.5: 100 vs 010 -> 010");
        run_handshake(ENC_SPEEDIDLE, ENC_TXSELFCAL, "1.6: 010 vs 001 -> 010");
        run_handshake(ENC_SPEEDIDLE, ENC_REPAIR   , "1.7: 010 vs 100 -> 010");
        run_handshake(ENC_SPEEDIDLE, ENC_SPEEDIDLE, "1.8: 010 vs 010 -> 010");

        // ---- Scenario 2: partner req arrives BEFORE DUT's req sent (sticky test) ----
        $display("\n-- Scenario 2: partner req-first (req sticky) --");
        do_async_reset();
        local_retrain_enc = ENC_REPAIR;
        ltsm_rdy = 1'b0;                    // block our tx temporarily
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (2) @(posedge clk);
        // partner sends req while ours is still blocked
        send_partner_req(ENC_SPEEDIDLE);    // partner has SPEEDIDLE -> resolved = SPEEDIDLE
        repeat (5) @(posedge clk);
        check(phyretrain_done === 1'b0, "2: still no done while our req unsent");
        // release back-pressure; our req and rsp should both go out, then partner rsp
        @(negedge clk) ltsm_rdy = 1'b1;
        // partner sends its rsp eventually
        repeat (5) @(posedge clk);
        send_partner_rsp(ENC_SPEEDIDLE);
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "2: done asserts after both sent + both received");
        check(resolved_retrain_enc === ENC_SPEEDIDLE, "2: resolved = SPEEDIDLE (local REPAIR vs partner SPEEDIDLE)");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 3: partner rsp arrives BEFORE we've sent our rsp ----
        $display("\n-- Scenario 3: partner rsp-first (rsp sticky) --");
        do_async_reset();
        local_retrain_enc = ENC_TXSELFCAL;
        @(negedge clk) phyretrain_enable = 1'b1;
        // partner sends rsp first (atypical but must be tolerated)
        repeat (2) @(posedge clk);
        send_partner_rsp(ENC_TXSELFCAL);
        // then partner sends req
        repeat (3) @(posedge clk);
        send_partner_req(ENC_TXSELFCAL);
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "3: done asserts when partner rsp precedes req");
        check(resolved_retrain_enc === ENC_TXSELFCAL, "3: resolved = TXSELFCAL");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 4: ltsm_rdy backpressure delays our req for many cycles ----
        $display("\n-- Scenario 4: long backpressure --");
        do_async_reset();
        local_retrain_enc = ENC_REPAIR;
        ltsm_rdy = 1'b0;
        @(negedge clk) phyretrain_enable = 1'b1;
        repeat (40) @(posedge clk);
        check(phyretrain_done === 1'b0, "4: backpressure: no done");
        check(tx_sb_msg_valid && tx_sb_msg == PHYRETRAIN_retrain_start_req,
              "4: req msg held high under backpressure");
        @(negedge clk) ltsm_rdy = 1'b1;
        send_partner_req(ENC_TXSELFCAL);
        repeat (3) @(posedge clk);
        send_partner_rsp(ENC_REPAIR);       // partner-resolved = REPAIR
        wait (phyretrain_done === 1'b1);
        check(phyretrain_done === 1'b1, "4: done asserts after release");
        check(resolved_retrain_enc === ENC_REPAIR, "4: resolved = REPAIR");
        @(negedge clk) phyretrain_enable = 1'b0; @(posedge clk);

        // ---- Scenario 5: done held until enable drops ----
        $display("\n-- Scenario 5: done held until enable drops --");
        run_handshake(ENC_TXSELFCAL, ENC_TXSELFCAL, "5.setup");
        do_async_reset();
        local_retrain_enc = ENC_TXSELFCAL;
        @(negedge clk) phyretrain_enable = 1'b1;
        fork
            begin send_partner_req(ENC_TXSELFCAL); end
            begin repeat (4) @(posedge clk); send_partner_rsp(ENC_TXSELFCAL); end
        join
        wait (phyretrain_done === 1'b1);
        repeat (50) @(posedge clk);
        check(phyretrain_done === 1'b1, "5: done remains high in DONE_HOLD");
        @(negedge clk) phyretrain_enable = 1'b0;
        @(posedge clk); #1;
        check(phyretrain_done === 1'b0, "5: done drops after enable=0");

        // ---- Scenario 6: re-entry restarts handshake ----
        $display("\n-- Scenario 6: re-entry --");
        run_handshake(ENC_SPEEDIDLE, ENC_REPAIR, "6.run1: 010 vs 100");
        run_handshake(ENC_REPAIR   , ENC_TXSELFCAL, "6.run2: 100 vs 001");

        // ---- Scenario 7: async rst_n ----
        $display("\n-- Scenario 7: async rst_n --");
        do_async_reset();
        local_retrain_enc = ENC_TXSELFCAL;
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
