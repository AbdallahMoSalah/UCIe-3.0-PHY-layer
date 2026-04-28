// =============================================================================
// Module  : unit_DATATRAINCENTER2
// Purpose : MBTRAIN.DATATRAINCENTER2 sub-state FSM.
//           Sweeps the Tx Phase Interpolator (PI) across its full range using
//           a "Tx-Initiated Data to Clock Point Test" and then applies the
//           optimal per-lane PI phase center.
//
//  Algorithm (data-path always block):
//  ------------------------------------
//  For every PI phase code from MIN to MAX (inner sweep loop):
//    Zone A (new pass zone starts):
//      swept_code_r enters a fresh contiguous pass region.
//      Record zone_min_r[lane] = swept_code_r. Set zone_valid[lane]=1.
//      If this is the very first passing code ever (found_pass[lane]==0):
//        seed best_lo[lane] = best_hi[lane] = swept_code_r, found_pass=1.
//
//    Zone B (continuing inside a contiguous pass zone):
//      Extend best_hi[lane] = swept_code_r.
//      (zone_min_r is already set from Zone A, so best_lo implicitly stays.)
//
//  After full sweep (CALC_APPLY):
//    best_code_r[lane] = (best_lo[lane] + best_hi[lane]) / 2
//    fail_flag_r = 1 if ANY negotiated lane has found_pass[lane]==0.
// =============================================================================

