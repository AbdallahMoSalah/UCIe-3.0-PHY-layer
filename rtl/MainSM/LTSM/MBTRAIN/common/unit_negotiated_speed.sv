// =============================================================================
// Module  : unit_negotiated_speed
// Purpose : Decode the 3-bit phy_negotiated_speed encoding into boolean flags
//           and named speed indicators for use in MBTRAIN sub-state FSMs.
//
// This is a purely combinational, synthesizable decoder — no clock or reset.
//
// Speed encoding (per internal_ltsm_if.sv / UCIe Spec Table 4-1):
//   3'b000 →  4 GT/s
//   3'b001 →  8 GT/s
//   3'b010 → 12 GT/s
//   3'b011 → 16 GT/s
//   3'b100 → 24 GT/s
//   3'b101 → 32 GT/s   ← boundary (≤ 32 GT/s = "standard speed", > 32 GT/s = "high speed")
//   3'b110 → 48 GT/s   ← HIGH SPEED: requires EQ preset negotiation in RXDESKEW
//   3'b111 → 64 GT/s   ← HIGH SPEED
//
// The critical flag `is_high_speed` is used in RXDESKEW to determine whether
// EQ Preset negotiation (Step 2) is required, and whether the DTC1 arc loop
// and exit_to_DTC1 messages are enabled.
//
// Memory Reference:
//   See: target_implementation_technique/null/what_we_will_do_next/memory_for_RXDESKEW_local.md
//        Section 7 — unit_negotiated_speed.sv Design
// =============================================================================

module unit_negotiated_speed (
        //=====================================//
        // Input: Raw speed encoding           //
        //=====================================//
        input  logic [2:0] phy_negotiated_speed, // From PHY / MBTRAIN_if

        //=====================================//
        // Outputs: Speed flags                //
        //=====================================//
        // The most important flag — used by RXDESKEW, TXSELFCAL, etc.
        output logic        is_high_speed // 1 = speed > 32 GT/s (48 or 64 GT/s)
        // 0 = speed ≤ 32 GT/s
    );

    // =========================================================================
    // High-Speed Flag
    // speed > 32 GT/s means encoding is 3'b110 (48 GT/s) or 3'b111 (64 GT/s)
    // =========================================================================
    localparam [2:0] SPEED_32G = 3'b101;
    assign is_high_speed = (phy_negotiated_speed > SPEED_32G);

    // // =========================================================================
    // // Individual Speed Flags (one-hot, combinational)
    // // Current this signals are not used so, comment-out them.
    // // =========================================================================
    // assign speed_is_4g  = (phy_negotiated_speed == 3'b000);
    // assign speed_is_8g  = (phy_negotiated_speed == 3'b001);
    // assign speed_is_12g = (phy_negotiated_speed == 3'b010);
    // assign speed_is_16g = (phy_negotiated_speed == 3'b011);
    // assign speed_is_24g = (phy_negotiated_speed == 3'b100);
    // assign speed_is_32g = (phy_negotiated_speed == 3'b101);
    // assign speed_is_48g = (phy_negotiated_speed == 3'b110);
    // assign speed_is_64g = (phy_negotiated_speed == 3'b111);

endmodule


