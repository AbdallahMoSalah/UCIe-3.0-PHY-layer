// =============================================================================
// unit_val_sweep.sv
//
// Vref Sweep Datapath for the Valid-Lane Receiver Voltage Reference calibration.
// Extracted from unit_VALVREF so that the FSM shell remains small and the sweep
// logic can be reused or independently verified.
//
// This module has NO interface ports. All signals are plain scalars.
// =============================================================================
module unit_val_sweep #(
        parameter MAX_VAL_VREF_CODE = 7'D127,
        parameter MIN_VAL_VREF_CODE = 7'D10
    ) (
        // ======================== //
        // Clock & Reset            //
        // ======================== //
        input  wire        lclk,
        input  wire        rst_n,
        input  wire        is_ltsm_out_of_reset,

        // ======================== //
        // Control Flags            //
        // ======================== //
        input  wire        start_req_state,
        input  wire        log_result_state,
        input  wire        calc_apply_state,

        // ======================== //
        // D2C Test Result          //
        // ======================== //
        input  wire        d2c_val_pass,  // 1 = valid lane passed at current Vref code.

        // ======================== //
        // Outputs                  //
        // ======================== //
        // During sweep (S3-S5): current swept code driven to PHY.
        // After CALC_APPLY (S6): holds the computed midpoint (best Vref center).
        output reg  [$clog2(MAX_VAL_VREF_CODE + 1)-1:0] phy_rx_valvref_ctrl,
        // 1 when CALC_APPLY finishes with no passing Vref code found.
        // Used by the VALVREF FSM to trigger TO_TRAINERROR.
        output wire        valvref_fail_flag
    );

    // -------------------------------------------------------------------------
    // Width of the Vref code counter.
    // Must match the declaration in unit_VALVREF.sv.
    // -------------------------------------------------------------------------
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE + 1);

    // -------------------------------------------------------------------------
    // Internal sweep-tracking registers
    // -------------------------------------------------------------------------
    reg  [VREF_CODE_WIDTH-1:0] temp_min_vref;   // zone_min_r  : start of current contiguous pass zone
    reg  [VREF_CODE_WIDTH-1:0] min_vref_code;   // best_lo     : left  edge of widest pass window
    reg  [VREF_CODE_WIDTH-1:0] max_vref_code;   // best_hi     : right edge of widest pass window
    reg                        vref_code_filled; // found_pass  : at least one passing code seen
    reg                        is_in_valid_region; // zone_valid : currently inside a contiguous pass zone

    // -------------------------------------------------------------------------
    // Combinational helpers
    // -------------------------------------------------------------------------
    wire [VREF_CODE_WIDTH-1:0] vref_range;      // best recorded window width
    wire [VREF_CODE_WIDTH-1:0] temp_vref_range; // current zone width

    assign vref_range      = (vref_code_filled == 1'b1) ? (max_vref_code - min_vref_code) : '0;
    assign temp_vref_range = (phy_rx_valvref_ctrl - temp_min_vref);

    // Fail flag: set for exactly 1 cycle during CALC_APPLY when no passing code was found.
    assign valvref_fail_flag = calc_apply_state & (~vref_code_filled);

    // =========================================================================
    // Sequential: phy_rx_valvref_ctrl counter and midpoint computation
    //
    // Dual purpose:
    //   During sweep  (S3-S5): acts as the swept_code_r counter.
    //   After S6      (S6+)  : holds the computed best-Vref midpoint.
    // =========================================================================
    always @(posedge lclk or negedge rst_n) begin : VALVREF_CALC_APPLY_PROC
        if (!rst_n) begin
            phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE; // Reset to safe Vref.
        end
        else if (!is_ltsm_out_of_reset) begin
            phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE;
        end
        // Reset swept code on re-entry (allows reuse across MBTRAIN passes).
        else if (start_req_state) begin
            phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE;
        end
        // Increment swept code after each LOG_RESULT cycle.
        else if (log_result_state) begin
            if (phy_rx_valvref_ctrl != MAX_VAL_VREF_CODE) begin
                phy_rx_valvref_ctrl <= phy_rx_valvref_ctrl + 1;
            end
        end
        // Compute and apply the optimal Vref midpoint.
        // Spec eq.: vref_code = (min_vref_code + max_vref_code) / 2
        else if (calc_apply_state) begin
            if (vref_code_filled == 1'b1) begin
                phy_rx_valvref_ctrl <= ({1'b0, min_vref_code} + {1'b0, max_vref_code}) >> 1;
            end
            else begin
                phy_rx_valvref_ctrl <= '0; // No passing code: safe default.
            end
        end
    end

    // =========================================================================
    // Sequential: two-zone eye-map tracking (LOG_RESULT)
    //
    // Zone A (new contiguous pass zone starts):
    //   is_in_valid_region 0->1; save temp_min_vref = current code (zone_min_r).
    //   If first-ever pass (vref_code_filled==0): seed min/max_vref_code.
    // Zone B (extending the pass zone):
    //   If current zone is wider than the best recorded window:
    //   update min_vref_code (best_lo) and max_vref_code (best_hi).
    // Fail (hole):
    //   is_in_valid_region -> 0. Zone A restarts on the next passing code.
    //
    // Edge case: Force Zone A on MIN_VAL_VREF_CODE to reset stale zone tracking
    // from a prior calibration run.
    // =========================================================================
    always @(posedge lclk or negedge rst_n) begin : VALVREF_LOG_RESULT_PROC
        if (!rst_n) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <=   '0;
        end
        else if (!is_ltsm_out_of_reset) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <=   '0;
        end
        // Reset zone tracking at the start of each calibration run.
        else if (start_req_state) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'd0;
            temp_min_vref      <=   '0;
        end
        // Eye-map tracking.
        else if (log_result_state) begin
            if (d2c_val_pass) begin
                // ─── PASS ────────────────────────────────────────────────────
                // Zone A: entering a new contiguous pass zone.
                if (!is_in_valid_region || phy_rx_valvref_ctrl == MIN_VAL_VREF_CODE) begin
                    is_in_valid_region <= 1'b1;
                    temp_min_vref      <= phy_rx_valvref_ctrl; // save zone start (zone_min_r)
                    if (!vref_code_filled) begin
                        // Very first passing code: seed best window.
                        vref_code_filled <= 1'b1;
                        min_vref_code    <= phy_rx_valvref_ctrl; // best_lo
                        max_vref_code    <= phy_rx_valvref_ctrl; // best_hi
                    end
                end
                // Zone B: extending the current contiguous pass zone.
                else begin
                    if ((temp_vref_range) > (vref_range)) begin
                        min_vref_code <= temp_min_vref;       // best_lo = zone_min_r
                        max_vref_code <= phy_rx_valvref_ctrl; // best_hi = swept_code_r
                    end
                end
            end
            else begin
                // ─── FAIL (hole) ─────────────────────────────────────────────
                // Close the current pass zone. Zone A will restart on the next pass.
                is_in_valid_region <= 1'b0;
            end
        end
    end

endmodule
