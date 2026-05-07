module unit_VALVREF #(
        parameter MAX_VAL_VREF_CODE   = 7'D127,
        parameter MIN_VAL_VREF_CODE   = 7'D10,
        // D2C pattern test configuration – override for simulation speed.
        // Spec defaults: 128 iterations × 8-cycle burst.
        parameter D2C_ITER_COUNT      = 16'D128,
        parameter D2C_BURST_COUNT     = 16'D8
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.valvref_mp valvref_if,
        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    // For analog Voltage control.
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE + 1);
    //reg [1:0] clk_sampling; // To know if the fsm has looped on all Clock sampling values (0h(Eye Center), 1h(Left edge), 2h(Right edge)).
    // To get the used SB messages for: (valvref_if.tx_sb_msg, sb_it.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_VALVREF_start_req ; // Msg Number: d35
    import UCIe_pkg::MBTRAIN_VALVREF_start_resp; // Msg Number: d36
    import UCIe_pkg::MBTRAIN_VALVREF_end_req   ; // Msg Number: d37
    import UCIe_pkg::MBTRAIN_VALVREF_end_resp  ; // Msg Number: d38
    import UCIe_pkg::TRAINERROR_Entry_req      ; // Msg Number: d107
    import UCIe_pkg::NOTHING                   ; // Msg Number: 8'hFF
    // States names
    localparam  VALVREF_IDLE          = 4'h0, // (S0)
    VALVREF_START_REQ     = 4'h1, // (S1)
    VALVREF_START_RESP    = 4'h2, // (S2)
    VALVREF_SET_VREF_CODE = 4'h3, // (S3)
    VALVREF_RX_D2C_PT     = 4'h4, // (S4)
    VALVREF_LOG_RESULT    = 4'h5, // (S5)
    VALVREF_CALC_APPLY    = 4'h6, // (S6)
    VALVREF_END_REQ       = 4'h7, // (S7)
    VALVREF_END_RESP      = 4'h8, // (S8)
    TO_DATAVREF           = 4'h9, // (S9)
    TO_TRAINERROR         = 4'hA; // (S10)
    reg [3:0] current_state, next_state; // The Current, Next states, and Previous state of the FSM.
    wire valvref_fail_flag; // To know if there is no successful Valid Receiver Vref Code.
    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    wire is_tx_sb_msg_valid = (current_state == next_state);
    // Current State Logic of the FSM:
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin
        if (!valvref_if.rst_n) begin
            current_state  <= VALVREF_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end
    // Next State Logic of the FSM:
    always_comb begin
        if(valvref_if.timeout_8ms_occured | (valvref_if.rx_sb_msg == TRAINERROR_Entry_req && valvref_if.rx_sb_msg_valid == 1'b1) | valvref_fail_flag) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start VALVREF FSM.
                VALVREF_IDLE: begin
                    if (valvref_if.valvref_en) next_state = VALVREF_START_REQ;
                    else next_state = VALVREF_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.VALVREFF start req}
                VALVREF_START_REQ: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_start_req && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_START_RESP;
                    else next_state = VALVREF_START_REQ;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.VALVREFF start resp}.
                VALVREF_START_RESP: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_start_resp && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_SET_VREF_CODE;
                    else next_state = VALVREF_START_RESP;
                end
                // (S3) Drive Vref (vref_code) to PHY MB Receiver Valid Lane.
                VALVREF_SET_VREF_CODE: begin
                    if (valvref_if.analog_settle_time_done) next_state = VALVREF_RX_D2C_PT;
                    else next_state = VALVREF_SET_VREF_CODE;
                end
                // (S4) Implement the test (Rx Init Data to Clock Point Test).
                VALVREF_RX_D2C_PT: begin
                    // if (d2c_if.d2c_timeout_or_error) next_state = TO_TRAINERROR;
                    if (d2c_if.test_d2c_done) next_state = VALVREF_LOG_RESULT;
                    else next_state = VALVREF_RX_D2C_PT;
                end
                // (S5) Log the current vref_code value if the received pattern on MB Receiver is valid.
                VALVREF_LOG_RESULT: begin
                    if (valvref_if.phy_rx_valvref_ctrl == MAX_VAL_VREF_CODE) next_state = VALVREF_CALC_APPLY;
                    else next_state = VALVREF_SET_VREF_CODE;
                end
                // (S6) Caluculate the best value for vref_code.
                VALVREF_CALC_APPLY: begin
                    next_state = VALVREF_END_REQ;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.VALVREFF end resp}. Also, drive Vref_code to the PHY MB Receiver Valid Lane.
                VALVREF_END_REQ: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_req && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_END_RESP;
                    else next_state = VALVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                VALVREF_END_RESP: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_resp && valvref_if.rx_sb_msg_valid == 1'b1) next_state = TO_DATAVREF;
                    else next_state = VALVREF_END_RESP;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                TO_DATAVREF: begin
                    next_state = (valvref_if.valvref_en)? TO_DATAVREF : VALVREF_IDLE; // Stay here till "ltsm_if.valvref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (valvref_if.valvref_en) ? TO_TRAINERROR : VALVREF_IDLE;
                end
                default: begin
                    next_state = (valvref_if.valvref_en) ? TO_TRAINERROR : VALVREF_IDLE; // Default case to avoid latches in synthesis.
                end
            endcase
        end
    end
    // Output logic based on current state:
    always_comb begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//
        //==========================
        // LTSM -> LTSM signals:
        //==========================
        valvref_if.valvref_done   = 1'b0;
        valvref_if.trainerror_req = 1'b0;
        valvref_if.update_lane_mask = 1'b0;
        //==========================
        // Timers:
        //==========================
        valvref_if.timeout_timer_en       = 1;
        valvref_if.analog_settle_timer_en = 0;
        //=================================================
        // Control Signals For (Rx init D to C point test):
        //=================================================
        d2c_if.rx_pt_en = 1'b0; // To enable Rx init Data to Clock Point Test
        d2c_if.tx_pt_en = 1'b0; // To enable Tx init Data to Clock Point Test
        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'b00;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_lfsr_en          = 1'b0  ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        d2c_if.d2c_pattern_setup    = 3'b010; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        d2c_if.d2c_data_pattern_sel = 2'b11 ; // Data pattern used during training: LFSR, ID, or all 0.
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // 0: VALTRAIN pattern, 1: Held Low.
        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        d2c_if.d2c_burst_count  = D2C_BURST_COUNT; // Burst Count: Indicates the duration of selected pattern (UI count).
        d2c_if.d2c_idle_count   = 16'D0          ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        d2c_if.d2c_iter_count   = D2C_ITER_COUNT ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D2; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        valvref_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        valvref_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        valvref_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        valvref_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        valvref_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        valvref_if.mb_rx_data_lane_sel = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        valvref_if.mb_rx_val_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        valvref_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).
        //============================
        // SB signals:
        //============================
        // For SB TX:
        valvref_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        valvref_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state: Wait for the trigger to start VALVREF FSM.
            VALVREF_IDLE: begin
                //Nothing special
                valvref_if.timeout_timer_en = 0;
            end
            // (S1) Send & Receive SB Message: {MBTRAIN.VALVREF start req}
            VALVREF_START_REQ: begin
                valvref_if.update_lane_mask = 1'b1; // Tell the MBTRAIN.REPAIR substate to update the value of "mb_(rx/tx)_data_lane_mask" to take the value of "mbinit_(rx/tx)_data_lane_mask". It's used in the begining of the MBTRAIN.

                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)      ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_start_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0                    ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0                    ; // Data field of the SB message.
            end
            // (S2) Send & Receive SB Message: {MBTRAIN.VALVREF start resp}.
            VALVREF_START_RESP: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)       ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_start_resp; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S3) Drive Vref (vref_code) to PHY MB Receiver Valid Lane.
            VALVREF_SET_VREF_CODE: begin
                valvref_if.analog_settle_timer_en = 1;
            end
            // (S4) Implement the test (Rx Init Data to Clock Point Test).
            VALVREF_RX_D2C_PT: begin
                //=================================================
                // Control Signals For (Rx init D to C point test):
                //=================================================
                d2c_if.rx_pt_en = 1'b1; // To enable Rx init Data to Clock Point Test.
            end
            // (S5) Log the current vref_code value if the received pattern on MB Receiver is valid.
            VALVREF_LOG_RESULT: begin
                // There is only sequential logic here. we just log Vref of Valid lane (if was no valid lane error).
                // look at "VALVREF_LOG_RESULT_PROC" always block below.
            end
            // (S6) Caluculate the best value for vref_code.
            VALVREF_CALC_APPLY: begin
                // There is only sequential logic here. we calculate the best Vref value.
                // look at "VALVREF_CALC_APPLY_PROC" always block below.
            end
            // (S7) Send & Receive SB Message: {MBTRAIN.VALVREFF end resp}. Also, drive Vref_code to the PHY MB Receiver Valid Lane.
            VALVREF_END_REQ: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)    ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            VALVREF_END_RESP: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)     ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_resp; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            TO_DATAVREF: begin
                valvref_if.valvref_done     = 1'b1;
                valvref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                valvref_if.valvref_done     = 1'b1;
                valvref_if.trainerror_req   = 1'b1;
                valvref_if.timeout_timer_en = 1'b0;
            end
            default: begin
                // Default case to avoid latches in synthesis.
            end
        endcase
    end
    // =====================================================================
    // Vref sweep data-path registers
    //
    // Unified signal names (for cross-module readability):
    //   phy_rx_valvref_ctrl     <-> swept_code_r  -- the Vref code swept (S3-S5 loop)
    //                                               and applied value after CALC_APPLY.
    //   is_in_valid_region      <-> zone_valid    -- 1 while inside a contiguous pass zone
    //   vref_code_filled        <-> found_pass    -- 1 once any passing code seen
    //   temp_min_vref           <-> zone_min_r    -- start of the current contiguous pass zone
    //   min_vref_code           <-> best_lo       -- left  edge of widest pass window
    //   max_vref_code           <-> best_hi       -- right edge of widest pass window
    //   (no separate best_code_r: result written directly to phy_rx_valvref_ctrl)
    //
    // Two-zone algorithm (same as DATAVREF / DTVREF companion modules):
    //   Zone A (new contiguous pass zone starts):
    //     is_in_valid_region 0->1; save temp_min_vref = phy_rx_valvref_ctrl.
    //     First-ever pass (vref_code_filled==0): seed min/max_vref_code.
    //   Zone B (extending the contiguous pass zone):
    //     If current zone wider than best window: update min/max_vref_code.
    //   Fail: is_in_valid_region -> 0 (hole in Valid-lane Vref eye diagram).
    // =====================================================================
    wire [VREF_CODE_WIDTH-1:0] vref_range;      // width of best recorded window
    wire [VREF_CODE_WIDTH-1:0] temp_vref_range; // width of current contiguous zone
    reg  [VREF_CODE_WIDTH-1:0] temp_min_vref;   // (zone_min_r) start of current zone
    reg  [VREF_CODE_WIDTH-1:0] min_vref_code;   // (best_lo) left  edge of widest window
    reg  [VREF_CODE_WIDTH-1:0] max_vref_code;   // (best_hi) right edge of widest window
    reg                        vref_code_filled; // (found_pass) at least one pass seen
    // vref_range: best window width (0 if no passing code seen yet).
    assign vref_range      = (vref_code_filled == 1'b1) ? (max_vref_code - min_vref_code) : '0;
    // temp_vref_range: current zone width (distance from zone start to current code).
    assign temp_vref_range = (valvref_if.phy_rx_valvref_ctrl - temp_min_vref);
    assign valvref_fail_flag = (current_state == VALVREF_CALC_APPLY) & (~vref_code_filled);
    // =====================================================================
    // Sequential: swept_code_r (phy_rx_valvref_ctrl) increment and apply
    //
    // In this module phy_rx_valvref_ctrl serves dual purpose:
    //   During sweep (S3-S5): driven with the current Vref code.
    //   After CALC_APPLY    : holds the computed midpoint (best Vref center).
    // The LOG_RESULT block reads phy_rx_valvref_ctrl as swept_code_r.
    // =====================================================================
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin : VALVREF_CALC_APPLY_PROC
        if(!valvref_if.rst_n) begin
            valvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE; // Reset to safe Vref.
        end
        // Reset on re-entry (allows module reuse across multiple MBTRAIN passes).
        else if(current_state == VALVREF_START_REQ) begin
            valvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE;
        end
        // (S5) Advance swept_code_r: increment phy_rx_valvref_ctrl each LOG step.
        else if(current_state == VALVREF_LOG_RESULT) begin
            if(valvref_if.phy_rx_valvref_ctrl != MAX_VAL_VREF_CODE) begin
                valvref_if.phy_rx_valvref_ctrl <= valvref_if.phy_rx_valvref_ctrl + 1;
            end
        end
        // (S6) Compute and apply the optimal Vref midpoint.
        //      Spec eq.: vref_code = (min_vref_code + max_vref_code) / 2
        //      i.e.      best_code_r = (best_lo + best_hi) / 2
        else if(current_state == VALVREF_CALC_APPLY) begin
            if(vref_code_filled == 1'b1) begin
                valvref_if.phy_rx_valvref_ctrl <= ({1'b0, min_vref_code} + {1'b0, max_vref_code}) >> 1;
            end
            else begin
                valvref_if.phy_rx_valvref_ctrl <= '0; // No passing code: safe default
            end
        end
    end
    reg is_in_valid_region; // (zone_valid) 1 while inside a contiguous pass zone.
    // =====================================================================
    // Sequential: two-zone eye-map tracking for Valid-lane Vref sweep
    //
    // Signal names (unified with DATAVREF / DTVREF companion modules):
    //   valvref_if.phy_rx_valvref_ctrl <-> swept_code_r (both sweep and result)
    //   is_in_valid_region             <-> zone_valid
    //   vref_code_filled               <-> found_pass
    //   temp_min_vref                  <-> zone_min_r
    //   min_vref_code                  <-> best_lo
    //   max_vref_code                  <-> best_hi
    //
    // Zone A (new contiguous pass zone starts):
    //   is_in_valid_region 0->1; temp_min_vref = current code (= zone_min_r).
    //   If first-ever pass (vref_code_filled==0): seed min/max_vref_code (best_lo/hi).
    // Zone B (extending the contiguous pass zone):
    //   If temp_vref_range (zone_range) > vref_range (best_range):
    //     update min_vref_code (best_lo) and max_vref_code (best_hi).
    // Fail: is_in_valid_region -> 0 (hole detected in Valid-lane Vref eye).
    // =====================================================================
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin : VALVREF_LOG_RESULT_PROC
        if(!valvref_if.rst_n) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <=   '0;
        end
        else if(current_state == VALVREF_START_REQ) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'd0;
            temp_min_vref      <=   '0;
        end
        else if(current_state == VALVREF_LOG_RESULT) begin
            // ─── PASS: d2c_val_err == 0 ──────────────────────────────────────
            if (!d2c_if.d2c_val_err) begin
                // Zone A: entering a fresh contiguous pass zone.
                // Handles two sub-cases:
                //   a) After a fail (is_in_valid_region was 0).
                //   b) At the very first code (MIN_VAL_VREF_CODE): always start Zone A
                //      to reset zone tracking (prevents stale zone_min_r from prior run).
                if (!is_in_valid_region || valvref_if.phy_rx_valvref_ctrl == MIN_VAL_VREF_CODE) begin
                    is_in_valid_region <= 1'b1; // mark zone active (zone_valid = 1)
                    temp_min_vref      <= valvref_if.phy_rx_valvref_ctrl; // save zone start (zone_min_r)
                    if (!vref_code_filled) begin
                        // Very first passing code: seed best window (best_lo = best_hi = swept_code_r).
                        vref_code_filled <= 1'b1; // found_pass = 1
                        min_vref_code    <= valvref_if.phy_rx_valvref_ctrl; // best_lo
                        max_vref_code    <= valvref_if.phy_rx_valvref_ctrl; // best_hi
                    end
                end
                // Zone B: still inside the current contiguous pass zone.
                // Update best window only if current zone is wider than last best.
                // (temp_vref_range = zone_range, vref_range = best_range)
                else begin
                    if ((temp_vref_range) > (vref_range)) begin
                        min_vref_code <= temp_min_vref                 ; // best_lo = zone_min_r
                        max_vref_code <= valvref_if.phy_rx_valvref_ctrl; // best_hi = swept_code_r
                    end
                end
            end
            // ─── FAIL: d2c_val_err == 1 ──────────────────────────────────────
            // Hole in the Valid-lane Vref eye: close the current contiguous zone.
            // Zone A will restart on the next passing code.
            else begin
                is_in_valid_region <= 1'b0; // zone_valid = 0
            end
        end
    end
endmodule
