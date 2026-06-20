// wrapper_DATATRAINVREF.sv — MBTRAIN.DATATRAINVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the DATATRAINVREF substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.

module wrapper_DATATRAINVREF #(
        parameter int unsigned MAX_DATA_VREF_CODE = 'd16
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

        input  logic        datatrainvref_en,
        output logic        datatrainvref_done,

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15],
        output logic        partner_sweep_en,

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        local_sweep_en,
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  swept_code,
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  best_code [0:15],
        input  logic        sweep_done,

        // =========================================================================
        // Group 5: MB Signals (Mainband Control & Status)
        // =========================================================================
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

    logic        local_datatrainvref_done_wire;
    logic        partner_datatrainvref_done_wire;

    logic        local_tx_sb_msg_valid;
    logic [7:0]  local_tx_sb_msg      ;
    logic [15:0] local_tx_msginfo     ;
    logic [63:0] local_tx_data_field  ;

    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg     ;
    logic [15:0] partner_tx_msginfo    ;
    logic [63:0] partner_tx_data_field ;

    unit_DATATRAINVREF_local #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE)
    ) u_local (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .datatrainvref_en               (datatrainvref_en),
        .soft_rst_n                     (soft_rst_n),
        .datatrainvref_done             (local_datatrainvref_done_wire),
        .phy_rx_datavref_ctrl           (phy_rx_datavref_ctrl),
        // MB RX signals moved to wrapper as static assigns
        .sweep_en                       (local_sweep_en),
        .swept_code                     (swept_code),
        .best_code                      (best_code),
        .sweep_done                     (sweep_done),
        .tx_sb_msg_valid                (local_tx_sb_msg_valid),
        .tx_sb_msg                      (local_tx_sb_msg),
        .tx_msginfo                     (local_tx_msginfo),
        .tx_data_field                  (local_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg)
        // .rx_msginfo                     (rx_msginfo),
        // .rx_data_field                  (rx_data_field)
    );

    unit_DATATRAINVREF_partner u_partner (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .datatrainvref_en               (datatrainvref_en),
        .soft_rst_n                     (soft_rst_n),
        .datatrainvref_done             (partner_datatrainvref_done_wire),
        // MB TX signals moved to wrapper as static assigns
        .partner_sweep_en               (partner_sweep_en),
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid),
        .tx_sb_msg                      (partner_tx_sb_msg),
        .tx_msginfo                     (partner_tx_msginfo),
        .tx_data_field                  (partner_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg)
        // .rx_msginfo                     (rx_msginfo),
        // .rx_data_field                  (rx_data_field)
    );

    // Combine terminal signals
    assign datatrainvref_done = local_datatrainvref_done_wire & partner_datatrainvref_done_wire;

    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    // =========================================================================
    // MB Lane Assignments — Static per spec §4.5.3.4.9 MBTRAIN.DATATRAINVREF:
    //   Local   (RX side): CLK/DATA/VAL RX enabled, TRK RX disabled.
    //   Partner (TX side): CLK TX active (01), DATA/VAL/TRK TX held low.
    //   wrapper_MBTRAIN ss_active gates these when substate is not active.
    // =========================================================================
    assign mb_rx_clk_lane_sel  = 1'b1;
    assign mb_rx_data_lane_sel = 1'b1;
    assign mb_rx_val_lane_sel  = 1'b1;
    assign mb_rx_trk_lane_sel  = 1'b0;

endmodule


