import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import UCIe_pkg::*;

module wrapper_sm_handshake_logic(
    input  logic           lclk,
    input  logic           rst_n,
    
    // Inputs from SM side
    input  logic           pl_error,
    input  LTSM_state_e    state_sts,
    input  msg_no_e        message_receive,
    input  RDI_state       lp_state_req,
    input  logic           lp_linkerror,
    
    // Outputs from SM side
    output logic           phyinrecenter,
    output msg_no_e        message_send,
    output RDI_state       rdi_state_sts,
    
    // Inputs from Handshake Logic side
    input  logic           ungating_done,
    input  logic           lp_stallack,
    input  logic           lp_awak_req,
    input  logic           clk_handshake_strt,
    input  logic           lp_clk_ack,
    
    // Outputs from Handshake Logic side
    output logic           pl_awak_ack,
    output logic           ungating_req,
    output logic           pl_stallreq,
    output msg_no_e        Active_message_send,
    output logic           pl_clk_req,
    output logic           clk_handshake_done
);

    // Internal signals between SM and Handshake Logic
    logic pm_exit;
    logic trainerror;
    logic inband_pres;
    logic stall_req;
    logic Active_handshake_strt;
    logic stall_done;
    logic Active_handshake_done;

    wrapper_sm sm_inst (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .state_sts              (state_sts),
        .pl_error               (pl_error),
        .lp_linkerror           (lp_linkerror),
        .lp_state_req           (lp_state_req),
        .message_receive        (message_receive),
        .Active_handshake_done  (Active_handshake_done),
        .stall_done             (stall_done),
        
        .stall_req              (stall_req),
        .Active_handshake_strt  (Active_handshake_strt),
        .message_send           (message_send),
        .trainerror             (trainerror),
        .phyinrecenter          (phyinrecenter),
        .pm_exit                (pm_exit),
        .inband_pres            (inband_pres),
        .rdi_state_sts          (rdi_state_sts)
    );

    wrapper_handshake_logic handshake_inst (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        
        // AWAKE Handshake
        .lp_awak_req            (lp_awak_req),
        .ungating_done          (ungating_done),
        .pl_awak_ack            (pl_awak_ack),
        .ungating_req           (ungating_req),
        
        // STALL Handshake
        .lp_stallack            (lp_stallack),
        .stall_req              (stall_req),
        .pl_stallreq            (pl_stallreq),
        .stall_done             (stall_done),
        
        // Active handshake
        .Active_handshake_strt  (Active_handshake_strt),
        .message_receive        (message_receive),
        .pm_exit                (pm_exit),
        .inband_pres            (inband_pres),
        .Active_handshake_done  (Active_handshake_done),
        .Active_message_send    (Active_message_send),

        // CLK Handshake
        .clk_handshake_strt     (clk_handshake_strt),
        .lp_clk_ack             (lp_clk_ack),
        .pl_clk_req             (pl_clk_req),
        .clk_handshake_done     (clk_handshake_done)
    );

endmodule
