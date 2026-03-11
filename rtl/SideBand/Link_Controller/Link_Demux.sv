module LINK_Demux (
    input  logic [127:0] msg_word_rcvd,
    input  logic         word_valid_r,
    output logic [127:0] Adapter_msg_rcvd,
    output logic         Adapter_valid_r,
    output logic [127:0] LINK_msg_rcvd,
    output logic         LINK_valid_r
);
import sb_pkg::*;
parameter LINK =0, Adapter =1;
logic msg_dist;

always_comb begin
    LINK_msg_rcvd = 128'b0;
    LINK_valid_r = 1'b0;
    Adapter_msg_rcvd = 128'b0;
    Adapter_valid_r = 1'b0;
    if(msg_word_rcvd[58:56] == REMOTE_PHY) begin
        msg_dist = LINK;
    end
    else begin
        msg_dist = Adapter;
    end
if (msg_dist == LINK) begin
    LINK_msg_rcvd = msg_word_rcvd;
    LINK_valid_r = word_valid_r;
end
else if (msg_dist == Adapter) begin
    Adapter_msg_rcvd = msg_word_rcvd;
    Adapter_valid_r = word_valid_r;
end
end

endmodule