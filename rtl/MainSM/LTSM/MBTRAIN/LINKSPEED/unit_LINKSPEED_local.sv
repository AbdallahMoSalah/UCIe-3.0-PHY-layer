// ====================================================================================================
// Module  : unit_LINKSPEED_local
// Purpose : MBTRAIN.LINKSPEED sub-state LOCAL (Initiator) FSM (UCIe 3.0 Spec §4.5.3.4.12).
//
// ─── ARCHITECTURE: STRICTLY CROSS-DIE, NO ROLE B ─────────────────────────────────────────────────
// Per the decoupled Local/Partner architecture (see hierarchy.md §6):
//   "All SB communication is strictly cross-die — zero SB message exchange between modules
//    within the same die."
//
// This module (LOCAL) communicates ONLY with the PARTNER module on the REMOTE die.
// The PARTNER module on OUR die handles all responses to the REMOTE LOCAL's requests.
//
// Therefore:
//   ✅ LOCAL sends {exit to phy retrain REQ}   → received by REMOTE PARTNER
//   ✅ LOCAL waits for {exit to phy retrain RESP} ← sent by REMOTE PARTNER
//   ✅ PARTNER (on our die) receives {exit to phy retrain REQ} from REMOTE LOCAL
//   ✅ PARTNER (on our die) sends {exit to phy retrain RESP}  → REMOTE LOCAL
//
// LOCAL NEVER sends {exit to phy retrain RESP}. That is PARTNER's sole job.
// There is no "Role B" in this module. The old P3 snoop override was architecturally wrong.
//
// ─── SIMULTANEOUS PHY RETRAIN (both dies detect params_changed) ──────────────────────────────────
// Because LOCAL and PARTNER are decoupled and operate on independent virtual channels:
//   - Our LOCAL sends REQ  → Remote PARTNER responds with RESP  → Our LOCAL exits PHYRETRAIN ✓
//   - Remote LOCAL sends REQ → Our PARTNER responds with RESP   → Remote LOCAL exits PHYRETRAIN ✓
// Both channels operate completely independently — no deadlock is possible.
//
// ─── ROLE (LOCAL = INITIATOR ONLY) ───────────────────────────────────────────────────────────────
// 1. Sends {start req}  → waits for {start resp}
// 2. Runs TX-initiated D2C point test via unit_D2C_sweep (single point test, code=0).
// 3. Evaluates per-lane pass/fail results masked by active_rx_lanes.
// 4. SUCCESS PATH (no errors):
//      a. If PHY_IN_RETRAIN AND params_changed    → sends {exit to phy retrain REQ}, waits RESP → PHYRETRAIN
//      b. If PHY_IN_RETRAIN AND !params_changed   → proceeds to {done req}
//      c. If NOT PHY_IN_RETRAIN                   → sends {done req}, waits {done resp} → LINKINIT
// 5. ERROR PATH (errors detected):
//      → TX Electrical Idle, sends {error req}, waits {error resp}
//      → Repair or Speed-degrade decision
//
// ─── SB MESSAGES TABLE (LOCAL = INITIATOR) ───────────────────────────────────────────────────────
// +----------------------------------------------------+-----------+-------------------------------+
// | Message Name                                       | Direction | MsgInfo & Data Field Details  |
// +----------------------------------------------------+-----------+-------------------------------+
// | {MBTRAIN.LINKSPEED start req}                      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED start resp}                     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED done req}                       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED done resp}                      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED error req}                      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED error resp}                     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED exit to repair req}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED exit to repair resp}            | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED exit to speed degrade req}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED exit to speed degrade resp}     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// | {MBTRAIN.LINKSPEED exit to phy retrain req}        | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0   |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           | (shared opcode with RXDESKEW   |
// |      MBTRAIN_RXDESKEW_EQ_Preset_req)               |           |  EQ Preset req; disambiguated  |
// |                                                    |           |  by LTSM state context)        |
// | {MBTRAIN.LINKSPEED exit to phy retrain resp}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0   |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           | (shared opcode with RXDESKEW   |
// |      MBTRAIN_RXDESKEW_EQ_Preset_resp)              |           |  EQ Preset resp; disambiguated)|
// | {TRAINERROR entry req}                             | In  (RX)  | → TO_TRAINERROR immediately    |
// +----------------------------------------------------+-----------+-------------------------------+
// ====================================================================================================

