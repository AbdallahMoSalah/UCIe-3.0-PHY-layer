`timescale 1ns/1ps

import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import UCIe_pkg::*;

module wrapper_sm_tb;

    // --- Signals ---
    logic           lclk;
    logic           rst_n;
    LTSM_state_e    state_sts;
    logic           pl_error;
    logic           lp_linkerror;
    RDI_state       lp_state_req;
    msg_no_e        message_receive;
    logic           Active_handshake_done;
    logic           stall_done;
    
    logic           stall_req;
    logic           Active_handshake_strt;
    msg_no_e        message_send;
    logic           trainerror;
    logic           phyinrecenter;
    logic           pm_exit;
    logic           inband_pres;
    RDI_state       rdi_state_sts;

    // --- Clock Generation (2GHz -> 500ps period) ---
    always #0.25 lclk = ~lclk;

    // --- Device Under Test ---
    wrapper_sm dut (
        .lclk(lclk),
        .rst_n(rst_n),
        .state_sts(state_sts),
        .pl_error(pl_error),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .Active_handshake_done(Active_handshake_done),
        .stall_done(stall_done),
        .stall_req(stall_req),
        .Active_handshake_strt(Active_handshake_strt),
        .message_send(message_send),
        .trainerror(trainerror),
        .phyinrecenter(phyinrecenter),
        .pm_exit(pm_exit),
        .inband_pres(inband_pres),
        .rdi_state_sts(rdi_state_sts)
    );

    task Recive_req(input RDI_state message);
        @(negedge lclk);
        case (message)
            Active: message_receive=RDI_ACTIVE_REQ;
            LinkReset:message_receive=RDI_LINK_RESET_REQ;
            LinkError:message_receive=RDI_LINK_ERROR_REQ;
            L_1:message_receive=RDI_L1_REQ;
            L_2:message_receive=RDI_L2_REQ;
            Retrain:message_receive=RDI_RETRAIN_REQ;
            Disabled:message_receive=RDI_DISABLE_REQ;
            default: begin
                $error("Invalid message passed to Recive_req: %s", message.name());
                message_receive = NOP;
            end
        endcase
        @(negedge lclk);
        $display("[%t] %s Recived. Success!", $time, message_receive.name());
        message_receive=NOP;
    endtask

    task Recive_rsp(input RDI_state message);
        @(negedge lclk);
        case (message)
            Active: message_receive=RDI_ACTIVE_RSP;
            LinkReset:message_receive=RDI_LINK_RESET_RSP;
            LinkError:message_receive=RDI_LINK_ERROR_RSP;
            L_1:message_receive=RDI_L1_RSP;
            L_2:message_receive=RDI_L2_RSP;
            Retrain:message_receive=RDI_RETRAIN_RSP;
            Disabled:message_receive=RDI_DISABLE_RSP;
            Active_PMNAK:message_receive=RDI_PMNAK_RSP;
            default: begin
                $error("Invalid message passed to Recive_rsp: %s", message.name());
                message_receive = NOP;
            end
        endcase
        @(negedge lclk);
        $display("[%t] %s Recived. Success!", $time, message_receive.name());
        message_receive=NOP;
    endtask
    
    task active_hs_done;
        @(negedge lclk);
        Active_handshake_done=1;
        @(negedge lclk);
        Active_handshake_done=0;
    endtask

    task Stall_Done;
        @(negedge lclk);
        stall_done=1;
        @(negedge lclk);
        stall_done=0;
    endtask
    
    task reset ;
    begin
        @(negedge lclk);
        rst_n = 0;
        @(negedge lclk);
        rst_n = 1;
    end
    endtask

    task nop_to_active();
        @(negedge lclk);
        lp_state_req = Nop;
        @(negedge lclk);
        lp_state_req = Active;
    endtask

    task reset2active;
    begin
       // 1. Request Active from Adapter
        @(negedge lclk);
        lp_state_req = Active;

        // 2. Simulate LINKINIT state from Link Training State Machine
        @(negedge lclk);
        state_sts = SBINIT;
        @(negedge lclk);
        state_sts = MBINIT;
        @(negedge lclk);
        state_sts = MBTRAIN;
        @(negedge lclk);
        state_sts = LINKINIT;

        //3. Transatction Nop->Active
        nop_to_active();

        // 4. Move through Handshake logic
        fork
            begin
                wait(Active_handshake_strt);
                $display("[%0t] Active Handshake Started.", $time);
            end

            begin
                repeat(5)
                    @(negedge lclk);
                $error("[%0t] Timeout, Active Handshake not started. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;
        active_hs_done();
        $display("[%0t] Active Handshake Done.", $time);

        // 5. Wait for transition in Main Controller
        fork
            begin
                wait(rdi_state_sts == Active);
                @(negedge lclk);
                state_sts = ACTIVE;
                $display("[%0t] Transitioned to Active. Success!", $time);
            end
            begin
                repeat(5)
                    @(negedge lclk);    
                $error("[%0t] Timeout, Active not transitioned. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;
        #20; 
    end
    endtask
    
    // --- Test Stimulus ---
    initial begin
        // Initialize inputs
        lclk = 0;
        rst_n = 0;
        state_sts = RESET;
        pl_error = 0;
        lp_linkerror = 0;
        lp_state_req = Reset;
        message_receive = NOP;
        Active_handshake_done = 0;
        stall_done = 0;

        // Reset Sequence
        reset();
        $display("[%0t] Reset released. Current RDI State: %s", $time, rdi_state_sts.name());
        
        //==============================================================================
        //===========Test scenario :Transition from Reset to LinkError state======================== 
        //==============================================================================

        //=============================================================================
        // ========== Test scenario :Transition from Reset to LinkReset state======================== 
        //=============================================================================
        
        
        //===========================================================================================
        // ==========Test scenario 4: Transition from Reset to Disabled State======================== 
        //===========================================================================================
        //1.Transaction of NOP -> Disabled
        @(negedge lclk);
        lp_state_req = Nop;
        @(negedge lclk);
        lp_state_req = Disabled;
        
        //2.Send RDI_DISABLE_REQ
        fork
            begin
                wait(message_send == RDI_DISABLE_REQ);
                Recive_rsp(Disabled);
                $display("[%0t] RDI_DISABLE_REQ sent. Success!", $time);
            end
            begin
                repeat(5)
                    @(negedge lclk);
                $error("[%0t] Timeout, RDI_DISABLE_REQ not sent. Failure!", $time);
                $stop;
            end        
        join_any;
        disable fork;

        //3. Wait for transition in Main Controller
        fork
            begin
                wait(rdi_state_sts == Disabled);
                @(negedge lclk);
                state_sts = TRAINERROR;
                $display("[%0t] Transitioned to Disabled. Success!", $time);
            end
            begin
                repeat(5)
                    @(negedge lclk);    
                $error("[%0t] Timeout, Disabled not transitioned. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;
        reset();
        
        //=============================================================================
        // ========== Test Scenario 1: Transition from Reset to Active State ==========
        //=============================================================================

        // 1. Request Active from Adapter
        @(negedge lclk);
        lp_state_req = Active;

        // 2. Simulate LINKINIT state from Link Training State Machine
        @(negedge lclk);
        state_sts = SBINIT;
        @(negedge lclk);
        state_sts = MBINIT;
        @(negedge lclk);
        state_sts = MBTRAIN;
        @(negedge lclk);
        state_sts = LINKINIT;

        //3. Transatction Nop->Active
        nop_to_active();

        // 4. Move through Handshake logic
        fork
            begin
                wait(Active_handshake_strt);
                $display("[%0t] Active Handshake Started.", $time);
            end

            begin
                repeat(5)
                    @(negedge lclk);
                $error("[%0t] Timeout, Active Handshake not started. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;
        active_hs_done();
        $display("[%0t] Active Handshake Done.", $time);

        // 5. Wait for transition in Main Controller
        fork
            begin
                wait(rdi_state_sts == Active);
                @(negedge lclk);
                state_sts = ACTIVE;
                $display("[%0t] Transitioned to Active. Success!", $time);
            end
            begin
                repeat(5)
                    @(negedge lclk);    
                $error("[%0t] Timeout, Active not transitioned. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;
        #20;

        //===========================================================================================
        // ==========Test scenario 2: Trainsitoin from Active to Linkerror vai lp_linkerror========== 
        //===========================================================================================

        // 1. assert lp_linkerror
        @(negedge lclk);
        lp_linkerror = 1;

        // 2.Send RDI_LINK_ERROR_REQ
        fork 
            begin
                wait(message_send == RDI_LINK_ERROR_REQ);
                @(negedge lclk);
                Recive_rsp(LinkError);
            end 
            begin
                repeat(5)
                    @(negedge lclk);    
                $error("[%0t] Timeout, RDI_LINK_ERROR_REQ not sent. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;

        // 3. Wait for transition in Main Controller
        fork
            begin
                wait(rdi_state_sts == LinkError);
                @(negedge lclk);
                state_sts = TRAINERROR;
                $display("[%0t] Transitioned to LinkError. Success!", $time);
            end
            begin
                repeat(5)
                    @(negedge lclk);    
                $error("[%0t] Timeout, LinkError not transitioned. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;

        //===========================================================================================
        // ==========Test scenario 3: Transition from Linkerror to Reset state ========== 
        //===========================================================================================
        
        //1.deassert lp_linkerror
        @(negedge lclk);
        lp_linkerror = 0;
        @(negedge lclk);
        lp_state_req = Active;

        // 2. wait for 16 ms timer
        fork 
            begin
                wait(dut.time_16ms);
                $display("[%0t] 16ms timer is expired. Success!", $time);
            end

            begin
                while (rdi_state_sts != Reset) begin
                    @(negedge lclk);
                end
                $error("[%0t] Transtion to Reset is done before timer is expired. Failure!", $time);
                $stop;
            end

            begin
                #16_000_000;//16ms  
                $error("[%0t] Timeout, 16ms timer is not expired. Failure!", $time);
                $stop;
            end
        join_any;
        disable fork;

        //5. transition to reset state
        fork
            begin
                wait (rdi_state_sts == Reset);
                $display("Transitioned to Reset. Success!");
                @(negedge lclk);
                state_sts = RESET;
            end
            begin
                repeat (100) @(negedge lclk);
                $error("Timeout reached, Transition to Reset Failed!");
                $stop;
            end
        join_any;
        disable fork;        
        
        //===========================================================================================
        // ==========Test scenario 5: Transition from Disabled to Reset State======================== 
        //===========================================================================================
        
        //1.Transition form Disabled to Reset
        @(negedge lclk);
        lp_state_req=Active;

        //2.Wait till transition to Reset state
        fork
            begin
                wait(rdi_state_sts == Reset);
                $display("[%0t] Transitioned to Reset. Success!", $time);
                @(negedge lclk);
                state_sts=RESET;
            end
            begin
                repeat(10)
                    @(negedge lclk);
                $error("[%0t] Timeout, Transition to Reset Failed!", $time);
                $stop;
            end
        join_any
        disable fork;

        //===========================================================================================
        // ==========Test scenario 6: Test PMNAK Handshake======================== 
        //===========================================================================================
        

        $display("[%0t] All tests completed successfully!", $time);
        $stop;
    end
    // Monitor
    initial begin
        $monitor("[%0t] RDI_STS: %s, MSG_SEND: %s", $time, rdi_state_sts.name(), message_send.name());
    end

endmodule
