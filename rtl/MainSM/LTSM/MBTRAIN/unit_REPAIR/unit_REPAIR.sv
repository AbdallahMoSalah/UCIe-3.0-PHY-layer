// =============================================================================
// Module  : unit_REPAIR
// Purpose : MBTRAIN.REPAIR sub-state FSM.
//           Handles lane repair / lane degradation after a LINKSPEED failure:
//
//           Two exit paths depending on `linkspeed_fail_flag`:
//             A) REPAIR path  (linkspeed_fail_flag = 0, normal repair request):
//                  INIT_REQ → wait for APPLY_REPAIR_RESP → END_REQ/RESP → done
//             B) DEGRADE path (linkspeed_fail_flag = 1, cannot repair, must degrade lanes):
//                  INIT_REQ → APPLY_DEGRADE_REQ/RESP → END_REQ/RESP → done
//
//           In both paths the FSM starts with a SB init handshake and ends with
//           a SB end handshake.  After END_RESP the module asserts `repair_done`
//           and `repair_req` so the MBTRAIN controller can advance.
//
//           Fatal conditions (8ms timeout, partner TRAINERROR) → TO_TRAINERROR.
//
// UCIe 3.0 Spec Reference: Section 4.5.3.4.13 – MBTRAIN.REPAIR
//
// SB messages used:
//   MBTRAIN_REPAIR_init_req          (B5h/1Bh) – start handshake
//   MBTRAIN_REPAIR_init_resp         (BAh/1Bh) – start response
//   MBTRAIN_REPAIR_apply_repair_req  (B5h/1Ch) – partner applies repair (Tx message)
//   MBTRAIN_REPAIR_apply_repair_resp (BAh/1Ch) – receive repair applied
//   MBTRAIN_REPAIR_apply_degrade_req (B5h/1Eh) – send degrade lane map
//   MBTRAIN_REPAIR_apply_degrade_resp(BAh/1Eh) – partner acks degrade
//   MBTRAIN_REPAIR_end_req           (B5h/1Dh) – end handshake
//   MBTRAIN_REPAIR_end_resp          (BAh/1Dh) – end response
//
// FSM States:
//   RP_IDLE              (S0)  Wait for repair_en assertion.
//   RP_INIT_REQ          (S1)  Send & receive: init_req.
//   RP_INIT_RESP         (S2)  Send & receive: init_resp → branch on linkspeed_fail_flag.
//   RP_APPLY_REPAIR_REQ  (S3)  Wait for partner's apply_repair_req (partner Tx-drives repair address).
//   RP_APPLY_DEGRADE_REQ (S4)  Send apply_degrade_req / receive apply_degrade_req.
//   RP_APPLY_DEGRADE_RESP(S5)  Send apply_degrade_resp / receive apply_degrade_resp.
//   RP_END_REQ           (S6)  Send & receive: end_req.
//   RP_END_RESP          (S7)  Send & receive: end_resp → done.
//   TO_DONE              (S8)  Assert repair_done + repair_req for 1 cycle then idle.
//   TO_TRAINERROR        (S9)  Fatal: timeout or partner TRAINERROR.
// =============================================================================
module unit_REPAIR (
        internal_ltsm_if.repair_mp rp_if
    );
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_REPAIR_init_req          ;
    import UCIe_pkg::MBTRAIN_REPAIR_init_resp         ;
    import UCIe_pkg::MBTRAIN_REPAIR_apply_repair_req  ;
    import UCIe_pkg::MBTRAIN_REPAIR_apply_repair_resp ;
    import UCIe_pkg::MBTRAIN_REPAIR_apply_degrade_req ;
    import UCIe_pkg::MBTRAIN_REPAIR_apply_degrade_resp;
    import UCIe_pkg::MBTRAIN_REPAIR_end_req           ;
    import UCIe_pkg::MBTRAIN_REPAIR_end_resp          ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING;
    // =========================================================================
    // State encoding
    // =========================================================================
    localparam RP_IDLE              = 4'h0, // (S0)
               RP_INIT_REQ          = 4'h1, // (S1) init handshake – request
               RP_INIT_RESP         = 4'h2, // (S2) init handshake – response
               RP_APPLY_REPAIR_REQ  = 4'h3, // (S3) wait for partner apply_repair_req (REPAIR path)
               RP_APPLY_DEGRADE_REQ = 4'h4, // (S4) send apply_degrade_req (DEGRADE path)
               RP_APPLY_DEGRADE_RESP= 4'h5, // (S5) send/recv apply_degrade_resp
               RP_END_REQ           = 4'h6, // (S6) end handshake – request
               RP_END_RESP          = 4'h7, // (S7) end handshake – response
               TO_DONE              = 4'h8, // (S8) success exit
               TO_TRAINERROR        = 4'h9; // (S9) fatal exit
    reg [3:0] current_state, next_state;
    // Glitch-guard: suppress tx_sb_msg_valid on the cycle of a state transition.
    wire data_incoherence = (current_state != next_state);
    // =========================================================================
    // Data-path registers
    // =========================================================================
    // Latch the linkspeed_fail_flag at INIT_REQ so the branch is stable.
    reg degrade_r;  // 1 = degrade path, 0 = repair path
    // =========================================================================
    // (Block 1) Sequential: current state register
    // =========================================================================
    always @(posedge rp_if.lclk or negedge rp_if.rst_n) begin
        if (!rp_if.rst_n) begin
            current_state  <= RP_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end
    // =========================================================================
    // (Block 2) Combinational: next-state logic
    // =========================================================================
    always @(*) begin
        // Global overrides: fatal conditions take priority over normal flow.
        if (rp_if.timeout_8ms_occured |
                (rp_if.rx_sb_msg == TRAINERROR_Entry_req && rp_if.rx_sb_msg_valid)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                // (S0) Wait for enable
                RP_IDLE: begin
                    next_state = rp_if.repair_en ? RP_INIT_REQ : RP_IDLE;
                end
                // (S1) Send & receive: init_req
                RP_INIT_REQ: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_init_req &&
                                  rp_if.rx_sb_msg_valid) ? RP_INIT_RESP : RP_INIT_REQ;
                end
                // (S2) Send & receive: init_resp → branch on degrade_r
                RP_INIT_RESP: begin
                    if (rp_if.rx_sb_msg == MBTRAIN_REPAIR_init_resp && rp_if.rx_sb_msg_valid)
                        next_state = degrade_r ? RP_APPLY_DEGRADE_REQ : RP_APPLY_REPAIR_REQ;
                    else
                        next_state = RP_INIT_RESP;
                end
                // (S3) REPAIR path: send apply_repair_req (with lane address) and wait
                //      for partner's apply_repair_req echo back.
                RP_APPLY_REPAIR_REQ: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_repair_req &&
                                  rp_if.rx_sb_msg_valid) ? RP_END_REQ : RP_APPLY_REPAIR_REQ;
                end
                // (S4) DEGRADE path: send & receive apply_degrade_req
                RP_APPLY_DEGRADE_REQ: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req &&
                                  rp_if.rx_sb_msg_valid) ? RP_APPLY_DEGRADE_RESP : RP_APPLY_DEGRADE_REQ;
                end
                // (S5) DEGRADE path: send & receive apply_degrade_resp
                RP_APPLY_DEGRADE_RESP: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_resp &&
                                  rp_if.rx_sb_msg_valid) ? RP_END_REQ : RP_APPLY_DEGRADE_RESP;
                end
                // (S6) End handshake – request
                RP_END_REQ: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_end_req &&
                                  rp_if.rx_sb_msg_valid) ? RP_END_RESP : RP_END_REQ;
                end
                // (S7) End handshake – response → done
                RP_END_RESP: begin
                    next_state = (rp_if.rx_sb_msg == MBTRAIN_REPAIR_end_resp &&
                                  rp_if.rx_sb_msg_valid) ? TO_DONE : RP_END_RESP;
                end
                // (S8-S9) Terminal states: hold until enable de-asserts, then idle.
                TO_DONE, TO_TRAINERROR: begin
                    next_state = rp_if.repair_en ? current_state : RP_IDLE;
                end
                default: next_state = rp_if.repair_en ? TO_TRAINERROR : RP_IDLE;
            endcase
        end
    end
    // =========================================================================
    // (Block 3) Combinational: output logic
    // =========================================================================
    always @(*) begin
        // ── Safe defaults (prevent latches) ──────────────────────────────────
        rp_if.repair_done            = 1'b0;
        rp_if.repair_req             = 1'b0;
        rp_if.trainerror_req         = 1'b0;
        rp_if.timeout_timer_en       = 1'b1;
        rp_if.analog_settle_timer_en = 1'b0;
        // MB lane defaults – keep all lanes active during repair
        rp_if.mb_tx_clk_lane_sel  = 2'b01; // Clock lane active
        rp_if.mb_tx_data_lane_sel = 2'b01; // Data lanes active
        rp_if.mb_tx_val_lane_sel  = 2'b01; // Valid lane active
        rp_if.mb_tx_trk_lane_sel  = 2'b00; // Track lane low
        rp_if.mb_rx_clk_lane_sel  = 1'b1 ;
        rp_if.mb_rx_data_lane_sel = 1'b1 ;
        rp_if.mb_rx_val_lane_sel  = 1'b1 ;
        rp_if.mb_rx_trk_lane_sel  = 1'b0 ;
        // SB defaults
        rp_if.tx_sb_msg_valid = 1'b0;
        rp_if.tx_sb_msg       = NOTHING;
        rp_if.tx_msginfo      = 16'h0;
        rp_if.tx_data_field   = 64'h0;
        case (current_state)
            RP_IDLE: begin
                rp_if.timeout_timer_en = 1'b0;
            end
            // (S1) Both sides send init_req simultaneously
            RP_INIT_REQ: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_init_req;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S2) Both sides send init_resp simultaneously
            RP_INIT_RESP: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_init_resp;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S3) REPAIR path: drive apply_repair_req (lane address in data_field)
            //      and wait for the partner's echo of apply_repair_req.
            RP_APPLY_REPAIR_REQ: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_apply_repair_req;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'hFFFF_FFFF_FFFF_FFFF; // No repair (FFh per lane)
            end
            // (S4) DEGRADE path: send apply_degrade_req (lane-map in msginfo[2:0])
            RP_APPLY_DEGRADE_REQ: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_req;
                // MsgInfo[2:0]: Standard Package logical lane map (all-zero = no remap for sim)
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S5) DEGRADE path: send apply_degrade_resp
            RP_APPLY_DEGRADE_RESP: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_resp;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S6) Both sides send end_req simultaneously
            RP_END_REQ: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_end_req;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S7) Both sides send end_resp simultaneously
            RP_END_RESP: begin
                rp_if.tx_sb_msg_valid = !data_incoherence;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_end_resp;
                rp_if.tx_msginfo      = 16'h0;
                rp_if.tx_data_field   = 64'h0;
            end
            // (S8) Done: assert repair_done and repair_req to notify MBTRAIN ctrl
            TO_DONE: begin
                rp_if.repair_done      = 1'b1;
                rp_if.repair_req       = 1'b1;
                rp_if.timeout_timer_en = 1'b0;
            end
            // (S9) Fatal
            TO_TRAINERROR: begin
                rp_if.trainerror_req   = 1'b1;
                rp_if.repair_done      = 1'b1;
                rp_if.timeout_timer_en = 1'b0;
            end
            default: begin end
        endcase
    end
    // =========================================================================
    // (Block 4) Sequential: data-path — latch degrade flag at INIT_REQ
    // =========================================================================
    always @(posedge rp_if.lclk or negedge rp_if.rst_n) begin
        if (!rp_if.rst_n) begin
            degrade_r <= 1'b0;
        end else begin
            case (current_state)
                // Capture linkspeed_fail_flag at the start of the sequence.
                // If it is set → we must degrade lanes, not repair.
                RP_INIT_REQ: begin
                    degrade_r <= rp_if.linkspeed_fail_flag;
                end
                default: begin end
            endcase
        end
    end
endmodule
