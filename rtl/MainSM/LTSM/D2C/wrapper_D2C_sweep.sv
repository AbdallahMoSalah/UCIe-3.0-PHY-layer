// ====================================================================================================
// wrapper_D2C_sweep.sv — D2C Sweep Top-Level Wrapper
//
// This module is the single instantiation point for both:
//   • unit_D2C_sweep   — sweep FSM that iterates PHY codes and tracks best eye per lane.
//   • wrapper_D2C_PT   — D2C Point Test engine (TX_D2C_PT + RX_D2C_PT FSMs, MB/SB routing).
//
// ─── CONNECTION STRATEGY ──────────────────────────────────────────────────────────────────────────
// The following 14 signals are INTERNAL wires only.  They flow exclusively between
// unit_D2C_sweep (producer) and wrapper_D2C_PT (consumer / feedback provider) and are
// NOT exported to any parent module:
//
//   Feedback (wrapper_D2C_PT → unit_D2C_sweep):
//     local_test_d2c_done   — 1: one D2C point-test cycle complete; perlane_pass is valid.
//     partner_test_d2c_done — 1: partner's D2C point-test cycle complete.
//     d2c_perlane_pass      — per-lane pass/fail vector, valid when local_test_d2c_done=1.
//     d2c_val_pass          — 1: no Valid Lane error; 0: Valid Lane pattern mismatch.
//
//   Control (unit_D2C_sweep → wrapper_D2C_PT):
//     local_tx_pt_en        — assert to start local  TX_D2C_PT handshake (1: enable, 0: idle).
//     local_rx_pt_en        — assert to start local  RX_D2C_PT handshake (1: enable, 0: idle).
//     partner_tx_pt_en      — assert to start partner TX_D2C_PT handshake (1: enable, 0: idle).
//     partner_rx_pt_en      — assert to start partner RX_D2C_PT handshake (1: enable, 0: idle).
//     d2c_clk_sampling      — clock sampling phase (00: Eye Center, 01: Left, 10: Right).
//     d2c_pattern_setup     — pattern component enables (bit0: Data, bit1: Valid, bit2: Clock).
//     d2c_data_pattern_sel  — data pattern type (00: LFSR, 01: Per-Lane ID, 10: All-Zeros).
//     d2c_val_pattern_sel   — valid lane pattern (0: VALTRAIN, 1: Held Low).
//     d2c_pattern_mode      — generator mode (0: Continuous, 1: Burst).
//     d2c_burst_count       — burst duration in UI (unsigned 16-bit).
//     d2c_idle_count        — idle duration in UI (unsigned 16-bit).
//     d2c_iter_count        — burst-idle iteration count (unsigned 16-bit).
//     d2c_compare_setup     — comparison mode (00: Per-Lane, 01: Aggregate, 10: Valid, 11: Clk).
//
// ─── EXPORTED INTERFACE (External) ───────────────────────────────────────────────────────────────
// From/to MBTRAIN substates:
//   active_lanes      — active lane mask (to unit_D2C_sweep).
//   local_sweep_en    — start/sustain sweep (from substate LOCAL FSM).
//   partner_sweep_en  — partner is holding MB for a sweep (from substate PARTNER FSM).
//   sweep_done        — 1: full code sweep complete (to substate LOCAL FSM).
//   swept_code        — current PHY code being tested (to PHY).
//   best_code[0:15]   — per-lane best midpoint code after sweep (to substate for latching).
//   min_eye_width     — narrowest eye across active lanes after sweep (to substate).
//
// From/to LTSM (state routing):
//   state_n           — current LTSM sub-state (selects D2C config in unit_D2C_sweep).
//
// From/to MB (Mainband):
//   All mb_tx_* and mb_rx_* control signals (from wrapper_D2C_PT).
//
// From/to SB (Sideband):
//   tx_sb_msg_valid, tx_sb_msg, tx_msginfo, tx_data_field (outputs from wrapper_D2C_PT).
//   rx_sb_msg_valid, rx_sb_msg, rx_msginfo, rx_data_field (inputs to  wrapper_D2C_PT).
//
// From PHY/Register File:
//   mb_rx_data_lane_mask, cfg_max_err_thresh_perlane, cfg_max_err_thresh_aggr.
//   mb_tx_pattern_count_done, mb_rx_aggr_pass, mb_rx_perlane_pass, mb_rx_val_pass.
// ====================================================================================================

