// ====================================================================================================
// wrapper_LINKSPEED.sv — MBTRAIN.LINKSPEED Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the LINKSPEED
// substate. It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB)
// control outputs depending on whether the Local or Partner FSM is active.
//
// ─── ARCHITECTURE ─────────────────────────────────────────────────────────────────────────────────
// Each UCIe die instantiates BOTH:
//   • unit_LINKSPEED_local   → Initiator: sends REQs, waits for RESPs, drives D2C sweep.
//   • unit_LINKSPEED_partner → Responder: waits for REQs from remote LOCAL, sends RESPs.
//
// Both FSMs share the physical SB TX bus. This wrapper arbitrates with LOCAL having priority.
// Both FSMs share the physical SB RX bus (broadcast — same rx_sb_* inputs to both).
//
// ─── D2C SWEEP ────────────────────────────────────────────────────────────────────────────────────
// unit_LINKSPEED_local uses an external unit_D2C_sweep (single TX D2C point test, 1 code).
// The sweep_en / d2c_perlane_pass / sweep_done ports are passed through to the top-level wrapper
// which instantiates unit_D2C_sweep. The PARTNER FSM does NOT use D2C.
//
// ─── MB ROUTING ───────────────────────────────────────────────────────────────────────────────────
// TX side:
//   • If partner_linkspeed_en: PARTNER drives TX (it holds clock; DATA/VAL held Low).
//   • Else:                    LOCAL  drives TX (Active during D2C, Elec-Idle on errors).
// RX side:
//   • If local_linkspeed_en:   LOCAL  drives RX (always enabled).
//   • Else:                    PARTNER drives RX (disabled on error path via error_req_rcvd).
//
// ─── ROUTING OUTPUTS ──────────────────────────────────────────────────────────────────────────────
// Both LOCAL and PARTNER independently assert their routing signals. The top-level MBTRAIN
// controller monitors them separately:
//   local_*_req  → exit decision for the LOCAL FSM path
//   partner_*_req→ exit decision for the PARTNER FSM path
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.LINKSPEED (Wrapper Routing):
// +----------------------------------------------------+-----------+-------------------------------+
// | Message Name                                       | Direction | Notes                         |
// +----------------------------------------------------+-----------+-------------------------------+
// | {MBTRAIN.LINKSPEED start req}                      | Out (TX)  | From LOCAL                    |
// | {MBTRAIN.LINKSPEED start resp}                     | In  (RX)  | To LOCAL, from remote PARTNER |
// | {MBTRAIN.LINKSPEED start req}                      | In  (RX)  | To PARTNER from remote LOCAL  |
// | {MBTRAIN.LINKSPEED start resp}                     | Out (TX)  | From PARTNER                  |
// | {MBTRAIN.LINKSPEED done req/resp}                  | Both      | LOCAL↔PARTNER (cross-die)     |
// | {MBTRAIN.LINKSPEED error req/resp}                 | Both      | Error path                    |
// | {MBTRAIN.LINKSPEED exit to repair req/resp}        | Both      | Repair path                   |
// | {MBTRAIN.LINKSPEED exit to speed degrade req/resp} | Both      | Speed degrade path            |
// | {MBTRAIN.LINKSPEED exit to phy retrain req/resp}   | Both      | PHY retrain path              |
// | {TRAINERROR entry req}                             | In  (RX)  | → Both FSMs → TO_TRAINERROR   |
// +----------------------------------------------------+-----------+-------------------------------+
// ====================================================================================================

