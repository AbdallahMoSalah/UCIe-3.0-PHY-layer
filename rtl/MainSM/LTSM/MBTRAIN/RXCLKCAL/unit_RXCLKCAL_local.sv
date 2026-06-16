// ====================================================================================================
// Module      : unit_RXCLKCAL_local
// Purpose     : MBTRAIN.RXCLKCAL sub-state FSM (Local/Initiator Side).
//               Performs Receiver Clock Calibration (IQ alignment) at target speed.
// ====================================================================================================
// Sideband Messages Used (Local):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.RXCLKCAL start req}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL start resp}            | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL done req}              | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL done resp}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR Entry req}                   | In  (RX)  | From partner                              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RXCLKCAL_local
    import UCIe_pkg::*;
    (
        // Clock and Reset
        input  logic        lclk,
        input  logic        rst_n,
        input  logic        soft_rst_n,

        // Control and Status
        input  logic        rxclkcal_en,
        output logic        rxclkcal_done,
        output logic        trainerror_req,

        // Link Configuration
        input  logic        is_high_speed,          // 1 = operating speed > 32 GT/s

        // PHY Lock Controls
        output logic        phy_rx_clock_lock_en,
        output logic        phy_rx_track_lock_en,

        // Interface to separated IQ Local sub-module
        output logic        iq_en,
        input  logic        iq_done,
        input  logic        iq_error,

        // MB RX Lane Control Outputs (Local FSM controls receiver settings)
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // Timer Interface
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // Sideband Interface
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo
    );

    // ============================================================================
    // State Encoding
    // ============================================================================
    typedef enum logic [3:0] {
        RXCLKCAL_LCL_IDLE              = 4'h0,
        RXCLKCAL_LCL_SEND_START_REQ    = 4'h1,
        RXCLKCAL_LCL_WAIT_START_RESP   = 4'h2,
        RXCLKCAL_LCL_INIT_LOCK         = 4'h3,
        RXCLKCAL_LCL_IQ_LOOP           = 4'h4,
        RXCLKCAL_LCL_SEND_DONE_REQ     = 4'h5,
        RXCLKCAL_LCL_WAIT_DONE_RESP    = 4'h6,
        RXCLKCAL_LCL_TO_VALTRAINCENTER = 4'h7,
        RXCLKCAL_LCL_TO_TRAINERROR     = 4'h8
    } state_t;

    state_t current_state, next_state;

    // ============================================================================
    // State Transitions
    // ============================================================================
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= RXCLKCAL_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= RXCLKCAL_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;

        // Global Error Override
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = RXCLKCAL_LCL_TO_TRAINERROR;
        end
        else if (!rxclkcal_en) begin
            next_state = RXCLKCAL_LCL_IDLE;
        end
        else begin
            case (current_state)
                RXCLKCAL_LCL_IDLE: begin
                    next_state = RXCLKCAL_LCL_SEND_START_REQ;
                end

                RXCLKCAL_LCL_SEND_START_REQ: begin
                    next_state = RXCLKCAL_LCL_WAIT_START_RESP;
                end

                RXCLKCAL_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_start_resp)
                        next_state = RXCLKCAL_LCL_INIT_LOCK;
                end

                RXCLKCAL_LCL_INIT_LOCK: begin
                    if (analog_settle_time_done) begin
                        if (is_high_speed) // speed > 32 GT/s
                            next_state = RXCLKCAL_LCL_IQ_LOOP;
                        else
                            next_state = RXCLKCAL_LCL_SEND_DONE_REQ;
                    end
                end

                RXCLKCAL_LCL_IQ_LOOP: begin
                    if (iq_done) begin
                        if (iq_error)
                            next_state = RXCLKCAL_LCL_TO_TRAINERROR;
                        else
                            next_state = RXCLKCAL_LCL_SEND_DONE_REQ;
                    end
                end

                RXCLKCAL_LCL_SEND_DONE_REQ: begin
                    next_state = RXCLKCAL_LCL_WAIT_DONE_RESP;
                end

                RXCLKCAL_LCL_WAIT_DONE_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_done_resp)
                        next_state = RXCLKCAL_LCL_TO_VALTRAINCENTER;
                end

                RXCLKCAL_LCL_TO_VALTRAINCENTER: begin
                    next_state = RXCLKCAL_LCL_TO_VALTRAINCENTER;
                end

                RXCLKCAL_LCL_TO_TRAINERROR: begin
                    next_state = RXCLKCAL_LCL_TO_TRAINERROR;
                end

                default: next_state = RXCLKCAL_LCL_IDLE;
            endcase
        end
    end

    // ============================================================================
    // Output Logic
    // ============================================================================
    always_comb begin
        // Safe Defaults
        rxclkcal_done          = 1'b0;
        trainerror_req         = 1'b0;
        phy_rx_clock_lock_en   = 1'b0;
        phy_rx_track_lock_en   = 1'b0;
        iq_en                  = 1'b0;
        mb_rx_clk_lane_sel     = 1'b0;
        mb_rx_trk_lane_sel     = 1'b0;
        analog_settle_timer_en = 1'b0;

        tx_sb_msg_valid        = 1'b0;
        tx_sb_msg              = NOTHING;
        tx_msginfo             = 16'h0;
        tx_data_field          = 64'h0;

        case (current_state)
            RXCLKCAL_LCL_IDLE: begin
                // Idle
            end

            RXCLKCAL_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXCLKCAL_start_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            RXCLKCAL_LCL_WAIT_START_RESP: begin
                // Waiting for response
            end

            RXCLKCAL_LCL_INIT_LOCK: begin
                phy_rx_clock_lock_en   = 1'b1;
                phy_rx_track_lock_en   = 1'b1;
                mb_rx_clk_lane_sel     = 1'b1;
                mb_rx_trk_lane_sel     = 1'b1;
                analog_settle_timer_en = 1'b1;
            end

            RXCLKCAL_LCL_IQ_LOOP: begin
                phy_rx_clock_lock_en = 1'b1;
                phy_rx_track_lock_en = 1'b1;
                mb_rx_clk_lane_sel   = 1'b1;
                mb_rx_trk_lane_sel   = 1'b1;
                iq_en                = 1'b1;
            end

            RXCLKCAL_LCL_SEND_DONE_REQ: begin
                phy_rx_clock_lock_en = 1'b1;
                phy_rx_track_lock_en = 1'b1;
                mb_rx_clk_lane_sel   = 1'b1;
                mb_rx_trk_lane_sel   = 1'b1;
                tx_sb_msg_valid      = 1'b1;
                tx_sb_msg            = MBTRAIN_RXCLKCAL_done_req;
                tx_msginfo           = 16'h0;
                tx_data_field        = 64'h0;
            end

            RXCLKCAL_LCL_WAIT_DONE_RESP: begin
                phy_rx_clock_lock_en = 1'b1;
                phy_rx_track_lock_en = 1'b1;
                mb_rx_clk_lane_sel   = 1'b1;
                mb_rx_trk_lane_sel   = 1'b1;
            end

            RXCLKCAL_LCL_TO_VALTRAINCENTER: begin
                rxclkcal_done = 1'b1;
            end

            RXCLKCAL_LCL_TO_TRAINERROR: begin
                rxclkcal_done  = 1'b1;
                trainerror_req = 1'b1;
            end
        endcase
    end

endmodule
