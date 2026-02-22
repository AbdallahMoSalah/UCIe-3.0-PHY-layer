module AWAKE_handshake_block (
    input lp_awak_req, ungating_done, lclk,
    output pl_awak_ack, ungating_req
);

typedef enum bit [1:0] {IDLE, UNGATING, ACK} state;
state AWAK_cs=IDLE;

//next state logic 
    always @(posedge lclk) begin
        case (AWAK_cs)
            IDLE:begin
                if (lp_awak_req)
                    AWAK_cs=UNGATING;
                else 
                    AWAK_cs=IDLE;
            end
            UNGATING:begin
                if(ungating_done)
                    AWAK_cs=ACK;
                else 
                    AWAK_cs=UNGATING;
            end
            ACK:begin
                if (~lp_awak_req)
                    AWAK_cs=IDLE;
                else 
                    AWAK_cs=ACK;
            end
        endcase
    end

    //output logic
    assign ungating_req = (AWAK_cs==UNGATING);
    assign pl_awak_ack  = (AWAK_cs==ACK);
endmodule