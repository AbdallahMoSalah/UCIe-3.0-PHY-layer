import UCIe_pkg::*;

module unit_msg_handler(
    input logic lclk, 
    input logic rst_n,
    input msg_no_e Active_message_send,
    input msg_no_e Message_send,
    input logic valid_r,
    input msg_no_e Link_Mgmt_Msg_Received,

    output logic valid_s,
    output msg_no_e Link_Mgmt_Msg_Send,
    output msg_no_e Message_receive
);
    typedef enum logic [2:0] {IDLE, LnkMsgS, LnkMsgR, ActvHsS} state;
    state cs = IDLE;

    // ---------------------------------------------------------------
    // 1-entry RX capture register
    // Captures every valid_r pulse unconditionally so a message
    // arriving while the FSM is busy is never silently dropped.
    //
    // NOTE: pending_rx_valid is driven from a single always_ff block
    // below (merged with the FSM) to avoid the multi-driver violation
    // that would result from two separate always_ff blocks writing the
    // same register.  Consume (clear) takes priority over capture (set)
    // so a simultaneous valid_r on the same cycle as the FSM consuming
    // the entry does not re-assert a flag that was just cleared.
    // ---------------------------------------------------------------
    msg_no_e pending_rx_msg;
    logic    pending_rx_valid;

    // Helper wire: FSM is consuming the pending entry this cycle
    // (any state where the else-if(pending_rx_valid) branch is taken).
    // Because the consume condition is identical in every FSM state
    // (pending_rx_valid && the FSM chooses the LnkMsgR branch), we
    // capture it once here for use in the unified register update.
    logic consuming_pending;
    assign consuming_pending =
        pending_rx_valid &&
        (Message_send == NOP) &&  // LnkMsgS branch not taken
        (cs == IDLE    ||
         cs == LnkMsgS ||
         cs == LnkMsgR ||
         cs == ActvHsS);

    always_ff @(posedge lclk or negedge rst_n) begin
        if (~rst_n) begin
            cs                 <= IDLE;
            valid_s            <= 1'b0;
            Link_Mgmt_Msg_Send <= NOP;
            Message_receive    <= NOP;
            pending_rx_msg     <= NOP;
            pending_rx_valid   <= 1'b0;
        end else begin
            // ----------------------------------------------------------
            // Unified pending_rx register update — single driver only.
            // Consume (clear) takes priority over capture (set).
            // ----------------------------------------------------------
            if (consuming_pending) begin
                // FSM is consuming the entry this cycle — clear it.
                // Even if valid_r is asserted simultaneously, the new
                // message will arrive again next cycle (or must be
                // re-presented); clearing takes priority to avoid a
                // stale flag masking future captures.
                pending_rx_valid <= 1'b0;
            end else if (valid_r) begin
                pending_rx_msg   <= Link_Mgmt_Msg_Received;
                pending_rx_valid <= 1'b1;
            end

            // ----------------------------------------------------------
            // FSM state transitions
            // ----------------------------------------------------------
            case (cs)
            //------------------------------------------------------
            // IDLE State
            //------------------------------------------------------
            IDLE: begin
                if (Message_send != NOP) begin //transition to LnkMsgS
                    cs                 <= LnkMsgS;
                    valid_s            <= 1'b1;
                    Link_Mgmt_Msg_Send <= Message_send;
                end
                //--------------------------------------------------
                else if (pending_rx_valid) begin //transition to LnkMsgR
                    cs              <= LnkMsgR;
                    Message_receive <= pending_rx_msg;
                    // pending_rx_valid cleared by unified block above
                end
                //--------------------------------------------------
                else if (Active_message_send != NOP) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_message_send == RDI_ACTIVE_REQ) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s            <= 1'b1;
                    end else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s            <= 1'b1;
                    end
                end
            end
            //------------------------------------------------------
            // Link Layer Message Send
            //------------------------------------------------------
            LnkMsgS: begin
                if (Message_send != NOP) begin //transition to LnkMsgS
                    cs                 <= LnkMsgS;
                    valid_s            <= 1'b1;
                    Link_Mgmt_Msg_Send <= Message_send;
                end
                //--------------------------------------------------
                else if (pending_rx_valid) begin //transition to LnkMsgR
                    cs              <= LnkMsgR;
                    Message_receive <= pending_rx_msg;
                    // pending_rx_valid cleared by unified block above
                end
                //--------------------------------------------------
                else if (Active_message_send != NOP) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_message_send == RDI_ACTIVE_REQ) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s            <= 1'b1;
                    end else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s            <= 1'b1;
                    end
                end
                //--------------------------------------------------
                else begin //transition to IDLE
                    cs                 <= IDLE;
                    valid_s            <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOP;
                    Message_receive    <= NOP;
                end
            end
            //------------------------------------------------------
            // Link Layer Message Receive
            //------------------------------------------------------
            LnkMsgR: begin
                if (Message_send != NOP) begin //transition to LnkMsgS
                    cs                 <= LnkMsgS;
                    valid_s            <= 1'b1;
                    Link_Mgmt_Msg_Send <= Message_send;
                end
                //--------------------------------------------------
                else if (pending_rx_valid) begin //transition to LnkMsgR
                    cs              <= LnkMsgR;
                    Message_receive <= pending_rx_msg;
                    // pending_rx_valid cleared by unified block above
                end
                //--------------------------------------------------
                else if (Active_message_send != NOP) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_message_send == RDI_ACTIVE_REQ) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s            <= 1'b1;
                    end else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s            <= 1'b1;
                    end
                end
                //--------------------------------------------------
                else begin //transition to IDLE
                    cs                 <= IDLE;
                    valid_s            <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOP;
                    Message_receive    <= NOP;
                end
            end
            //------------------------------------------------------
            // Active Handshake Send
            //------------------------------------------------------
            ActvHsS: begin
                if (Message_send != NOP) begin //transition to LnkMsgS
                    cs                 <= LnkMsgS;
                    valid_s            <= 1'b1;
                    Link_Mgmt_Msg_Send <= Message_send;
                end
                //--------------------------------------------------
                else if (pending_rx_valid) begin //transition to LnkMsgR
                    cs              <= LnkMsgR;
                    Message_receive <= pending_rx_msg;
                    // pending_rx_valid cleared by unified block above
                end
                //--------------------------------------------------
                else if (Active_message_send != NOP) begin //transition to ActvHsS
                    cs <= ActvHsS;
                    if (Active_message_send == RDI_ACTIVE_REQ) begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_REQ;
                        valid_s            <= 1'b1;
                    end else begin
                        Link_Mgmt_Msg_Send <= RDI_ACTIVE_RSP;
                        valid_s            <= 1'b1;
                    end
                end
                //--------------------------------------------------
                else begin //transition to IDLE
                    cs                 <= IDLE;
                    valid_s            <= 1'b0;
                    Link_Mgmt_Msg_Send <= NOP;
                    Message_receive    <= NOP;
                end
            end
                default: cs <= IDLE;
            endcase
        end
    end
endmodule
