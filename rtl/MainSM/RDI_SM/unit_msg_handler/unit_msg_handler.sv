import UCIe_pkg::*;

module unit_msg_handler(
    input logic lclk, 
    input logic Active_resp_s,
    input logic Active_req_s,
    input logic valid_r,
    input msg_no_e Link_Mgmt_Msg_Recieved,
    input msg_no_e Massage_send,

    output logic Active_resp_r,
    output logic Active_req_r,
    output logic valid_s,
    output msg_no_e Link_Mgmt_Msg_Send,
    output msg_no_e Massage_recieve
);
    typedef enum logic [2:0] {IDLE, LnkMsgS, LnkMsgR, ActvHsS, ActvHsR} state;
    state cs=IDLE;

    always @(posedge lclk) begin
        case (cs)
            //------------------------------------------------------
            // IDLE State
            //------------------------------------------------------
            IDLE: begin
                if (Massage_send != NOTHING) begin//transition to LnkMsgS
                    cs <= LnkMsgS;
                    valid_s <= 1'b1;
                    Link_Mgmt_Msg_Send <= Massage_send;
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_REQ) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_RSP)) begin //transition to LnkMsgR
                    cs <= LnkMsgR;
                    Massage_recieve <= Link_Mgmt_Msg_Recieved;
                end
                //--------------------------------------------------------------------------------------
                else if (Active_req_s == 1'b1 || Active_resp_s == 1'b1) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_req_s == 1'b1) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s <= 1'b1;
                    end
                    else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s <= 1'b1;
                    end 
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && ( (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) || 
                                                (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_RSP))) begin //transition to ActvHsR
                    cs <= ActvHsR;
                    if (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) begin
                        Active_req_r <= 1'b1;
                    end
                    else begin
                        Active_resp_r <= 1'b1;
                    end
                end
            end
            //------------------------------------------------------
            // Link Layer Message Send
            //------------------------------------------------------
            LnkMsgS: begin
                if (Massage_send != NOTHING) begin//transition to LnkMsgS
                    cs <= LnkMsgS;
                    valid_s <= 1'b1;
                    Link_Mgmt_Msg_Send <= Massage_send;
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_REQ) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_RSP)) begin //transition to LnkMsgR
                    cs <= LnkMsgR;
                    Massage_recieve <= Link_Mgmt_Msg_Recieved;
                end
                //--------------------------------------------------------------------------------------
                else if (Active_req_s == 1'b1 || Active_resp_s == 1'b1) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_req_s == 1'b1) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s <= 1'b1;
                    end
                    else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s <= 1'b1;
                    end 
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && ( (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) || 
                                                (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_RSP))) begin //transition to ActvHsR
                    cs <= ActvHsR;
                    if (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) begin
                        Active_req_r <= 1'b1;
                    end
                    else begin
                        Active_resp_r <= 1'b1;
                    end
                end
                //--------------------------------------------------------------------------------------
                else begin //transition to IDLE
                    cs <= IDLE;
                    valid_s <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOTHING;
                    Massage_recieve <= NOTHING;
                    Active_req_r <= 1'b0;
                    Active_resp_r <= 1'b0;
                end 
            end
            //------------------------------------------------------
            // Link Layer Message Recieve
            //------------------------------------------------------
            LnkMsgR: begin
                if (Massage_send != NOTHING) begin//transition to LnkMsgS
                    cs <= LnkMsgS;
                    valid_s <= 1'b1;
                    Link_Mgmt_Msg_Send <= Massage_send;
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_REQ) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_RSP)) begin //transition to LnkMsgR
                    cs <= LnkMsgR;
                    Massage_recieve <= Link_Mgmt_Msg_Recieved;
                end
                //--------------------------------------------------------------------------------------
                else if (Active_req_s == 1'b1 || Active_resp_s == 1'b1) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_req_s == 1'b1) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s <= 1'b1;
                    end
                    else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s <= 1'b1;
                    end 
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && ( (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) || 
                                                (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_RSP))) begin //transition to ActvHsR
                    cs <= ActvHsR;
                    if (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) begin
                        Active_req_r <= 1'b1;
                    end
                    else begin
                        Active_resp_r <= 1'b1;
                    end
                end
                //--------------------------------------------------------------------------------------
                else begin //transition to IDLE
                    cs <= IDLE;
                    valid_s <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOTHING;
                    Massage_recieve <= NOTHING;
                    Active_req_r <= 1'b0;
                    Active_resp_r <= 1'b0;
                end 
            end
            //------------------------------------------------------
            // Active Handshake Send
            //------------------------------------------------------
            ActvHsS: begin
                if (Massage_send != NOTHING) begin//transition to LnkMsgS
                    cs <= LnkMsgS;
                    valid_s <= 1'b1;
                    Link_Mgmt_Msg_Send <= Massage_send;
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_REQ) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_RSP)) begin //transition to LnkMsgR
                    cs <= LnkMsgR;
                    Massage_recieve <= Link_Mgmt_Msg_Recieved;
                end
                //--------------------------------------------------------------------------------------
                else if (Active_req_s == 1'b1 || Active_resp_s == 1'b1) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_req_s == 1'b1) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s <= 1'b1;
                    end
                    else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s <= 1'b1;
                    end 
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && ( (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) || 
                                                (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_RSP))) begin //transition to ActvHsR
                    cs <= ActvHsR;
                    if (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) begin
                        Active_req_r <= 1'b1;
                    end
                    else begin
                        Active_resp_r <= 1'b1;
                    end
                end
                //--------------------------------------------------------------------------------------
                else begin //transition to IDLE
                    cs <= IDLE;
                    valid_s <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOTHING;
                    Massage_recieve <= NOTHING;
                    Active_req_r <= 1'b0;
                    Active_resp_r <= 1'b0;
                end 
            end
            //------------------------------------------------------
            // Active Handshake Recieve
            //------------------------------------------------------
            ActvHsR: begin
                if (Massage_send != NOTHING) begin//transition to LnkMsgS
                    cs <= LnkMsgS;
                    valid_s <= 1'b1;
                    Link_Mgmt_Msg_Send <= Massage_send;
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_REQ) && 
                        (Link_Mgmt_Msg_Recieved != RDI_ACTIVE_RSP)) begin //transition to LnkMsgR
                    cs <= LnkMsgR;
                    Massage_recieve <= Link_Mgmt_Msg_Recieved;
                end
                //--------------------------------------------------------------------------------------
                else if (Active_req_s == 1'b1 || Active_resp_s == 1'b1) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_req_s == 1'b1) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s <= 1'b1;
                    end
                    else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s <= 1'b1;
                    end 
                end
                //--------------------------------------------------------------------------------------
                else if ((valid_r == 1'b1) && ( (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) || 
                                                (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_RSP))) begin //transition to ActvHsR
                    cs <= ActvHsR;
                    if (Link_Mgmt_Msg_Recieved == RDI_ACTIVE_REQ) begin
                        Active_req_r <= 1'b1;
                    end
                    else begin
                        Active_resp_r <= 1'b1;
                    end
                end
                //--------------------------------------------------------------------------------------
                else begin //transition to IDLE
                    cs <= IDLE;
                    valid_s <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOTHING;
                    Massage_recieve <= NOTHING;
                    Active_req_r <= 1'b0;
                    Active_resp_r <= 1'b0;
                end 
            end
        endcase
    end    
endmodule