module wrapper_LINKSPEED (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,                              // LTSM clock domain (1 GHz or 2 GHz)
        input  logic        rst_n,                             // 0: Asynchronous reset; 1: Normal operation

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        soft_rst_n,                        // 0: Soft reset; 1: Normal operation
        input  logic        is_high_speed,                     // 0: <= 32 GT/s; 1: > 32 GT/s
        input  logic        is_continuous_clk_mode,            // 0: Strobe mode; 1: Continuous clock

        // Local FSM Control:
        input  logic        local_linkspeed_en,                // 0: Disable; 1: Enable Local LINKSPEED FSM
        // Partner FSM Control:
        input  logic        partner_linkspeed_en,              // 0: Disable; 1: Enable Partner LINKSPEED FSM

        // Combined outputs
        output logic        linkspeed_done,                    // 0: In progress; 1: Sub-state completed
        output logic        trainerror_req,                    // 1: Request exit to TRAINERROR

        // Exit route requests: (Note: we commented-out each local/partner outputs here and replaced each pair with one output port)
        // output logic        local_linkinit_req,                // 1: Request exit to LINKINIT
        // output logic        partner_linkinit_req,              // 1: Request exit to LINKINIT
        output logic        linkspeed_linkinit_req ,              // 1: Request exit to LINKINIT

        // output logic        local_speedidle_req,               // 1: Request exit to MBTRAIN.SPEEDIDLE
        // output logic        partner_speedidle_req,             // 1: Request exit to MBTRAIN.SPEEDIDLE
        output logic        linkspeed_speedidle_req ,             // 1: Request exit to MBTRAIN.SPEEDIDLE

        // output logic        local_repair_req,                  // 1: Request exit to MBTRAIN.REPAIR
        // output logic        partner_repair_req,                // 1: Request exit to MBTRAIN.REPAIR
        output logic        linkspeed_repair_req ,                // 1: Request exit to MBTRAIN.REPAIR

        // output logic        local_phyretrain_req,              // 1: Request exit to PHYRETRAIN
        // output logic        partner_phyretrain_req,            // 1: Request exit to PHYRETRAIN
        output logic        linkspeed_phyretrain_req ,            // 1: Request exit to PHYRETRAIN

        // =========================================================================
        // Group 3: Lane & Width Configuration (Local FSM only)
        // =========================================================================
        input  logic [15:0] active_rx_lanes,                   // Active RX lane mask from unit_negotiated_lanes
        input  logic        width_degrade_feasible,            // 1=A valid degraded lane map is feasible

        // =========================================================================
        // Group 4: PHY Retrain Signals (Local FSM only)
        // =========================================================================
        input  logic        PHY_IN_RETRAIN,                    // 1: LTSM entered via PHY retrain path
        input  logic        params_changed,                    // 1: Runtime Link Test Control reg changed
        output logic        PHY_IN_RETRAIN_rst,                // 1-cycle pulse: clears PHY_IN_RETRAIN flag
        output logic        busy_bit_rst,                      // 1-cycle pulse: clears busy_bit flag

        // =========================================================================
        // Group 5: D2C Sweep Interface (Local FSM → unit_D2C_sweep, external)
        // =========================================================================
        output logic        local_sweep_en,                    // 0: Stop; 1: Start/sustain D2C sweep
        output logic        partner_sweep_en,                  // 0: Partner not ready; 1: Partner holding MB for sweep
        input  logic [15:0] d2c_perlane_pass,                  // Per-lane pass result (valid at sweep_done)
        input  logic        local_sweep_done,                  // 0: Sweeping; 1: Complete

        // =========================================================================
        // Group 6: LINKSPEED Result Output (Local FSM → MBTRAIN.REPAIR)
        // =========================================================================
        output logic [15:0] linkspeed_success_lanes,           // Per-lane D2C pass mask for REPAIR sub-state

        // =========================================================================
        // Group 7: MB Signals (Mainband Control)
        // =========================================================================
        output logic [1:0]  mb_tx_clk_lane_sel,                // 00: Low; 01: Active; 11: Elec-Idle
        output logic [1:0]  mb_tx_data_lane_sel,               // 00: Low; 01: Active; 11: Elec-Idle
        output logic [1:0]  mb_tx_val_lane_sel,                // 00: Low; 01: Active; 11: Elec-Idle
        output logic [1:0]  mb_tx_trk_lane_sel,                // 00: Low (always)
        output logic        mb_rx_clk_lane_sel,                // 0: Disabled; 1: Enabled
        output logic        mb_rx_data_lane_sel,               // 0: Disabled; 1: Enabled
        output logic        mb_rx_val_lane_sel,                // 0: Disabled; 1: Enabled
        output logic        mb_rx_trk_lane_sel,                // 0: Disabled (always)

        // =========================================================================
        // Group 8: SB Signals (Sideband)
        // =========================================================================
        output logic        tx_sb_msg_valid,                   // 0: Idle; 1: Valid 1-cycle TX pulse
        output logic [7:0]  tx_sb_msg,                        // Transmitted MsgCode
        output logic [15:0] tx_msginfo,                        // Transmitted MsgInfo payload
        output logic [63:0] tx_data_field,                     // Transmitted 64-bit Data payload

        input  logic        rx_sb_msg_valid,                   // 0: Idle; 1: Valid 1-cycle RX pulse
        input  logic [7:0]  rx_sb_msg,                        // Received MsgCode
        input  logic [15:0] rx_msginfo,                        // Received MsgInfo payload
        input  logic [63:0] rx_data_field                      // Received 64-bit Data payload
    );

    // =========================================================================
    // Internal Intermediate Wires
    // =========================================================================

    // Exit route requests:

    logic        local_linkinit_req    ;          // 1: Request exit to LINKINIT
    logic        partner_linkinit_req  ;          // 1: Request exit to LINKINIT

    logic        local_speedidle_req   ;          // 1: Request exit to MBTRAIN.SPEEDIDLE
    logic        partner_speedidle_req ;          // 1: Request exit to MBTRAIN.SPEEDIDLE

    logic        local_repair_req      ;          // 1: Request exit to MBTRAIN.REPAIR
    logic        partner_repair_req    ;          // 1: Request exit to MBTRAIN.REPAIR

    logic        local_phyretrain_req  ;          // 1: Request exit to PHYRETRAIN
    logic        partner_phyretrain_req;          // 1: Request exit to PHYRETRAIN

    assign linkspeed_linkinit_req   = local_linkinit_req   & partner_linkinit_req   ;
    assign linkspeed_speedidle_req  = local_speedidle_req  & partner_speedidle_req  ;
    assign linkspeed_repair_req     = local_repair_req     & partner_repair_req     ;
    assign linkspeed_phyretrain_req = local_phyretrain_req & partner_phyretrain_req ;

    // Done and trainerror wires from substate FSMs:
    logic        local_linkspeed_done_w     ;
    logic        partner_linkspeed_done_w   ;
    logic        local_trainerror_req_w     ;
    logic        partner_trainerror_req_w   ;

    // SB outputs from Local FSM:
    logic        local_tx_sb_msg_valid    ;
    logic [7:0]  local_tx_sb_msg          ;
    logic [15:0] local_tx_msginfo         ;
    logic [63:0] local_tx_data_field      ;

    // SB outputs from Partner FSM:
    logic        partner_tx_sb_msg_valid  ;
    logic [7:0]  partner_tx_sb_msg        ;
    logic [15:0] partner_tx_msginfo       ;
    logic [63:0] partner_tx_data_field    ;

    // MB outputs from Local FSM:
    logic [1:0]  local_mb_tx_clk_lane_sel ;
    logic [1:0]  local_mb_tx_data_lane_sel;
    logic [1:0]  local_mb_tx_val_lane_sel ;
    logic [1:0]  local_mb_tx_trk_lane_sel ;
    logic        local_mb_rx_clk_lane_sel ;
    logic        local_mb_rx_data_lane_sel;
    logic        local_mb_rx_val_lane_sel ;
    logic        local_mb_rx_trk_lane_sel ;

    // MB outputs from Partner FSM:
    logic [1:0]  partner_mb_tx_clk_lane_sel ;
    logic [1:0]  partner_mb_tx_data_lane_sel;
    logic [1:0]  partner_mb_tx_val_lane_sel ;
    logic [1:0]  partner_mb_tx_trk_lane_sel ;
    logic        partner_mb_rx_clk_lane_sel ;
    logic        partner_mb_rx_data_lane_sel;
    logic        partner_mb_rx_val_lane_sel ;
    logic        partner_mb_rx_trk_lane_sel ;

    // =========================================================================
    // 1st: Port Mapping of unit_LINKSPEED_local
    // =========================================================================
    unit_LINKSPEED_local u_LINKSPEED_local (
        // Clock and Reset Signals
        .lclk                           (lclk                          ), // LTSM clock domain
        .rst_n                          (rst_n                         ), // Active-low async reset
        // LTSM Control Signals
        .linkspeed_en                   (local_linkspeed_en            ), // Enable Local LINKSPEED FSM
        .soft_rst_n                     (soft_rst_n                    ), // Soft-reset control
        .linkspeed_done                 (local_linkspeed_done_w        ), // Sub-state done
        .speedidle_req                  (local_speedidle_req           ), // Exit to SPEEDIDLE
        .repair_req                     (local_repair_req              ), // Exit to REPAIR
        .linkinit_req                   (local_linkinit_req            ), // Exit to LINKINIT
        .phyretrain_req                 (local_phyretrain_req          ), // Exit to PHYRETRAIN
        .trainerror_req                 (local_trainerror_req_w        ), // Exit to TRAINERROR
        // Lane & Width Configuration
        .active_rx_lanes                (active_rx_lanes               ), // Active lane mask
        .width_degrade_feasible         (width_degrade_feasible        ), // Width degradation feasibility
        // PHY Retrain Signals
        .PHY_IN_RETRAIN                 (PHY_IN_RETRAIN                ), // PHY retrain flag
        .params_changed                 (params_changed                ), // Runtime reg changed flag
        .PHY_IN_RETRAIN_rst             (PHY_IN_RETRAIN_rst            ), // Clear PHY_IN_RETRAIN pulse
        .busy_bit_rst                   (busy_bit_rst                  ), // Clear busy bit pulse
        // LINKSPEED Result
        .linkspeed_success_lanes        (linkspeed_success_lanes       ), // Per-lane D2C pass mask
        // MB Lane Control
        .mb_tx_clk_lane_sel             (local_mb_tx_clk_lane_sel      ), // Clock TX select
        .mb_tx_data_lane_sel            (local_mb_tx_data_lane_sel     ), // Data TX select
        .mb_tx_val_lane_sel             (local_mb_tx_val_lane_sel      ), // Valid TX select
        .mb_tx_trk_lane_sel             (local_mb_tx_trk_lane_sel      ), // Track TX select
        .mb_rx_clk_lane_sel             (local_mb_rx_clk_lane_sel      ), // Clock RX enable
        .mb_rx_data_lane_sel            (local_mb_rx_data_lane_sel     ), // Data RX enable
        .mb_rx_val_lane_sel             (local_mb_rx_val_lane_sel      ), // Valid RX enable
        .mb_rx_trk_lane_sel             (local_mb_rx_trk_lane_sel      ), // Track RX enable
        // Speed and Clock Mode
        .is_high_speed                  (is_high_speed                 ), // Speed > 32 GT/s
        .is_continuous_clk_mode         (is_continuous_clk_mode        ), // Continuous clock mode
        // D2C Sweep Interface
        .sweep_en                       (local_sweep_en                ), // To external unit_D2C_sweep
        .d2c_perlane_pass               (d2c_perlane_pass              ), // From external unit_D2C_sweep
        .sweep_done                     (local_sweep_done              ), // From external unit_D2C_sweep
        // Sideband TX (to arbiter)
        .tx_sb_msg_valid                (local_tx_sb_msg_valid         ), // SB TX valid pulse
        .tx_sb_msg                      (local_tx_sb_msg               ), // SB TX MsgCode
        .tx_msginfo                     (local_tx_msginfo              ), // SB TX MsgInfo
        .tx_data_field                  (local_tx_data_field           ), // SB TX Data
        // Sideband RX (broadcast)
        .rx_sb_msg_valid                (rx_sb_msg_valid               ), // SB RX valid pulse
        .rx_sb_msg                      (rx_sb_msg                     ), // SB RX MsgCode
        .rx_msginfo                     (rx_msginfo                    ), // SB RX MsgInfo
        .rx_data_field                  (rx_data_field                 )  // SB RX Data
    );


    // =========================================================================
    // 2nd: Port Mapping of unit_LINKSPEED_partner
    // =========================================================================
    unit_LINKSPEED_partner u_LINKSPEED_partner (
        // Clock and Reset Signals
        .lclk                           (lclk                          ), // LTSM clock domain
        .rst_n                          (rst_n                         ), // Active-low async reset
        // LTSM Control Signals
        .linkspeed_en                   (partner_linkspeed_en          ), // Enable Partner LINKSPEED FSM
        .soft_rst_n                     (soft_rst_n                    ), // Soft-reset control
        .linkspeed_done                 (partner_linkspeed_done_w      ), // Sub-state done
        .speedidle_req                  (partner_speedidle_req         ), // Exit to SPEEDIDLE
        .repair_req                     (partner_repair_req            ), // Exit to REPAIR
        .linkinit_req                   (partner_linkinit_req          ), // Exit to LINKINIT
        .phyretrain_req                 (partner_phyretrain_req        ), // Exit to PHYRETRAIN
        .trainerror_req                 (partner_trainerror_req_w      ), // Exit to TRAINERROR
        // MB Lane Control
        .mb_tx_clk_lane_sel             (partner_mb_tx_clk_lane_sel    ), // Clock TX select
        .mb_tx_data_lane_sel            (partner_mb_tx_data_lane_sel   ), // Data TX select
        .mb_tx_val_lane_sel             (partner_mb_tx_val_lane_sel    ), // Valid TX select
        .mb_tx_trk_lane_sel             (partner_mb_tx_trk_lane_sel    ), // Track TX select
        .mb_rx_clk_lane_sel             (partner_mb_rx_clk_lane_sel    ), // Clock RX enable
        .mb_rx_data_lane_sel            (partner_mb_rx_data_lane_sel   ), // Data RX enable
        .mb_rx_val_lane_sel             (partner_mb_rx_val_lane_sel    ), // Valid RX enable
        .mb_rx_trk_lane_sel             (partner_mb_rx_trk_lane_sel    ), // Track RX enable
        // Speed and Clock Mode
        .is_high_speed                  (is_high_speed                 ), // Speed > 32 GT/s
        .is_continuous_clk_mode         (is_continuous_clk_mode        ), // Continuous clock mode
        // D2C Sweep Interface
        .partner_sweep_en               (partner_sweep_en              ), // To external unit_D2C_sweep
        // Sideband TX (to arbiter)
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid       ), // SB TX valid pulse
        .tx_sb_msg                      (partner_tx_sb_msg             ), // SB TX MsgCode
        .tx_msginfo                     (partner_tx_msginfo            ), // SB TX MsgInfo
        .tx_data_field                  (partner_tx_data_field         ), // SB TX Data
        // Sideband RX (broadcast)
        .rx_sb_msg_valid                (rx_sb_msg_valid               ), // SB RX valid pulse
        .rx_sb_msg                      (rx_sb_msg                     ), // SB RX MsgCode
        .rx_msginfo                     (rx_msginfo                    ), // SB RX MsgInfo
        .rx_data_field                  (rx_data_field                 )  // SB RX Data
    );


    // =========================================================================
    // 3rd: Multiplexing and Output Assignments
    // =========================================================================

    // Consolidated terminal/status signals
    assign linkspeed_done = local_linkspeed_done_w & partner_linkspeed_done_w;
    assign trainerror_req = local_trainerror_req_w | partner_trainerror_req_w;

    // ── Sideband TX Output Arbitration ───────────────────────────────────────
    // LOCAL has priority (Source A). PARTNER is secondary (Source B).
    // Both asserting simultaneously is impossible:
    //   LOCAL is in a SEND state (transmitting REQ),
    //   PARTNER is in a WAIT state (waiting for the REQ to arrive) — mutually exclusive.
    assign tx_sb_msg_valid = local_tx_sb_msg_valid  | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid  ? local_tx_sb_msg       : partner_tx_sb_msg     ;
    assign tx_msginfo      = local_tx_sb_msg_valid  ? local_tx_msginfo      : partner_tx_msginfo    ;
    assign tx_data_field   = local_tx_sb_msg_valid  ? local_tx_data_field   : partner_tx_data_field ;

    // ── MB Outputs MUX ───────────────────────────────────────────────────────
    // TX side routing:
    //   PARTNER active → PARTNER drives TX (holds clock; data/val held Low by its defaults).
    //   Otherwise     → LOCAL   drives TX (Active during D2C; Elec-Idle on error path).
    //
    // RX side routing:
    //   LOCAL active  → LOCAL   drives RX (always-enabled until error path sets Elec-Idle).
    //   Otherwise     → PARTNER drives RX (may disable on error path via error_req_rcvd flag).
    always_comb begin : MB_OUTPUTS_MUX
        // ── MB TX source selection ──
        if (partner_linkspeed_en) begin
            mb_tx_clk_lane_sel  = partner_mb_tx_clk_lane_sel ;
            mb_tx_data_lane_sel = partner_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = partner_mb_tx_val_lane_sel ;
            mb_tx_trk_lane_sel  = partner_mb_tx_trk_lane_sel ;
        end else begin
            mb_tx_clk_lane_sel  = local_mb_tx_clk_lane_sel   ;
            mb_tx_data_lane_sel = local_mb_tx_data_lane_sel  ;
            mb_tx_val_lane_sel  = local_mb_tx_val_lane_sel   ;
            mb_tx_trk_lane_sel  = local_mb_tx_trk_lane_sel   ;
        end

        // ── MB RX source selection ──
        if (local_linkspeed_en) begin
            mb_rx_clk_lane_sel  = local_mb_rx_clk_lane_sel   ;
            mb_rx_data_lane_sel = local_mb_rx_data_lane_sel  ;
            mb_rx_val_lane_sel  = local_mb_rx_val_lane_sel   ;
            mb_rx_trk_lane_sel  = local_mb_rx_trk_lane_sel   ;
        end else begin
            mb_rx_clk_lane_sel  = partner_mb_rx_clk_lane_sel ;
            mb_rx_data_lane_sel = partner_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = partner_mb_rx_val_lane_sel ;
            mb_rx_trk_lane_sel  = partner_mb_rx_trk_lane_sel ;
        end
    end

endmodule
// ====================================================================================================
// END wrapper_LINKSPEED
// ====================================================================================================


