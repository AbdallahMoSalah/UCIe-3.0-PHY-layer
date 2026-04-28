`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_RXDESKEW_tb
// Purpose   : Self-checking testbench for unit_RXDESKEW FSM.
// =============================================================================
module unit_RXDESKEW_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ;
    parameter TIMEOUT_CYCLES       = 800_000 ; // ≤1M per design constraint; SB echo=5 cycles keeps all scenarios fast
    parameter ANALOG_SETTLE_CYCLES = 10     ;
    parameter MIN_DESKEW_CODE      = 7'd0   ;
    // Reduced from 127→7 for simulation speed (8-code sweep vs 128-code).
    // The FSM behaviour and all arc transitions are identical at any code range.
    parameter MAX_DESKEW_CODE      = 7'd7   ;

    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // FSM state names explicitly defined to match RTL localparams
    typedef enum reg [4:0] {
        RXDESKEW_IDLE              = 5'd00,
        RXDESKEW_START_REQ         = 5'd01,
        RXDESKEW_START_RESP        = 5'd02,
        RXDESKEW_SET_CODE          = 5'd03,
        RXDESKEW_RX_D2C_PT         = 5'd04,
        RXDESKEW_LOG_RESULT        = 5'd05,
        RXDESKEW_CALC_APPLY        = 5'd06,
        RXDESKEW_END_REQ           = 5'd07,
        RXDESKEW_END_RESP          = 5'd08,
        TO_DTC2                    = 5'd09,
        RXDESKEW_CHOOSE_PRESET     = 5'd10,
        RXDESKEW_PRESET_REQ_RESP   = 5'd11,
        RXDESKEW_LOG_PRESET_RESULT = 5'd12,
        RXDESKEW_EXIT_DTC1_REQ     = 5'd13,
        RXDESKEW_ARC_COUNT         = 5'd14,
        RXDESKEW_EXIT_DTC1_RESP    = 5'd15,
        TO_DTC1                    = 5'd16,
        RXDESKEW_IDLE2             = 5'd17,
        TO_TRAINERROR              = 5'd18,
        Continue_Repeating_The_Sweep_States = 5'h1F // Display string for transcript
    } fsm_state_t;

    fsm_state_t current_state, monitor_current_state;
    assign current_state = fsm_state_t'(unit_RXDESKEW_inst.current_state);

    logic first_loop;
    reg [18:0] entered_states;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) first_loop = 1;
        // If we've seen S3, S4, S5 then start collapsing to prevent log spam
        else if (entered_states[3] && entered_states[4] && entered_states[5]) first_loop = 0;
        else first_loop = 1;
    end

    assign monitor_current_state =
        (current_state == TO_TRAINERROR) ? TO_TRAINERROR :
        ((entered_states[3] && entered_states[4] && entered_states[5]) && !first_loop &&
         (current_state == RXDESKEW_SET_CODE || current_state == RXDESKEW_RX_D2C_PT || current_state == RXDESKEW_LOG_RESULT)) ?
        Continue_Repeating_The_Sweep_States : current_state;

    // Clock
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // DUT
    unit_RXDESKEW #(
        .MAX_DESKEW_CODE(MAX_DESKEW_CODE), // 7 for sim speed; RTL logic unchanged
        .MIN_DESKEW_CODE(MIN_DESKEW_CODE),
        .MAX_ARC_LIMIT  (3'd4)
    ) unit_RXDESKEW_inst (
        .rxdeskew_if(intf),
        .d2c_if     (intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_CLK_PERIOD       (0.001               )  // 1ps SB clock (ultra-fast for sim)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Deskew eye model ─────────────────────────────────────────────────
    reg [6:0] deskew_pass_min [15:0];
    reg [6:0] deskew_pass_max [15:0];
    always @(*) begin
        for (int i = 0; i < 16; i++) begin
            intf.tb_perlane_err[i] =
                (intf.phy_rx_deskew_ctrl[i] < deskew_pass_min[i] ||
                 intf.phy_rx_deskew_ctrl[i] > deskew_pass_max[i]) ? 1'b1 : 1'b0;
        end
        intf.tb_aggr_err = |intf.tb_perlane_err;
    end

    // ── Reset ──────────────────────────────────────────────────────────────
    task reset();
        rst_n                            = 0;
        intf.tb_aggr_err                 = 0;
        intf.tb_perlane_err              = 0;
        intf.tb_val_err                  = 0;
        intf.tb_clk_err                  = 0;
        intf.tb_wait_timeout             = 0;
        intf.tb_wrong_sb_msg_en          = 0;
        intf.tb_wrong_sb_msg             = NOTHING;
        intf.tb_rx_msginfo               = 16'h0;
        intf.tb_rx_data_field            = 64'h0;
        intf.datatraincenter1_fail_flag  = 1'b0;
        intf.valtraincenter_fail_flag    = 1'b0;
        intf.partner_valtraincenter_fail_flag = 1'b0;
        intf.param_negotiated_max_speed  = 3'd4; // ≤32 GT/s by default
        intf.mb_rx_data_lane_mask        = 3'b011; // 16 lanes
        for (int i = 0; i < 16; i++) begin
            deskew_pass_min[i]           = 7'd2; // Fit inside 0..7 code range
            deskew_pass_max[i]           = 7'd6;
        end
        #10; rst_n = 1;
    endtask

    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_counter_run_flag = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_counter_run_flag) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    task start_test(
            input integer  abort_after       = TIMEOUT_CYCLES,
            input integer  wrong_sb_after    = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg         = NOTHING,
            input logic    expect_dtc1_req   = 1'b0,
            input logic    expect_trainerror = 1'b0,
            input integer  expected_dtc1_loops = 0,
            input logic    expect_fail_flag  = 1'b0
        );
        integer dtc1_req_count;
        dtc1_req_count    = 0;
        lclk_counter_run_flag = 1;
        entered_states = 0;

        fork : TEST
            begin
                intf.rxdeskew_en = 1'b1;

                // Monitor DTC1 re-entry requests
                if (expect_dtc1_req) begin
                    for (int i = 0; i < expected_dtc1_loops; i++) begin
                        @(posedge intf.datatraincenter1_req); #1step;
                        dtc1_req_count++;
                        // Simulate controller: deassert rxdeskew_en, wait, reassert
                        intf.rxdeskew_en = 1'b0;
                        repeat(10) @(posedge lclk);
                        intf.rxdeskew_en = 1'b1;
                    end
                end

                wait(intf.rxdeskew_done || intf.trainerror_req); #1step;
                intf.rxdeskew_en = 1'b0;

                if (expect_trainerror && !intf.trainerror_req) begin
                    repeat(5) $display("\t\t *** ERROR *** Expected TRAINERROR!"); 
                    fail_count++; $stop;
                end
                if (!expect_trainerror && intf.trainerror_req &&
                        !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                    repeat(5) $display("\t\t *** ERROR *** Unexpected TRAINERROR!"); 
                    fail_count++; $stop;
                end
                if (expect_dtc1_req && dtc1_req_count != expected_dtc1_loops) begin
                    $display("\t\t *** ERROR *** DTC1 re-entry count=%0d expected=%0d", dtc1_req_count, expected_dtc1_loops); 
                    fail_count++; $stop;
                end
                if (!expect_trainerror && intf.rxdeskew_fail_flag != expect_fail_flag) begin
                    $display("\t\t *** ERROR *** fail_flag=%0b expected=%0b", intf.rxdeskew_fail_flag, expect_fail_flag);
                    fail_count++; $stop;
                end

                wait(current_state == RXDESKEW_IDLE || current_state == TO_TRAINERROR);
                success_count++;
                $display("---------------------------------------------------------");
                $display("%10t ps: Scenario Passed. (Success=%0d, Fails=%0d, Cycles=%0d)\n",
                    $realtime(), success_count, fail_count, lclk_counter);
                disable TEST;
            end

            begin
                for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg    = wrong_msg;
            end

            begin
                for (int i = 0; i < abort_after; i++) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end

            begin : STATE_MONITOR
                forever @(posedge lclk) begin
                    entered_states[current_state] = 1;
                end
            end
        join

        lclk_counter_run_flag           = 0;
        intf.tb_wait_timeout            = 0;
        intf.tb_wrong_sb_msg_en         = 0;
        intf.datatraincenter1_fail_flag = 0;
        intf.valtraincenter_fail_flag   = 0;
        intf.partner_valtraincenter_fail_flag = 0;
        entered_states                  = 0;
        @(posedge lclk); #1step;
    endtask

    integer scenario = 1;
    fsm_state_t prev_mon_state;

    initial begin
        reset();
        
        fork
            begin
                forever @(posedge lclk) begin
                    if (monitor_current_state != prev_mon_state) begin
                        $display("%10t ps: State=(%s)", $realtime(), monitor_current_state.name());
                        prev_mon_state = monitor_current_state;
                    end
                end
            end
        join_none

        // ─ 1: Speed ≤32, no error → full deskew sweep ──────────────
        $display("=========================================================");
        $display("==> Scenario %0d START: Speed<=32, No accum error", scenario++);
        intf.param_negotiated_max_speed = 3'd5; // 32 GT/s
        intf.valtraincenter_fail_flag   = 0;
        start_test();
        reset();

        // ─ 2: Speed ≤32, valtraincenter_fail_flag=1 → speed-degrade exit ────────────────
        $display("=========================================================");
        $display("==> Scenario %0d START: Speed<=32, vtc fail (speed-degrade)", scenario++);
        intf.param_negotiated_max_speed = 3'd5; // 32 GT/s
        intf.valtraincenter_fail_flag   = 1;
        start_test();
        reset();

        // ─ 3: Speed >32, no error → Iterates 6 Tx EQ Presets, exit ──────
        // The FSM will arc back to DTC1 a maximum of 4 times if the preset was unchanged initially.
        $display("=========================================================");
        $display("==> Scenario %0d START: Speed>32, No accum, iterate presets then exit", scenario++);
        intf.param_negotiated_max_speed = 3'd6; // 40 GT/s (> 32)
        intf.valtraincenter_fail_flag   = 0;
        start_test(.expect_dtc1_req(1'b1), .expected_dtc1_loops(4));
        reset();

        // ─ 4: 8ms hardware timeout ──
        $display("=========================================================");
        $display("==> Scenario %0d START: 8ms hardware timeout -> TRAINERROR", scenario++);
        intf.param_negotiated_max_speed = 3'd5; // 32 GT/s
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─ 5: Partner TRAINERROR ──────────────────────────────────────────
        $display("=========================================================");
        $display("==> Scenario %0d START: Partner TRAINERROR msg", scenario++);
        intf.param_negotiated_max_speed = 3'd5; // 32 GT/s
        start_test(.wrong_sb_after(3_000), .wrong_msg(TRAINERROR_Entry_req), .expect_trainerror(1'b1));
        reset();

        // ─ 6-9: Randomized speed/fail/zones ───
        for (int s = 6; s <= 9; s++) begin
            $display("=========================================================");
            $display("==> Scenario %0d START: Random Zones and Speed", scenario++);
            intf.param_negotiated_max_speed = $urandom_range(4, 5); // Speed <= 32 to keep log short
            intf.valtraincenter_fail_flag   = 0;
            for (int i = 0; i < 16; i++) begin
                deskew_pass_min[i] = $urandom_range(0, 3);  // Must fit in 0..MAX_DESKEW_CODE=7
                deskew_pass_max[i] = deskew_pass_min[i] + $urandom_range(1, 4);
            end
            start_test();
            reset();
        end

        // ─ 10: All fail zones
        $display("=========================================================");
        $display("==> Scenario %0d START: All lanes fail -> rxdeskew_fail_flag=1", scenario++);
        intf.param_negotiated_max_speed = 3'd5; // 32 GT/s
        intf.valtraincenter_fail_flag   = 0;
        for (int i = 0; i < 16; i++) begin
            deskew_pass_min[i] = 7; // impossible window: min > max within 0..7 range
            deskew_pass_max[i] = 0; // -> all codes will fail the eye model
        end
        start_test(.expect_fail_flag(1'b1));
        reset();

        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============  Congratulations!  ==============     ");
            $display("   ==================  Tests Passed!  ==================   ");
            $display("        ============================================       ");
            $display("      Total Scenarios: %0d | Success: %0d | Fails: %0d", scenario-1, success_count, fail_count);
        end else begin
            $display("        ============================================       ");
            $display("      ==================   FAILED   ==================     ");
            $display("      Total Scenarios: %0d | Success: %0d | Fails: %0d", scenario-1, success_count, fail_count);
        end
        @(posedge lclk); $stop;
    end
endmodule
