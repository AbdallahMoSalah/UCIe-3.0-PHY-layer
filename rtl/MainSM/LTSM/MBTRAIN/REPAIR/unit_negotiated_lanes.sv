// =============================================================================
// Module  : unit_negotiated_lanes
// Purpose : Decode the 3-bit MB lane-mask encoding (from internal_ltsm_if /
//           MBTRAIN_if) into 16-bit one-hot active-lane vectors for both the
//           TX side and the RX side.
//
// ─── DESIGN RULES ────────────────────────────────────────────────────────────
//   1. PURELY COMBINATIONAL — no clock, no reset, no state.
//   2. SINGLE RESPONSIBILITY — only maps 3-bit mask to 16-bit one-hot vector.
//   3. All evaluation logic (error detection, width-degrade feasibility) belongs
//      inside the sub-state FSM (e.g., unit_LINKSPEED_local, unit_RXDESKEW_local).
//      This module does NOT compute width-degrade eligibility.
//   4. Default output is 16'h0000 (no lanes active) for all reserved encodings.
//
// ─── LANE MASK ENCODING ──────────────────────────────────────────────────────
//   (Per internal_ltsm_if.sv / UCIe 3.0 Specification §4.x)
//
//   Encoding  | Active Lanes           | One-Hot Mask
//   ----------|------------------------|-------------
//   3'b000    | None (degrade failed)  | 16'h0000
//   3'b001    | Lanes  0 –  7 (x8 lo) | 16'h00FF
//   3'b010    | Lanes  8 – 15 (x8 hi) | 16'hFF00
//   3'b011    | Lanes  0 – 15 (x16)   | 16'hFFFF
//   3'b100    | Lanes  0 –  3 (x4 lo) | 16'h000F
//   3'b101    | Lanes  4 –  7 (x4 ml) | 16'h00F0
//   others    | None (safe default)    | 16'h0000
//
// ─── USAGE ───────────────────────────────────────────────────────────────────
//   Instantiate in sub-state wrappers (e.g. wrapper_RXDESKEW.sv,
//   wrapper_LINKSPEED.sv) to provide the active-lane mask to sub-state FSMs.
//
//   Sub-state FSMs use active_rx_lanes to:
//     - Mask per-lane D2C pass/fail results (AND with d2c_perlane_pass).
//     - Determine which lanes are included in sweep analysis.
//     - Evaluate width-degrade or repair feasibility (done inside the FSM).
//
// ─── MEMORY REFERENCE ────────────────────────────────────────────────────────
//   See: target_implementation_technique/null/what_we_will_do_next/
//        memory_for_RXDESKEW_local.md  Section 6 — unit_negotiated_lanes Design
//        memory_for_LINKSPEED_local.md Section 5.2 — Combinational Decoder Separation
// =============================================================================

