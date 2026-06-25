module unit_awak_handshake (
    input lp_wake_req, ungating_done, lclk, rst_n,
    output pl_wake_ack, ungating_req
);

typedef enum bit [1:0] {IDLE, UNGATING, ACK} state;
state AWAK_cs;

//next state logic 
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            AWAK_cs <= IDLE;
        end else begin
            case (AWAK_cs)
            IDLE:begin
                if (lp_wake_req)
                    AWAK_cs<=UNGATING;
            end
            UNGATING:begin
                if(ungating_done)
                    AWAK_cs<=ACK;
            end
            ACK:begin
                if (~lp_wake_req)
                    AWAK_cs<=IDLE;
            end
            default: AWAK_cs <= IDLE;
        endcase
        end
    end

    //output logic
    assign ungating_req = (AWAK_cs==UNGATING);
    assign pl_wake_ack  = (AWAK_cs==ACK);
endmodule
