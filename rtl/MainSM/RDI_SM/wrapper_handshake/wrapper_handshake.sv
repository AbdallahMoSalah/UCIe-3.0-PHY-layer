module wrapper_handshake(
    input logic lp_clk_ack, lp_awak_req, lp_stallack, lclk, clk_handshake_strt, ungating_done,
                stall_req, signal_transition, traffic_req,
    output logic pl_clk_req, pl_awak_ack, pl_stallreq, ungating_req, stall_done, 
                 clk_handshake_done
);

    unit_clk_handshake u1 (
        .lp_clk_ack(lp_clk_ack),
        .clk_handshake_strt(clk_handshake_strt | signal_transition | traffic_req),
        .lclk(lclk),
        .pl_clk_req(pl_clk_req),
        .clk_handshake_done(clk_handshake_done)
    );

    unit_awak_handshake u2 (
        .lp_awak_req(lp_awak_req),
        .ungating_done(ungating_done),
        .lclk(lclk),
        .pl_awak_ack(pl_awak_ack),
        .ungating_req(ungating_req)
    );

    unit_stall_handshake u3 (
        .lp_stallack(lp_stallack),
        .lclk(lclk),
        .stall_req(stall_req), 
        .pl_stallreq(pl_stallreq),
        .stall_done(stall_done)
    );
endmodule