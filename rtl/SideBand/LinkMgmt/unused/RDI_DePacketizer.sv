import sb_pkg::*;

module RDI_DePacketizer(
    input logic clk,
    input logic rst_n,

    // From link control
    input logic [127:0] LINK_msg_rcvd,
    input logic LINK_vld_rcvd,
    output sb_rdi_msg_no_e RDI_msg_no_rcvd,
    output logic stall_rcvd,
    output logic RDI_vld_rcvd
);


    sb_header_u header;


    sb_rdi_msg_no_e RDI_msg_no_rcvd_next;
    logic stall_rcvd_next;
    logic rdi_msg_valid;

    logic        cp_calc;

    logic error;

    // ----------------------------------
    // Cast 128-bit message → struct
    // ----------------------------------


    // ----------------------------------
    // Decode logic
    // ----------------------------------
    always_comb begin

        RDI_msg_no_rcvd_next = NOP;
        stall_rcvd_next      = 1'b0;

        header = LINK_msg_rcvd[63:0];

        cp_calc = ^header.raw[61:0];

        if (header.msg.msgcode == 8'h02 )begin
            stall_rcvd_next = (header.msg.MsgInfo == 16'hFFFF);
        end
        else begin
            stall_rcvd_next = 0;
        end
        case ({header.msg.msgcode, header.msg.MsgSubcode})
            {8'h01,8'h01}: RDI_msg_no_rcvd_next = ACTIVE_REQ;
            {8'h01,8'h04}: RDI_msg_no_rcvd_next = L1_REQ;
            {8'h01,8'h08}: RDI_msg_no_rcvd_next = L2_REQ;
            {8'h01,8'h09}: RDI_msg_no_rcvd_next = LINK_RESET_REQ;
            {8'h01,8'h0A}: RDI_msg_no_rcvd_next = LINK_ERROR_REQ;
            {8'h01,8'h0B}: RDI_msg_no_rcvd_next = RETRAIN_REQ;
            {8'h01,8'h0C}: RDI_msg_no_rcvd_next = DISABLE_REQ;
            {8'h02,8'h01}: RDI_msg_no_rcvd_next = ACTIVE_RSP;
            {8'h02,8'h02}: RDI_msg_no_rcvd_next = PMNAK_RSP;
            {8'h02,8'h04}: RDI_msg_no_rcvd_next = L1_RSP;
            {8'h02,8'h08}: RDI_msg_no_rcvd_next = L2_RSP;
            {8'h02,8'h09}: RDI_msg_no_rcvd_next = LINK_RESET_RSP;
            {8'h02,8'h0A}: RDI_msg_no_rcvd_next = LINK_ERROR_RSP;
            {8'h02,8'h0B}: RDI_msg_no_rcvd_next = RETRAIN_RSP;
            {8'h02,8'h0C}: RDI_msg_no_rcvd_next = DISABLE_RSP;
            default: RDI_msg_no_rcvd_next = NOP;
        endcase
            
        rdi_msg_valid = ((header.msg.MsgInfo == 16'h0 || header.msg.MsgInfo == 16'hffff) && RDI_msg_no_rcvd_next != NOP);
        error = (header.msg.opcode != SB_MSG_WITHOUT_DATA || header.msg.cp != cp_calc || !rdi_msg_valid);
    end

    // --------------------------
    // Sequential
    // --------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RDI_vld_rcvd <= 1'b0; // No valid message on reset
            RDI_msg_no_rcvd <= NOP;
            stall_rcvd <= 1'b0;

        end else if(LINK_vld_rcvd && !error) begin

            RDI_msg_no_rcvd <= RDI_msg_no_rcvd_next;
            stall_rcvd <= stall_rcvd_next;
            RDI_vld_rcvd <=1; // Indicate that the message is valid and ready to be sent  
        end else begin
            RDI_vld_rcvd <= 1'b0; 
            RDI_msg_no_rcvd <= NOP;
            stall_rcvd <= 0;
        end
    end
    
endmodule