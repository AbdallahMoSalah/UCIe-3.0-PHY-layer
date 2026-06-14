// ====================================================================================================
// wrapper_DATAVREF.sv — MBTRAIN.DATAVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the DATAVREF substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs
// depending on whether the Local or Partner FSM is currently driving the MB lanes.
//
// ====================================================================================================

module wrapper_DATAVREF #(
        parameter int unsigned MAX_DATA_VREF_CODE = 7'd127, // Maximum Vref code
        parameter int unsigned MIN_DATA_VREF_CODE = 7'd10   // Minimum Vref code
    ) (
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,                           // LTSM clock domain
        input  logic        rst_n,                          // 0: Asynchronous reset; 1: Normal operation

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic        soft_rst_n,                      // 0: Soft reset active; 1: Normal operation

        // Local FSM Control:
        input  logic        local_datavref_en,               // 0: Disable; 1: Enable Local DATAVREF sequence
        output logic        local_update_lane_mask,         // Pulse: update negotiated lane mask

        // Partner FSM Control:
        input  logic        partner_datavref_en,             // 0: Disable; 1: Enable Partner DATAVREF sequence

        // Combined outputs
        output logic        datavref_done,                  // 0: In progress; 1: Completed
        output logic        trainerror_req,                  // 0: Normal; 1: Request TRAINERROR entry

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15], // RX Data Lanes Vref codes
        output logic        partner_sweep_en,               // 1: Partner holds MB TX pattern active

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        sweep_en,                       // 0: Stop sweep; 1: Start/sustain D2C sweep
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  swept_code,                     // Current Vref code being tested
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  best_code [0:15],          // Per-lane best Vref midpoints
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
    wire        local_datavref_done_wire;
    wire        partner_datavref_done_wire;
    wire        local_trainerror_req_wire;
    wire        partner_trainerror_req_wire;

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
    // 1st: Port Mapping of unit_DATAVREF_local
    // =========================================================================
    unit_DATAVREF_local #(
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE  (MIN_DATA_VREF_CODE)
    ) u_DATAVREF_local (
        // Clock and Reset Signals
        .lclk                   (lclk                         ),
        .rst_n                  (rst_n                        ),
        // LTSM Control Signals
        .datavref_en            (local_datavref_en            ),
        .soft_rst_n             (soft_rst_n                   ),
        .datavref_done          (local_datavref_done_wire     ),
        .trainerror_req         (local_trainerror_req_wire    ),
        .update_lane_mask       (local_update_lane_mask       ),
        // PHY Vref Control
        .phy_rx_datavref_ctrl   (phy_rx_datavref_ctrl         ),
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
    // 2nd: Port Mapping of unit_DATAVREF_partner
    // =========================================================================
    unit_DATAVREF_partner u_DATAVREF_partner (
        // Clock and Reset Signals
        .lclk                   (lclk                          ),
        .rst_n                  (rst_n                         ),
        // LTSM Control Signals
        .datavref_en            (partner_datavref_en           ),
        .soft_rst_n             (soft_rst_n                    ),
        .datavref_done          (partner_datavref_done_wire    ),
        .trainerror_req         (partner_trainerror_req_wire   ),
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

    // Combined done and trainerror logic:
    assign datavref_done  = local_datavref_done_wire & partner_datavref_done_wire;
    assign trainerror_req = local_trainerror_req_wire | partner_trainerror_req_wire;

    // Sideband TX Output arbitration:
    // Local FSM has priority; partner drives only when local is silent.
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg      ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo     ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field  ;

    // MB Outputs MUX: independent TX/RX routing.
    //   MB TX: PARTNER drives when partner_datavref_en=1;
    //          otherwise LOCAL drives.
    //   MB RX: LOCAL drives when local_datavref_en=1;
    //          otherwise PARTNER drives.
    always_comb begin : MB_OUTPUTS_MUX
        // MB TX source selection:
        if (partner_datavref_en) begin
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
        if (local_datavref_en) begin
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


