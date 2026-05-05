// `timescale 1ps/1ps
module unit_DATAVREF #(
        parameter MAX_DATA_VREF_CODE  = 7'D127,
        parameter MIN_DATA_VREF_CODE  = 7'D10
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.datavref_mp datavref_if,

        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    // For analog Voltage control.
    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE);

    // To get the used SB messages for: (datavref_if.tx_sb_msg, sb_it.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATAVREF_start_req ; // Msg Number: d39
    import UCIe_pkg::MBTRAIN_DATAVREF_start_resp; // Msg Number: d40
    import UCIe_pkg::MBTRAIN_DATAVREF_end_req   ; // Msg Number: d41
    import UCIe_pkg::MBTRAIN_DATAVREF_end_resp  ; // Msg Number: d42
    import UCIe_pkg::TRAINERROR_Entry_req       ; // Msg Number: d107
    import UCIe_pkg::NOTHING                    ; // Msg Number: 8'hFF

    // States names
    localparam DATAVREF_IDLE          = 4'h0, // (S0)
    DATAVREF_START_REQ     = 4'h1, // (S1)
    DATAVREF_START_RESP    = 4'h2, // (S2)
    DATAVREF_SET_VREF_CODE = 4'h3, // (S3)
    DATAVREF_RX_D2C_PT     = 4'h4, // (S4)
    DATAVREF_LOG_RESULT    = 4'h5, // (S5)
    DATAVREF_CALC_APPLY    = 4'h6, // (S6)
    DATAVREF_END_REQ       = 4'h7, // (S7)
    DATAVREF_END_RESP      = 4'h8, // (S8)
    TO_SPEEDIDLE           = 4'h9, // (S9)
    TO_TRAINERROR          = 4'hA; // (S10)

    reg [3:0] current_state, next_state; // The Current, Next states of the FSM.
    wire is_tx_sb_data_valid;

    // ====================================================================
    // Vref sweep data-path registers (per-lane, 16 lanes)
    //
    // Unified signal names mirroring VALVREF / DTVREF companion modules:
    //   swept_code_r    <-> current_vref_code  -- Vref code being swept (S3-S5 loop)
    //   zone_valid[l]   <-> is_in_valid_region -- 1 while inside a contiguous pass zone
    //   found_pass[l]   <-> vref_code_filled   -- 1 once any passing code seen for lane l
    //   zone_min_r[l]   <-> temp_min_vref      -- start of the current contiguous pass zone
    //   best_lo[l]      <-> min_vref_code      -- left  edge of widest pass window
    //   best_hi[l]      <-> max_vref_code      -- right edge of widest pass window
    //   best_vref_code[l]                      -- midpoint applied after CALC_APPLY
    //
    // Two-zone algorithm (same logic as VALVREF_LOG_RESULT_PROC):
    //   Zone A (new contiguous pass zone starts):
    //     -> set zone_valid[l], save zone_min_r[l] = swept_code_r.
    //     -> if first-ever pass (found_pass[l]==0): seed best_lo/hi, set found_pass.
    //   Zone B (extending a contiguous pass zone):
    //     -> if current zone wider than best window: update best_lo/hi.
    //   Fail: zone_valid[l] -> 0 (hole in the lane's Vref eye diagram).
    // ====================================================================
    reg [DATA_VREF_CODE_WIDTH-1:0] swept_code_r; // Vref code currently being swept

    // Per-lane eye-map tracking arrays (indexed [lane])
    wire [DATA_VREF_CODE_WIDTH-1:0] best_range     [15:0]; // width of best window
    wire [DATA_VREF_CODE_WIDTH-1:0] zone_range     [15:0]; // width of current zone
    reg  [DATA_VREF_CODE_WIDTH-1:0] zone_min_r     [15:0]; // start of current zone (zone_min_r)
    reg  [DATA_VREF_CODE_WIDTH-1:0] best_lo        [15:0]; // left  edge (min_vref_code)
    reg  [DATA_VREF_CODE_WIDTH-1:0] best_hi        [15:0]; // right edge (max_vref_code)
    reg  [15:0] found_pass;   // 1b per lane: at least one pass code seen
    reg  [15:0] zone_valid;   // 1b per lane: currently inside a contiguous pass zone

    reg  [DATA_VREF_CODE_WIDTH-1:0] best_vref_code [15:0]; // applied midpoint after CALC_APPLY

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign is_tx_sb_data_valid = (current_state == next_state);


    // Current State Logic of the FSM:
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n) begin
        if (!datavref_if.rst_n) begin
            current_state  <= DATAVREF_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end

    // Next State Logic of the FSM:
    always_comb begin
        if (datavref_if.timeout_8ms_occured | (datavref_if.rx_sb_msg == TRAINERROR_Entry_req && datavref_if.rx_sb_msg_valid == 1'b1)) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start DATAVREF FSM.
                DATAVREF_IDLE: begin
                    if (datavref_if.datavref_en) next_state = DATAVREF_START_REQ;
                    else next_state = DATAVREF_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
                DATAVREF_START_REQ: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_start_req && datavref_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_START_RESP;
                    else next_state = DATAVREF_START_REQ;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
                DATAVREF_START_RESP: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_start_resp && datavref_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_SET_VREF_CODE;
                    else next_state = DATAVREF_START_RESP;
                end
                // (S3) Drive Vref (swept_code_r) to PHY MB Receiver Data Lanes.
                DATAVREF_SET_VREF_CODE: begin
                    if (datavref_if.analog_settle_time_done) next_state = DATAVREF_RX_D2C_PT;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S4) Implement the test (Rx Init Data to Clock Point Test).
                DATAVREF_RX_D2C_PT: begin
                    if (d2c_if.test_d2c_done) next_state = DATAVREF_LOG_RESULT;
                    else next_state = DATAVREF_RX_D2C_PT;
                end
                // (S5) Log the current vref_code value if the received pattern on MB Receiver Data Lanes is valid.
                DATAVREF_LOG_RESULT: begin
                    if (swept_code_r == MAX_DATA_VREF_CODE) next_state = DATAVREF_CALC_APPLY;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S6) Caluculate the best value for vref_code for all 16 lanes independently.
                DATAVREF_CALC_APPLY: begin
                    next_state = DATAVREF_END_REQ;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.DATAVREF end req}.
                DATAVREF_END_REQ: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_end_req && datavref_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_END_RESP;
                    else next_state = DATAVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
                DATAVREF_END_RESP: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_end_resp && datavref_if.rx_sb_msg_valid == 1'b1) next_state = TO_SPEEDIDLE;
                    else next_state = DATAVREF_END_RESP;
                end
                // (S9) Next sub-state.
                TO_SPEEDIDLE: begin
                    next_state = (datavref_if.datavref_en)? TO_SPEEDIDLE : DATAVREF_IDLE; // Stay here till "datavref_if.datavref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (datavref_if.datavref_en)? TO_TRAINERROR : DATAVREF_IDLE;
                end
                default: begin
                    next_state = (datavref_if.datavref_en)? TO_TRAINERROR : DATAVREF_IDLE; // Default case to avoid latches in synthesis.
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
        datavref_if.datavref_done  = 1'b0;
        datavref_if.trainerror_req = 1'b0;

        //==========================
        // Timers:
        //==========================
        datavref_if.timeout_timer_en       = 1;
        datavref_if.analog_settle_timer_en = 0;

        //=================================================
        // Control Signals For (Rx init D to C point test):
        //=================================================
        d2c_if.rx_pt_en = 1'b0; // To enable Rx init Data to Clock Point Test
        d2c_if.tx_pt_en = 1'b0; // To enable Tx init Data to Clock Point Test

        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'd0;  // Clock Phase control: Eye Center only.

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_lfsr_en          = 1'b0  ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        d2c_if.d2c_pattern_setup    = 3'b011; // Data Pattern
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // Data pattern used during training: LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b1  ; // Held Low (don't care for data lanes)

        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        d2c_if.d2c_burst_count  = 16'D1  ; // Burst Count: Indicates the duration of selected pattern (UI count).
        d2c_if.d2c_idle_count   = 16'D0  ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        d2c_if.d2c_iter_count   = 16'D128; // Iteration Count: Indicates the iteration count of bursts followed by idle.

        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D0; // 0: Per-Lane Comparison


        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        datavref_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        datavref_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        datavref_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        datavref_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        datavref_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        datavref_if.mb_rx_data_lane_sel = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        datavref_if.mb_rx_val_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        datavref_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).


        //============================
        // SB signals:
        //============================
        // For SB TX:
        datavref_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        datavref_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state
            DATAVREF_IDLE: begin
                datavref_if.timeout_timer_en = 0;
            end
            // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
            DATAVREF_START_REQ: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_data_valid)     ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_req; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
            DATAVREF_START_RESP: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_data_valid)      ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_resp; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S3) Drive Vref
            DATAVREF_SET_VREF_CODE: begin
                datavref_if.analog_settle_timer_en = 1;
            end
            // (S4) Implement the test (Rx Init Data to Clock Point Test).
            DATAVREF_RX_D2C_PT: begin
                d2c_if.rx_pt_en = 1'b1; // To enable Rx init Data to Clock Point Test.
            end
            DATAVREF_LOG_RESULT: begin
                // Sequential logic handled in DATAVREF_LOG_RESULT_PROC
            end
            DATAVREF_CALC_APPLY: begin
                // Sequential logic handled in DATAVREF_CALC_APPLY_PROC
            end
            // (S7) Send & Receive SB Message: {MBTRAIN.DATAVREF end req}
            DATAVREF_END_REQ: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_data_valid)   ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_req; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
            DATAVREF_END_RESP: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_data_valid)    ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_resp; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S9) Next Sub-state
            TO_SPEEDIDLE: begin
                datavref_if.datavref_done    = 1'b1;
                datavref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                datavref_if.datavref_done    = 1'b1;
                datavref_if.trainerror_req   = 1'b1;
                datavref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            default: begin
            end
        endcase
    end
    // ==================================================
    // ==================================================
    // MB Lane Control
    // To convert the "mb_rx_data_lane_mask" from 3 bits to 16 bits, we use "negotiated_data_lanes".
    // 000b:  None (Degrade not possible)
    // 001b: Logical Lanes 0 to 7
    // 010b: Logical Lanes 8 to 15
    // 011b: Logical Lanes 0 to 15
    // 100b: Logical Lanes 0 to 3
    // 101b: Logical Lanes 4 to 7
    logic [15:0] negotiated_data_lanes;
    always @(*) begin
        case(datavref_if.mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    genvar lane;
    generate
        for(lane=0; lane<16; lane=lane+1) begin : VREF_RANGE_GEN
            // best_range[l]: width of the best recorded pass window for lane l.
            assign best_range[lane] = (found_pass[lane] == 1'b1) ?
                (best_hi[lane] - best_lo[lane]) : '0;
            // zone_range[l]: width of the current contiguous pass zone for lane l.
            assign zone_range[lane] = (swept_code_r - zone_min_r[lane]);

            // Drive swept_code_r to PHY during the sweep states (S1-S5),
            // then switch to the per-lane best midpoint (best_vref_code) afterwards.
            assign datavref_if.phy_rx_datavref_ctrl[lane] = (current_state == DATAVREF_START_REQ     ||
                    current_state == DATAVREF_START_RESP    ||
                    current_state == DATAVREF_SET_VREF_CODE ||
                    current_state == DATAVREF_RX_D2C_PT     ||
                    current_state == DATAVREF_LOG_RESULT) ? swept_code_r : best_vref_code[lane];
        end
    endgenerate

    // =====================================================================
    // Sequential: swept_code_r counter and per-lane best_vref_code apply
    //
    // This block manages:
    //   1. Reset of swept_code_r at the start of each calibration run (S1).
    //   2. Increment of swept_code_r on every LOG_RESULT cycle (S5).
    //   3. Compute per-lane best midpoint in CALC_APPLY (S6) and record fail flag.
    // =====================================================================
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n) begin : DATAVREF_CODE_AND_CALC_PROC
        integer j;
        if(!datavref_if.rst_n) begin
            swept_code_r                   <= MIN_DATA_VREF_CODE;
            // datavref_if.datavref_fail_flag <= 1'b0;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        else if(current_state == DATAVREF_START_REQ) begin
            // Reset swept_code_r and applied values at the start of each run.
            swept_code_r                   <= MIN_DATA_VREF_CODE;
            // datavref_if.datavref_fail_flag <= 1'b0;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        // (S5) Advance the Vref sweep counter after each test result is logged.
        else if(current_state == DATAVREF_LOG_RESULT) begin
            if(swept_code_r != MAX_DATA_VREF_CODE) begin
                swept_code_r <= swept_code_r + 1;
            end
        end
        // (S6) Compute the per-lane best Vref midpoint:
        //      best_vref_code[l] = (best_lo[l] + best_hi[l]) / 2
        //      Spec eq.: vref_code = (1st_success + last_success) / 2
        else if(current_state == DATAVREF_CALC_APPLY) begin
            for(j=0; j<16; j=j+1) begin
                if(found_pass[j] == 1'b1) begin
                    best_vref_code[j] <= ({1'b0, best_lo[j]} + {1'b0, best_hi[j]}) >> 1;
                end
                else begin
                    best_vref_code[j] <= '0; // No passing code: safe default
                end
            end

            // Fail flag: set if any negotiated lane has no passing Vref code.
            // (negotiated_data_lanes mask gates out non-active lanes.)
            // datavref_if.datavref_fail_flag <= ~( &(found_pass|(~negotiated_data_lanes)) );
        end
    end

    // =====================================================================
    // Sequential: per-lane two-zone eye-map tracking (LOG_RESULT)
    //
    // Same algorithm as VALVREF_LOG_RESULT_PROC, extended to 16 lanes.
    // Signal names (unified):
    //   zone_valid[l]  <-> is_in_valid_region[l]
    //   found_pass[l]  <-> vref_code_filled[l]
    //   zone_min_r[l]  <-> temp_min_vref[l]
    //   best_lo[l]     <-> min_vref_code[l]
    //   best_hi[l]     <-> max_vref_code[l]
    //   swept_code_r   <-> current_vref_code
    //
    // Zone A (new contiguous pass zone):
    //   zone_valid[l] 0->1; save zone_min_r[l]=swept_code_r.
    //   First-ever pass (found_pass[l]==0 & negotiated): seed best_lo/hi.
    // Zone B (continuing inside the pass zone):
    //   If zone_range[l] > best_range[l]: update best_lo[l]/best_hi[l].
    // Fail (hole detected):
    //   zone_valid[l] -> 0.
    // =====================================================================
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n) begin : DATAVREF_LOG_RESULT_PROC
        integer i;
        if(!datavref_if.rst_n) begin
            for(i=0; i<16; i=i+1) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                zone_min_r[i] <= '0;
            end
        end
        else if(current_state == DATAVREF_START_REQ) begin
            for(i=0; i<16; i=i+1) begin
                best_lo   [i] <= '0;
                best_hi   [i] <= '0;
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
                zone_min_r[i] <= '0;
            end
        end
        else if(current_state == DATAVREF_LOG_RESULT) begin
            for(i=0; i<16; i=i+1) begin
                if (!d2c_if.d2c_perlane_err[i]) begin
                    // PASS at swept_code_r for lane i
                    // Zone A: entering a new contiguous pass region.
                    if (!zone_valid[i]) begin
                        zone_valid[i] <= 1'b1; // mark zone active
                        zone_min_r[i] <= swept_code_r; // save zone start

                        if (!found_pass[i] && negotiated_data_lanes[i]) begin
                            // Very first passing code for this lane: seed the window.
                            found_pass[i] <= 1'b1;
                            best_lo[i]    <= swept_code_r;
                            best_hi[i]    <= swept_code_r;
                        end
                    end
                    // Zone B: extending the current contiguous pass zone.
                    // Update best window only if current zone is wider.
                    else begin
                        if (zone_range[i] > best_range[i]) begin
                            best_lo[i] <= zone_min_r[i];
                            best_hi[i] <= swept_code_r;
                        end
                    end
                end
                // FAIL at swept_code_r for lane i: close pass zone
                // (Hole in the Vref eye diagram - Zone A will restart on next pass)
                else begin
                    zone_valid[i] <= 1'b0;
                end
            end
        end
    end

endmodule
