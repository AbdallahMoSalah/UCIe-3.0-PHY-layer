import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import UCIe_pkg::*;

module wrapper_sm(
    input  logic           lclk,
    input  logic           rst_n,      // Added rst_n as requested for completeness
    input  LTSM_state_e    state_sts,
    input  logic           pl_error,
    input  logic           lp_linkerror,
    input  RDI_state       lp_state_req,
    input  msg_no_e        message_receive,
    input  logic           Active_handshake_done,
    input  logic           stall_done,
    
    output logic           stall_req,
    output logic           Active_handshake_strt,
    output msg_no_e        message_send,
    output logic           trainerror,
    output logic           phyinrecenter,
    output logic           pm_exit,
    output logic           inband_pres,
    output RDI_state       rdi_state_sts
);

    // --- Internal State Enable Signals ---
    logic Reset_EN, Active_EN, Active_PMNAK_EN, Retrain_EN, L1_EN, L2_EN;
    logic LinkReset_EN, LinkError_EN, Disable_EN;

    // --- Internal Next State Signals ---
    RDI_state Reset_next_state;
    RDI_state Active_next_state;
    RDI_state Active_PMNAK_next_state;
    RDI_state Retrain_next_state;
    RDI_state L1_next_state;
    RDI_state L2_next_state;
    RDI_state LinkReset_next_state;
    RDI_state LinkError_next_state;
    RDI_state Disable_next_state;

    // --- Message Signals from Sub-modules ---
    msg_no_e Reset_message_send;
    msg_no_e Active_message_send;
    msg_no_e Active_PMNAK_message_send;
    msg_no_e Retrain_message_send;
    msg_no_e L1_message_send;
    msg_no_e L2_message_send;
    msg_no_e LinkReset_message_send;

    // --- Handshake and Timeout Signals ---
    logic Reset_Active_handshake_strt;
    logic Retrain_Active_handshake_strt;
    logic L1_Active_handshake_strt;
    logic L2_Active_handshake_strt;
    
    logic Active_stall_req;
    logic Active_PMNAK_stall_req;
    
    logic start_time_16ms;
    logic start_time_1us;
    logic time_16ms;
    logic time_1us;

    // --- Combinational Assignments for Aggregated Signals ---
    assign stall_req = Active_stall_req | Active_PMNAK_stall_req;
    
    assign Active_handshake_strt = Reset_Active_handshake_strt | 
                                   Retrain_Active_handshake_strt | 
                                   L1_Active_handshake_strt | 
                                   L2_Active_handshake_strt;

    // --- Module Instantiations ---

    // Timer Module
    unit_Timer u_unit_Timer (
        .lclk(lclk),
        .rst_n(rst_n),
        .start_time_16ms(start_time_16ms),
        .start_time_1us(start_time_1us),
        .time_16ms(time_16ms),
        .time_1us(time_1us)
    );

    // Reset State Module
    unit_reset_state u_unit_reset_state (
        .lclk(lclk),
        .lp_linkerror(lp_linkerror),
        .Active_handshake_done(Active_handshake_done),
        .EN(Reset_EN),
        .state_sts(state_sts),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .next_state(Reset_next_state),
        .Active_handshake_strt(Reset_Active_handshake_strt),
        .message_send(Reset_message_send)
    );

    // Active State Module
    unit_active_state u_unit_active_state (
        .lclk(lclk),
        .lp_linkerror(lp_linkerror),
        .message_receive(message_receive),
        .stall_done(stall_done),
        .EN(Active_EN),
        .lp_state_req(lp_state_req),
        .rst_n(rst_n),
        .timeout_1us(time_1us),
        .pl_error(pl_error),
        .next_state(Active_next_state),
        .stall_req(Active_stall_req),
        .start_1us_timer(start_time_1us),
        .message_send(Active_message_send)
    );

    // Active PMNAK State Module
    unit_active_pmnak_state u_unit_active_pmnak_state (
        .lclk(lclk),
        .rst_n(rst_n),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .stall_done(stall_done),
        .EN(Active_PMNAK_EN),
        .stall_req(Active_PMNAK_stall_req),
        .message_send(Active_PMNAK_message_send),
        .next_state(Active_PMNAK_next_state)
    );
                                                  
    // Retrain State Module
    unit_retrain_state u_unit_retrain_state ( 
        .lclk(lclk),
        .EN(Retrain_EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .Active_handshake_done(Active_handshake_done),
        .state_sts(state_sts),
        .next_state(Retrain_next_state),
        .Active_handshake_strt(Retrain_Active_handshake_strt),
        .message_send(Retrain_message_send)
    );

    // L1 State Module
    unit_L1_state u_unit_L1_state (
        .lclk(lclk),
        .EN(L1_EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .Active_handshake_done(Active_handshake_done),
        .next_state(L1_next_state),
        .active_handshake_strt(L1_Active_handshake_strt),
        .message_send(L1_message_send)
    );
                            
    // L2 State Module
    unit_L2_state u_unit_L2_state (
        .lclk(lclk),
        .EN(L2_EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .Active_handshake_done(Active_handshake_done),
        .next_state(L2_next_state),
        .active_handshake_strt(L2_Active_handshake_strt),
        .message_send(L2_message_send)
    );
                            
    // LinkReset State Module
    unit_linkreset_state u_unit_linkreset_state ( 
        .lclk(lclk),
        .EN(LinkReset_EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .next_state(LinkReset_next_state),
        .message_send(LinkReset_message_send)
    );
                            
    // LinkError State Module
    unit_linkerror_state u_unit_linkerror_state ( 
        .lclk(lclk),
        .EN(LinkError_EN),
        .lp_linkerror(lp_linkerror),
        .time_16ms(time_16ms),
        .lp_state_req(lp_state_req),
        .start_timer_16ms(start_time_16ms),
        .next_state(LinkError_next_state)
    );

    // Disabled State Module
    unit_disabled_state u_unit_disabled_state ( 
        .lclk(lclk),
        .EN(Disable_EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .next_state(Disable_next_state)
    );
                                            
    // Main Controller Module
    unit_main_controller u_unit_main_controller (
        .lclk(lclk),
        .Reset_next_state(Reset_next_state),
        .LinkError_next_state(LinkError_next_state),
        .Disable_next_state(Disable_next_state),
        .LinkReset_next_state(LinkReset_next_state),
        .Active_next_state(Active_next_state),
        .L1_next_state(L1_next_state),
        .L2_next_state(L2_next_state),
        .Retrain_next_state(Retrain_next_state),
        .Active_PMNAK_next_state(Active_PMNAK_next_state),
        .state_sts(state_sts),
        .Active_EN(Active_EN),
        .L1_EN(L1_EN),
        .L2_EN(L2_EN),
        .Retrain_EN(Retrain_EN),
        .Active_PMNAK_EN(Active_PMNAK_EN),
        .LinkReset_EN(LinkReset_EN),
        .Disable_EN(Disable_EN),
        .Reset_EN(Reset_EN),
        .LinkError_EN(LinkError_EN),
        .trainerror(trainerror),
        .phyinrecenter(phyinrecenter),
        .inband_pres(inband_pres),
        .pm_exit(pm_exit),
        .rdi_state_sts(rdi_state_sts)
    );
                                            
    // Message Send MUX
    unit_message_send_MUX u_unit_message_send_MUX (
        .Reset_message_send(Reset_message_send),
        .Retrain_message_send(Retrain_message_send),
        .Active_message_send(Active_message_send),
        .Active_PMNAK_message_send(Active_PMNAK_message_send),
        .L1_message_send(L1_message_send),
        .L2_message_send(L2_message_send),
        .LinkReset_message_send(LinkReset_message_send),
        .rdi_state_sts(rdi_state_sts),
        .message_send(message_send)
    );

endmodule