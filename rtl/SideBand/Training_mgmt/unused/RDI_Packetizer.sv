import sb_pkg::*;

module RDI_Packetizer (
    input logic clk,
    input logic rst_n,

    // From RDI_SM
    input sb_rdi_msg_no_e RDI_msg_no_send,
    input logic stall_send,
    input logic RDI_vld_send,
    output logic RDI_rdy, // Indicates that the packetizer is rdy to accept a new message from RDI_SM

    input logic push_rdy,  // Indicates that the fifo is rdy to accept a new message (!= full)
    output logic [127:0] RDI_msg,
    output logic RDI_vld_out
);

    sb_header_u header_reg;
    sb_header_u header_next;

    always_comb begin
        header_next = '0;

        header_next.msg.opcode = SB_MSG_WITHOUT_DATA;
        header_next.msg.srcid = PHY;
        header_next.msg.dstid = REMOTE_PHY;

        header_next.msg.dp = 1'b0;

        // msgcode
        if (RDI_msg_no_send <= DISABLE_REQ) begin
            header_next.msg.msgcode = msg_code_e'(8'h01);  // Request
        end else if (RDI_msg_no_send == NOP) begin
            header_next.msg.msgcode = msg_code_e'(8'h00);
        end else begin
            header_next.msg.msgcode = msg_code_e'(8'h02);  // Response
        end

        // subcode mapping
        case (RDI_msg_no_send)
            ACTIVE_REQ, ACTIVE_RSP:         header_next.msg.MsgSubcode = 8'h01;
            PMNAK_RSP:                      header_next.msg.MsgSubcode = 8'h02;
            L1_REQ, L1_RSP:                 header_next.msg.MsgSubcode = 8'h04;
            L2_REQ, L2_RSP:                 header_next.msg.MsgSubcode = 8'h08;
            LINK_RESET_REQ, LINK_RESET_RSP: header_next.msg.MsgSubcode = 8'h09;
            LINK_ERROR_REQ, LINK_ERROR_RSP: header_next.msg.MsgSubcode = 8'h0A;
            RETRAIN_REQ, RETRAIN_RSP:       header_next.msg.MsgSubcode = 8'h0B;
            DISABLE_REQ, DISABLE_RSP:       header_next.msg.MsgSubcode = 8'h0C;
            default:                        header_next.msg.MsgSubcode = 8'h00;
        endcase

        // MsgInfo
        if (RDI_msg_no_send >= ACTIVE_RSP && RDI_msg_no_send != NOP) begin
            header_next.msg.MsgInfo = stall_send ? 16'hFFFF : 16'h0000;
        end else begin
            header_next.msg.MsgInfo = 16'h0000;
        end

        // parity (even)
        header_next.msg.cp = ^header_next.raw[61:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RDI_vld_out <= 1'b0;  // No valid message on reset
            header_reg  <= '0;  // Clear header on reset
        end else if (RDI_vld_send && push_rdy) begin
            header_reg  <= header_next;
            RDI_vld_out <= 1'b1;  // Indicate that the message is valid and rdy to be sent  
        end else begin
            RDI_vld_out <= 1'b0;  // No valid message if not sending
        end
    end


    assign RDI_rdy = push_rdy; // Packetizer is rdy to accept a new message if the fifo is rdy

    // ---------------------------
    // Output mapping
    // ---------------------------

    assign RDI_msg[63:0] = header_reg;
    assign RDI_msg[127:64] = 64'b0;

endmodule