module unit_DATATRAINCENTER2 #(
        parameter MAX_PHASE_CODE   = 6'h3F, // Maximum PI phase sweep code (6-bit).
        parameter MIN_PHASE_CODE   = 6'h00, // Minimum PI phase sweep code.
        parameter NUM_DATA_LANES   = 16     // Number of data lanes tracked.
    ) (
        internal_ltsm_if.datatraincenter2_mp dtc2_if,
        internal_ltsm_if.substate2d2c_mp     d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_start_req ;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_start_resp;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_end_req   ;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_end_resp  ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING             ;

    // =====================================================================
    // State encoding
    // =====================================================================
    localparam  DTC2_IDLE = 4'h0, // (S0)  Wait for enable
    DTC2_START_REQ        = 4'h1, // (S1)  SB: DTC2 start req
    DTC2_START_RESP       = 4'h2, // (S2)  SB: DTC2 start resp
    DTC2_SET_PHASE        = 4'h3, // (S3)  Drive PI phase; analog settle
    DTC2_TX_D2C_PT        = 4'h4, // (S4)  Tx D2C point test
    DTC2_LOG_RESULT       = 4'h5, // (S5)  Per-lane log; bump swept_code_r
    DTC2_CALC_APPLY       = 4'h6, // (S6)  Compute per-lane midpoints; analog settle
    DTC2_END_REQ          = 4'h7, // (S7)  SB: DTC2 end req
    DTC2_END_RESP         = 4'h8, // (S8)  SB: DTC2 end resp
    TO_LINKSPEED          = 4'h9, // (S9)  Signal done; wait en de-assert (goes to LINKSPEED next)
    TO_TRAINERROR         = 4'hA; // (S10) Fatal

    reg [3:0] current_state, next_state, previous_state;

    // Glitch-guard: do not assert tx_sb_msg_valid on the cycle of a state change.
    wire data_incoherence = (current_state != previous_state);

    // Phase sweep counter width (6-bit to match phy_tx_pi_phase_ctrl)
    localparam PW = $clog2(MAX_PHASE_CODE + 1); // 6

    // =====================================================================
    // Internal data-path registers (unified naming, same as DATAVREF/VALVREF)
    // =====================================================================

    // swept_code_r : current PI phase code being swept (S3-S5 loop)
    reg [PW-1:0] swept_code_r;

    // Per-lane eye-map tracking:
    //   zone_valid[l] : 1 while inside a contiguous passing zone (Zone A->B)
    //   found_pass[l] : 1 once any passing code has been seen for lane l
    //   best_lo[l]    : left  edge of the widest (or only) contiguous pass window
    //   best_hi[l]    : right edge of the widest (or only) contiguous pass window
    //
    // DTC2 tracks only ONE contiguous window per lane (last widest found),
    // because the PI eye is expected to be unimodal at this stage.
    // (Contrast with VALVREF/DATAVREF which compare old vs new to pick widest.)
    reg [PW-1:0] best_lo  [NUM_DATA_LANES-1:0];
    reg [PW-1:0] best_hi  [NUM_DATA_LANES-1:0];
    reg          found_pass[NUM_DATA_LANES-1:0];
    reg          zone_valid[NUM_DATA_LANES-1:0];

    // best_code_r[l] : mid-point applied to PHY for each lane after CALC_APPLY
    reg [PW-1:0] best_code_r [NUM_DATA_LANES-1:0];

    // fail_flag_r : set if ANY lane has no passing code in the sweep
    reg fail_flag_r;
    assign dtc2_if.datatraincenter2_fail_flag = fail_flag_r;

    // any_fail: combinational reduction over found_pass[]
    genvar g;
    wire any_fail_w;
    wire [NUM_DATA_LANES-1:0] found_pass_bus;
    generate
        for (g = 0; g < NUM_DATA_LANES; g++) begin : GEN_FP
            assign found_pass_bus[g] = found_pass[g];
        end
    endgenerate
    assign any_fail_w = ~(&found_pass_bus); // any lane with found_pass==0 -> fail

    // =====================================================================
    // (Block 1) Sequential: current state
    // =====================================================================
    always @(posedge dtc2_if.lclk or negedge dtc2_if.rst_n) begin
        if (!dtc2_if.rst_n) begin
            current_state  <= DTC2_IDLE;
            previous_state <= DTC2_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: next state
    // =====================================================================
    always @(*) begin
        if (dtc2_if.timeout_8ms_occured |
                (dtc2_if.rx_sb_msg == TRAINERROR_Entry_req &&
                    dtc2_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                DTC2_IDLE: begin
                    next_state = dtc2_if.datatraincenter2_en ?
                        DTC2_START_REQ : DTC2_IDLE;
                end
                DTC2_START_REQ: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_req &&
                        dtc2_if.rx_sb_msg_valid) ?
                        DTC2_START_RESP : DTC2_START_REQ;
                end
                DTC2_START_RESP: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_resp &&
                        dtc2_if.rx_sb_msg_valid) ?
                        DTC2_SET_PHASE : DTC2_START_RESP;
                end
                DTC2_SET_PHASE: begin
                    next_state = dtc2_if.analog_settle_time_done ?
                        DTC2_TX_D2C_PT : DTC2_SET_PHASE;
                end
                DTC2_TX_D2C_PT: begin
                    next_state = d2c_if.test_d2c_done ?
                        DTC2_LOG_RESULT : DTC2_TX_D2C_PT;
                end
                DTC2_LOG_RESULT: begin
                    // swept_code_r is incremented in the sequential block.
                    // Transition to CALC_APPLY when the last code (MAX) has been logged.
                    next_state = (swept_code_r == MAX_PHASE_CODE) ?
                        DTC2_CALC_APPLY : DTC2_SET_PHASE;
                end
                DTC2_CALC_APPLY: begin
                    next_state = dtc2_if.analog_settle_time_done ?
                        DTC2_END_REQ : DTC2_CALC_APPLY;
                end
                DTC2_END_REQ: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_req &&
                        dtc2_if.rx_sb_msg_valid) ?
                        DTC2_END_RESP : DTC2_END_REQ;
                end
                DTC2_END_RESP: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_resp &&
                        dtc2_if.rx_sb_msg_valid) ?
                        TO_LINKSPEED : DTC2_END_RESP;
                end
                TO_LINKSPEED: begin
                    next_state = dtc2_if.datatraincenter2_en ?
                        TO_LINKSPEED : DTC2_IDLE;
                end
                TO_TRAINERROR: begin
                    next_state = dtc2_if.datatraincenter2_en ?
                        TO_TRAINERROR : DTC2_IDLE;
                end
                default: next_state = dtc2_if.datatraincenter2_en ?
                    TO_TRAINERROR : DTC2_IDLE;
            endcase
        end
    end

    // =====================================================================
    // (Block 3) Combinational: outputs
    // All interface outputs are driven here; the data-path block below
    // maintains swept_code_r, best_lo/hi, best_code_r, and fail_flag_r.
    // =====================================================================
    always @(*) begin
        // Safe defaults
        dtc2_if.datatraincenter2_done  = 1'b0;
        dtc2_if.trainerror_req         = 1'b0;
        dtc2_if.timeout_timer_en       = 1'b1;
        dtc2_if.analog_settle_timer_en = 1'b0;

        // D2C point test defaults
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00; // Eye center
        d2c_if.d2c_lfsr_en          = 1'b1 ;
        d2c_if.d2c_pattern_setup    = 3'b011; // Data pattern
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // Operational valid
        d2c_if.d2c_pattern_mode     = 1'b0  ; // Continuous
        d2c_if.d2c_burst_count      = 16'd4096;
        d2c_if.d2c_idle_count       = 16'd0   ;
        d2c_if.d2c_iter_count       = 16'd1   ;
        d2c_if.d2c_compare_setup    = 2'd0    ; // Per-lane

        // MB defaults
        dtc2_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        dtc2_if.mb_tx_data_lane_sel = 2'b00; // Low
        dtc2_if.mb_tx_val_lane_sel  = 2'b00; // Low
        dtc2_if.mb_tx_trk_lane_sel  = 2'b00; // Low
        dtc2_if.mb_rx_clk_lane_sel  = 1'b1 ; // Enable
        dtc2_if.mb_rx_data_lane_sel = 1'b1 ; // Enable
        dtc2_if.mb_rx_val_lane_sel  = 1'b1 ; // Enable
        dtc2_if.mb_rx_trk_lane_sel  = 1'b0 ; // Disable

        // SB defaults
        dtc2_if.tx_sb_msg_valid = 1'b0   ;
        dtc2_if.tx_sb_msg       = NOTHING ;
        dtc2_if.tx_msginfo      = 16'h0  ;
        dtc2_if.tx_data_field   = 64'h0  ;

        // PHY: drive best_code_r[0] by default (applied after CALC_APPLY).
        dtc2_if.phy_tx_pi_phase_ctrl = best_code_r[0];

        case (current_state)
            DTC2_IDLE: dtc2_if.timeout_timer_en = 1'b0;

            DTC2_START_REQ: begin
                dtc2_if.tx_sb_msg_valid = !data_incoherence;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_req;
            end

            DTC2_START_RESP: begin
                dtc2_if.tx_sb_msg_valid = !data_incoherence;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_resp;
            end

            DTC2_SET_PHASE: begin
                // Drive the current sweep code to the PI and wait for analog settle.
                dtc2_if.phy_tx_pi_phase_ctrl   = swept_code_r;
                dtc2_if.analog_settle_timer_en = 1'b1;
            end

            DTC2_TX_D2C_PT: begin
                // Hold swept_code_r on PHY while the Tx D2C test runs.
                dtc2_if.phy_tx_pi_phase_ctrl = swept_code_r;
                d2c_if.tx_pt_en              = 1'b1;
            end

            DTC2_LOG_RESULT: begin
                // Hold swept_code_r on PHY during the 1-cycle result logging.
                dtc2_if.phy_tx_pi_phase_ctrl = swept_code_r;
            end

            DTC2_CALC_APPLY: begin
                // best_code_r[0] is already driven as default (apply best center).
                // Wait for analog settle before accepting the final value.
                dtc2_if.analog_settle_timer_en = 1'b1;
            end

            DTC2_END_REQ: begin
                dtc2_if.tx_sb_msg_valid = !data_incoherence;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_req;
            end

            DTC2_END_RESP: begin
                dtc2_if.tx_sb_msg_valid = !data_incoherence;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_resp;
            end

            TO_LINKSPEED: begin
                dtc2_if.datatraincenter2_done = 1'b1;
                dtc2_if.timeout_timer_en      = 1'b0;
            end

            TO_TRAINERROR: begin
                dtc2_if.datatraincenter2_done = 1'b1;
                dtc2_if.trainerror_req        = 1'b1;
                dtc2_if.timeout_timer_en      = 1'b0;
            end

            default: begin end
        endcase
    end

    // =====================================================================
    // Sequential: PI phase sweep counter + per-lane eye-map tracking
    //
    // This block implements the inner sweep loop (S1/S5) and the
    // best-center calculation (S6). Signal names are unified with the
    // companion modules (DATAVREF, VALVREF):
    //   swept_code_r  <-> current sweep step
    //   zone_valid[l] <-> is_in_valid_region / in_pass
    //   found_pass[l] <-> vref_code_filled (per-lane)
    //   best_lo[l]    <-> left edge of widest contiguous pass window (min_vref_code)
    //   best_hi[l]    <-> right edge of widest contiguous pass window (max_vref_code)
    //   best_code_r[l]<-> applied midpoint after CALC_APPLY
    //   fail_flag_r   <-> dtc2_fail_flag (set if any lane has zero passing codes)
    //
    // Two-zone logic per lane:
    //   Zone A (new pass zone begins):
    //     zone_valid[l] transitions 0->1.
    //     On the first-ever pass (found_pass[l]==0): seed best_lo/hi with swept_code_r.
    //     On subsequent new zones: reset zone tracking but keep best_lo/hi.
    //   Zone B (continuing in a pass zone):
    //     Extend best_hi[l] = swept_code_r (right boundary grows).
    //     best_lo[l] stays at the value set when Zone A began.
    //   Fail transition:
    //     zone_valid[l] -> 0 (current pass zone closed).
    // =====================================================================
    always @(posedge dtc2_if.lclk or negedge dtc2_if.rst_n) begin : DTC2_SWEEP_PROC
        integer i;
        if (!dtc2_if.rst_n) begin
            // Async reset: initialise all sweep registers
            swept_code_r <= MIN_PHASE_CODE;
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                best_code_r[i] <= MIN_PHASE_CODE;
            end
            fail_flag_r <= 1'b0;

        end else if (current_state == DTC2_START_REQ) begin
            // (S1) Reset sweep state at the start of every new run.
            // Done in START_REQ so back-to-back activations each get a fresh sweep.
            swept_code_r <= MIN_PHASE_CODE;
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                best_code_r[i] <= MIN_PHASE_CODE;
            end
            fail_flag_r <= 1'b0;

        end else if (current_state == DTC2_LOG_RESULT) begin
            // (S5) Per-lane pass/fail logging and swept_code_r increment.
            // d2c_perlane_err[l]==0 -> pass, ==1 -> fail for that lane.
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                if (!d2c_if.d2c_perlane_err[i]) begin
                    // PASS at swept_code_r for lane i
                    if (!zone_valid[i]) begin
                        // Zone A: entering a fresh contiguous pass region.
                        zone_valid[i] <= 1'b1;
                        if (!found_pass[i]) begin
                            // Very first passing code ever: seed the best window.
                            found_pass[i] <= 1'b1;
                            best_lo[i]    <= swept_code_r;
                            best_hi[i]    <= swept_code_r;
                        end
                        // If found_pass[i] already 1 (re-entering Zone A after a hole):
                        // keep existing best_lo/hi; Zone B will extend if wider.
                    end else begin
                        // Zone B: continuing inside the current contiguous pass zone.
                        // Extend the right boundary of the window.
                        best_hi[i] <= swept_code_r;
                    end
                end else begin
                    // FAIL at swept_code_r: close the current pass zone.
                    zone_valid[i] <= 1'b0;
                end
            end
            // Advance the sweep counter (saturates at MAX).
            if (swept_code_r != MAX_PHASE_CODE)
                swept_code_r <= swept_code_r + 1;

        end else if (current_state == DTC2_CALC_APPLY) begin
            // (S6) Compute per-lane PI midpoints and record fail flag.
            // Spec: phase_code = (Left_Edge + Right_Edge) / 2 per lane.
            // Defective lane (found_pass==0): leave best_code_r at its
            // reset/previous value (do not apply a random midpoint).
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                if (found_pass[i]) begin
                    best_code_r[i] <=
                        ({1'b0, best_lo[i]} + {1'b0, best_hi[i]}) >> 1;
                end
                // else: keep previous best_code_r[i] (defective lane, no update).
            end
            // Fail if any negotiated lane never passed.
            fail_flag_r <= any_fail_w;
        end
    end

endmodule
