// ====================================================================================================
// wrapper_DATAVREF.sv — MBTRAIN.DATAVREF Wrapper
//
// This module wraps both the Local (Initiator) and Partner (Responder) FSMs of the DATAVREF substate.
// It arbitrates their Sideband (SB) TX outputs and multiplexes their Mainband (MB) control outputs
// depending on whether the Local or Partner FSM is currently driving the MB lanes.
//
// ====================================================================================================

module wrapper_DATAVREF #(
        parameter int unsigned MAX_DATA_VREF_CODE = 'd16 // Maximum Vref code
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
        input  logic        datavref_en,               // 0: Disable; 1: Enable Local DATAVREF sequence

        // Combined outputs
        output logic        datavref_done,                  // 0: In progress; 1: Completed

        // =========================================================================
        // Group 3: PHY Control Signals
        // =========================================================================
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15], // RX Data Lanes Vref codes
        output logic        partner_sweep_en,               // 1: Partner holds MB TX pattern active

        // =========================================================================
        // Group 4: D2C Sweep Interface (For Local FSM)
        // =========================================================================
        output logic        local_sweep_en,                       // 0: Stop sweep; 1: Start/sustain D2C sweep
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  swept_code,                     // Current Vref code being tested
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  best_code [0:15],          // Per-lane best Vref midpoints
        input  logic        sweep_done,                     // 0: Sweeping; 1: Sweep completed


        // =========================================================================
        // Group 6: SB Signals (Sideband Control & Status)
        // =========================================================================
        output logic        tx_sb_msg_valid,                // 0: Invalid; 1: Valid 1-cycle TX sideband pulse
        output logic [7:0]  tx_sb_msg,                      // Transmitted Sideband MsgCode
        output logic [15:0] tx_msginfo,                     // Transmitted Sideband MsgInfo payload
        output logic [63:0] tx_data_field,                  // Transmitted Sideband 64-bit Data payload

        input  logic        rx_sb_msg_valid,                // 0: Invalid; 1: Valid 1-cycle RX sideband pulse
        input  logic [7:0]  rx_sb_msg                       // Received Sideband MsgCode
        // input  logic [15:0] rx_msginfo,                     // Received Sideband MsgInfo payload
        // input  logic [63:0] rx_data_field                   // Received Sideband 64-bit Data payload
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Internal Intermediate Wires
    // =========================================================================
    wire        local_datavref_done_wire;
    wire        partner_datavref_done_wire;

    // SB outputs from Local FSM:
    logic        local_tx_sb_msg_valid;
    logic [7:0]  local_tx_sb_msg      ;
    logic [15:0] local_tx_msginfo     ;
    logic [63:0] local_tx_data_field  ;

    // SB outputs from Partner FSM:
    logic        partner_tx_sb_msg_valid;
    logic [7:0]  partner_tx_sb_msg      ;
    logic [15:0] partner_tx_msginfo     ;
    logic [63:0] partner_tx_data_field  ;

    // =========================================================================
    // 1st: Port Mapping of unit_DATAVREF_local
    // =========================================================================
    unit_DATAVREF_local #(
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE)
    ) u_DATAVREF_local (
        // Clock and Reset Signals
        .lclk                   (lclk                         ),
        .rst_n                  (rst_n                        ),
        // LTSM Control Signals
        .datavref_en            (datavref_en                  ),
        .soft_rst_n             (soft_rst_n                   ),
        .datavref_done          (local_datavref_done_wire     ),
        // PHY Vref Control
        .phy_rx_datavref_ctrl   (phy_rx_datavref_ctrl         ),
        // MB Lane Control: moved to wrapper as static assigns
        // D2C Sweep Interface
        .sweep_en               (local_sweep_en               ),
        .swept_code             (swept_code                   ),
        .best_code              (best_code                    ),
        .sweep_done             (sweep_done                   ),
        // Sideband Control Signals
        .tx_sb_msg_valid        (local_tx_sb_msg_valid        ),
        .tx_sb_msg              (local_tx_sb_msg              ),
        .tx_msginfo             (local_tx_msginfo             ),
        .tx_data_field          (local_tx_data_field          ),
        .rx_sb_msg_valid        (rx_sb_msg_valid              ),
        .rx_sb_msg              (rx_sb_msg                    )
        // .rx_msginfo             (rx_msginfo                   ),
        // .rx_data_field          (rx_data_field                )
    );

    // =========================================================================
    // 2nd: Port Mapping of unit_DATAVREF_partner
    // =========================================================================
    unit_DATAVREF_partner u_DATAVREF_partner (
        // Clock and Reset Signals
        .lclk                   (lclk                          ),
        .rst_n                  (rst_n                         ),
        // LTSM Control Signals
        .datavref_en            (datavref_en                   ),
        .soft_rst_n             (soft_rst_n                    ),
        .datavref_done          (partner_datavref_done_wire    ),
        // MB Lane Control: moved to wrapper as static assigns
        .partner_sweep_en       (partner_sweep_en              ),
        // Sideband Control Signals
        .tx_sb_msg_valid        (partner_tx_sb_msg_valid       ),
        .tx_sb_msg              (partner_tx_sb_msg             ),
        .tx_msginfo             (partner_tx_msginfo            ),
        .tx_data_field          (partner_tx_data_field         ),
        .rx_sb_msg_valid        (rx_sb_msg_valid               ),
        .rx_sb_msg              (rx_sb_msg                     )
        // .rx_msginfo             (rx_msginfo                    ),
        // .rx_data_field          (rx_data_field                 )
    );

    // =========================================================================
    // 3rd: Multiplexing and Output Assignments
    // =========================================================================

    // Combined done logic:
    assign datavref_done  = local_datavref_done_wire & partner_datavref_done_wire;

    // Sideband TX Output arbitration:
    // Local FSM has priority; partner drives only when local is silent.
    assign tx_sb_msg_valid = local_tx_sb_msg_valid | partner_tx_sb_msg_valid;
    assign tx_sb_msg       = local_tx_sb_msg_valid ? local_tx_sb_msg       : partner_tx_sb_msg      ;
    assign tx_msginfo      = local_tx_sb_msg_valid ? local_tx_msginfo      : partner_tx_msginfo     ;
    assign tx_data_field   = local_tx_sb_msg_valid ? local_tx_data_field   : partner_tx_data_field  ;


endmodule


