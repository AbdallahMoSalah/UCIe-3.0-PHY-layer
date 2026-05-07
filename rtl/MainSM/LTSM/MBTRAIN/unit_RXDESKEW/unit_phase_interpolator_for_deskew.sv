// =============================================================================
// Module  : unit_phase_interpolator_for_deskew
// Purpose : Self-contained Phase Interpolator (PI) sweep FSM for
//           MBTRAIN.RXDESKEW.
//
//           Receives a single enable pulse (pi_en) from unit_RXDESKEW and
//           internally executes the full 5-step deskew sweep:
//             PI_SET_CODE          → set swept code, assert analog settle timer
//             PI_RX_D2C_PT         → run Rx D2C point test, wait for done
//             PI_LOG_RESULT        → log per-lane pass/fail; loop until MAX code
//             PI_LOG_PRESET_RESULT → (high-speed only) evaluate current preset
//             PI_CALC_APPLY        → compute per-lane optimal midpoint
//           On completion:  asserts pi_done  and waits in PI_WAIT_CLEAR
//                           until pi_en is de-asserted, then returns to PI_IDLE.
//           On abort (val-train fail): asserts pi_abort, same clearing protocol.
//
//           This pattern is analogous to unit_RX_D2C_PT's rx_pt_en / test_d2c_done
//           handshake.
//
// Algorithm (5-step min/max-edge + cross-lane normalization):
// ---------------------------------------------------------------------------
//   Step 1 — Per-lane edge tracking (PI_LOG_RESULT, sequential):
//     For every deskew code swept from MIN to MAX, for each negotiated lane:
//       PASS (d2c_perlane_err[lane]==0):
//         First-ever pass → record best_lo[lane] = swept_code_r  (min edge).
//         Every pass      → update best_hi[lane] = swept_code_r  (max edge).
//       FAIL: no update.
//
//   Step 2 — Highest min-edge (HIGHEST_MIN_EDGE_PROC, combinational):
//     highest_min_edge = max( best_lo[lane] ) across all negotiated lanes.
//
//   Step 3 — Per-lane available range (DESKEW_RANGE_GEN, combinational):
//     best_range[lane] = best_hi[lane] − highest_min_edge.
//
//   Step 4 — Min reference deskew range (PRESET_MIN_RANGE_PROC, combinational):
//     current_preset_min_range = min( best_range[lane] ) across negotiated lanes.
//
//   Step 5 — Midpoint (PI_CALC_APPLY, sequential):
//     best_deskew_code[lane] = ( highest_min_edge + best_hi[lane] ) / 2
//     fail_flag_r = 1 if ANY negotiated lane has found_pass[lane] == 0.
// =============================================================================

