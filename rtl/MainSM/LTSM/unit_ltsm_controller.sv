// =============================================================================
// unit_ltsm_controller  —  Step 1: initial / minimal LTSM controller FSM
// =============================================================================
// Sequences the Step-1 subset of LTSM states:
//
//     RESET -> SBINIT -> MBINIT -> MBTRAIN -> LINKINIT -> ACTIVE
//
// Responsibilities (kept deliberately minimal — pure FSM, no datapath muxing):
//   * one-hot per-state enables (drive the state submodules in the wrapper)
//   * the current-state status enum (used by the wrapper to mux SB / MB / D2C)
//   * the shared 8 ms watchdog control (enabled in the SB/MB training states,
//     restarted on every state change so each state gets a fresh budget)
//
// MBTRAIN is a PASS-THROUGH in Step 1 (no verified MBTRAIN block yet): the FSM
// enters it, asserts mbtrain_en, and leaves as soon as mbtrain_done is seen
// (the wrapper ties mbtrain_done high). The MB datapath is exercised by MBINIT.
//
// Deferred to later steps: PHYRETRAIN / L1 / L2 / TRAINERROR states, the
// timeout_8ms_occured -> TRAINERROR reaction, and the sideband/mainband muxing
// (that lives in the LTSM wrapper for now). The state register uses the full
// ltsm_ctrl_state_e so adding those states later is a localised change.
// =============================================================================

