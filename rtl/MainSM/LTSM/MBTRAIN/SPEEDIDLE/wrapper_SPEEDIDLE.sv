// ====================================================================================================
// wrapper_SPEEDIDLE.sv — MBTRAIN.SPEEDIDLE Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the SPEEDIDLE substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.
//
// ====================================================================================================

module wrapper_SPEEDIDLE (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control and Configuration Signals
        input  logic        soft_rst_n,
        input  logic        speedidle_en,

        // Combined outputs
        output logic        speedidle_done,
        output logic        trainerror_req,

        // Timer Control (Settle timer)
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // Config signals
        input  wire ltsm_state_n_pkg::state_n_e state_n_1,
        input  logic [2:0]  param_negotiated_max_speed,
        output logic [2:0]  phy_negotiated_speed,

        // MB Signals
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // SB Signals
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo,
        // input  logic [63:0] rx_data_field
    );

    // Internal wires
    logic        local_speedidle_done_wire;
    logic        partner_speedidle_done_wire;
    logic        local_trainerror_req_wire;
    logic        partner_trainerror_req_wire;


    // SB outputs from Local FSM
    logic        local_tx_sb_msg_valid;
    logic [7:0]  local_tx_sb_msg;
    logic [15:0] local_tx_msginfo;
    logic [63:0] local_tx_data_field;

    // SB outputs from Partner FSM
    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg;
    logic [15:0] partner_tx_msginfo;
    logic [63:0] partner_tx_data_field;


    // Instantiate Local FSM
    unit_SPEEDIDLE_local u_SPEEDIDLE_local (
        .lclk                      (lclk),
        .rst_n                     (rst_n),
        .speedidle_en              (speedidle_en),
        .soft_rst_n                (soft_rst_n),
        .speedidle_done            (local_speedidle_done_wire),
        .trainerror_req            (local_trainerror_req_wire),
        .state_n_1                 (state_n_1),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .phy_negotiated_speed      (phy_negotiated_speed),
        .analog_settle_timer_en    (analog_settle_timer_en),
        .analog_settle_time_done   (analog_settle_time_done),
        .tx_sb_msg_valid           (local_tx_sb_msg_valid),
        .tx_sb_msg                 (local_tx_sb_msg),
        .tx_msginfo                (local_tx_msginfo),
        .tx_data_field             (local_tx_data_field),
        .rx_sb_msg_valid           (rx_sb_msg_valid),
        .rx_sb_msg                 (rx_sb_msg)
        // .rx_msginfo             (rx_msginfo),
        // .rx_data_field          (rx_data_field)
    );

    // Instantiate Partner FSM
    unit_SPEEDIDLE_partner u_SPEEDIDLE_partner (
        .lclk                      (lclk),
        .rst_n                     (rst_n),
        .speedidle_en              (speedidle_en),
        .soft_rst_n                (soft_rst_n),
        .speedidle_done            (partner_speedidle_done_wire),
        .trainerror_req            (partner_trainerror_req_wire),
        .state_n_1                 (state_n_1),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .tx_sb_msg_valid           (partner_tx_sb_msg_valid),
        .tx_sb_msg                 (partner_tx_sb_msg),
        .tx_msginfo                (partner_tx_msginfo),
        .tx_data_field             (partner_tx_data_field),
        .rx_sb_msg_valid           (rx_sb_msg_valid),
        .rx_sb_msg                 (rx_sb_msg)
        // .rx_msginfo             (rx_msginfo),
        // .rx_data_field          (rx_data_field)
    );

    // Combined outputs logic
    assign speedidle_done         = local_speedidle_done_wire & partner_speedidle_done_wire;
    assign trainerror_req         = local_trainerror_req_wire | partner_trainerror_req_wire;

    // SB TX output arbitration
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    assign mb_tx_clk_lane_sel  = 2'b01; // Clock held low/differential low
    assign mb_tx_data_lane_sel = 2'b00;
    assign mb_tx_val_lane_sel  = 2'b00;
    assign mb_tx_trk_lane_sel  = 2'b00;
    assign mb_rx_clk_lane_sel  = 1'b1;  // Clock Receiver enabled
    assign mb_rx_data_lane_sel = 1'b0;
    assign mb_rx_val_lane_sel  = 1'b0;
    assign mb_rx_trk_lane_sel  = 1'b0;

endmodule
