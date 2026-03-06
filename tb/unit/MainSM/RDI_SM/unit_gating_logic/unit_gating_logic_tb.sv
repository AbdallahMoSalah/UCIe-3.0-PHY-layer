`timescale 1ns/1ps

import RDI_SM_pkg::*;

module unit_gating_logic_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    logic pl_phyinrecenter;
    logic pl_clk_req;
    logic ungating_req;
    RDI_state pl_state_sts;

    logic lclk_g;
    logic ungating_done;

    // Golden model signals
    logic exp_lclk_g;
    logic exp_ungating_done;

    // ===============
    // DUT Instantiation
    // ===============
    unit_gating_logic dut (
        .lclk(lclk),
        .pl_phyinrecenter(pl_phyinrecenter),
        .pl_clk_req(pl_clk_req),
        .ungating_req(ungating_req),
        .pl_state_sts(pl_state_sts),
        .lclk_g(lclk_g),
        .ungating_done(ungating_done)
    );

    // ===============
    // Clock Generation
    // ===============
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk;
    end

    // ===============
    // Golden Model
    // ===============
    localparam bit EXP_UNGATING = 1'b0;
    localparam bit EXP_GATING = 1'b1;
    logic exp_state = EXP_UNGATING;

    // Golden model state machine - models expected behavior
    always_ff @(posedge lclk) begin
        case (exp_state)
            EXP_UNGATING: begin
                if (((pl_state_sts == Reset)||(pl_state_sts == LinkReset)||(pl_state_sts == Disabled)||(pl_state_sts == L1)||(pl_state_sts == L2)) &&
                    ~pl_phyinrecenter &&
                    ~pl_clk_req && 
                    ~ungating_req)
                    exp_state <= EXP_GATING;
            end
            EXP_GATING: begin
                if (pl_clk_req || ungating_req || pl_phyinrecenter || ~((pl_state_sts == Reset)||
                                                                     (pl_state_sts == LinkReset)||
                                                                     (pl_state_sts == Disabled)||
                                                                     (pl_state_sts == L1)||
                                                                     (pl_state_sts == L2)))
                    exp_state <= EXP_UNGATING;
            end 
        endcase
    end

    // Expected outputs based on golden model state
    assign exp_lclk_g = (exp_state == EXP_GATING) ? 1'b0 : lclk;
    assign exp_ungating_done = (exp_state == EXP_UNGATING);

    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs safely on negative clock edge
    task drive_inputs(
        input logic phyinrecenter,
        input logic clk_req,
        input logic ungate_req,
        input RDI_state state_sts
    );
        begin
            @(negedge lclk); 
            pl_phyinrecenter = phyinrecenter;
            pl_clk_req = clk_req;
            ungating_req = ungate_req;
            pl_state_sts = state_sts;
            $display("[%0t] DRIVER : Driven phyinrecenter=%b, clk_req=%b, ungate_req=%b, state_sts=%0d", 
                $time, phyinrecenter, clk_req, ungate_req, state_sts);
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden model
    // Note: To check lclk_g properly, we should check it during the high phase of lclk
    task check_outputs();
        begin
            // Wait until shortly after posedge to avoid race conditions with lclk_g combinational logic
            @(posedge lclk);
            #2; 
            
            if (ungating_done !== exp_ungating_done || lclk_g !== exp_lclk_g) begin
                $error("[%0t] CHECKER: MISMATCH! Expected (done=%b, lclk_g=%b) | Actual (done=%b, lclk_g=%b) [exp_state=%b]", 
                    $time, exp_ungating_done, exp_lclk_g, ungating_done, lclk_g, exp_state);
                err_count++;
            end else begin
                $display("[%0t] CHECKER: MATCH! done=%b, lclk_g=%b [exp_state=%b]", $time, ungating_done, lclk_g, exp_state);
            end
        end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting unit_gating_logic Testbench");
        $display("========================================");

        // Initialize inputs
        pl_phyinrecenter = 0;
        pl_clk_req = 0;
        ungating_req = 0;
        pl_state_sts = Active;
        
        // Let system settle during initialization
        repeat(2) @(posedge lclk);
        
        // ----------------------------------------
        // Transaction 1: Stay in UNGATING (Active state)
        // ----------------------------------------
        $display("\n--- Test 1: Stay in UNGATING (Active state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, Active);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 2: Transition to GATING (Reset state + idle requests)
        // ----------------------------------------
        $display("\n--- Test 2: Transition to GATING (Reset state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, Reset);
        check_outputs(); // 1st posedge captures Reset state, state machine enters GATING

        // ----------------------------------------
        // Transaction 3: Verify GATING state functionality 
        // ----------------------------------------
        $display("\n--- Test 3: Stay in GATING (L1 state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, L1);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 4: Wake up via pl_clk_req
        // ----------------------------------------
        $display("\n--- Test 4: Wake up via pl_clk_req ---");
        drive_inputs(1'b0, 1'b1, 1'b0, L1);
        check_outputs(); 

        // Back to sleep
        $display("\n--- Test 5: Back to Sleep (L2 state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, L2);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 6: Wake up via ungating_req
        // ----------------------------------------
        $display("\n--- Test 6: Wake up via ungating_req ---");
        drive_inputs(1'b0, 1'b0, 1'b1, L2);
        check_outputs(); 

        // Back to sleep
        $display("\n--- Test 7: Back to Sleep (Disabled state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, Disabled);
        check_outputs();

        // ----------------------------------------
        // Transaction 8: Wake up via state change to Active
        // ----------------------------------------
        $display("\n--- Test 8: Wake up via state change to Active ---");
        drive_inputs(1'b0, 1'b0, 1'b0, Active);
        check_outputs(); 

        // Back to sleep
        $display("\n--- Test 9: Back to Sleep (LinkReset state) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, LinkReset);
        check_outputs();

        // ----------------------------------------
        // Transaction 10: Wake up via phyinrecenter
        // ----------------------------------------
        $display("\n--- Test 10: Wake up via phyinrecenter ---");
        drive_inputs(1'b1, 1'b0, 1'b0, LinkReset);
        check_outputs(); 

        // Summary
        $display("\n========================================");
        if (err_count == 0)
            $display("TEST PASSED! 0 Mismatches.");
        else
            $display("TEST FAILED! %0d Mismatches.", err_count);
        $display("========================================");

        $stop;
    end

endmodule
