// wrapper_VALTRAINVREF.sv — MBTRAIN.VALTRAINVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the VALTRAINVREF substate.
// It arbitrates their Sideband (SB) TX outputs and routes their Mainband (MB) control outputs directly.

module wrapper_VALTRAINVREF #(
        parameter int unsigned MAX_VAL_VREF_CODE = 'd16
    ) (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,
        input  logic        rst_n,

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        soft_rst_n,
        output logic        valtrainvref_done,
        // output logic        trainerror_req,

        // Control & Status:
        input  logic        valtrainvref_en,

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] phy_rx_valvref_ctrl,
        output logic        partner_sweep_en,

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,
        input  logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  swept_code,
        input  wire logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  best_code [0:15],
        input  logic        sweep_done,

        // =========================================================================
        // Group 5: MB Signals (Mainband Control & Status)
        // =========================================================================
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // =========================================================================
        // Group 6: SB Signals (Sideband Control & Status)
        // =========================================================================
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo,
        // input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // Local/partner intermediate signals
    logic        local_valtrainvref_done_wire;
    logic        partner_valtrainvref_done_wire;

    // SB outputs from Local FSM:
    logic        local_tx_sb_msg_valid ;
    logic [7:0]  local_tx_sb_msg      ;
    logic [15:0] local_tx_msginfo     ;
    logic [63:0] local_tx_data_field  ;

    // SB outputs from Partner FSM:
    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg     ;
    logic [15:0] partner_tx_msginfo    ;
    logic [63:0] partner_tx_data_field ;

    unit_VALTRAINVREF_local #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE)
    ) u_local (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .valtrainvref_en                (valtrainvref_en),
        .soft_rst_n                     (soft_rst_n),
        .valtrainvref_done              (local_valtrainvref_done_wire),
        .phy_rx_valvref_ctrl            (phy_rx_valvref_ctrl),
        .sweep_en                       (sweep_en),
        .swept_code                     (swept_code),
        .best_code                      (best_code),
        .sweep_done                     (sweep_done),
        .tx_sb_msg_valid                (local_tx_sb_msg_valid),
        .tx_sb_msg                      (local_tx_sb_msg),
        .tx_msginfo                     (local_tx_msginfo),
        .tx_data_field                  (local_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg)
    );

    // Partner FSM Instance (Controls Transmitter Settings)
    unit_VALTRAINVREF_partner u_partner (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .valtrainvref_en                (valtrainvref_en),
        .soft_rst_n                     (soft_rst_n),
        .valtrainvref_done              (partner_valtrainvref_done_wire),
        .partner_sweep_en               (partner_sweep_en),
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid),
        .tx_sb_msg                      (partner_tx_sb_msg),
        .tx_msginfo                     (partner_tx_msginfo),
        .tx_data_field                  (partner_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg)
    );

    // Combine terminal signals
    assign valtrainvref_done = local_valtrainvref_done_wire & partner_valtrainvref_done_wire;

    // Sideband Arbitration
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    // =========================================================================
    // MB Lane Assignments — Static per spec §4.5.3.4.6 MBTRAIN.VALTRAINVREF:
    //   Partner (TX side): CLK TX active, VAL TX active (VALTRAIN), DATA/TRK TX held low.
    //   Local   (RX side): CLK/VAL RX enabled, DATA/TRK RX disabled.
    //   All go to zero when valtrainvref_en=0.
    // =========================================================================
    assign mb_tx_clk_lane_sel  = 2'b01;
    assign mb_tx_data_lane_sel = 2'b00;
    assign mb_tx_val_lane_sel  = 2'b01;
    assign mb_tx_trk_lane_sel  = 2'b00;
    assign mb_rx_clk_lane_sel  = 1'b1 ;
    assign mb_rx_data_lane_sel = 1'b0 ;
    assign mb_rx_val_lane_sel  = 1'b1 ;
    assign mb_rx_trk_lane_sel  = 1'b0 ;

endmodule
