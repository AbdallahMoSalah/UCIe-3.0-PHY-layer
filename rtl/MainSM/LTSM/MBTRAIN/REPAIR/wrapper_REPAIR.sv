// ====================================================================================================
// wrapper_REPAIR.sv — MBTRAIN.REPAIR Wrapper
//
// Wraps both the Local (Initiator) and Partner (Responder) FSMs of the REPAIR substate.
//
// OWNERSHIP MODEL:
//   - PARTNER FSM is the sole owner of mb_tx_data_lane_mask and mb_rx_data_lane_mask.
//     It applies the UCIe spec Step 2 decision rules after receiving Die B's TX code.
//   - LOCAL FSM manages only the SB handshake (sends REQs, waits RESPs) and TRAINERROR detection.
//     LOCAL has no lane mask ports.
//
// wrapper outputs:
//   - mb_tx_data_lane_mask  ← directly from PARTNER FSM
//   - mb_rx_data_lane_mask  ← directly from PARTNER FSM
//
// ====================================================================================================

module wrapper_REPAIR (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control and Configuration Signals
        input  logic        soft_rst_n,

        // Local FSM Control
        input  logic        repair_en,
        output logic        repair_done,
        output logic        trainerror_req,

        // Width Degradation Inputs for unit_negotiated_lanes
        input  logic [15:0] success_tx_lanes,           // Per-lane TX success bitmask
        input  logic        rf_cap_SPMW,                // Standard Package Module Width cap bit
        input  logic [3:0]  rf_ctrl_target_link_width,  // Target link width register
        input  logic        param_UCIe_S_x8,            // UCIe-S forced x8 mode parameter

        // Lane Mask Outputs (owned by PARTNER FSM)
        //   mb_tx_data_lane_mask: our TX lane mask (decided by PARTNER after receiving Die B's TX code)
        //   mb_rx_data_lane_mask: our RX lane mask (= Die B's TX code after decision logic)
        output logic [2:0]  mb_tx_data_lane_mask,
        output logic [2:0]  mb_rx_data_lane_mask,

        // Decoded lane outputs from internal unit_negotiated_lanes.
        // Exposed so wrapper_MBTRAIN can connect to them directly (active_rx_lanes →
        // sweep_active_lanes + wrapper_LINKSPEED; degrade_feasible → wrapper_LINKSPEED)
        // instead of instantiating a duplicate unit_negotiated_lanes at the top level.
        output logic [15:0] active_rx_lanes,        // Active RX lane bitmask
        output logic        degrade_feasible,        // 1 = valid degraded lane code is feasible

        // LTSM controller override: reload masks to initial values
        input  logic [2:0]  mbinit_rx_data_lane_mask,
        input  logic [2:0]  mbinit_tx_data_lane_mask,
        // input  logic        update_lane_mask,
        input  ltsm_state_n_pkg::state_n_e state_n_0,

        // MB Signals (multiplexed from Local/Partner based on which is active)
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
        input  logic [15:0] rx_msginfo
        // input  logic [63:0] rx_data_field
    );

    // =========================================================================
    // Internal wires
    // =========================================================================
    logic        local_repair_done_w;
    logic        partner_repair_done_w;
    logic        local_trainerror_req_w;
    logic        partner_trainerror_req_w;

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

    // MB signals moved to wrapper as static assigns — see below.

    // Internal outputs from unit_negotiated_lanes (active_rx_lanes and degrade_feasible
    // are now declared as module output ports above — not re-declared here).
    logic [2:0]  degraded_lane_map_code; // Our best TX degraded code (fed to both LOCAL and PARTNER)
    logic        is_x16_module;          // 1 = X16 full-width; 0 = X8 module (changes "all functional" meaning)

    // =========================================================================
    // Instantiate unit_negotiated_lanes
    // Computes the degraded TX code and module-type flag.
    // mb_tx/rx_data_lane_mask fed back for the TX/RX active lane decode.
    // =========================================================================
    unit_negotiated_lanes u_negotiated_lanes (
        .mb_rx_data_lane_mask       (mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (mb_tx_data_lane_mask),
        .active_rx_lanes            (active_rx_lanes),
        .active_tx_lanes            (), // not used
        .success_tx_lanes           (success_tx_lanes),
        .rf_cap_SPMW                (rf_cap_SPMW),
        .rf_ctrl_target_link_width  (rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (param_UCIe_S_x8),
        .degraded_lane_map_code     (degraded_lane_map_code),
        .degrade_feasible           (degrade_feasible),
        .is_x16_module              (is_x16_module)
    );

    // =========================================================================
    // Instantiate Local FSM
    // LOCAL manages SB handshake only — no lane mask ports.
    // =========================================================================
    unit_REPAIR_local u_REPAIR_local (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .repair_en                  (repair_en),
        .soft_rst_n                 (soft_rst_n),
        .repair_done                (local_repair_done_w),
        .trainerror_req             (local_trainerror_req_w),
        .degraded_tx_lane_map_code  (degraded_lane_map_code),
        .width_degrade_feasible     (degrade_feasible),
        // MB signals moved to wrapper as static assigns
        .tx_sb_msg_valid            (local_tx_sb_msg_valid),
        .tx_sb_msg                  (local_tx_sb_msg),
        .tx_msginfo                 (local_tx_msginfo),
        .tx_data_field              (local_tx_data_field),
        .rx_sb_msg_valid            (rx_sb_msg_valid),
        .rx_sb_msg                  (rx_sb_msg),
        .rx_msginfo                 (rx_msginfo)
        // .rx_data_field              (rx_data_field)
    );

    // =========================================================================
    // Instantiate Partner FSM
    // PARTNER is the decision-maker for final TX and RX lane masks.
    // =========================================================================
    unit_REPAIR_partner u_REPAIR_partner (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .repair_en                  (repair_en),
        .soft_rst_n                 (soft_rst_n),
        .repair_done                (partner_repair_done_w),
        .trainerror_req             (partner_trainerror_req_w),
        .degraded_tx_lane_map_code  (degraded_lane_map_code),
        .width_degrade_feasible     (degrade_feasible),
        .is_x16_module              (is_x16_module),
        .mb_rx_data_lane_mask       (mb_rx_data_lane_mask),
        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (mb_tx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .state_n_0                  (state_n_0),
        // MB signals moved to wrapper as static assigns
        .tx_sb_msg_valid            (partner_tx_sb_msg_valid),
        .tx_sb_msg                  (partner_tx_sb_msg),
        .tx_msginfo                 (partner_tx_msginfo),
        .tx_data_field              (partner_tx_data_field),
        .rx_sb_msg_valid            (rx_sb_msg_valid),
        .rx_sb_msg                  (rx_sb_msg),
        .rx_msginfo                 (rx_msginfo)
        // .rx_data_field              (rx_data_field)
    );

    // =========================================================================
    // Output done & trainerror consolidation
    // =========================================================================
    assign repair_done    = local_repair_done_w & partner_repair_done_w;
    assign trainerror_req = local_trainerror_req_w | partner_trainerror_req_w;

    // =========================================================================
    // SB TX output arbitration
    // Local sends REQs, Partner sends RESPs — they should not collide in practice.
    // Local takes priority if both assert simultaneously (defensive).
    // =========================================================================
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid                      ;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg    ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo   ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field;

    // =========================================================================
    // MB Assignments — Static per spec §4.5.3.4.13 MBTRAIN.REPAIR:
    //   CLK TX=01, DATA/VAL/TRK TX=00, CLK RX=1, DATA/VAL/TRK RX=0.
    //   wrapper_MBTRAIN ss_active gates these when substate is not active.
    // =========================================================================
    assign mb_rx_clk_lane_sel  = 1'b1;
    assign mb_rx_data_lane_sel = 1'b0;
    assign mb_rx_val_lane_sel  = 1'b0;
    assign mb_rx_trk_lane_sel  = 1'b0;


endmodule
