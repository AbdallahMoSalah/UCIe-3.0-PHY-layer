module unit_awak_handshake (
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
                    AWAK_cs<=UNGATING;
            end
            UNGATING:begin
                if(ungating_done)
                    AWAK_cs<=ACK;
            end
            ACK:begin
                if (~lp_awak_req)
                    AWAK_cs<=IDLE;
            end
        endcase
    end

    //output logic
    assign ungating_req = (AWAK_cs==UNGATING);
    assign pl_awak_ack  = (AWAK_cs==ACK);
endmodule