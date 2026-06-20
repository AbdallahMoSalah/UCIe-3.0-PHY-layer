
// =============================================================================
// wrapper_D2C_PT_top.sv — D2C Point Test Top-Level Wrapper
//
// This module acts as the top-layer glue for all D2C Point Test scenarios:
//   - TX-initiated test (local die sends pattern, partner die receives)
//   - RX-initiated test (partner die sends pattern, local die receives)
//
// Both tests may be triggered from either MBINIT or MBTRAIN substates.
// This module performs three functions:
//   1. MUX between MBINIT and MBTRAIN configuration signals (feeds wrapper_D2C_PT_local).
//   2. Route MB TX/RX signals between local and partner sub-wrappers depending
//      on which test is active (four mutually exclusive cases per the UCIe spec).
//   3. Arbitrate the single SB TX output between local and partner sub-wrappers.
// =============================================================================

module wrapper_D2C_PT(
        // =========================================================================
        // Group 1: Clock and Reset Signals
        // =========================================================================
        input  logic        lclk,                           // LTSM clock domain (1 GHz or 2 GHz). All transitions synchronous to lclk.
        input  logic        rst_n,                          // Active-low reset (0: reset, 1: operational). Synchronously resets FSM.

        // =========================================================================
        // Group 2: LTSM Control and Configuration Signals
        // =========================================================================
        input  logic [2:0]  mb_rx_data_lane_mask,           // 000: None, 001: Lanes 0-7, 010: Lanes 8-15, 011: Lanes 0-15, 100: Lanes 0-3, 101: Lanes 4-7.

        // broadcasted signals for MBINIT & MBTRAIN Substates FSMs.
        output logic        local_test_d2c_done,            // (for TX/RX_D2C_PT) D2C point training completed (1: sequence complete, 0: in progress or inactive).
        output logic        partner_test_d2c_done,          // (for TX/RX_D2C_PT) D2C point training completed (1: sequence complete, 0: in progress or inactive).
        output logic [15:0] d2c_perlane_pass,               // (for TX/RX_D2C_PT) Per-lane error status; each bit=1 if that lane passed. (didn't excesse the threshold)
        output logic        d2c_aggr_pass,                  // (for TX/RX_D2C_PT) 16-bit aggregate error count across all data lanes. (1: success, 0: failed)
        output logic        d2c_val_pass,                   // (for TX/RX_D2C_PT) 1: No Valid Lane error, 0: Valid Lane pattern mismatch detected.

        // These signals are coming from MBINIT State (from its MBINIT.REPAIRMB substate) and MBTRAIN State (from its substates: MBTRAIN.VALVREF, MBTRAIN.DATAVREF, MBTRAIN.VALTRAINVREF, MBTRAIN.DATATRAINVREF, MBTRAIN.VALTRAINCENTER, MBTRAIN.DATATRAINCENTER1, MBTRAIN.RXDESKEW, MBTRAIN.DATATRAINCENTER2, MBTRAIN.LINKSPEED).
        input  logic        local_tx_pt_en,                 // (for TX_D2C_PT) Enable local   TX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
        input  logic        partner_tx_pt_en,               // (for TX_D2C_PT) Enable partner TX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
        input  logic        local_rx_pt_en,                 // (for RX_D2C_PT) Enable local   RX D2C point test (1: enable/initiate test handshake, 0: disable/idle). RX_D2C_PT test is used only in MBTRAIN substates.
        input  logic        partner_rx_pt_en,               // (for RX_D2C_PT) Enable partner RX D2C point test (1: enable/initiate test handshake, 0: disable/idle). RX_D2C_PT test is used only in MBTRAIN substates.
        input  logic [1:0]  d2c_clk_sampling,               // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
        input  logic [2:0]  d2c_pattern_setup,              // (for TX/RX_D2C_PT) Bit0: Data Pattern Enable, Bit1: Valid Pattern Enable, Bit2: Clock Pattern Enable.
        input  logic [1:0]  d2c_data_pattern_sel,           // (for TX/RX_D2C_PT) 00: LFSR pattern, 01: Per-Lane ID, 10: Fixed All Zeros, 11: Reserved.
        input  logic        d2c_val_pattern_sel,            // (for TX/RX_D2C_PT) 0: VALTRAIN/functional pattern, 1: Held Low / Operational Valid.
        input  logic        d2c_pattern_mode,               // (for TX/RX_D2C_PT) 0: Continuous mode (indefinite), 1: Burst mode (burst/idle counts).
        input  logic [15:0] d2c_burst_count,                // (for TX/RX_D2C_PT) Unsigned 16-bit burst duration in Unit Intervals (UI).
        input  logic [15:0] d2c_idle_count,                 // (for TX/RX_D2C_PT) Unsigned 16-bit idle duration in Unit Intervals (UI).
        input  logic [15:0] d2c_iter_count,                 // (for TX/RX_D2C_PT) Unsigned 16-bit iteration count of burst-idle cycles.
        input  logic [1:0]  d2c_compare_setup,              // (for TX/RX_D2C_PT) 00: Per-Lane comparison, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.

        // These signals are unified for both MBINIT and MBTRAIN substates.
        input  logic [11:0] cfg_max_err_thresh_perlane,             // Unsigned 12-bit max error threshold per lane from Register File.
        input  logic [15:0] cfg_max_err_thresh_aggr,                // Unsigned 16-bit max aggregate error threshold from Register File.

        // =========================================================================
        // Group 3: MB Signals (Mainband Control & Status)
        // =========================================================================
        output logic        mb_rx_trk_lane_sel,             // 0: Disabled (RX logical tracking lane inactive). 1: Enabled.
        output logic        mb_rx_clk_lane_sel,             // 0: Disabled. 1: Enabled (RX logical clock lane active).
        output logic        mb_rx_val_lane_sel,             // 0: Disabled. 1: Enabled (RX logical valid lane active).
        output logic        mb_rx_data_lane_sel,            // 0: Disabled. 1: Enabled (RX logical data lanes active).

        // These signals are MUXed depending on the signals: `mbtrain_local_tx_pt_en`, `mbtrain_partner_tx_pt_en`, `mbtrain_local_rx_pt_en`, `mbtrain_partner_rx_pt_en`, `mbinit_local_tx_pt_en`, `mbinit_partner_tx_pt_en`.
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

        // These input signals are broadcasted to both of TX_D2C_PT and RX_D2C_PT FSMs.
        //     (ex: 'mb_tx_pattern_count_done' is broadcasted to both of unit_TX_D2C_PT_local   and unit_RX_D2C_PT_partner)
        input  logic        mb_tx_pattern_count_done,       // 0: TX pattern generator is transmitting. 1: Completed all iterations.
        input  logic        mb_rx_aggr_pass,                // 1: Aggregate comparison passed (error count within threshold). 0: Failed.
        input  logic [15:0] mb_rx_perlane_pass,             // 16-bit status vector; each bit corresponds to an operational lane.
        input  logic        mb_rx_val_pass,                 // 1: Valid Lane pattern matched. 0: Valid Lane pattern mismatch detected.

        // =========================================================================
        // Group 4: SB Signals (Sideband Control & Status)
        // =========================================================================
        // These outputs are MUXed depending on the `tx_sb_msg_valid` signal and from where we git it? (Is from `TX_D2C_PT` or from `RX_D2C_PT`?)
        // Just to remember: It's imposible to get `tx_sb_msg_valid` = 1 from unit_TX_D2C_PT_local FSM and `tx_sb_msg_valid` = 1 from unit_TX_D2C_PT_partner FSM at the same moment. so, We are safe.
        //                   It's imposible to get `tx_sb_msg_valid` = 1 from unit_RX_D2C_PT_local FSM and `tx_sb_msg_valid` = 1 from unit_RX_D2C_PT_partner FSM at the same moment. so, We are safe.
        output logic        tx_sb_msg_valid,                // Asserted for exactly 1 lclk cycle to transmit a sideband message.
        output logic [7:0]  tx_sb_msg,                      // MsgCode value to transmit. See SB message table above.
        output logic [15:0] tx_msginfo,                     // MsgInfo payload field (varies by message type).
        output logic [63:0] tx_data_field,                  // 64-bit data payload (varies by message type).

        // These SB input are broadcasted to both of TX_D2C_PT and RX_D2C_PT FSMs
        input  logic        rx_sb_msg_valid,                // Pulse (1 lclk cycle) when a valid sideband message has been received from partner.
        input  logic [7:0]  rx_sb_msg,                      // Received MsgCode value from partner die.
        input  logic [15:0] rx_msginfo,                     // Received MsgInfo payload field.
        input  logic [63:0] rx_data_field                   // Received 64-bit data payload.
    );

    // =========================================================================
    // Internal Convenience Wires: Aggregated Enable Signals
    // =========================================================================
    // These signals are MUXed depending on the signals: `mbtrain_local_tx_pt_en`, `mbtrain_partner_tx_pt_en`, `mbtrain_local_rx_pt_en`, `mbtrain_partner_rx_pt_en`, `mbinit_local_tx_pt_en`, `mbinit_partner_tx_pt_en`.
    //     (ex1: If `mbtrain_local_tx_pt_en`  =1 OR `mbinit_local_tx_pt_en`  =1 ==> The Tx signals are connected to `wrapper_D2C_PT_local`  , while the Rx signals are connected to `wrapper_D2C_PT_local`   if (`mbtrain_partner_tx_pt_en`=0 AND `mbinit_partner_tx_pt_en`=0) )
    //     (ex2: If `mbtrain_partner_tx_pt_en`=1 OR `mbinit_partner_tx_pt_en`=1 ==> The Rx signals are connected to `wrapper_D2C_PT_partner`, while the Tx signals are connected to `wrapper_D2C_PT_partner` if (`mbtrain_local_tx_pt_en`  =0 AND `mbinit_local_tx_pt_en`  =0) )
    //     (ex3: If `mbtrain_local_rx_pt_en`  =1                                ==> The Rx signals are connected to `wrapper_D2C_PT_local`  , while the Tx signals are connected to `wrapper_D2C_PT_local`   if (`mbtrain_partner_rx_pt_en`=0)                                 )
    //     (ex4: If `mbtrain_partner_rx_pt_en`=1                                ==> The Tx signals are connected to `wrapper_D2C_PT_partner`, while the Rx signals are connected to `wrapper_D2C_PT_partner` if (`mbtrain_local_rx_pt_en`  =0)                                 )
    // Just to remember: It's imposible to get ((`mbtrain_local_tx_pt_en`  =1 OR `mbinit_local_tx_pt_en`  =1) AND `mbtrain_local_rx_pt_en`  =1) at the same moment. so, There is no conflict in Tx and Rx signals assignment, and We are safe.
    //                   It's imposible to get ((`mbtrain_partner_tx_pt_en`=1 OR `mbinit_partner_tx_pt_en`=1) AND `mbtrain_partner_rx_pt_en`=1) at the same moment. so, There is no conflict in Tx and Rx signals assignment, and We are safe.



    // =========================================================================
    // Internal Wires: Sub-wrapper MB Outputs
    // =========================================================================
    // From wrapper_D2C_PT_local:
    logic        loc_mb_rx_trk_lane_sel;
    logic        loc_mb_rx_clk_lane_sel;
    logic        loc_mb_rx_val_lane_sel;
    logic        loc_mb_rx_data_lane_sel;
    logic        loc_mb_tx_pattern_en;
    logic [2:0]  loc_mb_tx_pattern_setup;
    logic [2:0]  loc_mb_rx_pattern_setup;
    logic        loc_mb_tx_lfsr_en;
    logic        loc_mb_tx_lfsr_rst;
    logic        loc_mb_rx_lfsr_en;
    logic        loc_mb_rx_lfsr_rst;
    logic [15:0] loc_mb_rx_iter_count;
    logic [15:0] loc_mb_rx_idle_count;
    logic [15:0] loc_mb_rx_burst_count;
    logic        loc_mb_rx_pattern_mode;
    logic        loc_mb_rx_val_pattern_sel;
    logic [1:0]  loc_mb_rx_data_pattern_sel;
    logic        loc_mb_rx_compare_en;
    logic [1:0]  loc_mb_rx_compare_setup;
    logic [11:0] loc_mb_rx_max_err_thresh_perlane;
    logic [15:0] loc_mb_rx_max_err_thresh_aggr;
    logic        loc_mb_tx_clk_sampling_en;
    logic [1:0]  loc_mb_tx_clk_sampling;
    logic        loc_mb_tx_pattern_mode;
    logic [15:0] loc_mb_tx_burst_count;
    logic [15:0] loc_mb_tx_idle_count;
    logic [15:0] loc_mb_tx_iter_count;
    logic [1:0]  loc_mb_tx_data_pattern_sel;
    logic        loc_mb_tx_val_pattern_sel;

    // From wrapper_D2C_PT_partner:
    logic        ptn_mb_rx_trk_lane_sel;
    logic        ptn_mb_rx_clk_lane_sel;
    logic        ptn_mb_rx_val_lane_sel;
    logic        ptn_mb_rx_data_lane_sel;
    logic        ptn_mb_tx_pattern_en;
    logic [2:0]  ptn_mb_tx_pattern_setup;
    logic [2:0]  ptn_mb_rx_pattern_setup;
    logic        ptn_mb_tx_lfsr_en;
    logic        ptn_mb_tx_lfsr_rst;
    logic        ptn_mb_rx_lfsr_en;
    logic        ptn_mb_rx_lfsr_rst;
    logic [15:0] ptn_mb_rx_iter_count;
    logic [15:0] ptn_mb_rx_idle_count;
    logic [15:0] ptn_mb_rx_burst_count;
    logic        ptn_mb_rx_pattern_mode;
    logic        ptn_mb_rx_val_pattern_sel;
    logic [1:0]  ptn_mb_rx_data_pattern_sel;
    logic        ptn_mb_rx_compare_en;
    logic [1:0]  ptn_mb_rx_compare_setup;
    logic [11:0] ptn_mb_rx_max_err_thresh_perlane;
    logic [15:0] ptn_mb_rx_max_err_thresh_aggr;
    logic        ptn_mb_tx_clk_sampling_en;
    logic [1:0]  ptn_mb_tx_clk_sampling;
    logic        ptn_mb_tx_pattern_mode;
    logic [15:0] ptn_mb_tx_burst_count;
    logic [15:0] ptn_mb_tx_idle_count;
    logic [15:0] ptn_mb_tx_iter_count;
    logic [1:0]  ptn_mb_tx_data_pattern_sel;
    logic        ptn_mb_tx_val_pattern_sel;

    // Internal wires: Sub-wrapper SB Outputs
    logic        loc_tx_sb_msg_valid;
    logic [7:0]  loc_tx_sb_msg;
    logic [15:0] loc_tx_msginfo;
    logic [63:0] loc_tx_data_field;

    logic        ptn_tx_sb_msg_valid;
    logic [7:0]  ptn_tx_sb_msg;
    logic [15:0] ptn_tx_msginfo;
    logic [63:0] ptn_tx_data_field;

    // Internal wires: Sub-wrapper completion and result outputs
    logic        loc_test_d2c_done;
    logic [15:0] loc_d2c_perlane_pass;
    logic        loc_d2c_aggr_pass;
    logic        loc_d2c_val_pass;
    logic        ptn_test_d2c_done;

    // =========================================================================
    // Sub-wrapper Instantiation 1: wrapper_D2C_PT_local
    // =========================================================================
    wrapper_D2C_PT_local u_wrapper_D2C_PT_local (
        // ── Group 1: Clock and Reset ─────────────────────────────────────────
        .lclk                           (lclk                          ), // LTSM clock domain
        .rst_n                          (rst_n                         ), // Active-low reset

        // ── Group 2: LTSM Control and Configuration ──────────────────────────
        // Enable signals: local module acts as TX-local when local_tx_pt_en=1,
        //                 local module acts as RX-local when local_rx_pt_en=1.
        .tx_pt_en                       (local_tx_pt_en                ), // 1: local TX D2C test is active.
        .rx_pt_en                       (local_rx_pt_en                ), // 1: local RX D2C test is active.
        .test_d2c_done                  (loc_test_d2c_done             ), // Completion flag from local sub-wrapper.
        .d2c_clk_sampling               (d2c_clk_sampling              ), // Selected clock sampling phase config.
        .d2c_pattern_setup              (d2c_pattern_setup             ), // Selected pattern component enable bits.
        .d2c_data_pattern_sel           (d2c_data_pattern_sel          ), // Selected data pattern type.
        .d2c_val_pattern_sel            (d2c_val_pattern_sel           ), // Selected valid pattern type.
        .d2c_pattern_mode               (d2c_pattern_mode              ), // Selected pattern generation mode.
        .d2c_burst_count                (d2c_burst_count               ), // Selected burst duration in UI.
        .d2c_idle_count                 (d2c_idle_count                ), // Selected idle duration in UI.
        .d2c_iter_count                 (d2c_iter_count                ), // Selected iteration loop count.
        .d2c_compare_setup              (d2c_compare_setup             ), // Selected comparison mode.
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane    ), // Selected per-lane error threshold.
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr       ), // aggregate error threshold.
        .d2c_perlane_pass               (loc_d2c_perlane_pass          ), // Per-lane pass status from local module.
        .d2c_aggr_pass                  (loc_d2c_aggr_pass             ), // Aggregate pass status from local module.
        .d2c_val_pass                   (loc_d2c_val_pass              ), // Valid Lane pass status from local module.

        // ── Group 3: MB Signals (outputs captured to loc_* wires) ────────────
        .mb_rx_trk_lane_sel             (loc_mb_rx_trk_lane_sel        ), // Local RX tracking lane enable.
        .mb_rx_clk_lane_sel             (loc_mb_rx_clk_lane_sel        ), // Local RX clock lane enable.
        .mb_rx_val_lane_sel             (loc_mb_rx_val_lane_sel        ), // Local RX valid lane enable.
        .mb_rx_data_lane_sel            (loc_mb_rx_data_lane_sel       ), // Local RX data lane enable.
        .mb_tx_pattern_en               (loc_mb_tx_pattern_en          ), // Local TX active pattern enable.
        .mb_tx_pattern_setup            (loc_mb_tx_pattern_setup       ), // Local TX pattern sub-components.
        .mb_rx_pattern_setup            (loc_mb_rx_pattern_setup       ), // Local RX expected pattern components.
        .mb_tx_lfsr_en                  (loc_mb_tx_lfsr_en             ), // Local TX LFSR scrambler enable.
        .mb_tx_lfsr_rst                 (loc_mb_tx_lfsr_rst            ), // Local TX LFSR synchronous reset.
        .mb_rx_lfsr_en                  (loc_mb_rx_lfsr_en             ), // Local RX LFSR descrambler enable.
        .mb_rx_lfsr_rst                 (loc_mb_rx_lfsr_rst            ), // Local RX LFSR synchronous reset.
        .mb_rx_iter_count               (loc_mb_rx_iter_count          ), // Local RX expected iteration count.
        .mb_rx_idle_count               (loc_mb_rx_idle_count          ), // Local RX expected idle duration.
        .mb_rx_burst_count              (loc_mb_rx_burst_count         ), // Local RX expected burst duration.
        .mb_rx_pattern_mode             (loc_mb_rx_pattern_mode        ), // Local RX evaluation mode.
        .mb_rx_val_pattern_sel          (loc_mb_rx_val_pattern_sel     ), // Local RX expected valid pattern.
        .mb_rx_data_pattern_sel         (loc_mb_rx_data_pattern_sel    ), // Local RX expected data pattern.
        .mb_rx_compare_en               (loc_mb_rx_compare_en          ), // Local RX comparison circuit enable.
        .mb_rx_compare_setup            (loc_mb_rx_compare_setup       ), // Local RX comparison mode.
        .mb_rx_max_err_thresh_perlane   (loc_mb_rx_max_err_thresh_perlane), // Local RX per-lane error threshold.
        .mb_rx_max_err_thresh_aggr      (loc_mb_rx_max_err_thresh_aggr ), // Local RX aggregate error threshold.
        .mb_tx_clk_sampling_en          (loc_mb_tx_clk_sampling_en     ), // Local TX clock phase update enable.
        .mb_tx_clk_sampling             (loc_mb_tx_clk_sampling        ), // Local TX clock phase value.
        .mb_tx_pattern_mode             (loc_mb_tx_pattern_mode        ), // Local TX pattern generator mode.
        .mb_tx_burst_count              (loc_mb_tx_burst_count         ), // Local TX burst duration.
        .mb_tx_idle_count               (loc_mb_tx_idle_count          ), // Local TX idle duration.
        .mb_tx_iter_count               (loc_mb_tx_iter_count          ), // Local TX iteration count.
        .mb_tx_data_pattern_sel         (loc_mb_tx_data_pattern_sel    ), // Local TX data pattern selection.
        .mb_tx_val_pattern_sel          (loc_mb_tx_val_pattern_sel     ), // Local TX valid pattern selection.
        // Broadcast inputs (shared with both sub-wrappers):
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done      ), // 1: TX pattern generator completed all iterations.
        .mb_rx_aggr_pass                (mb_rx_aggr_pass               ), // 1: Aggregate comparison passed.
        .mb_rx_perlane_pass             (mb_rx_perlane_pass            ), // Per-lane pass vector.
        .mb_rx_val_pass                 (mb_rx_val_pass                ), // 1: Valid lane comparison passed.

        // ── Group 4: SB Signals ───────────────────────────────────────────────
        .tx_sb_msg_valid                (loc_tx_sb_msg_valid           ), // Local SB transmit pulse (1 cycle).
        .tx_sb_msg                      (loc_tx_sb_msg                 ), // Local SB MsgCode to transmit.
        .tx_msginfo                     (loc_tx_msginfo                ), // Local SB msginfo payload.
        .tx_data_field                  (loc_tx_data_field             ), // Local SB 64-bit data payload.
        .rx_sb_msg_valid                (rx_sb_msg_valid               ), // Broadcast: received SB strobe pulse.
        .rx_sb_msg                      (rx_sb_msg                     ), // Broadcast: received MsgCode.
        .rx_msginfo                     (rx_msginfo                    ), // Broadcast: received msginfo payload.
        .rx_data_field                  (rx_data_field                 )  // Broadcast: received data payload.
    );

    // =========================================================================
    // Sub-wrapper Instantiation 2: wrapper_D2C_PT_partner
    // =========================================================================
    wrapper_D2C_PT_partner u_wrapper_D2C_PT_partner (
        // ── Group 1: Clock and Reset ─────────────────────────────────────────
        .lclk                           (lclk                          ), // LTSM clock domain
        .rst_n                          (rst_n                         ), // Active-low reset

        // ── Group 2: LTSM Control and Configuration ──────────────────────────
        // Enable signals: partner module acts as RX-partner when partner_tx_pt_en=1,
        //                 partner module acts as TX-partner when partner_rx_pt_en=1.
        .tx_pt_en                       (partner_tx_pt_en              ), // 1: partner TX D2C test active (from MBINIT or MBTRAIN).
        .rx_pt_en                       (partner_rx_pt_en              ), // 1: partner RX D2C test active (MBTRAIN only).
        .test_d2c_done                  (ptn_test_d2c_done             ), // Completion flag from partner sub-wrapper.
        .mb_rx_data_lane_mask           (mb_rx_data_lane_mask          ), // Negotiated lane mask (passes through directly).

        // ── Group 3: MB Signals (outputs captured to ptn_* wires) ────────────
        .mb_rx_trk_lane_sel             (ptn_mb_rx_trk_lane_sel        ), // Partner RX tracking lane enable.
        .mb_rx_clk_lane_sel             (ptn_mb_rx_clk_lane_sel        ), // Partner RX clock lane enable.
        .mb_rx_val_lane_sel             (ptn_mb_rx_val_lane_sel        ), // Partner RX valid lane enable.
        .mb_rx_data_lane_sel            (ptn_mb_rx_data_lane_sel       ), // Partner RX data lane enable.
        .mb_tx_pattern_en               (ptn_mb_tx_pattern_en          ), // Partner TX active pattern enable.
        .mb_tx_pattern_setup            (ptn_mb_tx_pattern_setup       ), // Partner TX pattern sub-components.
        .mb_rx_pattern_setup            (ptn_mb_rx_pattern_setup       ), // Partner RX expected pattern components.
        .mb_tx_lfsr_en                  (ptn_mb_tx_lfsr_en             ), // Partner TX LFSR scrambler enable.
        .mb_tx_lfsr_rst                 (ptn_mb_tx_lfsr_rst            ), // Partner TX LFSR synchronous reset.
        .mb_rx_lfsr_en                  (ptn_mb_rx_lfsr_en             ), // Partner RX LFSR descrambler enable.
        .mb_rx_lfsr_rst                 (ptn_mb_rx_lfsr_rst            ), // Partner RX LFSR synchronous reset.
        .mb_rx_iter_count               (ptn_mb_rx_iter_count          ), // Partner RX expected iteration count.
        .mb_rx_idle_count               (ptn_mb_rx_idle_count          ), // Partner RX expected idle duration.
        .mb_rx_burst_count              (ptn_mb_rx_burst_count         ), // Partner RX expected burst duration.
        .mb_rx_pattern_mode             (ptn_mb_rx_pattern_mode        ), // Partner RX evaluation mode.
        .mb_rx_val_pattern_sel          (ptn_mb_rx_val_pattern_sel     ), // Partner RX expected valid pattern.
        .mb_rx_data_pattern_sel         (ptn_mb_rx_data_pattern_sel    ), // Partner RX expected data pattern.
        .mb_rx_compare_en               (ptn_mb_rx_compare_en          ), // Partner RX comparison circuit enable.
        .mb_rx_compare_setup            (ptn_mb_rx_compare_setup       ), // Partner RX comparison mode.
        .mb_rx_max_err_thresh_perlane   (ptn_mb_rx_max_err_thresh_perlane), // Partner RX per-lane error threshold.
        .mb_rx_max_err_thresh_aggr      (ptn_mb_rx_max_err_thresh_aggr ), // Partner RX aggregate error threshold.
        .mb_tx_clk_sampling_en          (ptn_mb_tx_clk_sampling_en     ), // Partner TX clock phase update enable.
        .mb_tx_clk_sampling             (ptn_mb_tx_clk_sampling        ), // Partner TX clock phase value.
        .mb_tx_pattern_mode             (ptn_mb_tx_pattern_mode        ), // Partner TX pattern generator mode.
        .mb_tx_burst_count              (ptn_mb_tx_burst_count         ), // Partner TX burst duration.
        .mb_tx_idle_count               (ptn_mb_tx_idle_count          ), // Partner TX idle duration.
        .mb_tx_iter_count               (ptn_mb_tx_iter_count          ), // Partner TX iteration count.
        .mb_tx_data_pattern_sel         (ptn_mb_tx_data_pattern_sel    ), // Partner TX data pattern selection.
        .mb_tx_val_pattern_sel          (ptn_mb_tx_val_pattern_sel     ), // Partner TX valid pattern selection.
        // Broadcast inputs (shared with both sub-wrappers):
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done      ), // 1: TX pattern generator completed all iterations.
        .mb_rx_aggr_pass                (mb_rx_aggr_pass               ), // 1: Aggregate comparison passed.
        .mb_rx_perlane_pass             (mb_rx_perlane_pass            ), // Per-lane pass vector.
        .mb_rx_val_pass                 (mb_rx_val_pass                ), // 1: Valid lane comparison passed.

        // ── Group 4: SB Signals ───────────────────────────────────────────────
        .tx_sb_msg_valid                (ptn_tx_sb_msg_valid           ), // Partner SB transmit pulse (1 cycle).
        .tx_sb_msg                      (ptn_tx_sb_msg                 ), // Partner SB MsgCode to transmit.
        .tx_msginfo                     (ptn_tx_msginfo                ), // Partner SB msginfo payload.
        .tx_data_field                  (ptn_tx_data_field             ), // Partner SB 64-bit data payload.
        .rx_sb_msg_valid                (rx_sb_msg_valid               ), // Broadcast: received SB strobe pulse.
        .rx_sb_msg                      (rx_sb_msg                     ), // Broadcast: received MsgCode.
        .rx_msginfo                     (rx_msginfo                    ), // Broadcast: received msginfo payload.
        .rx_data_field                  (rx_data_field                 )  // Broadcast: received data payload.
    );

    // =========================================================================
    // Output Assignments: Test Completion & Results
    // =========================================================================
    // local_test_d2c_done: directly from local sub-wrapper.
    assign local_test_d2c_done   = loc_test_d2c_done;

    // partner_test_d2c_done: directly from partner sub-wrapper.
    assign partner_test_d2c_done = ptn_test_d2c_done;

    // Pass/fail results are always captured by the local module
    // (it is always the initiator that receives the results SB message).
    assign d2c_perlane_pass      = loc_d2c_perlane_pass;
    assign d2c_aggr_pass         = loc_d2c_aggr_pass;
    assign d2c_val_pass          = loc_d2c_val_pass;

    // =========================================================================
    // MUX 2: MB Signal Routing
    // =========================================================================
    // Determines which sub-wrapper drives the external MB TX lanes and which
    // sub-wrapper reads the external MB RX lanes, based on the active test case.
    //
    // Four mutually exclusive cases (UCIe spec guarantees no overlap): (to keep it more cleare: the local die is "Die 0" and the partner die is "Die 1" and each one has its own local FSMs and partner FSMs)
    // Note: It's impossible to be that "Die 0" applies TX_D2C_PT and "Die 1" applies RX_D2C_PT in the same time.
    //       So, It's   impossible to get (local_tx_pt_en=1   and (local_rx_pt_en=1 OR partner_rx_pt_en=1)).
    //       Also, It's impossible to get (partner_tx_pt_en=1 and (local_rx_pt_en=1 OR partner_rx_pt_en=1)).
    //
    //   1) Case A — Local TX test (local_tx_pt_en=1 & partner_tx_pt_en=0) & (local_rx_pt_en=0 & partner_rx_pt_en=0):
    //     The local die's TX (Die 0 TX) is the TRANSMITTER  → MB TX pins come from loc (TX side). and we drive a default values of MB RX signals (that we get from 'wrapper_D2C_PT_local').
    //     The partner die's RX (Die 1 RX) is the RECEIVER   → MB RX pins come from ptn (RX side).
    //
    //   2) Case B — Partner TX test (local_tx_pt_en=0 & partner_tx_pt_en=1) & (local_rx_pt_en=0 & partner_rx_pt_en=0):
    //     The partner die's TX (Die 1 TX) is the TRANSMITTER → MB TX pins come from ptn (TX side).
    //     The local die's RX (Die 0 RX) is the RECEIVER      → MB RX pins come from loc (RX side). and we drive a default values of MB TX signals (that we get from 'wrapper_D2C_PT_partner').
    //     (Note: local_tx_pt_en=0 in this case since it's the partner's TX (partner's TX_D2C_PT) init test)
    //
    //   3) Case AB — Local TX, and Partner TX test (local_tx_pt_en=1 & partner_tx_pt_en=1) & (local_rx_pt_en=0 & partner_rx_pt_en=0):
    //     The partner die's TX (Die 1 TX) is the TRANSMITTER → MB TX pins come from ptn (TX side).
    //     The partner die's RX (Die 1 RX) is the RECEIVER    → MB RX pins come from ptn (RX side).
    //     The local die's TX (Die 0 TX) is the TRANSMITTER   → MB TX pins come from loc (TX side). and we drive the values of MB RX signals (that we get from 'wrapper_D2C_PT_partner').
    //     The local die's RX (Die 0 RX) is the RECEIVER      → MB RX pins come from loc (RX side). and we drive the values of MB TX signals (that we get from 'wrapper_D2C_PT_local').
    //     (Note: local_tx_pt_en=1 & partner_tx_pt_en=1 means the partner's TX (partner's TX_D2C_PT) and local's TX (local's TX_D2C_PT) init the same test but from each Die's perspective (Die 0 and Die 1) to implement the complete seperation between MB transmitter and MB receiver, and keep each Substate use TX_D2C_PT ignoring if the partner is using TX_D2C_PT now or not).
    //
    //   4) Case C — Local RX test (local_tx_pt_en=0 & partner_tx_pt_en=0) & (local_rx_pt_en=1 & partner_rx_pt_en=0):
    //     The local die is the RECEIVER           → MB RX pins come from loc (RX side). and we drive a default values of MB TX signals (that we get from 'wrapper_D2C_PT_local').
    //     The partner die's TX is the TRANSMITTER → MB TX pins come from ptn (TX side).
    //
    //   5) Case D — Partner RX test (local_tx_pt_en=0 & partner_tx_pt_en=0) & (local_rx_pt_en=0 & partner_rx_pt_en=1):
    //     The partner die is the RECEIVER         → MB RX pins come from ptn (RX side).
    //     The local die's TX is the TRANSMITTER   → MB TX pins come from loc (TX side). and we drive a default values of MB RX signals (that we get from 'wrapper_D2C_PT_partner').
    //
    //   6) Case CD — Local RX, and Partner RX test (local_rx_pt_en=0 & partner_rx_pt_en=0) & (local_rx_pt_en=1 & partner_rx_pt_en=1):
    //     The partner die's TX (Die 1 TX) is the TRANSMITTER → MB TX pins come from ptn (TX side).
    //     The partner die's RX (Die 1 RX) is the RECEIVER    → MB RX pins come from ptn (RX side).
    //     The local die's TX (Die 0 TX) is the TRANSMITTER   → MB TX pins come from loc (TX side). and we drive the values of MB RX signals (that we get from 'wrapper_D2C_PT_local').
    //     The local die's RX (Die 0 RX) is the RECEIVER      → MB RX pins come from loc (RX side). and we drive the values of MB TX signals (that we get from 'wrapper_D2C_PT_partner').
    //     (Note: local_rx_pt_en=1 & partner_rx_pt_en=1 means the partner's RX (partner's RX_D2C_PT) and local's RX (local's RX_D2C_PT) init the same test but from each Die's perspective (Die 0 and Die 1) to implement the complete seperation between MB transmitter and MB receiver, and keep each Substate use RX_D2C_PT ignoring if the partner is using RX_D2C_PT now or not).
    //
    // ── Design Rationale for Parallel MB TX/RX Routing ───────────────────────
    // The MB TX bus and MB RX bus are INDEPENDENT hardware resources. Therefore
    // the routing logic for each bus is implemented as a SEPARATE always_comb
    // block driven by its own independent enable condition. This correctly handles
    // the "Case AB" and "Case CD" parallel scenarios where both local and partner
    // FSMs are active simultaneously:
    //
    //   MB TX source selection (who drives Die 0's physical TX bus):
    //     • local_tx_pt_en=1  → loc_mb_tx_* (unit_TX_D2C_PT_local transmits)    [Cases A, AB]
    //     • partner_rx_pt_en=1→ ptn_mb_tx_* (unit_RX_D2C_PT_partner transmits)  [Cases D, CD]
    //     • none active       → safe zero defaults
    //
    //   MB RX source selection (who drives Die 0's physical RX bus):
    //     • partner_tx_pt_en=1→ ptn_mb_rx_* (unit_TX_D2C_PT_partner receives)   [Cases B, AB]
    //     • local_rx_pt_en=1  → loc_mb_rx_* (unit_RX_D2C_PT_local receives)     [Cases C, CD]
    //     • none active       → safe zero defaults
    //
    // NOTE: The UCIe spec guarantees the following mutual exclusions:
    //   local_tx_pt_en=1  and partner_rx_pt_en=1  cannot both be 1 simultaneously.
    //   partner_tx_pt_en=1 and local_rx_pt_en=1   cannot both be 1 simultaneously.
    //   local_tx_pt_en=1  and local_rx_pt_en=1    cannot both be 1 simultaneously.
    //   partner_tx_pt_en=1 and partner_rx_pt_en=1 cannot both be 1 simultaneously.
    // So the two parallel MUXes below will never have conflicting assignments.

    // ──────────────────────────────────────────────────────────────────────────
    // MB TX BUS ROUTING — Independent combinational block
    // Selects which sub-wrapper drives Die 0's physical MB TX outputs.
    // ──────────────────────────────────────────────────────────────────────────
    always_comb begin : MB_TX_ROUTING_MUX
        if (local_tx_pt_en) begin
            // ── Cases A & AB: Die 0 (local) is the TX transmitter ────────────
            // unit_TX_D2C_PT_local is active inside wrapper_D2C_PT_local.
            // Its outputs come out via loc_mb_tx_* wires.
            mb_tx_pattern_en        = loc_mb_tx_pattern_en;
            mb_tx_pattern_setup     = loc_mb_tx_pattern_setup;
            mb_tx_lfsr_en           = loc_mb_tx_lfsr_en;
            mb_tx_lfsr_rst          = loc_mb_tx_lfsr_rst;
            mb_tx_clk_sampling_en   = loc_mb_tx_clk_sampling_en;
            mb_tx_clk_sampling      = loc_mb_tx_clk_sampling;
            mb_tx_pattern_mode      = loc_mb_tx_pattern_mode;
            mb_tx_burst_count       = loc_mb_tx_burst_count;
            mb_tx_idle_count        = loc_mb_tx_idle_count;
            mb_tx_iter_count        = loc_mb_tx_iter_count;
            mb_tx_data_pattern_sel  = loc_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel   = loc_mb_tx_val_pattern_sel;

        end else if (partner_rx_pt_en) begin
            // ── Cases D & CD: Die 0 transmits for Die 1's RX test ───────────
            // unit_RX_D2C_PT_partner is active inside wrapper_D2C_PT_partner.
            // When partner_rx_pt_en=1, the partner wrapper routes its
            // unit_RX_D2C_PT_partner outputs through ptn_mb_tx_* wires.
            mb_tx_pattern_en        = ptn_mb_tx_pattern_en;
            mb_tx_pattern_setup     = ptn_mb_tx_pattern_setup;
            mb_tx_lfsr_en           = ptn_mb_tx_lfsr_en;
            mb_tx_lfsr_rst          = ptn_mb_tx_lfsr_rst;
            mb_tx_clk_sampling_en   = ptn_mb_tx_clk_sampling_en;
            mb_tx_clk_sampling      = ptn_mb_tx_clk_sampling;
            mb_tx_pattern_mode      = ptn_mb_tx_pattern_mode;
            mb_tx_burst_count       = ptn_mb_tx_burst_count;
            mb_tx_idle_count        = ptn_mb_tx_idle_count;
            mb_tx_iter_count        = ptn_mb_tx_iter_count;
            mb_tx_data_pattern_sel  = ptn_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel   = ptn_mb_tx_val_pattern_sel;

        end else begin
            // ── Cases B & C & idle: Die 0's TX bus is unused ─────────────────
            // No local TX test and no partner RX test → drive safe zero defaults
            // to keep the physical TX hardware quiescent.
            mb_tx_pattern_en        = 1'b0;
            mb_tx_pattern_setup     = 3'b000;
            mb_tx_lfsr_en           = 1'b0;
            mb_tx_lfsr_rst          = 1'b0;
            mb_tx_clk_sampling_en   = 1'b0;
            mb_tx_clk_sampling      = 2'b00;
            mb_tx_pattern_mode      = 1'b0;
            mb_tx_burst_count       = 16'd0;
            mb_tx_idle_count        = 16'd0;
            mb_tx_iter_count        = 16'd0;
            mb_tx_data_pattern_sel  = 2'b00;
            mb_tx_val_pattern_sel   = 1'b0;
        end
    end

    // ──────────────────────────────────────────────────────────────────────────
    // MB RX BUS ROUTING — Independent combinational block
    // Selects which sub-wrapper drives Die 0's physical MB RX outputs.
    // ──────────────────────────────────────────────────────────────────────────
    always_comb begin : MB_RX_ROUTING_MUX
        if (partner_tx_pt_en) begin
            // ── Cases B & AB: Die 0 (local) receives for Die 1's TX test ─────
            // unit_TX_D2C_PT_partner is active inside wrapper_D2C_PT_partner.
            // When partner_tx_pt_en=1, the partner wrapper routes its
            // unit_TX_D2C_PT_partner outputs through ptn_mb_rx_* wires
            // (because Die 1 transmits → Die 0 acts as the receiver).
            mb_rx_trk_lane_sel              = ptn_mb_rx_trk_lane_sel;
            mb_rx_clk_lane_sel              = ptn_mb_rx_clk_lane_sel;
            mb_rx_val_lane_sel              = ptn_mb_rx_val_lane_sel;
            mb_rx_data_lane_sel             = ptn_mb_rx_data_lane_sel;
            mb_rx_pattern_setup             = ptn_mb_rx_pattern_setup;
            mb_rx_lfsr_en                   = ptn_mb_rx_lfsr_en;
            mb_rx_lfsr_rst                  = ptn_mb_rx_lfsr_rst;
            mb_rx_iter_count                = ptn_mb_rx_iter_count;
            mb_rx_idle_count                = ptn_mb_rx_idle_count;
            mb_rx_burst_count               = ptn_mb_rx_burst_count;
            mb_rx_pattern_mode              = ptn_mb_rx_pattern_mode;
            mb_rx_val_pattern_sel           = ptn_mb_rx_val_pattern_sel;
            mb_rx_data_pattern_sel          = ptn_mb_rx_data_pattern_sel;
            mb_rx_compare_en                = ptn_mb_rx_compare_en;
            mb_rx_compare_setup             = ptn_mb_rx_compare_setup;
            mb_rx_max_err_thresh_perlane    = ptn_mb_rx_max_err_thresh_perlane;
            mb_rx_max_err_thresh_aggr       = ptn_mb_rx_max_err_thresh_aggr;

        end else if (local_rx_pt_en) begin
            // ── Cases C & CD: Die 0 (local) receives in its own RX test ──────
            // unit_RX_D2C_PT_local is active inside wrapper_D2C_PT_local.
            // When local_rx_pt_en=1, the local wrapper routes its
            // unit_RX_D2C_PT_local outputs through loc_mb_rx_* wires.
            mb_rx_trk_lane_sel              = loc_mb_rx_trk_lane_sel;
            mb_rx_clk_lane_sel              = loc_mb_rx_clk_lane_sel;
            mb_rx_val_lane_sel              = loc_mb_rx_val_lane_sel;
            mb_rx_data_lane_sel             = loc_mb_rx_data_lane_sel;
            mb_rx_pattern_setup             = loc_mb_rx_pattern_setup;
            mb_rx_lfsr_en                   = loc_mb_rx_lfsr_en;
            mb_rx_lfsr_rst                  = loc_mb_rx_lfsr_rst;
            mb_rx_iter_count                = loc_mb_rx_iter_count;
            mb_rx_idle_count                = loc_mb_rx_idle_count;
            mb_rx_burst_count               = loc_mb_rx_burst_count;
            mb_rx_pattern_mode              = loc_mb_rx_pattern_mode;
            mb_rx_val_pattern_sel           = loc_mb_rx_val_pattern_sel;
            mb_rx_data_pattern_sel          = loc_mb_rx_data_pattern_sel;
            mb_rx_compare_en                = loc_mb_rx_compare_en;
            mb_rx_compare_setup             = loc_mb_rx_compare_setup;
            mb_rx_max_err_thresh_perlane    = loc_mb_rx_max_err_thresh_perlane;
            mb_rx_max_err_thresh_aggr       = loc_mb_rx_max_err_thresh_aggr;

        end else begin
            // ── Cases A & D & idle: Die 0's RX bus is unused ─────────────────
            // No partner TX test and no local RX test → drive safe zero defaults
            // to keep the physical RX hardware quiescent.
            mb_rx_trk_lane_sel              = 1'b0;
            mb_rx_clk_lane_sel              = 1'b0;
            mb_rx_val_lane_sel              = 1'b0;
            mb_rx_data_lane_sel             = 1'b0;
            mb_rx_pattern_setup             = 3'b000;
            mb_rx_lfsr_en                   = 1'b0;
            mb_rx_lfsr_rst                  = 1'b0;
            mb_rx_iter_count                = 16'd0;
            mb_rx_idle_count                = 16'd0;
            mb_rx_burst_count               = 16'd0;
            mb_rx_pattern_mode              = 1'b0;
            mb_rx_val_pattern_sel           = 1'b0;
            mb_rx_data_pattern_sel          = 2'b00;
            mb_rx_compare_en                = 1'b0;
            mb_rx_compare_setup             = 2'b00;
            mb_rx_max_err_thresh_perlane    = 12'd0;
            mb_rx_max_err_thresh_aggr       = 16'd0;
        end
    end

    // =========================================================================
    // MUX 3: SB Output Arbitration
    // =========================================================================
    // The single external SB TX port is driven from either the local or partner
    // sub-wrapper. The UCIe spec guarantees that at any given moment only one
    // sub-wrapper will assert tx_sb_msg_valid=1. Priority is given to the local
    // sub-wrapper (which acts as the initiator in most cases).
    // The arbitration is purely combinational (latch-free).
    always_comb begin : SB_ARBITRATION_MUX
        if (loc_tx_sb_msg_valid) begin
            // Local sub-wrapper has a message to send.
            tx_sb_msg_valid = loc_tx_sb_msg_valid;
            tx_sb_msg       = loc_tx_sb_msg;
            tx_msginfo      = loc_tx_msginfo;
            tx_data_field   = loc_tx_data_field;
        end else if (ptn_tx_sb_msg_valid) begin
            // Partner sub-wrapper has a message to send.
            tx_sb_msg_valid = ptn_tx_sb_msg_valid;
            tx_sb_msg       = ptn_tx_sb_msg;
            tx_msginfo      = ptn_tx_msginfo;
            tx_data_field   = ptn_tx_data_field;
        end else begin
            // No active SB message — drive safe idle values.
            tx_sb_msg_valid = 1'b0;
            tx_sb_msg       = 8'h00;
            tx_msginfo      = 16'h0000;
            tx_data_field   = 64'h0000_0000_0000_0000;
        end
    end

endmodule


