module unit_clk_handshake(
    input lp_clk_ack, clk_handshake_strt, lclk,
    output pl_clk_req, clk_handshake_done
);
    
typedef enum bit [1:0] {IDLE, REQ, DONE} state;
state CLK_cs=IDLE;

//next state logic 
    always @(posedge lclk) begin
        case (CLK_cs)
            IDLE:begin
                if (clk_handshake_strt)
                    CLK_cs=REQ;
                else 
                    CLK_cs=IDLE;
            end
            REQ:begin
                if(lp_clk_ack)
                    CLK_cs=DONE;
                else 
                    CLK_cs=REQ;
            end
            DONE:begin
                if (~clk_handshake_strt)
                    CLK_cs=IDLE;
                else 
                    CLK_cs=DONE;
            end
        endcase
    end

    //output logic
    assign clk_handshake_done = (CLK_cs==DONE);
    assign pl_clk_req  = (CLK_cs==REQ);
endmodule