// ====================================================================================================
// unit_MBTRAIN_lane_sel.sv — MBTRAIN Substates Lane Control Selector
//
// This module decodes lane configurations combinationally for all MBTRAIN substates.
// It maps the current substate, speed/clock configurations, and dynamic status flags
// from RXCLKCAL and LINKSPEED to drive mainband TX/RX lane selectors.
//
// TX lane selector encoding (2-bit):
//   2'b00 = Held Low (differential low / simultaneous low)
//   2'b01 = Active (forwarded clock or training pattern)
//   2'b10 = Hi-Z / Tri-stated
//   2'b11 = Electrical Idle
//
// RX lane selector encoding (1-bit):
//   1'b0  = Receiver disabled
//   1'b1  = Receiver enabled
//
// ─── SUBSTATE CLOCK TX RULES ──────────────────────────────────────────────────────────────────────
// • VALVREF, DATAVREF, SPEEDIDLE:
//     Clock TX is always ACTIVE (2'b01). The partner FSM of our die drives the forwarded
//     clock unconditionally during these substates regardless of speed (the die always acts as
//     the clock transmitter so the other die's LOCAL FSM can perform its calibration).
//
// • VALTRAINCENTER, VALTRAINVREF, DATATRAINCENTER1, DATATRAINVREF, RXDESKEW, DATATRAINCENTER2,
//   LINKSPEED (normal):
//     Clock TX is speed-conditional:
//       (is_high_speed || is_continuous_clk_mode) → 2'b01 (forwarded clock)
//       otherwise                                  → 2'b00 (held differential low)
//
// • SPEEDIDLE: Always ACTIVE (2'b01) — partner drives forwarded clock during speed settling.
//
// • TXSELFCAL: All TX tri-stated (2'b10). Both clock and data lines are disconnected.
//
// • RXCLKCAL: Dynamic — controlled by rx_clk_active / tx_clk_active flags from wrapper_RXCLKCAL.
//
// • LINKSPEED error path: lcl_tx_elec_idle → all TX Electrical Idle (2'b11).
//
// • REPAIR: Clock TX is HELD LOW (2'b00). Spec §4.5.3.4.13: "Clock Transmitters are held
//     differential low (for differential clocking) or simultaneous low (for Quadrature clocking)."
// ====================================================================================================

