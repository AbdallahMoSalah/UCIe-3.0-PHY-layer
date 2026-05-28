// =============================================================================
// wrapper_D2C_PT_local.sv — D2C Point Test Wrapper (Local side only)
// Combines TX and RX D2C Point Test Local modules and multiplexes their outputs.
// =============================================================================

module wrapper_D2C_PT_local (
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
        input  logic [1:0]  d2c_clk_sampling,               // 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
        input  logic [2:0]  d2c_pattern_setup,              // Bit0: Data Pattern Enable, Bit1: Valid Pattern Enable, Bit2: Clock Pattern Enable.
        input  logic [1:0]  d2c_data_pattern_sel,           // 00: LFSR pattern, 01: Per-Lane ID, 10: Fixed All Zeros, 11: Reserved.
        input  logic        d2c_val_pattern_sel,            // 0: VALTRAIN/functional pattern, 1: Held Low / Operational Valid.
        input  logic        d2c_pattern_mode,               // 0: Continuous mode (indefinite), 1: Burst mode (burst/idle counts).
        input  logic [15:0] d2c_burst_count,                // Unsigned 16-bit burst duration in Unit Intervals (UI).
        input  logic [15:0] d2c_idle_count,                 // Unsigned 16-bit idle duration in Unit Intervals (UI).
        input  logic [15:0] d2c_iter_count,                 // Unsigned 16-bit iteration count of burst-idle cycles.
        input  logic [1:0]  d2c_compare_setup,              // 00: Per-Lane comparison, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.
        input  logic [11:0] cfg_max_err_thresh_perlane,     // Unsigned 12-bit max error threshold per lane from Register File.
        input  logic [15:0] cfg_max_err_thresh_aggr,        // Unsigned 16-bit max aggregate error threshold from Register File.
        output logic [15:0] d2c_perlane_pass,               // Per-lane error status; each bit=1 if that lane passed. (didn't excesse the threshold)
        output logic        d2c_aggr_pass,                  // 16-bit aggregate error count across all data lanes. (1: success, 0: failed)
        output logic        d2c_val_pass,                   // 1: No Valid Lane error, 0: Valid Lane pattern mismatch detected.

        // =========================================================================
        // Group 3: MB Signals (Mainband Control & Status)
        // =========================================================================
        output logic [1:0]  mb_tx_trk_lane_sel,             // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_clk_lane_sel,             // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_val_lane_sel,             // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_data_lane_sel,            // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic        mb_rx_trk_lane_sel,             // 0: Disabled (RX logical tracking lane inactive). 1: Enabled.
        output logic        mb_rx_clk_lane_sel,             // 0: Disabled. 1: Enabled (RX logical clock lane active).
        output logic        mb_rx_val_lane_sel,             // 0: Disabled. 1: Enabled (RX logical valid lane active).
        output logic        mb_rx_data_lane_sel,            // 0: Disabled. 1: Enabled (RX logical data lanes active).

        output logic        mb_tx_pattern_en,               // 0: TX in static idle. 1: Drive active training pattern on configured TX lanes.
        output logic [2:0]  mb_tx_pattern_setup,            // Bit0: Data Enable, Bit1: Valid Enable, Bit2: Clock Enable.
        output logic [2:0]  mb_rx_pattern_setup,            // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output logic        mb_tx_lfsr_en,                  // 0: Disable TX LFSR. 1: Enable TX LFSR scrambler.
        output logic        mb_tx_lfsr_rst,                 // 0: Normal operation. 1: Synchronously reset TX LFSR to default seed.
        output logic        mb_rx_lfsr_en,                  // 0: Disable RX LFSR descrambler. 1: Enable RX LFSR descrambler.
        output logic        mb_rx_lfsr_rst,                 // 0: Normal operation. 1: Synchronously reset RX LFSR to default seed.
        output logic [15:0] mb_rx_iter_count,               // (For Rx) Iteration Count: Indicates the iteration count of bursts followed by idle.
        output logic [15:0] mb_rx_idle_count,               // (For Rx) IDLE Count: Indicates the duration of low following the burst (UI count).
        output logic [15:0] mb_rx_burst_count,              // (For Rx) Burst Count: Indicates the duration of selected pattern (UI count).
        output logic        mb_rx_pattern_mode,             // (For Rx) 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        output logic        mb_rx_val_pattern_sel,          // (For Rx) 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
        output logic [1:0]  mb_rx_data_pattern_sel,         // (For Rx) Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.
        output logic        mb_rx_compare_en,               // 0: Disable RX comparison circuit. 1: Enable RX comparison, start error accumulation.
        output logic [1:0]  mb_rx_compare_setup,            // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane comparison.
        output logic [11:0] mb_rx_max_err_thresh_perlane,   // Drives per-lane max error threshold to RX comparison block.
        output logic [15:0] mb_rx_max_err_thresh_aggr,      // Drives aggregate max error threshold to RX comparison block.
        output logic        mb_tx_clk_sampling_en,          // 0: TX Clock phase unchanged. 1: Update TX Clock phase.
        output logic [1:0]  mb_tx_clk_sampling,             // 00: Eye Center, 01: Left Edge, 10: Right Edge.
        output logic        mb_tx_pattern_mode,             // 0: Continuous mode, 1: Burst mode.
        output logic [15:0] mb_tx_burst_count,              // Unsigned 16-bit burst duration UI count.
        output logic [15:0] mb_tx_idle_count,               // Unsigned 16-bit idle duration UI count.
        output logic [15:0] mb_tx_iter_count,               // Unsigned 16-bit iteration count.
        output logic [1:0]  mb_tx_data_pattern_sel,         // 00: LFSR, 01: Per-Lane ID, 10: Fixed All Zeros.
        output logic        mb_tx_val_pattern_sel,          // 0: VALTRAIN/functional, 1: Held Low.
        input  logic        mb_tx_pattern_count_done,       // 0: TX pattern generator is transmitting. 1: Completed all iterations.
        input  logic        mb_rx_compare_done,             // 0: Comparison in progress. 1: Comparison of configured pattern iterations is complete.
        input  logic        mb_rx_aggr_pass,                // 1: Aggregate comparison passed (error count within threshold). 0: Failed.
        input  logic [15:0] mb_rx_perlane_pass,             // 16-bit status vector; each bit corresponds to an operational lane.
        input  logic        mb_rx_val_pass,                 // 1: Valid Lane pattern matched. 0: Valid Lane pattern mismatch detected.

        // =========================================================================
        // Group 4: SB Signals (Sideband Control & Status)
        // =========================================================================
        output logic        tx_sb_msg_valid,                // Asserted for exactly 1 lclk cycle to transmit a sideband message.
        output logic [7:0]  tx_sb_msg,                      // MsgCode value to transmit. See SB message table above.
        output logic [15:0] tx_msginfo,                     // MsgInfo payload field (varies by message type).
        output logic [63:0] tx_data_field,                  // 64-bit data payload (varies by message type).
        input  logic        rx_sb_msg_valid,                // Pulse (1 lclk cycle) when a valid sideband message has been received from partner.
        input  logic [7:0]  rx_sb_msg,                      // Received MsgCode value from partner die.
        input  logic [15:0] rx_msginfo,                     // Received MsgInfo payload field.
        input  logic [63:0] rx_data_field                   // Received 64-bit data payload.
    );

    // =========================================================================
    // Internal Logic Wires for Sub-module Outputs
    // =========================================================================
    // From unit_TX_D2C_PT_local:
    logic        tx_test_d2c_done;               // Completed status from TX local module
    logic [15:0] tx_d2c_perlane_pass;            // Per-lane pass status from TX local module
    logic        tx_d2c_aggr_pass;               // Aggregate pass status from TX local module
    logic        tx_d2c_val_pass;                // Valid Lane pass status from TX local module
    logic        tx_mb_tx_clk_sampling_en;       // Updates physical clock phase on MB transmitter
    logic [1:0]  tx_mb_tx_clk_sampling;          // Clock sampling phase setup
    logic        tx_mb_tx_pattern_en;            // Enables MB transmitter pattern generator
    logic [2:0]  tx_mb_tx_pattern_setup;         // Sub-patterns enabled
    logic        tx_mb_tx_lfsr_en;               // Enables LFSR scrambler on transmitter lanes
    logic        tx_mb_tx_lfsr_rst;              // Resets MB transmitter LFSR generator
    logic        tx_mb_tx_pattern_mode;          // MB pattern generation mode
    logic [15:0] tx_mb_tx_burst_count;           // Duration of pattern burst in UI
    logic [15:0] tx_mb_tx_idle_count;            // Duration of idle in UI
    logic [15:0] tx_mb_tx_iter_count;            // Number of burst-idle loops
    logic [1:0]  tx_mb_tx_data_pattern_sel;      // Training pattern type
    logic        tx_mb_tx_val_pattern_sel;       // Valid pattern select
    logic [1:0]  tx_mb_tx_trk_lane_sel;          // Tx Tracking Lane logical mode
    logic [1:0]  tx_mb_tx_clk_lane_sel;          // Tx Clock Lane logical mode
    logic [1:0]  tx_mb_tx_val_lane_sel;          // Tx Valid Lane logical mode
    logic [1:0]  tx_mb_tx_data_lane_sel;         // Tx Data Lanes logical mode
    logic        tx_tx_sb_msg_valid;             // Sideband transmit request pulse
    logic [7:0]  tx_tx_sb_msg;                   // MsgCode of sideband message to transmit
    logic [15:0] tx_tx_msginfo;                  // 16-bit message information payload to transmit
    logic [63:0] tx_tx_data_field;               // 64-bit data payload to transmit

    // From unit_RX_D2C_PT_local:
    logic        rx_test_d2c_done;               // Completed status from RX local module
    logic [15:0] rx_d2c_perlane_pass;            // Per-lane pass status from RX local module
    logic        rx_d2c_aggr_pass;               // Aggregate pass status from RX local module
    logic        rx_d2c_val_pass;                // Valid Lane pass status from RX local module
    logic [2:0]  rx_mb_rx_pattern_setup;         // Pattern components enabled
    logic        rx_mb_rx_lfsr_en;               // Enables LFSR descrambler on the receiver lanes
    logic        rx_mb_rx_lfsr_rst;              // Resets MB receiver LFSR descrambler
    logic [15:0] rx_mb_rx_iter_count;            // Expected number of burst-idle loops to evaluate
    logic [15:0] rx_mb_rx_idle_count;            // Expected duration of idle low interval in UI
    logic [15:0] rx_mb_rx_burst_count;           // Expected duration of active burst in UI
    logic        rx_mb_rx_pattern_mode;          // Receiver evaluation mode
    logic        rx_mb_rx_val_pattern_sel;       // Expected Valid pattern type
    logic [1:0]  rx_mb_rx_data_pattern_sel;      // Expected data pattern type
    logic        rx_mb_rx_compare_en;            // Activates MB comparison logic to evaluate inputs
    logic [11:0] rx_mb_rx_max_err_thresh_perlane;// Maximum error count allowed on any single lane
    logic [15:0] rx_mb_rx_max_err_thresh_aggr;   // Maximum combined error count allowed
    logic [1:0]  rx_mb_rx_compare_setup;         // Comparison mode
    logic        rx_mb_rx_trk_lane_sel;          // Enables logical tracking lane receiver circuit
    logic        rx_mb_rx_clk_lane_sel;          // Enables logical clock lane receiver circuit
    logic        rx_mb_rx_val_lane_sel;          // Enables logical valid lane receiver circuit
    logic        rx_mb_rx_data_lane_sel;         // Enables logical data lanes receiver circuits
    logic        rx_tx_sb_msg_valid;             // Sideband transmit request pulse
    logic [7:0]  rx_tx_sb_msg;                   // MsgCode of sideband message to transmit
    logic [15:0] rx_tx_msginfo;                  // 16-bit message information payload to transmit
    logic [63:0] rx_tx_data_field;               // 64-bit data payload to transmit

    // =========================================================================
    // 1st: Port Mapping of unit_TX_D2C_PT_local (Broadcasting Inputs)
    // =========================================================================
    unit_TX_D2C_PT_local u_TX_D2C_PT_local (
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low asynchronous reset
        .tx_pt_en                       (tx_pt_en                    ), // Enable/trigger TX Point Test
        .test_d2c_done                  (tx_test_d2c_done            ), // Output training completed status
        .d2c_clk_sampling               (d2c_clk_sampling            ), // Sampling phase configuration input
        .d2c_pattern_setup              (d2c_pattern_setup           ), // Pattern setup components configuration input
        .d2c_data_pattern_sel           (d2c_data_pattern_sel        ), // Selected data pattern configuration input
        .d2c_val_pattern_sel            (d2c_val_pattern_sel         ), // Selected Valid pattern configuration input
        .d2c_pattern_mode               (d2c_pattern_mode            ), // Pattern mode configuration input
        .d2c_burst_count                (d2c_burst_count             ), // Burst duration UI count configuration input
        .d2c_idle_count                 (d2c_idle_count              ), // Idle duration UI count configuration input
        .d2c_iter_count                 (d2c_iter_count              ), // Burst-idle loops count configuration input
        .d2c_compare_setup              (d2c_compare_setup           ), // Target comparison mode configuration input
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane  ), // Max error threshold allowed per lane input
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr     ), // Max combined error threshold allowed input
        .d2c_perlane_pass               (tx_d2c_perlane_pass         ), // Output per-lane pass status
        .d2c_aggr_pass                  (tx_d2c_aggr_pass            ), // Output aggregate pass status
        .d2c_val_pass                   (tx_d2c_val_pass             ), // Output Valid Lane pass status
        .mb_tx_clk_sampling_en          (tx_mb_tx_clk_sampling_en    ), // Output update TX Clock phase enable
        .mb_tx_clk_sampling             (tx_mb_tx_clk_sampling       ), // Output clock sampling phase value
        .mb_tx_pattern_en               (tx_mb_tx_pattern_en         ), // Output drive active pattern enable
        .mb_tx_pattern_setup            (tx_mb_tx_pattern_setup      ), // Output sub-patterns enabled configuration
        .mb_tx_lfsr_en                  (tx_mb_tx_lfsr_en            ), // Output enable TX LFSR scrambler
        .mb_tx_lfsr_rst                 (tx_mb_tx_lfsr_rst           ), // Output synchronously reset TX LFSR
        .mb_tx_pattern_mode             (tx_mb_tx_pattern_mode       ), // Output pattern generator mode
        .mb_tx_burst_count              (tx_mb_tx_burst_count        ), // Output burst duration UI count
        .mb_tx_idle_count               (tx_mb_tx_idle_count         ), // Output idle duration UI count
        .mb_tx_iter_count               (tx_mb_tx_iter_count         ), // Output iteration loops count
        .mb_tx_data_pattern_sel         (tx_mb_tx_data_pattern_sel   ), // Output data pattern selection
        .mb_tx_val_pattern_sel          (tx_mb_tx_val_pattern_sel    ), // Output Valid pattern selection
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done    ), // Input transmitter done handshake status
        .mb_tx_trk_lane_sel             (tx_mb_tx_trk_lane_sel       ), // Output Tx Tracking Lane logical mode
        .mb_tx_clk_lane_sel             (tx_mb_tx_clk_lane_sel       ), // Output Tx Clock Lane logical mode
        .mb_tx_val_lane_sel             (tx_mb_tx_val_lane_sel       ), // Output Tx Valid Lane logical mode
        .mb_tx_data_lane_sel            (tx_mb_tx_data_lane_sel      ), // Output Tx Data Lanes logical mode
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
    // 2nd: Port Mapping of unit_RX_D2C_PT_local (Broadcasting Inputs)
    // =========================================================================
    unit_RX_D2C_PT_local u_RX_D2C_PT_local (
        .lclk                           (lclk                        ), // LTSM clock domain
        .rst_n                          (rst_n                       ), // Active-low asynchronous reset
        .rx_pt_en                       (rx_pt_en                    ), // Enable/trigger RX Point Test
        .test_d2c_done                  (rx_test_d2c_done            ), // Output training completed status
        .d2c_clk_sampling               (d2c_clk_sampling            ), // Sampling phase configuration input
        .d2c_pattern_setup              (d2c_pattern_setup           ), // Pattern setup components configuration input
        .d2c_data_pattern_sel           (d2c_data_pattern_sel        ), // Selected data pattern configuration input
        .d2c_val_pattern_sel            (d2c_val_pattern_sel         ), // Selected Valid pattern configuration input
        .d2c_pattern_mode               (d2c_pattern_mode            ), // Pattern mode configuration input
        .d2c_burst_count                (d2c_burst_count             ), // Burst duration UI count configuration input
        .d2c_idle_count                 (d2c_idle_count              ), // Idle duration UI count configuration input
        .d2c_iter_count                 (d2c_iter_count              ), // Burst-idle loops count configuration input
        .d2c_compare_setup              (d2c_compare_setup           ), // Target comparison mode configuration input
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane  ), // Max error threshold allowed per lane input
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr     ), // Max combined error threshold allowed input
        .d2c_perlane_pass               (rx_d2c_perlane_pass         ), // Output per-lane pass status
        .d2c_aggr_pass                  (rx_d2c_aggr_pass            ), // Output aggregate pass status
        .d2c_val_pass                   (rx_d2c_val_pass             ), // Output Valid Lane pass status
        .mb_rx_pattern_setup            (rx_mb_rx_pattern_setup      ), // Output expected pattern components configuration
        .mb_rx_lfsr_en                  (rx_mb_rx_lfsr_en            ), // Output enable RX LFSR descrambler
        .mb_rx_lfsr_rst                 (rx_mb_rx_lfsr_rst           ), // Output synchronously reset RX LFSR
        .mb_rx_iter_count               (rx_mb_rx_iter_count         ), // Output expected loops count
        .mb_rx_idle_count               (rx_mb_rx_idle_count         ), // Output expected idle duration count
        .mb_rx_burst_count              (rx_mb_rx_burst_count        ), // Output expected burst duration count
        .mb_rx_pattern_mode             (rx_mb_rx_pattern_mode       ), // Output receiver evaluation mode
        .mb_rx_val_pattern_sel          (rx_mb_rx_val_pattern_sel    ), // Output expected Valid pattern selection
        .mb_rx_data_pattern_sel         (rx_mb_rx_data_pattern_sel   ), // Output expected data pattern selection
        .mb_rx_compare_en               (rx_mb_rx_compare_en         ), // Output activate comparison logic enable
        .mb_rx_max_err_thresh_perlane   (rx_mb_rx_max_err_thresh_perlane), // Output per-lane max error threshold allowed
        .mb_rx_max_err_thresh_aggr      (rx_mb_rx_max_err_thresh_aggr), // Output aggregate max error threshold allowed
        .mb_rx_compare_setup            (rx_mb_rx_compare_setup      ), // Output comparison target mode
        .mb_rx_compare_done             (mb_rx_compare_done          ), // Input comparison complete handshake status
        .mb_rx_aggr_pass                (mb_rx_aggr_pass             ), // Input aggregate pass feedback status
        .mb_rx_perlane_pass             (mb_rx_perlane_pass          ), // Input per-lane pass feedback status vector
        .mb_rx_val_pass                 (mb_rx_val_pass              ), // Input Valid Lane comparison pass status
        .mb_rx_trk_lane_sel             (rx_mb_rx_trk_lane_sel       ), // Output enables logical tracking lane receiver
        .mb_rx_clk_lane_sel             (rx_mb_rx_clk_lane_sel       ), // Output enables logical clock lane receiver
        .mb_rx_val_lane_sel             (rx_mb_rx_val_lane_sel       ), // Output enables logical valid lane receiver
        .mb_rx_data_lane_sel            (rx_mb_rx_data_lane_sel      ), // Output enables logical data lanes receivers
        .tx_sb_msg_valid                (rx_tx_sb_msg_valid          ), // Output Sideband transmit request pulse
        .tx_sb_msg                      (rx_tx_sb_msg                ), // Output MsgCode to transmit
        .tx_msginfo                     (rx_tx_msginfo               ), // Output message info payload to transmit
        .tx_data_field                  (rx_tx_data_field            ), // Output message data payload to transmit
        .rx_sb_msg_valid                (rx_sb_msg_valid             ), // Input received sideband strobe pulse
        .rx_sb_msg                      (rx_sb_msg                   )  // Input received MsgCode value
    );

    // =========================================================================
    // 3rd: Multiplexing and Output Assignments (Latch-free Combination)
    // =========================================================================
    assign test_d2c_done    = tx_pt_en ? tx_test_d2c_done    : rx_test_d2c_done;
    assign d2c_perlane_pass = tx_pt_en ? tx_d2c_perlane_pass : rx_d2c_perlane_pass;
    assign d2c_aggr_pass    = tx_pt_en ? tx_d2c_aggr_pass    : rx_d2c_aggr_pass;
    assign d2c_val_pass     = tx_pt_en ? tx_d2c_val_pass     : rx_d2c_val_pass;

    // SB outputs multiplexing:
    assign tx_sb_msg_valid  = tx_pt_en ? tx_tx_sb_msg_valid  : rx_tx_sb_msg_valid;
    assign tx_sb_msg        = tx_pt_en ? tx_tx_sb_msg        : rx_tx_sb_msg;
    assign tx_msginfo       = tx_pt_en ? tx_tx_msginfo       : rx_tx_msginfo;
    assign tx_data_field    = tx_pt_en ? tx_tx_data_field    : rx_tx_data_field;

    // MB outputs assignments:
    always_comb begin : MB_OUTPUTS_MUX
        if (tx_pt_en) begin
            mb_tx_clk_lane_sel              = tx_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel             = tx_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel              = tx_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel              = tx_mb_tx_trk_lane_sel;
            mb_rx_clk_lane_sel              = 1'b0; // RX is inactive
            mb_rx_data_lane_sel             = 1'b0; // RX is inactive
            mb_rx_val_lane_sel              = 1'b0; // RX is inactive
            mb_rx_trk_lane_sel              = 1'b0; // RX is inactive
            mb_tx_pattern_en                = tx_mb_tx_pattern_en;
            mb_tx_pattern_setup             = tx_mb_tx_pattern_setup;
            mb_tx_lfsr_en                   = tx_mb_tx_lfsr_en;
            mb_tx_lfsr_rst                  = tx_mb_tx_lfsr_rst;
            mb_rx_lfsr_en                   = 1'b0; // RX is inactive
            mb_rx_lfsr_rst                  = 1'b0; // RX is inactive
            mb_rx_compare_en                = 1'b0; // RX is inactive
            mb_rx_compare_setup             = 2'b00; // RX is inactive
            mb_rx_max_err_thresh_perlane    = 12'd0; // RX is inactive
            mb_rx_max_err_thresh_aggr       = 16'd0; // RX is inactive
            mb_tx_clk_sampling_en           = tx_mb_tx_clk_sampling_en;
            mb_tx_clk_sampling              = tx_mb_tx_clk_sampling;
            mb_tx_pattern_mode              = tx_mb_tx_pattern_mode;
            mb_tx_burst_count               = tx_mb_tx_burst_count;
            mb_tx_idle_count                = tx_mb_tx_idle_count;
            mb_tx_iter_count                = tx_mb_tx_iter_count;
            mb_tx_data_pattern_sel          = tx_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel           = tx_mb_tx_val_pattern_sel;
            mb_rx_pattern_setup             = 3'b000;
            mb_rx_iter_count                = 16'd0;
            mb_rx_idle_count                = 16'd0;
            mb_rx_burst_count               = 16'd0;
            mb_rx_pattern_mode              = 1'b0;
            mb_rx_val_pattern_sel           = 1'b0;
            mb_rx_data_pattern_sel          = 2'b00;
        end else if (rx_pt_en) begin
            mb_tx_clk_lane_sel              = 2'b00; // TX is inactive
            mb_tx_data_lane_sel             = 2'b00; // TX is inactive
            mb_tx_val_lane_sel              = 2'b00; // TX is inactive
            mb_tx_trk_lane_sel              = 2'b00; // TX is inactive
            mb_rx_clk_lane_sel              = rx_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel             = rx_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel              = rx_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel              = rx_mb_rx_trk_lane_sel;
            mb_tx_pattern_en                = 1'b0; // TX is inactive
            mb_tx_pattern_setup             = 3'b000; // TX is inactive
            mb_tx_lfsr_en                   = 1'b0; // TX is inactive
            mb_tx_lfsr_rst                  = 1'b0; // TX is inactive
            mb_rx_lfsr_en                   = rx_mb_rx_lfsr_en;
            mb_rx_lfsr_rst                  = rx_mb_rx_lfsr_rst;
            mb_rx_compare_en                = rx_mb_rx_compare_en;
            mb_rx_compare_setup             = rx_mb_rx_compare_setup;
            mb_rx_max_err_thresh_perlane    = rx_mb_rx_max_err_thresh_perlane;
            mb_rx_max_err_thresh_aggr       = rx_mb_rx_max_err_thresh_aggr;
            mb_tx_clk_sampling_en           = 1'b0; // TX is inactive
            mb_tx_clk_sampling              = 2'b00; // TX is inactive
            mb_tx_pattern_mode              = 1'b0; // TX is inactive
            mb_tx_burst_count               = 16'd0; // TX is inactive
            mb_tx_idle_count                = 16'd0; // TX is inactive
            mb_tx_iter_count                = 16'd0; // TX is inactive
            mb_tx_data_pattern_sel          = 2'b00; // TX is inactive
            mb_tx_val_pattern_sel           = 1'b0; // TX is inactive
            mb_rx_pattern_setup             = rx_mb_rx_pattern_setup;
            mb_rx_iter_count                = rx_mb_rx_iter_count;
            mb_rx_idle_count                = rx_mb_rx_idle_count;
            mb_rx_burst_count               = rx_mb_rx_burst_count;
            mb_rx_pattern_mode              = rx_mb_rx_pattern_mode;
            mb_rx_val_pattern_sel           = rx_mb_rx_val_pattern_sel;
            mb_rx_data_pattern_sel          = rx_mb_rx_data_pattern_sel;
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
            mb_rx_pattern_setup             = 3'b000;
            mb_rx_iter_count                = 16'd0;
            mb_rx_idle_count                = 16'd0;
            mb_rx_burst_count               = 16'd0;
            mb_rx_pattern_mode              = 1'b0;
            mb_rx_val_pattern_sel           = 1'b0;
            mb_rx_data_pattern_sel          = 2'b00;
        end
    end

endmodule
