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
    // Clock Generation — 2 GHz (500 ps period)
    // =========================================================================
    initial lclk = 0; //lclk generation of 2GHz, period 500ps
    always #0.25 lclk = ~lclk;

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
    //Task for recieving messages from SB
    // =========================================================================
    typedef enum logic [3:0] { active_req,
                               active_rsp,
                               l1_req,
                               l1_rsp,
                               l2_req,
                               l2_rsp,
                               linkreset_req,
                               linkreset_rsp,
                               linkerror_req,
                               linkerror_rsp,
                               retrain_req,
                               retrain_rsp,
                               disable_req,
                               disable_rsp,
                               pm_nak_rsp,
                               nop} Msg_e;
    task receive_sb_msg( input Msg_e  msg);
        @(negedge lclk);
        case (msg)
            active_req: begin
                Link_Mgmt_Msg_Receive = RDI_ACTIVE_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            active_rsp: begin
                Link_Mgmt_Msg_Receive = RDI_ACTIVE_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            l1_req : begin 
                Link_Mgmt_Msg_Receive = RDI_L1_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end 

            l1_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_L1_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            l2_req : begin
                Link_Mgmt_Msg_Receive = RDI_L2_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            l2_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_L2_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            linkreset_req : begin
                Link_Mgmt_Msg_Receive = RDI_LINK_RESET_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            linkreset_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_LINK_RESET_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            linkerror_req : begin
                Link_Mgmt_Msg_Receive = RDI_LINK_ERROR_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            linkerror_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_LINK_ERROR_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            retrain_req : begin
                Link_Mgmt_Msg_Receive = RDI_RETRAIN_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            retrain_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_RETRAIN_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            disable_req : begin
                Link_Mgmt_Msg_Receive = RDI_DISABLE_REQ;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            disable_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_DISABLE_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            pm_nak_rsp : begin
                Link_Mgmt_Msg_Receive = RDI_PMNAK_RSP;
                valid_r = 1'b1;
                @(negedge lclk);
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end

            nop : begin
                Link_Mgmt_Msg_Receive = NOP;
                valid_r = 1'b0;
            end 

            default : begin
                $error("Invalid message received");
            end
        endcase
    endtask
    
    //==========================================================================
    //Task for checking the sent message 
    //==========================================================================
    task check_sb_msg(input Msg_e msg, input int timeout = 20);
        msg_no_e r_msg;
        case(msg)
            active_req : r_msg = RDI_ACTIVE_REQ;
            active_rsp : r_msg = RDI_ACTIVE_RSP;
            l1_req : r_msg = RDI_L1_REQ;
            l1_rsp : r_msg = RDI_L1_RSP;
            l2_req : r_msg = RDI_L2_REQ;
            l2_rsp : r_msg = RDI_L2_RSP;
            linkreset_req : r_msg = RDI_LINK_RESET_REQ;
            linkreset_rsp : r_msg = RDI_LINK_RESET_RSP;
            linkerror_req : r_msg = RDI_LINK_ERROR_REQ;
            linkerror_rsp : r_msg = RDI_LINK_ERROR_RSP;
            retrain_req : r_msg = RDI_RETRAIN_REQ;
            retrain_rsp : r_msg = RDI_RETRAIN_RSP;
            disable_req : r_msg = RDI_DISABLE_REQ;
            disable_rsp : r_msg = RDI_DISABLE_RSP;
            pm_nak_rsp : r_msg = RDI_PMNAK_RSP;
            nop : r_msg = NOP;
        endcase
        fork
            begin
                wait(Link_Mgmt_Msg_Send == r_msg);
                $display("%s message sent correctly", msg.name());
            end
            begin
                repeat(timeout) @(negedge lclk);
                $error("%s message not sent correctly", msg.name());
            end
        join_any
        disable fork;
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
    //Task for checking stall handshake
    // =========================================================================
    task check_stall_handshake();
        fork
            begin
                wait(pl_stallreq);
                $display("stall handshake starts correctly");
                
                @(negedge lclk);
                lp_stallack = 1'b1;//sending the ack to complete the handshake
                
                wait(~pl_stallreq);
                @(negedge lclk);
                lp_stallack = 1'b0;//removing the ack to indicate the completion of handshake
                $display("stall handshake done correctly");
            end
            begin
                repeat(20) @(negedge lclk);
                $error("stall handshake not done correctly");
            end
        join_any
        disable fork;
    endtask
    //==========================================================================
    //Task for checking awak handshake
    // =========================================================================
    task check_awak_handshake();
        @(negedge lclk);
        lp_awak_req = 1'b1;//sending the request to complete the handshake
        fork
            begin
                wait(pl_awak_ack);
                $display("awak handshake starts correctly");
            end
            begin
                repeat(20) @(negedge lclk);
                $error("pl_awak_ack not received");
            end
        join_any
        disable fork;

        @(negedge lclk);
        lp_awak_req = 1'b0;//removing the ack to indicate the completion of handshake
        fork
            begin
                wait(~pl_awak_ack);
                $display("awak handshake done correctly");
            end
            begin
                repeat(20) @(negedge lclk);
                $error("lp_clk_ack not received");
            end
        join_any
        disable fork;
    endtask
    
    //==========================================================================
    //Task for bring up flow
    // =========================================================================
    task bringup_flow();
            //a. awak handshake
            check_awak_handshake();

            //b. lp stateReq to active then check for clk handshake
            lp_state_req = Active;
            @(posedge lclk);
            state_sts = SBINIT;
            check_clk_handshake();
            
            //c. check for pl_phyinrecenter
             fork
                 begin
                     wait(pl_phyinrecenter);
                     $display("pl_phyinrecenter is high, success");
                 end
                 begin 
                     repeat(20)@(negedge lclk);
                     $error("pl_phyinrecenter is low, failure");
                 end
             join_any
             disable fork;

            //d. Training is done, check for pl_inband_pres
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

            //e. NOP to Active transition
            $display("Time=%0t: NOP to Active transition, wait for Active handshake", $time);
            @(negedge lclk);
            lp_state_req = Nop;
            @(negedge lclk) 
            lp_state_req =Active;
            check_sb_msg(active_req);  
            wait(Link_Mgmt_Msg_Send == NOP);

            //receive active response and request
            receive_sb_msg(active_rsp);
            receive_sb_msg(active_req);

            //check active response
            check_sb_msg(active_rsp);
            
            //f. check for clk handshake then, check for state of the RDI_SM is Active
            check_clk_handshake();//clk handshake check
            fork
                begin
                    wait(pl_state_sts == Active);
                    $display("State is Active, success");
                    state_sts = ACTIVE; //set state to active
                    $display("=========================================================================");
                    $display("================== Link bring up is done successfully ===================");
                    $display("=========================================================================");
                    $display("                                 =======   ");
                    $display("                                | ^   ^ |  ");
                    $display("                                |   =   |  ");
                    $display("                                | \\___/ |  ");
                    $display("                                 =======   ");
                    $display("               Bring up flow PASSED, 1st War is ended ^_^    \n ");
                end
                begin 
                    repeat(20)@(posedge lclk);
                    $error("State is not Active ");

                end
            join_any
            disable fork;
            
            #30;

    endtask
    //=====================================================================
    //=================task for L1_entry flow
    //=====================================================================
    task L1_entry();
      //A. Partner die requests PM Entry thruogh SB
              receive_sb_msg(l1_req);

              //B. Wait for lp_state_req to be L1 (for 10 clk cycles) then check for stall handshake
              repeat (10) @(negedge lclk);
              lp_state_req = L_1;
              check_stall_handshake();

              //C. check for RDI_L1_REQ and RDI_L1_RSP are sent
              check_sb_msg(l1_req);
              check_sb_msg(l1_rsp);
              //D. Wait for RDI state to be L1 after clk handshake is done successfully
              receive_sb_msg(l1_rsp);
              check_clk_handshake();//clk handshake check
              fork
                  begin
                      wait(pl_state_sts == L_1);
                      $display("pl_state_sts is L1");
                      $display("Case 2 ends successfully ^_^ \n");

                      $display("=========================================================================");
                      $display("================== PM (L1) flow is done successfully ====================");
                      $display("=========================================================================");
                      $display("                                 =======   ");
                      $display("                                | ^   ^ |  ");
                      $display("                                |   =   |  ");
                      $display("                                | \\___/ |  ");
                      $display("                                 =======   ");
                      $display("               PM (L1) flow PASSED, 1st War is ended ^_^    \n ");
                  end
                  begin
                      repeat(10) @(negedge lclk);
                      $error("pl_state_sts is not L1");
                  end
              join_any
              disable fork;
    endtask
  
    //==========================================================================
    //==========================================================================
    //======================                      ==============================
    //======================     Test Sequence    ==============================
    //======================                      ==============================
    //==========================================================================
    //==========================================================================

    initial begin
        //initailization and resetting the design
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
            
        bringup_flow();

        #30;
        
        //==========================================================================
        //======================== Test 2 :PM (L1) Entry by the partner============= 
        //========================================================================== 
        $display("\n=========================================================================");
        $display("========================= PM (L1) Entry by Partner  =========================");
        $display("=========================================================================\n");
            
        //Case 1: Partner die requests PM Entry through SB but local can't enter PM (PMNAK)
        $display("-----------Case 1: Partner die requests PM Entry through SB but local refused-------------");
        
        //A. Partner die requests PM Entry thruogh SB
        receive_sb_msg(l1_req);

        //B. Wait till RDI_PMNAK_RSP is sent
        check_sb_msg(pm_nak_rsp, 2005);
            
        //C. Check RDI state is still Active
        fork
            begin
                wait(pl_state_sts != Active);
                $error("RDI state is not Active");
            end
            begin
                repeat(5) @(negedge lclk);
                $display("RDI state is still Active, success");
                $display("Case 1 ends successfully ^_^");
            end
        join_any
        disable fork;

        //Test 2: Partner die requests PM Entry through SB and local enters PM (L1)
        $display("-----------Case 2: Partner die requests PM Entry through SB and local enters PM (L1)-------------");
        L1_entry;
            
        
        //================================================================================================
        //=============================Test 3 : PM L2 Entry ==============================================
        //================================================================================================
        $display
            
            repeat(20) @(posedge lclk);
            $display("Simulation complete.");
            $stop;
        end

endmodule