module wrapper_D2C_sweep #(
    //=========================================================================
    // Sweep Code Range (passed through to unit_D2C_sweep)
    //=========================================================================
    parameter int unsigned MAX_VAL_VREF_CODE  = 'D16, // Rx Valid Lane Vref: max code (inclusive).
    parameter int unsigned MAX_DATA_VREF_CODE = 'D16, // Rx Data Lane  Vref: max code (inclusive).
    parameter int unsigned MAX_DATA_PI_CODE   = 'D16, // TX Data Lane  PI  : max code (inclusive).
    parameter int unsigned MAX_VAL_PI_CODE    = 'D16, // TX Valid Lane PI  : max code (inclusive).
    parameter int unsigned MAX_DESKEW_CODE    = 'D16, // RX Data Lane Deskew: max code (inclusive).

    parameter int unsigned MIN_VAL_VREF_CODE  = 'D1,  // Rx Valid Lane Vref: min code (inclusive).
    parameter int unsigned MIN_DATA_VREF_CODE = 'D1,  // Rx Data Lane  Vref: min code (inclusive).
    parameter int unsigned MIN_DATA_PI_CODE   = 'D0,  // TX Data Lane  PI  : min code (inclusive).
    parameter int unsigned MIN_VAL_PI_CODE    = 'D0,  // TX Valid Lane PI  : min code (inclusive).
    parameter int unsigned MIN_DESKEW_CODE    = 'D0,  // RX Data Lane Deskew: min code (inclusive).

    // MAX_CODE: derived automatically — do not override.
    parameter int unsigned MAX_CODE =
        (MAX_VAL_VREF_CODE  >= MAX_DATA_VREF_CODE && MAX_VAL_VREF_CODE  >= MAX_DATA_PI_CODE && MAX_VAL_VREF_CODE  >= MAX_VAL_PI_CODE  && MAX_VAL_VREF_CODE  >= MAX_DESKEW_CODE)  ? MAX_VAL_VREF_CODE  :
        (MAX_DATA_VREF_CODE >= MAX_DATA_PI_CODE   && MAX_DATA_VREF_CODE >= MAX_VAL_PI_CODE  &&  MAX_DATA_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_VREF_CODE :
        (MAX_DATA_PI_CODE   >= MAX_VAL_PI_CODE    && MAX_DATA_PI_CODE   >= MAX_DESKEW_CODE)  ? MAX_DATA_PI_CODE   :
        (MAX_VAL_PI_CODE    >= MAX_DESKEW_CODE) ? MAX_VAL_PI_CODE : MAX_DESKEW_CODE
) (
    // =========================================================================
    // Group 1: Clock and Reset
    // =========================================================================
    input  logic        lclk,                          // LTSM clock domain (1 GHz or 2 GHz). All transitions synchronous to lclk.
    input  logic        rst_n,                         // Active-low async reset (0: reset, 1: normal operation).

    // =========================================================================
    // Group 2: MBTRAIN Substate Control Interface
    // =========================================================================
    // Active lane mask — from unit_negotiated_lanes (or LTSM configuration).
    // Tells the sweep FSM and the D2C engine which lanes to include in results.
    input  logic [15:0] active_lanes,                  // Bit[i]=1: lane i is active and must pass the D2C test.

    // Sweep enable — asserted by the MBTRAIN substate LOCAL FSM.
    //   0: sweep FSM stays in IDLE (or returns to IDLE after sweep_done).
    //   1: sweep FSM runs the full code sweep (TRIGGER → LOG → ADVANCE → DONE).
    input  logic        local_sweep_en,

    // Partner sweep enable — asserted by the MBTRAIN substate PARTNER FSM.
    //   0: partner is not holding the MB for a sweep.
    //   1: partner is holding the MB bus ready for the sweep point test.
    //      Drives partner_pt_en inside unit_D2C_sweep so it acknowledges each point test.
    input  logic        partner_sweep_en,

    // Sweep done — combinational output, deasserts when local_sweep_en is deasserted.
    //   0: sweep is in progress (or FSM is idle / not yet started).
    //   1: full code sweep complete; best_code[] and min_eye_width are valid.
    output logic        sweep_done,
    
    //pass 
    output logic [15:0] d2c_perlane_pass,
    output logic  d2c_val_pass,
    // =========================================================================
    // Group 3: PHY Code Output (to PHY control registers)
    // =========================================================================
    // Current code under test — registered; changes once per D2C point-test cycle.
    // The parent must apply this code to the PHY before each point-test trigger.
    output logic [$clog2(MAX_CODE+1)-1:0] swept_code,  // Current code under test → drive to PHY.

    // =========================================================================
    // Group 4: Sweep Results (from unit_D2C_sweep, to MBTRAIN substate)
    // =========================================================================
    // These outputs are purely combinational — always reflect the latest zone-tracker
    // state. They are valid and stable while sweep_done=1, and hold the last-sweep
    // values when the FSM is IDLE (ready for next sweep invocation).
    //
    // Valid Lane test  → use best_code[0] only (lane 0 = Valid Lane).
    // Data Lane  test  → use best_code[i] for each active lane i.
    output wire [$clog2(MAX_CODE+1)-1:0] best_code [0:15], // Per-lane best midpoint code after sweep.
    output wire [$clog2(MAX_CODE+1)-1:0] min_eye_width,    // Narrowest best-window across active lanes.

    // =========================================================================
    // Group 5: LTSM State (routes to unit_D2C_sweep to select D2C configuration)
    // =========================================================================
    input  ltsm_state_n_pkg::state_n_e   state_n,          // Current LTSM main-state / sub-state enum.

    // =========================================================================
    // Group 6: PHY / Register File Configuration (to wrapper_D2C_PT)
    // =========================================================================
    // Lane mask for the RX data bus.
    //   000: No lanes, 001: Lanes 0-7, 010: Lanes 8-15,
    //   011: Lanes 0-15, 100: Lanes 0-3, 101: Lanes 4-7.
    input  logic [2:0]  mb_rx_data_lane_mask,

    // Per-lane error threshold — unsigned 12-bit.
    // A lane passes when its accumulated error count does not exceed this value.
    input  logic [11:0] cfg_max_err_thresh_perlane,

    // Aggregate error threshold — unsigned 16-bit.
    // Aggregate pass when total error count (across all lanes) ≤ this value.
    input  logic [15:0] cfg_max_err_thresh_aggr,

    // =========================================================================
    // Group 7: MB Signals — TX (outputs from wrapper_D2C_PT to MB hardware)
    // =========================================================================
    // TX lane select encoding: 00=Driven Low, 01=Active pattern, 1x=Tri-stated.
    output logic [1:0]  mb_tx_trk_lane_sel,               // 00: Low; 01: Active tracking; 1x: Tri-state.
    output logic [1:0]  mb_tx_clk_lane_sel,               // 00: Low; 01: Active clock;    1x: Tri-state.
    output logic [1:0]  mb_tx_val_lane_sel,               // 00: Low; 01: Active valid;    1x: Tri-state.
    output logic [1:0]  mb_tx_data_lane_sel,              // 00: Low; 01: Active data;     1x: Tri-state.

    // 0: TX in static idle; 1: Drive active training pattern on configured TX lanes.
    output logic        mb_tx_pattern_en,

    // TX pattern component enable bits: Bit0=Data, Bit1=Valid, Bit2=Clock.
    output logic [2:0]  mb_tx_pattern_setup,

    // 0: Disable TX LFSR scrambler; 1: Enable TX LFSR scrambler.
    output logic        mb_tx_lfsr_en,

    // 0: Normal operation; 1: Synchronously reset TX LFSR to default seed.
    output logic        mb_tx_lfsr_rst,

    // 0: TX Clock phase unchanged; 1: Update TX Clock phase to mb_tx_clk_sampling value.
    output logic        mb_tx_clk_sampling_en,

    // TX Clock sampling phase: 00=Eye Center (In-phase), 01=Left Edge, 10=Right Edge.
    output logic [1:0]  mb_tx_clk_sampling,

    // TX pattern generator mode: 0=Continuous (indefinite), 1=Burst (burst/idle counts apply).
    output logic        mb_tx_pattern_mode,

    // TX burst duration — unsigned 16-bit UI count (applies when mb_tx_pattern_mode=1).
    output logic [15:0] mb_tx_burst_count,

    // TX idle duration — unsigned 16-bit UI count (low period after burst, when mode=1).
    output logic [15:0] mb_tx_idle_count,

    // TX iteration count — unsigned 16-bit (number of burst+idle cycles, when mode=1).
    output logic [15:0] mb_tx_iter_count,

    // TX data pattern selection: 00=LFSR, 01=Per-Lane ID, 10=Fixed All-Zeros.
    output logic [1:0]  mb_tx_data_pattern_sel,

    // TX valid lane pattern: 0=VALTRAIN/functional pattern, 1=Held Low.
    output logic        mb_tx_val_pattern_sel,

    // 0: TX pattern generator is transmitting; 1: Completed all iterations (all bursts done).
    input  logic        mb_tx_pattern_count_done,

    // =========================================================================
    // Group 8: MB Signals — RX (outputs from wrapper_D2C_PT to MB hardware)
    // =========================================================================
    // RX lane enable: 0=Disabled, 1=Enabled.
    output logic        mb_rx_trk_lane_sel,               // 0: Disabled; 1: RX tracking lane active.
    output logic        mb_rx_clk_lane_sel,               // 0: Disabled; 1: RX clock lane active.
    output logic        mb_rx_val_lane_sel,               // 0: Disabled; 1: RX valid lane active.
    output logic        mb_rx_data_lane_sel,              // 0: Disabled; 1: RX data lanes active.

    // RX expected pattern component bits: Bit0=Data, Bit1=Valid, Bit2=Clock.
    output logic [2:0]  mb_rx_pattern_setup,

    // 0: Disable RX LFSR descrambler; 1: Enable RX LFSR descrambler.
    output logic        mb_rx_lfsr_en,

    // 0: Normal operation; 1: Synchronously reset RX LFSR to default seed.
    output logic        mb_rx_lfsr_rst,

    // RX expected iteration count — unsigned 16-bit.
    output logic [15:0] mb_rx_iter_count,

    // RX expected idle duration — unsigned 16-bit UI count.
    output logic [15:0] mb_rx_idle_count,

    // RX expected burst duration — unsigned 16-bit UI count.
    output logic [15:0] mb_rx_burst_count,

    // RX evaluation mode: 0=Continuous, 1=Burst.
    output logic        mb_rx_pattern_mode,

    // RX valid lane pattern: 0=VALTRAIN pattern, 1=Held Low / Operational Valid.
    output logic        mb_rx_val_pattern_sel,

    // RX data pattern: 00=LFSR, 01=Per-Lane ID (or All-Zeros).
    output logic [1:0]  mb_rx_data_pattern_sel,

    // 0: Disable RX comparison; 1: Enable RX comparison, start error accumulation.
    output logic        mb_rx_compare_en,

    // RX comparison mode: 00=Per-Lane, 01=Aggregate, 10=Valid Lane, 11=Clock Lane.
    output logic [1:0]  mb_rx_compare_setup,

    // Per-lane max error threshold driven to RX comparison block (unsigned 12-bit).
    output logic [11:0] mb_rx_max_err_thresh_perlane,

    // Aggregate max error threshold driven to RX comparison block (unsigned 16-bit).
    output logic [15:0] mb_rx_max_err_thresh_aggr,

    // 1: Aggregate comparison passed (total error ≤ cfg_max_err_thresh_aggr); 0: Failed.
    input  logic        mb_rx_aggr_pass,

    // Per-lane pass vector: bit[i]=1 if lane i's error count ≤ cfg_max_err_thresh_perlane.
    input  logic [15:0] mb_rx_perlane_pass,

    // 1: Valid Lane pattern matched; 0: Valid Lane pattern mismatch detected.
    input  logic        mb_rx_val_pass,

    // =========================================================================
    // Group 9: SB Signals — TX (from wrapper_D2C_PT to SB TX bus)
    // =========================================================================
    // Asserted for exactly 1 lclk cycle to transmit a sideband message to the partner.
    output logic        tx_sb_msg_valid,

    // MsgCode to transmit (valid when tx_sb_msg_valid=1).
    output logic [7:0]  tx_sb_msg,

    // MsgInfo payload field (varies by message type; valid when tx_sb_msg_valid=1).
    output logic [15:0] tx_msginfo,

    // 64-bit data payload (varies by message type; valid when tx_sb_msg_valid=1).
    output logic [63:0] tx_data_field,

    // =========================================================================
    // Group 10: SB Signals — RX (from SB RX bus to wrapper_D2C_PT, broadcast)
    // =========================================================================
    // Pulse: 1 lclk cycle when a valid sideband message has been received from partner.
    input  logic        rx_sb_msg_valid,

    // Received MsgCode from partner (valid when rx_sb_msg_valid=1).
    input  logic [7:0]  rx_sb_msg,

    // Received MsgInfo payload field (valid when rx_sb_msg_valid=1).
    input  logic [15:0] rx_msginfo,

    // Received 64-bit data payload (valid when rx_sb_msg_valid=1).
    input  logic [63:0] rx_data_field
);

    // =========================================================================
    // Internal Wires: unit_D2C_sweep ↔ wrapper_D2C_PT
    // These 14 signals are purely internal — not exposed to any parent.
    // =========================================================================

    // Feedback: wrapper_D2C_PT → unit_D2C_sweep
    logic        w_local_test_d2c_done  ; // 1: one D2C point-test cycle complete; perlane_pass valid.
    logic        w_partner_test_d2c_done; // 1: partner's D2C point-test cycle complete.
    logic [15:0] w_d2c_perlane_pass     ; // Per-lane pass/fail, valid when w_local_test_d2c_done=1.
    logic        w_d2c_val_pass         ; // 1: No Valid Lane error; 0: Valid Lane mismatch.

    // Control: unit_D2C_sweep → wrapper_D2C_PT
    logic        w_local_tx_pt_en       ; // (TX_D2C_PT) Enable local  TX test   (1: enable, 0: idle).
    logic        w_local_rx_pt_en       ; // (RX_D2C_PT) Enable local  RX test   (1: enable, 0: idle).
    logic        w_partner_tx_pt_en     ; // (TX_D2C_PT) Enable partner TX test  (1: enable, 0: idle).
    logic        w_partner_rx_pt_en     ; // (RX_D2C_PT) Enable partner RX test  (1: enable, 0: idle).
    logic [1:0]  w_d2c_clk_sampling    ; // 00: Eye Center, 01: Left Edge, 10: Right Edge, 11: Rsvd.
    logic [2:0]  w_d2c_pattern_setup   ; // Bit0: Data Enable, Bit1: Valid Enable, Bit2: Clock Enable.
    logic [1:0]  w_d2c_data_pattern_sel; // 00: LFSR, 01: Per-Lane ID, 10: All-Zeros, 11: Rsvd.
    logic        w_d2c_val_pattern_sel ; // 0: VALTRAIN/functional pattern, 1: Held Low.
    logic        w_d2c_pattern_mode    ; // 0: Continuous mode (indefinite), 1: Burst mode.
    logic [15:0] w_d2c_burst_count     ; // Unsigned 16-bit burst duration in UI.
    logic [15:0] w_d2c_idle_count      ; // Unsigned 16-bit idle duration in UI.
    logic [15:0] w_d2c_iter_count      ; // Unsigned 16-bit iteration count of burst-idle cycles.
    logic [1:0]  w_d2c_compare_setup   ; // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clk.

    assign d2c_perlane_pass = w_d2c_perlane_pass;
    assign d2c_val_pass = w_d2c_val_pass;

    // =========================================================================
    // Instantiation 1: unit_D2C_sweep
    // =========================================================================
    unit_D2C_sweep #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE   (MAX_DATA_PI_CODE  ),
        .MAX_VAL_PI_CODE    (MAX_VAL_PI_CODE   ),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   ),
        .MIN_VAL_VREF_CODE  (MIN_VAL_VREF_CODE ),
        .MIN_DATA_VREF_CODE (MIN_DATA_VREF_CODE),
        .MIN_DATA_PI_CODE   (MIN_DATA_PI_CODE  ),
        .MIN_VAL_PI_CODE    (MIN_VAL_PI_CODE   ),
        .MIN_DESKEW_CODE    (MIN_DESKEW_CODE   )
    ) u_D2C_sweep (
        // ── Group 1: Clock and Reset ────────────────────────────────────────
        .lclk                  (lclk                    ), // LTSM clock domain.
        .rst_n                 (rst_n                   ), // Active-low async reset.

        // ── Group 2: Active Lane Mask ───────────────────────────────────────
        .active_lanes          (active_lanes             ), // Bit[i]=1: lane i participates in sweep.

        // ── Group 3: Parent FSM Control ─────────────────────────────────────
        .local_sweep_en        (local_sweep_en           ), // 1: Start/sustain sweep; 0: idle.
        .partner_sweep_en      (partner_sweep_en         ), // 1: Partner is holding MB for sweep.
        .sweep_done            (sweep_done               ), // 1: Full sweep complete (combinational).
        .state_n               (state_n                  ), // Current LTSM sub-state.

        // ── Group 4: D2C Point Test Feedback (internal — from wrapper_D2C_PT) ──
        .local_test_d2c_done   (w_local_test_d2c_done   ), // 1: Point-test cycle complete.
        .partner_test_d2c_done (w_partner_test_d2c_done ), // 1: Partner point-test cycle complete.
        .d2c_perlane_pass      (w_d2c_perlane_pass      ), // Per-lane pass vector, valid on done.
        .d2c_val_pass          (w_d2c_val_pass          ), // 1: No valid lane error.

        // ── Group 5: D2C PT Control Outputs (internal — to wrapper_D2C_PT) ──
        .local_tx_pt_en        (w_local_tx_pt_en        ), // Enable local  TX_D2C_PT handshake.
        .local_rx_pt_en        (w_local_rx_pt_en        ), // Enable local  RX_D2C_PT handshake.
        .partner_tx_pt_en      (w_partner_tx_pt_en      ), // Enable partner TX_D2C_PT handshake.
        .partner_rx_pt_en      (w_partner_rx_pt_en      ), // Enable partner RX_D2C_PT handshake.
        .d2c_clk_sampling      (w_d2c_clk_sampling      ), // Clock sampling phase selection.
        .d2c_pattern_setup     (w_d2c_pattern_setup     ), // Pattern component enables.
        .d2c_data_pattern_sel  (w_d2c_data_pattern_sel  ), // Data pattern type.
        .d2c_val_pattern_sel   (w_d2c_val_pattern_sel   ), // Valid lane pattern type.
        .d2c_pattern_mode      (w_d2c_pattern_mode      ), // Generator mode (continuous/burst).
        .d2c_burst_count       (w_d2c_burst_count       ), // Burst duration in UI.
        .d2c_idle_count        (w_d2c_idle_count        ), // Idle duration in UI.
        .d2c_iter_count        (w_d2c_iter_count        ), // Iteration count.
        .d2c_compare_setup     (w_d2c_compare_setup     ), // Comparison mode selection.

        // ── Group 6: PHY Code and Sweep Results (external outputs) ───────────
        .swept_code            (swept_code              ), // Current code → drive to PHY.
        .best_code             (best_code               ), // Per-lane best midpoint after sweep.
        .min_eye_width         (min_eye_width           )  // Narrowest eye across active lanes.
    );

    // =========================================================================
    // Instantiation 2: wrapper_D2C_PT
    // =========================================================================
    wrapper_D2C_PT u_wrapper_D2C_PT (
        // ── Group 1: Clock and Reset ────────────────────────────────────────
        .lclk                          (lclk                         ), // LTSM clock domain.
        .rst_n                         (rst_n                        ), // Active-low async reset.

        // ── Group 2: LTSM Control Configuration ─────────────────────────────
        .mb_rx_data_lane_mask          (mb_rx_data_lane_mask         ), // Negotiated RX data lane mask.

        // Test completion outputs (internal — fed back to unit_D2C_sweep)
        .local_test_d2c_done           (w_local_test_d2c_done        ), // 1: Local point-test cycle done.
        .partner_test_d2c_done         (w_partner_test_d2c_done      ), // 1: Partner point-test cycle done.
        .d2c_perlane_pass              (w_d2c_perlane_pass           ), // Per-lane pass vector.
        .d2c_aggr_pass                 (/* unconnected — not used by sweep */), // Aggregate pass (unused).
        .d2c_val_pass                  (w_d2c_val_pass               ), // Valid lane pass.

        // PT enable inputs (internal — driven by unit_D2C_sweep)
        .local_tx_pt_en                (w_local_tx_pt_en             ), // Local  TX_D2C_PT enable.
        .partner_tx_pt_en              (w_partner_tx_pt_en           ), // Partner TX_D2C_PT enable.
        .local_rx_pt_en                (w_local_rx_pt_en             ), // Local  RX_D2C_PT enable.
        .partner_rx_pt_en              (w_partner_rx_pt_en           ), // Partner RX_D2C_PT enable.

        // D2C configuration inputs (internal — driven by unit_D2C_sweep)
        .d2c_clk_sampling              (w_d2c_clk_sampling           ), // Clock sampling phase.
        .d2c_pattern_setup             (w_d2c_pattern_setup          ), // Pattern component enables.
        .d2c_data_pattern_sel          (w_d2c_data_pattern_sel       ), // Data pattern type.
        .d2c_val_pattern_sel           (w_d2c_val_pattern_sel        ), // Valid lane pattern type.
        .d2c_pattern_mode              (w_d2c_pattern_mode           ), // Generator mode.
        .d2c_burst_count               (w_d2c_burst_count            ), // Burst duration.
        .d2c_idle_count                (w_d2c_idle_count             ), // Idle duration.
        .d2c_iter_count                (w_d2c_iter_count             ), // Iteration count.
        .d2c_compare_setup             (w_d2c_compare_setup          ), // Comparison mode.

        // Error threshold configuration (external — from register file)
        .cfg_max_err_thresh_perlane    (cfg_max_err_thresh_perlane   ), // Per-lane max error threshold.
        .cfg_max_err_thresh_aggr       (cfg_max_err_thresh_aggr      ), // Aggregate max error threshold.

        // ── Group 3: MB TX (external — to MB hardware) ─────────────────────
        .mb_tx_trk_lane_sel            (mb_tx_trk_lane_sel           ), // TX tracking lane mode.
        .mb_tx_clk_lane_sel            (mb_tx_clk_lane_sel           ), // TX clock lane mode.
        .mb_tx_val_lane_sel            (mb_tx_val_lane_sel           ), // TX valid lane mode.
        .mb_tx_data_lane_sel           (mb_tx_data_lane_sel          ), // TX data lane mode.
        .mb_tx_pattern_en              (mb_tx_pattern_en             ), // TX active pattern enable.
        .mb_tx_pattern_setup           (mb_tx_pattern_setup          ), // TX pattern components.
        .mb_tx_lfsr_en                 (mb_tx_lfsr_en                ), // TX LFSR scrambler enable.
        .mb_tx_lfsr_rst                (mb_tx_lfsr_rst               ), // TX LFSR synchronous reset.
        .mb_tx_clk_sampling_en         (mb_tx_clk_sampling_en        ), // TX clock phase update enable.
        .mb_tx_clk_sampling            (mb_tx_clk_sampling           ), // TX clock phase value.
        .mb_tx_pattern_mode            (mb_tx_pattern_mode           ), // TX generator mode.
        .mb_tx_burst_count             (mb_tx_burst_count            ), // TX burst duration.
        .mb_tx_idle_count              (mb_tx_idle_count             ), // TX idle duration.
        .mb_tx_iter_count              (mb_tx_iter_count             ), // TX iteration count.
        .mb_tx_data_pattern_sel        (mb_tx_data_pattern_sel       ), // TX data pattern selection.
        .mb_tx_val_pattern_sel         (mb_tx_val_pattern_sel        ), // TX valid pattern selection.
        .mb_tx_pattern_count_done      (mb_tx_pattern_count_done     ), // 1: TX pattern gen completed.

        // ── Group 4: MB RX (external — to MB hardware) ─────────────────────
        .mb_rx_trk_lane_sel            (mb_rx_trk_lane_sel           ), // RX tracking lane enable.
        .mb_rx_clk_lane_sel            (mb_rx_clk_lane_sel           ), // RX clock lane enable.
        .mb_rx_val_lane_sel            (mb_rx_val_lane_sel           ), // RX valid lane enable.
        .mb_rx_data_lane_sel           (mb_rx_data_lane_sel          ), // RX data lane enable.
        .mb_rx_pattern_setup           (mb_rx_pattern_setup          ), // RX expected pattern components.
        .mb_rx_lfsr_en                 (mb_rx_lfsr_en                ), // RX LFSR descrambler enable.
        .mb_rx_lfsr_rst                (mb_rx_lfsr_rst               ), // RX LFSR synchronous reset.
        .mb_rx_iter_count              (mb_rx_iter_count             ), // RX expected iteration count.
        .mb_rx_idle_count              (mb_rx_idle_count             ), // RX expected idle duration.
        .mb_rx_burst_count             (mb_rx_burst_count            ), // RX expected burst duration.
        .mb_rx_pattern_mode            (mb_rx_pattern_mode           ), // RX evaluation mode.
        .mb_rx_val_pattern_sel         (mb_rx_val_pattern_sel        ), // RX expected valid pattern.
        .mb_rx_data_pattern_sel        (mb_rx_data_pattern_sel       ), // RX expected data pattern.
        .mb_rx_compare_en              (mb_rx_compare_en             ), // RX comparison circuit enable.
        .mb_rx_compare_setup           (mb_rx_compare_setup          ), // RX comparison mode.
        .mb_rx_max_err_thresh_perlane  (mb_rx_max_err_thresh_perlane ), // RX per-lane error threshold.
        .mb_rx_max_err_thresh_aggr     (mb_rx_max_err_thresh_aggr    ), // RX aggregate error threshold.
        .mb_rx_aggr_pass               (mb_rx_aggr_pass              ), // 1: Aggregate comparison passed.
        .mb_rx_perlane_pass            (mb_rx_perlane_pass           ), // Per-lane pass vector.
        .mb_rx_val_pass                (mb_rx_val_pass               ), // 1: Valid lane comparison passed.

        // ── Group 5: SB TX (external — to SB TX bus) ───────────────────────
        .tx_sb_msg_valid               (tx_sb_msg_valid              ), // 1-cycle SB transmit strobe.
        .tx_sb_msg                     (tx_sb_msg                    ), // SB MsgCode to transmit.
        .tx_msginfo                    (tx_msginfo                   ), // SB MsgInfo payload.
        .tx_data_field                 (tx_data_field                ), // SB 64-bit data payload.

        // ── Group 6: SB RX (external — from SB RX bus, broadcast) ──────────
        .rx_sb_msg_valid               (rx_sb_msg_valid              ), // 1-cycle received SB strobe.
        .rx_sb_msg                     (rx_sb_msg                    ), // Received SB MsgCode.
        .rx_msginfo                    (rx_msginfo                   ), // Received SB MsgInfo payload.
        .rx_data_field                 (rx_data_field                )  // Received SB 64-bit data payload.
    );

endmodule
// ====================================================================================================
// END wrapper_D2C_sweep
// ====================================================================================================
