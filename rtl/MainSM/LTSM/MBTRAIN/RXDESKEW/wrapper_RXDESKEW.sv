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
        parameter int unsigned MAX_DESKEW_CODE          = 'd16, // Maximum deskew code (inclusive)
        parameter int unsigned MIN_DESKEW_CODE          = 'd0 , // Minimum deskew code (inclusive)
        parameter int unsigned MAX_ARC_LIMIT            = 'd4 , // Maximum DTC1 arc iterations (spec = 4)
        parameter int unsigned MAX_VALID_PRESET         = 'd5 , // Valid TX EQ preset range limit
        parameter int unsigned MIN_DESIRED_SWEEP_RANGE  = (MAX_DESKEW_CODE - MIN_DESKEW_CODE + 1) * 75 / 100
    ) (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,                           // LTSM clock domain (1 GHz or 2 GHz)
        input  logic        rst_n,                          // 0: Asynchronous reset; 1: Normal operation

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        soft_rst_n,                     // 0: Soft reset active; 1: Normal operation
        input  logic        is_high_speed,                  // 0: <= 32 GT/s; 1: > 32 GT/s
        input  logic        is_continuous_clk_mode,         // 0: Strobe mode; 1: Continuous clock mode

        // FSM Control & Status:
        input  logic        rxdeskew_en,                    // 0: Disable; 1: Enable RXDESKEW sequence
        output logic        rxdeskew_done,                  // 0: In progress; 1: Sub-state completed
        output logic        datatraincenter1_req,           // 0: No arc; 1: Request arc to DATATRAINCENTER1
        output logic        trainerror_req,                 // 0: Normal; 1: Request TRAINERROR entry

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  phy_rx_deskew_ctrl [15:0],      // RX deskew phase interpolator codes
        output logic        partner_sweep_en,               // 0: Partner not ready; 1: Partner holding MB for sweep
        output logic [2:0]  phy_tx_eq_preset_ctrl,          // 3-bit EQ preset code applied to TX PHY (0-5)
        output logic        phy_tx_eq_preset_en,            // 0: Hold current; 1: Apply EQ preset

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output      logic                                  local_sweep_en,         // 0: Stop sweep; 1: Start/sustain D2C sweep
        input       logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  swept_code,       // Current code being tested
        input  wire logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  best_code [0:15], // Array of best deskew codes per lane
        input       logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  min_eye_width,    // Narrowest eye width found across lanes
        input       logic                                  sweep_done,       // 0: Sweeping; 1: Sweep completed

        // =========================================================================
        // Group 5: MB Signals (Mainband Control & Status)
        // =========================================================================
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
        input  logic [15:0] rx_msginfo                      // Received Sideband MsgInfo payload
        // input  logic [63:0] rx_data_field                   // Received Sideband 64-bit Data payload
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Internal Intermediate Wires
    // =========================================================================
    // Cross-die coordination signals
    wire         local_exit_dtc1_active       ;
    wire         local_end_active             ;
    wire [2:0]   partner_arc_cnt_wire         ;

    logic        local_rxdeskew_done_wire;
    logic        local_datatraincenter1_req_wire;
    logic        local_trainerror_req_wire;

    logic        partner_rxdeskew_done_wire;
    logic        partner_datatraincenter1_req_wire;
    logic        partner_trainerror_req_wire;

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


    // =========================================================================
    // 1st: Port Mapping of unit_RXDESKEW_local
    // =========================================================================
    unit_RXDESKEW_local #(
        .MAX_DESKEW_CODE                (MAX_DESKEW_CODE             ),
        .MIN_DESKEW_CODE                (MIN_DESKEW_CODE             ),
        .MAX_ARC_LIMIT                  (MAX_ARC_LIMIT               ),
        .MAX_VALID_PRESET               (MAX_VALID_PRESET            ),
        .MIN_DESIRED_SWEEP_RANGE        (MIN_DESIRED_SWEEP_RANGE     )
    ) u_RXDESKEW_local (
        .lclk                           (lclk                        ),
        .rst_n                          (rst_n                       ),
        .rxdeskew_en                    (rxdeskew_en                 ),
        .soft_rst_n                     (soft_rst_n                  ),
        .rxdeskew_done                  (local_rxdeskew_done_wire    ),
        .datatraincenter1_req           (local_datatraincenter1_req_wire),
        .trainerror_req                 (local_trainerror_req_wire   ),
        .local_exit_dtc1_active         (local_exit_dtc1_active      ),
        .local_end_active               (local_end_active            ),
        .partner_arc_cnt                (partner_arc_cnt_wire        ),
        .phy_rx_deskew_ctrl             (phy_rx_deskew_ctrl          ),
        // MB RX signals moved to wrapper as static assigns
        .is_high_speed                  (is_high_speed               ),
        .sweep_en                       (local_sweep_en              ),
        .swept_code                     (swept_code                  ),
        .best_code                      (best_code                   ),
        .min_eye_width                  (min_eye_width               ),
        .sweep_done                     (sweep_done                  ),
        .tx_sb_msg_valid                (local_tx_sb_msg_valid       ),
        .tx_sb_msg                      (local_tx_sb_msg             ),
        .tx_msginfo                     (local_tx_msginfo            ),
        .tx_data_field                  (local_tx_data_field         ),
        .rx_sb_msg_valid                (rx_sb_msg_valid             ),
        .rx_sb_msg                      (rx_sb_msg                   ),
        .rx_msginfo                     (rx_msginfo                  )
    );


    // =========================================================================
    // 2nd: Port Mapping of unit_RXDESKEW_partner
    // =========================================================================
    unit_RXDESKEW_partner #(
        .MAX_VALID_PRESET               (MAX_VALID_PRESET            )
    ) u_RXDESKEW_partner (
        .lclk                           (lclk                        ),
        .rst_n                          (rst_n                       ),
        .rxdeskew_en                    (rxdeskew_en                 ),
        .soft_rst_n                     (soft_rst_n                  ),
        .rxdeskew_done                  (partner_rxdeskew_done_wire  ),
        .datatraincenter1_req           (partner_datatraincenter1_req_wire),
        .trainerror_req                 (partner_trainerror_req_wire ),
        .partner_sweep_en               (partner_sweep_en            ),
        .partner_arc_cnt_out            (partner_arc_cnt_wire        ),
        .local_exit_dtc1_active         (local_exit_dtc1_active      ),
        .local_arc_taken                (local_datatraincenter1_req_wire),
        .local_end_active               (local_end_active            ),
        .phy_tx_eq_preset_ctrl          (phy_tx_eq_preset_ctrl       ),
        .phy_tx_eq_preset_en            (phy_tx_eq_preset_en         ),
        // MB TX signals moved to wrapper as static/conditional assigns
        // Speed and clock-mode inputs consumed in wrapper assign below
        .tx_sb_msg_valid                (partner_tx_sb_msg_valid     ),
        .tx_sb_msg                      (partner_tx_sb_msg           ),
        .tx_msginfo                     (partner_tx_msginfo          ),
        .tx_data_field                  (partner_tx_data_field       ),
        .rx_sb_msg_valid                (rx_sb_msg_valid             ),
        .rx_sb_msg                      (rx_sb_msg                   ),
        .rx_msginfo                     (rx_msginfo                  )
    );


    // =========================================================================
    // 3rd: Multiplexing and Output Assignments
    // =========================================================================

    // Combine terminal signals
    assign rxdeskew_done        = local_rxdeskew_done_wire & partner_rxdeskew_done_wire;
    assign datatraincenter1_req = local_datatraincenter1_req_wire | partner_datatraincenter1_req_wire;
    assign trainerror_req       = local_trainerror_req_wire | partner_trainerror_req_wire;

    // Sideband TX Output arbitration:
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg     ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo    ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field ;

    // =========================================================================
    // MB Lane Assignments — Static per spec §4.5.3.4.10 MBTRAIN.RXDESKEW:
    //   Local   (RX side): CLK/DATA/VAL RX enabled, TRK RX disabled.
    //   Partner (TX side): CLK TX=speed-dep, DATA/VAL/TRK TX=00.
    //   wrapper_MBTRAIN ss_active gates these when substate is not active.
    // =========================================================================
    assign mb_rx_clk_lane_sel  = 1'b1;
    assign mb_rx_data_lane_sel = 1'b1;
    assign mb_rx_val_lane_sel  = 1'b1;
    assign mb_rx_trk_lane_sel  = 1'b0;
    // CLK TX: free-running if >32GT/s or continuous clock mode; else held low

endmodule


