// ====================================================================================================
// unit_SPEEDIDLE_local.sv — MBTRAIN.SPEEDIDLE LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled SPEEDIDLE substate.
// The Local FSM:
//   - Configures the new negotiated link speed based on state entry history.
//   - Waits for the PLL to lock at the new speed (using analog settle timer).
//   - Sends {MBTRAIN.SPEEDIDLE done req} to the partner.
//   - Waits for {MBTRAIN.SPEEDIDLE done resp} from the partner's Partner FSM.
//
// ====================================================================================================

module unit_SPEEDIDLE_local (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control and Config Signals
        input  logic        speedidle_en,
        input  logic        soft_rst_n,
        output logic        speedidle_done,
        output logic        trainerror_req,

        // State history and max speed configuration
        input  wire  ltsm_state_n_pkg::state_n_e state_n_1,
        input  logic [2:0]  param_negotiated_max_speed,
        output logic [2:0]  phy_negotiated_speed,

        // Timer Control Signals
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
        SPEEDIDLE_LCL_IDLE           = 3'd0,
        SPEEDIDLE_LCL_CONFIG         = 3'd1,
        SPEEDIDLE_LCL_WAIT_PLL       = 3'd2,
        SPEEDIDLE_LCL_SEND_REQ       = 3'd3,
        SPEEDIDLE_LCL_WAIT_RESP      = 3'd4,
        SPEEDIDLE_LCL_TO_TXSELFCAL   = 3'd5,
        SPEEDIDLE_LCL_TO_TRAINERROR  = 3'd6
    } state_t;

    state_t current_state, next_state;

    // Registers
    reg [2:0] internal_phy_negotiated_speed;

    assign phy_negotiated_speed = internal_phy_negotiated_speed;

    // Check if degrade is impossible (already at min speed 4 GT/s)
    wire is_entry_datavref = (state_n_1 == LOG_MBTRAIN_DATAVREF);
    wire is_entry_l1_l2    = (state_n_1 == LOG_L1 || state_n_1 == LOG_L2 || state_n_1 == LOG_L1_L2);
    wire is_entry_degrade  = (state_n_1 == LOG_MBTRAIN_LINKSPEED || state_n_1 == LOG_PHYRETRAIN);

    wire speed_degrade_error = !(is_entry_datavref || is_entry_l1_l2 || (is_entry_degrade && (internal_phy_negotiated_speed != 3'b000)));

    // FSM State and Registers
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state                 <= SPEEDIDLE_LCL_IDLE;
            internal_phy_negotiated_speed <= 3'b000;
        end else if (!soft_rst_n) begin
            current_state                 <= SPEEDIDLE_LCL_IDLE;
            internal_phy_negotiated_speed <= 3'b000;
        end else begin
            current_state <= next_state;

            // Speed register configuration logic
            if (current_state == SPEEDIDLE_LCL_CONFIG) begin
                if (state_n_1 == LOG_MBTRAIN_DATAVREF) begin
                    internal_phy_negotiated_speed <= param_negotiated_max_speed;
                end else if (state_n_1 == LOG_L1 || state_n_1 == LOG_L1_L2) begin
                    internal_phy_negotiated_speed <= internal_phy_negotiated_speed; // Keep
                end else if (state_n_1 == LOG_MBTRAIN_LINKSPEED || state_n_1 == LOG_PHYRETRAIN) begin
                    if (internal_phy_negotiated_speed != 3'b000) begin
                        internal_phy_negotiated_speed <= internal_phy_negotiated_speed - 3'b001;
                    end
                end
            end
        end
    end

    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        if ((rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) || (speed_degrade_error & speedidle_en)) begin
            next_state = SPEEDIDLE_LCL_TO_TRAINERROR;
        end
        else if (~speedidle_en) begin
            next_state = SPEEDIDLE_LCL_IDLE;
        end
        else begin
            case (current_state)
                SPEEDIDLE_LCL_IDLE: begin
                    next_state = SPEEDIDLE_LCL_CONFIG;
                end

                SPEEDIDLE_LCL_CONFIG: begin
                    next_state = SPEEDIDLE_LCL_WAIT_PLL;
                end

                SPEEDIDLE_LCL_WAIT_PLL: begin
                    if (analog_settle_time_done) begin
                        next_state = SPEEDIDLE_LCL_SEND_REQ;
                    end
                end

                SPEEDIDLE_LCL_SEND_REQ: begin
                    next_state = SPEEDIDLE_LCL_WAIT_RESP;
                end

                SPEEDIDLE_LCL_WAIT_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_SPEEDIDLE_done_resp) begin
                        next_state = SPEEDIDLE_LCL_TO_TXSELFCAL;
                    end
                end

                SPEEDIDLE_LCL_TO_TXSELFCAL: begin
                    if (!speedidle_en) begin
                        next_state = SPEEDIDLE_LCL_IDLE;
                    end
                end

                SPEEDIDLE_LCL_TO_TRAINERROR: begin
                    if (!speedidle_en) begin
                        next_state = SPEEDIDLE_LCL_IDLE;
                    end
                end

                default: next_state = SPEEDIDLE_LCL_IDLE;
            endcase
        end
    end

    always_comb begin : OUTPUT_LOGIC
        // Default outputs
        speedidle_done         = 1'b0;
        trainerror_req         = 1'b0;
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
            SPEEDIDLE_LCL_IDLE: begin
                mb_rx_clk_lane_sel = 1'b0; // Clock RX disabled when FSM is inactive
            end

            SPEEDIDLE_LCL_CONFIG: begin
                // single cycle configuration transition
            end

            SPEEDIDLE_LCL_WAIT_PLL: begin
                analog_settle_timer_en = 1'b1;
            end

            SPEEDIDLE_LCL_SEND_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_SPEEDIDLE_done_req;
            end

            SPEEDIDLE_LCL_WAIT_RESP: begin
                // Waiting
            end

            SPEEDIDLE_LCL_TO_TXSELFCAL: begin
                speedidle_done   = 1'b1;
            end

            SPEEDIDLE_LCL_TO_TRAINERROR: begin
                speedidle_done   = 1'b1;
                trainerror_req   = 1'b1;
            end
        endcase
    end

endmodule
