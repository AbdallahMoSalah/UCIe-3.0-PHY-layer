module LINK_Demux (
    input  logic [127:0] msg_word_rcvd,
    input  logic         word_vld_rcvd,
    output logic [127:0] Adapter_msg_rcvd,
    output logic         Adapter_vld_rcvd,
    output logic [127:0] Link_msg_rcvd,
    output logic         Link_vld_rcvd
);
import sb_pkg::*;
parameter LINK =0, Adapter =1;
logic msg_dist;

always_comb begin
    Link_msg_rcvd = 128'b0;
    Link_vld_rcvd = 1'b0;
    Adapter_msg_rcvd = 128'b0;
    Adapter_vld_rcvd = 1'b0;
    if(msg_word_rcvd[58:56] == REMOTE_PHY) begin
        msg_dist = LINK;
    end
    else begin
        msg_dist = Adapter;
    end
if (msg_dist == LINK) begin
    Link_msg_rcvd = msg_word_rcvd;
    Link_vld_rcvd = word_vld_rcvd;
end
else if (msg_dist == Adapter) begin
    Adapter_msg_rcvd = msg_word_rcvd;
    Adapter_vld_rcvd = word_vld_rcvd;
end
end

endmodule