// ====================================================================================================
// wrapper_TXSELFCAL.sv — MBTRAIN.TXSELFCAL Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the TXSELFCAL substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.
//
// ====================================================================================================

module wrapper_TXSELFCAL (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // Control and Configuration Signals
        input  logic        soft_rst_n,
        input  logic        txselfcal_en,
        output logic        txselfcal_done,
        output logic        trainerror_req,

        // Timer Control
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // PHY Control Signals
        output logic        phy_tx_selfcal_en,

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
    logic        local_txselfcal_done_wire;
    logic        partner_txselfcal_done_wire;
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
    unit_TXSELFCAL_local u_TXSELFCAL_local (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .txselfcal_en           (txselfcal_en),
        .soft_rst_n             (soft_rst_n),
        .txselfcal_done         (local_txselfcal_done_wire),
        .trainerror_req         (local_trainerror_req_wire),
        .analog_settle_timer_en (analog_settle_timer_en),
        .analog_settle_time_done(analog_settle_time_done),
        .phy_tx_selfcal_en      (phy_tx_selfcal_en  ),
        .mb_tx_clk_lane_sel     (mb_tx_clk_lane_sel ),
        .mb_tx_data_lane_sel    (mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel     (mb_tx_val_lane_sel ),
        .mb_tx_trk_lane_sel     (mb_tx_trk_lane_sel ),
        .tx_sb_msg_valid        (local_tx_sb_msg_valid),
        .tx_sb_msg              (local_tx_sb_msg),
        .tx_msginfo             (local_tx_msginfo),
        .tx_data_field          (local_tx_data_field),
        .rx_sb_msg_valid        (rx_sb_msg_valid),
        .rx_sb_msg              (rx_sb_msg)
        // .rx_msginfo             (rx_msginfo),
        // .rx_data_field          (rx_data_field)
    );

    // Instantiate Partner FSM
    unit_TXSELFCAL_partner u_TXSELFCAL_partner (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .txselfcal_en           (txselfcal_en),
        .soft_rst_n             (soft_rst_n),
        .txselfcal_done         (partner_txselfcal_done_wire),
        .trainerror_req         (partner_trainerror_req_wire),
        .mb_rx_clk_lane_sel     (mb_rx_clk_lane_sel ),
        .mb_rx_data_lane_sel    (mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (mb_rx_val_lane_sel ),
        .mb_rx_trk_lane_sel     (mb_rx_trk_lane_sel ),
        .tx_sb_msg_valid        (partner_tx_sb_msg_valid),
        .tx_sb_msg              (partner_tx_sb_msg),
        .tx_msginfo             (partner_tx_msginfo),
        .tx_data_field          (partner_tx_data_field),
        .rx_sb_msg_valid        (rx_sb_msg_valid),
        .rx_sb_msg              (rx_sb_msg)
        // .rx_msginfo             (rx_msginfo),
        // .rx_data_field          (rx_data_field)
    );

    // Combined outputs logic
    assign txselfcal_done = local_txselfcal_done_wire & partner_txselfcal_done_wire;
    assign trainerror_req = local_trainerror_req_wire | partner_trainerror_req_wire;

    // SB TX output arbitration (Local FSM has priority)
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

endmodule
