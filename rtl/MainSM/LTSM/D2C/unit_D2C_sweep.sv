// ============================================================================
// unit_D2C_sweep.sv
//
// Generalized Data-Lane Sweep Datapath for TX/RX-initiated D2C Point Tests.
//
// Used by: RXDESKEW, DATATRAINCENTER1, DATATRAINCENTER2, DATAVREF, DATATRAINVREF.
//
// This module is SELF-CONTAINED: it has its own internal FSM that drives the
// full sweep loop (TRIGGER_D2C → LOG_RESULT → ADVANCE_CODE → DONE).
// No analog settle wait is needed: the D2C_PT module's own MB pattern startup
// time is already long enough. The parent only needs to:
//   1. Assert  local_sweep_en  to start a sweep (enter TRIGGER_D2C from IDLE).
//   2. Deassert local_sweep_en after seeing sweep_done to let FSM return to IDLE.
//   3. Read swept_code  to apply to the PHY during the sweep.
//   4. Read best_code[] and min_eye_width any time (purely combinational).
//
// ============================================================================
// Algorithm: Online Zone-Tracking (synthesisable, low memory)
//   Memory cost: O(N_LANES) registers only (best_lo, best_hi per lane).
//   For each code from min_code to max_code:
//     On PASS (d2c_perlane_pass[i] & active_lanes[i]):
//       If entering a new passing zone: record zone_min_r; seed best_lo/best_hi.
//       If continuing in same zone: extend best_hi when zone beats previous best.
//     On FAIL: close the current zone (zone_valid = 0).
//   After full sweep (DONE state):
//     best_code[lane] = (best_lo[lane] + best_hi[lane]) >> 1   (combinational)
//     min_eye_width   = narrowest (best_hi - best_lo) across all active lanes. (combinational)
//
// ============================================================================
// D2C Trigger Interface:
//   local_pt_en   — output — asserted for 1+ cycles to start the D2C test.
//   local_test_d2c_done — input  — asserted by D2C PT module when test is complete.
//   d2c_perlane_pass — input — per-lane pass result, valid when local_test_d2c_done=1.
//
// ============================================================================
// Spec Reference:
//   UCIe 3.0 §4.5.3 MBTRAIN sub-states (DATAVREF, DTC1, DTC2, RXDESKEW)
// ============================================================================

