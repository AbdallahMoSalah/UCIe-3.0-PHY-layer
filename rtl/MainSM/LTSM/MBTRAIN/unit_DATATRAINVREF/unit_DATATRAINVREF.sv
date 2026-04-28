// =============================================================================
// Module  : unit_DATATRAINVREF
// Purpose : MBTRAIN.DATATRAINVREF sub-state FSM.
//           Sweeps the Rx Vref for ALL 16 data lanes independently using an
//           Rx-Initiated D2C point test to find the optimal voltage reference
//           at the target speed, then applies the per-lane midpoint to the PHY.
//
//           Key Compliance:
//           ---------------------------------------------------------------------
//           S2 shortcut: IF (dtc1_fail_flag==1 OR valtraincenter_fail_flag==1)
//                        -> skip sweep, jump to END_REQ directly.
//           S5 (LOG_RESULT): No TRAINERROR on fail; set fail_flag and continue.
//           S6 (CALC_APPLY): Wait analog settle; apply best midpoint Vref.
//           SB messages: start_req/resp (d65/d66), end_req/resp (d67/d68).
//
//  Algorithm (data-path always block, mirrors unit_DATAVREF exactly):
//  ------------------------------------
//  For every Vref code from MIN to MAX (inner sweep loop, S3-S5):
//    For each of the 16 data lanes independently:
//
//    Zone A (new pass zone starts):
//      d2c_perlane_err[lane] == 0 (pass) AND zone_valid[lane] == 0:
//      Record zone_min_r[lane] = swept_code_r. Set zone_valid[lane] = 1.
//      If this is the very first passing code (found_pass[lane]==0)
//        AND the lane is negotiated (negotiated_data_lanes[lane]==1):
//        seed best_lo[lane] = best_hi[lane] = swept_code_r, found_pass[lane]=1.
//
//    Zone B (continuing inside a contiguous pass zone):
//      d2c_perlane_err[lane] == 0 AND zone_valid[lane] == 1:
//      If current zone is wider than best recorded window:
//        update best_lo[lane] = zone_min_r[lane], best_hi[lane] = swept_code_r.
//
//    Fail (hole detected):
//      d2c_perlane_err[lane] == 1: zone_valid[lane] -> 0.
//
//  After full sweep (CALC_APPLY, S6):
//    best_vref_code[lane] = (best_lo[lane] + best_hi[lane]) / 2
//    fail_flag = 1 if ANY negotiated lane has found_pass[lane] == 0.
//
//  PHY drive:
//    During sweep (S3-S5): phy_rx_datavref_ctrl[lane] = swept_code_r (shared).
//    After CALC_APPLY   : phy_rx_datavref_ctrl[lane] = best_vref_code[lane].
// =============================================================================

