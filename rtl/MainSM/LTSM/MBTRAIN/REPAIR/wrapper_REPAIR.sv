// ====================================================================================================
// wrapper_REPAIR.sv — MBTRAIN.REPAIR Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the REPAIR substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs.
//
// ====================================================================================================

module wrapper_REPAIR (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control and Configuration Signals
        input  logic        is_ltsm_out_of_reset,
        input  logic        timeout_8ms_occured,

        // Local FSM Control
        input  logic        local_repair_en,
        output logic        local_repair_done,
        output logic        local_txselfcal_req,
        output logic        local_trainerror_req,

        // Partner FSM Control
        input  logic        partner_repair_en,
        output logic        partner_repair_done,
        output logic        partner_trainerror_req,

        // Timer Control (Combined OR logic for watchdog)
        output logic        timeout_timer_en,

        // Width Degradation Inputs / Outputs
        input  logic [2:0]  local_tx_lane_map_code,
        input  logic        width_degrade_feasible,
        output logic [2:0]  mb_rx_data_lane_mask,
        output logic [2:0]  mb_tx_data_lane_mask,
        input  logic [2:0]  mbinit_rx_data_lane_mask,
        input  logic [2:0]  mbinit_tx_data_lane_mask,
        input  logic        update_lane_mask,

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
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    // Internal wires
    logic        local_timeout_timer_en;
    logic        partner_timeout_timer_en;

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

    // MB TX & RX outputs from Local FSM
    logic [1:0]  local_mb_tx_clk_lane_sel;
    logic [1:0]  local_mb_tx_data_lane_sel;
    logic [1:0]  local_mb_tx_val_lane_sel;
    logic [1:0]  local_mb_tx_trk_lane_sel;
    logic        local_mb_rx_clk_lane_sel;
    logic        local_mb_rx_data_lane_sel;
    logic        local_mb_rx_val_lane_sel;
    logic        local_mb_rx_trk_lane_sel;

    // MB TX & RX outputs from Partner FSM
    logic [1:0]  partner_mb_tx_clk_lane_sel;
    logic [1:0]  partner_mb_tx_data_lane_sel;
    logic [1:0]  partner_mb_tx_val_lane_sel;
    logic [1:0]  partner_mb_tx_trk_lane_sel;
    logic        partner_mb_rx_clk_lane_sel;
    logic        partner_mb_rx_data_lane_sel;
    logic        partner_mb_rx_val_lane_sel;
    logic        partner_mb_rx_trk_lane_sel;

    // Instantiate Local FSM
    unit_REPAIR_local u_REPAIR_local (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .repair_en              (local_repair_en),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset),
        .timeout_8ms_occured    (timeout_8ms_occured),
        .repair_done            (local_repair_done),
        .txselfcal_req          (local_txselfcal_req),
        .trainerror_req         (local_trainerror_req),
        .local_tx_lane_map_code (local_tx_lane_map_code),
        .width_degrade_feasible (width_degrade_feasible),
        .mb_tx_data_lane_mask   (mb_tx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
        .update_lane_mask       (update_lane_mask),
        .timeout_timer_en       (local_timeout_timer_en),
        .mb_tx_clk_lane_sel     (local_mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel    (local_mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel     (local_mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel     (local_mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel     (local_mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel    (local_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (local_mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel     (local_mb_rx_trk_lane_sel),
        .tx_sb_msg_valid        (local_tx_sb_msg_valid),
        .tx_sb_msg              (local_tx_sb_msg),
        .tx_msginfo             (local_tx_msginfo),
        .tx_data_field          (local_tx_data_field),
        .rx_sb_msg_valid        (rx_sb_msg_valid),
        .rx_sb_msg              (rx_sb_msg),
        .rx_msginfo             (rx_msginfo),
        .rx_data_field          (rx_data_field)
    );

    // Instantiate Partner FSM
    unit_REPAIR_partner u_REPAIR_partner (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .repair_en              (partner_repair_en),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset),
        .timeout_8ms_occured    (timeout_8ms_occured),
        .repair_done            (partner_repair_done),
        .txselfcal_req          (partner_txselfcal_req), // I didn't handle This port yet. we have to handle `partner_repair_txselfcal_req`
        .trainerror_req         (partner_trainerror_req),
        .mb_rx_data_lane_mask   (mb_rx_data_lane_mask),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .update_lane_mask       (update_lane_mask),
        .timeout_timer_en       (partner_timeout_timer_en),
        .mb_tx_clk_lane_sel     (partner_mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel    (partner_mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel     (partner_mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel     (partner_mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel     (partner_mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel    (partner_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (partner_mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel     (partner_mb_rx_trk_lane_sel),
        .tx_sb_msg_valid        (partner_tx_sb_msg_valid),
        .tx_sb_msg              (partner_tx_sb_msg),
        .tx_msginfo             (partner_tx_msginfo),
        .tx_data_field          (partner_tx_data_field),
        .rx_sb_msg_valid        (rx_sb_msg_valid),
        .rx_sb_msg              (rx_sb_msg),
        .rx_msginfo             (rx_msginfo),
        .rx_data_field          (rx_data_field)
    );

    // OR logic for watchdog timer
    assign timeout_timer_en = local_timeout_timer_en | partner_timeout_timer_en;

    // SB TX output arbitration
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    // MB Multiplexing
    always_comb begin : MB_MUX
        // TX Multiplexing: Partner FSM controls transmitters when active, otherwise Local FSM controls them
        if (partner_repair_en) begin
            mb_tx_clk_lane_sel  = partner_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel = partner_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = partner_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel  = partner_mb_tx_trk_lane_sel;
        end else begin
            mb_tx_clk_lane_sel  = local_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel = local_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = local_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel  = local_mb_tx_trk_lane_sel;
        end

        // RX Multiplexing: Local FSM controls receivers when active, otherwise Partner FSM controls them
        if (local_repair_en) begin
            mb_rx_clk_lane_sel  = local_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel = local_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = local_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel  = local_mb_rx_trk_lane_sel;
        end else begin
            mb_rx_clk_lane_sel  = partner_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel = partner_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = partner_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel  = partner_mb_rx_trk_lane_sel;
        end
    end

endmodule
