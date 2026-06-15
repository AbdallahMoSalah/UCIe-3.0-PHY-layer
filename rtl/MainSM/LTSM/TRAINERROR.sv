module TRAINERROR
    import RDI_SM_pkg::*;
    (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        trainerror_enable,
    input  RDI_state    rdi_state_sts,

    output logic        trainerror_done
);

    // ---------------- FSM ----------------
    typedef enum logic [1:0] {
        IDLE,
        HOLD,
        DONE
    } te_state_e;

    te_state_e current_state, next_state;

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // ---------------- Next-state ----------------
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE          : if (trainerror_enable) next_state = HOLD;
            HOLD          : if (rdi_state_sts != LinkError) next_state = DONE;
            DONE          : ;
            default       : next_state = IDLE;
        endcase
    end

    assign trainerror_done = (current_state == DONE);

endmodule
