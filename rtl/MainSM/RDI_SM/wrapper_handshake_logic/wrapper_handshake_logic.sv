import UCIe_pkg::*;

module wrapper_handshake_logic(
    input  logic lclk,
    input  logic rst_n,
    // AWAKE Handshake
    input  logic lp_wake_req,
    input  logic ungating_done,
    output logic pl_wake_ack,
    output logic ungating_req,
    
    // STALL Handshake
    input  logic lp_stallack,
    input  logic stall_req,
    output logic pl_stallreq,
    output logic stall_done,
    
    // Active handshake
    input  logic Active_handshake_strt,
    input  msg_no_e message_receive,
    input  logic pm_exit,
    input  logic inband_pres,
    output logic Active_handshake_done,
    output msg_no_e Active_message_send,

    // CLK Handshake
    input  logic clk_handshake_strt,
    input  logic lp_clk_ack,
    output logic pl_clk_req,
    output logic clk_handshake_done
);

    unit_clk_handshake u1 (
        .lp_clk_ack(lp_clk_ack),
        .clk_handshake_strt(clk_handshake_strt),
        .lclk(lclk),
        .rst_n(rst_n),
        .pl_clk_req(pl_clk_req),
        .clk_handshake_done(clk_handshake_done)
    );

    unit_awak_handshake u2 (
        .lp_wake_req(lp_wake_req),
        .ungating_done(ungating_done),
        .lclk(lclk),
        .rst_n(rst_n),
        .pl_wake_ack(pl_wake_ack),
        .ungating_req(ungating_req)
    );

    unit_stall_handshake u3 (
        .lp_stallack(lp_stallack),
        .lclk(lclk),
        .rst_n(rst_n),
        .stall_req(stall_req), 
        .pl_stallreq(pl_stallreq),
        .stall_done(stall_done)
    );

    unit_active_handshake u4 (
        .lclk(lclk),
        .rst_n(rst_n),
        .pm_exit(pm_exit),
        .message_receive(message_receive),
        .active_handshake_strt(Active_handshake_strt),
        .inband_pres(inband_pres),
        .active_message_send(Active_message_send),
        .active_handshake_done(Active_handshake_done)
    );

endmodule