module unit_D2C_sweep #(
        //=========================================================================
        // Sweep Code Range
        //=========================================================================
        parameter int unsigned MAX_VAL_VREF_CODE  = 'D16, // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        parameter int unsigned MAX_DATA_VREF_CODE = 'D16, // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        parameter int unsigned MAX_DATA_PI_CODE   = 'D16, // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        parameter int unsigned MAX_VAL_PI_CODE    = 'D16, // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        parameter int unsigned MAX_DESKEW_CODE    = 'D16,  // for Deskew control.                       For the MB Rx Data Lanes.

        parameter int unsigned MIN_VAL_VREF_CODE  = 'D1 , // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        parameter int unsigned MIN_DATA_VREF_CODE = 'D1 , // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        parameter int unsigned MIN_DATA_PI_CODE   = 'D0 , // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        parameter int unsigned MIN_VAL_PI_CODE    = 'D0 , // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        parameter int unsigned MIN_DESKEW_CODE    = 'D0 , // for Deskew control.                       For the MB Rx Data Lanes.

        parameter int unsigned MAX_CODE =
            (MAX_VAL_VREF_CODE >= MAX_DATA_VREF_CODE && MAX_VAL_VREF_CODE >= MAX_DATA_PI_CODE && MAX_VAL_VREF_CODE >= MAX_VAL_PI_CODE && MAX_VAL_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_VAL_VREF_CODE :
            (MAX_DATA_VREF_CODE >= MAX_DATA_PI_CODE && MAX_DATA_VREF_CODE >= MAX_VAL_PI_CODE && MAX_DATA_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_VREF_CODE :
            (MAX_DATA_PI_CODE >= MAX_VAL_PI_CODE && MAX_DATA_PI_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_PI_CODE :
            (MAX_VAL_PI_CODE >= MAX_DESKEW_CODE) ? MAX_VAL_PI_CODE : MAX_DESKEW_CODE // Maximum code value (inclusive). Sets counter width.
    ) (
        //============================//
        // Clock and Reset            //
        //============================//
        input  logic        lclk,                 // LTSM clock
        input  logic        rst_n,                // Async active-low reset

        //============================//
        // Active Lane Mask           //
        //============================//
        input  logic [15:0] active_lanes,         // 1 = lane is active (from unit_negotiated_lanes)

        //============================//
        // Parent FSM Control         //
        //============================//
        // local_sweep_en: asserted by parent when current_state == RXDESKEW_TX_D2C_SWEEP.
        //   - FSM leaves IDLE only when local_sweep_en=1.
        //   - FSM cannot return to IDLE while local_sweep_en=1.
        //   - Parent deasserts local_sweep_en after observing sweep_done=1.
        // NOTE: No analog settle timer is needed. The D2C_PT module's own MB
        //       pattern startup time provides sufficient analog settling time.
        input  logic        local_sweep_en        ,
        input  logic        partner_sweep_en      ,
        output logic        sweep_done            , // 1 = sweep complete; held until local_sweep_en deasserts (combinational)
        input  ltsm_state_n_pkg::state_n_e state_n, // The current Main State/Substate.

        //============================//
        // D2C Point Test Interface   //
        //============================//
        input  logic        local_test_d2c_done   , // 1 = test complete, perlane_pass is valid
        input  logic        partner_test_d2c_done , // 1 = partner test completed.
        input  logic [15:0] d2c_perlane_pass      , // Per-lane pass/fail, valid when local_test_d2c_done=1
        input  logic        d2c_val_pass          , // (for TX/RX_D2C_PT) 1: No Valid Lane error, 0: Valid Lane pattern mismatch detected.

        // These signals are coming from MBTRAIN State (from its substates: MBTRAIN.VALVREF, MBTRAIN.DATAVREF, MBTRAIN.VALTRAINVREF, MBTRAIN.DATATRAINVREF, MBTRAIN.VALTRAINCENTER, MBTRAIN.DATATRAINCENTER1, MBTRAIN.RXDESKEW, MBTRAIN.DATATRAINCENTER2, MBTRAIN.LINKSPEED).
        output logic        local_tx_pt_en        , // (for TX_D2C_PT) Enable local  TX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
        output logic        local_rx_pt_en        , // (for RX_D2C_PT) Enable local  RX D2C point test (1: enable/initiate test handshake, 0: disable/idle). RX_D2C_PT test is used only in MBTRAIN substates.
        output logic        partner_tx_pt_en      , // (for TX_D2C_PT) Enable partner TX D2C point test (1: enable/initiate test handshake, 0: disable/idle).
        output logic        partner_rx_pt_en      , // (for RX_D2C_PT) Enable partner RX D2C point test (1: enable/initiate test handshake, 0: disable/idle). RX_D2C_PT test is used only in MBTRAIN substates.

        output logic [1:0]  d2c_clk_sampling      , // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
        output logic [2:0]  d2c_pattern_setup     , // (for TX/RX_D2C_PT) Bit0: Data Pattern Enable, Bit1: Valid Pattern Enable, Bit2: Clock Pattern Enable.
        output logic [1:0]  d2c_data_pattern_sel  , // (for TX/RX_D2C_PT) 00: LFSR pattern, 01: Per-Lane ID, 10: Fixed All Zeros, 11: Reserved.
        output logic        d2c_val_pattern_sel   , // (for TX/RX_D2C_PT) 0: VALTRAIN/functional pattern, 1: Held Low / Operational Valid.
        output logic        d2c_pattern_mode      , // (for TX/RX_D2C_PT) 0: Continuous mode (indefinite), 1: Burst mode (burst/idle counts).
        output logic [15:0] d2c_burst_count       , // (for TX/RX_D2C_PT) Unsigned 16-bit burst duration in Unit Intervals (UI).
        output logic [15:0] d2c_idle_count        , // (for TX/RX_D2C_PT) Unsigned 16-bit idle duration in Unit Intervals (UI).
        output logic [15:0] d2c_iter_count        , // (for TX/RX_D2C_PT) Unsigned 16-bit iteration count of burst-idle cycles.
        output logic [1:0]  d2c_compare_setup     , // (for TX/RX_D2C_PT) 00: Per-Lane comparison, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.

        //============================//
        // PHY Code Output            //
        //============================//
        output logic [$clog2(MAX_CODE+1)-1:0] swept_code,       // Current code under test → drive to PHY (registered)

        //============================//
        // Results / Status           //
        //============================//
        // Purely combinational outputs — always reflect the latest zone-tracker state.
        // Valid and stable while in D2C_SWEEP_DONE (and hold last-sweep values in IDLE).
        // If We test the Valid Lane: --> Use best_code[0] only.
        // If We test the Data Lanes: --> Use best_code for all lanes.
        output wire [$clog2(MAX_CODE+1)-1:0] best_code [0:15],  // Per-lane best midpoint (combinational)
        output wire [$clog2(MAX_CODE+1)-1:0] min_eye_width      // Narrowest best-window across active lanes (combinational)
        // output logic local_pt_en_dbg   <==== REMOVE this Single. DON'T USE IT.
    );
    import ltsm_state_n_pkg::*;
    // =========================================================================
    // Local parameter: code bit-width
    // =========================================================================
    localparam int unsigned CW = $clog2(MAX_CODE + 1);
    logic [CW-1:0] max_code;
    logic [CW-1:0] min_code;

    // =========================================================================
    // FSM State Encoding
    // D2C_SWEEP_WAIT_SETTLE removed — no analog settle needed.
    // D2C_SWEEP_CALC_BEST removed  — best_code/min_eye_width are purely combinational.
    // =========================================================================
    localparam [2:0]
    D2C_SWEEP_IDLE         = 3'd0, // Wait for local_sweep_en. Zone trackers hold last-sweep values.
    D2C_SWEEP_TRIGGER_D2C  = 3'd1, // Assert local_pt_en for 1+ cycles until local_test_d2c_done.
    D2C_SWEEP_LOG_RESULT   = 3'd2, // (1-cycle) Update zone trackers from d2c_perlane_pass.
    D2C_SWEEP_ADVANCE_CODE = 3'd3, // (1-cycle) Increment swept_code; loop back or finish.
    D2C_SWEEP_DONE         = 3'd4; // Hold sweep_done=1 until parent (substate) deasserts local_sweep_en.

    reg   [2:0]  current_state, next_state;
    logic        local_pt_en              ; // Assert to trigger TX/RX D2C point test (combinational)
    // assign local_pt_en_dbg = local_pt_en;
    logic [15:0] active_lanes_with_val    ; // To handle when we want to test the Valid Lane.
    logic [15:0] d2c_perlane_pass_with_val; // To handle when we want to test the Valid Lane.
    assign active_lanes_with_val     = (d2c_pattern_setup == 3'b010)? 16'd1 : active_lanes;
    assign d2c_perlane_pass_with_val = (d2c_pattern_setup == 3'b010)? {15'b0, d2c_val_pass} : d2c_perlane_pass;

    // =========================================================================
    // Sequential: current state register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= D2C_SWEEP_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational: next-state logic (Moore machine — no output in this block)
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        if(!local_sweep_en) begin
            next_state = D2C_SWEEP_IDLE;
        end
        else begin
            case (current_state)
                // -----------------------------------------------------------------
                // IDLE: wait for parent to assert local_sweep_en.
                // Sweep starts immediately at TRIGGER_D2C — no settle wait needed.
                // -----------------------------------------------------------------
                D2C_SWEEP_IDLE: begin
                    next_state = D2C_SWEEP_TRIGGER_D2C;
                end

                // -----------------------------------------------------------------
                // TRIGGER_D2C: hold local_pt_en until D2C test completes.
                // -----------------------------------------------------------------
                D2C_SWEEP_TRIGGER_D2C: begin
                    if (local_test_d2c_done) begin
                        next_state = D2C_SWEEP_LOG_RESULT;
                    end
                end

                // -----------------------------------------------------------------
                // LOG_RESULT: 1-cycle — zone trackers update in sequential block.
                // -----------------------------------------------------------------
                D2C_SWEEP_LOG_RESULT: begin
                    next_state = D2C_SWEEP_ADVANCE_CODE;
                end

                // -----------------------------------------------------------------
                // ADVANCE_CODE: 1-cycle — swept_code counter increments.
                // If more codes remain → TRIGGER_D2C (loop directly, no settle wait).
                // If at max_code → DONE (outputs are purely combinational).
                // -----------------------------------------------------------------
                D2C_SWEEP_ADVANCE_CODE: begin
                    if (swept_code >= max_code) begin
                        next_state = D2C_SWEEP_DONE;
                    end
                    else begin
                        next_state = D2C_SWEEP_TRIGGER_D2C;
                    end
                end

                // -----------------------------------------------------------------
                // DONE: hold sweep_done=1 until parent deasserts local_sweep_en.
                // -----------------------------------------------------------------
                D2C_SWEEP_DONE: begin
                    if (!local_sweep_en) begin
                        next_state = D2C_SWEEP_IDLE;
                    end
                end

                default: begin
                    next_state = D2C_SWEEP_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Combinational Output Logic (Moore: purely from current_state)
    // local_pt_en and sweep_done are purely combinational.
    // =========================================================================
    always_comb begin : OUTPUT_PROC
        // Safe defaults
        local_pt_en = 1'b0;
        sweep_done  = 1'b0;

        case (current_state)
            D2C_SWEEP_IDLE: begin
                // No activity.
            end

            D2C_SWEEP_TRIGGER_D2C: begin
                // Hold local_pt_en until D2C PT module asserts local_test_d2c_done.
                local_pt_en = 1'b1;
            end

            D2C_SWEEP_LOG_RESULT: begin
                // 1-cycle: sequential block updates zone trackers.
            end

            D2C_SWEEP_ADVANCE_CODE: begin
                // 1-cycle: sequential block increments swept_code.
            end

            D2C_SWEEP_DONE: begin
                sweep_done = 1'b1;
            end

            default: begin
                // No activity.
            end
        endcase
    end

    // =========================================================================
    // swept_code counter (registered)
    // Rule:
    // - IDLE state: hold at min_code so the next sweep always starts from MIN.
    // - ADVANCE_CODE state: increment if not yet at MAX.
    // - All other states: hold value.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : SWEPT_CODE_PROC
        if (!rst_n) begin
            swept_code <= {CW{1'b0}};
        end
        else begin
            case (current_state)
                D2C_SWEEP_IDLE: begin
                    swept_code <= min_code;
                end
                D2C_SWEEP_ADVANCE_CODE: begin
                    if (swept_code < max_code) begin
                        swept_code <= swept_code + 1'b1;
                    end
                    // At max_code: hold (FSM moves to DONE next cycle).
                end
                default: begin
                    // Hold swept_code in all other states.
                end
            endcase
        end
    end


    // =========================================================================
    // Per-lane zone-tracking registers (registered)
    // Rule: rst_n in SEPARATE if/else-if branches.
    // - Hard reset (rst_n=0): all trackers zeroed.
    // - IDLE state: trackers reset so the next sweep starts clean.
    // - LOG_RESULT state: update trackers from d2c_perlane_pass.
    // - All other states: hold (no change).
    // =========================================================================
    logic [CW-1:0] best_lo    [0:15]; // Start of best (longest) passing window
    logic [CW-1:0] best_hi    [0:15]; // End   of best (longest) passing window
    logic [CW-1:0] zone_min_r [0:15]; // Start of current contiguous pass zone
    logic          found_pass [0:15]; // 1 = at least one passing code seen this sweep
    logic          zone_valid [0:15]; // 1 = currently inside a contiguous pass zone

    always_ff @(posedge lclk or negedge rst_n) begin : ZONE_TRACK_PROC
        integer i;
        if (!rst_n) begin
            // Async reset must load a constant — resetting to the combinational
            // `min_code` infers an un-timeable FDCPE (async set+reset). The IDLE
            // state reloads these with min_code before any LOG_RESULT, so a
            // constant-0 async reset is functionally equivalent.
            for (i = 0; i < 16; i = i + 1) begin
                best_lo   [i] <= {CW{1'b0}};
                best_hi   [i] <= {CW{1'b0}};
                zone_min_r[i] <= {CW{1'b0}};
                found_pass[i] <= 1'b0;
                zone_valid[i] <= 1'b0;
            end
        end
        else begin
            case (current_state)
                // ── IDLE: reset trackers so next sweep starts clean ────────────
                D2C_SWEEP_IDLE: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        best_lo   [i] <= min_code;
                        best_hi   [i] <= min_code;
                        zone_min_r[i] <= min_code;
                        found_pass[i] <= 1'b0;
                        zone_valid[i] <= 1'b0;
                    end
                end

                // ── LOG_RESULT: update zone trackers from D2C result ──────────
                D2C_SWEEP_LOG_RESULT: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (d2c_perlane_pass_with_val[i] & active_lanes_with_val[i]) begin
                            // ── PASS ──────────────────────────────────────────
                            if (!zone_valid[i]) begin
                                // Enter a new passing zone.
                                zone_valid[i] <= 1'b1;
                                zone_min_r[i] <= swept_code;
                                if (!found_pass[i]) begin
                                    // First passing code ever — seed the best window.
                                    found_pass[i] <= 1'b1;
                                    best_lo   [i] <= swept_code;
                                    best_hi   [i] <= swept_code;
                                end
                            end
                            else begin
                                // Continue inside an existing passing zone.
                                // Replace best window only if this zone is wider.
                                if ((swept_code - zone_min_r[i]) > (best_hi[i] - best_lo[i])) begin
                                    best_lo[i] <= zone_min_r[i];
                                    best_hi[i] <= swept_code;
                                end
                            end
                        end
                        else begin
                            // ── FAIL: close the current zone ──────────────────
                            zone_valid[i] <= 1'b0;
                        end
                    end
                end

                // ── All other states: hold zone registers ──────────────────────
                default: begin
                    // No change.
                end
            endcase
        end
    end

    // =========================================================================
    // Combinational Eye-Width and Best-Code Computation
    //
    // These are PURELY COMBINATIONAL — no register needed.
    // They always reflect the latest state of best_lo[] / best_hi[] registers.
    // The parent reads them after sweep_done=1 (DONE state).
    //
    // eye_width[lane]  = best_hi[lane] - best_lo[lane]
    // min_eye_w[0]     = {CW{1'b1}}  (sentinel: start at maximum)
    // min_eye_w[n+1]   = min(eye_width[n], min_eye_w[n])  for active lanes with a pass
    // min_eye_width    = min_eye_w[16]  (wire output)
    // best_code[lane]  = midpoint of best window  (wire output)
    // =========================================================================
    wire [CW-1:0] eye_width      [0:15];
    wire [CW-1:0] min_eye_w      [0:16];

    assign min_eye_w[0] = {CW{1'b1}}; // Sentinel: all-ones = maximum possible width

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : GEN_COMB_RESULTS

            // Eye width for this lane (valid only when found_pass[lane]=1)
            assign eye_width[lane] = best_hi[lane] - best_lo[lane];

            // Ripple-min: carry forward the narrowest eye across active lanes.
            // If an active lane has no passing window, the minimum eye width is 0.
            assign min_eye_w[lane+1] =
                (active_lanes_with_val[lane]) ? (
                    (!found_pass[lane]) ? {CW{1'b0}} : (
                        (eye_width[lane] < min_eye_w[lane]) ? eye_width[lane] : min_eye_w[lane]
                    )
                ) : min_eye_w[lane];

            // Per-lane best midpoint code (combinational)
            assign best_code[lane] =
                (!active_lanes_with_val[lane]) ? min_code                      : // Inactive lane: safe default
                (found_pass[lane])    ? CW'(( {1'b0, best_lo[lane]} + {1'b0, best_hi[lane]} ) >> 1) : // Midpoint of widest window
                CW'(( {1'b0, max_code} + {1'b0, min_code} ) >> 1); // No pass found: use range midpoint
        end
    endgenerate

    // min_eye_width: result of the ripple-min chain (purely combinational wire output)
    assign min_eye_width = min_eye_w[16];


    // ===================================================================================================================== //
    // =============================================                           ============================================= //
    // ===========================================   set D2C PTs Configurations  =========================================== //
    // ===========================================    TX_D2C_PT  &  RX_D2C_PT    =========================================== //
    // =============================================                           ============================================= //
    // ===================================================================================================================== //

    // For the PARTNER enable signals:
    reg partner_pt_en;
    always_ff @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            partner_pt_en <= 1'b0;
        end
        else if(partner_sweep_en) begin
            partner_pt_en <= (partner_test_d2c_done)? 1'b0 : 1'b1;
        end
        else begin
            partner_pt_en <= 1'b0;
        end
    end

    // For the LOCAL/PARTNER modules enable signals:
    always_comb begin
        case(state_n) // The current operated substate.
            LOG_MBINIT_REPAIRMB : begin // Enable TX_D2C_PT test only in this state.
                local_tx_pt_en       = local_pt_en  ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = 1'b0         ;
            end
            LOG_MBTRAIN_VALVREF : begin // Enable RX_D2C_PT test only in this state.
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = local_pt_en  ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = 1'b0         ;
                partner_rx_pt_en     = partner_pt_en;
            end
            LOG_MBTRAIN_DATAVREF : begin // Enable RX_D2C_PT test only in this state.
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = local_pt_en  ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = 1'b0         ;
                partner_rx_pt_en     = partner_pt_en;
            end
            LOG_MBTRAIN_VALTRAINCENTER : begin // Enable TX_D2C_PT test only in this state.
                local_tx_pt_en       = local_pt_en  ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = 1'b0         ;
            end
            LOG_MBTRAIN_VALTRAINVREF : begin // Enable RX_D2C_PT test only in this state.
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = local_pt_en  ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = 1'b0         ;
                partner_rx_pt_en     = partner_pt_en;
            end
            LOG_MBTRAIN_DATATRAINCENTER1 : begin // Enable TX_D2C_PT test only in this state.
                local_tx_pt_en       = local_pt_en  ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = 1'b0         ;
            end
            LOG_MBTRAIN_DATATRAINVREF : begin // Enable RX_D2C_PT test only in this state.
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = local_pt_en  ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = 1'b0         ;
                partner_rx_pt_en     = partner_pt_en;
            end
            LOG_MBTRAIN_RXDESKEW : begin // Enable RX_D2C_PT test only in this state.
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = local_pt_en  ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = 1'b0         ;
                partner_rx_pt_en     = partner_pt_en;
            end
            LOG_MBTRAIN_DATATRAINCENTER2 : begin // Enable TX_D2C_PT test only in this state.
                local_tx_pt_en       = local_pt_en  ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = 1'b0         ;
            end
            LOG_MBTRAIN_LINKSPEED : begin // Enable TX_D2C_PT test only in this state.
                local_tx_pt_en       = local_pt_en  ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = 1'b0         ;
            end
            default : begin
                local_tx_pt_en       = 1'b0         ; // (for TX_D2C_PT) Enable local TX D2C point test.
                local_rx_pt_en       = 1'b0         ; // (for RX_D2C_PT) Enable local RX D2C point test.
                partner_tx_pt_en     = partner_pt_en;
                partner_rx_pt_en     = partner_pt_en;
            end
        endcase
    end

    // For common configurations of D2C_PT inMBTRAIN substates.
    // for VALID lane test.
    // Spec defaults: 128 iterations × 8-cycle burst = 1024 UI.
    localparam MBTRAIN_VAL_BURST_COUNT = 16'D8    ; // 8 UI in each burst.
    localparam MBTRAIN_VAL_IDLE_COUNT  = 16'D0    ; // 0 UI in each idle.
    localparam MBTRAIN_VAL_ITER_COUNT  = 16'D128  ; // 128 iterations.

    // for DATA lane tests used in MBTRAIN: Total UIs = 1 * 4096 = 4096 UI.
    localparam MBTRAIN_DATA_BURST_COUNT = 16'D4096; // 4096 UI in each burst.
    localparam MBTRAIN_DATA_IDLE_COUNT  = 16'D0   ; // 0 UI in each idle. (continuous mode).
    localparam MBTRAIN_DATA_ITER_COUNT  = 16'D1   ; // 1 iteration.       (continuous mode).

    // for DATA lane tests used in MBINIT: Total UIs = 32 * 128 = 4096 UI.
    localparam MBINIT_DATA_BURST_COUNT  = 16'D32  ; // 32 UI in each burst (in each Per Lane ID Pattern Word).
    localparam MBINIT_DATA_IDLE_COUNT   = 16'D0   ; // 0 UI in each idle.
    localparam MBINIT_DATA_ITER_COUNT   = 16'D128 ; // 128 iteration.

    always_comb begin
        case(state_n)
            LOG_MBTRAIN_VALVREF        ,
            LOG_MBTRAIN_VALTRAINVREF   ,
            LOG_MBTRAIN_VALTRAINCENTER : begin
                // Clock sampling/PI phase control
                d2c_clk_sampling     = 2'b00                  ; // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.

                // Received Tx Pattern Generator Setup Group:
                d2c_pattern_setup    = 3'b010                 ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_data_pattern_sel = 2'b10                  ; // Data pattern used during training: 2'b10 is "0" (all zeros)
                d2c_val_pattern_sel  = 1'b0                   ; // 0: VALTRAIN pattern.

                // Received Tx Pattern Mode Setup Group:
                d2c_pattern_mode     =  1'D0                  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_burst_count      = MBTRAIN_VAL_BURST_COUNT; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_idle_count       = MBTRAIN_VAL_IDLE_COUNT ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_iter_count       = MBTRAIN_VAL_ITER_COUNT ; // Iteration Count: Indicates the iteration count of bursts followed by idle.

                // Received Receiver Comparison Setup & Errors
                d2c_compare_setup    = 2'D2; // 2: Valid Lane Comparison.
            end

            LOG_MBTRAIN_DATAVREF         ,
            LOG_MBTRAIN_DATATRAINVREF    ,
            LOG_MBTRAIN_DATATRAINCENTER1 ,
            LOG_MBTRAIN_RXDESKEW         ,
            LOG_MBTRAIN_DATATRAINCENTER2 ,
            LOG_MBTRAIN_LINKSPEED        : begin
                // Clock sampling/PI phase control
                d2c_clk_sampling     = 2'b00                   ; // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.

                // Received Tx Pattern Generator Setup Group:
                d2c_pattern_setup    = 3'b001                  ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_data_pattern_sel = 2'b00                   ; // Data pattern: LFSR pattern.
                d2c_val_pattern_sel  = 1'b1                    ; // 0: VALTRAIN pattern (Valid framing).

                // Received Tx Pattern Mode Setup Group:
                d2c_pattern_mode     = 1'b0                    ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_burst_count      = MBTRAIN_DATA_BURST_COUNT; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_idle_count       = MBTRAIN_DATA_IDLE_COUNT ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_iter_count       = MBTRAIN_DATA_ITER_COUNT ; // Iteration Count: Indicates the iteration count of bursts followed by idle.

                // Received Receiver Comparison Setup & Errors
                d2c_compare_setup    = 2'D0; // 0: Per-Lane Comparison.
            end


            LOG_MBINIT_REPAIRMB : begin
                // Clock sampling/PI phase control
                d2c_clk_sampling     = 2'b00                 ; // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.

                // Received Tx Pattern Generator Setup Group:
                d2c_pattern_setup    = 3'b001                ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_data_pattern_sel = 2'b01                 ; // Data pattern: Per-Lane ID pattern.
                d2c_val_pattern_sel  = 1'b1                  ; // 0: VALTRAIN pattern (Valid framing);  1: Held Low.

                // Received Tx Pattern Mode Setup Group:
                d2c_pattern_mode     = 1'b0                   ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_burst_count      = MBINIT_DATA_BURST_COUNT; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_idle_count       = MBINIT_DATA_IDLE_COUNT ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_iter_count       = MBINIT_DATA_ITER_COUNT ; // Iteration Count: Indicates the iteration count of bursts followed by idle.

                // Received Receiver Comparison Setup & Errors
                d2c_compare_setup    = 2'D0; // 0: Per-Lane Comparison.
            end

            default : begin
                d2c_clk_sampling     = 2'b00 ; // (for TX/RX_D2C_PT) 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
                d2c_pattern_setup    = 3'b000; // (for TX/RX_D2C_PT) Bit0: Data Pattern Enable, Bit1: Valid Pattern Enable, Bit2: Clock Pattern Enable.
                d2c_data_pattern_sel = 2'b10 ; // (for TX/RX_D2C_PT) 00: LFSR pattern, 01: Per-Lane ID, 10: Fixed All Zeros, 11: Reserved.
                d2c_val_pattern_sel  = 1'b1  ; // (for TX/RX_D2C_PT) 0: VALTRAIN/functional pattern, 1: Held Low.
                d2c_pattern_mode     = 1'b0  ; // (for TX/RX_D2C_PT) 0: Continuous mode (indefinite), 1: Burst mode (burst/idle counts).
                d2c_burst_count      = 16'b0 ; // (for TX/RX_D2C_PT) Unsigned 16-bit burst duration in Unit Intervals (UI).
                d2c_idle_count       = 16'b0 ; // (for TX/RX_D2C_PT) Unsigned 16-bit idle duration in Unit Intervals (UI).
                d2c_iter_count       = 16'b0 ; // (for TX/RX_D2C_PT) Unsigned 16-bit iteration count of burst-idle cycles.
                d2c_compare_setup    = 2'b00 ; // (for TX/RX_D2C_PT) 00: Per-Lane comparison, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Find the Min and Max Code for each substate.
    // ------------------------------------------------------------------------
    always_comb begin
        case(state_n) // The current operated substate.
            LOG_MBINIT_REPAIRMB : begin // Enable TX_D2C_PT test only in this state.
                max_code = {CW{1'b0}};
                min_code = {CW{1'b0}};
            end
            LOG_MBTRAIN_VALVREF : begin // Enable RX_D2C_PT test only in this state.
                max_code = MAX_VAL_VREF_CODE[CW-1:0];
                min_code = MIN_VAL_VREF_CODE[CW-1:0];
            end
            LOG_MBTRAIN_DATAVREF : begin // Enable RX_D2C_PT test only in this state.
                max_code = MAX_DATA_VREF_CODE[CW-1:0];
                min_code = MIN_DATA_VREF_CODE[CW-1:0];
            end
            LOG_MBTRAIN_VALTRAINCENTER : begin // Enable TX_D2C_PT test only in this state.
                max_code = MAX_VAL_PI_CODE[CW-1:0];
                min_code = MIN_VAL_PI_CODE[CW-1:0];
            end
            LOG_MBTRAIN_VALTRAINVREF : begin // Enable RX_D2C_PT test only in this state.
                max_code = MAX_VAL_VREF_CODE[CW-1:0];
                min_code = MIN_VAL_VREF_CODE[CW-1:0];
            end
            LOG_MBTRAIN_DATATRAINCENTER1 : begin // Enable TX_D2C_PT test only in this state.
                max_code = MAX_DATA_PI_CODE[CW-1:0];
                min_code = MIN_DATA_PI_CODE[CW-1:0];
            end
            LOG_MBTRAIN_DATATRAINVREF : begin // Enable RX_D2C_PT test only in this state.
                max_code = MAX_DATA_VREF_CODE[CW-1:0];
                min_code = MIN_DATA_VREF_CODE[CW-1:0];
            end
            LOG_MBTRAIN_RXDESKEW : begin // Enable RX_D2C_PT test only in this state.
                max_code = MAX_DESKEW_CODE[CW-1:0];
                min_code = MIN_DESKEW_CODE[CW-1:0];
            end
            LOG_MBTRAIN_DATATRAINCENTER2 : begin // Enable TX_D2C_PT test only in this state.
                max_code = MAX_DATA_PI_CODE[CW-1:0];
                min_code = MIN_DATA_PI_CODE[CW-1:0];
            end
            LOG_MBTRAIN_LINKSPEED : begin // Enable TX_D2C_PT test only in this state.
                max_code = {CW{1'b0}};
                min_code = {CW{1'b0}};
            end
            default : begin
                max_code = {CW{1'b0}};
                min_code = {CW{1'b0}};
            end
        endcase
    end


endmodule


