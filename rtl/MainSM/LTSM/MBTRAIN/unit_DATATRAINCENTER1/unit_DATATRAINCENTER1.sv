// =============================================================================
// Module  : unit_DATATRAINCENTER1
// Purpose : MBTRAIN.DATATRAINCENTER1 sub-state FSM.
//           Sweeps the Tx Phase Interpolator (PI) across its full range using
//           a "Tx-Initiated Data to Clock Point Test" and then applies the
//           optimal per-lane deskew center.
//
//           Spec Reference: LTSM_from_MBTRAIN_tables.txt lines 500-565.
// =============================================================================

module unit_DATATRAINCENTER1 #(
        parameter MAX_PHASE_CODE   = 6'h3F, // Maximum PI phase sweep code (6-bit per phy_tx_pi_phase_ctrl).
        parameter MIN_PHASE_CODE   = 6'h00, // Minimum PI phase sweep code.
        parameter NUM_DATA_LANES   = 16     // Number of data lanes tracked.
    ) (
        internal_ltsm_if.datatraincenter1_mp dtc1_if,
        internal_ltsm_if.substate2d2c_mp     d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER1_start_req ;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER1_start_resp;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER1_end_req   ;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER1_end_resp  ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING             ;

    // =====================================================================
    // State encoding
    // =====================================================================
    localparam  DTC1_IDLE        = 4'h0, // (S0)  Wait for enable
    DTC1_START_REQ  = 4'h1, // (S1)  SB: DTC1 start req
    DTC1_START_RESP = 4'h2, // (S2)  SB: DTC1 start resp
    DTC1_SET_PHASE  = 4'h3, // (S3)  Drive PI phase; analog settle
    DTC1_TX_D2C_PT  = 4'h4, // (S4)  Tx D2C point test
    DTC1_LOG_RESULT = 4'h5, // (S5)  Per-lane log; bump phase_code
    DTC1_CALC_APPLY = 4'h6, // (S6)  Compute midpoints; analog settle
    DTC1_END_REQ    = 4'h7, // (S7)  SB: DTC1 end req
    DTC1_END_RESP   = 4'h8, // (S8)  SB: DTC1 end resp
    TO_DATATRAINVREF= 4'h9, // (S9)  Signal done; wait en de-assert
    TO_TRAINERROR   = 4'hA; // (S10) Fatal

    reg [3:0] current_state, next_state, previous_state;

    // Glitch-guard: do not assert tx_sb_msg_valid on the cycle of a state change.
    wire data_incoherence = (current_state != previous_state);

    // ─── Phase sweep counter (6-bit to match phy_tx_pi_phase_ctrl) ───────
    localparam PW = $bits(dtc1_if.phy_tx_pi_phase_ctrl); // 6
    reg [PW-1:0] phase_code_r;

    // ─── Per-lane: left/right edges of widest contiguous pass window ─────
    reg [PW-1:0] left_edge [NUM_DATA_LANES-1:0];
    reg [PW-1:0] right_edge[NUM_DATA_LANES-1:0];
    reg          found_pass [NUM_DATA_LANES-1:0];
    reg          in_pass    [NUM_DATA_LANES-1:0];

    // ─── Registered fail flag (output, must persist past CALC_APPLY) ─────
    reg dtc1_fail_flag_r;
    assign dtc1_if.datatraincenter1_fail_flag = dtc1_fail_flag_r;

    // ─── Applied PI phase (registered to avoid multiple-driver conflict) ──
    reg [PW-1:0] pi_phase_applied_r;

    // EQ preset first-entry tracking
    reg r_first_entry_flag;

    // ─── any_fail combinational reduction (used in CALC_APPLY) ───────────
    genvar g;
    wire any_fail_w;
    wire [NUM_DATA_LANES-1:0] found_pass_bus;
    generate
        for (g = 0; g < NUM_DATA_LANES; g++) begin : GEN_FP
            assign found_pass_bus[g] = found_pass[g];
        end
    endgenerate
    assign any_fail_w = ~(&found_pass_bus); // any lane with found_pass==0 → fail

    // =====================================================================
    // (Block 1) Sequential: current state
    // =====================================================================
    always @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n) begin
        if (!dtc1_if.rst_n) begin
            current_state  <= DTC1_IDLE;
            previous_state <= DTC1_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: next state
    // =====================================================================
    always @(*) begin
        if (dtc1_if.timeout_8ms_occured |
            (dtc1_if.rx_sb_msg == TRAINERROR_Entry_req &&
             dtc1_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                DTC1_IDLE: begin
                    next_state = dtc1_if.datatraincenter1_en ?
                                 DTC1_START_REQ : DTC1_IDLE;
                end
                DTC1_START_REQ: begin
                    next_state = (dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_start_req &&
                                  dtc1_if.rx_sb_msg_valid) ?
                                 DTC1_START_RESP : DTC1_START_REQ;
                end
                DTC1_START_RESP: begin
                    next_state = (dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_start_resp &&
                                  dtc1_if.rx_sb_msg_valid) ?
                                 DTC1_SET_PHASE : DTC1_START_RESP;
                end
                DTC1_SET_PHASE: begin
                    next_state = dtc1_if.analog_settle_time_done ?
                                 DTC1_TX_D2C_PT : DTC1_SET_PHASE;
                end
                DTC1_TX_D2C_PT: begin
                    next_state = d2c_if.test_d2c_done ?
                                 DTC1_LOG_RESULT : DTC1_TX_D2C_PT;
                end
                DTC1_LOG_RESULT: begin
                    // Counter is incremented in the sequential block.
                    // When already at MAX before increment → we are at MAX → go to CALC.
                    next_state = (phase_code_r == MAX_PHASE_CODE) ?
                                 DTC1_CALC_APPLY : DTC1_SET_PHASE;
                end
                DTC1_CALC_APPLY: begin
                    next_state = dtc1_if.analog_settle_time_done ?
                                 DTC1_END_REQ : DTC1_CALC_APPLY;
                end
                DTC1_END_REQ: begin
                    next_state = (dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_req &&
                                  dtc1_if.rx_sb_msg_valid) ?
                                 DTC1_END_RESP : DTC1_END_REQ;
                end
                DTC1_END_RESP: begin
                    next_state = (dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_resp &&
                                  dtc1_if.rx_sb_msg_valid) ?
                                 TO_DATATRAINVREF : DTC1_END_RESP;
                end
                TO_DATATRAINVREF: begin
                    next_state = dtc1_if.datatraincenter1_en ?
                                 TO_DATATRAINVREF : DTC1_IDLE;
                end
                TO_TRAINERROR: begin
                    next_state = dtc1_if.datatraincenter1_en ?
                                 TO_TRAINERROR : DTC1_IDLE;
                end
                default: next_state = dtc1_if.datatraincenter1_en ?
                                      TO_TRAINERROR : DTC1_IDLE;
            endcase
        end
    end

    // =====================================================================
    // (Block 3) Combinational: outputs
    // All outputs are driven here; sequential blocks only maintain
    // internal data registers (phase_code_r, left_edge, pi_phase_applied_r).
    // =====================================================================
    always @(*) begin
        // ── Safe defaults ─────────────────────────────────────────────────
        dtc1_if.datatraincenter1_done  = 1'b0;
        dtc1_if.trainerror_req         = 1'b0;
        dtc1_if.timeout_timer_en       = 1'b1;
        dtc1_if.analog_settle_timer_en = 1'b0;

        // D2C point test defaults
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00; // Eye center
        d2c_if.d2c_lfsr_en          = 1'b1 ;
        d2c_if.d2c_pattern_setup    = 3'b001; // Data pattern
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // Operational valid
        d2c_if.d2c_pattern_mode     = 1'b0  ; // Continuous
        d2c_if.d2c_burst_count      = 16'd4096;
        d2c_if.d2c_idle_count       = 16'd0;
        d2c_if.d2c_iter_count       = 16'd1;
        d2c_if.d2c_compare_setup    = 2'd0  ; // Per-lane

        // MB defaults
        dtc1_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        dtc1_if.mb_tx_data_lane_sel = 2'b01; // Active
        dtc1_if.mb_tx_val_lane_sel  = 2'b01; // Operational Valid
        dtc1_if.mb_tx_trk_lane_sel  = 2'b00; // Low (spec S1)
        dtc1_if.mb_rx_clk_lane_sel  = 1'b1 ;
        dtc1_if.mb_rx_data_lane_sel = 1'b1 ;
        dtc1_if.mb_rx_val_lane_sel  = 1'b0 ;
        dtc1_if.mb_rx_trk_lane_sel  = 1'b0 ;

        // SB defaults
        dtc1_if.tx_sb_msg_valid = 1'b0   ;
        dtc1_if.tx_sb_msg       = NOTHING ;
        dtc1_if.tx_msginfo      = 16'h0  ;
        dtc1_if.tx_data_field   = 64'h0  ;

        // PHY: drive phase code from the registered value
        dtc1_if.phy_tx_pi_phase_ctrl = pi_phase_applied_r;

        case (current_state)
            DTC1_IDLE: dtc1_if.timeout_timer_en = 1'b0;

            DTC1_START_REQ: begin
                dtc1_if.tx_sb_msg_valid = !data_incoherence;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_req;
            end

            DTC1_START_RESP: begin
                dtc1_if.tx_sb_msg_valid = !data_incoherence;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_resp;
            end

            DTC1_SET_PHASE: begin
                dtc1_if.phy_tx_pi_phase_ctrl   = phase_code_r;
                dtc1_if.analog_settle_timer_en = 1'b1;
            end

            DTC1_TX_D2C_PT: begin
                dtc1_if.phy_tx_pi_phase_ctrl = phase_code_r;
                d2c_if.tx_pt_en              = 1'b1;
            end

            DTC1_LOG_RESULT: begin
                dtc1_if.phy_tx_pi_phase_ctrl = phase_code_r;
            end

            DTC1_CALC_APPLY: begin
                dtc1_if.analog_settle_timer_en = 1'b1;
                // pi_phase_applied_r is already set by sequential CALC_APPLY block
            end

            DTC1_END_REQ: begin
                dtc1_if.tx_sb_msg_valid = !data_incoherence;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_end_req;
            end

            DTC1_END_RESP: begin
                dtc1_if.tx_sb_msg_valid = !data_incoherence;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_end_resp;
            end

            TO_DATATRAINVREF: begin
                dtc1_if.datatraincenter1_done = 1'b1;
                dtc1_if.timeout_timer_en      = 1'b0;
            end

            TO_TRAINERROR: begin
                dtc1_if.datatraincenter1_done = 1'b1;
                dtc1_if.trainerror_req        = 1'b1;
                dtc1_if.timeout_timer_en      = 1'b0;
            end

            default: begin end
        endcase
    end

    // =====================================================================
    // Sequential: phase code counter
    // =====================================================================
    always @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n) begin : DTC1_PHASE_CNT
        integer i;
        if (!dtc1_if.rst_n) begin
            phase_code_r <= MIN_PHASE_CODE;
        end else if (current_state == DTC1_START_REQ) begin
            // Reset sweep tracker
            phase_code_r <= MIN_PHASE_CODE;
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                left_edge [i] <= '0;
                right_edge[i] <= '0;
                found_pass[i] <= 1'b0;
                in_pass   [i] <= 1'b0;
            end
            dtc1_fail_flag_r  <= 1'b0;
            pi_phase_applied_r <= MIN_PHASE_CODE;
        end else if (current_state == DTC1_LOG_RESULT) begin
            // Per-lane: bit l of d2c_perlane_err==1 means error (fail for that lane).
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                if (!d2c_if.d2c_perlane_err[i]) begin
                    // Pass
                    if (!in_pass[i]) begin
                        in_pass   [i] <= 1'b1;
                        left_edge [i] <= phase_code_r;
                        right_edge[i] <= phase_code_r;
                        found_pass[i] <= 1'b1;
                    end else begin
                        right_edge[i] <= phase_code_r; // Extend right boundary
                    end
                end else begin
                    in_pass[i] <= 1'b0; // Fail: close current pass zone
                end
            end
            // Increment phase code
            if (phase_code_r != MAX_PHASE_CODE)
                phase_code_r <= phase_code_r + 1;
        end else if (current_state == DTC1_CALC_APPLY) begin
            // Apply midpoints and record fail flag
            for (i = 0; i < NUM_DATA_LANES; i++) begin
                if (found_pass[i]) begin
                    pi_phase_applied_r <=
                        ({1'b0, left_edge[i]} + {1'b0, right_edge[i]}) >> 1;
                end
                // Otherwise leave at whatever it was
            end
            dtc1_fail_flag_r <= any_fail_w;
        end
    end

    // =====================================================================
    // Sequential: EQ preset first-entry flag
    // =====================================================================
    always @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n) begin : DTC1_FIRST_ENTRY
        if (!dtc1_if.rst_n) begin
            r_first_entry_flag <= 1'b1;
        end else if (current_state == TO_DATATRAINVREF ||
                     current_state == TO_TRAINERROR) begin
            r_first_entry_flag <= 1'b0;
        end
    end

endmodule
