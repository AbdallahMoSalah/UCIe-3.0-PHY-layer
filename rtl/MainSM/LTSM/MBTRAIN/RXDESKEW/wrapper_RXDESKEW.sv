// ====================================================================================================
// wrapper_RXDESKEW.sv — MBTRAIN.RXDESKEW Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the RXDESKEW substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs
// depending on whether the Local or Partner FSM is currently enabled.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.RXDESKEW (Wrapper Routing):
// +----------------------------------------------------+-----------+----------------------------------------+
// | Message Name                                       | Direction | MsgInfo & Data Field Details           |
// +----------------------------------------------------+-----------+----------------------------------------+
// | {MBTRAIN.RXDESKEW start req}                       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW start resp}                      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW EQ Preset req}                   | Out (TX)  | MsgInfo[3:0]: EQ preset code (0–5)     |
// |                                                    |           | MsgInfo[15:4]: Reserved                |
// |                                                    |           | Data: 64'h0                            |
// | {MBTRAIN.RXDESKEW EQ Preset resp}                  | In  (RX)  | MsgInfo[0]: 0=Success, 1=Fail          |
// |                                                    |           | MsgInfo[15:1]: Reserved                |
// |                                                    |           | Data: 64'h0                            |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}    | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp}   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end req}                         | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end resp}                        | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {TRAINERROR entry req}                             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// +----------------------------------------------------+-----------+----------------------------------------+
// ====================================================================================================