module unit_MBTRAIN_lane_sel (
        input  ltsm_state_n_pkg::state_n_e state_n_0,
        input  logic                       is_high_speed,
        input  logic                       is_continuous_clk_mode,
        input  logic                       rx_clk_active,
        input  logic                       tx_clk_active,
        input  logic                       lcl_tx_elec_idle,
        input  logic                       ptr_rx_elec_idle,

        output logic [1:0]                 mb_tx_clk_lane_sel,
        output logic [1:0]                 mb_tx_data_lane_sel,
        output logic [1:0]                 mb_tx_val_lane_sel,
        output logic [1:0]                 mb_tx_trk_lane_sel,

        output logic                       mb_rx_clk_lane_sel,
        output logic                       mb_rx_data_lane_sel,
        output logic                       mb_rx_val_lane_sel,
        output logic                       mb_rx_trk_lane_sel
    );

    import ltsm_state_n_pkg::*;

    always_comb begin
        // Default postures (all low / disabled)
        mb_tx_clk_lane_sel  = 2'b00;
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b00;
        mb_tx_trk_lane_sel  = 2'b00;

        mb_rx_clk_lane_sel  = 1'b0;
        mb_rx_data_lane_sel = 1'b0;
        mb_rx_val_lane_sel  = 1'b0;
        mb_rx_trk_lane_sel  = 1'b0;

        case (state_n_0)

            // ─────────────────────────────────────────────────────────────────────────
            // VALVREF (§4.5.3.4.1)
            //   • Partner of our die drives the forwarded clock
            //     and the VALTRAIN pattern on the Valid lane.
            //   • Local of our die receives: CLK RX and VAL RX enabled.
            //   • Data and Track TX/RX are held low / disabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_VALVREF: begin
                mb_tx_clk_lane_sel  = 2'b00;   // Clock Transmitters are held differential low (for differential clocking) or simultaneous low (for Quadrature clocking)
                mb_tx_data_lane_sel = 2'b00;   // Held low
                mb_tx_val_lane_sel  = 2'b01;   // Partner drives VALTRAIN pattern
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b0;    // Data RX disabled
                mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled (local samples VALTRAIN)
                mb_rx_trk_lane_sel  = 1'b0;    // Track RX permitted to be disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // DATAVREF (§4.5.3.4.2)
            //   • Partner drives forwarded clock and LFSR data
            //     via sweep engine (partner_sweep_en overrides data TX during sweep).
            //   • Local samples: CLK, DATA, and VAL RX all enabled.
            //   • Track TX/RX are held low / disabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_DATAVREF: begin
                mb_tx_clk_lane_sel  = 2'b00;   // Clock Transmitters are held differential low (for differential clocking) or simultaneous low (for Quadrature clocking)
                mb_tx_data_lane_sel = 2'b00;   // Held low (sweep engine overrides via partner_sweep_en)
                mb_tx_val_lane_sel  = 2'b00;   // Held low
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b1;    // Data RX enabled
                mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled
                mb_rx_trk_lane_sel  = 1'b0;    // Track RX disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // SPEEDIDLE (§4.5.3.4.3)
            //   • Clock TX is kept differential/simultaneous Low.
            //   • Data, Valid, and Track TX are held low.
            //   • Only Clock RX is enabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_SPEEDIDLE: begin
                mb_tx_clk_lane_sel  = 2'b00;   // Forwarded clock active during speed transition
                mb_tx_data_lane_sel = 2'b00;   // Held low
                mb_tx_val_lane_sel  = 2'b00;   // Held low
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b0;    // Disabled
                mb_rx_val_lane_sel  = 1'b0;    // Disabled
                mb_rx_trk_lane_sel  = 1'b0;    // Disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // TXSELFCAL (§4.5.3.4.4)
            //   • All TX lanes (Clock, Data, Valid, Track) are tri-stated (Hi-Z).
            //   • All RX lanes are permitted to be disabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_TXSELFCAL: begin
                mb_tx_clk_lane_sel  = 2'b10;   // Hi-Z / Tri-stated
                mb_tx_data_lane_sel = 2'b10;   // Hi-Z / Tri-stated
                mb_tx_val_lane_sel  = 2'b10;   // Hi-Z / Tri-stated
                mb_tx_trk_lane_sel  = 2'b10;   // Hi-Z / Tri-stated

                mb_rx_clk_lane_sel  = 1'b0;    // Permitted to be disabled
                mb_rx_data_lane_sel = 1'b0;    // Permitted to be disabled
                mb_rx_val_lane_sel  = 1'b0;    // Permitted to be disabled
                mb_rx_trk_lane_sel  = 1'b0;    // Permitted to be disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // RXCLKCAL (§4.5.3.4.5)
            //   Dynamic based on flags from wrapper_RXCLKCAL:
            //
            //   • rx_clk_active=1:  Our LOCAL FSM is receiving the remote clock.
            //       RX CLK and TRK enabled, TX all held low.
            //
            //   • tx_clk_active=1:  Our PARTNER FSM is transmitting the forwarded
            //       clock and track to the remote LOCAL.
            //       TX CLK and TRK active, RX all disabled.
            //
            //   • Default (neither active yet): Standard low-speed default posture.
            //       CLK TX conditional on speed; CLK RX enabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_RXCLKCAL: begin
                // Our LOCAL FSM is calibrating its RX clock path
                if (rx_clk_active) begin
                    mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled for calibration
                    mb_rx_val_lane_sel  = 1'b0;    // Data/Val RX disabled (permitted)
                    mb_rx_data_lane_sel = 1'b0;
                    mb_rx_trk_lane_sel  = 1'b1;    // Track RX enabled for clock-to-track cal
                end else begin
                    // Default posture: neither active yet
                    mb_rx_clk_lane_sel  = 1'b1;    // CLK RX enabled (ready to lock)
                    mb_rx_val_lane_sel  = 1'b0;
                    mb_rx_data_lane_sel = 1'b0;
                    mb_rx_trk_lane_sel  = 1'b0;
                end

                // Our PARTNER FSM is sending the forwarded clock and track
                if (tx_clk_active) begin
                    mb_tx_clk_lane_sel  = 2'b01;   // TX CLK active (forwarded clock)
                    mb_tx_val_lane_sel  = 2'b00;   // Data/Val TX held low
                    mb_tx_data_lane_sel = 2'b00;
                    mb_tx_trk_lane_sel  = 2'b01;   // TX TRK active (forwarded track)

                end else begin
                    mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;
                    mb_tx_val_lane_sel  = 2'b00;
                    mb_tx_data_lane_sel = 2'b00;
                    mb_tx_trk_lane_sel  = 2'b00;
                end
            end

            // ─────────────────────────────────────────────────────────────────────────
            // VALTRAINCENTER (§4.5.3.4.6)
            //   • Clock TX is speed-conditional (same rule as other high-speed substates).
            //   • Valid TX active (partner drives VALTRAIN for valid-to-clock centering).
            //   • Data and Track TX held low.
            //   • CLK and VAL RX enabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_VALTRAINCENTER: begin
                mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;
                mb_tx_data_lane_sel = 2'b00;   // Held low
                mb_tx_val_lane_sel  = 2'b01;   // Partner drives VALTRAIN pattern
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b0;    // Data RX disabled
                mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled (local samples VALTRAIN)
                mb_rx_trk_lane_sel  = 1'b0;    // Track RX disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // VALTRAINVREF (§4.5.3.4.7)
            //   • Valid TX active (partner drives VALTRAIN pattern).
            //   • Data and Track TX held low.
            //   • CLK and VAL RX enabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_VALTRAINVREF: begin
                mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00; // Forwarded clock active
                mb_tx_data_lane_sel = 2'b00;   // Held low
                mb_tx_val_lane_sel  = 2'b01;   // Partner drives VALTRAIN pattern
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b0;    // Data RX disabled
                mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled
                mb_rx_trk_lane_sel  = 1'b0;    // Track RX disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // DATATRAINCENTER1, DATATRAINVREF, RXDESKEW, and DATATRAINCENTER2
            //   • Clock TX is speed-conditional.
            //   • Data and Valid TX held low (sweep engine overrides during D2C sweeps).
            //   • Track TX held low.
            //   • CLK, DATA, and VAL RX enabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_DATATRAINCENTER1, LOG_MBTRAIN_DATATRAINVREF, LOG_MBTRAIN_RXDESKEW, LOG_MBTRAIN_DATATRAINCENTER2: begin
                mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;
                mb_tx_data_lane_sel = 2'b00;   // Held low (sweep engine active)
                mb_tx_val_lane_sel  = 2'b00;   // Held low
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b1;    // Data RX enabled
                mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled
                mb_rx_trk_lane_sel  = 1'b0;    // Track RX disabled
            end

            // ─────────────────────────────────────────────────────────────────────────
            // LINKSPEED (§4.5.3.4.12)
            //   • TX: Dynamic based on lcl_tx_elec_idle flag.
            //       If set (error req sent): All TX → Electrical Idle (2'b11).
            //       Else: Clock TX speed-conditional; Data/Val/Track TX held low.
            //   • RX: Dynamic based on ptr_rx_elec_idle flag.
            //       If set (partner's RX disabled after receiving our error req):
            //           All RX → disabled.
            //       Else: CLK, DATA, VAL RX enabled; Track RX disabled.
            //   Note: TX and RX conditions are evaluated independently.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_LINKSPEED: begin
                if (lcl_tx_elec_idle) begin
                    // Local TX entered electrical idle after sending error_req
                    mb_tx_clk_lane_sel  = 2'b10;   // Electrical Idle (We consider the electrical idle state = Low state)
                    mb_tx_data_lane_sel = 2'b10;   // Electrical Idle (We consider the electrical idle state = Low state)
                    mb_tx_val_lane_sel  = 2'b10;   // Electrical Idle (We consider the electrical idle state = Low state)
                    mb_tx_trk_lane_sel  = 2'b10;   // Electrical Idle (We consider the electrical idle state = Low state)
                end else begin
                    // Normal TX posture during LINKSPEED
                    mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;
                    mb_tx_data_lane_sel = 2'b00;   // Held low
                    mb_tx_val_lane_sel  = 2'b00;   // Held low
                    mb_tx_trk_lane_sel  = 2'b00;   // Track TX held low (spec §4.5.3.4.12)
                end

                if (ptr_rx_elec_idle) begin
                    // Partner's RX disabled after receiving our error_req
                    mb_rx_clk_lane_sel  = 1'b0;    // Disabled
                    mb_rx_data_lane_sel = 1'b0;    // Disabled
                    mb_rx_val_lane_sel  = 1'b0;    // Disabled
                    mb_rx_trk_lane_sel  = 1'b0;    // Disabled
                end else begin
                    // Normal RX posture during LINKSPEED
                    mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                    mb_rx_data_lane_sel = 1'b1;    // Data RX enabled
                    mb_rx_val_lane_sel  = 1'b1;    // Valid RX enabled
                    mb_rx_trk_lane_sel  = 1'b0;    // Track RX disabled
                end
            end

            // ─────────────────────────────────────────────────────────────────────────
            // REPAIR (§4.5.3.4.13)
            //   • Clock TX held differential low (2'b00) — spec explicit.
            //   • Track, Data, and Valid TX held low.
            //   • Clock RX enabled; all other RX disabled.
            // ─────────────────────────────────────────────────────────────────────────
            LOG_MBTRAIN_REPAIR: begin
                mb_tx_clk_lane_sel  = 2'b00;   // Held differential low (spec §4.5.3.4.13)
                mb_tx_data_lane_sel = 2'b00;   // Held low
                mb_tx_val_lane_sel  = 2'b00;   // Held low
                mb_tx_trk_lane_sel  = 2'b00;   // Held low

                mb_rx_clk_lane_sel  = 1'b1;    // Clock RX enabled
                mb_rx_data_lane_sel = 1'b0;    // Disabled
                mb_rx_val_lane_sel  = 1'b0;    // Disabled
                mb_rx_trk_lane_sel  = 1'b0;    // Disabled
            end

            default: begin
                // All outputs remain at default (all 0 / disabled)
            end
        endcase
    end

endmodule
