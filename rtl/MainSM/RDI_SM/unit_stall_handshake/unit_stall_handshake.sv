module unit_stall_handshake(
    input lp_stallack, lclk, stall_req, 
    output pl_stallreq, stall_done
);

typedef enum logic [1:0] { IDLE, STALLREQ, STALLACK, STALLDONE } state;
state STALL_state= IDLE;

always @(posedge lclk) begin
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

assign pl_stallreq = (STALL_state == STALLREQ)||(STALL_state ==STALLACK);
assign stall_done = (STALL_state ==STALLACK);
endmodule