module wrapper_RXDESKEW #(
        parameter int unsigned MAX_DESKEW_CODE          = 7'd127, // Maximum deskew code (inclusive)
        parameter int unsigned MIN_DESKEW_CODE          = 7'd0  , // Minimum deskew code (inclusive)
        parameter int unsigned MAX_ARC_LIMIT            = 3'd4  , // Maximum DTC1 arc iterations (spec = 4)
        parameter int unsigned MAX_PRESET_SEARCH        = 3'd6  , // Maximum EQ presets to try (0–5, total 6)
        parameter int unsigned MIN_DESIRED_SWEEP_RANGE  = (MAX_DESKEW_CODE - MIN_DESKEW_CODE + 1) * 75 / 100,
        parameter int unsigned MAX_VALID_PRESET         = 4'd5    // Valid TX EQ preset range limit
    ) (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,                           // LTSM clock domain (1 GHz or 2 GHz)
        input  logic        rst_n,                          // 0: Asynchronous reset; 1: Normal operation

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        is_ltsm_out_of_reset,           // 0: Soft reset active; 1: Normal operation
        input  logic        timeout_8ms_occured,            // 0: No timeout; 1: 8ms watchdog timeout occurred
        input  logic        is_high_speed,                  // 0: <= 32 GT/s; 1: > 32 GT/s
        input  logic        is_continuous_clk_mode,         // 0: Strobe mode; 1: Continuous clock mode

        // Local FSM Control:
        input  logic        local_rxdeskew_en,              // 0: Disable; 1: Enable Local RXDESKEW sequence
        output logic        local_rxdeskew_done,            // 0: In progress; 1: Sub-state completed
        output logic        local_datatraincenter1_req,     // 0: No arc; 1: Request arc to DATATRAINCENTER1
        output logic        local_trainerror_req,           // 0: Normal; 1: Request TRAINERROR entry

        // Partner FSM Control:
        input  logic        partner_rxdeskew_en,            // 0: Disable; 1: Enable Partner RXDESKEW sequence
        output logic        partner_rxdeskew_done,          // 0: In progress; 1: Sub-state completed
        output logic        partner_datatraincenter1_req,   // 0: No arc; 1: Request arc to DATATRAINCENTER1
        output logic        partner_trainerror_req,         // 0: Normal; 1: Request TRAINERROR entry

        // Timer Control (Combined OR logic for watchdog):
        output logic        timeout_timer_en,               // 0: Disable 8ms timer; 1: Enable 8ms timer (OR'ed)

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [6:0]  phy_rx_deskew_ctrl [15:0],      // RX deskew phase interpolator codes
        output logic        partner_sweep_en,               // 0: Partner not ready; 1: Partner holding MB for sweep
        output logic [2:0]  phy_tx_eq_preset_ctrl,          // 3-bit EQ preset code applied to TX PHY (0-5)
        output logic        phy_tx_eq_preset_en,            // 0: Hold current; 1: Apply EQ preset

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,                       // 0: Stop sweep; 1: Start/sustain D2C sweep
        input  logic [6:0]  swept_code,                     // Current code being tested
        input  wire logic [6:0]  best_code [0:15],               // Array of best deskew codes per lane
        input  logic [6:0]  min_eye_width,                  // Narrowest eye width found across lanes
        input  logic        sweep_done,                     // 0: Sweeping; 1: Sweep completed

        // =========================================================================
        // Group 5: MB Signals (Mainband Control & Status)
        // =========================================================================
        output logic [1:0]  mb_tx_clk_lane_sel,             // 00: Low; 01: Active clock; 10: Tri-state
        output logic [1:0]  mb_tx_data_lane_sel,            // 00: Low; 01: Active data; 10: Tri-state
        output logic [1:0]  mb_tx_val_lane_sel,             // 00: Low; 01: Active valid; 10: Tri-state
        output logic [1:0]  mb_tx_trk_lane_sel,             // 00: Low; 01: Active track; 10: Tri-state
        output logic        mb_rx_clk_lane_sel,             // 0: Disabled; 1: Enabled
        output logic        mb_rx_data_lane_sel,            // 0: Disabled; 1: Enabled
        output logic        mb_rx_val_lane_sel,             // 0: Disabled; 1: Enabled
        output logic        mb_rx_trk_lane_sel,             // 0: Disabled; 1: Enabled

        // =========================================================================
        // Group 6: SB Signals (Sideband Control & Status)
        // =========================================================================
        output logic        tx_sb_msg_valid,                // 0: Invalid; 1: Valid 1-cycle TX sideband pulse
        output logic [7:0]  tx_sb_msg,                      // Transmitted Sideband MsgCode
        output logic [15:0] tx_msginfo,                     // Transmitted Sideband MsgInfo payload
        output logic [63:0] tx_data_field,                  // Transmitted Sideband 64-bit Data payload

        input  logic        rx_sb_msg_valid,                // 0: Invalid; 1: Valid 1-cycle RX sideband pulse
        input  logic [7:0]  rx_sb_msg,                      // Received Sideband MsgCode
        input  logic [15:0] rx_msginfo,                     // Received Sideband MsgInfo payload
        input  logic [63:0] rx_data_field                   // Received Sideband 64-bit Data payload
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Internal Intermediate Wires
    // =========================================================================
    // Cross-die coordination signals
    wire         local_exit_dtc1_active       ;
    wire         local_end_active             ;
    wire [2:0]   partner_arc_cnt_wire         ;
    wire         local_timeout_timer_en_wire  ;
    wire         partner_timeout_timer_en_wire;

    // SB outputs from Local FSM:
    logic        local_tx_sb_msg_valid        ;
    logic [7:0]  local_tx_sb_msg              ;
    logic [15:0] local_tx_msginfo             ;
    logic [63:0] local_tx_data_field          ;

    // SB outputs from Partner FSM:
    logic        partner_tx_sb_msg_valid      ;
    logic [7:0]  partner_tx_sb_msg            ;
    logic [15:0] partner_tx_msginfo           ;
    logic [63:0] partner_tx_data_field        ;

    // MB outputs from Local FSM:
    logic [1:0]  local_mb_tx_clk_lane_sel     ;
    logic [1:0]  local_mb_tx_data_lane_sel    ;
    logic [1:0]  local_mb_tx_val_lane_sel     ;
    logic [1:0]  local_mb_tx_trk_lane_sel     ;
    logic        local_mb_rx_clk_lane_sel     ;
    logic        local_mb_rx_data_lane_sel    ;
    logic        local_mb_rx_val_lane_sel     ;
    logic        local_mb_rx_trk_lane_sel     ;

    // MB outputs from Partner FSM:
    logic [1:0]  partner_mb_tx_clk_lane_sel   ;
    logic [1:0]  partner_mb_tx_data_lane_sel  ;
    logic [1:0]  partner_mb_tx_val_lane_sel   ;
    logic [1:0]  partner_mb_tx_trk_lane_sel   ;
    logic        partner_mb_rx_clk_lane_sel   ;
    logic        partner_mb_rx_data_lane_sel  ;
    logic        partner_mb_rx_val_lane_sel   ;
    logic        partner_mb_rx_trk_lane_sel   ;


    // =========================================================================
    // 1st: Port Mapping of unit_RXDESKEW_local
    // =========================================================================
    unit_RXDESKEW_local #(
        .MAX_DESKEW_CODE                (MAX_DESKEW_CODE             ),
        .MIN_DESKEW_CODE                (MIN_DESKEW_CODE             ),
        .MAX_ARC_LIMIT                  (MAX_ARC_LIMIT               ),
        .MAX_PRESET_SEARCH              (MAX_PRESET_SEARCH           ),
        .MIN_DESIRED_SWEEP_RANGE        (MIN_DESIRED_SWEEP_RANGE     )
    ) u_RXDESKEW_local (
        // Clock and Reset Signals
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low reset
        // LTSM Control Signals
        .rxdeskew_en                    (local_rxdeskew_en           ), // Enable Local RXDESKEW
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset        ), // Soft reset control
        .timeout_8ms_occured            (timeout_8ms_occured         ), // residency timeout
        .rxdeskew_done                  (local_rxdeskew_done         ), // Sub-state done
        .datatraincenter1_req           (local_datatraincenter1_req  ), // Arc request to DTC1
        .trainerror_req                 (local_trainerror_req        ), // TRAINERROR exit request
        .local_exit_dtc1_active         (local_exit_dtc1_active      ), // Committed to arc flag
        .local_end_active               (local_end_active            ),
        .partner_arc_cnt                (partner_arc_cnt_wire        ), // From Partner: unified arc count
        // Timer Control Signals
        .timeout_timer_en               (local_timeout_timer_en_wire ), // Watchdog timer enable
        // PHY Deskew Control
        .phy_rx_deskew_ctrl             (phy_rx_deskew_ctrl          ), // Per-lane rx deskew settings
        // MB Lane Control Outputs
        .mb_tx_clk_lane_sel             (local_mb_tx_clk_lane_sel    ), // Logical clock lane TX select
        .mb_tx_data_lane_sel            (local_mb_tx_data_lane_sel   ), // Logical data lanes TX select
        .mb_tx_val_lane_sel             (local_mb_tx_val_lane_sel    ), // Logical valid lane TX select
        .mb_tx_trk_lane_sel             (local_mb_tx_trk_lane_sel    ), // Logical tracking lane TX select
        .mb_rx_clk_lane_sel             (local_mb_rx_clk_lane_sel    ), // Logical clock lane RX enable
        .mb_rx_data_lane_sel            (local_mb_rx_data_lane_sel   ), // Logical data lanes RX enable
        .mb_rx_val_lane_sel             (local_mb_rx_val_lane_sel    ), // Logical valid lane RX enable
        .mb_rx_trk_lane_sel             (local_mb_rx_trk_lane_sel    ), // Logical tracking lane RX enable
        // Speed and Clock Mode
        .is_high_speed                  (is_high_speed               ), // Speed > 32 GT/s
        .is_continuous_clk_mode         (is_continuous_clk_mode      ), // continuous clock mode
        // D2C Sweep Interface
        .sweep_en                       (sweep_en                    ), // To unit_D2C_sweep: start sweep
        .swept_code                     (swept_code                  ), // From D2C: swept code
        .best_code                      (best_code                   ), // From D2C: best code array
        .min_eye_width                  (min_eye_width               ), // From D2C: narrowest eye
        .sweep_done                     (sweep_done                  ), // From D2C: sweep done
        // Sideband Control Signals
        .tx_sb_msg_valid                (local_tx_sb_msg_valid       ), // Sideband TX valid strobe
        .tx_sb_msg                      (local_tx_sb_msg             ), // Sideband TX MsgCode
        .tx_msginfo                     (local_tx_msginfo            ), // Sideband TX MsgInfo
        .tx_data_field                  (local_tx_data_field         ), // Sideband TX data payload
        .rx_sb_msg_valid                (rx_sb_msg_valid             ), // Sideband RX valid strobe
        .rx_sb_msg                      (rx_sb_msg                   ), // Sideband RX MsgCode
        .rx_msginfo                     (rx_msginfo                  ), // Sideband RX MsgInfo
        .rx_data_field                  (rx_data_field               )  // Sideband RX data payload
    );


    // =========================================================================
    // 2nd: Port Mapping of unit_RXDESKEW_partner
    // =========================================================================
    unit_RXDESKEW_partner #(
        .MAX_VALID_PRESET               (MAX_VALID_PRESET            )
    ) u_RXDESKEW_partner (
        // Clock and Reset Signals
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low reset
        // LTSM Control Signals
        .rxdeskew_en                    (partner_rxdeskew_en         ), // Enable Partner RXDESKEW
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset        ), // Soft reset control
        .timeout_8ms_occured            (timeout_8ms_occured         ), // residency timeout
        .rxdeskew_done                  (partner_rxdeskew_done       ), // Sub-state done
        .datatraincenter1_req           (partner_datatraincenter1_req), // Arc request to DTC1
        .trainerror_req                 (partner_trainerror_req      ), // TRAINERROR exit request
        .partner_sweep_en               (partner_sweep_en            ), // Partner sweep ready indicator
        .partner_arc_cnt_out            (partner_arc_cnt_wire        ), // To Local: unified arc count
        // Cross-die Coordination
        .local_exit_dtc1_active         (local_exit_dtc1_active      ), // Coordination from Local FSM
        .local_arc_taken                (local_datatraincenter1_req  ),
        .local_end_active               (local_end_active            ),
        // Timer Control Signals
        .timeout_timer_en               (partner_timeout_timer_en_wire), // Watchdog timer enable
        // PHY TX EQ Preset Control
        .phy_tx_eq_preset_ctrl          (phy_tx_eq_preset_ctrl       ), // Applied Tx EQ preset
        .phy_tx_eq_preset_en            (phy_tx_eq_preset_en         ), // Strobe to apply preset
        // MB Lane Control Outputs
        .mb_tx_clk_lane_sel             (partner_mb_tx_clk_lane_sel  ), // Logical clock lane TX select
        .mb_tx_data_lane_sel            (partner_mb_tx_data_lane_sel ), // Logical data lanes TX select
        .mb_tx_val_lane_sel             (partner_mb_tx_val_lane_sel  ), // Logical valid lane TX select
        .mb_tx_trk_lane_sel             (partner_mb_tx_trk_lane_sel  ), // Logical tracking lane TX select
        .mb_rx_clk_lane_sel             (partner_mb_rx_clk_lane_sel  ), // Logical clock lane RX enable
        .mb_rx_data_lane_sel            (partner_mb_rx_data_lane_sel ), // Logical data lanes RX enable
        .mb_rx_val_lane_sel             (partner_mb_rx_val_lane_sel  ), // Logical valid lane RX enable
        .mb_rx_trk_lane_sel             (partner_mb_rx_trk_lane_sel  ), // Logical tracking lane RX enable
        // Speed and Clock Mode Inputs
        .is_high_speed                  (is_high_speed               ), // Speed > 32 GT/s
        .is_continuous_clk_mode         (is_continuous_clk_mode      ), // continuous clock mode
        // Sideband Control Signals
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid     ), // Sideband TX valid strobe
        .tx_sb_msg                      (partner_tx_sb_msg           ), // Sideband TX MsgCode
        .tx_msginfo                     (partner_tx_msginfo          ), // Sideband TX MsgInfo
        .tx_data_field                  (partner_tx_data_field       ), // Sideband TX data payload
        .rx_sb_msg_valid                (rx_sb_msg_valid             ), // Sideband RX valid strobe
        .rx_sb_msg                      (rx_sb_msg                   ), // Sideband RX MsgCode
        .rx_msginfo                     (rx_msginfo                  ), // Sideband RX MsgInfo
        .rx_data_field                  (rx_data_field               )  // Sideband RX data payload
    );


    // =========================================================================
    // 3rd: Multiplexing and Output Assignments
    // =========================================================================

    // Timeout timer enable OR logic:
    // If either FSM requests the 8ms timer, enable it.
    assign timeout_timer_en = local_timeout_timer_en_wire | partner_timeout_timer_en_wire;

    // Sideband TX Output arbitration:
    // Local FSM has priority: if local_tx_sb_msg_valid=1 it wins, otherwise partner drives the SB port.
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg     ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo    ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field ;

    // MB Outputs MUX: independent routing for TX and RX MB lanes.
    // This allows parallel MB TX/RX routing just like in wrapper_D2C_PT_top.
    always_comb begin : MB_OUTPUTS_MUX
        // MB TX source selection:
        // If PARTNER RXDESKEW is    active --> It    drives the TX signals.
        // If PARTNER RXDESKEW isn't active --> LOCAL drives the TX default values.
        if (partner_rxdeskew_en) begin
            mb_tx_clk_lane_sel  = partner_mb_tx_clk_lane_sel ;
            mb_tx_data_lane_sel = partner_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel  = partner_mb_tx_val_lane_sel ;
            mb_tx_trk_lane_sel  = partner_mb_tx_trk_lane_sel ;
        end
        else begin
            mb_tx_clk_lane_sel  = local_mb_tx_clk_lane_sel   ;
            mb_tx_data_lane_sel = local_mb_tx_data_lane_sel  ;
            mb_tx_val_lane_sel  = local_mb_tx_val_lane_sel   ;
            mb_tx_trk_lane_sel  = local_mb_tx_trk_lane_sel   ;
        end

        // MB RX source selection:
        // If LOCAL RXDESKEW is    active --> It      drives the RX signals.
        // If LOCAL RXDESKEW isn't active --> PARTNER drives the RX default values.
        if (local_rxdeskew_en) begin
            mb_rx_clk_lane_sel  = local_mb_rx_clk_lane_sel   ;
            mb_rx_data_lane_sel = local_mb_rx_data_lane_sel  ;
            mb_rx_val_lane_sel  = local_mb_rx_val_lane_sel   ;
            mb_rx_trk_lane_sel  = local_mb_rx_trk_lane_sel   ;
        end
        else begin
            mb_rx_clk_lane_sel  = partner_mb_rx_clk_lane_sel ;
            mb_rx_data_lane_sel = partner_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel  = partner_mb_rx_val_lane_sel ;
            mb_rx_trk_lane_sel  = partner_mb_rx_trk_lane_sel ;
        end
    end

endmodule


