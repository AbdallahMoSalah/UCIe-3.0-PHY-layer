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
    input  state_n_e    mbinit_state_n,
    input  state_n_e    mbtrain_state_n,
    output state_n_e    current_ltsm_state_n,

    output logic        sbinit_en,
    input  logic        sbinit_done,

    output logic        mbinit_en,
    input  logic        mbinit_done,

    output logic        mbtrain_en,
    input  logic        mbtrain_done,

    output logic        linkinit_en,
    input  logic        linkinit_done,

    output logic        active_en,

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

    // =============================================================================
    // STATE LOG REGISTERS (SHIFT & LATCH HISTORY)
    // =============================================================================
    always_comb begin
        case (current_state)
            CTRL_RESET:      current_log_state = LOG_RESET;
            CTRL_SBINIT:     current_log_state = LOG_SBINIT;
            CTRL_MBINIT:     current_log_state = mbinit_state_n;
            CTRL_MBTRAIN:    current_log_state = mbtrain_state_n;
            CTRL_LINKINIT:   current_log_state = LOG_LINKINIT;
            CTRL_ACTIVE:     current_log_state = LOG_ACTIVE;
            //CTRL_PHYRETRAIN: current_log_state = LOG_PHYRETRAIN;
            //CTRL_L1, CTRL_L2: current_log_state = LOG_L1_L2;
            //CTRL_TRAINERROR: current_log_state = LOG_TRAINERROR;
            // Handshake sub-phases log as TRAINERROR; this also restarts the
            // shared watchdog on entry (fresh 8 ms for the handshake) and avoids
            // a duplicate log shift when CTRL_TRAINERROR is finally reached.
            default:             current_log_state = LOG_RESET;
        endcase
    end

    logic [7:0] log0_state_n_reg;
    logic [7:0] log0_state_n_minus_1_reg;
    logic [7:0] log0_state_n_minus_2_reg;
    logic [7:0] log1_state_n_minus_3_reg;

    logic log0_state_n_valid_reg;
    logic log0_state_n_minus_1_valid_reg;
    logic log0_state_n_minus_2_valid_reg;
    logic log1_state_n_minus_3_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_state_n_reg         <= 8'h00;
            log0_state_n_minus_1_reg <= 8'h00;
            log0_state_n_minus_2_reg <= 8'h00;
            log1_state_n_minus_3_reg <= 8'h00;

            log0_state_n_valid_reg         <= 1'b0;
            log0_state_n_minus_1_valid_reg <= 1'b0;
            log0_state_n_minus_2_valid_reg <= 1'b0;
            log1_state_n_minus_3_valid_reg <= 1'b0;
        end else begin
            log0_state_n_valid_reg         <= 1'b0;
            log0_state_n_minus_1_valid_reg <= 1'b0;
            log0_state_n_minus_2_valid_reg <= 1'b0;
            log1_state_n_minus_3_valid_reg <= 1'b0;

            if (current_log_state != log0_state_n_reg[4:0]) begin
                log0_state_n_reg         <= {3'b0, current_log_state};
                log0_state_n_minus_1_reg <= log0_state_n_reg;
                log0_state_n_minus_2_reg <= log0_state_n_minus_1_reg;
                log1_state_n_minus_3_reg <= log0_state_n_minus_2_reg;

                log0_state_n_valid_reg         <= 1'b1;
                log0_state_n_minus_1_valid_reg <= 1'b1;
                log0_state_n_minus_2_valid_reg <= 1'b1;
                log1_state_n_minus_3_valid_reg <= 1'b1;
            end
        end
    end

    assign current_ltsm_state_n = current_log_state;

    assign log0_state_n         = log0_state_n_reg;
    assign log0_state_n_minus_1 = log0_state_n_minus_1_reg;
    assign log0_state_n_minus_2 = log0_state_n_minus_2_reg;
    assign log1_state_n_minus_3 = log1_state_n_minus_3_reg;

    assign log0_state_n_valid         = log0_state_n_valid_reg;
    assign log0_state_n_minus_1_valid = log0_state_n_minus_1_valid_reg;
    assign log0_state_n_minus_2_valid = log0_state_n_minus_2_valid_reg;
    assign log1_state_n_minus_3_valid = log1_state_n_minus_3_valid_reg;

    // Dynamically evaluate log0_width_degrade and log0_lane_reversal
    always_comb begin
        log0_width_degrade = 1'b0;
        if (reg_Max_Link_Width_cap == 3'b000) begin // Local max width capability x16
            if (reg_Link_Width_enable_status == 4'h1 || reg_Link_Width_enable_status == 4'h0) begin
                log0_width_degrade = 1'b1;
            end
        end else if (reg_Max_Link_Width_cap == 3'b111) begin // Local max width capability x8
            if (reg_Link_Width_enable_status == 4'h0) begin
                log0_width_degrade = 1'b1;
            end
        end
    end

    assign log0_lane_reversal = mb_lane_reversal_req;

    logic log0_lane_reversal_valid_reg;
    logic log0_width_degrade_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_lane_reversal_valid_reg <= 1'b0;
            log0_width_degrade_valid_reg <= 1'b0;
        end else begin
            log0_lane_reversal_valid_reg <= (next_state != current_state);
            log0_width_degrade_valid_reg <= (next_state != current_state);
        end
    end

    assign log0_lane_reversal_valid = log0_lane_reversal_valid_reg;
    assign log0_width_degrade_valid = log0_width_degrade_valid_reg;

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