module unit_phase_interpolator_for_deskew #(
        parameter MAX_DESKEW_CODE = 7'd127,
        parameter MIN_DESKEW_CODE = 7'd0  ,
        // DW is derived from MAX_DESKEW_CODE and exposed as a parameter so it can
        // be used in the port-list declarations below.
        parameter DW              = $clog2(MAX_DESKEW_CODE + 1)
    ) (
        // =========================================================================
        // Clock and Reset
        // =========================================================================
        input  logic        lclk ,
        input  logic        rst_n,
        input  logic        is_ltsm_out_of_reset,

        // =========================================================================
        // Handshake Interface  (driven by unit_RXDESKEW)
        // =========================================================================
        // Assert pi_en for the full duration of RXDESKEW_APPLY_SKEW_SWEEP.
        // De-assert after pi_done or pi_abort is seen.
        input  logic        pi_en,
        // One-cycle pulse emitted when RXDESKEW transitions IDLE → START_REQ_RESP.
        // Used to clear preset-evaluation state at the start of a new session.
        input  logic        pi_session_start,

        // =========================================================================
        // Abort Triggers  (from rxdeskew_if)
        // =========================================================================
        input  logic        valtraincenter_fail_flag,
        input  logic        partner_valtraincenter_fail_flag,

        // =========================================================================
        // D2C Point-Test Interface  (from d2c_if, forwarded by unit_RXDESKEW)
        // =========================================================================
        input  logic        test_d2c_done,    // asserted when RX D2C PT finishes
        input  logic [15:0] d2c_perlane_err,  // per-lane error result

        // =========================================================================
        // Lane Configuration  (from unit_RXDESKEW)
        // =========================================================================
        // 3-bit encoding that represents the 16-lanes mask of negotiated (functional) data lanes. (Table 4-9 in the UCIe-3.0-reference)
        input  logic [2:0] mb_rx_data_lane_mask,
        // High-speed path flag (speed > 32 GT/s).
        input  logic        is_high_speed,

        // =========================================================================
        // Preset Evaluation Inputs  (high-speed path only)
        // =========================================================================
        input  logic [2:0]  partner_preset,
        input  logic        partner_preset_fail_status,

        // =========================================================================
        // Handshake Outputs  (back to unit_RXDESKEW)
        // =========================================================================
        // pi_done  — asserted while in PI_WAIT_CLEAR (sweep complete, calc done).
        output logic        pi_done,
        // pi_abort — asserted while in PI_ABORT (val-train fail detected).
        output logic        pi_abort,
        // pi_in_sweep — 1 during PI_SET_CODE / PI_RX_D2C_PT / PI_LOG_RESULT.
        //   Drives the phy_rx_deskew_ctrl mux in unit_RXDESKEW.
        output logic        pi_in_sweep,

        // =========================================================================
        // Control Outputs  (forwarded to rxdeskew_if / d2c_if by unit_RXDESKEW)
        // =========================================================================
        output logic        pi_analog_settle_timer_en,
        output logic        pi_rx_pt_en,
        // Current sweep code (broadcast to phy_rx_deskew_ctrl while pi_in_sweep).
        output logic [DW-1:0] swept_code_r_out,

        // =========================================================================
        // Computation Outputs  (per-lane optimal codes, consumed by unit_RXDESKEW)
        // =========================================================================
        output logic [DW-1:0] best_deskew_code [15:0],
        // // Fail flag: 1 if any negotiated lane has no passing deskew code.
        // output logic          fail_flag_r,

        // =========================================================================
        // Preset Evaluation Outputs  (consumed by unit_RXDESKEW FSM decisions)
        // =========================================================================
        // output logic [DW-1:0] current_preset_min_range_out,
        output logic [2:0]    best_preset_saved,
        output logic [DW-1:0] overall_best_min_range
        // output logic [DW-1:0] overall_best_lo    [15:0],
        // output logic [DW-1:0] overall_best_hi    [15:0],
        // output logic          overall_found_pass [15:0]
    );
    parameter      IS_HIGHEST_MIN_EDGE_UNIFIED = 1'b0; // I think (0) will be more realistic. for now, I prefer to keep it with 0 tell i ask someone better than me.

    logic [DW-1:0] overall_best_lo    [15:0];
    logic [DW-1:0] overall_best_hi    [15:0];
    logic          overall_found_pass [15:0];

    // =========================================================================
    // PI FSM State Encoding
    // =========================================================================
    localparam [2:0]
    PI_IDLE              = 3'd0,  // Wait for pi_en assertion.
    PI_SET_CODE          = 3'd1,  // Drive swept_code_r; analog settle.
    PI_RX_D2C_PT         = 3'd2,  // Enable RX D2C PT; wait for done.
    PI_LOG_RESULT        = 3'd3,  // Log per-lane result; loop or advance.
    PI_LOG_PRESET_RESULT = 3'd4,  // (HS) Evaluate current preset (1 cycle).
    PI_CALC_APPLY        = 3'd5,  // Compute midpoint (1 cycle).
    PI_WAIT_CLEAR        = 3'd6,  // Assert pi_done; wait for pi_en low.
    PI_ABORT             = 3'd7;  // Assert pi_abort; wait for pi_en low.

    reg [2:0] pi_state, pi_next;

    // =========================================================================
    // Internal Sweep Counter  (replaces swept_code_r in unit_RXDESKEW)
    // =========================================================================
    reg [DW-1:0] swept_code_r;

    // Expose for parent's phy_rx_deskew_ctrl mux.
    assign swept_code_r_out = swept_code_r;

    // =========================================================================
    // PI FSM — Sequential (State Register)
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : PI_STATE_REG
        if (!rst_n) pi_state <= PI_IDLE;
        else if (!is_ltsm_out_of_reset) pi_state <= PI_IDLE;
        else        pi_state <= pi_next;
    end

    // =========================================================================
    // PI FSM — Combinational (Next-State Logic)
    // =========================================================================
    always_comb begin : PI_NEXT_STATE
        case (pi_state)
            // -----------------------------------------------------------------
            // (S0) PI_IDLE: Wait for pi_en from unit_RXDESKEW.
            // -----------------------------------------------------------------
            PI_IDLE: begin
                pi_next = pi_en ? PI_SET_CODE : PI_IDLE;
            end
            // -----------------------------------------------------------------
            // (S1) PI_SET_CODE: Broadcast swept_code_r; check abort condition.
            // -----------------------------------------------------------------
            PI_SET_CODE: begin
                if (!pi_en)
                    pi_next = PI_IDLE;
                else if (valtraincenter_fail_flag | partner_valtraincenter_fail_flag)
                    pi_next = PI_ABORT;
                else
                    pi_next = PI_RX_D2C_PT;
            end
            // -----------------------------------------------------------------
            // (S2) PI_RX_D2C_PT: Run Rx D2C point test; wait for done.
            // -----------------------------------------------------------------
            PI_RX_D2C_PT: begin
                if (!pi_en)
                    pi_next = PI_IDLE;
                else if (test_d2c_done)
                    pi_next = PI_LOG_RESULT;
                else
                    pi_next = PI_RX_D2C_PT;
            end
            // -----------------------------------------------------------------
            // (S3) PI_LOG_RESULT: Log result; loop back or advance.
            // -----------------------------------------------------------------
            PI_LOG_RESULT: begin
                if (!pi_en)
                    pi_next = PI_IDLE;
                else if (swept_code_r == MAX_DESKEW_CODE[DW-1:0])
                    pi_next = is_high_speed ? PI_LOG_PRESET_RESULT : PI_CALC_APPLY;
                else
                    pi_next = PI_SET_CODE;
            end
            // -----------------------------------------------------------------
            // (S4) PI_LOG_PRESET_RESULT: 1-cycle preset evaluation (HS only).
            // -----------------------------------------------------------------
            PI_LOG_PRESET_RESULT: begin
                pi_next = PI_CALC_APPLY;
            end
            // -----------------------------------------------------------------
            // (S5) PI_CALC_APPLY: Compute per-lane midpoints (1 cycle).
            // -----------------------------------------------------------------
            PI_CALC_APPLY: begin
                pi_next = PI_WAIT_CLEAR;
            end
            // -----------------------------------------------------------------
            // (S6) PI_WAIT_CLEAR: Assert pi_done; wait for pi_en to drop.
            // -----------------------------------------------------------------
            PI_WAIT_CLEAR: begin
                pi_next = pi_en ? PI_WAIT_CLEAR : PI_IDLE;
            end
            // -----------------------------------------------------------------
            // (S7) PI_ABORT: Assert pi_abort; wait for pi_en to drop.
            // -----------------------------------------------------------------
            PI_ABORT: begin
                pi_next = pi_en ? PI_ABORT : PI_IDLE;
            end
            default: pi_next = PI_IDLE;
        endcase
    end

    // =========================================================================
    // PI FSM — Combinational Outputs
    // =========================================================================
    assign pi_done                  = (pi_state == PI_WAIT_CLEAR);
    assign pi_abort                 = (pi_state == PI_ABORT);
    assign pi_in_sweep              = (pi_state == PI_SET_CODE   ||
            pi_state == PI_RX_D2C_PT  ||
            pi_state == PI_LOG_RESULT);
    assign pi_analog_settle_timer_en = (pi_state == PI_SET_CODE);
    assign pi_rx_pt_en               = (pi_state == PI_RX_D2C_PT);

    // =========================================================================
    // SWEPT_CODE_PROC: Deskew sweep counter
    //   Reset to MIN when PI exits IDLE (start of every new sweep).
    //   Incremented once per PI_LOG_RESULT cycle until MAX is reached.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : SWEPT_CODE_PROC
        if (!rst_n) begin
            swept_code_r <= MIN_DESKEW_CODE[DW-1:0];
        end else if (!is_ltsm_out_of_reset) begin
            swept_code_r <= MIN_DESKEW_CODE[DW-1:0];
        end else if (pi_state == PI_IDLE && pi_en) begin
            // New sweep starting — reset counter.
            swept_code_r <= MIN_DESKEW_CODE[DW-1:0];
        end else if (pi_state == PI_LOG_RESULT) begin
            if (swept_code_r != MAX_DESKEW_CODE[DW-1:0])
                swept_code_r <= swept_code_r + 1'b1;
        end
    end

    // =========================================================================
    // Per-lane eye-map tracking registers
    // =========================================================================
    logic [DW-1:0] best_lo    [15:0];
    logic [DW-1:0] best_hi    [15:0];
    logic          found_pass [15:0];

    // =========================================================================
    // Combinational range helpers (per-lane)
    // =========================================================================
    wire [DW-1:0] best_range [15:0];

    // Packed buses (unpacked arrays cannot appear in reduction operators).
    wire [15:0] found_pass_bus;
    wire [15:0] overall_found_pass_bus;

    // =========================================================================
    // Negotiated data lane mask
    // Converts 3-bit mb_rx_data_lane_mask → 16-bit bitmask of active lanes.
    // =========================================================================
    logic [15:0] negotiated_data_lanes;
    always_comb begin
        case (mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    // =========================================================================
    // HIGHEST_MIN_EDGE_PROC: Step 2 — Combinational max(best_lo[]) reduction
    // =========================================================================
    logic [DW-1:0] highest_min_edge_arr [0:16];
    always_comb begin : HIGHEST_MIN_EDGE_PROC
        integer l;
        highest_min_edge_arr[0] = '0;
        for (l = 0; l < 16; l = l + 1) begin
            highest_min_edge_arr[l+1] = (negotiated_data_lanes[l] && found_pass[l] && (best_lo[l] > highest_min_edge_arr[l])) ?
                best_lo[l] : highest_min_edge_arr[l];
        end
    end
    wire [DW-1:0] highest_min_edge = highest_min_edge_arr[16];

    // =========================================================================
    // DESKEW_RANGE_GEN: Step 3 — Per-lane available range (combinational)
    // =========================================================================
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : DESKEW_RANGE_GEN
            assign found_pass_bus[lane]         = found_pass[lane];
            assign overall_found_pass_bus[lane] = overall_found_pass[lane];

            assign best_range[lane] = (found_pass[lane] == 1'b1 && best_hi[lane] >= highest_min_edge) ?
                (best_hi[lane] - highest_min_edge) : '0;
        end
    endgenerate

    // =========================================================================
    // PRESET_MIN_RANGE_PROC: Step 4 — Combinational min(best_range[]) reduction
    // =========================================================================
    logic [DW-1:0] current_preset_min_range [0:16];

    always_comb begin : PRESET_MIN_RANGE_PROC
        integer l;
        current_preset_min_range[0] = MAX_DESKEW_CODE[DW-1:0];
        for (l = 0; l < 16; l = l + 1) begin
            current_preset_min_range[l + 1] = (negotiated_data_lanes[l] && (best_range[l] < current_preset_min_range[l])) ?
                best_range[l] : current_preset_min_range[l];
        end
    end

    // assign current_preset_min_range_out = current_preset_min_range[16];

    // =========================================================================
    // PRESET_EVAL_PROC: Sequential — tracks the globally best preset.
    //   Triggered on PI_LOG_PRESET_RESULT (replaces in_log_preset_result gate).
    //   Reset on pi_session_start (replaces in_idle_start gate).
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : PRESET_EVAL_PROC
        integer i;
        if (!rst_n) begin
            best_preset_saved      <= 3'd0;
            overall_best_min_range <= '0;
            for (i = 0; i < 16; i = i + 1) begin
                overall_best_lo[i]    <= '0;
                overall_best_hi[i]    <= '0;
                overall_found_pass[i] <= 1'b0;
            end
        end else if (!is_ltsm_out_of_reset) begin
            best_preset_saved      <= 3'd0;
            overall_best_min_range <= '0;
            for (i = 0; i < 16; i = i + 1) begin
                overall_best_lo[i]    <= '0;
                overall_best_hi[i]    <= '0;
                overall_found_pass[i] <= 1'b0;
            end
        end else begin
            // Clear at the start of a new RXDESKEW session.
            if (pi_session_start) begin
                best_preset_saved      <= 3'd0;
                overall_best_min_range <= '0;
                for (i = 0; i < 16; i = i + 1) begin
                    overall_best_lo[i]    <= '0;
                    overall_best_hi[i]    <= '0;
                    overall_found_pass[i] <= 1'b0;
                end
            end

            // Evaluate the current preset when PI reaches LOG_PRESET_RESULT.
            if (pi_state == PI_LOG_PRESET_RESULT) begin
                if (current_preset_min_range[16] >= overall_best_min_range) begin
                    overall_best_min_range <= current_preset_min_range[16];
                    best_preset_saved      <= partner_preset;
                    for (i = 0; i < 16; i = i + 1) begin
                        if (IS_HIGHEST_MIN_EDGE_UNIFIED == 1'B1) begin
                            // Store the common lower bound in every overall_best_lo slot.
                            // CALC_APPLY: midpoint = (overall_best_lo[i] + overall_best_hi[i]) / 2
                            //                      = (highest_min_edge + best_hi[i]) / 2  (Step 5).
                            overall_best_lo[i] <= highest_min_edge;
                        end
                        else begin
                            // CALC_APPLY: midpoint = (overall_best_lo[i] + overall_best_hi[i]) / 2
                            //                      = (best_lo[i] + best_hi[i]) / 2  (Step 5).
                            overall_best_lo[i] <= best_lo[i];
                        end
                        overall_best_hi[i]     <= best_hi[i];
                        overall_found_pass[i]  <= found_pass[i];
                    end
                end
            end
        end
    end

    // =========================================================================
    // DESKEW_TRACKING_PROC: Sequential — per-lane edge tracking + CALC_APPLY
    //
    //   PI_IDLE && pi_en  → reset tracking arrays (replaces in_preset_req_start).
    //   PI_LOG_RESULT     → track min/max edges per lane   (Step 1).
    //   PI_CALC_APPLY     → compute midpoints + fail flag   (Step 5).
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : DESKEW_TRACKING_PROC
        integer i;
        if (!rst_n) begin
            // fail_flag_r <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                best_lo[i]          <= '0;
                best_hi[i]          <= '0;
                found_pass[i]       <= 1'b0;
                best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
            end
        end else if (!is_ltsm_out_of_reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                best_lo[i]          <= '0;
                best_hi[i]          <= '0;
                found_pass[i]       <= 1'b0;
                best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
            end
        end else begin
            // -----------------------------------------------------------------
            // Reset tracking arrays when starting a new sweep
            // (PI_IDLE → PI_SET_CODE, i.e., on the cycle pi_en is first seen).
            // -----------------------------------------------------------------
            if (pi_state == PI_IDLE && pi_en) begin
                // fail_flag_r <= 1'b0;
                for (i = 0; i < 16; i = i + 1) begin
                    best_lo[i]    <= '0;
                    best_hi[i]    <= '0;
                    found_pass[i] <= 1'b0;
                end
            end

            // -----------------------------------------------------------------
            // Step 1 — PI_LOG_RESULT: Track min edge (best_lo) and max edge (best_hi).
            // -----------------------------------------------------------------
            else if (pi_state == PI_LOG_RESULT) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (!d2c_perlane_err[i] && negotiated_data_lanes[i]) begin
                        if (!found_pass[i]) begin
                            found_pass[i] <= 1'b1;
                            best_lo[i]    <= swept_code_r; // min edge (first pass)
                        end
                        best_hi[i] <= swept_code_r; // max edge (every pass)
                    end
                end
            end

            // -----------------------------------------------------------------
            // Step 5 — PI_CALC_APPLY: Compute per-lane midpoint and fail flag.
            // -----------------------------------------------------------------
            else if (pi_state == PI_CALC_APPLY) begin
                if (is_high_speed) begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (overall_found_pass[i]) begin
                            best_deskew_code[i] <=
                                ({1'b0, overall_best_lo[i]} + {1'b0, overall_best_hi[i]}) >> 1;
                        end else begin
                            best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
                        end
                    end
                    // fail_flag_r <= ~(&(overall_found_pass_bus | (~negotiated_data_lanes)));
                end else begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (found_pass[i]) begin
                            best_deskew_code[i] <=
                                ({1'b0, highest_min_edge} + {1'b0, best_hi[i]}) >> 1;
                        end else begin
                            best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
                        end
                    end
                    // fail_flag_r <= ~(&(found_pass_bus | (~negotiated_data_lanes)));
                end
            end
        end
    end

endmodule
