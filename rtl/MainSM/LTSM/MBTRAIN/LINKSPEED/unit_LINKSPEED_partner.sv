// ====================================================================================================
// Module  : unit_LINKSPEED_partner
// Purpose : MBTRAIN.LINKSPEED sub-state PARTNER (Responder) FSM (UCIe 3.0 Spec §4.5.3.4.12).
//
// ─── ROLE ─────────────────────────────────────────────────────────────────────────────────────────
// This is the PARTNER (Responder) side of the decoupled LINKSPEED sub-state.
//
// The PARTNER FSM waits for Request messages from the REMOTE die's LOCAL module, then sends
// the appropriate Response. It mirrors (waits for req → sends resp) all the message pairs that
// unit_LINKSPEED_local sends (sends req → waits for resp).
//
// PARTNER FSM responsibilities:
//   1. Wait for {start req} → send {start resp}
//   2. Hold MB lanes at idle posture while the remote LOCAL performs its D2C point test.
//   3. Wait for whichever of these arrives next:
//        a. {done req}                   → send {done resp}       → exit to LINKINIT
//        b. {error req}                  → enter Elec-Idle on RX → send {error resp}
//                                        → wait for partner's recovery decision req
//        c. {exit to phy retrain req}    → send {exit to phy retrain resp} → PHYRETRAIN
//   4. On error path, respond to recovery decision:
//        {exit to repair req}            → send {exit to repair resp}       → REPAIR
//        {exit to speed degrade req}     → send {exit to speed degrade resp} → SPEEDIDLE
//
// ─── PHY RETRAIN ROLE ─────────────────────────────────────────────────────────────────────────────
// The PARTNER FSM on our die handles the RESPONDER role for {exit to phy retrain req}:
//   - When the remote LOCAL sends {exit to phy retrain req}:
//       PARTNER sends {exit to phy retrain resp} → exits to PHYRETRAIN.
//   - The LOCAL FSM on our die (unit_LINKSPEED_local) handles the INITIATOR role:
//       LOCAL sends {exit to phy retrain req} (if params_changed detected locally).
//
// NOTE: This division is correct. The PARTNER module only handles:
//   - Messages the REMOTE die's LOCAL sends as requests.
//   - We only send responses to those requests.
//   - The LOCAL module on OUR die handles both initiating AND responding to phy retrain
//     (see unit_LINKSPEED_local.sv Role A and Role B documentation).
//
// ─── BUS CONTENTION NOTE ──────────────────────────────────────────────────────────────────────────
// Both unit_LINKSPEED_local and unit_LINKSPEED_partner share the TX SB bus.
// Their tx_sb_msg_valid outputs feed into unit_sb_tx_arbiter (instantiated in the wrapper),
// which serializes them with a mandatory 1-cycle idle gap between transmissions.
// LOCAL has priority (Source A); PARTNER is secondary (Source B).
//
// ─── ARCHITECTURE ─────────────────────────────────────────────────────────────────────────────────
// Single FSM, WAIT → SEND pattern (exact mirror of LOCAL's SEND → WAIT).
// Each WAIT state polls rx_sb_msg until the expected request arrives.
// Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle, then transitions.
//
// ─── SB MESSAGES TABLE ────────────────────────────────────────────────────────────────────────────
// | Message                                        | Dir       | Notes                            |
// |------------------------------------------------|-----------|----------------------------------|
// | {MBTRAIN.LINKSPEED start req}                  | RX (In)   | From remote LOCAL                |
// | {MBTRAIN.LINKSPEED start resp}                 | TX (Out)  | Our response                     |
// | {MBTRAIN.LINKSPEED done req}                   | RX (In)   | Remote LOCAL success             |
// | {MBTRAIN.LINKSPEED done resp}                  | TX (Out)  | Our response → LINKINIT          |
// | {MBTRAIN.LINKSPEED error req}                  | RX (In)   | Remote LOCAL found errors        |
// | {MBTRAIN.LINKSPEED error resp}                 | TX (Out)  | Our response (after D2C done)    |
// | {MBTRAIN.LINKSPEED exit to repair req}         | RX (In)   | Remote LOCAL chose repair        |
// | {MBTRAIN.LINKSPEED exit to repair resp}        | TX (Out)  | Our response → REPAIR            |
// | {MBTRAIN.LINKSPEED exit to speed degrade req}  | RX (In)   | Remote LOCAL chose speed degrade |
// | {MBTRAIN.LINKSPEED exit to speed degrade resp} | TX (Out)  | Our response → SPEEDIDLE         |
// | {MBTRAIN.LINKSPEED exit to phy retrain req}    | RX (In)   | Remote LOCAL detected change     |
// | {MBTRAIN.LINKSPEED exit to phy retrain resp}   | TX (Out)  | Our response → PHYRETRAIN        |
// | {TRAINERROR entry req}                         | RX (In)   | → TO_TRAINERROR immediately      |
// NOTE: {exit to phy retrain req/resp} share opcodes with RXDESKEW EQ Preset req/resp.
// ====================================================================================================

