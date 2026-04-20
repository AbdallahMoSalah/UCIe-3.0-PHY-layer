// =============================================================================
// Module  : unit_DATATRAINVREF
// Purpose : MBTRAIN.DATATRAINVREF sub-state FSM.
//           Sweeps the Rx Vref for data lanes using an Rx-Initiated D2C point
//           test to find the optimal voltage reference at the target speed.
//
//           Spec Reference: LTSM_from_MBTRAIN_tables.txt lines 566-626.
//
//           Key Compliance:
//           ─────────────────────────────────────────────────────────────────
//           S2 shortcut: IF (dtc1_fail_flag==1 OR valtraincenter_fail_flag==1)
//                        → skip to END_REQ (same pattern as VALTRAINVREF S2).
//           S5 (LOG_RESULT): No TRAINERROR on fail; set fail_flag and continue.
//           S6 (CALC_APPLY): Wait analog settle; apply best midpoint.
//           SB messages: start_req/resp (d65/d66), end_req/resp (d67/d68).
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
    localparam  DTVREF_IDLE       = 4'h0,
    DTVREF_START_REQ  = 4'h1,
    DTVREF_START_RESP = 4'h2,
    DTVREF_SET_VREF   = 4'h3,
    DTVREF_RX_D2C_PT  = 4'h4,
    DTVREF_LOG_RESULT = 4'h5,
    DTVREF_CALC_APPLY = 4'h6,
    DTVREF_END_REQ    = 4'h7,
    DTVREF_END_RESP   = 4'h8,
    TO_RXDESKEW       = 4'h9,
    TO_TRAINERROR     = 4'hA;

    reg [3:0] current_state, next_state, previous_state;
    wire data_incoherence = (current_state != previous_state);

    // ── Internal Vref sweep register (7-bit) ─────────────────────────────
    localparam VW = $clog2(MAX_VREF_CODE + 1); // 7
    reg [VW-1:0] vref_code_r; // Current sweep code

    // ── Eye-map tracking registers (widest contiguous pass zone) ─────────
    reg [VW-1:0] min_vref_code, max_vref_code, temp_min_vref;
    reg          vref_code_filled;  // At least one pass code found
    reg          is_in_valid_region;

    // ── Best-center applied value ─────────────────────────────────────────
    reg [VW-1:0] vref_applied_r;

    // ── Registered fail flag ──────────────────────────────────────────────
    reg datatrainvref_fail_flag_r;
    assign dtvref_if.datatrainvref_fail_flag = datatrainvref_fail_flag_r;

    // ── any_fail: no pass found anywhere in sweep ─────────────────────────
    wire sweep_failed = !vref_code_filled;

    // =====================================================================
    // (Block 1) Sequential: current state
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
                    next_state = dtvref_if.datatrainvref_en ?
                                 DTVREF_START_REQ : DTVREF_IDLE;
                end
                DTVREF_START_REQ: begin
                    next_state = (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_start_req &&
                                  dtvref_if.rx_sb_msg_valid) ?
                                 DTVREF_START_RESP : DTVREF_START_REQ;
                end
                // SPEC S2 shortcut: if dtc1_fail OR valtraincenter_fail → skip sweep.
                DTVREF_START_RESP: begin
                    if (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_start_resp &&
                        dtvref_if.rx_sb_msg_valid) begin
                        next_state = (dtvref_if.datatraincenter1_fail_flag |
                                      dtvref_if.valtraincenter_fail_flag) ?
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
                    next_state = (vref_code_r == MAX_VREF_CODE[VW-1:0]) ?
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
    // =====================================================================
    always @(*) begin
        dtvref_if.datatrainvref_done   = 1'b0;
        dtvref_if.trainerror_req       = 1'b0;
        dtvref_if.timeout_timer_en     = 1'b1;
        dtvref_if.analog_settle_timer_en = 1'b0;

        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00;
        d2c_if.d2c_lfsr_en          = 1'b1 ;
        d2c_if.d2c_pattern_setup    = 3'b001;
        d2c_if.d2c_data_pattern_sel = 2'b00 ;
        d2c_if.d2c_val_pattern_sel  = 1'b0  ;
        d2c_if.d2c_pattern_mode     = 1'b0  ;
        d2c_if.d2c_burst_count      = 16'd4096;
        d2c_if.d2c_idle_count       = 16'd0;
        d2c_if.d2c_iter_count       = 16'd1;
        d2c_if.d2c_compare_setup    = 2'd0  ;

        dtvref_if.mb_tx_clk_lane_sel  = 2'b01;
        dtvref_if.mb_tx_data_lane_sel = 2'b00; // Low until test active
        dtvref_if.mb_tx_val_lane_sel  = 2'b00;
        dtvref_if.mb_tx_trk_lane_sel  = 2'b00;
        dtvref_if.mb_rx_clk_lane_sel  = 1'b1 ;
        dtvref_if.mb_rx_data_lane_sel = 1'b1 ;
        dtvref_if.mb_rx_val_lane_sel  = 1'b0 ;
        dtvref_if.mb_rx_trk_lane_sel  = 1'b0 ;

        dtvref_if.tx_sb_msg_valid = 1'b0  ;
        dtvref_if.tx_sb_msg       = NOTHING;
        dtvref_if.tx_msginfo      = 16'h0  ;
        dtvref_if.tx_data_field   = 64'h0  ;

        // Drive the Vref ctrl with current sweep/applied value.
        dtvref_if.phy_rx_datavref_ctrl[0] = vref_code_r;

        case (current_state)
            DTVREF_IDLE: dtvref_if.timeout_timer_en = 1'b0;

            DTVREF_START_REQ: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_req;
            end

            DTVREF_START_RESP: begin
                dtvref_if.tx_sb_msg_valid = !data_incoherence;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_resp;
            end

            DTVREF_SET_VREF: begin
                dtvref_if.analog_settle_timer_en = 1'b1;
            end

            DTVREF_RX_D2C_PT: begin
                d2c_if.rx_pt_en               = 1'b1;
                dtvref_if.mb_tx_data_lane_sel  = 2'b01; // Active during test
                dtvref_if.mb_tx_val_lane_sel   = 2'b01;
            end

            DTVREF_LOG_RESULT: begin
                /* Sequential processing in DTVREF_DATA_PROC */
            end

            DTVREF_CALC_APPLY: begin
                dtvref_if.phy_rx_datavref_ctrl[0] = vref_applied_r;
                dtvref_if.analog_settle_timer_en   = 1'b1;
            end

            DTVREF_END_REQ: begin
                dtvref_if.phy_rx_datavref_ctrl[0] = vref_applied_r;
                dtvref_if.tx_sb_msg_valid          = !data_incoherence;
                dtvref_if.tx_sb_msg                = MBTRAIN_DATATRAINVREF_end_req;
            end

            DTVREF_END_RESP: begin
                dtvref_if.phy_rx_datavref_ctrl[0] = vref_applied_r;
                dtvref_if.tx_sb_msg_valid          = !data_incoherence;
                dtvref_if.tx_sb_msg                = MBTRAIN_DATATRAINVREF_end_resp;
            end

            TO_RXDESKEW: begin
                dtvref_if.phy_rx_datavref_ctrl[0] = vref_applied_r;
                dtvref_if.datatrainvref_done       = 1'b1;
                dtvref_if.timeout_timer_en         = 1'b0;
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
    // Sequential: Vref sweep, eye-map tracking, fail flag, and calc/apply
    // =====================================================================
    wire [VW:0] vref_range      = vref_code_filled ?
                                  ({1'b0, max_vref_code} - {1'b0, min_vref_code}) : '0;
    wire [VW:0] temp_vref_range = ({1'b0, vref_code_r} - {1'b0, temp_min_vref});

    always @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n) begin : DTVREF_DATA_PROC
        if (!dtvref_if.rst_n) begin
            vref_code_r             <= MIN_VREF_CODE[VW-1:0];
            min_vref_code           <= '0;
            max_vref_code           <= '0;
            temp_min_vref           <= '0;
            vref_code_filled        <= 1'b0;
            is_in_valid_region      <= 1'b0;
            vref_applied_r          <= MIN_VREF_CODE[VW-1:0];
            datatrainvref_fail_flag_r <= 1'b0;
        end else if (current_state == DTVREF_START_REQ) begin
            // Reset sweep state at start of each run
            vref_code_r        <= MIN_VREF_CODE[VW-1:0];
            min_vref_code      <= '0;
            max_vref_code      <= '0;
            temp_min_vref      <= '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            datatrainvref_fail_flag_r <= 1'b0;
        end else if (current_state == DTVREF_LOG_RESULT) begin
            // Pass/fail based on per-lane error at element 0 (representative lane)
            if (!d2c_if.d2c_perlane_err[0]) begin
                // Pass at current Vref code
                if (!is_in_valid_region) begin
                    is_in_valid_region <= 1'b1;
                    temp_min_vref      <= vref_code_r;
                    if (!vref_code_filled) begin
                        vref_code_filled <= 1'b1;
                        min_vref_code    <= vref_code_r;
                        max_vref_code    <= vref_code_r;
                    end
                end else begin
                    // Still in pass zone — update best window if wider
                    if (temp_vref_range > vref_range) begin
                        min_vref_code <= temp_min_vref;
                        max_vref_code <= vref_code_r;
                    end
                end
            end else begin
                is_in_valid_region <= 1'b0; // Fail: close current pass zone
            end
            // Increment Vref code
            if (vref_code_r != MAX_VREF_CODE[VW-1:0])
                vref_code_r <= vref_code_r + 1;
        end else if (current_state == DTVREF_CALC_APPLY) begin
            datatrainvref_fail_flag_r <= sweep_failed;
            if (vref_code_filled) begin
                vref_applied_r <=
                    ({1'b0, min_vref_code} + {1'b0, max_vref_code}) >> 1;
            end else begin
                vref_applied_r <= MIN_VREF_CODE[VW-1:0];
            end
        end
    end

endmodule
