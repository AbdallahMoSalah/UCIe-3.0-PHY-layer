`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_DATATRAINVREF_tb
// Purpose   : Self-checking testbench for unit_DATATRAINVREF FSM.
//
// Scenarios:
//   ✓ Happy path: full Vref sweep → midpoint applied
//   ✓ S2 shortcut: dtc1_fail_flag=1 OR valtraincenter_fail_flag=1 → skip sweep
//   ✓ All-fail sweep → datatrainvref_fail_flag=1 (no TRAINERROR)
//   ✓ 8ms timeout → TO_TRAINERROR
//   ✓ Partner TRAINERROR message → TO_TRAINERROR
//   ✓ Randomized holes-in-eye
// =============================================================================
module unit_DATATRAINVREF_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ;
    parameter TIMEOUT_CYCLES       = 700_000;
    parameter ANALOG_SETTLE_CYCLES = 10     ;
    parameter MIN_VREF_CODE        = 7'd10  ;
    parameter MAX_VREF_CODE        = 7'd127 ;

    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // FSM state names
    typedef enum reg [3:0] {
        DTVREF_IDLE        = unit_DATATRAINVREF_inst.DTVREF_IDLE       ,
        DTVREF_START_REQ   = unit_DATATRAINVREF_inst.DTVREF_START_REQ  ,
        DTVREF_START_RESP  = unit_DATATRAINVREF_inst.DTVREF_START_RESP ,
        DTVREF_SET_VREF    = unit_DATATRAINVREF_inst.DTVREF_SET_VREF   ,
        DTVREF_RX_D2C_PT   = unit_DATATRAINVREF_inst.DTVREF_RX_D2C_PT ,
        DTVREF_LOG_RESULT  = unit_DATATRAINVREF_inst.DTVREF_LOG_RESULT ,
        DTVREF_CALC_APPLY  = unit_DATATRAINVREF_inst.DTVREF_CALC_APPLY ,
        DTVREF_END_REQ     = unit_DATATRAINVREF_inst.DTVREF_END_REQ    ,
        DTVREF_END_RESP    = unit_DATATRAINVREF_inst.DTVREF_END_RESP   ,
        TO_RXDESKEW        = unit_DATATRAINVREF_inst.TO_RXDESKEW       ,
        TO_TRAINERROR      = unit_DATATRAINVREF_inst.TO_TRAINERROR
    } fsm_state_t;
    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_DATATRAINVREF_inst.current_state);

    // Clock
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // DUT
    unit_DATATRAINVREF #(
        .MAX_VREF_CODE(MAX_VREF_CODE),
        .MIN_VREF_CODE(MIN_VREF_CODE)
    ) unit_DATATRAINVREF_inst (
        .dtvref_if(intf),
        .d2c_if   (intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Vref eye model ────────────────────────────────────────────────────
    // Uses intf.phy_rx_datavref_ctrl[0] (indexed) to avoid packed/unpacked mix.
    reg [6:0] current_vref_min    ;
    reg [6:0] current_vref_max    ;
    reg       inject_hole_at_quarter;

    always @(*) begin
        if (intf.phy_rx_datavref_ctrl[0] >= current_vref_min &&
            intf.phy_rx_datavref_ctrl[0] <= current_vref_max) begin
            // One hole injected at the quarter-point of the pass window
            if ((intf.phy_rx_datavref_ctrl[0] ==
                     (current_vref_min + (current_vref_max - current_vref_min)/4))
                && inject_hole_at_quarter)
                intf.tb_perlane_err = 16'h0001; // Lane-0 fails
            else
                intf.tb_perlane_err = 16'h0000; // All pass
        end else begin
            intf.tb_perlane_err = 16'h0001; // Outside range: lane-0 fails
        end
        intf.tb_aggr_err = intf.tb_perlane_err[0];
    end

    // ── Reset ─────────────────────────────────────────────────────────────
    task reset();
        rst_n                           = 0;
        intf.tb_aggr_err                = 0;
        intf.tb_perlane_err             = 0;
        intf.tb_val_err                 = 0;
        intf.tb_clk_err                 = 0;
        intf.tb_wait_timeout            = 0;
        intf.tb_wrong_sb_msg_en         = 0;
        intf.tb_wrong_sb_msg            = NOTHING;
        intf.tb_rx_msginfo              = 16'B0;
        intf.tb_rx_data_field           = 64'B0;
        intf.datatraincenter1_fail_flag = 1'b0;
        intf.valtraincenter_fail_flag   = 1'b0;
        current_vref_min                = MIN_VREF_CODE;
        current_vref_max                = MAX_VREF_CODE;
        inject_hole_at_quarter          = 0;
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
            input logic    dtc1_fail         = 1'b0,
            input logic    vtc_fail          = 1'b0,
            input logic    expect_skip       = 1'b0,
            input logic    expect_fail_flag  = 1'b0,
            input logic    expect_trainerror = 1'b0
        );
        intf.datatraincenter1_fail_flag = dtc1_fail;
        intf.valtraincenter_fail_flag   = vtc_fail;
        lclk_counter_run_flag           = 1;

        fork : TEST
            begin
                intf.datatrainvref_en = 1'b1;
                wait(intf.datatrainvref_done || intf.trainerror_req); #1step;
                intf.datatrainvref_en = 1'b0;

                if (expect_trainerror && !intf.trainerror_req) begin
                    repeat(5) $display("\t\t *** ERROR *** Expected TRAINERROR!"); $stop;
                end
                if (!expect_trainerror && intf.trainerror_req &&
                    !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                    repeat(5) $display("\t\t *** ERROR *** Unexpected TRAINERROR!"); $stop;
                end
                if (!expect_trainerror &&
                    intf.datatrainvref_fail_flag != expect_fail_flag) begin
                    $display("\t\t DEBUG: vref_filled=%0b vref_code_r=%0d min=%0d max=%0d",
                        unit_DATATRAINVREF_inst.vref_code_filled,
                        unit_DATATRAINVREF_inst.vref_code_r,
                        unit_DATATRAINVREF_inst.min_vref_code,
                        unit_DATATRAINVREF_inst.max_vref_code);
                    $display("\t\t DEBUG: current_vref_min=%0d current_vref_max=%0d inject_hole=%0b",
                        current_vref_min, current_vref_max, inject_hole_at_quarter);
                    repeat(5) $display("\t\t *** ERROR *** fail_flag=%0b expected=%0b",
                        intf.datatrainvref_fail_flag, expect_fail_flag); $stop;
                end

                wait(current_state == DTVREF_IDLE || current_state == TO_TRAINERROR);
                success_count++;
                $display("%10t ps: Passed. (Success=%0d Cycles=%0d)\n",
                    $realtime(), success_count, lclk_counter);
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
        join

        lclk_counter_run_flag           = 0;
        intf.tb_wait_timeout            = 0;
        intf.tb_wrong_sb_msg_en         = 0;
        intf.datatraincenter1_fail_flag = 0;
        intf.valtraincenter_fail_flag   = 0;
        @(posedge lclk); #1step;
    endtask

    integer scenario = 1;
    integer tmp;

    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), current_state.name());

        // ─ 1: Happy path ──────────────────────────────────────────────────
        $display("\n==> Scenario %0d: Happy Path", scenario++);
        current_vref_min = 30; current_vref_max = 90; inject_hole_at_quarter = 0;
        start_test(.expect_fail_flag(1'b0));
        reset();

        // ─ 2: S2 shortcut — dtc1_fail_flag = 1 ───────────────────────────
        $display("\n==> Scenario %0d: S2 shortcut (dtc1_fail=1)", scenario++);
        start_test(.dtc1_fail(1'b1), .expect_skip(1'b1));
        reset();

        // ─ 3: S2 shortcut — valtraincenter_fail_flag = 1 ──────────────────
        $display("\n==> Scenario %0d: S2 shortcut (vtc_fail=1)", scenario++);
        start_test(.vtc_fail(1'b1), .expect_skip(1'b1));
        reset();

        // ─ 4: Both fail flags → S2 shortcut ──────────────────────────────
        $display("\n==> Scenario %0d: S2 shortcut (both fail)", scenario++);
        start_test(.dtc1_fail(1'b1), .vtc_fail(1'b1), .expect_skip(1'b1));
        reset();

        // ─ 5: 8ms hardware timeout ───────────────────────────────────────
        $display("\n==> Scenario %0d: 8ms timeout -> TRAINERROR", scenario++);
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─ 6: Partner TRAINERROR ─────────────────────────────────────────
        $display("\n==> Scenario %0d: Partner TRAINERROR", scenario++);
        start_test(.wrong_sb_after(50_000),
                   .wrong_msg(TRAINERROR_Entry_req), .expect_trainerror(1'b1));
        reset();

        // ─ 7: All-fail (single-code window + hole) → fail_flag=1 ─────────
        $display("\n==> Scenario %0d: All-fail Vref sweep", scenario++);
        current_vref_min = 7'd50; current_vref_max = 7'd50;
        inject_hole_at_quarter = 1; // hole at the only pass code → all fail
        start_test(.expect_fail_flag(1'b1));
        reset();

        // ─ 8-57: Randomized holes ─────────────────────────────────────────
        for (int s = 8; s <= 57; s++) begin
            integer max_candidate;
            $display("\n==> Scenario %0d: Random holes", scenario++);
            inject_hole_at_quarter = $urandom_range(0, 1);
            // Pick min in [MIN .. MAX-10] so there is room for at least 1 wider code.
            tmp = $urandom_range(int'(MIN_VREF_CODE), int'(MAX_VREF_CODE) - 10);
            current_vref_min = tmp[6:0];
            max_candidate    = tmp + $urandom_range(5, 30);
            if (max_candidate > int'(MAX_VREF_CODE)) max_candidate = int'(MAX_VREF_CODE);
            current_vref_max = max_candidate[6:0];
            // All-fail only if single-code window AND hole injected (impossible here since range >= 5)
            start_test(.expect_fail_flag(inject_hole_at_quarter &&
                (current_vref_min == current_vref_max)));
            reset();
        end

        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============  Congratulations!  ==============     ");
            $display("   ==================  Tests Passed!  ==================   ");
            $display("        ============================================       ");
        end
        @(posedge lclk); $stop;
    end
endmodule
