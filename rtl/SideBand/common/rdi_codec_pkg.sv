package rdi_codec_pkg;
    import sb_pkg::*;

    function automatic sb_header_t encode_rdi_header(
        input sb_rdi_msg_no_e msg_no,
        input logic stall
    );
        
        sb_header_t hdr;
        hdr        = '0;
        hdr.opcode = SB_MSG_WITHOUT_DATA;
        hdr.srcid  = PHY;
        hdr.dstid  = REMOTE_PHY;
        hdr.dp     = 1'b0;
        // msgcode
        case (msg_no)
            ACTIVE_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h01;
                hdr.MsgInfo = 16'h0000;
            end
            L1_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h04;
                hdr.MsgInfo = 16'h0000;
            end
            L2_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h08;
                hdr.MsgInfo = 16'h0000;
            end
            LINK_RESET_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h09;
                hdr.MsgInfo = 16'h0000;
            end
            LINK_ERROR_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h0A;
                hdr.MsgInfo = 16'h0000;
            end
            RETRAIN_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h0B;
                hdr.MsgInfo = 16'h0000;
            end
            DISABLE_REQ: begin
                hdr.msgcode = msg_code_e'(8'h01);
                hdr.MsgSubcode = 8'h0C;
                hdr.MsgInfo = 16'h0000;
            end
            ACTIVE_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h01;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            PMNAK_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h02;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            L1_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h04;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            L2_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h08;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            LINK_RESET_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h09;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            LINK_ERROR_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h0A;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            RETRAIN_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h0B;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            DISABLE_RSP: begin
                hdr.msgcode = msg_code_e'(8'h02);
                hdr.MsgSubcode = 8'h0C;
                hdr.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            default: begin
                hdr.msgcode = msg_code_e'(8'h00);
                hdr.MsgSubcode = 8'h00;
                hdr.MsgInfo = 16'h0000;
            end
        endcase
        hdr.cp = ^hdr[61:0];

        return hdr;
    endfunction

endpackage