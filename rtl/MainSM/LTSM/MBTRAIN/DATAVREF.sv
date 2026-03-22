`timescale 1ps/1ps
module DATAVREF #(
        parameter MAX_DATA_VREF_CODE  = 7'D127,
        parameter MIN_DATA_VREF_CODE  = 7'D10
    ) (
        // lclk and rst
        ltsm_if.clk_rst_mp clk_rst_if,

        // Timers.
        ltsm_if.state_timerout_8ms_mp        timeout_8ms_if        ,
        ltsm_if.state_analog_settle_timer_mp analog_settle_timer_if,

        // Control Signals For (Rx init D to C point test)
        ltsm_if.ltsm2d2c_mp d2c_if,

        // ltsm & MB & SB signals
        ltsm_if.datavref2ltsm_mp ltsm_if,
        ltsm_if.datavref2mb_mp   mb_if  ,
        ltsm_if.ltsm2sb_mp       sb_if

    );
    // For analog Voltage control.
    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE);

    // To get the used SB messages for: (sb_if.tx_sb_msg, sb_it.rx_sb_msg)
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

    reg [3:0] current_state, next_state, previous_state; // The Current, Next states, and Previous state of the FSM.
    wire data_incoherence;

    //================================
    // Calculate Vref Code:
    //================================
    reg [DATA_VREF_CODE_WIDTH-1:0] current_vref_code; // The code that is currently swept.

    // Arrays for each of the 16 lanes
    wire [DATA_VREF_CODE_WIDTH-1:0] vref_range [15:0];
    wire [DATA_VREF_CODE_WIDTH-1:0] temp_vref_range [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] temp_min_vref [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] min_vref_code [15:0];
    reg  [DATA_VREF_CODE_WIDTH-1:0] max_vref_code [15:0];
    reg  [15:0] vref_code_filled;
    reg  [15:0] is_in_valid_region;

    reg  [DATA_VREF_CODE_WIDTH-1:0] best_vref_code [15:0];
    // reg  [15:0] lane_fail_flag;

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;


    // Current State Logic of the FSM:
    always @(posedge clk_rst_if.lclk or negedge clk_rst_if.rst_n) begin
        if (!clk_rst_if.rst_n) begin
            current_state  <= DATAVREF_IDLE;
            previous_state <= DATAVREF_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if (timeout_8ms_if.timeout_8ms_occured | (sb_if.rx_sb_msg == TRAINERROR_Entry_req && sb_if.rx_sb_msg_valid == 1'b1)) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start DATAVREF FSM.
                DATAVREF_IDLE: begin
                    if (ltsm_if.datavref_en) next_state = DATAVREF_START_REQ;
                    else next_state = DATAVREF_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
                DATAVREF_START_REQ: begin
                    if (sb_if.rx_sb_msg == MBTRAIN_DATAVREF_start_req && sb_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_START_RESP;
                    else next_state = DATAVREF_START_REQ;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
                DATAVREF_START_RESP: begin
                    if (sb_if.rx_sb_msg == MBTRAIN_DATAVREF_start_resp && sb_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_SET_VREF_CODE;
                    else next_state = DATAVREF_START_RESP;
                end
                // (S3) Drive Vref (current_vref_code) to PHY MB Receiver Data Lanes.
                DATAVREF_SET_VREF_CODE: begin
                    if (analog_settle_timer_if.analog_settle_time_done) next_state = DATAVREF_RX_D2C_PT;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S4) Implement the test (Rx Init Data to Clock Point Test).
                DATAVREF_RX_D2C_PT: begin
                    if (d2c_if.test_d2c_done) next_state = DATAVREF_LOG_RESULT;
                    else next_state = DATAVREF_RX_D2C_PT;
                end
                // (S5) Log the current vref_code value if the received pattern on MB Receiver Data Lanes is valid.
                DATAVREF_LOG_RESULT: begin
                    if (current_vref_code == MAX_DATA_VREF_CODE) next_state = DATAVREF_CALC_APPLY;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S6) Caluculate the best value for vref_code for all 16 lanes independently.
                DATAVREF_CALC_APPLY: begin
                    next_state = DATAVREF_END_REQ;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.DATAVREF end req}.
                DATAVREF_END_REQ: begin
                    if (sb_if.rx_sb_msg == MBTRAIN_DATAVREF_end_req && sb_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_END_RESP;
                    else next_state = DATAVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
                DATAVREF_END_RESP: begin
                    if (sb_if.rx_sb_msg == MBTRAIN_DATAVREF_end_resp && sb_if.rx_sb_msg_valid == 1'b1) next_state = TO_SPEEDIDLE;
                    else next_state = DATAVREF_END_RESP;
                end
                // (S9) Next sub-state.
                TO_SPEEDIDLE: begin
                    next_state = (ltsm_if.datavref_en)? TO_SPEEDIDLE : DATAVREF_IDLE; // Stay here till "ltsm_if.datavref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = TO_TRAINERROR; // Stay in TRAINERROR state until reset.
                end
                default: begin
                    next_state = TO_TRAINERROR; // Default case to avoid latches in synthesis.
                end
            endcase
        end
    end


    // Output logic based on current state:
    always @(*) begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//

        //==========================
        // LTSM -> LTSM signals:
        //==========================
        ltsm_if.datavref_done  = 1'b0;
        ltsm_if.trainerror_req = 1'b0;

        //==========================
        // Timers:
        //==========================
        timeout_8ms_if.timeout_timer_en               = 1;
        analog_settle_timer_if.analog_settle_timer_en = 0;

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
        d2c_if.d2c_pattern_setup    = 3'b001; // Data Pattern
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
        mb_if.mb_tx_clk_lane_sel  = 2'b01; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        mb_if.mb_tx_data_lane_sel = 2'b01; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        mb_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        mb_if.mb_tx_trk_lane_sel  = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        mb_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        mb_if.mb_rx_data_lane_sel = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        mb_if.mb_rx_val_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        mb_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).


        //============================
        // SB signals:
        //============================
        // For SB TX:
        sb_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        sb_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        sb_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        sb_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state
            DATAVREF_IDLE: begin
                timeout_8ms_if.timeout_timer_en = 0;
            end
            // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
            DATAVREF_START_REQ: begin
                sb_if.tx_sb_msg_valid = (!data_incoherence)        ; // Tell the SB that the selected message is valid.
                sb_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_req; // Tell the Sideband the message that it should to send.
                sb_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                sb_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
            DATAVREF_START_RESP: begin
                sb_if.tx_sb_msg_valid = (!data_incoherence)         ; // Tell the SB that the selected message is valid.
                sb_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_resp; // Tell the Sideband the message that it should to send.
                sb_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                sb_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S3) Drive Vref
            DATAVREF_SET_VREF_CODE: begin
                analog_settle_timer_if.analog_settle_timer_en = 1;
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
                sb_if.tx_sb_msg_valid = (!data_incoherence)        ; // Tell the SB that the selected message is valid.
                sb_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_req; // Tell the Sideband the message that it should to send.
                sb_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                sb_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
            DATAVREF_END_RESP: begin
                sb_if.tx_sb_msg_valid = (!data_incoherence)        ; // Tell the SB that the selected message is valid.
                sb_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_resp; // Tell the Sideband the message that it should to send.
                sb_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                sb_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S9) Next Sub-state
            TO_SPEEDIDLE: begin
                ltsm_if.datavref_done = 1'b1;
            end
            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                ltsm_if.datavref_done  = 1'b1;
                ltsm_if.trainerror_req = 1'b1;
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
        case(ltsm_if.mb_rx_data_lane_mask)
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
            assign vref_range[lane]      = (vref_code_filled[lane] == 1'b1) ? (max_vref_code[lane] - min_vref_code[lane]) : '0;
            assign temp_vref_range[lane] = (current_vref_code - temp_min_vref[lane]);

            // Drive the sweeping current_vref_code during early active states, otherwise output the permanent best_vref_code.
            assign mb_if.phy_rx_datavref_ctrl[lane] = (current_state == DATAVREF_START_REQ     ||
                    current_state == DATAVREF_START_RESP    ||
                    current_state == DATAVREF_SET_VREF_CODE ||
                    current_state == DATAVREF_RX_D2C_PT     ||
                    current_state == DATAVREF_LOG_RESULT) ? current_vref_code : best_vref_code[lane];
        end
    endgenerate

    always @(posedge clk_rst_if.lclk or negedge clk_rst_if.rst_n) begin : DATAVREF_CALC_APPLY_PROC
        integer j;
        if(!clk_rst_if.rst_n) begin
            current_vref_code         <= MIN_DATA_VREF_CODE;
            ltsm_if.datavref_fail_flag <= 1'b0;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        else if(current_state == DATAVREF_START_REQ) begin
            current_vref_code         <= MIN_DATA_VREF_CODE;
            ltsm_if.datavref_fail_flag <= 1'b0;
            for(j=0; j<16; j=j+1) begin
                best_vref_code[j] <= MIN_DATA_VREF_CODE;
            end
        end
        // Change the Vref value:
        else if(current_state == DATAVREF_LOG_RESULT) begin
            if(current_vref_code != MAX_DATA_VREF_CODE) begin
                current_vref_code <= current_vref_code + 1;
            end
        end
        // Calculate the best Vref value for all 16 lanes independently:
        else if(current_state == DATAVREF_CALC_APPLY) begin
            for(j=0; j<16; j=j+1) begin
                if(vref_code_filled[j] == 1'b1) begin
                    best_vref_code[j] <= ({1'b0, min_vref_code[j]} + {1'b0, max_vref_code[j]}) >> 1;
                end
                else begin
                    best_vref_code[j] <= '0;
                end
            end

            // Fail if any lane (of the negotiated lanes) is not filled
            ltsm_if.datavref_fail_flag <= ~( &(vref_code_filled|(~negotiated_data_lanes)) );
        end
    end

    //=======================================
    // DATAVREF_LOG_RESULT: Log the Vref Code
    //=======================================
    always @(posedge clk_rst_if.lclk or negedge clk_rst_if.rst_n) begin : DATAVREF_LOG_RESULT_PROC
        integer i;
        if(!clk_rst_if.rst_n) begin
            for(i=0; i<16; i=i+1) begin
                min_vref_code[i]      <= '0;
                max_vref_code[i]      <= '0;
                vref_code_filled[i]   <= 1'b0;
                is_in_valid_region[i] <= 1'b0;
                temp_min_vref[i]      <= '0;
            end
        end
        else if(current_state == DATAVREF_START_REQ) begin
            for(i=0; i<16; i=i+1) begin
                min_vref_code[i]      <= '0;
                max_vref_code[i]      <= '0;
                vref_code_filled[i]   <= 1'b0;
                is_in_valid_region[i] <= 1'b0;
                temp_min_vref[i]      <= '0;
            end
        end
        else if(current_state == DATAVREF_LOG_RESULT) begin
            for(i=0; i<16; i=i+1) begin
                // Check if the current lane is successful (No error)
                if (!d2c_if.d2c_perlane_err[i]) begin
                    // 1. If we start a new connected Vref valid region
                    if (!is_in_valid_region[i] || current_vref_code == MIN_DATA_VREF_CODE) begin
                        is_in_valid_region[i] <= 1'b1; // start new zone.
                        temp_min_vref[i]      <= current_vref_code;

                        if (!vref_code_filled[i] && negotiated_data_lanes[i]) begin
                            vref_code_filled[i] <= 1'b1;
                            min_vref_code[i]    <= current_vref_code;
                            max_vref_code[i]    <= current_vref_code;
                        end
                    end
                    // 2. If we continue within a current success zone
                    else begin
                        if ((temp_vref_range[i]) > (vref_range[i])) begin
                            min_vref_code[i] <= temp_min_vref[i];
                            max_vref_code[i] <= current_vref_code;
                        end
                    end
                end
                // The result was "Fail" for this lane
                else begin
                    is_in_valid_region[i] <= 1'b0;
                end
            end
        end
    end

endmodule