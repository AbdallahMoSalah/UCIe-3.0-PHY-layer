module unit_stall_handshake(
    input  lp_stallack, lclk, stall_req, rst_n,
    input  mapper_en,
    output pl_stallreq, stall_done,
    output logic stall_done_latched
);

typedef enum logic [1:0] { IDLE, STALLREQ, STALLACK, STALLDONE } state;
state STALL_state;

always @(posedge lclk or negedge rst_n) begin
    if (!rst_n) begin
        STALL_state <= IDLE;
    end else begin
    case (STALL_state)
    IDLE:begin
        if (stall_req) begin
            STALL_state <= STALLREQ;
        end
    end
    STALLREQ:begin
        if (lp_stallack) begin
            STALL_state <= STALLACK;
        end
    end
    STALLACK:begin
        if (~stall_req) begin
            STALL_state <= STALLDONE;
        end
    end
    STALLDONE:begin
        if (~lp_stallack) begin
            STALL_state <= IDLE;
        end
    end
    default: STALL_state<=IDLE;
    endcase
    end
end

assign pl_stallreq = (STALL_state == STALLREQ)||(STALL_state ==STALLACK);
assign stall_done = (STALL_state ==STALLACK);

// -------------------------------------------------------------------------
// Mapper-stall latch (relocated here from the MainSM glue): capture the
// stall_done pulse into a level ("data path stalled") held until the LTSM
// mapper enable falls, so the stall handshake fully owns this signal.
//   * set   on stall_done   (handshake reached STALLACK)
//   * clear when mapper_en falls (acts as the latch reset)
// -------------------------------------------------------------------------
always @(posedge lclk or negedge rst_n) begin
    if (!rst_n)
        stall_done_latched <= 1'b0;
    else if (!mapper_en)        // enable low -> clear the latch
        stall_done_latched <= 1'b0;
    else if (stall_done)        // set on stall_done (stalled)
        stall_done_latched <= 1'b1;
end
endmodule