module unit_LINKSPEED_local (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk,                 // LTSM clock domain (1–2 GHz). All transitions synchronous.
        input  logic        rst_n,                // 0: Asynchronous reset to IDLE; 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        linkspeed_en,         // 1: Enable LINKSPEED substate; 0: Return to IDLE.
        input  logic        soft_rst_n,           // 1: Normal operation; 0: Soft-reset (return to IDLE).

        output logic        linkspeed_done,       // 1: Sub-state completed (held until linkspeed_en deasserts).
        output logic        speedidle_req,        // 1: Request transition to MBTRAIN.SPEEDIDLE.
        output logic        repair_req,           // 1: Request transition to MBTRAIN.REPAIR.
        output logic        linkinit_req,         // 1: Request transition to LINKINIT.
        output logic        phyretrain_req,       // 1: Request transition to PHYRETRAIN.

        //=====================================//
        // Lane & Width Degrade Inputs:        //
        //=====================================//
        input  logic [15:0] active_rx_lanes,           // From unit_negotiated_lanes (in wrapper).
        input  logic        width_degrade_feasible,    // 1: A valid degraded lane map is feasible (from unit_negotiated_lanes in wrapper).

        //=====================================//
        // PHY Retrain Inputs:                 //
        //=====================================//
        // PHY_IN_RETRAIN: set by LTSM when the link entered MBTRAIN via PHY retrain path.
        // params_changed: set when Runtime Link Test Control register differs from the
        //   value at the previous PHYRETRAIN entry. LOCAL evaluates this after the D2C test.
        //   If both are set → LOCAL is the initiator of {exit to phy retrain req}.
        input  logic        PHY_IN_RETRAIN,            // 1 = LTSM entered via PHY retrain path.
        input  logic        params_changed,            // 1 = Runtime Link Test Control reg changed.
        // PHY_IN_RETRAIN_rst: 1-cycle active-high pulse that instructs the LTSM to clear the
        //   PHY_IN_RETRAIN flag. Fired in the RECOVERY_DECISION state (immediately after
        //   {MBTRAIN.LINKSPEED error resp} is received). Spec §4.5.3.4.12:
        //   "after the {MBTRAIN.LINKSPEED error resp} sideband message is received, the
        //    PHY_IN_RETRAIN flag is cleared."
        //   Duration: exactly 1 lclk (Moore output of RECOVERY_DECISION — a 1-cycle state).
        //   RECOVERY_DECISION has zero SB TX/RX activity, so the pulse is isolated from
        //   any sideband traffic (satisfies the user requirement: ≥1 lclk, < SB msg gap).
        output logic        PHY_IN_RETRAIN_rst,        // 1-cycle pulse: clear PHY_IN_RETRAIN in LTSM.
        output logic        busy_bit_rst      ,        // 1-cycle pulse: clear busy_bit in LTSM.

        //=====================================//
        // Result Output:                      //
        //=====================================//
        output logic [15:0] linkspeed_success_lanes,   // Per-lane D2C pass mask. Used by REPAIR.

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        // TX encoding: 2'b00=Low / 2'b01=Active / 2'b10=Hi-Z / 2'b11=Elec Idle
        // RX encoding: 1=Enabled / 0=Disabled
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        //=====================================//
        // Speed and Clock Mode:               //
        //=====================================//
        input  logic        is_high_speed,          // 1 = operating speed > 32 GT/s.
        input  logic        is_continuous_clk_mode, // 1 = continuous clock mode advertised by partner.

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en,              // To unit_D2C_sweep: 1 = run/sustain sweep.
        input  logic [15:0] d2c_perlane_pass,      // From D2C: per-lane pass result (valid when sweep_done).
        input  logic        sweep_done,            // From D2C: 1 = point test complete.

        //=====================================//
        // Sideband TX Signals:                //
        //=====================================//
        // Feed into unit_sb_tx_arbiter (instantiated in wrapper) — NOT directly to SB bus.
        output logic        tx_sb_msg_valid,       // 1 = valid message this cycle (1-cycle pulse).
        output logic [7:0]  tx_sb_msg,             // Message opcode.
        output logic [15:0] tx_msginfo,            // MsgInfo payload (always 16'h0 for LINKSPEED).
        output logic [63:0] tx_data_field,         // Data payload (always 64'h0 for LINKSPEED).

        //=====================================//
        // Sideband RX Signals:                //
        //=====================================//
        // Connected to the physical RX SB bus (same for both LOCAL and PARTNER FSMs).
        input  logic        rx_sb_msg_valid,       // 1 = valid RX message arrived this cycle.
        input  logic [7:0]  rx_sb_msg,             // Received opcode.
        input  logic [15:0] rx_msginfo,            // Received MsgInfo.   NOTE: all LINKSPEED messages carry MsgInfo=16'h0; port is
        //   wired but not consumed by this FSM. Retained for interface
        //   completeness (PARTNER FSM shares the same RX SB bus).
        input  logic [63:0] rx_data_field          // Received 64-bit data. NOTE: same as rx_msginfo — always 64'h0.
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Combinational D2C Result Evaluation
    // ─────────────────────────────────────────────────────────────────────────
    // Computed from d2c_perlane_pass (stable after sweep_done) and active_rx_lanes.
    // Used to latch decision registers in EVAL_RESULT (1-cycle state).
    // =========================================================================
    logic [15:0] final_perlane_pass_w;
    logic        error_detected_w;

    assign final_perlane_pass_w = d2c_perlane_pass & active_rx_lanes;
    assign error_detected_w     = (final_perlane_pass_w != active_rx_lanes);

    // =========================================================================
    // FSM State Encoding
    // ─────────────────────────────────────────────────────────────────────────
    // SEND → WAIT pattern. Each SEND state lasts exactly 1 lclk cycle.
    // LOCAL is INITIATOR only — no Role B (RESPONDER) states.
    // The PARTNER module on our die handles all responses to the remote LOCAL.
    // =========================================================================
    typedef enum logic [4:0] {
        // ── Common flow ──────────────────────────────────────────────────────
        LINKSPEED_LCL_IDLE                   = 5'd0,  // Wait for linkspeed_en.
        LINKSPEED_LCL_SEND_START_REQ         = 5'd1,  // Send {start req}.
        LINKSPEED_LCL_WAIT_START_RESP        = 5'd2,  // Wait for {start resp}.
        LINKSPEED_LCL_TX_D2C_PT              = 5'd3,  // Assert sweep_en; wait for sweep_done.
        LINKSPEED_LCL_EVAL_RESULT            = 5'd4,  // 1-cycle: evaluate D2C results.

        // ── SUCCESS PATH ─────────────────────────────────────────────────────
        // PHY retrain: LOCAL detected params_changed (INITIATOR role only).
        LINKSPEED_LCL_SEND_PHY_RETRAIN_REQ   = 5'd5,  // Send {exit to phy retrain REQ}.
        LINKSPEED_LCL_WAIT_PHY_RETRAIN_RESP  = 5'd6,  // Wait for {exit to phy retrain RESP} from REMOTE PARTNER.
        // Normal success:
        LINKSPEED_LCL_SEND_DONE_REQ          = 5'd7,  // Send {done req}.
        LINKSPEED_LCL_WAIT_DONE_RESP         = 5'd8,  // Wait for {done resp}.

        // ── ERROR / RECOVERY PATH ────────────────────────────────────────────
        LINKSPEED_LCL_SEND_ERROR_REQ         = 5'd9,  // Send {error req}. TX → Elec Idle.
        LINKSPEED_LCL_WAIT_ERROR_RESP        = 5'd10, // Wait for {error resp}.
        LINKSPEED_LCL_RECOVERY_DECISION      = 5'd11, // 1-cycle: choose repair vs speed-degrade.
        LINKSPEED_LCL_SEND_REPAIR_REQ        = 5'd12, // Send {exit to repair req}.
        LINKSPEED_LCL_WAIT_REPAIR_RESP       = 5'd13, // Wait for {exit to repair resp}.
        LINKSPEED_LCL_SEND_SPEED_DEGRADE_REQ = 5'd14, // Send {exit to speed degrade req}.
        LINKSPEED_LCL_WAIT_SPEED_DEGRADE_RESP= 5'd15, // Wait for {exit to speed degrade resp}.
        LINKSPEED_LCL_WAIT_RECOVERY_REQ      = 5'd16, // Wait for partner's recovery req (PARTNER FSM handles resp).

        // ── Terminal states ───────────────────────────────────────────────────
        LINKSPEED_LCL_TO_LINKINIT            = 5'd17, // linkspeed_done=1, linkinit_req=1.
        LINKSPEED_LCL_TO_REPAIR              = 5'd18, // linkspeed_done=1, repair_req=1.
        LINKSPEED_LCL_TO_SPEEDIDLE           = 5'd19, // linkspeed_done=1, speedidle_req=1.
        LINKSPEED_LCL_TO_PHYRETRAIN          = 5'd20  // linkspeed_done=1, phyretrain_req=1.
    } linkspeed_lcl_state_e;

    linkspeed_lcl_state_e current_state, next_state;

    // =========================================================================
    // Decision Registers (latched in EVAL_RESULT, 1-cycle state)
    // ─────────────────────────────────────────────────────────────────────────
    // Only registers that are consumed by subsequent states are declared here.
    //
    // NOT declared as registers (used combinationally only in EVAL_RESULT):
    //   d2c_fail_r       — EVAL_RESULT next-state reads error_detected_w directly
    //                      (combinational, same cycle). A flopped copy is never read.
    //   local_phy_retrain_r — EVAL_RESULT next-state reads (PHY_IN_RETRAIN && params_changed)
    //                         directly. No subsequent state reads a latched version.
    // =========================================================================
    logic req_speed_degrade_r;   // 1 = width degrade NOT feasible → must speed degrade.
    //     Read in: RECOVERY_DECISION.
    logic in_electrical_idle_r;  // 1 = TX must remain in Electrical Idle.
    //     Read in: OUTPUT_COMB_PROC MB TX default logic.

    // =========================================================================
    // Snooped Partner Message Flags (Sticky)
    // ─────────────────────────────────────────────────────────────────────────
    // LOCAL only monitors messages that it needs for its own FSM decisions.
    // It does NOT snoop {exit to phy retrain req} — that is handled exclusively
    // by the PARTNER FSM on our die (the PARTNER responds to the remote LOCAL).
    //
    // Cleared on: hard reset, soft reset, session teardown (!linkspeed_en).
    // Set on: each matching RX pulse, independently.
    // =========================================================================
    logic partner_error_req_rcvd;                 // Remote LOCAL sent {error req} → LOCAL must go to WAIT_RECOVERY.
    logic partner_exit_to_repair_req_rcvd;        // Remote LOCAL sent {exit to repair req} → LOCAL exits to REPAIR.
    logic partner_exit_to_speed_degrade_req_rcvd; // Remote LOCAL sent {exit to speed degrade req} → SPEEDIDLE.

    always_ff @(posedge lclk or negedge rst_n) begin : SNOOP_FLAGS_PROC
        if (!rst_n) begin
            partner_error_req_rcvd                  <= 1'b0;
            partner_exit_to_repair_req_rcvd         <= 1'b0;
            partner_exit_to_speed_degrade_req_rcvd  <= 1'b0;
        end
        else if (!linkspeed_en) begin
            partner_error_req_rcvd                  <= 1'b0;
            partner_exit_to_repair_req_rcvd         <= 1'b0;
            partner_exit_to_speed_degrade_req_rcvd  <= 1'b0;
        end
        else if (rx_sb_msg_valid) begin
            if (rx_sb_msg == MBTRAIN_LINKSPEED_error_req)
                partner_error_req_rcvd <= 1'b1;
            if (rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_repair_req)
                partner_exit_to_repair_req_rcvd <= 1'b1;
            if (rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req)
                partner_exit_to_speed_degrade_req_rcvd <= 1'b1;
        end
    end

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n)
            current_state <= LINKSPEED_LCL_IDLE;
        else if (!soft_rst_n)
            current_state <= LINKSPEED_LCL_IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // FSM Next-State Logic
    // ─────────────────────────────────────────────────────────────────────────
    // Priority levels:
    //   P1 (highest): Watchdog OR TRAINERROR req received → TO_TRAINERROR
    //   P2:           !linkspeed_en                       → IDLE
    //   P3:           Normal FSM case statement
    //
    // NOTE: There is NO "Role B" P3 override in this module.
    //   The PARTNER FSM on our die exclusively handles {exit to phy retrain req}
    //   received from the remote LOCAL. Our LOCAL has zero responsibility for
    //   responding to the remote LOCAL's requests (hierarchy.md §6).
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        // P2: Session teardown.
        if (!linkspeed_en) begin
            next_state = LINKSPEED_LCL_IDLE;
        end
        // P3: Normal FSM transitions.
        else begin
            case (current_state)

                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_IDLE: begin
                    next_state = linkspeed_en ? LINKSPEED_LCL_SEND_START_REQ : LINKSPEED_LCL_IDLE;
                end

                // ────────────────────────────────────────────────────────────
                // SEND_START_REQ: 1-cycle. Move to WAIT_START_RESP immediately.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_SEND_START_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_START_RESP;
                end

                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_WAIT_START_RESP: begin
                    next_state = (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_start_resp) ?
                        LINKSPEED_LCL_TX_D2C_PT : LINKSPEED_LCL_WAIT_START_RESP;
                end

                // ────────────────────────────────────────────────────────────
                // TX_D2C_PT: Holds sweep_en=1 until sweep_done.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_TX_D2C_PT: begin
                    next_state = sweep_done ? LINKSPEED_LCL_EVAL_RESULT : LINKSPEED_LCL_TX_D2C_PT;
                end

                // ────────────────────────────────────────────────────────────
                // EVAL_RESULT: 1-cycle. Uses COMBINATIONAL signals (not yet
                //   registered) to decide next state:
                //   - Error detected                          → error path
                //   - No error + PHY retrain + params changed → Role A (send req)
                //   - No error + PHY retrain + no change      → clear flag, done
                //   - No error + no PHY retrain               → done path
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_EVAL_RESULT: begin
                    if (error_detected_w)
                        next_state = LINKSPEED_LCL_SEND_ERROR_REQ;
                    else if (PHY_IN_RETRAIN && params_changed)
                        next_state = LINKSPEED_LCL_SEND_PHY_RETRAIN_REQ;
                    else
                        // PHY_IN_RETRAIN && !params_changed: clear flags and go to done.
                        // !PHY_IN_RETRAIN: go to done.
                        next_state = LINKSPEED_LCL_SEND_DONE_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // Role A: LOCAL sends {exit to phy retrain REQ}.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_SEND_PHY_RETRAIN_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_PHY_RETRAIN_RESP;
                end

                // ────────────────────────────────────────────────────────────
                // Role A: Wait for partner's {exit to phy retrain RESP}.
                //   Spec: "Once this sideband message is received, the UCIe Module
                //           must exit to PHY retrain."
                //   NOTE: The shared opcode is also used as RXDESKEW EQ Preset resp —
                //   in LINKSPEED context it unambiguously means the phy retrain resp.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_WAIT_PHY_RETRAIN_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp)
                        next_state = LINKSPEED_LCL_TO_PHYRETRAIN;
                    else
                        next_state = LINKSPEED_LCL_WAIT_PHY_RETRAIN_RESP;
                end

                // ────────────────────────────────────────────────────────────
                // SUCCESS PATH: {done req} / {done resp}.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_SEND_DONE_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_DONE_RESP;
                end

                // Wait for {done resp}. Interrupt: partner sent {error req} first.
                // Per spec §4.5.3.4.12 Step 3d: outstanding {done req} must be abandoned.
                LINKSPEED_LCL_WAIT_DONE_RESP: begin
                    if (partner_error_req_rcvd)
                        next_state = LINKSPEED_LCL_WAIT_RECOVERY_REQ;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_done_resp)
                        next_state = LINKSPEED_LCL_TO_LINKINIT;
                    else
                        next_state = LINKSPEED_LCL_WAIT_DONE_RESP;
                end

                // ────────────────────────────────────────────────────────────
                // ERROR PATH.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_SEND_ERROR_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_ERROR_RESP;
                end

                // Spec Step 3: "if not initiating {exit to phy retrain req}, partner
                //   enters Elec Idle and sends {error resp}."
                // P3 handles the case where partner IS initiating phy retrain req instead.
                LINKSPEED_LCL_WAIT_ERROR_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_error_resp)
                        next_state = LINKSPEED_LCL_RECOVERY_DECISION;
                    else
                        next_state = LINKSPEED_LCL_WAIT_ERROR_RESP;
                end

                // 1-cycle decision: check if partner already committed to speed degrade.
                LINKSPEED_LCL_RECOVERY_DECISION: begin
                    if (partner_exit_to_speed_degrade_req_rcvd)
                        next_state = LINKSPEED_LCL_TO_SPEEDIDLE;
                    else if (req_speed_degrade_r)
                        next_state = LINKSPEED_LCL_SEND_SPEED_DEGRADE_REQ;
                    else
                        next_state = LINKSPEED_LCL_SEND_REPAIR_REQ;
                end

                LINKSPEED_LCL_SEND_REPAIR_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_REPAIR_RESP;
                end

                // Spec Step 3c: {speed degrade req} received → abandon {repair req}.
                LINKSPEED_LCL_WAIT_REPAIR_RESP: begin
                    if (partner_exit_to_speed_degrade_req_rcvd)
                        next_state = LINKSPEED_LCL_TO_SPEEDIDLE;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_repair_resp)
                        next_state = LINKSPEED_LCL_TO_REPAIR;
                    else
                        next_state = LINKSPEED_LCL_WAIT_REPAIR_RESP;
                end

                LINKSPEED_LCL_SEND_SPEED_DEGRADE_REQ: begin
                    next_state = LINKSPEED_LCL_WAIT_SPEED_DEGRADE_RESP;
                end

                LINKSPEED_LCL_WAIT_SPEED_DEGRADE_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp)
                        next_state = LINKSPEED_LCL_TO_SPEEDIDLE;
                    else
                        next_state = LINKSPEED_LCL_WAIT_SPEED_DEGRADE_RESP;
                end

                // Cross-die: LOCAL was on success path; partner had errors.
                // Wait for partner to send recovery req (handled by PARTNER FSM resp).
                // Priority: speed degrade > repair.
                LINKSPEED_LCL_WAIT_RECOVERY_REQ: begin
                    if (partner_exit_to_speed_degrade_req_rcvd)
                        next_state = LINKSPEED_LCL_TO_SPEEDIDLE;
                    else if (partner_exit_to_repair_req_rcvd)
                        next_state = LINKSPEED_LCL_TO_REPAIR;
                    else
                        next_state = LINKSPEED_LCL_WAIT_RECOVERY_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // Terminal states: hold until linkspeed_en deasserts.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_LCL_TO_LINKINIT: begin
                    next_state = LINKSPEED_LCL_TO_LINKINIT;
                end
                LINKSPEED_LCL_TO_REPAIR: begin
                    next_state = LINKSPEED_LCL_TO_REPAIR;
                end
                LINKSPEED_LCL_TO_SPEEDIDLE: begin
                    next_state = LINKSPEED_LCL_TO_SPEEDIDLE;
                end
                LINKSPEED_LCL_TO_PHYRETRAIN: begin
                    next_state = LINKSPEED_LCL_TO_PHYRETRAIN;
                end

                default: next_state = LINKSPEED_LCL_IDLE;

            endcase
        end
    end

    // =========================================================================
    // Sequential Data Path Registers (latched in EVAL_RESULT)
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : DATA_PATH_REG_PROC
        if (!rst_n) begin
            req_speed_degrade_r     <= 1'b0;
            in_electrical_idle_r    <= 1'b0;
            linkspeed_success_lanes <= 16'h0;
        end
        else if (!soft_rst_n || !linkspeed_en) begin
            req_speed_degrade_r     <= 1'b0;
            in_electrical_idle_r    <= 1'b0;
            linkspeed_success_lanes <= 16'h0;
        end
        else begin
            if (current_state == LINKSPEED_LCL_EVAL_RESULT) begin
                // req_speed_degrade_r: held for RECOVERY_DECISION state (after error resp).
                req_speed_degrade_r     <= ~width_degrade_feasible;
                // in_electrical_idle_r: held throughout the error path; drives MB TX Elec-Idle.
                in_electrical_idle_r    <= error_detected_w;
                // linkspeed_success_lanes: passed to MBTRAIN.REPAIR to identify which lanes need repair.
                linkspeed_success_lanes <= final_perlane_pass_w;
                // NOTE: d2c_fail_r and local_phy_retrain_r are NOT latched here.
                // The EVAL_RESULT next-state logic reads error_detected_w and
                // (PHY_IN_RETRAIN && params_changed) combinationally in the same cycle,
                // so registered copies would only introduce a 1-cycle delay without benefit.
            end
        end
    end

    // =========================================================================
    // sweep_en: Combinational, deasserts automatically on leaving TX_D2C_PT.
    // =========================================================================
    assign sweep_en = (current_state == LINKSPEED_LCL_TX_D2C_PT);

    // =========================================================================
    // FSM Output Logic (Moore Machine — outputs depend only on current_state)
    // =========================================================================
    always_comb begin : OUTPUT_COMB_PROC

        // ── Control output defaults ──
        linkspeed_done      = 1'b0;
        speedidle_req       = 1'b0;
        repair_req          = 1'b0;
        linkinit_req        = 1'b0;
        phyretrain_req      = 1'b0;
        // NOTE: PHY_IN_RETRAIN_rst is driven by its own dedicated block (PHY_IN_RETRAIN_RST_PROC).

        // ── MB Rx defaults (always enabled per spec) ──
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b1;
        mb_rx_val_lane_sel  = 1'b1;
        mb_rx_trk_lane_sel  = 1'b0;

        // ── MB Tx defaults ──
        mb_tx_trk_lane_sel  = 2'b00; // Track TX: always held Low.
        if (in_electrical_idle_r) begin
            mb_tx_data_lane_sel = 2'b11; // Electrical Idle.
            mb_tx_val_lane_sel  = 2'b11;
            mb_tx_clk_lane_sel  = 2'b11;
        end else begin
            mb_tx_data_lane_sel = 2'b00; // Held Low.
            mb_tx_val_lane_sel  = 2'b00;
            mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;
        end

        // ── SB TX defaults ──
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = NOTHING;
        tx_msginfo      = 16'h0000;
        tx_data_field   = 64'h0;

        case (current_state)

            LINKSPEED_LCL_IDLE: ;

            // ── Common flow ──────────────────────────────────────────────────
            LINKSPEED_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_start_req;
            end

            LINKSPEED_LCL_WAIT_START_RESP: ; // Hold.

            LINKSPEED_LCL_TX_D2C_PT: begin
                mb_tx_data_lane_sel = 2'b01; // Active: TX sends LFSR pattern.
                mb_tx_val_lane_sel  = 2'b01; // Active: TX sends valid framing.
                // Clock TX: set by default logic above.
            end

            LINKSPEED_LCL_EVAL_RESULT: ; // No SB output. Sequential block latches this cycle.

            // ── Role A: LOCAL initiates PHY retrain ──────────────────────────
            // (LOCAL detected params_changed AND PHY_IN_RETRAIN AND no D2C errors)
            LINKSPEED_LCL_SEND_PHY_RETRAIN_REQ: begin
                tx_sb_msg_valid = 1'b1;
                // Opcode shared with RXDESKEW EQ Preset req — context disambiguates.
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
            end

            LINKSPEED_LCL_WAIT_PHY_RETRAIN_RESP: ; // Hold. Wait for partner's resp.

            // ── Success path ─────────────────────────────────────────────────
            LINKSPEED_LCL_SEND_DONE_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_done_req;
            end

            LINKSPEED_LCL_WAIT_DONE_RESP: ; // Hold.

            // ── Error path ───────────────────────────────────────────────────
            LINKSPEED_LCL_SEND_ERROR_REQ: begin
                tx_sb_msg_valid     = 1'b1;
                tx_sb_msg           = MBTRAIN_LINKSPEED_error_req;
                // TX already in Elec-Idle from in_electrical_idle_r (set in EVAL_RESULT).
                mb_tx_data_lane_sel = 2'b11;
                mb_tx_val_lane_sel  = 2'b11;
                mb_tx_clk_lane_sel  = 2'b11;
            end

            LINKSPEED_LCL_WAIT_ERROR_RESP: ; // Hold. TX in Elec-Idle.

            LINKSPEED_LCL_RECOVERY_DECISION: ; // 1-cycle. No SB output. (PHY_IN_RETRAIN_rst driven by PHY_IN_RETRAIN_RST_PROC)

            LINKSPEED_LCL_SEND_REPAIR_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_repair_req;
            end

            LINKSPEED_LCL_WAIT_REPAIR_RESP: ; // Hold.

            LINKSPEED_LCL_SEND_SPEED_DEGRADE_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_req;
            end

            LINKSPEED_LCL_WAIT_SPEED_DEGRADE_RESP: ; // Hold.

            LINKSPEED_LCL_WAIT_RECOVERY_REQ: ; // Hold. Partner had errors; wait for their recovery req.

            // ── Terminal states ──────────────────────────────────────────────
            LINKSPEED_LCL_TO_LINKINIT: begin
                linkspeed_done   = 1'b1;
                linkinit_req     = 1'b1;
            end

            LINKSPEED_LCL_TO_REPAIR: begin
                linkspeed_done   = 1'b1;
                repair_req       = 1'b1;
            end

            LINKSPEED_LCL_TO_SPEEDIDLE: begin
                linkspeed_done   = 1'b1;
                speedidle_req    = 1'b1;
            end

            LINKSPEED_LCL_TO_PHYRETRAIN: begin
                linkspeed_done   = 1'b1;
                phyretrain_req   = 1'b1;
            end

            default: ; // All defaults apply.

        endcase
    end

    // =========================================================================
    // PHY_IN_RETRAIN Reset Pulse
    // ─────────────────────────────────────────────────────────────────────────
    // Spec §4.5.3.4.12 (exact text):
    //   "after the {MBTRAIN.LINKSPEED error resp} sideband message is received,
    //    the PHY_IN_RETRAIN flag is cleared."
    //
    // HOW IT WORKS:
    //   1. FSM is in WAIT_ERROR_RESP, waiting for {error resp} from the remote die.
    //   2. {error resp} arrives → FSM transitions to RECOVERY_DECISION (next lclk).
    //   3. RECOVERY_DECISION is a dedicated 1-cycle evaluation state:
    //        • No SB message is sent (tx_sb_msg_valid = 0).
    //        • No SB message is expected on the RX bus.
    //        • PHY_IN_RETRAIN_rst = 1 for exactly this 1 lclk.
    //   4. On the following lclk, FSM moves to SEND_REPAIR_REQ or SEND_SPEED_DEGRADE_REQ.
    //        PHY_IN_RETRAIN_rst returns to 0.
    //
    // RESULT: A clean 1-lclk-wide active-high pulse, fully isolated from any SB activity.
    // =========================================================================
    always_comb begin : PHY_IN_RETRAIN_RST_PROC
        PHY_IN_RETRAIN_rst = (current_state == LINKSPEED_LCL_RECOVERY_DECISION) || (current_state == LINKSPEED_LCL_SEND_DONE_REQ);
        busy_bit_rst       = (current_state == LINKSPEED_LCL_SEND_DONE_REQ);
    end

endmodule
// ====================================================================================================
// END unit_LINKSPEED_local
// ====================================================================================================


