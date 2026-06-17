// wrapper_VALTRAINCENTER.sv — MBTRAIN.VALTRAINCENTER Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the VALTRAINCENTER substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs
// depending on whether the Local or Partner FSM is currently driving the MB lanes.

module wrapper_VALTRAINCENTER #(
        parameter int unsigned MAX_VAL_PI_CODE = 'd16
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
        output logic        valtraincenter_done,

        // Control & Status:
        input  logic        valtraincenter_en,

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_VAL_PI_CODE+1)-1:0] phy_tx_val_pi_phase_ctrl,
        output logic        partner_sweep_en,

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,
        input  logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]  swept_code,
        input  wire logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]  best_code [0:15],
        input  logic        sweep_done,

        // =========================================================================
        // Group 4b: MB Control configurations
        // =========================================================================
        input  logic        mb_tx_continuous_or_strobe_clk,
        input  logic [2:0]  phy_negotiated_speed,

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
        // input  logic [15:0] rx_msginfo
        // input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // Local/partner intermediate signals
    logic        local_valtraincenter_done_wire;
    logic        partner_valtraincenter_done_wire;

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

    // Local FSM Instance
    unit_VALTRAINCENTER_local #(
        .MAX_VAL_PI_CODE(MAX_VAL_PI_CODE)
    ) u_local (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .valtraincenter_en              (valtraincenter_en),
        .soft_rst_n                     (soft_rst_n),
        .valtraincenter_done            (local_valtraincenter_done_wire),
        .phy_tx_val_pi_phase_ctrl       (phy_tx_val_pi_phase_ctrl),
        // MB signals moved to wrapper (incl. speed-dep CLK)
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

    // Partner FSM Instance
    unit_VALTRAINCENTER_partner u_partner (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .valtraincenter_en              (valtraincenter_en),
        .soft_rst_n                     (soft_rst_n),
        .valtraincenter_done            (partner_valtraincenter_done_wire),
        // MB signals moved to wrapper as static assigns
        .partner_sweep_en               (partner_sweep_en),
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid),
        .tx_sb_msg                      (partner_tx_sb_msg),
        .tx_msginfo                     (partner_tx_msginfo),
        .tx_data_field                  (partner_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg)
    );

    // Combine terminal signals
    assign valtraincenter_done = local_valtraincenter_done_wire & partner_valtraincenter_done_wire;

    // Sideband Arbitration
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    // =========================================================================
    // MB Lane Assignments — Static per spec §4.5.3.4.3 MBTRAIN.VALTRAINCENTER:
    //   Local   (TX side): CLK TX active (speed-dep), VAL TX active (VALTRAIN), DATA/TRK TX=00.
    //   Partner (RX side): CLK/DATA/VAL RX enabled, TRK RX disabled.
    //   wrapper_MBTRAIN ss_active already gates these when substate is not active.
    // =========================================================================
    // CLK TX: continuous/active (01) unless <=32GT/s strobe mode (00)
    assign mb_tx_clk_lane_sel  = (mb_tx_continuous_or_strobe_clk && phy_negotiated_speed <= 3'b101)
                                  ? 2'b00 : 2'b01;
    assign mb_tx_data_lane_sel = 2'b00;
    assign mb_tx_val_lane_sel  = 2'b01; // VALTRAIN pattern always active
    assign mb_tx_trk_lane_sel  = 2'b00;
    assign mb_rx_clk_lane_sel  = 1'b1;
    assign mb_rx_data_lane_sel = 1'b1;
    assign mb_rx_val_lane_sel  = 1'b1;
    assign mb_rx_trk_lane_sel  = 1'b0;

endmodule