module unit_negotiated_lanes (
        //=====================================//
        // Inputs: Raw 3-bit lane masks        //
        //=====================================//
        input  logic [2:0]  mb_rx_data_lane_mask, // Negotiated Rx active-lane encoding (from MBTRAIN_if / registers).
        input  logic [2:0]  mb_tx_data_lane_mask, // Negotiated Tx active-lane encoding (from MBTRAIN_if / registers).

        //=====================================//
        // Outputs: 16-bit one-hot lane vectors //
        //=====================================//
        // A bit set to 1 means that logical data lane is active/functional.
        // A bit set to 0 means that lane is inactive (unused or failed).
        output logic [15:0] active_rx_lanes, // 1 = that Rx data lane is active.
        output logic [15:0] active_tx_lanes, // 1 = that Tx data lane is active.

        //==========================================================================//
        // Inputs: Shared Lane Map Evaluation                                       //
        // Used by LINKSPEED and REPAIR substates to compute width degradation.     //
        //==========================================================================//
        input  logic [15:0] success_tx_lanes,          // A 16-bit vector where each bit represents the status of the corresponding physical TX data lane.

        input  logic        rf_cap_SPMW,               // Standard Package Module Width (SPMW) register bit.
        // 1 = Module is limited to x8 width capability; 0 = Module supports full x16 width.
        input  logic [3:0]  rf_ctrl_target_link_width, // Register control specifying the target link width configuration.
        // 4'h2 = Target link width is x16; 4'h1 = Target link width is x8; others = Reserved.
        input  logic        param_UCIe_S_x8,           // Forced x8 Mode Configuration Parameter (UCIe-S).
        // 1 = Force x8 mode operation; 0 = Standard operation (x16 capability allowed).

        //==========================================================================//
        // Outputs: Shared Lane Map Evaluation                                      //
        // Results of the combinational degradation logic.                          //
        //==========================================================================//
        output logic [2:0]  degraded_lane_map_code,    // 3-bit lane mask code representing the selected degraded lane map configuration:
        // 3'b000: None (Degradation not possible/failed)
        // 3'b001: Logical Lanes 0 to 7 (x8 low-half active)
        // 3'b010: Logical Lanes 8 to 15 (x8 high-half active)
        // 3'b011: Logical Lanes 0 to 15 (x16 full-width active)
        // 3'b100: Logical Lanes 0 to 3 (x4 low-quarter active)
        // 3'b101: Logical Lanes 4 to 7 (x4 mid-low active)
        output logic        degrade_feasible,          // 1 = A valid degraded lane map configuration was successfully resolved (code != 3'b000)
        output logic        is_x16_module              // 1 = X16 standard package (all-functional code = 3'b011)
                                                       // 0 = X8  standard package or forced X8 mode (all-functional code = 3'b001)
    );

    // 3'b000: None (Degradation not possible/failed)
    // 3'b001: Logical Lanes 0 to 7 (x8 low-half active)
    // 3'b010: Logical Lanes 8 to 15 (x8 high-half active)
    // 3'b011: Logical Lanes 0 to 15 (x16 full-width active)
    // 3'b100: Logical Lanes 0 to 3 (x4 low-quarter active)
    // 3'b101: Logical Lanes 4 to 7 (x4 mid-low active)
    localparam [2:0] X16_FFFF = 3'b011;
    localparam [2:0] X16_00FF = 3'b001;
    localparam [2:0] X16_FF00 = 3'b010;
    localparam [2:0] X16_000F = 3'b100;
    localparam [2:0] X16_00F0 = 3'b101;
    localparam [2:0] X16_0000 = 3'b000;

    // =========================================================================
    // RX Active Lane Decoder
    // Purely combinational case statement — no latches, no registers.
    // =========================================================================
    always_comb begin : RX_DECODE
        case (mb_rx_data_lane_mask)
            X16_00FF : active_rx_lanes = 16'h00FF; // Lanes 0–7   (x8 low half)
            X16_FF00 : active_rx_lanes = 16'hFF00; // Lanes 8–15  (x8 high half)
            X16_FFFF : active_rx_lanes = 16'hFFFF; // Lanes 0–15  (x16 full width)
            X16_000F : active_rx_lanes = 16'h000F; // Lanes 0–3   (x4 low quarter)
            X16_00F0 : active_rx_lanes = 16'h00F0; // Lanes 4–7   (x4 mid-low quarter)
            default: active_rx_lanes   = 16'h0000; // 3'b000 = None, or reserved encoding → safe default
        endcase
    end

    // =========================================================================
    // TX Active Lane Decoder
    // Purely combinational case statement — no latches, no registers.
    // =========================================================================
    always_comb begin : TX_DECODE
        case (mb_tx_data_lane_mask)
            X16_00FF : active_tx_lanes = 16'h00FF; // Lanes 0–7   (x8 low half)
            X16_FF00 : active_tx_lanes = 16'hFF00; // Lanes 8–15  (x8 high half)
            X16_FFFF : active_tx_lanes = 16'hFFFF; // Lanes 0–15  (x16 full width)
            X16_000F : active_tx_lanes = 16'h000F; // Lanes 0–3   (x4 low quarter)
            X16_00F0 : active_tx_lanes = 16'h00F0; // Lanes 4–7   (x4 mid-low quarter)
            default: active_tx_lanes = 16'h0000; // 3'b000 = None, or reserved encoding → safe default
        endcase
    end

    // =========================================================================
    // Combinational Lane Map Degradation Evaluation
    // Shared between LINKSPEED and REPAIR substates.
    // =========================================================================
    wire is_x8_module;

    always_comb begin : DEGRADE_EVAL
        if (is_x16_module) begin
            // x16 standard package module
            if (success_tx_lanes == 16'hFFFF)
                degraded_lane_map_code = 3'b011; // Logical Lanes 0 to 15
            else if (success_tx_lanes[7:0]  == 8'hFF)
                degraded_lane_map_code = 3'b001; // Logical Lanes 0 to 7
            else if (success_tx_lanes[15:8] == 8'hFF)
                degraded_lane_map_code = 3'b010; // Logical Lanes 8 to 15
            else
                degraded_lane_map_code = 3'b000; // degrade not possible
        end else if (is_x8_module) begin
            // x8 standard package module OR x8 Mode
            if (success_tx_lanes[7:0] == 8'hFF)
                degraded_lane_map_code = 3'b001; // Logical Lanes 0 to 7
            else if (success_tx_lanes[3:0] == 4'hF)
                degraded_lane_map_code = 3'b100; // Logical Lanes 0 to 3
            else if (success_tx_lanes[7:4] == 4'hF)
                degraded_lane_map_code = 3'b101; // Logical Lanes 4 to 7
            else
                degraded_lane_map_code = 3'b000; // degrade not possible
        end else begin
            degraded_lane_map_code = 3'b000;
        end
    end

    assign degrade_feasible = (degraded_lane_map_code != 3'b000);

    // is_x16_module: 1 when the link is a full X16 standard package.
    //   PARTNER FSM uses this to determine which code means "all functional":
    //     X16 module → full_width_code = 3'b011
    //     X8  module → full_width_code = 3'b001
    assign is_x16_module = (rf_cap_SPMW == 1'b0) && (rf_ctrl_target_link_width == 4'h2) && (param_UCIe_S_x8 == 1'b0);
    assign is_x8_module  = rf_ctrl_target_link_width == 4'h1;
endmodule
// =============================================================================
// END unit_negotiated_lanes
// =============================================================================
