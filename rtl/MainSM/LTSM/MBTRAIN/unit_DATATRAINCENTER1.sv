// =============================================================================
// Module  : unit_DATATRAINCENTER1
// Purpose : MBTRAIN.DATATRAINCENTER1 sub-state FSM.
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
module unit_DATATRAINCENTER1 #(
        parameter MAX_PHASE_CODE   = 6'h3F, // Maximum PI phase sweep code (6-bit).
        parameter MIN_PHASE_CODE   = 6'h00  // Minimum PI phase sweep code.
    ) (
        internal_ltsm_if.datatraincenter1_mp dtc1_if,
        internal_ltsm_if.mbtrain2d2c_mp      d2c_if
    );
    localparam NUM_DATA_LANES   = 16; // Number of data lanes tracked.

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
    localparam  DTC1_IDLE = 4'h0, // (S0)  Wait for enable
    DTC1_START_REQ        = 4'h1, // (S1)  SB: DTC1 start req
    DTC1_START_RESP       = 4'h2, // (S2)  SB: DTC1 start resp
    DTC1_SET_PHASE        = 4'h3, // (S3)  Drive PI phase; analog settle
    DTC1_TX_D2C_PT        = 4'h4, // (S4)  Tx D2C point test
    DTC1_LOG_RESULT       = 4'h5, // (S5)  Per-lane log; bump swept_code_r
    DTC1_CALC_APPLY       = 4'h6, // (S6)  Compute per-lane midpoints; analog settle
    DTC1_END_REQ          = 4'h7, // (S7)  SB: DTC1 end req
    DTC1_END_RESP         = 4'h8, // (S8)  SB: DTC1 end resp
    TO_DATATRAINVREF      = 4'h9, // (S9)  Signal done; wait en de-assert
    TO_TRAINERROR         = 4'hA; // (S10) Fatal
    reg [3:0] current_state, next_state, previous_state;

    wire is_tx_sb_msg_valid;
    assign is_tx_sb_msg_valid =
        (current_state != previous_state) && (
            (current_state == DTC1_START_REQ ) ||
            (current_state == DTC1_START_RESP) ||
            (current_state == DTC1_END_REQ   ) ||
            (current_state == DTC1_END_RESP  ) );

    // >> =====================  For the DTC1 stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!dtc1_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == DTC1_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == DTC1_SET_PHASE  ||
                    current_state == DTC1_TX_D2C_PT  ||
                    current_state == DTC1_LOG_RESULT ||
                    current_state == DTC1_CALC_APPLY ||
                    current_state == DTC1_END_REQ    ) &&
                dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_req && dtc1_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == DTC1_END_REQ && (end_req_sb_msg_rcvd || (dtc1_if.rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_req && dtc1_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'DTC1_TX_D2C_PT' -> 'DTC1_LOG_RESULT' -> 'DTC1_CALC_APPLY' -> 'DTC1_END_REQ' (for 1 lclk duration) -> 'DTC1_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'DTC1_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the TX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_rx_pt_en = 1'b0;
    always @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n)
    begin
        if(!dtc1_if.rst_n) begin
            d2c_if.partner_tx_pt_en <= 1'b0;
        end
        else if(current_state == DTC1_IDLE || current_state == DTC1_END_RESP) begin // To force the synchronization when we send and receive the {... end req} SB message.
            d2c_if.partner_tx_pt_en <= 1'b0;
        end
        else if(current_state == DTC1_SET_PHASE  ||
                current_state == DTC1_TX_D2C_PT  ||
                current_state == DTC1_LOG_RESULT ||
                current_state == DTC1_CALC_APPLY ||
                current_state == DTC1_END_REQ    ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_tx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_tx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //


    // Phase sweep counter width
    localparam PW = $clog2(MAX_PHASE_CODE + 1);

    wire [PW-1:0] swept_code_r;
    wire [PW-1:0] best_code_r [15:0];

    unit_data_sweep #(
        .MAX_DATA_VREF_CODE(MAX_PHASE_CODE),
        .MIN_DATA_VREF_CODE(MIN_PHASE_CODE)
    ) u_data_sweep (
        .lclk                (dtc1_if.lclk),
        .rst_n               (dtc1_if.rst_n),
        .is_ltsm_out_of_reset(dtc1_if.is_ltsm_out_of_reset),
        .start_req_state     (current_state == DTC1_START_REQ),
        .log_result_state    (current_state == DTC1_LOG_RESULT),
        .calc_apply_state    (current_state == DTC1_CALC_APPLY),
        .mb_rx_data_lane_mask(dtc1_if.mb_rx_data_lane_mask),
        .d2c_perlane_pass    (d2c_if.d2c_perlane_pass),
        .swept_code_r        (swept_code_r),
        .best_vref_code      (best_code_r)
    );

    // =====================================================================
    // (Block 1) Sequential: current state
    // =====================================================================
    always_ff @(posedge dtc1_if.lclk or negedge dtc1_if.rst_n) begin
        if (!dtc1_if.rst_n) begin
            current_state  <= DTC1_IDLE;
            previous_state <= DTC1_IDLE;
        end
        else if (!dtc1_if.is_ltsm_out_of_reset) begin
            current_state  <= DTC1_IDLE;
            previous_state <= DTC1_IDLE;
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
                    next_state = d2c_if.local_test_d2c_done ?
                        DTC1_LOG_RESULT : DTC1_TX_D2C_PT;
                end
                DTC1_LOG_RESULT: begin
                    // swept_code_r is incremented in the sequential block.
                    // Transition to CALC_APPLY when the last code (MAX) has been logged.
                    next_state = (swept_code_r == MAX_PHASE_CODE) ?
                        DTC1_CALC_APPLY : DTC1_SET_PHASE;
                end
                DTC1_CALC_APPLY: begin
                    next_state = dtc1_if.analog_settle_time_done ?
                        DTC1_END_REQ : DTC1_CALC_APPLY;
                end
                DTC1_END_REQ: begin
                    next_state = (end_req_sb_msg_rcvd & ready_for_end_resp_sb_msg) ?
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
    // All interface outputs are driven here; the data-path block below
    // maintains swept_code_r, best_lo/hi, best_code_r, and fail_flag_r.
    // =====================================================================
    always_comb begin
        // Safe defaults
        dtc1_if.datatraincenter1_done  = 1'b0;
        dtc1_if.trainerror_req         = 1'b0;
        dtc1_if.timeout_timer_en       = 1'b1;
        dtc1_if.analog_settle_timer_en = 1'b0;
        // D2C point test defaults
        d2c_if.local_tx_pt_en       = 1'b0;
        d2c_if.local_rx_pt_en       = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00; // Eye center
        d2c_if.d2c_pattern_setup    = 3'b011; // Data pattern
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // Operational valid
        d2c_if.d2c_pattern_mode     = 1'b0  ; // Continuous
        d2c_if.d2c_burst_count      = 16'd4096;
        d2c_if.d2c_idle_count       = 16'd0   ;
        d2c_if.d2c_iter_count       = 16'd1   ;
        d2c_if.d2c_compare_setup    = 2'd0    ; // Per-lane
        // MB defaults
        dtc1_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        dtc1_if.mb_tx_data_lane_sel = 2'b00; // Low
        dtc1_if.mb_tx_val_lane_sel  = 2'b00; // Low
        dtc1_if.mb_tx_trk_lane_sel  = 2'b00; // Low
        dtc1_if.mb_rx_clk_lane_sel  = 1'b1 ; // Enable
        dtc1_if.mb_rx_data_lane_sel = 1'b1 ; // Enable
        dtc1_if.mb_rx_val_lane_sel  = 1'b1 ; // Enable
        dtc1_if.mb_rx_trk_lane_sel  = 1'b0 ; // Disable
        // SB defaults
        dtc1_if.tx_sb_msg_valid = 1'b0   ;
        dtc1_if.tx_sb_msg       = NOTHING ;
        dtc1_if.tx_msginfo      = 16'h0  ;
        dtc1_if.tx_data_field   = 64'h0  ;
        case (current_state)
            DTC1_IDLE: dtc1_if.timeout_timer_en = 1'b0;
            DTC1_START_REQ: begin
                dtc1_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_req;
            end
            DTC1_START_RESP: begin
                dtc1_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_resp;
            end
            DTC1_SET_PHASE: begin
                // Drive the current sweep code to the PI and wait for analog settle.
                dtc1_if.analog_settle_timer_en = 1'b1;
            end
            DTC1_TX_D2C_PT: begin
                // Hold swept_code_r on PHY while the Tx D2C test runs.
                d2c_if.local_tx_pt_en          = 1'b1;
            end
            DTC1_LOG_RESULT: begin
                // Hold swept_code_r on PHY during the 1-cycle result logging.
            end
            DTC1_CALC_APPLY: begin
                // phy_tx_data_pi_phase_ctrl[lane] is now driven per-lane by the
                // generate block (best_code_r[lane] after sweep completes).
                // Wait for analog settle before the link partner reads the final value.
                dtc1_if.analog_settle_timer_en = 1'b1;
            end
            DTC1_END_REQ: begin
                dtc1_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
                dtc1_if.tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_end_req;
            end
            DTC1_END_RESP: begin
                dtc1_if.tx_sb_msg_valid = is_tx_sb_msg_valid;
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
    // Per-lane phy_tx_data_pi_phase_ctrl combinational assignment.
    //
    // During the PI sweep states (SET_PHASE, TX_D2C_PT, LOG_RESULT) every
    // lane is driven with the current swept_code_r so the PHY sees the code
    // under test.  In all other states each lane independently receives its
    // own best_code_r[l] — the midpoint calculated in CALC_APPLY.
    //
    // This mirrors the per-lane generate pattern used in unit_DATAVREF.sv.
    // =====================================================================
    genvar g;
    generate
        for (g = 0; g < NUM_DATA_LANES; g++) begin : GEN_PI_PHASE
            assign dtc1_if.phy_tx_data_pi_phase_ctrl[g] =
                (   current_state == DTC1_SET_PHASE   ||
                    current_state == DTC1_TX_D2C_PT   ||
                    current_state == DTC1_LOG_RESULT ) ? swept_code_r : best_code_r[g];
        end
    endgenerate

    // Sweep algorithm and datapath are delegated to unit_data_sweep.
endmodule