module unit_DATATRAINVREF #(
        parameter MAX_VREF_CODE = 7'd127,
        parameter MIN_VREF_CODE = 7'd10
    ) (
        internal_ltsm_if.datatrainvref_mp dtvref_if,
        internal_ltsm_if.substate2d2c_mp  d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATATRAINVREF_start_req ;
    import UCIe_pkg::MBTRAIN_DATATRAINVREF_start_resp;
    import UCIe_pkg::MBTRAIN_DATATRAINVREF_end_req   ;
    import UCIe_pkg::MBTRAIN_DATATRAINVREF_end_resp  ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING             ;

    // =====================================================================
    // State encoding
    // =====================================================================
    localparam  DTVREF_IDLE = 4'h0,
    DTVREF_START_REQ        = 4'h1,
    DTVREF_START_RESP       = 4'h2,
    DTVREF_SET_VREF         = 4'h3,
    DTVREF_RX_D2C_PT        = 4'h4,
    DTVREF_LOG_RESULT       = 4'h5,
    DTVREF_CALC_APPLY       = 4'h6,
    DTVREF_END_REQ          = 4'h7,
    DTVREF_END_RESP         = 4'h8,
    TO_RXDESKEW             = 4'h9,
    TO_TRAINERROR           = 4'hA;

    reg [3:0] current_state, next_state, previous_state;

    // Glitch-guard: suppress tx_sb_msg_valid on the cycle of a state change.
    wire data_incoherence = (current_state != previous_state);

    // =====================================================================
    // Vref code width
    // =====================================================================
    localparam VW = $clog2(MAX_VREF_CODE + 1); // 7 bits for codes up to 127

    // =====================================================================
    // Per-lane Vref sweep data-path registers (mirrors unit_DATAVREF)
    //
    // Unified signal names (consistent across all MBTRAIN Vref modules):
    //   swept_code_r    - current Vref code swept (S3-S5 loop), shared by all lanes
    //   zone_valid[l]   - 1 while inside a contiguous pass zone for lane l
    //   found_pass[l]   - 1 once any passing code has been seen for lane l
    //   zone_min_r[l]   - start of the current contiguous pass zone for lane l
    //   best_lo[l]      - left  edge of the widest contiguous pass window for lane l
    //   best_hi[l]      - right edge of the widest contiguous pass window for lane l
    //   best_vref_code[l] - optimal Vref midpoint applied to PHY after CALC_APPLY
    //
    // Two-zone algorithm (same as DATAVREF_LOG_RESULT_PROC / VALVREF):
    //   Zone A: zone_valid[l] 0->1; save zone_min_r[l] = swept_code_r.
    //           First-ever pass (found_pass[l]==0 & negotiated): seed best_lo/hi.
    //   Zone B: If zone_range[l] > best_range[l]: update best_lo[l]/best_hi[l].
    //   Fail  : zone_valid[l] -> 0.
    // =====================================================================

    // Swept Vref code: one counter drives the same Vref to all lanes simultaneously.
    reg [VW-1:0] swept_code_r;

    // Per-lane eye-map tracking arrays (one element per data lane).
    reg [VW-1:0] zone_min_r  [15:0]; // start of current contiguous pass zone
    reg [VW-1:0] best_lo     [15:0]; // left  edge of widest pass window
    reg [VW-1:0] best_hi     [15:0]; // right edge of widest pass window
    reg          found_pass  [15:0]; // 1 = at least one passing Vref code seen
    reg          zone_valid  [15:0]; // 1 = currently inside a contiguous pass zone

    // Applied per-lane optimal midpoint (written in CALC_APPLY, held afterwards).
    reg [VW-1:0] best_vref_code [15:0];

    // fail_flag: asserted if ANY negotiated lane has no passing Vref code at all.
    reg fail_flag_r;
    assign dtvref_if.datatrainvref_fail_flag = fail_flag_r;

    // =====================================================================
    // Negotiated data lane mask
    //
    // Converts the 3-bit mb_rx_data_lane_mask into a 16-bit bitmask.
    // Only lanes set to 1 here are evaluated when computing the fail flag.
    //   000b: None  001b: Lanes 0-7  010b: Lanes 8-15  011b: Lanes 0-15
    //   100b: Lanes 0-3  101b: Lanes 4-7
    // =====================================================================
    logic [15:0] negotiated_data_lanes;
    always @(*) begin
        case (dtvref_if.mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    // =====================================================================
    // Per-lane combinational range helpers (used in Zone B comparison)
    //   best_range[l] = width of the best recorded pass window for lane l.
    //   zone_range[l] = width of the current contiguous pass zone for lane l.
    // =====================================================================
    wire [VW-1:0] best_range [15:0];
    wire [VW-1:0] zone_range [15:0];

    // Packed bus that mirrors found_pass[] for reduction operations.
    // (Unpacked arrays cannot be used directly in bitwise/reduction operators.)
    wire [15:0] found_pass_bus;

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : VREF_RANGE_GEN
            // Mirror found_pass[lane] -> found_pass_bus[lane] for reductions.
            assign found_pass_bus[lane] = found_pass[lane];

            // Width of the best (widest) recorded pass window for this lane.
            assign best_range[lane] = (found_pass[lane] == 1'b1) ?
                (best_hi[lane] - best_lo[lane]) : '0;
            // Width of the current contiguous pass zone for this lane.
            assign zone_range[lane] = (swept_code_r - zone_min_r[lane]);

            // Drive swept_code_r to PHY during the sweep states (S3-S5),
            // then switch to the per-lane optimal midpoint (best_vref_code) afterwards.
            assign dtvref_if.phy_rx_datavref_ctrl[lane] =
                (current_state == DTVREF_START_REQ  ||
                    current_state == DTVREF_START_RESP ||
                    current_state == DTVREF_SET_VREF   ||
                    current_state == DTVREF_RX_D2C_PT  ||
                    current_state == DTVREF_LOG_RESULT) ? swept_code_r : best_vref_code[lane];
        end
    endgenerate

    // =====================================================================
    // (Block 1) Sequential: current state register
    // =====================================================================
    always @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n) begin
        if (!dtvref_if.rst_n) begin
            current_state  <= DTVREF_IDLE;
            previous_state <= DTVREF_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: next state
    // =====================================================================
    always @(*) begin
        if (dtvref_if.timeout_8ms_occured |
                (dtvref_if.rx_sb_msg == TRAINERROR_Entry_req &&
                    dtvref_if.rx_sb_msg_valid)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                DTVREF_IDLE: begin
                    next_state = dtvref_if.datatrainvref_en ? DTVREF_START_REQ : DTVREF_IDLE;
                end
                DTVREF_START_REQ: begin
                    next_state = (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_start_req &&
                        dtvref_if.rx_sb_msg_valid) ?
                        DTVREF_START_RESP : DTVREF_START_REQ;
                end
                // SPEC S2 shortcut: if dtc1_fail OR valtraincenter_fail -> skip sweep.
                DTVREF_START_RESP: begin
                    if (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_start_resp &&
                            dtvref_if.rx_sb_msg_valid) begin
                        next_state = (dtvref_if.valtraincenter_fail_flag | d2c_if.partner_valtraincenter_fail_flag) ?
                            DTVREF_END_REQ : DTVREF_SET_VREF;
                    end else begin
                        next_state = DTVREF_START_RESP;
                    end
                end
                DTVREF_SET_VREF: begin
                    next_state = dtvref_if.analog_settle_time_done ?
                        DTVREF_RX_D2C_PT : DTVREF_SET_VREF;
                end
                DTVREF_RX_D2C_PT: begin
                    next_state = d2c_if.test_d2c_done ?
                        DTVREF_LOG_RESULT : DTVREF_RX_D2C_PT;
                end
                DTVREF_LOG_RESULT: begin
                    // swept_code_r is incremented in the sequential block.
                    // Transition to CALC_APPLY when the last code has been logged.
                    next_state = (swept_code_r == MAX_VREF_CODE[VW-1:0]) ?
                        DTVREF_CALC_APPLY : DTVREF_SET_VREF;
                end
                DTVREF_CALC_APPLY: begin
                    next_state = dtvref_if.analog_settle_time_done ?
                        DTVREF_END_REQ : DTVREF_CALC_APPLY;
                end
                DTVREF_END_REQ: begin
                    next_state = (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_end_req &&
                        dtvref_if.rx_sb_msg_valid) ?
                        DTVREF_END_RESP : DTVREF_END_REQ;
                end
                DTVREF_END_RESP: begin
                    next_state = (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_end_resp &&
                        dtvref_if.rx_sb_msg_valid) ?
                        TO_RXDESKEW : DTVREF_END_RESP;
                end
                TO_RXDESKEW: begin
                    next_state = dtvref_if.datatrainvref_en ? TO_RXDESKEW : DTVREF_IDLE;
                end
                TO_TRAINERROR: begin
                    next_state = dtvref_if.datatrainvref_en ? TO_TRAINERROR : DTVREF_IDLE;
                end
                default: next_state = dtvref_if.datatrainvref_en ? TO_TRAINERROR : DTVREF_IDLE;
            endcase
        end
    end

    // =====================================================================
    // (Block 3) Combinational: outputs
    //
    // NOTE: phy_rx_datavref_ctrl[15:0] is driven entirely by the generate
    //       block above (VREF_RANGE_GEN). No assignments are made here to
    //       avoid duplicate drivers.
    // =====================================================================
    always @(*) begin
        // LTSM controller signals.
        dtvref_if.datatrainvref_done   = 1'b0;
        dtvref_if.trainerror_req       = 1'b0;

        // Timers.
        dtvref_if.timeout_timer_en       = 1'b1;
        dtvref_if.analog_settle_timer_en = 1'b0;

        // D2C test configuration (Rx-initiated, Per-Lane comparison).
        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00;    // 00h: Eye Center.
        d2c_if.d2c_lfsr_en          = 1'b1;     // Enable Tx & Rx LFSR.
        d2c_if.d2c_pattern_setup    = 3'b011;   // Data + Valid pattern active.
        d2c_if.d2c_data_pattern_sel = 2'b00;    // Per-Lane LFSR pattern.
        d2c_if.d2c_val_pattern_sel  = 1'b0;     // VALTRAIN pattern (held no-care).
        d2c_if.d2c_pattern_mode     = 1'b0;     // Continuous mode.
        d2c_if.d2c_burst_count      = 16'd4096; // 4096 UI burst.
        d2c_if.d2c_idle_count       = 16'd0;
        d2c_if.d2c_iter_count       = 16'd1;
        d2c_if.d2c_compare_setup    = 2'd0;     // Per-Lane comparison -> d2c_perlane_err[15:0].

        // MB lane configuration.
        dtvref_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        dtvref_if.mb_tx_data_lane_sel = 2'b00; // Low until test active
        dtvref_if.mb_tx_val_lane_sel  = 2'b00; // Low
        dtvref_if.mb_tx_trk_lane_sel  = 2'b00; // Low
        dtvref_if.mb_rx_clk_lane_sel  = 2'b01;  // Enable
        dtvref_if.mb_rx_data_lane_sel  = 2'b01;  // Enable
        dtvref_if.mb_rx_val_lane_sel  = 2'b01;  // Enable (holds valid pattern)
        dtvref_if.mb_rx_trk_lane_sel  = 2'b00;  // Disable

        // SB TX defaults.
        dtvref_if.tx_sb_msg_valid = 1'b0   ;
        dtvref_if.tx_sb_msg       = NOTHING ;
        dtvref_if.tx_msginfo      = 16'h0  ;
        dtvref_if.tx_data_field   = 64'h0  ;

        case (current_state)
            DTVREF_IDLE: begin
                dtvref_if.timeout_timer_en = 1'b0;
            end

            DTVREF_START_REQ: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_req;
            end

            DTVREF_START_RESP: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_resp;
            end

            DTVREF_SET_VREF: begin
                // swept_code_r is driven to all PHY lanes by the generate block.
                // Enable the analog settle timer and wait for it to finish before S4.
                dtvref_if.analog_settle_timer_en = 1'b1;
            end

            DTVREF_RX_D2C_PT: begin
                // swept_code_r still held on all PHY lanes; launch Rx D2C test.
                d2c_if.rx_pt_en = 1'b1;
            end

            DTVREF_LOG_RESULT: begin
                // Sequential logic only; see DTVREF_LOG_RESULT_PROC below.
            end

            DTVREF_CALC_APPLY: begin
                // Per-lane best midpoints are driven by the generate block.
                // Wait for analog settle before accepting the final value.
                dtvref_if.analog_settle_timer_en = 1'b1;
            end

            DTVREF_END_REQ: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_end_req;
            end

            DTVREF_END_RESP: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_end_resp;
            end

            TO_RXDESKEW: begin
                dtvref_if.datatrainvref_done = 1'b1;
                dtvref_if.timeout_timer_en   = 1'b0;
            end

            TO_TRAINERROR: begin
                dtvref_if.datatrainvref_done = 1'b1;
                dtvref_if.trainerror_req     = 1'b1;
                dtvref_if.timeout_timer_en   = 1'b0;
            end

            default: begin end
        endcase
    end

    // =====================================================================
    // Sequential: Vref sweep counter, per-lane eye-map tracking (LOG_RESULT)
    //
    // Mirrors the DATAVREF_CODE_AND_CALC_PROC + DATAVREF_LOG_RESULT_PROC pair
    // from unit_DATAVREF, combined into a single always block here for clarity.
    //
    // Signal roles recap (unified with unit_DATAVREF):
    //   swept_code_r   : incremented each LOG_RESULT, reset in START_REQ.
    //   zone_valid[l]  : is_in_valid_region per lane.
    //   found_pass[l]  : vref_code_filled per lane.
    //   zone_min_r[l]  : temp_min_vref per lane (start of current pass zone).
    //   best_lo[l]     : min_vref_code per lane (left edge of widest window).
    //   best_hi[l]     : max_vref_code per lane (right edge of widest window).
    //   best_vref_code[l]: midpoint applied to PHY for lane l after CALC_APPLY.
    //   fail_flag_r    : set if ANY negotiated lane has no passing Vref code.
    // =====================================================================
    always @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n) begin : DTVREF_LOG_RESULT_PROC
        integer i;
        if (!dtvref_if.rst_n) begin
            // Async reset: clear all per-lane tracking registers.
            swept_code_r <= MIN_VREF_CODE[VW-1:0];
            fail_flag_r  <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                zone_min_r     [i] <= '0;
                best_lo        [i] <= '0;
                best_hi        [i] <= '0;
                found_pass     [i] <= 1'b0;
                zone_valid     [i] <= 1'b0;
                best_vref_code [i] <= MIN_VREF_CODE[VW-1:0];
            end

        end else if (current_state == DTVREF_START_REQ) begin
            // (S1) Reset sweep state at the start of each run.
            // Done in START_REQ so back-to-back activations each get a fresh sweep.
            swept_code_r <= MIN_VREF_CODE[VW-1:0];
            fail_flag_r  <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                zone_min_r     [i] <= '0;
                best_lo        [i] <= '0;
                best_hi        [i] <= '0;
                found_pass     [i] <= 1'b0;
                zone_valid     [i] <= 1'b0;
                best_vref_code [i] <= MIN_VREF_CODE[VW-1:0];
            end

        end else if (current_state == DTVREF_LOG_RESULT) begin
            // (S5) Per-lane pass/fail logging, then advance swept_code_r.
            // d2c_perlane_err[l] == 0 -> PASS for lane l.
            // d2c_perlane_err[l] == 1 -> FAIL for lane l.
            for (i = 0; i < 16; i = i + 1) begin
                if (!d2c_if.d2c_perlane_err[i]) begin
                    // PASS at swept_code_r for lane i.
                    // Zone A: entering a new contiguous pass region.
                    if (!zone_valid[i]) begin
                        zone_valid[i]  <= 1'b1;          // mark zone active
                        zone_min_r[i]  <= swept_code_r;  // save zone start

                        // First-ever pass for this (negotiated) lane: seed the window.
                        if (!found_pass[i] && negotiated_data_lanes[i]) begin
                            found_pass[i] <= 1'b1;
                            best_lo[i]    <= swept_code_r;
                            best_hi[i]    <= swept_code_r;
                        end
                    end
                    // Zone B: extending the current contiguous pass zone.
                    // Update the best window only if the current zone is wider.
                    else begin
                        if (zone_range[i] > best_range[i]) begin
                            best_lo[i] <= zone_min_r[i];
                            best_hi[i] <= swept_code_r;
                        end
                    end
                end else begin
                    // FAIL at swept_code_r for lane i: close pass zone.
                    // (Hole in the Vref eye diagram - Zone A will restart on next pass)
                    zone_valid[i] <= 1'b0;
                end
            end

            // Advance the Vref sweep counter (saturates at MAX).
            if (swept_code_r != MAX_VREF_CODE[VW-1:0])
                swept_code_r <= swept_code_r + 1;

        end else if (current_state == DTVREF_CALC_APPLY) begin
            // (S6) Compute per-lane Vref midpoints and record fail flag.
            // Spec eq.: vref_code = (first_success + last_success) / 2
            //           i.e.       = (best_lo[l]   + best_hi[l])   / 2
            for (i = 0; i < 16; i = i + 1) begin
                if (found_pass[i] == 1'b1) begin
                    best_vref_code[i] <= ({1'b0, best_lo[i]} + {1'b0, best_hi[i]}) >> 1;
                end else begin
                    best_vref_code[i] <= MIN_VREF_CODE[VW-1:0]; // safe default
                end
            end

            // Fail flag: set if ANY negotiated lane has no passing Vref code.
            // Uses found_pass_bus (packed) so the bitwise NOT and AND are legal.
            // Non-negotiated lane bits are forced to 1 (via ~negotiated_data_lanes)
            // so they never cause a false failure.
            fail_flag_r <= ~(&(found_pass_bus | (~negotiated_data_lanes)));
        end
    end

endmodule