module unit_ltsm_controller
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------------------------------------------------------- handshakes
    output logic        reset_en,
    input  logic        reset_done,

    output logic        sbinit_en,
    input  logic        sbinit_done,

    output logic        mbinit_en,
    input  logic        mbinit_done,

    output logic        mbtrain_en,
    input  logic        mbtrain_done,
    // MBTRAIN-resolved exit request (from wrapper_MBTRAIN.ltsm_phyretrain_req).
    // LINKINIT exit is implied by mbtrain_done; TRAINERROR exit arrives via
    // mbtrain_error (wrapper_MBTRAIN.ltsm_trainerror_req).
    input  logic        mbtrain_phyretrain_req,

    output logic        linkinit_en,
    input  logic        linkinit_done,

    output logic        active_en,

    // L1 exit re-enters MBTRAIN at SPEEDIDLE: held high for the whole MBTRAIN
    // visit that follows an L1 wake (drives wrapper_MBTRAIN.mbtrain_speedidle_req).
    output logic        mbtrain_speedidle_req,

    // ---------------------------------------------------------------- error inputs
    // Reserved: in a later step these drive the TRAINERROR entry handshake
    // (§4.5.3.8). For now they are wired through from the state blocks but the
    // FSM takes NO action on them.
    input  logic        sbinit_error,
    input  logic        mbinit_error,
    input  logic        mbtrain_error,   // <= MBTRAIN ltsm_trainerror_req
    input  logic        linkinit_error,
    input  logic        active_error,

    // ---------------------------------------------------------------- ACTIVE exit
    // Reserved: ACTIVE resolves the next LTSM state (PHYRETRAIN / L1 / L2 /
    // TRAINERROR) here. Wired now; the FSM acts on it in a later step (ACTIVE is
    // terminal in Step 1).
    input  ltsm_ctrl_state_e active_next_ltsm_state,

    // ---------------------------------------------------------------- status
    output LTSM_state_e current_ltsm_state,

    // ---------------------------------------------------------------- handshakes for remaining states
    output logic        phyretrain_en,
    input  logic        phyretrain_done,

    output logic        l1_en,
    input  logic        l1_done,
    input  logic        l1_error,

    output logic        l2_en,
    input  logic        l2_done,
    input  logic        l2_error,

    output logic        trainerror_en,
    input  logic        trainerror_done,

    // ---------------------------------------------------------------- 8 ms timer
    input  logic        timeout_8ms_occured  // drives TRAINERROR on timeout
);

    // =========================================================================
    // STATE REGISTER
    // =========================================================================
    ltsm_ctrl_state_e current_state, next_state;
    state_n_e current_log_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= CTRL_RESET;
        else        current_state <= next_state;
    end

    // =========================================================================
    // NEXT-STATE LOGIC (linear Step-1 walk)
    // =========================================================================
    always_comb begin
        next_state = current_state;
        
        // Global error / timeout transition to TRAINERROR
        if (timeout_8ms_occured && (
            current_state == CTRL_SBINIT ||
            current_state == CTRL_MBINIT ||
            current_state == CTRL_MBTRAIN ||
            current_state == CTRL_LINKINIT ||
            current_state == CTRL_PHYRETRAIN
        )) begin
            next_state = CTRL_TRAINERROR;
        end else begin
            case (current_state)
                CTRL_RESET:    if (reset_done)         next_state = CTRL_SBINIT;
                
                CTRL_SBINIT:   if (sbinit_error)       next_state = CTRL_TRAINERROR;
                               else if (sbinit_done)   next_state = CTRL_MBINIT;
                               
                CTRL_MBINIT:   if (mbinit_error)       next_state = CTRL_TRAINERROR;
                               else if (mbinit_done)   next_state = CTRL_MBTRAIN;
                               
                CTRL_MBTRAIN:  if (mbtrain_error)            next_state = CTRL_TRAINERROR;
                               else if (mbtrain_phyretrain_req) next_state = CTRL_PHYRETRAIN;
                               else if (mbtrain_done)        next_state = CTRL_LINKINIT;
                               
                CTRL_LINKINIT: if (linkinit_error)     next_state = CTRL_TRAINERROR;
                               else if (linkinit_done) next_state = CTRL_ACTIVE;
                               
                CTRL_ACTIVE:   if (active_next_ltsm_state == CTRL_TRAINERROR)
                                   next_state = CTRL_TRAINERROR;
                               else if (active_next_ltsm_state != CTRL_ACTIVE && active_next_ltsm_state != CTRL_NOP)
                                   next_state = active_next_ltsm_state;
                                   
                CTRL_PHYRETRAIN: if (phyretrain_done)  next_state = CTRL_MBTRAIN;

                // L1 exit -> MBTRAIN re-entering at SPEEDIDLE (see
                // mbtrain_speedidle_req below); error -> TRAINERROR
                CTRL_L1:       if (l1_error)           next_state = CTRL_TRAINERROR;
                               else if (l1_done)       next_state = CTRL_MBTRAIN;

                // L2 exit -> RESET (deep sleep, re-train from scratch); error -> TRAINERROR
                CTRL_L2:       if (l2_error)           next_state = CTRL_TRAINERROR;
                               else if (l2_done)       next_state = CTRL_RESET;
                
                CTRL_TRAINERROR: if (trainerror_done)  next_state = CTRL_RESET;
                
                default:       next_state = CTRL_RESET;
            endcase
        end
    end

    // =========================================================================
    // ONE-HOT STATE ENABLES
    // =========================================================================
    always_comb begin
        reset_en      = 1'b0;
        sbinit_en     = 1'b0;
        mbinit_en     = 1'b0;
        mbtrain_en    = 1'b0;
        linkinit_en   = 1'b0;
        active_en     = 1'b0;
        phyretrain_en = 1'b0;
        l1_en         = 1'b0;
        l2_en         = 1'b0;
        trainerror_en = 1'b0;
        case (current_state)
            CTRL_RESET:      reset_en      = 1'b1;
            CTRL_SBINIT:     sbinit_en     = 1'b1;
            CTRL_MBINIT:     mbinit_en     = 1'b1;
            CTRL_MBTRAIN:    mbtrain_en    = 1'b1;
            CTRL_LINKINIT:   linkinit_en   = 1'b1;
            CTRL_ACTIVE:     active_en     = 1'b1;
            CTRL_PHYRETRAIN: phyretrain_en = 1'b1;
            CTRL_L1:         l1_en         = 1'b1;
            CTRL_L2:         l2_en         = 1'b1;
            CTRL_TRAINERROR: trainerror_en = 1'b1;
            default: ;
        endcase
    end




    // =========================================================================
    // L1-EXIT MBTRAIN RE-ENTRY (SPEEDIDLE)
    // =========================================================================
    // When L1 exits we re-enter MBTRAIN at SPEEDIDLE (skipping VALVREF/DATAVREF).
    // wrapper_MBTRAIN samples mbtrain_speedidle_req in its IDLE state as mbtrain_en
    // rises, so we set the latch on the L1 -> MBTRAIN edge and hold it for the whole
    // MBTRAIN visit, clearing as MBTRAIN is left. Normal MBTRAIN entries (from
    // MBINIT) leave it low, so they enter at VALVREF as before.
    logic mbtrain_from_l1_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mbtrain_from_l1_q <= 1'b0;
        else if (current_state == CTRL_L1 && next_state == CTRL_MBTRAIN)
            mbtrain_from_l1_q <= 1'b1;
        else if (current_state == CTRL_MBTRAIN && next_state != CTRL_MBTRAIN)
            mbtrain_from_l1_q <= 1'b0;
    end
    assign mbtrain_speedidle_req = mbtrain_from_l1_q;

    // =========================================================================
    // CURRENT-STATE STATUS ENUM
    // =========================================================================
    always_comb begin
        case (current_state)
            CTRL_RESET:      current_ltsm_state = RESET;
            CTRL_SBINIT:     current_ltsm_state = SBINIT;
            CTRL_MBINIT:     current_ltsm_state = MBINIT;
            CTRL_MBTRAIN:    current_ltsm_state = MBTRAIN;
            CTRL_LINKINIT:   current_ltsm_state = LINKINIT;
            CTRL_ACTIVE:     current_ltsm_state = ACTIVE;
            CTRL_PHYRETRAIN: current_ltsm_state = PHYRETRAIN;
            CTRL_L1:         current_ltsm_state = L1;
            CTRL_L2:         current_ltsm_state = L2;
            CTRL_TRAINERROR: current_ltsm_state = TRAINERROR;
            default:         current_ltsm_state = NO_OP;
        endcase
    end

    // timeout_8ms_occured is consumed by the state blocks (global_error) in the
    // wrapper; the controller's own timeout -> TRAINERROR reaction is handled via transition.

endmodule
