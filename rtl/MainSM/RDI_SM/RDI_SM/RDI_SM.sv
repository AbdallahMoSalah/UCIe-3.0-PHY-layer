import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module RDI_SM #(
    // 8 ms sideband-message handshake timeout (cycles). Default = 8 ms @ 2 GHz.
    parameter int MSG_TIMEOUT_CYCLES = 16_000_000
)(
    //Interface with Adapter
    input  logic                    lclk                ,
    input  logic                    rst_n               ,
    input  logic                    lp_clk_ack          ,
    input  logic                    lp_wake_req         ,
    input  logic                    lp_stallack         ,
    input  RDI_state                lp_state_req        ,
    input  logic                    lp_linkerror        ,

    output logic                    pl_clk_req          ,
    output logic                    pl_stallreq         ,
    output logic                    pl_wake_ack         ,
    output logic                    pl_trainerror       ,
    output logic                    pl_inband_pres      ,
    output logic                    pl_phyinrecenter    ,
    output RDI_state                pl_state_sts        ,
    output logic                    pl_max_speedmode    ,
    output logic [2:0]              pl_speedmode        ,
    output logic [2:0]              pl_lnk_cfg          ,

    //Interface with SB
    input  logic [3:0]              UCIe_Link_DVSEC_UCIe_Link_Capability_7to4   ,
    input  logic [3:0]              UCIe_Link_DVSEC_UCIe_Link_Status_17to11     ,
    input  logic [3:0]              UCIe_Link_DVSEC_UCIe_Link_Status_10to7      ,
    input  msg_no_e                 Link_Mgmt_Msg_Receive                       ,
    input  logic                    valid_r                                      ,
    output msg_no_e                 Link_Mgmt_Msg_Send                          ,
    output logic                    valid_s                                      ,

    input  logic                    traffic_req         ,
    output logic                    clk_handshake_done  ,

    //Interface with MB
    // Clock-gate ENABLE level for the MB TX clock gate (1 = clock on, 0 = gated),
    // driven by the gating FSM (UNGATING => 1, GATING => 0).
    output logic                    lclk_g              ,
    output logic                    stall_done          ,
    input  logic                    mapper_en           ,
    output logic                    stall_done_latched  ,
    input  logic                    pl_error            ,

    //Interface with LTSM
    input  LTSM_state_e             state_sts                                   ,
    // LTSM "start link training" control (asserted while waiting in RESET to
    // begin training); used by the gating FSM to keep the MB clock ungated
    // through the RESET->SBINIT training-start window.
    input  logic                    phy_start_ucie_link_training_ctrl_out       ,
    input  logic                    sticky_sb_pattern_detected,
    // RDI state status forwarded to the LTSM (mirrors the internal
    // wrapper_sm rdi_state_sts so the LTSM can observe the RDI SM state)
    output RDI_state                rdi_state
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // wrapper_sm outputs → consumed internally
    logic           stall_req;
    logic           Active_handshake_strt;
    msg_no_e        message_send;
    logic           trainerror;
    logic           phyinrecenter;
    logic           pm_exit;
    logic           inband_pres;
    RDI_state       rdi_state_sts;

    // wrapper_handshake_logic outputs → consumed internally
    logic           ungating_req;
    logic           Active_handshake_done;
    msg_no_e        Active_message_send;

    // unit_gating_logic outputs → consumed internally
    logic           ungating_done;

    // unit_signal_transition_detector outputs → consumed internally
    logic           signal_transition;

    // unit_msg_handler outputs → consumed internally
    msg_no_e        message_receive;

    // Combinational
    logic           clk_handshake_strt;

    // =========================================================================
    // Submodule Instantiations
    // =========================================================================

    wrapper_sm #(
        .MSG_TIMEOUT_CYCLES (MSG_TIMEOUT_CYCLES)
    ) sm (
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

    wrapper_handshake_logic handshake_logic (
        .lclk                   (lclk),
        .rst_n                  (rst_n),

        // AWAKE Handshake
        .lp_wake_req            (lp_wake_req),
        .ungating_done          (ungating_done),
        .pl_wake_ack            (pl_wake_ack),
        .ungating_req           (ungating_req),

        // STALL Handshake
        .lp_stallack            (lp_stallack),
        .stall_req              (stall_req),
        .mapper_en              (mapper_en),
        .pl_stallreq            (pl_stallreq),
        .stall_done             (stall_done),
        .stall_done_latched     (stall_done_latched),

        // Active Handshake
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

    unit_gating_logic gating_logic (
        .lclk               (lclk),
        .rst_n              (rst_n),
        .inband_pres        (inband_pres),
        .phyinrecenter      (phyinrecenter),
        .pl_clk_req         (pl_clk_req),
        .ungating_req       (ungating_req),
        .phy_start          (phy_start_ucie_link_training_ctrl_out),
        .sticky_sb_pattern_detected (sticky_sb_pattern_detected),
        .pl_state_sts       (pl_state_sts),
        .lclk_g             (lclk_g),
        .ungating_done      (ungating_done)
    );

    unit_signal_transition_detector signal_transition_detector (
        .lclk               (lclk),
        .rst_n              (rst_n),
        .phyinrecenter      (phyinrecenter),
        .inband_pres        (inband_pres),
        .trainerror         (trainerror),
        .clk_handshake_done (clk_handshake_done),
        .rdi_state_sts      (rdi_state_sts),
        .pl_phyinrecenter   (pl_phyinrecenter),
        .pl_inband_pres     (pl_inband_pres),
        .pl_trainerror      (pl_trainerror),
        .signal_transition  (signal_transition),
        .pl_state_sts       (pl_state_sts)
    );

    unit_status_decoder status_decoder (
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4   (UCIe_Link_DVSEC_UCIe_Link_Capability_7to4),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7      (UCIe_Link_DVSEC_UCIe_Link_Status_10to7),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11     (UCIe_Link_DVSEC_UCIe_Link_Status_17to11),
        .pl_lnk_cfg         (pl_lnk_cfg),
        .pl_speedmode       (pl_speedmode),
        .pl_max_speedmode   (pl_max_speedmode)
    );

    unit_msg_handler msg_handler (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .Active_message_send    (Active_message_send),
        .Message_send           (message_send),
        .valid_r                (valid_r),
        .Link_Mgmt_Msg_Received (Link_Mgmt_Msg_Receive),
        .valid_s                (valid_s),
        .Link_Mgmt_Msg_Send     (Link_Mgmt_Msg_Send),
        .Message_receive        (message_receive)
    );

    // clk_handshake_strt: triggered by a signal transition OR an explicit traffic request
    assign clk_handshake_strt = signal_transition || traffic_req;

    // Forward the internal RDI state status out to the LTSM.
    assign rdi_state = rdi_state_sts;

endmodule