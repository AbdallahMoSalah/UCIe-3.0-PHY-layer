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
//  Sweep algorithm is fully delegated to unit_data_sweep (shared with
//  unit_DATAVREF, unit_DATATRAINCENTER1, unit_DATATRAINCENTER2).
// =============================================================================
module unit_DATATRAINVREF #(
        parameter MAX_VREF_CODE = 7'd127,
        parameter MIN_VREF_CODE = 7'd10
    ) (
        internal_ltsm_if.datatrainvref_mp dtvref_if,
        internal_ltsm_if.mbtrain2d2c_mp   d2c_if
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
    wire is_tx_sb_data_valid;
    assign is_tx_sb_data_valid = (current_state != previous_state) && (
            (current_state == DTVREF_START_REQ) ||
            (current_state == DTVREF_START_RESP) ||
            (current_state == DTVREF_END_REQ) ||
            (current_state == DTVREF_END_RESP)
        );

    // >> =====================  For the DTVREF stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!dtvref_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == DTVREF_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == DTVREF_SET_VREF      ||
                    current_state == DTVREF_RX_D2C_PT     ||
                    current_state == DTVREF_LOG_RESULT    ||
                    current_state == DTVREF_CALC_APPLY    ||
                    current_state == DTVREF_END_REQ       ) &&
                dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_end_req && dtvref_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == DTVREF_END_REQ && (end_req_sb_msg_rcvd || (dtvref_if.rx_sb_msg == MBTRAIN_DATATRAINVREF_end_req && dtvref_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'DTVREF_RX_D2C_PT' -> 'DTVREF_LOG_RESULT' -> 'DTVREF_CALC_APPLY' -> 'DTVREF_END_REQ' (for 1 lclk duration) -> 'DTVREF_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'DTVREF_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the RX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_tx_pt_en = 1'b0;
    always @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n)
    begin
        if(!dtvref_if.rst_n) begin
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == DTVREF_IDLE || current_state == DTVREF_END_RESP) begin // To force the synchronization when we send and receive the {... end req} SB message.
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == DTVREF_SET_VREF      ||
                current_state == DTVREF_RX_D2C_PT     ||
                current_state == DTVREF_LOG_RESULT    ||
                current_state == DTVREF_CALC_APPLY    ||
                current_state == DTVREF_END_REQ       ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_rx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_rx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //

    // =====================================================================
    // Vref code width
    // =====================================================================
    localparam VW = $clog2(MAX_VREF_CODE + 1); // 7 bits for codes up to 127

    // =====================================================================
    // unit_data_sweep instantiation
    //
    // Delegates all per-lane eye-map tracking, swept_code_r counter, and
    // CALC_APPLY midpoint computation to the shared submodule.
    // =====================================================================
    wire [VW-1:0] swept_code_r;
    wire [VW-1:0] best_vref_code [15:0];

    unit_data_sweep #(
        .MAX_DATA_VREF_CODE(MAX_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_VREF_CODE)
    ) u_data_sweep (
        .lclk                (dtvref_if.lclk),
        .rst_n               (dtvref_if.rst_n),
        .is_ltsm_out_of_reset(dtvref_if.is_ltsm_out_of_reset),
        .start_req_state     (current_state == DTVREF_START_REQ),
        .log_result_state    (current_state == DTVREF_LOG_RESULT),
        .calc_apply_state    (current_state == DTVREF_CALC_APPLY),
        .mb_rx_data_lane_mask(dtvref_if.mb_rx_data_lane_mask),
        .d2c_perlane_pass    (d2c_if.d2c_perlane_pass),
        .swept_code_r        (swept_code_r),
        .best_vref_code      (best_vref_code)
    );

    // =====================================================================
    // Per-lane PHY Vref drive
    //
    // During the sweep states (S3-S5): drive swept_code_r to the PHY
    //   (shared Vref for all lanes simultaneously).
    // After CALC_APPLY (S6+)        : drive the per-lane optimal midpoint.
    // =====================================================================
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : VREF_CTRL_GEN
            assign dtvref_if.phy_rx_datavref_ctrl[lane] =
                (current_state == DTVREF_START_REQ     ||
                    current_state == DTVREF_START_RESP ||
                    current_state == DTVREF_SET_VREF   ||
                    current_state == DTVREF_RX_D2C_PT  ||
                    current_state == DTVREF_LOG_RESULT) ? swept_code_r : best_vref_code[lane];
        end
    endgenerate

    // =====================================================================
    // (Block 1) Sequential: current state register
    // =====================================================================
    always_ff @(posedge dtvref_if.lclk or negedge dtvref_if.rst_n) begin
        if (!dtvref_if.rst_n) begin
            current_state  <= DTVREF_IDLE;
            previous_state <= DTVREF_IDLE;
        end
        else if (!dtvref_if.is_ltsm_out_of_reset) begin
            current_state  <= DTVREF_IDLE;
            previous_state <= DTVREF_IDLE;
        end
        else begin
            current_state  <= next_state   ;
            previous_state <= current_state;
        end
    end
    // =====================================================================
    // (Block 2) Combinational: next state
    // =====================================================================
    always_comb begin
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
                        next_state = DTVREF_SET_VREF  ;
                    end else begin
                        next_state = DTVREF_START_RESP;
                    end
                end
                DTVREF_SET_VREF: begin
                    next_state = dtvref_if.analog_settle_time_done ?
                        DTVREF_RX_D2C_PT : DTVREF_SET_VREF;
                end
                DTVREF_RX_D2C_PT: begin
                    next_state = d2c_if.local_test_d2c_done ?
                        DTVREF_LOG_RESULT : DTVREF_RX_D2C_PT;
                end
                DTVREF_LOG_RESULT: begin
                    // swept_code_r is incremented inside unit_data_sweep.
                    // Transition to CALC_APPLY when the last code has been logged.
                    next_state = (swept_code_r == MAX_VREF_CODE[VW-1:0]) ?
                        DTVREF_CALC_APPLY : DTVREF_SET_VREF;
                end
                DTVREF_CALC_APPLY: begin
                    next_state = dtvref_if.analog_settle_time_done ?
                        DTVREF_END_REQ : DTVREF_CALC_APPLY;
                end
                DTVREF_END_REQ: begin
                    next_state = (end_req_sb_msg_rcvd & ready_for_end_resp_sb_msg) ?
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
    //       block above (VREF_CTRL_GEN). No assignments are made here to
    //       avoid duplicate drivers.
    // =====================================================================
    always_comb begin
        // LTSM controller signals.
        dtvref_if.datatrainvref_done   = 1'b0;
        dtvref_if.trainerror_req       = 1'b0;
        // Timers.
        dtvref_if.timeout_timer_en       = 1'b1;
        dtvref_if.analog_settle_timer_en = 1'b0;
        // D2C test configuration (Rx-initiated, Per-Lane comparison).
        d2c_if.local_rx_pt_en             = 1'b0;
        d2c_if.local_tx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00;    // 00h: Eye Center.
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
        dtvref_if.mb_rx_clk_lane_sel  = 1'b1 ;  // Enable
        dtvref_if.mb_rx_data_lane_sel = 1'b1 ;  // Enable
        dtvref_if.mb_rx_val_lane_sel  = 1'b1 ;  // Enable (holds valid pattern)
        dtvref_if.mb_rx_trk_lane_sel  = 1'b0 ;  // Disable
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
                dtvref_if.tx_sb_msg_valid = is_tx_sb_data_valid;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_req;
            end
            DTVREF_START_RESP: begin
                dtvref_if.tx_sb_msg_valid = is_tx_sb_data_valid;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_resp;
            end
            DTVREF_SET_VREF: begin
                // swept_code_r is driven to all PHY lanes by the generate block.
                // Enable the analog settle timer and wait for it to finish before S4.
                dtvref_if.analog_settle_timer_en = 1'b1;
            end
            DTVREF_RX_D2C_PT: begin
                // swept_code_r still held on all PHY lanes; launch Rx D2C test.
                d2c_if.local_rx_pt_en = 1'b1;
            end
            DTVREF_LOG_RESULT: begin
                // Sequential logic handled inside unit_data_sweep.
            end
            DTVREF_CALC_APPLY: begin
                // Per-lane best midpoints are driven by the generate block.
                // Wait for analog settle before accepting the final value.
                dtvref_if.analog_settle_timer_en = 1'b1;
            end
            DTVREF_END_REQ: begin
                dtvref_if.tx_sb_msg_valid = is_tx_sb_data_valid;
                dtvref_if.tx_sb_msg       = MBTRAIN_DATATRAINVREF_end_req;
            end
            DTVREF_END_RESP: begin
                dtvref_if.tx_sb_msg_valid = is_tx_sb_data_valid;
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
endmodule
