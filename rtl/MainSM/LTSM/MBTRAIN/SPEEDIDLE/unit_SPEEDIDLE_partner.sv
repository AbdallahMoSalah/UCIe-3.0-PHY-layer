// ====================================================================================================
// unit_SPEEDIDLE_partner.sv — MBTRAIN.SPEEDIDLE PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled SPEEDIDLE substate.
// The Partner FSM:
//   - Configures the target speed based on entry state history.
//   - Waits for its own PLL to lock (using analog settle timer).
//   - Waits for {MBTRAIN.SPEEDIDLE done req} from the partner's Local FSM.
//   - Responds with {MBTRAIN.SPEEDIDLE done resp} back to the partner.
//
// ====================================================================================================

module unit_SPEEDIDLE_partner (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control and Config Signals
        input  logic        speedidle_en,
        input  logic        is_ltsm_out_of_reset,
        input  logic        timeout_8ms_occured,
        output logic        speedidle_done,
        output logic        trainerror_req,

        // State history and max speed configuration
        input  wire  ltsm_state_n_pkg::state_n_e state_n [3:0],
        input  logic [2:0]  param_negotiated_max_speed,
        output logic [2:0]  phy_negotiated_speed,

        // Timer Control Signals
        output logic        timeout_timer_en,
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // MB TX/RX Lane Control
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // Sideband Control Signals
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // State encoding
    typedef enum logic [2:0] {
        SPEEDIDLE_PTN_IDLE      = 3'd0,
        SPEEDIDLE_PTN_CONFIG    = 3'd1,
        SPEEDIDLE_PTN_WAIT_PLL  = 3'd2,
        SPEEDIDLE_PTN_WAIT_REQ  = 3'd3,
        SPEEDIDLE_PTN_SEND_RESP = 3'd4,
        SPEEDIDLE_PTN_DONE      = 3'd5,
        SPEEDIDLE_PTN_TO_TE     = 3'd6
    } state_t;

    state_t current_state, next_state;

    // Registers
    reg [2:0] internal_phy_negotiated_speed;

    assign phy_negotiated_speed = internal_phy_negotiated_speed;

    // Check if degrade is impossible (already at min speed 4 GT/s)
    wire speed_degrade_error = (state_n[1] == LOG_MBTRAIN_LINKSPEED || state_n[1] == LOG_PHYRETRAIN) &&
        (internal_phy_negotiated_speed == 3'b000);

    // FSM State and Registers
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state                 <= SPEEDIDLE_PTN_IDLE;
            internal_phy_negotiated_speed <= 3'b000;
        end else if (!is_ltsm_out_of_reset) begin
            current_state                 <= SPEEDIDLE_PTN_IDLE;
            internal_phy_negotiated_speed <= 3'b000;
        end else begin
            current_state <= next_state;

            // Speed register configuration logic
            if (current_state == SPEEDIDLE_PTN_CONFIG) begin
                if (state_n[1] == LOG_MBTRAIN_DATAVREF) begin
                    internal_phy_negotiated_speed <= param_negotiated_max_speed;
                end else if (state_n[1] == LOG_L1_L2) begin
                    internal_phy_negotiated_speed <= internal_phy_negotiated_speed; // Keep
                end else if (state_n[1] == LOG_MBTRAIN_LINKSPEED || state_n[1] == LOG_PHYRETRAIN) begin
                    if (internal_phy_negotiated_speed != 3'b000) begin
                        internal_phy_negotiated_speed <= internal_phy_negotiated_speed - 3'b001;
                    end
                end
            end
        end
    end

    // Next State Logic
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        // Watchdog timeout or partner error request
        if (timeout_8ms_occured || (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req)) begin
            next_state = SPEEDIDLE_PTN_TO_TE;
        end else begin
            case (current_state)
                SPEEDIDLE_PTN_IDLE: begin
                    if (speedidle_en) begin
                        if (speed_degrade_error) begin
                            next_state = SPEEDIDLE_PTN_TO_TE;
                        end else begin
                            next_state = SPEEDIDLE_PTN_CONFIG;
                        end
                    end
                end

                SPEEDIDLE_PTN_CONFIG: begin
                    next_state = SPEEDIDLE_PTN_WAIT_PLL;
                end

                SPEEDIDLE_PTN_WAIT_PLL: begin
                    if (analog_settle_time_done) begin
                        next_state = SPEEDIDLE_PTN_WAIT_REQ;
                    end
                end

                SPEEDIDLE_PTN_WAIT_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_SPEEDIDLE_done_req) begin
                        next_state = SPEEDIDLE_PTN_SEND_RESP;
                    end
                end

                SPEEDIDLE_PTN_SEND_RESP: begin
                    next_state = SPEEDIDLE_PTN_DONE;
                end

                SPEEDIDLE_PTN_DONE: begin
                    if (!speedidle_en) begin
                        next_state = SPEEDIDLE_PTN_IDLE;
                    end
                end

                SPEEDIDLE_PTN_TO_TE: begin
                    if (!speedidle_en) begin
                        next_state = SPEEDIDLE_PTN_IDLE;
                    end
                end

                default: next_state = SPEEDIDLE_PTN_IDLE;
            endcase
        end
    end

    // Output Logic
    always_comb begin : OUTPUT_LOGIC
        // Default outputs
        speedidle_done         = 1'b0;
        trainerror_req         = 1'b0;
        timeout_timer_en       = 1'b1;
        analog_settle_timer_en = 1'b0;

        // TX/RX Default Values
        mb_tx_clk_lane_sel     = 2'b01; // Clock held low/differential low
        mb_tx_data_lane_sel    = 2'b00;
        mb_tx_val_lane_sel     = 2'b00;
        mb_tx_trk_lane_sel     = 2'b00;
        mb_rx_clk_lane_sel     = 1'b1;  // Clock Receiver enabled
        mb_rx_data_lane_sel    = 1'b0;
        mb_rx_val_lane_sel     = 1'b0;
        mb_rx_trk_lane_sel     = 1'b0;

        tx_sb_msg_valid        = 1'b0;
        tx_sb_msg              = NOTHING;
        tx_msginfo             = 16'h0;
        tx_data_field          = 64'h0;

        case (current_state)
            SPEEDIDLE_PTN_IDLE: begin
                timeout_timer_en    = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00; // Low when inactive
            end

            SPEEDIDLE_PTN_CONFIG: begin
                // configuration phase
            end

            SPEEDIDLE_PTN_WAIT_PLL: begin
                analog_settle_timer_en = 1'b1;
            end

            SPEEDIDLE_PTN_WAIT_REQ: begin
                // Waiting
            end

            SPEEDIDLE_PTN_SEND_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_SPEEDIDLE_done_resp;
            end

            SPEEDIDLE_PTN_DONE: begin
                speedidle_done   = 1'b1;
                timeout_timer_en = 1'b0;
            end

            SPEEDIDLE_PTN_TO_TE: begin
                speedidle_done   = 1'b1;
                trainerror_req   = 1'b1;
                timeout_timer_en = 1'b0;
            end
        endcase
    end

endmodule
