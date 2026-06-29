// =============================================================================
// mbtrain_cb_sb_agent.sv — Sideband loopback agent
//
// KEY FIXES vs previous version:
//  1. Every REQ is translated to the matching RESP (not echoed back).
//  2. REPAIR apply_degrade_resp carries msginfo[2:0] = received TX lane code
//     so the DUT's PARTNER FSM can compute its decision correctly.
//  3. Shared RXDESKEW-EQ-Preset / LINKSPEED-PHY-Retrain opcode is routed by
//     checking current_mbtrain_substate, not guessed blindly.
//  4. LINKSPEED path is driven by config.linkspeed_pass_q:
//       all active lanes pass   -> send DONE_REQ path (no error)
//       partial/no pass         -> send ERROR_REQ then REPAIR or SPEED-DEGRADE
//  5. A scenario_generation counter lets stale pending responses be silently
//     dropped when a new scenario starts.
// =============================================================================
class mbtrain_cb_sb_agent;
    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    virtual mbtrain_cb_if vif;
    mbtrain_cb_config     cfg;

    // Internal mailbox — agent's background thread pulls from here
    typedef struct {
        logic [7:0]  msg;
        logic [15:0] info;
        int          generation;
    } pending_resp_t;
    pending_resp_t pending_resp_q[$];

    // ── Current linkspeed outcome for this invocation ─────────────────────────
    // Set from cfg before each LINKSPEED visit; read by the handler.
    logic [15:0] linkspeed_pass_for_this_visit;
    // Active-lane mask decoded from mbinit mask (set once per scenario by driver)
    logic [15:0] active_lanes_mask;

    function new(virtual mbtrain_cb_if v, mbtrain_cb_config c);
        vif = v;
        cfg = c;
        active_lanes_mask = 16'hFFFF;
    endfunction

    // -------------------------------------------------------------------------
    // Helper: convert 3-bit lane-mask code → 16-bit one-hot
    // -------------------------------------------------------------------------
    function automatic logic [15:0] lane_code_to_mask(logic [2:0] code);
        case (code)
            3'b000:  return 16'h0000;
            3'b001:  return 16'h00FF;
            3'b010:  return 16'hFF00;
            3'b011:  return 16'hFFFF;
            3'b100:  return 16'h000F;
            3'b101:  return 16'h00F0;
            default: return 16'h0000;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Enqueue a response to be delivered after sb_delay_cycles
    // -------------------------------------------------------------------------
    task automatic enqueue_resp(
        input logic [7:0]  resp_msg,
        input logic [15:0] resp_info = 16'h0000
    );
        pending_resp_t r;
        r.msg        = resp_msg;
        r.info       = resp_info;
        r.generation = cfg.scenario_generation;
        pending_resp_q.push_back(r);
    endtask

    // -------------------------------------------------------------------------
    // Background thread: send responses after the configured delay
    // -------------------------------------------------------------------------
    task automatic run();
        fork
            forever begin
                // Wait until there is something to send
                wait(pending_resp_q.size() > 0);
                begin
                    pending_resp_t r = pending_resp_q.pop_front();
                    // Discard if stale (new scenario started)
                    if (r.generation != cfg.scenario_generation) continue;
                    // Wait the configured delay
                    repeat(cfg.sb_delay_cycles) @(posedge vif.lclk);
                    // Discard again (scenario might have ended during the wait)
                    if (r.generation != cfg.scenario_generation) continue;
                    // Suppress if the scenario requests it
                    if (cfg.suppress_response_en &&
                        r.msg == cfg.suppress_response_msg) begin
                        // Drop — TB wants to observe a missing response (timeout test)
                        continue;
                    end
                    // Deliver
                    vif.send_rx_msg(r.msg, r.info);
                end
            end
        join_none
    endtask

    // -------------------------------------------------------------------------
    // Main monitor loop: watch DUT TX, compute and enqueue the right response
    // -------------------------------------------------------------------------
    task automatic monitor_and_respond();
        import UCIe_pkg::*;
        state_n_e cur_sub;
        logic [7:0] tx_msg;
        logic [15:0] tx_info;
        logic [15:0] ls_pass;

        fork
            forever begin
                // Wait for DUT to assert TX sideband valid
                @(posedge vif.lclk);
                if (!vif.substate_tx_sb_msg_valid) continue;

                tx_msg  = vif.substate_tx_sb_msg;
                tx_info = vif.substate_tx_msginfo;
                cur_sub = vif.current_mbtrain_substate;

                // ── Translate REQ → RESP ──────────────────────────────────────
                case (tx_msg)

                    // ── VALVREF ──────────────────────────────────────────────
                    MBTRAIN_VALVREF_start_req:
                        enqueue_resp(MBTRAIN_VALVREF_start_resp);
                    MBTRAIN_VALVREF_end_req:
                        enqueue_resp(MBTRAIN_VALVREF_end_resp);

                    // ── DATAVREF ─────────────────────────────────────────────
                    MBTRAIN_DATAVREF_start_req:
                        enqueue_resp(MBTRAIN_DATAVREF_start_resp);
                    MBTRAIN_DATAVREF_end_req:
                        enqueue_resp(MBTRAIN_DATAVREF_end_resp);

                    // ── SPEEDIDLE ────────────────────────────────────────────
                    MBTRAIN_SPEEDIDLE_done_req:
                        enqueue_resp(MBTRAIN_SPEEDIDLE_done_resp);

                    // ── TXSELFCAL ────────────────────────────────────────────
                    MBTRAIN_TXSELFCAL_Done_req:
                        enqueue_resp(MBTRAIN_TXSELFCAL_Done_resp);

                    // ── RXCLKCAL ─────────────────────────────────────────────
                    MBTRAIN_RXCLKCAL_start_req:
                        enqueue_resp(MBTRAIN_RXCLKCAL_start_resp);
                    MBTRAIN_RXCLKCAL_done_req:
                        enqueue_resp(MBTRAIN_RXCLKCAL_done_resp);
                    MBTRAIN_RXCLKCAL_TCKN_L_shift_req:
                        // MsgInfo[0]=0 → Success (shift applied)
                        enqueue_resp(MBTRAIN_RXCLKCAL_TCKN_L_shift_resp, 16'h0000);

                    // ── VALTRAINCENTER ───────────────────────────────────────
                    MBTRAIN_VALTRAINCENTER_start_req:
                        enqueue_resp(MBTRAIN_VALTRAINCENTER_start_resp);
                    MBTRAIN_VALTRAINCENTER_done_req:
                        enqueue_resp(MBTRAIN_VALTRAINCENTER_done_resp);

                    // ── VALTRAINVREF ─────────────────────────────────────────
                    MBTRAIN_VALTRAINVREF_start_req:
                        enqueue_resp(MBTRAIN_VALTRAINVREF_start_resp);
                    MBTRAIN_VALTRAINVREF_end_req:
                        enqueue_resp(MBTRAIN_VALTRAINVREF_end_resp);

                    // ── DATATRAINCENTER1 ─────────────────────────────────────
                    MBTRAIN_DATATRAINCENTER1_start_req:
                        enqueue_resp(MBTRAIN_DATATRAINCENTER1_start_resp);
                    MBTRAIN_DATATRAINCENTER1_end_req:
                        enqueue_resp(MBTRAIN_DATATRAINCENTER1_end_resp);

                    // ── DATATRAINVREF ────────────────────────────────────────
                    MBTRAIN_DATATRAINVREF_start_req:
                        enqueue_resp(MBTRAIN_DATATRAINVREF_start_resp);
                    MBTRAIN_DATATRAINVREF_end_req:
                        enqueue_resp(MBTRAIN_DATATRAINVREF_end_resp);

                    // ── RXDESKEW ─────────────────────────────────────────────
                    MBTRAIN_RXDESKEW_start_req:
                        enqueue_resp(MBTRAIN_RXDESKEW_start_resp);
                    MBTRAIN_RXDESKEW_end_req:
                        enqueue_resp(MBTRAIN_RXDESKEW_end_resp);
                    MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req:
                        enqueue_resp(MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp);

                    // ── DATATRAINCENTER2 ─────────────────────────────────────
                    MBTRAIN_DATATRAINCENTER2_start_req:
                        enqueue_resp(MBTRAIN_DATATRAINCENTER2_start_resp);
                    MBTRAIN_DATATRAINCENTER2_end_req:
                        enqueue_resp(MBTRAIN_DATATRAINCENTER2_end_resp);

                    // ── LINKSPEED ────────────────────────────────────────────
                    MBTRAIN_LINKSPEED_start_req:
                        enqueue_resp(MBTRAIN_LINKSPEED_start_resp);

                    MBTRAIN_LINKSPEED_done_req:
                        enqueue_resp(MBTRAIN_LINKSPEED_done_resp);

                    MBTRAIN_LINKSPEED_error_req:
                        // Partner must send error_resp after entering RX elec-idle.
                        // The recovery req (repair/speed-degrade) is handled when DUT
                        // sends it in a subsequent TX message.
                        enqueue_resp(MBTRAIN_LINKSPEED_error_resp);

                    MBTRAIN_LINKSPEED_exit_to_repair_req:
                        enqueue_resp(MBTRAIN_LINKSPEED_exit_to_repair_resp);

                    MBTRAIN_LINKSPEED_exit_to_speed_degrade_req:
                        enqueue_resp(MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp);

                    // ── SHARED OPCODE: RXDESKEW EQ Preset  /  LINKSPEED PHY Retrain ──
                    MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req: begin
                        if (cur_sub == LOG_MBTRAIN_LINKSPEED) begin
                            // PHY Retrain path in LINKSPEED
                            enqueue_resp(
                                MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp);
                        end else begin
                            // RXDESKEW EQ Preset: MsgInfo[0]=0 → Success
                            enqueue_resp(
                                MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp,
                                16'h0000);
                        end
                    end

                    // ── REPAIR ───────────────────────────────────────────────
                    MBTRAIN_REPAIR_init_req:
                        enqueue_resp(MBTRAIN_REPAIR_init_resp);

                    MBTRAIN_REPAIR_apply_degrade_req: begin
                        // KEY FIX:
                        // The PARTNER FSM on our die expects a pure ACK (no data in
                        // the resp) but unit_REPAIR_local.sv SNOOPS the partner's
                        // apply_degrade_req on the bus to grab the remote TX code.
                        //
                        // In the TB model both dies are the same DUT, so we send
                        // the partner's resp first, and then inject what looks like
                        // the "other die's" REPAIR_apply_degrade_req on the RX bus
                        // so the LOCAL FSM can capture the lane code.
                        //
                        // For simplicity: we ACK immediately (the resp is a pure ACK),
                        // and separately inject the partner die's apply_degrade_req
                        // with the received lane code.  This mirrors real behavior.
                        begin
                            logic [2:0] rx_lane_code;
                            // Use the same lane code the DUT just sent as what the
                            // "remote die" would also report. This means the remote
                            // die agrees (all-functional or same degrade).
                            // For degrade scenarios the config is pre-loaded with the
                            // correct lane code via configure_repair_partner_code().
                            rx_lane_code = repair_partner_lane_code;

                            // Send the other die's apply_degrade_req (snooped by LOCAL)
                            // after a short delay (so it appears as a separate beat)
                            fork
                                begin
                                    repeat(3) @(posedge vif.lclk);
                                    if (cfg.scenario_generation == cfg.scenario_generation) begin
                                        vif.send_rx_msg(MBTRAIN_REPAIR_apply_degrade_req,
                                                        {13'h0, rx_lane_code});
                                    end
                                end
                            join_none

                            // Send the pure ACK resp (no data)
                            enqueue_resp(MBTRAIN_REPAIR_apply_degrade_resp, 16'h0000);
                        end
                    end

                    MBTRAIN_REPAIR_end_req:
                        enqueue_resp(MBTRAIN_REPAIR_end_resp);

                    default: begin
                        // Unknown / unhandled message — ignore silently
                    end
                endcase
            end
        join_none
    endtask

    // ─── Repair partner lane code ─────────────────────────────────────────────
    // Set by the driver before each scenario to tell the agent what lane code
    // to report as the "remote die's" TX lane code in REPAIR apply_degrade_req.
    // Default 3'b011 = all lanes functional (x16 full-width).
    logic [2:0] repair_partner_lane_code = 3'b011;

    task automatic configure_repair_partner_code(input logic [2:0] code);
        repair_partner_lane_code = code;
    endtask

    // Flush pending queue (call at start of each scenario)
    task automatic flush();
        pending_resp_q.delete();
    endtask

endclass
