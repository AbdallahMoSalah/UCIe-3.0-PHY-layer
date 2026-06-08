// wrapper_DATATRAINVREF.sv — MBTRAIN.DATATRAINVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the DATATRAINVREF substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.

module wrapper_DATATRAINVREF #(
        parameter int unsigned MAX_DATA_VREF_CODE = 7'd127, 
        parameter int unsigned MIN_DATA_VREF_CODE = 7'd10   
    ) (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,
        input  logic        rst_n,

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        is_ltsm_out_of_reset,
        input  logic        timeout_8ms_occured,

        input  logic        local_datatrainvref_en,
        output logic        local_datatrainvref_done,
        output logic        local_trainerror_req,
        output logic        local_update_lane_mask,

        input  logic        partner_datatrainvref_en,
        output logic        partner_datatrainvref_done,
        output logic        partner_trainerror_req,

        output logic        timeout_timer_en,

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15],
        output logic        partner_sweep_en,

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  swept_code,
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  best_code [0:15],
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
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    wire        local_timeout_timer_en_wire  ;
    wire        partner_timeout_timer_en_wire;

    logic        local_tx_sb_msg_valid ;
    logic [7:0]  local_tx_sb_msg      ;
    logic [15:0] local_tx_msginfo     ;
    logic [63:0] local_tx_data_field  ;

    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg     ;
    logic [15:0] partner_tx_msginfo    ;
    logic [63:0] partner_tx_data_field ;

    logic [1:0]  local_mb_tx_clk_lane_sel  ;
    logic [1:0]  local_mb_tx_data_lane_sel ;
    logic [1:0]  local_mb_tx_val_lane_sel  ;
    logic [1:0]  local_mb_tx_trk_lane_sel  ;
    logic        local_mb_rx_clk_lane_sel  ;
    logic        local_mb_rx_data_lane_sel ;
    logic        local_mb_rx_val_lane_sel  ;
    logic        local_mb_rx_trk_lane_sel  ;

    logic [1:0]  partner_mb_tx_clk_lane_sel  ;
    logic [1:0]  partner_mb_tx_data_lane_sel ;
    logic [1:0]  partner_mb_tx_val_lane_sel  ;
    logic [1:0]  partner_mb_tx_trk_lane_sel  ;
    logic        partner_mb_rx_clk_lane_sel  ;
    logic        partner_mb_rx_data_lane_sel ;
    logic        partner_mb_rx_val_lane_sel  ;
    logic        partner_mb_rx_trk_lane_sel  ;

    unit_DATATRAINVREF_local #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE)
    ) u_local (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .datatrainvref_en               (local_datatrainvref_en),
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset),
        .timeout_8ms_occured            (timeout_8ms_occured),
        .datatrainvref_done             (local_datatrainvref_done),
        .trainerror_req                 (local_trainerror_req),
        .update_lane_mask               (local_update_lane_mask),
        .timeout_timer_en               (local_timeout_timer_en_wire),
        .phy_rx_datavref_ctrl           (phy_rx_datavref_ctrl),
        .mb_tx_clk_lane_sel             (local_mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel            (local_mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel             (local_mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel             (local_mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel             (local_mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel            (local_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel             (local_mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel             (local_mb_rx_trk_lane_sel),
        .sweep_en                       (sweep_en),
        .swept_code                     (swept_code),
        .best_code                      (best_code),
        .sweep_done                     (sweep_done),
        .tx_sb_msg_valid                (local_tx_sb_msg_valid),
        .tx_sb_msg                      (local_tx_sb_msg),
        .tx_msginfo                     (local_tx_msginfo),
        .tx_data_field                  (local_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg),
        .rx_msginfo                     (rx_msginfo),
        .rx_data_field                  (rx_data_field)
    );

    unit_DATATRAINVREF_partner u_partner (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .datatrainvref_en               (partner_datatrainvref_en),
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset),
        .timeout_8ms_occured            (timeout_8ms_occured),
        .datatrainvref_done             (partner_datatrainvref_done),
        .trainerror_req                 (partner_trainerror_req),
        .timeout_timer_en               (partner_timeout_timer_en_wire),
        .mb_tx_clk_lane_sel             (partner_mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel            (partner_mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel             (partner_mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel             (partner_mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel             (partner_mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel            (partner_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel             (partner_mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel             (partner_mb_rx_trk_lane_sel),
        .partner_sweep_en               (partner_sweep_en),
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid),
        .tx_sb_msg                      (partner_tx_sb_msg),
        .tx_msginfo                     (partner_tx_msginfo),
        .tx_data_field                  (partner_tx_data_field),
        .rx_sb_msg_valid                (rx_sb_msg_valid),
        .rx_sb_msg                      (rx_sb_msg),
        .rx_msginfo                     (rx_msginfo),
        .rx_data_field                  (rx_data_field)
    );

    assign timeout_timer_en = local_timeout_timer_en_wire | partner_timeout_timer_en_wire;

    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    always_comb begin : MB_OUTPUTS_MUX
        if (partner_datatrainvref_en) begin
            mb_tx_clk_lane_sel  = partner_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel = partner_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = partner_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel  = partner_mb_tx_trk_lane_sel;
        end
        else begin
            mb_tx_clk_lane_sel  = local_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel = local_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = local_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel  = local_mb_tx_trk_lane_sel;
        end

        if (local_datatrainvref_en) begin
            mb_rx_clk_lane_sel  = local_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel = local_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = local_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel  = local_mb_rx_trk_lane_sel;
        end
        else begin
            mb_rx_clk_lane_sel  = partner_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel = partner_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = partner_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel  = partner_mb_rx_trk_lane_sel;
        end
    end

endmodule


