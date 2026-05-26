// UCIe 3.0 §4.5.3.6 ACTIVE state.
//
// Physical layer is fully initialized; RDI is in Active; upper-layer packets
// flow over the mainband (scrambled per §4.4.1) under the clock-gating rules
// of §5.11.
//
// This module is purely a residency / exit-trigger detector.  ACTIVE has no
// internal sequencing and drives no MB / SB / scrambler control signals
// (those are hard-wired by the top LTSM module while ACTIVE is the current
// state).
//
// Exit triggers (all may arrive as 1-cycle pulses, so each is latched in a
// sticky while in ACTIVE):
//   phyretrain_req : §4.5.3.7 (Adapter / PHY framing error / remote-die request)
//   l1_req         : §4.5.3.9 L1 entry request from the Adapter
//   l2_req         : §4.5.3.9 L2 entry request from the Adapter
//   linkreset_req  : LinkReset request
//   linkerror_req  : LinkError request
//   trainerror_req : fatal/non-fatal event forcing return to RESET
//
// When any sticky is set, active_done asserts and is held until active_enable
// deasserts.  The top controller observes the raw trigger inputs (also routed
// to it) to choose the next state.

module ACTIVE (
    input  logic clk,
    input  logic rst_n,

    input  logic active_enable,

    // Exit triggers (single-cycle pulses or levels — both supported).
    input  logic phyretrain_req,
    input  logic l1_req,
    input  logic l2_req,
    input  logic linkreset_req,
    input  logic linkerror_req,
    input  logic trainerror_req,

    output logic active_done
);

    // ---------------- FSM ----------------
    typedef enum logic [1:0] {
        IDLE,
        ACTIVE_RUN,
        DONE_HOLD
    } active_state_e;

    active_state_e current_state, next_state;

    // ---------------- Exit-trigger stickies ----------------
    // Latched while not in IDLE.  Cleared on entry to IDLE (i.e. when
    // active_enable drops or async reset).
    logic phyretrain_sticky;
    logic l1_sticky;
    logic l2_sticky;
    logic linkreset_sticky;
    logic linkerror_sticky;
    logic trainerror_sticky;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phyretrain_sticky <= 1'b0;
            l1_sticky         <= 1'b0;
            l2_sticky         <= 1'b0;
            linkreset_sticky  <= 1'b0;
            linkerror_sticky  <= 1'b0;
            trainerror_sticky <= 1'b0;
        end else if (current_state == IDLE) begin
            phyretrain_sticky <= 1'b0;
            l1_sticky         <= 1'b0;
            l2_sticky         <= 1'b0;
            linkreset_sticky  <= 1'b0;
            linkerror_sticky  <= 1'b0;
            trainerror_sticky <= 1'b0;
        end else begin
            if (phyretrain_req) phyretrain_sticky <= 1'b1;
            if (l1_req)         l1_sticky         <= 1'b1;
            if (l2_req)         l2_sticky         <= 1'b1;
            if (linkreset_req)  linkreset_sticky  <= 1'b1;
            if (linkerror_req)  linkerror_sticky  <= 1'b1;
            if (trainerror_req) trainerror_sticky <= 1'b1;
        end
    end

    logic exit_seen;
    assign exit_seen = phyretrain_sticky
                    || l1_sticky
                    || l2_sticky
                    || linkreset_sticky
                    || linkerror_sticky
                    || trainerror_sticky;

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // ---------------- Next-state logic ----------------
    always_comb begin
        next_state = current_state;
        if (!active_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE       : next_state = ACTIVE_RUN;
                ACTIVE_RUN : if (exit_seen) next_state = DONE_HOLD;
                DONE_HOLD  : ; // hold until active_enable drops
                default    : next_state = IDLE;
            endcase
        end
    end

    assign active_done = (current_state == DONE_HOLD);

endmodule
