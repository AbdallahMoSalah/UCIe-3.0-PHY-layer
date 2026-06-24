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
        output logic        local_sweep_en,
        input  logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]  swept_code,
        input  logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]  best_code , // Per-lane best midpoint.
        input  logic        sweep_done,

        // =========================================================================
        // Group 4b: MB Control configurations
        // =========================================================================
        input  logic        mb_tx_continuous_or_strobe_clk,
        input  logic [2:0]  phy_negotiated_speed,


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


endmodule


