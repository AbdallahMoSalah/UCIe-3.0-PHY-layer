// =============================================================================
// wrapper_D2C_PT_partner.sv — D2C Point Test Wrapper (Partner side only)
// Combines TX and RX D2C Point Test Partner modules and multiplexes their outputs.
// =============================================================================
`timescale 1ps/1ps

module wrapper_D2C_PT_partner (
    // =========================================================================
    // Group 1: Clock and Reset Signals
    // =========================================================================
    input  logic        lclk,                           // LTSM clock domain (1 GHz or 2 GHz). All transitions synchronous to lclk.
    input  logic        rst_n,                          // Active-low reset (0: reset, 1: operational). Synchronously resets FSM.

    // =========================================================================
    // Group 2: LTSM Control and Configuration Signals
    // =========================================================================
    input  logic        tx_pt_en,                       // Enable TX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
    input  logic        rx_pt_en,                       // Enable RX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
    output logic        test_d2c_done,                  // D2C point training completed (1: sequence complete, 0: in progress or inactive).
    input  logic [1:0]  d2c_clk_sampling,               // Clock phase sampling setup (00: Eye Center/In-phase, 01: Left Edge, 10: Right Edge).
    input  logic [2:0]  d2c_pattern_setup,              // Active pattern components setup (Bit0: Data Pattern, Bit1: Valid, Bit2: Clock).
    input  logic [1:0]  d2c_data_pattern_sel,           // Data pattern selection (00: LFSR pattern, 01: Per-Lane ID pattern, 10: Fixed All Zeros).
    input  logic        d2c_val_pattern_sel,            // Valid Lane pattern selection (0: VALTRAIN functional pattern, 1: Held Low / Operational).
    input  logic        d2c_pattern_mode,               // Pattern generation mode (0: Continuous mode, 1: Burst mode using UI counts).
    input  logic [15:0] d2c_burst_count,                // Burst active duration UI count (16-bit unsigned).
    input  logic [15:0] d2c_idle_count,                 // Idle low-level duration UI count (16-bit unsigned).
    input  logic [15:0] d2c_iter_count,                 // Number of burst-idle loop iterations to run (16-bit unsigned).
    input  logic [1:0]  d2c_compare_setup,              // Comparison target mode (00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane).
    input  logic [11:0] cfg_max_err_thresh_perlane,     // Max error threshold allowed per data lane before flagging failure (12-bit unsigned).
    input  logic [15:0] cfg_max_err_thresh_aggr,        // Max combined error threshold allowed across all lanes before flagging aggregate failure.
    output logic [15:0] d2c_perlane_pass,               // Per-lane pass status (always 16'h0000 on Partner wrapper side).
    output logic        d2c_aggr_pass,                  // Aggregate pass status (always 1'b0 on Partner wrapper side).
    output logic        d2c_val_pass,                   // Valid Lane pass status (always 1'b0 on Partner wrapper side).
    input  logic        timeout_8ms_occured,            // LTSM watchdog timer status (1: 8ms timeout occurred, 0: normal operation) (Unused in D2C).

    // =========================================================================
    // Group 3: MB Signals (Mainband Control & Status)
    // =========================================================================
    output logic [1:0]  mb_tx_clk_lane_sel,             // Tx Clock Lane logical mode (00: Driven Low, 01: Active Pattern, 10: Tri-Stated).
    output logic [1:0]  mb_tx_data_lane_sel,            // Tx Data Lanes logical mode (00: Driven Low, 01: Active Pattern, 10: Tri-Stated).
    output logic [1:0]  mb_tx_val_lane_sel,             // Tx Valid Lane logical mode (00: Driven Low, 01: Active Pattern, 10: Tri-Stated).
    output logic [1:0]  mb_tx_trk_lane_sel,             // Tx Tracking Lane logical mode (00: Driven Low, 01: Active Pattern, 10: Tri-Stated).
    output logic        mb_rx_clk_lane_sel,             // Enables logical clock lane receiver circuit (0: Disabled/low, 1: Active).
    output logic        mb_rx_data_lane_sel,            // Enables logical data lanes receiver circuits (0: Disabled/low, 1: Active).
    output logic        mb_rx_val_lane_sel,             // Enables logical valid lane receiver circuit (0: Disabled/low, 1: Active).
    output logic        mb_rx_trk_lane_sel,             // Enables logical tracking lane receiver circuit (0: Disabled/low, 1: Active).
    output logic        mb_tx_pattern_en,               // Enables MB transmitter pattern generators to drive active patterns on lanes.
    output logic [2:0]  mb_tx_pattern_setup,            // Sub-patterns enabled (Bit0: Data Pattern, Bit1: Valid Pattern, Bit2: Clock Pattern).
    output logic        mb_tx_lfsr_en,                  // Enables LFSR scrambler on transmitter lanes.
    output logic        mb_tx_lfsr_rst,                 // Resets Mainband transmitter LFSR generators to default seed (active-high).
    output logic        mb_rx_lfsr_en,                  // Enables LFSR descrambler on the receiver lanes.
    output logic        mb_rx_lfsr_rst,                 // Resets Mainband receiver LFSR descrambler to default seed (active-high).
    output logic        mb_rx_compare_en,               // Activates Mainband comparison logic to evaluate inputs and record errors.
    output logic [1:0]  mb_rx_compare_setup,            // Comparison mode (00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane).
    output logic [11:0] mb_rx_max_err_thresh_perlane,   // Maximum error count allowed on any single lane before asserting failure.
    output logic [15:0] mb_rx_max_err_thresh_aggr,      // Maximum combined error count allowed across all lanes before asserting failure.
    output logic        mb_tx_clk_sampling_en,          // Updates physical clock phase on Mainband transmitters using mb_tx_clk_sampling.
    output logic [1:0]  mb_tx_clk_sampling,             // Clock sampling phase setup (00: Eye Center, 01: Left Edge, 10: Right Edge).
    output logic        mb_tx_pattern_mode,             // Mainband pattern generation mode (0: Continuous, 1: Burst mode).
    output logic [15:0] mb_tx_burst_count,              // Duration of pattern burst in UI (16-bit unsigned).
    output logic [15:0] mb_tx_idle_count,               // Duration of idle (low level) in UI (16-bit unsigned).
    output logic [15:0] mb_tx_iter_count,               // Number of burst-idle loops (16-bit unsigned).
    output logic [1:0]  mb_tx_data_pattern_sel,         // Training pattern type (00: LFSR pattern, 01: Per-Lane ID pattern, 10: Fixed All Zeros).
    output logic        mb_tx_val_pattern_sel,          // Valid pattern select (0: VALTRAIN pattern, 1: Held Low).
    input  logic        mb_tx_pattern_count_done,       // Handshake from MB Tx (1: transmitter finished driving all iterations, 0: active).
    input  logic        mb_rx_compare_done,             // Feedback from MB Rx (1: comparison of configured iterations is complete, 0: active).
    input  logic        mb_rx_aggr_pass,                // Feedback from MB Rx (1: total accumulated errors are within thresholds, 0: failed).
    input  logic [15:0] mb_rx_perlane_pass,             // Feedback from MB Rx (vector showing pass (1) or fail (0) status for 16 lanes).
    input  logic        mb_rx_val_pass,                 // Feedback from MB Rx (1: Valid Lane comparison was successful, 0: failed).

    // =========================================================================
    // Group 4: SB Signals (Sideband Control & Status)
    // =========================================================================
    output logic        tx_sb_msg_valid,                // Sideband transmit request pulse (asserted for exactly 1 lclk cycle to enqueue).
    output logic [7:0]  tx_sb_msg,                      // MsgCode of sideband message to transmit.
    output logic [15:0] tx_msginfo,                     // 16-bit message information payload to transmit.
    output logic [63:0] tx_data_field,                  // 64-bit data payload to transmit.
    input  logic        rx_sb_msg_valid,                // Sideband receive strobe pulse (asserted for exactly 1 lclk cycle when message arrives).
    input  logic [7:0]  rx_sb_msg,                      // MsgCode of received sideband message.
    input  logic [15:0] rx_msginfo,                     // 16-bit message information payload from received message.
    input  logic [63:0] rx_data_field                   // 64-bit data payload from received message.
);

    // =========================================================================
    // Internal Logic Wires for Partner Sub-module Outputs
    // =========================================================================
    // From unit_TX_D2C_PT_partner:
    logic        tx_test_d2c_done;              // Completed status from TX partner module
    logic        tx_mb_rx_trk_lane_sel;         // Enables logical tracking lane receiver
    logic        tx_mb_rx_clk_lane_sel;         // Enables logical clock lane receiver
    logic        tx_mb_rx_val_lane_sel;         // Enables logical valid lane receiver
    logic        tx_mb_rx_data_lane_sel;        // Enables logical data lanes receivers
    logic [2:0]  tx_mb_rx_pattern_setup;        // Pattern components enabled
    logic        tx_mb_rx_lfsr_en;              // Enables LFSR descrambler on the receiver lanes
    logic        tx_mb_rx_lfsr_rst;             // Resets MB receiver LFSR descrambler
    logic [15:0] tx_mb_rx_iter_count;           // Expected number of burst-idle loops
    logic [15:0] tx_mb_rx_idle_count;           // Expected duration of idle in UI
    logic [15:0] tx_mb_rx_burst_count;          // Expected duration of active burst in UI
    logic        tx_mb_rx_pattern_mode;         // Receiver evaluation mode
    logic        tx_mb_rx_val_pattern_sel;      // Expected Valid pattern type
    logic [1:0]  tx_mb_rx_data_pattern_sel;     // Expected data pattern type
    logic        tx_mb_rx_compare_en;           // Activates MB comparison logic
    logic [1:0]  tx_mb_rx_compare_setup;        // Comparison target mode
    logic [11:0] tx_mb_rx_max_err_thresh_perlane;// Maximum error count allowed per data lane
    logic [15:0] tx_mb_rx_max_err_thresh_aggr;   // Maximum combined error count allowed
    logic        tx_tx_sb_msg_valid;            // Sideband transmit request pulse
    logic [7:0]  tx_tx_sb_msg;                  // MsgCode of sideband message to transmit
    logic [15:0] tx_tx_msginfo;                 // 16-bit message information payload to transmit
    logic [63:0] tx_tx_data_field;              // 64-bit data payload to transmit

    // From unit_RX_D2C_PT_partner:
    logic        rx_test_d2c_done;              // Completed status from RX partner module
    logic        rx_mb_tx_clk_sampling_en;      // Updates physical clock phase on MB transmitter
    logic [1:0]  rx_mb_tx_clk_sampling;         // Clock sampling phase setup
    logic        rx_mb_tx_pattern_en;           // Enables MB transmitter pattern generator
    logic [2:0]  rx_mb_tx_pattern_setup;        // Sub-patterns enabled
    logic        rx_mb_tx_lfsr_en;              // Enables LFSR scrambler on transmitter lanes
    logic        rx_mb_tx_lfsr_rst;             // Resets MB transmitter LFSR generator
    logic        rx_mb_tx_pattern_mode;         // MB pattern generation mode
    logic [15:0] rx_mb_tx_burst_count;          // Duration of pattern burst in UI
    logic [15:0] rx_mb_tx_idle_count;           // Duration of idle in UI
    logic [15:0] rx_mb_tx_iter_count;           // Number of burst-idle loops
    logic [1:0]  rx_mb_tx_data_pattern_sel;     // Training pattern type
    logic        rx_mb_tx_val_pattern_sel;      // Valid pattern select
    logic [1:0]  rx_mb_tx_trk_lane_sel;         // Tx Tracking Lane logical mode
    logic [1:0]  rx_mb_tx_clk_lane_sel;         // Tx Clock Lane logical mode
    logic [1:0]  rx_mb_tx_val_lane_sel;         // Tx Valid Lane logical mode
    logic [1:0]  rx_mb_tx_data_lane_sel;        // Tx Data Lanes logical mode
    logic        rx_tx_sb_msg_valid;            // Sideband transmit request pulse
    logic [7:0]  rx_tx_sb_msg;                  // MsgCode of sideband message to transmit
    logic [15:0] rx_tx_msginfo;                 // 16-bit message information payload to transmit
    logic [63:0] rx_tx_data_field;              // 64-bit data payload to transmit

    // =========================================================================
    // 1st: Port Mapping of unit_TX_D2C_PT_partner (Broadcasting Inputs)
    // =========================================================================
    unit_TX_D2C_PT_partner u_TX_D2C_PT_partner (
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low asynchronous reset
        .tx_pt_en                       (tx_pt_en                    ), // Enable/trigger TX Point Test
        .test_d2c_done                  (tx_test_d2c_done            ), // Output training completed status
        .mb_rx_trk_lane_sel             (tx_mb_rx_trk_lane_sel       ), // Output enables logical tracking lane receiver
        .mb_rx_clk_lane_sel             (tx_mb_rx_clk_lane_sel       ), // Output enables logical clock lane receiver
        .mb_rx_val_lane_sel             (tx_mb_rx_val_lane_sel       ), // Output enables logical valid lane receiver
        .mb_rx_data_lane_sel            (tx_mb_rx_data_lane_sel      ), // Output enables logical data lanes receivers
        .mb_rx_pattern_setup            (tx_mb_rx_pattern_setup      ), // Output expected pattern components configuration
        .mb_rx_lfsr_en                  (tx_mb_rx_lfsr_en            ), // Output enable RX LFSR descrambler
        .mb_rx_lfsr_rst                 (tx_mb_rx_lfsr_rst           ), // Output synchronously reset RX LFSR
        .mb_rx_iter_count               (tx_mb_rx_iter_count         ), // Output expected loops count
        .mb_rx_idle_count               (tx_mb_rx_idle_count         ), // Output expected idle duration count
        .mb_rx_burst_count              (tx_mb_rx_burst_count        ), // Output expected burst duration count
        .mb_rx_pattern_mode             (tx_mb_rx_pattern_mode       ), // Output receiver evaluation mode
        .mb_rx_val_pattern_sel          (tx_mb_rx_val_pattern_sel    ), // Output expected Valid pattern selection
        .mb_rx_data_pattern_sel         (tx_mb_rx_data_pattern_sel   ), // Output expected data pattern selection
        .mb_rx_compare_en               (tx_mb_rx_compare_en         ), // Output activate comparison logic enable
        .mb_rx_compare_setup            (tx_mb_rx_compare_setup      ), // Output comparison target mode
        .mb_rx_max_err_thresh_perlane   (tx_mb_rx_max_err_thresh_perlane), // Output per-lane max error threshold allowed
        .mb_rx_max_err_thresh_aggr      (tx_mb_rx_max_err_thresh_aggr), // Output aggregate max error threshold allowed
        .mb_rx_data_lane_mask           (d2c_pattern_setup           ), // Input negotiated lanes mask cast from d2c_pattern_setup
        .mb_rx_compare_done             (mb_rx_compare_done          ), // Input comparison complete handshake status
        .mb_rx_aggr_pass                (mb_rx_aggr_pass             ), // Input aggregate pass feedback status
        .mb_rx_perlane_pass             (mb_rx_perlane_pass          ), // Input per-lane pass feedback status vector
        .mb_rx_val_pass                 (mb_rx_val_pass              ), // Input Valid Lane comparison pass status
        .tx_sb_msg_valid                (tx_tx_sb_msg_valid          ), // Output Sideband transmit request pulse
        .tx_sb_msg                      (tx_tx_sb_msg                ), // Output MsgCode to transmit
        .tx_msginfo                     (tx_tx_msginfo               ), // Output message info payload to transmit
        .tx_data_field                  (tx_tx_data_field            ), // Output message data payload to transmit
        .rx_sb_msg_valid                (rx_sb_msg_valid             ), // Input received sideband strobe pulse
        .rx_sb_msg                      (rx_sb_msg                   ), // Input received MsgCode value
        .rx_msginfo                     (rx_msginfo                  ), // Input received message info payload
        .rx_data_field                  (rx_data_field               )  // Input received message data payload
    );

    // =========================================================================
    // 2nd: Port Mapping of unit_RX_D2C_PT_partner (Broadcasting Inputs)
    // =========================================================================
    unit_RX_D2C_PT_partner u_RX_D2C_PT_partner (
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low asynchronous reset
        .rx_pt_en                       (rx_pt_en                    ), // Enable/trigger RX Point Test
        .test_d2c_done                  (rx_test_d2c_done            ), // Output training completed status
        .mb_tx_clk_sampling_en          (rx_mb_tx_clk_sampling_en    ), // Output update TX Clock phase enable
        .mb_tx_clk_sampling             (rx_mb_tx_clk_sampling       ), // Output clock sampling phase value
        .mb_tx_pattern_en               (rx_mb_tx_pattern_en         ), // Output drive active pattern enable
        .mb_tx_pattern_setup            (rx_mb_tx_pattern_setup      ), // Output sub-patterns enabled configuration
        .mb_tx_lfsr_en                  (rx_mb_tx_lfsr_en            ), // Output enable TX LFSR scrambler
        .mb_tx_lfsr_rst                 (rx_mb_tx_lfsr_rst           ), // Output synchronously reset TX LFSR
        .mb_tx_pattern_mode             (rx_mb_tx_pattern_mode       ), // Output pattern generator mode
        .mb_tx_burst_count              (rx_mb_tx_burst_count        ), // Output burst duration UI count
        .mb_tx_idle_count               (rx_mb_tx_idle_count         ), // Output idle duration UI count
        .mb_tx_iter_count               (rx_mb_tx_iter_count         ), // Output iteration loops count
        .mb_tx_data_pattern_sel         (rx_mb_tx_data_pattern_sel   ), // Output data pattern selection
        .mb_tx_val_pattern_sel          (rx_mb_tx_val_pattern_sel    ), // Output Valid pattern selection
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done    ), // Input transmitter done handshake status
        .mb_tx_trk_lane_sel             (rx_mb_tx_trk_lane_sel       ), // Output Tx Tracking Lane logical mode
        .mb_tx_clk_lane_sel             (rx_mb_tx_clk_lane_sel       ), // Output Tx Clock Lane logical mode
        .mb_tx_val_lane_sel             (rx_mb_tx_val_lane_sel       ), // Output Tx Valid Lane logical mode
        .mb_tx_data_lane_sel            (rx_mb_tx_data_lane_sel      ), // Output Tx Data Lanes logical mode
        .tx_sb_msg_valid                (rx_tx_sb_msg_valid          ), // Output Sideband transmit request pulse
        .tx_sb_msg                      (rx_tx_sb_msg                ), // Output MsgCode to transmit
        .tx_msginfo                     (rx_tx_msginfo               ), // Output message info payload to transmit
        .tx_data_field                  (rx_tx_data_field            ), // Output message data payload to transmit
        .rx_sb_msg_valid                (rx_sb_msg_valid             ), // Input received sideband strobe pulse
        .rx_sb_msg                      (rx_sb_msg                   ), // Input received MsgCode value
        .rx_data_field                  (rx_data_field               )  // Input received message data payload
    );

    // =========================================================================
    // 3rd: Multiplexing and Output Assignments (Latch-free Combination)
    // =========================================================================
    // Status outputs tied off to low/safe defaults as partner does not produce local pass/fail logs:
    assign d2c_perlane_pass = 16'h0000;
    assign d2c_aggr_pass    = 1'b0;
    assign d2c_val_pass     = 1'b0;

    assign test_d2c_done    = tx_pt_en ? tx_test_d2c_done    : rx_test_d2c_done;

    // SB outputs multiplexing:
    assign tx_sb_msg_valid  = tx_pt_en ? tx_tx_sb_msg_valid  : rx_tx_sb_msg_valid;
    assign tx_sb_msg        = tx_pt_en ? tx_tx_sb_msg        : rx_tx_sb_msg;
    assign tx_msginfo       = tx_pt_en ? tx_tx_msginfo       : rx_tx_msginfo;
    assign tx_data_field    = tx_pt_en ? tx_tx_data_field    : rx_tx_data_field;

    // MB outputs assignments:
    always_comb begin : MB_OUTPUTS_MUX
        if (tx_pt_en) begin
            mb_tx_clk_lane_sel              = 2'b00; // TX partner only has RX control
            mb_tx_data_lane_sel             = 2'b00; // TX partner only has RX control
            mb_tx_val_lane_sel              = 2'b00; // TX partner only has RX control
            mb_tx_trk_lane_sel              = 2'b00; // TX partner only has RX control
            mb_rx_clk_lane_sel              = tx_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel             = tx_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel              = tx_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel              = tx_mb_rx_trk_lane_sel;
            mb_tx_pattern_en                = 1'b0; // TX partner only has RX control
            mb_tx_pattern_setup             = 3'b000; // TX partner only has RX control
            mb_tx_lfsr_en                   = 1'b0; // TX partner only has RX control
            mb_tx_lfsr_rst                  = 1'b0; // TX partner only has RX control
            mb_rx_lfsr_en                   = tx_mb_rx_lfsr_en;
            mb_rx_lfsr_rst                  = tx_mb_rx_lfsr_rst;
            mb_rx_compare_en                = tx_mb_rx_compare_en;
            mb_rx_compare_setup             = tx_mb_rx_compare_setup;
            mb_rx_max_err_thresh_perlane    = tx_mb_rx_max_err_thresh_perlane;
            mb_rx_max_err_thresh_aggr       = tx_mb_rx_max_err_thresh_aggr;
            mb_tx_clk_sampling_en           = 1'b0; // TX partner only has RX control
            mb_tx_clk_sampling              = 2'b00; // TX partner only has RX control
            mb_tx_pattern_mode              = 1'b0; // TX partner only has RX control
            mb_tx_burst_count               = 16'd0; // TX partner only has RX control
            mb_tx_idle_count                = 16'd0; // TX partner only has RX control
            mb_tx_iter_count                = 16'd0; // TX partner only has RX control
            mb_tx_data_pattern_sel          = 2'b00; // TX partner only has RX control
            mb_tx_val_pattern_sel           = 1'b0; // TX partner only has RX control
        end else if (rx_pt_en) begin
            mb_tx_clk_lane_sel              = rx_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel             = rx_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel              = rx_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel              = rx_mb_tx_trk_lane_sel;
            mb_rx_clk_lane_sel              = 1'b0; // RX partner only has TX control
            mb_rx_data_lane_sel             = 1'b0; // RX partner only has TX control
            mb_rx_val_lane_sel              = 1'b0; // RX partner only has TX control
            mb_rx_trk_lane_sel              = 1'b0; // RX partner only has TX control
            mb_tx_pattern_en                = rx_mb_tx_pattern_en;
            mb_tx_pattern_setup             = rx_mb_tx_pattern_setup;
            mb_tx_lfsr_en                   = rx_mb_tx_lfsr_en;
            mb_tx_lfsr_rst                  = rx_mb_tx_lfsr_rst;
            mb_rx_lfsr_en                   = 1'b0; // RX partner only has TX control
            mb_rx_lfsr_rst                  = 1'b0; // RX partner only has TX control
            mb_rx_compare_en                = 1'b0; // RX partner only has TX control
            mb_rx_compare_setup             = 2'b00; // RX partner only has TX control
            mb_rx_max_err_thresh_perlane    = 12'd0; // RX partner only has TX control
            mb_rx_max_err_thresh_aggr       = 16'd0; // RX partner only has TX control
            mb_tx_clk_sampling_en           = rx_mb_tx_clk_sampling_en;
            mb_tx_clk_sampling              = rx_mb_tx_clk_sampling;
            mb_tx_pattern_mode              = rx_mb_tx_pattern_mode;
            mb_tx_burst_count               = rx_mb_tx_burst_count;
            mb_tx_idle_count                = rx_mb_tx_idle_count;
            mb_tx_iter_count                = rx_mb_tx_iter_count;
            mb_tx_data_pattern_sel          = rx_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel           = rx_mb_tx_val_pattern_sel;
        end else begin
            // All inactive default safe ties:
            mb_tx_clk_lane_sel              = 2'b00;
            mb_tx_data_lane_sel             = 2'b00;
            mb_tx_val_lane_sel              = 2'b00;
            mb_tx_trk_lane_sel              = 2'b00;
            mb_rx_clk_lane_sel              = 1'b0;
            mb_rx_data_lane_sel             = 1'b0;
            mb_rx_val_lane_sel              = 1'b0;
            mb_rx_trk_lane_sel              = 1'b0;
            mb_tx_pattern_en                = 1'b0;
            mb_tx_pattern_setup             = 3'b000;
            mb_tx_lfsr_en                   = 1'b0;
            mb_tx_lfsr_rst                  = 1'b0;
            mb_rx_lfsr_en                   = 1'b0;
            mb_rx_lfsr_rst                  = 1'b0;
            mb_rx_compare_en                = 1'b0;
            mb_rx_compare_setup             = 2'b00;
            mb_rx_max_err_thresh_perlane    = 12'd0;
            mb_rx_max_err_thresh_aggr       = 16'd0;
            mb_tx_clk_sampling_en           = 1'b0;
            mb_tx_clk_sampling              = 2'b00;
            mb_tx_pattern_mode              = 1'b0;
            mb_tx_burst_count               = 16'd0;
            mb_tx_idle_count                = 16'd0;
            mb_tx_iter_count                = 16'd0;
            mb_tx_data_pattern_sel          = 2'b00;
            mb_tx_val_pattern_sel           = 1'b0;
        end
    end

endmodule