module unit_LINKSPEED_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk,                  // LTSM clock domain (1–2 GHz).
        input  logic        rst_n,                 // 0: Async reset to IDLE; 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        linkspeed_en,          // 1: Enable; 0: Return to IDLE.
        input  logic        soft_rst_n,            // 1: Normal; 0: Soft-reset → IDLE.
        output logic        partner_sweep_en,      // 1: enable the TX_D2C_PT in partner side.

        output logic        linkspeed_done,        // 1: Sub-state completed (held until linkspeed_en=0).
        output logic        speedidle_req,         // 1: Exit to MBTRAIN.SPEEDIDLE.
        output logic        repair_req,            // 1: Exit to MBTRAIN.REPAIR.
        output logic        linkinit_req,          // 1: Exit to LINKINIT.
        output logic        phyretrain_req,        // 1: Exit to PHYRETRAIN.
        output logic        trainerror_req,        // 1: Exit to TRAINERROR.

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
        input  logic        is_high_speed,          // 1 = speed > 32 GT/s.
        input  logic        is_continuous_clk_mode, // 1 = continuous clock mode.

        //=====================================//
        // Sideband TX Signals:                //
        //=====================================//
        // Fed into unit_sb_tx_arbiter (Source B — lower priority than LOCAL).
        output logic        tx_sb_msg_valid,        // 1 = valid message this cycle (1-cycle pulse).
        output logic [7:0]  tx_sb_msg,              // Message opcode.
        output logic [15:0] tx_msginfo,             // MsgInfo payload (always 16'h0 for LINKSPEED).
        output logic [63:0] tx_data_field,          // Data payload (always 64'h0 for LINKSPEED).

        //=====================================//
        // Sideband RX Signals:                //
        //=====================================//
        input  logic        rx_sb_msg_valid,        // 1 = valid RX message arrived this cycle.
        input  logic [7:0]  rx_sb_msg,             // Received opcode.
        input  logic [15:0] rx_msginfo,            // Received MsgInfo. NOTE: always 16'h0 in LINKSPEED.
        input  logic [63:0] rx_data_field          // Received data.     NOTE: always 64'h0 in LINKSPEED.
    );

    import UCIe_pkg::*;

    // =========================================================================
    // FSM State Encoding — WAIT → SEND pattern
    // ─────────────────────────────────────────────────────────────────────────
    // Each WAIT state holds until the expected RX message arrives.
    // Each SEND state lasts exactly 1 lclk cycle (tx_sb_msg_valid=1).
    // Terminal states hold until linkspeed_en deasserts.
    // =========================================================================
    typedef enum logic [3:0] {
        // ── Common flow ─────────────────────────────────────────────────────
        LINKSPEED_PTR_IDLE                    = 4'd0,  // Wait for linkspeed_en.
        LINKSPEED_PTR_WAIT_START_REQ          = 4'd1,  // Wait for {start req} from remote LOCAL.
        LINKSPEED_PTR_SEND_START_RESP         = 4'd2,  // Send {start resp}.

        // ── Main wait loop: remote LOCAL is running D2C test ─────────────────
        // After {start resp}, we wait for whatever the remote LOCAL sends next:
        //   {done req}               → success path
        //   {error req}              → error path
        //   {exit to phy retrain req}→ PHY retrain path
        LINKSPEED_PTR_WAIT_POST_D2C_REQ       = 4'd3,

        // ── Success path ────────────────────────────────────────────────────
        LINKSPEED_PTR_SEND_DONE_RESP          = 4'd4,  // Send {done resp}.

        // ── Error path ───────────────────────────────────────────────────────
        // On {error req}: enter Elec-Idle on RX, send {error resp}.
        // Then wait for remote LOCAL's recovery decision req.
        LINKSPEED_PTR_SEND_ERROR_RESP         = 4'd5,  // Send {error resp}.
        LINKSPEED_PTR_WAIT_RECOVERY_REQ       = 4'd6,  // Wait for {repair req} or {speed degrade req}.
        LINKSPEED_PTR_SEND_REPAIR_RESP        = 4'd7,  // Send {exit to repair resp}.
        LINKSPEED_PTR_SEND_SPEED_DEGRADE_RESP = 4'd8,  // Send {exit to speed degrade resp}.

        // ── PHY retrain path ────────────────────────────────────────────────
        // Remote LOCAL detected params_changed, sends {exit to phy retrain req}.
        LINKSPEED_PTR_SEND_PHY_RETRAIN_RESP   = 4'd9,  // Send {exit to phy retrain resp}.

        // ── Terminal states ──────────────────────────────────────────────────
        LINKSPEED_PTR_TO_LINKINIT             = 4'd10, // linkspeed_done=1, linkinit_req=1.
        LINKSPEED_PTR_TO_REPAIR               = 4'd11, // linkspeed_done=1, repair_req=1.
        LINKSPEED_PTR_TO_SPEEDIDLE            = 4'd12, // linkspeed_done=1, speedidle_req=1.
        LINKSPEED_PTR_TO_PHYRETRAIN           = 4'd13, // linkspeed_done=1, phyretrain_req=1.
        LINKSPEED_PTR_TO_TRAINERROR           = 4'd14  // linkspeed_done=1, trainerror_req=1.
    } linkspeed_ptr_state_e;

    linkspeed_ptr_state_e current_state, next_state;

    // =========================================================================
    // Snoop Register: error_req_rcvd
    // ─────────────────────────────────────────────────────────────────────────
    // Sticky flag: set when {error req} arrives during WAIT_POST_D2C_REQ.
    // Used to track that we must enter Elec-Idle on our RX lanes and prepare
    // to send {error resp}. Also guards the WAIT_RECOVERY_REQ path.
    // Cleared on reset and session teardown.
    // =========================================================================
    logic error_req_rcvd;

    always_ff @(posedge lclk or negedge rst_n) begin : SNOOP_PROC
        if (!rst_n)
            error_req_rcvd <= 1'b0;
        else if (!linkspeed_en)
            error_req_rcvd <= 1'b0;
        else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_error_req)
            error_req_rcvd <= 1'b1;
    end

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n)
            current_state <= LINKSPEED_PTR_IDLE;
        else if (!soft_rst_n)
            current_state <= LINKSPEED_PTR_IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // FSM Next-State Logic
    // ─────────────────────────────────────────────────────────────────────────
    // Priority:
    //   P1 (highest): Watchdog OR TRAINERROR req received → TO_TRAINERROR
    //   P2:           !linkspeed_en                       → IDLE
    //   P3:           Normal FSM case transitions
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        // P1: TRAINERROR — highest priority.
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = LINKSPEED_PTR_TO_TRAINERROR;
        end
        // P2: Session teardown.
        else if (!linkspeed_en) begin
            next_state = LINKSPEED_PTR_IDLE;
        end
        // P3: Normal transitions.
        else begin
            case (current_state)

                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_IDLE: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_WAIT_START_REQ
                        : LINKSPEED_PTR_IDLE;
                end

                // ────────────────────────────────────────────────────────────
                // Wait for {start req} from remote LOCAL.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_WAIT_START_REQ: begin
                    next_state = (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_start_req) ?
                        LINKSPEED_PTR_SEND_START_RESP : LINKSPEED_PTR_WAIT_START_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // 1-cycle: send {start resp}.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_SEND_START_RESP: begin
                    next_state = LINKSPEED_PTR_WAIT_POST_D2C_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // Main wait loop: remote LOCAL runs its D2C point test.
                // We hold MB lanes at idle/clock posture and wait for whatever
                // the remote LOCAL sends after completing its test.
                //
                // Three possible incoming messages (in priority order):
                //   {exit to phy retrain req} — highest priority (abandons everything)
                //   {error req}               — remote LOCAL found errors
                //   {done req}                — remote LOCAL succeeded
                //
                // Spec §4.5.3.4.12 Step 3: "any outstanding messages are abandoned"
                // when {exit to phy retrain req} is received.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_WAIT_POST_D2C_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req)
                        // PHY retrain: abandon all, send resp, exit.
                        next_state = LINKSPEED_PTR_SEND_PHY_RETRAIN_RESP;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_error_req)
                        // Remote LOCAL found errors. We must send {error resp} after going
                        // Elec-Idle on RX. The snoop flag handles RX Elec-Idle in output logic.
                        next_state = LINKSPEED_PTR_SEND_ERROR_RESP;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_done_req)
                        next_state = LINKSPEED_PTR_SEND_DONE_RESP;
                    else
                        next_state = LINKSPEED_PTR_WAIT_POST_D2C_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // Send {done resp} → LINKINIT.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_SEND_DONE_RESP: begin
                    next_state = LINKSPEED_PTR_TO_LINKINIT;
                end

                // ────────────────────────────────────────────────────────────
                // Send {error resp} → wait for recovery decision from remote LOCAL.
                // Spec Step 3: "UCIe Module Partner enters electrical idle on its
                //   Receiver and sends the {error resp} sideband message."
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_SEND_ERROR_RESP: begin
                    next_state = LINKSPEED_PTR_WAIT_RECOVERY_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // Wait for remote LOCAL's recovery decision:
                //   {exit to repair req}         → send repair resp
                //   {exit to speed degrade req}  → send speed degrade resp
                //   {exit to phy retrain req}    → send phy retrain resp (abandons recovery)
                //
                // Priority: phy retrain > speed degrade > repair
                // Spec Step 3c: speed degrade overrides repair.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_WAIT_RECOVERY_REQ: begin
                    if (rx_sb_msg_valid &&
                            rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req)
                        next_state = LINKSPEED_PTR_SEND_PHY_RETRAIN_RESP;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req)
                        next_state = LINKSPEED_PTR_SEND_SPEED_DEGRADE_RESP;
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_repair_req)
                        next_state = LINKSPEED_PTR_SEND_REPAIR_RESP;
                    else
                        next_state = LINKSPEED_PTR_WAIT_RECOVERY_REQ;
                end

                // ────────────────────────────────────────────────────────────
                // 1-cycle SEND states → respective terminal states.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_SEND_REPAIR_RESP: begin
                    next_state = LINKSPEED_PTR_TO_REPAIR;
                end

                LINKSPEED_PTR_SEND_SPEED_DEGRADE_RESP: begin
                    next_state = LINKSPEED_PTR_TO_SPEEDIDLE;
                end

                LINKSPEED_PTR_SEND_PHY_RETRAIN_RESP: begin
                    next_state = LINKSPEED_PTR_TO_PHYRETRAIN;
                end

                // ────────────────────────────────────────────────────────────
                // Terminal states: hold until linkspeed_en deasserts.
                // ────────────────────────────────────────────────────────────
                LINKSPEED_PTR_TO_LINKINIT: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_TO_LINKINIT : LINKSPEED_PTR_IDLE;
                end
                LINKSPEED_PTR_TO_REPAIR: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_TO_REPAIR : LINKSPEED_PTR_IDLE;
                end
                LINKSPEED_PTR_TO_SPEEDIDLE: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_TO_SPEEDIDLE : LINKSPEED_PTR_IDLE;
                end
                LINKSPEED_PTR_TO_PHYRETRAIN: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_TO_PHYRETRAIN : LINKSPEED_PTR_IDLE;
                end
                LINKSPEED_PTR_TO_TRAINERROR: begin
                    next_state = linkspeed_en ? LINKSPEED_PTR_TO_TRAINERROR : LINKSPEED_PTR_IDLE;
                end

                default: next_state = LINKSPEED_PTR_IDLE;

            endcase
        end
    end

    // =========================================================================
    // FSM Output Logic (Moore Machine — outputs depend only on current_state)
    // ─────────────────────────────────────────────────────────────────────────
    // Exception: MB RX Elec-Idle is driven from error_req_rcvd (registered flag),
    // which is set in the snoop block. This is acceptable because error_req_rcvd is
    // a registered (not combinational) signal, so no combinational loop is created.
    // =========================================================================
    always_comb begin : OUTPUT_COMB_PROC

        // ── Control output defaults ──
        linkspeed_done   = 1'b0;
        speedidle_req    = 1'b0;
        repair_req       = 1'b0;
        linkinit_req     = 1'b0;
        phyretrain_req   = 1'b0;
        trainerror_req   = 1'b0;
        partner_sweep_en = 1'b0;

        // ── MB RX defaults (always enabled per spec §4.5.3.4.12) ──
        // Exception: when {error req} received, PARTNER must enter Elec-Idle on RX.
        // Spec Step 3: "the UCIe Module Partner enters electrical idle on its Receiver".
        // This is gated on error_req_rcvd (registered), which is set when {error req} arrives.
        if (error_req_rcvd) begin
            // RX Elec-Idle on error path (per spec).
            // Note: UCIe does not define a "Elec-Idle" encoding for RX lane selects;
            // "entering electrical idle on receiver" means disabling the RX receivers.
            mb_rx_clk_lane_sel  = 1'b0; // Disable clock RX.
            mb_rx_data_lane_sel = 1'b0; // Disable data RX.
            mb_rx_val_lane_sel  = 1'b0; // Disable valid RX.
            mb_rx_trk_lane_sel  = 1'b0;
        end else begin
            mb_rx_clk_lane_sel  = 1'b1;
            mb_rx_data_lane_sel = 1'b1;
            mb_rx_val_lane_sel  = 1'b1;
            mb_rx_trk_lane_sel  = 1'b0;
        end

        // ── MB TX defaults ──
        // PARTNER holds Data and Valid TX low while remote LOCAL runs its D2C test.
        // Track TX: always held Low (spec).
        // Clock TX: free-running (high speed/continuous clock) or low (strobe/≤32 GT/s).
        mb_tx_trk_lane_sel  = 2'b00;
        mb_tx_data_lane_sel = 2'b00; // Held Low — partner does not transmit data.
        mb_tx_val_lane_sel  = 2'b00; // Held Low — partner does not transmit valid.
        mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;

        // ── SB TX defaults ──
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = NOTHING;
        tx_msginfo      = 16'h0000;
        tx_data_field   = 64'h0;

        case (current_state)

            LINKSPEED_PTR_IDLE: begin
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00;
            end

            // ── Wait states: no SB TX output ────────────────────────────────
            LINKSPEED_PTR_WAIT_START_REQ     : ; // Hold.

            LINKSPEED_PTR_WAIT_POST_D2C_REQ  : begin
                partner_sweep_en = 1'b1;
            end

            LINKSPEED_PTR_WAIT_RECOVERY_REQ  : ; // Hold. RX Elec-Idle from error_req_rcvd.

            // ── SEND states: 1-cycle tx_sb_msg_valid pulse ───────────────────
            LINKSPEED_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_start_resp;
            end

            LINKSPEED_PTR_SEND_DONE_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_done_resp;
            end

            // Spec: Partner enters RX Elec-Idle (from error_req_rcvd above), then sends resp.
            LINKSPEED_PTR_SEND_ERROR_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_error_resp;
            end

            LINKSPEED_PTR_SEND_REPAIR_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_repair_resp;
            end

            LINKSPEED_PTR_SEND_SPEED_DEGRADE_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp;
            end

            // PHY retrain resp: shared opcode with RXDESKEW EQ Preset resp.
            // Context (LINKSPEED state) disambiguates.
            LINKSPEED_PTR_SEND_PHY_RETRAIN_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
            end

            // ── Terminal states ──────────────────────────────────────────────
            LINKSPEED_PTR_TO_LINKINIT: begin
                linkspeed_done   = 1'b1;
                linkinit_req     = 1'b1;
            end

            LINKSPEED_PTR_TO_REPAIR: begin
                linkspeed_done   = 1'b1;
                repair_req       = 1'b1;
            end

            LINKSPEED_PTR_TO_SPEEDIDLE: begin
                linkspeed_done   = 1'b1;
                speedidle_req    = 1'b1;
            end

            LINKSPEED_PTR_TO_PHYRETRAIN: begin
                linkspeed_done   = 1'b1;
                phyretrain_req   = 1'b1;
            end

            LINKSPEED_PTR_TO_TRAINERROR: begin
                linkspeed_done   = 1'b1;
                trainerror_req   = 1'b1;
            end

            default: ; // All defaults apply.

        endcase
    end

endmodule
// ====================================================================================================
// END unit_LINKSPEED_partner
// ====================================================================================================


