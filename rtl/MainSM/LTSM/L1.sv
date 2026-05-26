// UCIe 3.0 §4.5.3.9 L1 state.
//
// Entered after RDI transitions to PM (L1).  MB Tx is tri-stated and Rx may
// be disabled while resident.  L1 exit is coordinated with RDI; this LTSM
// state is a pure residency + exit-trigger detector.  Exit destination per
// spec: MBTRAIN.SPEEDIDLE (selected by the top controller).
//
// L2SPD is on the project's skipped-features list, so no SB power-down flow
// is implemented here.
//
// Exit triggers (level or 1-cycle pulse — both supported):
//   local_active_req       : local Adapter requested Active on RDI
//   remote_l1_exit_req     : remote partner requested L1 exit (decoded by
//                            top/SB from an incoming SB message)

module L1 (
    input  logic clk,
    input  logic rst_n,

    input  logic l1_enable,

    input  logic local_active_req,
    input  logic remote_l1_exit_req,

    output logic l1_done
);

    typedef enum logic [1:0] {
        IDLE,
        L1_RUN,
        DONE_HOLD
    } l1_state_e;

    l1_state_e current_state, next_state;

    // Exit-trigger stickies.
    logic local_active_sticky;
    logic remote_exit_sticky;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            local_active_sticky <= 1'b0;
            remote_exit_sticky  <= 1'b0;
        end else if (current_state == IDLE) begin
            local_active_sticky <= 1'b0;
            remote_exit_sticky  <= 1'b0;
        end else begin
            if (local_active_req)   local_active_sticky <= 1'b1;
            if (remote_l1_exit_req) remote_exit_sticky  <= 1'b1;
        end
    end

    logic exit_seen;
    assign exit_seen = local_active_sticky || remote_exit_sticky;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        if (!l1_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE      : next_state = L1_RUN;
                L1_RUN    : if (exit_seen) next_state = DONE_HOLD;
                DONE_HOLD : ; // hold until l1_enable drops
                default   : next_state = IDLE;
            endcase
        end
    end

    assign l1_done = (current_state == DONE_HOLD);

endmodule
