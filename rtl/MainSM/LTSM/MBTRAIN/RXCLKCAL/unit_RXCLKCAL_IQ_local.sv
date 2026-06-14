// ====================================================================================================
// Module      : unit_RXCLKCAL_IQ_local
// Purpose     : MBTRAIN.RXCLKCAL IQ Phase Calibration FSM (Local/Initiator Side).
//               Manages the quarter-rate clock in-phase/quadrature (IQ) correction loop.
// ====================================================================================================
// Sideband Messages Used (IQ Local):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.RXCLKCAL TCKN_L shift req}      | Out (TX)  | MsgInfo: [5:1]=shift; [0]=direction       |
// | {MBTRAIN.RXCLKCAL TCKN_L shift resp}     | In  (RX)  | MsgInfo: [0]=status (0=OK, 1=OutRange)    |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RXCLKCAL_IQ_local
    import UCIe_pkg::*;
    (
        // Clock and Reset
        input  logic        lclk,
        input  logic        rst_n,
        input  logic        soft_rst_n,

        // Interface with Main Local FSM
        input  logic        iq_en,                  // Enable from main Local FSM
        output logic        iq_done,                // Completed (either success or error)
        output logic        iq_error,               // Error (partner Out of Range)

        // PHY Controls & Status
        output logic        phy_rx_phase_detector_en,
        input  logic [4:0]  phy_rx_tckn_shift,      // Current residual shift needed
        input  logic        phy_rx_decrement_shift, // Direction of residual shift

        // Timer Interface
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // Sideband Interface
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo
    );

    // ============================================================================
    // State Encoding
    // ============================================================================
    typedef enum logic [2:0] {
        IQ_LCL_IDLE             = 3'h0,
        IQ_LCL_MEASURE          = 3'h1,
        IQ_LCL_EVAL             = 3'h2,
        IQ_LCL_SEND_SHIFT_REQ   = 3'h3,
        IQ_LCL_WAIT_RESP        = 3'h4,
        IQ_LCL_SETTLE           = 3'h5,
        IQ_LCL_DONE_SUCCESS     = 3'h6,
        IQ_LCL_DONE_ERROR       = 3'h7
    } state_t;

    state_t current_state, next_state;

    // ============================================================================
    // State Transitions
    // ============================================================================
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IQ_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= IQ_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;

        if (!iq_en) begin
            next_state = IQ_LCL_IDLE;
        end
        else begin
            case (current_state)
                IQ_LCL_IDLE: begin
                    next_state = IQ_LCL_MEASURE;
                end

                IQ_LCL_MEASURE: begin
                    if (analog_settle_time_done) next_state = IQ_LCL_EVAL;
                end

                IQ_LCL_EVAL: begin
                    if (phy_rx_tckn_shift == 5'd0)
                        next_state = IQ_LCL_DONE_SUCCESS;
                    else
                        next_state = IQ_LCL_SEND_SHIFT_REQ;
                end

                IQ_LCL_SEND_SHIFT_REQ: begin
                    next_state = IQ_LCL_WAIT_RESP;
                end

                IQ_LCL_WAIT_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_resp) begin
                        if (rx_msginfo[0] == 1'b1) // Out of Range status
                            next_state = IQ_LCL_DONE_ERROR;
                        else
                            next_state = IQ_LCL_SETTLE;
                    end
                end

                IQ_LCL_SETTLE: begin
                    if (analog_settle_time_done) next_state = IQ_LCL_MEASURE;
                end

                IQ_LCL_DONE_SUCCESS: begin
                    next_state = IQ_LCL_DONE_SUCCESS;
                end

                IQ_LCL_DONE_ERROR: begin
                    next_state = IQ_LCL_DONE_ERROR;
                end

                default: next_state = IQ_LCL_IDLE;
            endcase
        end
    end

    // ============================================================================
    // Output Logic
    // ============================================================================
    always_comb begin
        // Safe defaults
        iq_done                  = 1'b0;
        iq_error                 = 1'b0;
        phy_rx_phase_detector_en = 1'b0;
        analog_settle_timer_en   = 1'b0;

        tx_sb_msg_valid          = 1'b0;
        tx_sb_msg                = NOTHING;
        tx_msginfo               = 16'h0;
        tx_data_field            = 64'h0;

        case (current_state)
            IQ_LCL_IDLE: begin
                // Passive state
            end

            IQ_LCL_MEASURE: begin
                phy_rx_phase_detector_en = 1'b1;
                analog_settle_timer_en   = 1'b1;
            end

            IQ_LCL_EVAL: begin
                // Logic evaluated in next_state computation
            end

            IQ_LCL_SEND_SHIFT_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXCLKCAL_TCKN_L_shift_req;
                tx_msginfo      = {10'h0, phy_rx_tckn_shift, phy_rx_decrement_shift};
                tx_data_field   = 64'h0;
            end

            IQ_LCL_WAIT_RESP: begin
                // Waiting for partner response
            end

            IQ_LCL_SETTLE: begin
                analog_settle_timer_en = 1'b1;
            end

            IQ_LCL_DONE_SUCCESS: begin
                iq_done = 1'b1;
            end

            IQ_LCL_DONE_ERROR: begin
                iq_done  = 1'b1;
                iq_error = 1'b1;
            end
        endcase
    end

endmodule
