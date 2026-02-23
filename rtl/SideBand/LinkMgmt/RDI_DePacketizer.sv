import sb_pkg::*;

module RDI_DePacketizer(
    input logic clk,
    input logic rst_n,

    // From link control
    input logic [127:0] LINK_msg_rcvd,
    input logic LINK_vld_rcvd,
    output logic [3:0] RDI_msg_no_rcvd,
    output logic stall_rcvd,
    output logic RDI_vld_rcvd
);


    sb_header_t header;


    logic [3:0] RDI_msg_no_rcvd_next;
    logic stall_rcvd_next;

    sb_opcode_e opcode;
    sb_srcid_e srcid;
    sb_dstid_e dstid;

    logic [7:0] msgcode;
    logic [7:0] MsgSubcode;
    logic [15:0] MsgInfo;
    logic cp;


    logic        cp_calc;


    // ----------------------------------
    // Cast 128-bit message → struct
    // ----------------------------------
    assign header = LINK_msg_rcvd[63:0];

    // --------------------------
    // Field extraction
    // --------------------------
/* 
    assign opcode = LINK_msg_rcvd[0 +: 5];
    assign msgcode = LINK_msg_rcvd[14 +: 8];
    assign srcid = LINK_msg_rcvd[29 +: 3];
    assign MsgSubcode = LINK_msg_rcvd[32 +: 8];
    assign MsgInfo = LINK_msg_rcvd[40 +: 16];
    assign dstid = LINK_msg_rcvd[56 +: 3];
    assign cp = LINK_msg_rcvd[62];

    assign cp_calc    = ^LINK_msg_rcvd[0 +: 62];
 */
    // ----------------------------------
    // Decode logic
    // ----------------------------------
    always_comb begin

        RDI_msg_no_rcvd_next = sb_rdi_msg_no_e::NOP;
        stall_rcvd_next      = 1'b0;

        if (header.opcode == SB_MSG_WITHOUT_DATA &&
            header.cp == cp_calc) begin

            if (header.msgcode == 8'h02)
                stall_rcvd_next = (header.MsgInfo == 16'hFFFF);

            case ({header.msgcode, header.MsgSubcode})

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
        end
    end

    // --------------------------
    // Sequential
    // --------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RDI_vld_rcvd <= 1'b0; // No valid message on reset
            RDI_msg_no_rcvd <= sb_rdi_msg_no_e::NOP;
            stall_rcvd <= 1'b0;

        end else if(LINK_vld_rcvd) begin

            RDI_msg_no_rcvd <= RDI_msg_no_rcvd_next;
            stall_rcvd <= stall_rcvd_next;
            RDI_vld_out <= (cp == cp_calc); // Indicate that the message is valid and ready to be sent  
        end else begin
            RDI_vld_out <= 1'b0; // No valid message if not sending
        end
    end
   

endmodule