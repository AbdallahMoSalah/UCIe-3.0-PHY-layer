// ====================================================================================================
// wrapper_RXCLKCAL.sv — MBTRAIN.RXCLKCAL Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the RXCLKCAL substate,
// including their separated IQ calibration loop FSM sub-modules.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.RXCLKCAL (Wrapper Routing):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.RXCLKCAL start req}             | Both      | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL start resp}            | Both      | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL TCKN_L shift req}      | Both      | MsgInfo: [5:1]=shift; [0]=direction       |
// | {MBTRAIN.RXCLKCAL TCKN_L shift resp}     | Both      | MsgInfo: [0]=status (0=OK, 1=OutRange)    |
// | {MBTRAIN.RXCLKCAL done req}              | Both      | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL done resp}             | Both      | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR Entry req}                   | In  (RX)  | From partner                              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module wrapper_RXCLKCAL (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,
        input  logic        rst_n,
        input  logic        soft_rst_n,

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        is_high_speed,
        input  logic        is_continuous_clk_mode,

        // Control and Status
        input  logic        rxclkcal_en,

        // Combined outputs:
        output logic        rxclkcal_done,
        output logic        trainerror_req,

        // Timer Control:
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // =========================================================================
        // Group 3: PHY Interface
        // =========================================================================
        // Local (IQ Measurement)
        output logic        phy_rx_clock_lock_en,
        output logic        phy_rx_track_lock_en,
        output logic        phy_rx_phase_detector_en,
        input  logic [4:0]  phy_rx_tckn_shift,
        input  logic        phy_rx_decrement_shift,

        // Partner (TCKN Shift Application)
        output logic        phy_tx_tckn_shift_en,
        output logic [4:0]  phy_tx_tckn_shift,
        output logic        phy_tx_decrement_shift,
        input  logic        phy_tx_tckn_shift_out_of_range,

        // =========================================================================
        // Group 4: MB Signals (Mainband Control & Status)
        // =========================================================================
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        output logic        mb_tx_pattern_en,
        output logic [2:0]  mb_tx_pattern_setup,
        output logic [1:0]  mb_tx_clk_pattern_sel,

        // =========================================================================
        // Group 5: SB Signals (Sideband Control & Status)
        // =========================================================================
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo
        // input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // Internal Local FSM SB and Timer signals
    logic        local_tx_sb_msg_valid;
    logic [7:0]  local_tx_sb_msg;
    logic [15:0] local_tx_msginfo;
    logic [63:0] local_tx_data_field;
    logic        local_rxclkcal_done_wire;
    logic        local_trainerror_req_wire;
    logic        local_analog_settle_timer_en;

    // Internal IQ Local FSM SB and Timer signals
    logic        iq_en;
    logic        iq_done;
    logic        iq_error;
    logic        iq_local_tx_sb_msg_valid;
    logic [7:0]  iq_local_tx_sb_msg;
    logic [15:0] iq_local_tx_msginfo;
    logic [63:0] iq_local_tx_data_field;
    logic        iq_local_analog_settle_timer_en;

    // Internal Partner FSM SB and Timer signals
    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg;
    logic [15:0] partner_tx_msginfo;
    logic [63:0] partner_tx_data_field;
    logic        partner_rxclkcal_done_wire;
    logic        partner_trainerror_req_wire;

    // Internal IQ Partner FSM SB signals
    logic        iq_partner_en;
    logic        iq_partner_done;
    logic        iq_partner_error;
    logic        iq_partner_tx_sb_msg_valid;
    logic [7:0]  iq_partner_tx_sb_msg;
    logic [15:0] iq_partner_tx_msginfo;
    logic [63:0] iq_partner_tx_data_field;

    // =========================================================================
    // unit_RXCLKCAL_local Instance
    // =========================================================================
    unit_RXCLKCAL_local u_RXCLKCAL_local (
        .lclk                           (lclk                           ),
        .rst_n                          (rst_n                          ),
        .soft_rst_n                     (soft_rst_n                     ),
        .rxclkcal_en                    (rxclkcal_en                    ),
        .rxclkcal_done                  (local_rxclkcal_done_wire       ),
        .trainerror_req                 (local_trainerror_req_wire      ),
        .is_high_speed                  (is_high_speed                  ),
        // .is_continuous_clk_mode         (is_continuous_clk_mode         ),
        .phy_rx_clock_lock_en           (phy_rx_clock_lock_en           ),
        .phy_rx_track_lock_en           (phy_rx_track_lock_en           ),
        .iq_en                          (iq_en                          ),
        .iq_done                        (iq_done                        ),
        .iq_error                       (iq_error                       ),
        .mb_rx_clk_lane_sel             (mb_rx_clk_lane_sel             ),
        .mb_rx_trk_lane_sel             (mb_rx_trk_lane_sel             ),
        .analog_settle_timer_en         (local_analog_settle_timer_en   ),
        .analog_settle_time_done        (analog_settle_time_done        ),
        .tx_sb_msg_valid                (local_tx_sb_msg_valid          ),
        .tx_sb_msg                      (local_tx_sb_msg                ),
        .tx_msginfo                     (local_tx_msginfo               ),
        .tx_data_field                  (local_tx_data_field            ),
        .rx_sb_msg_valid                (rx_sb_msg_valid                ),
        .rx_sb_msg                      (rx_sb_msg                      )
        // .rx_msginfo                  (rx_msginfo                     )
    );

    // =========================================================================
    // unit_RXCLKCAL_IQ_local Instance
    // =========================================================================
    unit_RXCLKCAL_IQ_local u_RXCLKCAL_IQ_local (
        .lclk                           (lclk                           ),
        .rst_n                          (rst_n                          ),
        .soft_rst_n                     (soft_rst_n                     ),
        .iq_en                          (iq_en                          ),
        .iq_done                        (iq_done                        ),
        .iq_error                       (iq_error                       ),
        .phy_rx_phase_detector_en       (phy_rx_phase_detector_en       ),
        .phy_rx_tckn_shift              (phy_rx_tckn_shift              ),
        .phy_rx_decrement_shift         (phy_rx_decrement_shift         ),
        .analog_settle_timer_en         (iq_local_analog_settle_timer_en),
        .analog_settle_time_done        (analog_settle_time_done        ),
        .tx_sb_msg_valid                (iq_local_tx_sb_msg_valid       ),
        .tx_sb_msg                      (iq_local_tx_sb_msg             ),
        .tx_msginfo                     (iq_local_tx_msginfo            ),
        .tx_data_field                  (iq_local_tx_data_field         ),
        .rx_sb_msg_valid                (rx_sb_msg_valid                ),
        .rx_sb_msg                      (rx_sb_msg                      ),
        .rx_msginfo                     (rx_msginfo                     )
    );

    // =========================================================================
    // unit_RXCLKCAL_partner Instance
    // =========================================================================
    unit_RXCLKCAL_partner u_RXCLKCAL_partner (
        .lclk                           (lclk                           ),
        .rst_n                          (rst_n                          ),
        .soft_rst_n                     (soft_rst_n                     ),
        .rxclkcal_en                    (rxclkcal_en                    ),
        .rxclkcal_done                  (partner_rxclkcal_done_wire     ),
        .trainerror_req                 (partner_trainerror_req_wire    ),
        .is_high_speed                  (is_high_speed                  ),
        .is_continuous_clk_mode         (is_continuous_clk_mode         ),
        .iq_partner_en                  (iq_partner_en                  ),
        .iq_partner_done                (iq_partner_done                ),
        .iq_partner_error               (iq_partner_error               ),
        .mb_tx_pattern_en               (mb_tx_pattern_en               ),
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid        ),
        .tx_sb_msg                      (partner_tx_sb_msg              ),
        .tx_msginfo                     (partner_tx_msginfo             ),
        .tx_data_field                  (partner_tx_data_field          ),
        .rx_sb_msg_valid                (rx_sb_msg_valid                ),
        .rx_sb_msg                      (rx_sb_msg                      )
        // .rx_msginfo                  (rx_msginfo                     )
    );

    // =========================================================================
    // unit_RXCLKCAL_IQ_partner Instance
    // =========================================================================
    unit_RXCLKCAL_IQ_partner u_RXCLKCAL_IQ_partner (
        .lclk                           (lclk                           ),
        .rst_n                          (rst_n                          ),
        .soft_rst_n                     (soft_rst_n                     ),
        .iq_partner_en                  (iq_partner_en                  ),
        .iq_partner_done                (iq_partner_done                ),
        .iq_partner_error               (iq_partner_error               ),
        .phy_tx_tckn_shift_en           (phy_tx_tckn_shift_en           ),
        .phy_tx_tckn_shift              (phy_tx_tckn_shift              ),
        .phy_tx_decrement_shift         (phy_tx_decrement_shift         ),
        .phy_tx_tckn_shift_out_of_range (phy_tx_tckn_shift_out_of_range ),
        .tx_sb_msg_valid                (iq_partner_tx_sb_msg_valid     ),
        .tx_sb_msg                      (iq_partner_tx_sb_msg           ),
        .tx_msginfo                     (iq_partner_tx_msginfo          ),
        .tx_data_field                  (iq_partner_tx_data_field       ),
        .rx_sb_msg_valid                (rx_sb_msg_valid                ),
        .rx_sb_msg                      (rx_sb_msg                      ),
        .rx_msginfo                     (rx_msginfo                     )
    );

    // Combined outputs:
    assign rxclkcal_done  = local_rxclkcal_done_wire & partner_rxclkcal_done_wire;
    assign trainerror_req = local_trainerror_req_wire | partner_trainerror_req_wire;

    // Analog Settle Timer Enable OR logic
    assign analog_settle_timer_en = local_analog_settle_timer_en | iq_local_analog_settle_timer_en;

    // SB TX arbitration
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | iq_local_tx_sb_msg_valid |
        partner_tx_sb_msg_valid | iq_partner_tx_sb_msg_valid;

    assign tx_sb_msg       = local_tx_sb_msg_valid      ? local_tx_sb_msg      :
        iq_local_tx_sb_msg_valid   ? iq_local_tx_sb_msg   :
        partner_tx_sb_msg_valid    ? partner_tx_sb_msg    :
        iq_partner_tx_sb_msg;

    assign tx_msginfo      = local_tx_sb_msg_valid      ? local_tx_msginfo      :
        iq_local_tx_sb_msg_valid   ? iq_local_tx_msginfo   :
        partner_tx_sb_msg_valid    ? partner_tx_msginfo    :
        iq_partner_tx_msginfo;

    assign tx_data_field   = local_tx_sb_msg_valid      ? local_tx_data_field   :
        iq_local_tx_sb_msg_valid   ? iq_local_tx_data_field :
        partner_tx_sb_msg_valid    ? partner_tx_data_field  :
        iq_partner_tx_data_field;

    assign mb_rx_data_lane_sel   = 1'b0;
    assign mb_rx_val_lane_sel    = 1'b0;

    assign mb_tx_pattern_setup   = 3'b100; // Clock pattern configuration
    assign mb_tx_clk_pattern_sel = 2'd3;   // Clk Mode 2 (quarter rate clock)

endmodule
