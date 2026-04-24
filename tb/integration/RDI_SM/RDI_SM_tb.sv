`timescale 1ns/1ps

import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module RDI_SM_tb;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic        lclk;
    logic        rst_n;

    // =========================================================================
    // DUT Inputs — Adapter Interface
    // =========================================================================
    logic        lp_clk_ack;
    logic        lp_awak_req;
    logic        lp_stallack;
    RDI_state    lp_state_req;
    logic        lp_linkerror;

    // =========================================================================
    // DUT Outputs — Adapter Interface
    // =========================================================================
    logic        pl_clk_req;
    logic        pl_stallreq;
    logic        pl_awak_ack;
    logic        pl_trainerror;
    logic        pl_inband_pres;
    logic        pl_phyinrecenter;
    RDI_state    pl_state_sts;
    logic        pl_max_speedmode;
    logic [2:0]  pl_speedmode;
    logic [2:0]  pl_lnk_cfg;

    // =========================================================================
    // DUT Inputs / Outputs — Sideband Interface
    // =========================================================================
    logic [3:0]  UCIe_Link_DVSEC_UCIe_Link_Capability_7to4;
    logic [3:0]  UCIe_Link_DVSEC_UCIe_Link_Status_17to11;
    logic [3:0]  UCIe_Link_DVSEC_UCIe_Link_Status_10to7;
    msg_no_e     Link_Mgmt_Msg_Receive;
    logic        valid_r;
    msg_no_e     Link_Mgmt_Msg_Send;
    logic        valid_s;

    // =========================================================================
    // DUT Inputs / Outputs — Misc
    // =========================================================================
    logic        traffic_req;
    logic        clk_handshake_done;

    // =========================================================================
    // DUT Outputs — Macro-Block Interface
    // =========================================================================
    logic        lclk_g;
    logic        stall_done;
    logic        pl_error;

    // =========================================================================
    // DUT Input — LTSM Interface
    // =========================================================================
    LTSM_state_e state_sts;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    RDI_SM dut (
        // Adapter
        .lclk                                           (lclk),
        .rst_n                                          (rst_n),
        .lp_clk_ack                                     (lp_clk_ack),
        .lp_awak_req                                    (lp_awak_req),
        .lp_stallack                                    (lp_stallack),
        .lp_state_req                                   (lp_state_req),
        .lp_linkerror                                   (lp_linkerror),
        .pl_clk_req                                     (pl_clk_req),
        .pl_stallreq                                    (pl_stallreq),
        .pl_awak_ack                                    (pl_awak_ack),
        .pl_trainerror                                  (pl_trainerror),
        .pl_inband_pres                                 (pl_inband_pres),
        .pl_phyinrecenter                               (pl_phyinrecenter),
        .pl_state_sts                                   (pl_state_sts),
        .pl_max_speedmode                               (pl_max_speedmode),
        .pl_speedmode                                   (pl_speedmode),
        .pl_lnk_cfg                                     (pl_lnk_cfg),

        // Sideband
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4     (UCIe_Link_DVSEC_UCIe_Link_Capability_7to4),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11        (UCIe_Link_DVSEC_UCIe_Link_Status_17to11),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7         (UCIe_Link_DVSEC_UCIe_Link_Status_10to7),
        .Link_Mgmt_Msg_Receive                          (Link_Mgmt_Msg_Receive),
        .valid_r                                        (valid_r),
        .Link_Mgmt_Msg_Send                             (Link_Mgmt_Msg_Send),
        .valid_s                                        (valid_s),

        // Misc
        .traffic_req                                    (traffic_req),
        .clk_handshake_done                             (clk_handshake_done),

        // Macro-Block
        .lclk_g                                         (lclk_g),
        .stall_done                                     (stall_done),
        .pl_error                                       (pl_error),

        // LTSM
        .state_sts                                      (state_sts)
    );

    // =========================================================================
    // Clock Generation — 500 MHz (2 ns period)
    // =========================================================================
    initial lclk = 0;
    always #1 lclk = ~lclk;

    // =========================================================================
    // Reset Task
    // =========================================================================
    task apply_reset();
        rst_n = 1'b0;
        repeat(4) @(negedge lclk);
        rst_n = 1'b1;
        @(posedge lclk);
    endtask

    // =========================================================================
    // Input Initialization
    // =========================================================================
    task init_inputs();
        lp_clk_ack                              = 1'b0;
        lp_awak_req                             = 1'b0;
        lp_stallack                             = 1'b0;
        lp_state_req                            = Reset;        // RDI_state reset value
        lp_linkerror                            = 1'b0;
        pl_error                                = 1'b0;
        traffic_req                             = 1'b0;
        valid_r                                 = 1'b0;
        Link_Mgmt_Msg_Receive                   = NOP;
        state_sts                               = RESET;   // LTSM_state_e reset value
        UCIe_Link_DVSEC_UCIe_Link_Capability_7to4  = 4'h0;
        UCIe_Link_DVSEC_UCIe_Link_Status_17to11    = 4'h0;
        UCIe_Link_DVSEC_UCIe_Link_Status_10to7     = 4'h0;
    endtask
    
    //==========================================================================
    //Task for checking clk handshake
    // =========================================================================
    task check_clk_handshake();
        fork
            begin
                wait(pl_clk_req);
                $display("clk handshake starts correctly");
                
                @(negedge lclk);
                lp_clk_ack = 1'b1;//sending the ack to complete the handshake
                
                wait(~pl_clk_req);
                @(negedge lclk);
                lp_clk_ack = 1'b0;//removing the ack to indicate the completion of handshake
                $display("clk handshake done correctly");
            end
            begin
                repeat(20) @(negedge lclk);
                $error("clk handshake not done correctly");
            end
        join_any
        disable fork;
    endtask
    
    //==========================================================================
    //Task for checking clk handshake
    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        init_inputs();
        apply_reset();

        // Let system settle after reset
        repeat(4) @(posedge lclk);

        $display("\n========================================");
        $display("RDI_SM integration TB initialized");
        $display("========================================\n");
        
        // ==========================================================================
        // ========================= Test 1 :Bring up link ==========================
        // ==========================================================================
        $display("=========================================================================");
        $display("======================== Link bring up starts ===========================");
        $display("=========================================================================");
            
            //a. awak handshake first
            lp_awak_req = 1'b1;
            fork
                begin
                    wait(pl_awak_ack);
                    lp_awak_req = 1'b0;
                end
                begin
                    repeat(20) @(negedge lclk);
                    $error("lp_clk_ack not received");

                end
            join_any
            disable fork;

            //b. lp stateReq to active
            lp_state_req = Active;
            @(posedge lclk);
            state_sts = SBINIT;
            fork
                begin
                    wait(pl_clk_req);
                    $display("clk handshake starts correctly");
                    lp_clk_ack = 1'b1;
                    wait(~pl_clk_req && pl_phyinrecenter);
                    lp_clk_ack = 1'b0;
                    $display("clk handshake done correctly and pl_phyinrecenter is high");
                end
                begin
                    repeat(30) @(negedge lclk);
                    $error("clk handshake not done correctly or pl_phyinrecenter is low ");
                end
            join_any
            disable fork;
            
            //c. Training is done, check for pl_inband_pres
            @(negedge lclk);
            $display("Time=%0t: Training is done, wait for pl_inband_pres to be high", $time);
            state_sts=LINKINIT;
            
            check_clk_handshake();//clk handshake check
            
            fork
                begin
                    wait(pl_inband_pres);
                    $display("pl_inband_pres is high, success");
                end
                begin 
                    repeat(20)@(negedge lclk);
                    $error("pl_inband_pres is low, failure");
                end
            join_any
            disable fork;

            //d. NOP to Active transition
            $display("Time=%0t: NOP to Active transition, wait for Active handshake", $time);
            @(negedge lclk);
            lp_state_req = Nop;
            @(negedge lclk) 
            lp_state_req =Active;
            fork
                begin
                    wait (Link_Mgmt_Msg_Send == RDI_ACTIVE_REQ); //request is sent
                    $display("Active handshake is started successfully, Active req sent");
                    wait(Link_Mgmt_Msg_Send == NOP);
                    @(negedge lclk);
                    Link_Mgmt_Msg_Receive = RDI_ACTIVE_RSP;//response is recieved
                    valid_r = 1'b1;
                    $display("Active response is recieved");
                    @(negedge lclk);
                    Link_Mgmt_Msg_Receive = NOP;
                    valid_r = 1'b0;
                    @(negedge lclk);
                    Link_Mgmt_Msg_Receive = RDI_ACTIVE_REQ;//request is recieved
                    valid_r = 1'b1;
                    $display("Active req is recieved");
                    @(negedge lclk);
                    Link_Mgmt_Msg_Receive = NOP;//request is removed
                    valid_r = 1'b0;

                    wait (Link_Mgmt_Msg_Send == RDI_ACTIVE_RSP);//response is sent
                    $display("Active response is sent");
                    @(negedge lclk);

                    wait(dut.handshake_logic.Active_handshake_done == 1'b1)
                    $display("Active handshake is done successfully");                
                end

                begin
                    repeat(10) @(negedge lclk);
                    $error("Active Handshake not completed successfully"); 
                end    
            join_any
            disable fork;
            
            //e. check for clk handshake then, check for state of the RDI_SM is Active
            check_clk_handshake();//clk handshake check
            fork
                begin
                    wait(pl_state_sts == Active);
                    $display("State is Active, success");
                    $display("=========================================================================");
            $display("================== Link bring up is done successfully ===================");
            $display("=========================================================================");
            $display("                                 =======   ");
            $display("                                | ^   ^ |  ");
            $display("                                |   =   |  ");
            $display("                                | \\___/ |  ");
            $display("                                 =======   ");
            $display("                          TEST PASSED, War is ended ^_^    ");
                end
                begin 
                    repeat(20)@(posedge lclk);
                    $error("State is not Active ");

                end
            join_any
            disable fork;
            
            repeat(20) @(posedge lclk);
            $display("Simulation complete.");
            $stop;
        end

endmodule
