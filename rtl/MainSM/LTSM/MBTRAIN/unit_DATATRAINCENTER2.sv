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
        parameter MAX_PHASE_CODE   = 7'd127, // Maximum PI phase sweep code (7-bit).
        parameter MIN_PHASE_CODE   = 7'd00 , // Minimum PI phase sweep code.
        parameter NUM_DATA_LANES   = 16      // Number of data lanes tracked.
    ) (
        internal_ltsm_if.datatraincenter2_mp dtc2_if,
        internal_ltsm_if.mbtrain2d2c_mp      d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_start_req  ; // for {MBTRAIN.DATATRAINCENTER2 start req}
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_start_resp ; // for {MBTRAIN.DATATRAINCENTER2 start resp}
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_end_req    ; // for {MBTRAIN.DATATRAINCENTER2 end req}
    import UCIe_pkg::MBTRAIN_DATATRAINCENTER2_end_resp   ; // for {MBTRAIN.DATATRAINCENTER2 end resp}
    import UCIe_pkg::TRAINERROR_Entry_req                ; // for {TRAINERROR Entry req}
    import UCIe_pkg::NOTHING                             ; // There is no message to send.

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

    wire is_tx_sb_msg_valid;
    assign is_tx_sb_msg_valid =
        (current_state != previous_state) && (
            (current_state == DTC2_START_REQ ) ||
            (current_state == DTC2_START_RESP) ||
            (current_state == DTC2_END_REQ   ) ||
            (current_state == DTC2_END_RESP  ) );

    // >> =====================  For the DTC1 stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge dtc2_if.lclk or negedge dtc2_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!dtc2_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == DTC2_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == DTC2_SET_PHASE  ||
                    current_state == DTC2_TX_D2C_PT  ||
                    current_state == DTC2_LOG_RESULT ||
                    current_state == DTC2_CALC_APPLY ||
                    current_state == DTC2_END_REQ    ) &&
                dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_req && dtc2_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == DTC2_END_REQ && (end_req_sb_msg_rcvd || (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_req && dtc2_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'DTC2_TX_D2C_PT' -> 'DTC2_LOG_RESULT' -> 'DTC2_CALC_APPLY' -> 'DTC2_END_REQ' (for 1 lclk duration) -> 'DTC2_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'DTC2_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the TX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_rx_pt_en = 1'b0;
    always @(posedge dtc2_if.lclk or negedge dtc2_if.rst_n)
    begin
        if(!dtc2_if.rst_n) begin
            d2c_if.partner_tx_pt_en <= 1'b0;
        end
        else if(current_state == DTC2_IDLE || current_state == DTC2_END_RESP) begin // To force the synchronization when we send and receive the {... end req} SB message.
            d2c_if.partner_tx_pt_en <= 1'b0;
        end
        else if(current_state == DTC2_SET_PHASE  ||
                current_state == DTC2_TX_D2C_PT  ||
                current_state == DTC2_LOG_RESULT ||
                current_state == DTC2_CALC_APPLY ||
                current_state == DTC2_END_REQ    ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_tx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_tx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //

    // =====================================================================
    // Phase sweep counter width
    // =====================================================================
    localparam PW = $clog2(MAX_PHASE_CODE + 1);

    // Wires driven by unit_data_sweep sub-module
    wire [PW-1:0] swept_code_r;
    wire [PW-1:0] best_code_r [15:0];

    // =====================================================================
    // Sweep datapath: delegate to the shared unit_data_sweep module.
    // This replaces the inline sweep registers and DTC2_SWEEP_PROC block.
    // =====================================================================
    unit_data_sweep #(
        .MAX_DATA_VREF_CODE(MAX_PHASE_CODE),
        .MIN_DATA_VREF_CODE(MIN_PHASE_CODE)
    ) u_data_sweep (
        .lclk                (dtc2_if.lclk),
        .rst_n               (dtc2_if.rst_n),
        .is_ltsm_out_of_reset(dtc2_if.is_ltsm_out_of_reset),
        .start_req_state     (current_state == DTC2_START_REQ),
        .log_result_state    (current_state == DTC2_LOG_RESULT),
        .calc_apply_state    (current_state == DTC2_CALC_APPLY),
        .mb_rx_data_lane_mask(dtc2_if.mb_rx_data_lane_mask),
        .d2c_perlane_pass    (d2c_if.d2c_perlane_pass),
        .swept_code_r        (swept_code_r),
        .best_vref_code      (best_code_r)
    );

    // =====================================================================
    // (Block 1) Sequential: current state
    // =====================================================================
    always_ff @(posedge dtc2_if.lclk or negedge dtc2_if.rst_n) begin
        if (!dtc2_if.rst_n) begin
            current_state  <= DTC2_IDLE;
            previous_state <= DTC2_IDLE;
        end
        else if (!dtc2_if.is_ltsm_out_of_reset) begin
            current_state  <= DTC2_IDLE;
            previous_state <= DTC2_IDLE;
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
        if (dtc2_if.timeout_8ms_occured | (dtc2_if.rx_sb_msg == TRAINERROR_Entry_req && dtc2_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                DTC2_IDLE: begin
                    next_state = dtc2_if.datatraincenter2_en ?
                        DTC2_START_REQ : DTC2_IDLE;
                end
                DTC2_START_REQ: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_req && dtc2_if.rx_sb_msg_valid) ?
                        DTC2_START_RESP : DTC2_START_REQ;
                end
                DTC2_START_RESP: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_resp && dtc2_if.rx_sb_msg_valid) ?
                        DTC2_SET_PHASE : DTC2_START_RESP;
                end
                DTC2_SET_PHASE: begin
                    next_state = dtc2_if.analog_settle_time_done ?
                        DTC2_TX_D2C_PT : DTC2_SET_PHASE;
                end
                DTC2_TX_D2C_PT: begin
                    next_state = d2c_if.local_test_d2c_done ?
                        DTC2_LOG_RESULT : DTC2_TX_D2C_PT;
                end
                DTC2_LOG_RESULT: begin
                    // swept_code_r is incremented in unit_data_sweep.
                    // Transition to CALC_APPLY when the last code (MAX) has been logged.
                    next_state = (swept_code_r == MAX_PHASE_CODE) ?
                        DTC2_CALC_APPLY : DTC2_SET_PHASE;
                end
                DTC2_CALC_APPLY: begin
                    next_state = dtc2_if.analog_settle_time_done ?
                        DTC2_END_REQ : DTC2_CALC_APPLY;
                end
                DTC2_END_REQ: begin
                    next_state = (end_req_sb_msg_rcvd & ready_for_end_resp_sb_msg) ?
                        DTC2_END_RESP : DTC2_END_REQ;
                end
                DTC2_END_RESP: begin
                    next_state = (dtc2_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_resp && dtc2_if.rx_sb_msg_valid) ?
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
    // All interface outputs are driven here; the data-path is delegated
    // entirely to unit_data_sweep.
    // =====================================================================
    always_comb begin
        // Safe defaults
        dtc2_if.datatraincenter2_done  = 1'b0;
        dtc2_if.trainerror_req         = 1'b0;
        dtc2_if.timeout_timer_en       = 1'b1;
        dtc2_if.analog_settle_timer_en = 1'b0;

        // D2C point test defaults
        d2c_if.local_tx_pt_en       = 1'b0;
        d2c_if.local_rx_pt_en       = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00 ; // Eye center
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

        case (current_state)
            DTC2_IDLE: dtc2_if.timeout_timer_en = 1'b0;

            DTC2_START_REQ: begin
                dtc2_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_req;
            end

            DTC2_START_RESP: begin
                dtc2_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_resp;
            end

            DTC2_SET_PHASE: begin
                // Drive the current sweep code to the PI and wait for analog settle.
                // (phy_tx_data_pi_phase_ctrl is driven per-lane by the generate block.)
                dtc2_if.analog_settle_timer_en = 1'b1;
            end

            DTC2_TX_D2C_PT: begin
                // Hold swept_code_r on PHY while the Tx D2C test runs.
                // (phy_tx_data_pi_phase_ctrl is driven per-lane by the generate block.)
                d2c_if.local_tx_pt_en              = 1'b1;
            end

            DTC2_LOG_RESULT: begin
                // Hold swept_code_r on PHY during the 1-cycle result logging.
                // (phy_tx_data_pi_phase_ctrl is driven per-lane by the generate block.)
            end

            DTC2_CALC_APPLY: begin
                // phy_tx_data_pi_phase_ctrl[lane] is now driven per-lane by the
                // generate block (best_code_r[lane] after sweep completes).
                // Wait for analog settle before accepting the final value.
                dtc2_if.analog_settle_timer_en = 1'b1;
            end

            DTC2_END_REQ: begin
                dtc2_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc2_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_req;
            end

            DTC2_END_RESP: begin
                dtc2_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
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
    // Per-lane phy_tx_data_pi_phase_ctrl combinational assignment.
    //
    // During the PI sweep states (SET_PHASE, TX_D2C_PT, LOG_RESULT) every
    // lane is driven with the current swept_code_r so the PHY sees the code
    // under test.  In all other states each lane independently receives its
    // own best_code_r[l] — the midpoint calculated in CALC_APPLY.
    // =====================================================================
    genvar g2;
    generate
        for (g2 = 0; g2 < NUM_DATA_LANES; g2++) begin : GEN_PI_PHASE
            assign dtc2_if.phy_tx_data_pi_phase_ctrl[g2] =
                (current_state == DTC2_SET_PHASE     ||
                    current_state == DTC2_TX_D2C_PT  ||
                    current_state == DTC2_LOG_RESULT) ? swept_code_r : best_code_r[g2];
        end
    endgenerate

    // Sweep algorithm and datapath are delegated to unit_data_sweep.
endmodule
