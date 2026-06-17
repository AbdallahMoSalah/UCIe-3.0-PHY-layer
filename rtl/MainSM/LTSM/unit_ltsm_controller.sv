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
    input  logic        mbtrain_done,   // pass-through: tied high in the wrapper

    output logic        linkinit_en,
    input  logic        linkinit_done,

    output logic        active_en,

    // ---------------------------------------------------------------- error inputs
    // Reserved: in a later step these drive the TRAINERROR entry handshake
    // (§4.5.3.8). For now they are wired through from the state blocks but the
    // FSM takes NO action on them.
    input  logic        sbinit_error,
    input  logic        mbinit_error,
    input  logic        linkinit_error,
    input  logic        active_error,

    // ---------------------------------------------------------------- status
    output LTSM_state_e current_ltsm_state,

    // ---------------------------------------------------------------- 8 ms timer
    output logic        timeout_timer_en,
    output logic        timer_rst_n,
    input  logic        timeout_8ms_occured  // reserved: drives TRAINERROR in a later step
);

    // =========================================================================
    // STATE REGISTER
    // =========================================================================
    ltsm_ctrl_state_e current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= CTRL_RESET;
        else        current_state <= next_state;
    end

    // =========================================================================
    // NEXT-STATE LOGIC (linear Step-1 walk)
    // =========================================================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            CTRL_RESET:    if (reset_done)    next_state = CTRL_SBINIT;
            CTRL_SBINIT:   if (sbinit_done)   next_state = CTRL_MBINIT;
            CTRL_MBINIT:   if (mbinit_done)   next_state = CTRL_MBTRAIN;
            CTRL_MBTRAIN:  if (mbtrain_done)  next_state = CTRL_LINKINIT;
            CTRL_LINKINIT: if (linkinit_done) next_state = CTRL_ACTIVE;
            CTRL_ACTIVE:   next_state = CTRL_ACTIVE; // terminal in Step 1
            default:       next_state = CTRL_RESET;
        endcase
    end

    // =========================================================================
    // ONE-HOT STATE ENABLES
    // =========================================================================
    always_comb begin
        reset_en    = 1'b0;
        sbinit_en   = 1'b0;
        mbinit_en   = 1'b0;
        mbtrain_en  = 1'b0;
        linkinit_en = 1'b0;
        active_en   = 1'b0;
        case (current_state)
            CTRL_RESET:    reset_en    = 1'b1;
            CTRL_SBINIT:   sbinit_en   = 1'b1;
            CTRL_MBINIT:   mbinit_en   = 1'b1;
            CTRL_MBTRAIN:  mbtrain_en  = 1'b1;
            CTRL_LINKINIT: linkinit_en = 1'b1;
            CTRL_ACTIVE:   active_en   = 1'b1;
            default: ;
        endcase
    end

    // =========================================================================
    // CURRENT-STATE STATUS ENUM
    // =========================================================================
    always_comb begin
        case (current_state)
            CTRL_RESET:    current_ltsm_state = RESET;
            CTRL_SBINIT:   current_ltsm_state = SBINIT;
            CTRL_MBINIT:   current_ltsm_state = MBINIT;
            CTRL_MBTRAIN:  current_ltsm_state = MBTRAIN;
            CTRL_LINKINIT: current_ltsm_state = LINKINIT;
            CTRL_ACTIVE:   current_ltsm_state = ACTIVE;
            default:       current_ltsm_state = NO_OP;
        endcase
    end

    // =========================================================================
    // SHARED 8 ms WATCHDOG CONTROL
    // =========================================================================
    // Enabled while a sideband/mainband handshake can stall (SBINIT..LINKINIT).
    assign timeout_timer_en = (current_state == CTRL_SBINIT)  ||
                              (current_state == CTRL_MBINIT)   ||
                              (current_state == CTRL_MBTRAIN)  ||
                              (current_state == CTRL_LINKINIT);

    // Restart the counter for one cycle whenever the state changes, so every
    // state begins with a full 8 ms budget.
    logic state_changing;
    assign state_changing = (next_state != current_state);

    logic timer_rst_n_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) timer_rst_n_q <= 1'b0;
        else        timer_rst_n_q <= ~state_changing; // low for the first cycle of the new state
    end
    assign timer_rst_n = timer_rst_n_q;

    // timeout_8ms_occured is consumed by the state blocks (global_error) in the
    // wrapper; the controller's own timeout -> TRAINERROR reaction is a later step.

endmodule
