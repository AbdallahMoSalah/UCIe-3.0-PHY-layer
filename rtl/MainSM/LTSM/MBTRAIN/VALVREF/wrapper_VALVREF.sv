// ====================================================================================================
// wrapper_VALVREF.sv — MBTRAIN.VALVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the VALVREF substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs
// depending on whether the Local or Partner FSM is currently driving the MB lanes.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.VALVREF (Wrapper Routing):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.VALVREF start req}              | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF start resp}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end req}                | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end resp}               | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module wrapper_VALVREF #(
        parameter int unsigned MAX_VAL_VREF_CODE = 7'd127, // Maximum Vref code
        parameter int unsigned MIN_VAL_VREF_CODE = 7'd10   // Minimum Vref code
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

        // Local FSM Control:
        input  logic        local_valvref_en,               // 0: Disable; 1: Enable Local VALVREF sequence
        output logic        local_valvref_done,             // 0: In progress; 1: Sub-state completed
        output logic        local_trainerror_req,           // 0: Normal; 1: Request TRAINERROR entry
        output logic        local_update_lane_mask,         // Pulse: update negotiated lane mask

        // Partner FSM Control:
        input  logic        partner_valvref_en,             // 0: Disable; 1: Enable Partner VALVREF sequence
        output logic        partner_valvref_done,           // 0: In progress; 1: Sub-state completed
        output logic        partner_trainerror_req,         // 0: Normal; 1: Request TRAINERROR entry

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] phy_rx_valvref_ctrl, // RX Valid Lane Vref code
        output logic        partner_sweep_en,               // 1: Partner holds MB TX pattern active

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,                       // 0: Stop sweep; 1: Start/sustain D2C sweep
        input  logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  swept_code,                     // Current Vref code being tested
        input  wire logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  best_code [0:15],          // Per-lane best Vref midpoints
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

    // MB outputs from Local FSM:
    logic [1:0]  local_mb_tx_clk_lane_sel  ;
    logic [1:0]  local_mb_tx_data_lane_sel ;
    logic [1:0]  local_mb_tx_val_lane_sel  ;
    logic [1:0]  local_mb_tx_trk_lane_sel  ;
    logic        local_mb_rx_clk_lane_sel  ;
    logic        local_mb_rx_data_lane_sel ;
    logic        local_mb_rx_val_lane_sel  ;
    logic        local_mb_rx_trk_lane_sel  ;

    // MB outputs from Partner FSM:
    logic [1:0]  partner_mb_tx_clk_lane_sel  ;
    logic [1:0]  partner_mb_tx_data_lane_sel ;
    logic [1:0]  partner_mb_tx_val_lane_sel  ;
    logic [1:0]  partner_mb_tx_trk_lane_sel  ;
    logic        partner_mb_rx_clk_lane_sel  ;
    logic        partner_mb_rx_data_lane_sel ;
    logic        partner_mb_rx_val_lane_sel  ;
    logic        partner_mb_rx_trk_lane_sel  ;


    // =========================================================================
    // 1st: Port Mapping of unit_VALVREF_local
    // =========================================================================
    unit_VALVREF_local #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE  (MIN_VAL_VREF_CODE)
    ) u_VALVREF_local (
        // Clock and Reset Signals
        .lclk                   (lclk                         ),
        .rst_n                  (rst_n                        ),
        // LTSM Control Signals
        .valvref_en             (local_valvref_en             ),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset         ),
        .valvref_done           (local_valvref_done           ),
        .trainerror_req         (local_trainerror_req         ),
        .update_lane_mask       (local_update_lane_mask       ),
        // PHY Vref Control
        .phy_rx_valvref_ctrl    (phy_rx_valvref_ctrl          ),
        // MB Lane Control Outputs
        .mb_tx_clk_lane_sel     (local_mb_tx_clk_lane_sel     ),
        .mb_tx_data_lane_sel    (local_mb_tx_data_lane_sel    ),
        .mb_tx_val_lane_sel     (local_mb_tx_val_lane_sel     ),
        .mb_tx_trk_lane_sel     (local_mb_tx_trk_lane_sel     ),
        .mb_rx_clk_lane_sel     (local_mb_rx_clk_lane_sel     ),
        .mb_rx_data_lane_sel    (local_mb_rx_data_lane_sel    ),
        .mb_rx_val_lane_sel     (local_mb_rx_val_lane_sel     ),
        .mb_rx_trk_lane_sel     (local_mb_rx_trk_lane_sel     ),
        // D2C Sweep Interface
        .sweep_en               (sweep_en                     ),
        .swept_code             (swept_code                   ),
        .best_code              (best_code                    ),
        .sweep_done             (sweep_done                   ),
        // Sideband Control Signals
        .tx_sb_msg_valid        (local_tx_sb_msg_valid        ),
        .tx_sb_msg              (local_tx_sb_msg              ),
        .tx_msginfo             (local_tx_msginfo             ),
        .tx_data_field          (local_tx_data_field          ),
        .rx_sb_msg_valid        (rx_sb_msg_valid              ),
        .rx_sb_msg              (rx_sb_msg                    ),
        .rx_msginfo             (rx_msginfo                   ),
        .rx_data_field          (rx_data_field                )
    );


    // =========================================================================
    // 2nd: Port Mapping of unit_VALVREF_partner
    // =========================================================================
    unit_VALVREF_partner u_VALVREF_partner (
        // Clock and Reset Signals
        .lclk                   (lclk                          ),
        .rst_n                  (rst_n                         ),
        // LTSM Control Signals
        .valvref_en             (partner_valvref_en            ),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset          ),
        .valvref_done           (partner_valvref_done          ),
        .trainerror_req         (partner_trainerror_req        ),
        // MB Lane Control Outputs
        .mb_tx_clk_lane_sel     (partner_mb_tx_clk_lane_sel    ),
        .mb_tx_data_lane_sel    (partner_mb_tx_data_lane_sel   ),
        .mb_tx_val_lane_sel     (partner_mb_tx_val_lane_sel    ),
        .mb_tx_trk_lane_sel     (partner_mb_tx_trk_lane_sel    ),
        .mb_rx_clk_lane_sel     (partner_mb_rx_clk_lane_sel    ),
        .mb_rx_data_lane_sel    (partner_mb_rx_data_lane_sel   ),
        .mb_rx_val_lane_sel     (partner_mb_rx_val_lane_sel    ),
        .mb_rx_trk_lane_sel     (partner_mb_rx_trk_lane_sel    ),
        .partner_sweep_en       (partner_sweep_en              ),
        // Sideband Control Signals
        .tx_sb_msg_valid        (partner_tx_sb_msg_valid       ),
        .tx_sb_msg              (partner_tx_sb_msg             ),
        .tx_msginfo             (partner_tx_msginfo            ),
        .tx_data_field          (partner_tx_data_field         ),
        .rx_sb_msg_valid        (rx_sb_msg_valid               ),
        .rx_sb_msg              (rx_sb_msg                     ),
        .rx_msginfo             (rx_msginfo                    ),
        .rx_data_field          (rx_data_field                 )
    );


    // =========================================================================
    // 3rd: Multiplexing and Output Assignments
    // =========================================================================

    // Sideband TX Output arbitration:
    // Local FSM has priority; partner drives only when local is silent.
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg      ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo     ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field  ;

    // MB Outputs MUX: independent TX/RX routing.
    //   MB TX: PARTNER drives when partner_valvref_en=1 (it sends VALTRAIN pattern);
    //          otherwise LOCAL drives (default: all TX held low during Local's sweep).
    //   MB RX: LOCAL drives when local_valvref_en=1 (it needs RX valid enabled for sampling);
    //          otherwise PARTNER drives its defaults.
    always_comb begin : MB_OUTPUTS_MUX
        // MB TX source selection:
        if (partner_valvref_en) begin
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
        if (local_valvref_en) begin
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


