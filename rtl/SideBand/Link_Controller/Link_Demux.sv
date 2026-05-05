module LINK_Demux (
    input  logic [127:0] msg_word_rcvd,
    input  logic         word_vld_rcvd,
    output logic [127:0] adapter_msg_rcvd,
    output logic         adapter_vld_rcvd,
    output logic [127:0] trn_msg_rcvd,
    output logic         trn_vld_rcvd
);
import sb_pkg::*;
parameter LINK =0, Adapter =1;
logic msg_dist;

sb_packet_t sb_packet;

always_comb begin
    trn_msg_rcvd = 128'b0;
    trn_vld_rcvd = 1'b0;
    adapter_msg_rcvd = 128'b0;
    adapter_vld_rcvd = 1'b0;
    if(msg_word_rcvd[58:56] == REMOTE_PHY) begin
        msg_dist = LINK;
    end
    else begin
        msg_dist = Adapter;
    end
if (msg_dist == LINK) begin
    trn_msg_rcvd = msg_word_rcvd;
    trn_vld_rcvd = word_vld_rcvd;
end
else if (msg_dist == Adapter) begin
    adapter_msg_rcvd = msg_word_rcvd;
    adapter_vld_rcvd = word_vld_rcvd;
end

// DEBUG
// synthesis translate_off
     sb_packet = msg_word_rcvd; 
if (word_vld_rcvd) begin
    $display("[%0t] [LINK_Demux] Received Message! msg_dist=%0d dstid=%0s msg_word_rcvd[127:64]=%h [63:0]=%s", 
             $time, msg_dist, sb_packet.header.req.dstid, sb_packet.payload, sb_packet.header.req.opcode);
end
// synthesis translate_on

end

endmodule