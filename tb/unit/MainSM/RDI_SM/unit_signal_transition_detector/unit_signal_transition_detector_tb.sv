`timescale 1ns/1ps

module unit_signal_transition_detector_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    logic phyinrecenter;
    logic inband_pres;
    logic trainerror;
    logic clk_handshake_done;

    logic pl_phyinrecenter;
    logic pl_inband_pres;
    logic pl_trainerror;
    logic signal_transition;

    // Golden model signals
    logic exp_pl_phyinrecenter = 0;
    logic exp_pl_inband_pres = 0;
    logic exp_pl_trainerror = 0;
    logic exp_signal_transition;

    // ===============
    // DUT Instantiation
    // ===============
    unit_signal_transition_detector dut (
        .lclk(lclk),
        .phyinrecenter(phyinrecenter),
        .inband_pres(inband_pres),
        .trainerror(trainerror),
        .clk_handshake_done(clk_handshake_done),
        .pl_phyinrecenter(pl_phyinrecenter),
        .pl_inband_pres(pl_inband_pres),
        .pl_trainerror(pl_trainerror),
        .signal_transition(signal_transition)
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
    localparam bit EXP_IDLE = 1'b0;
    localparam bit EXP_CLK_HANDSHAKE = 1'b1;
    logic exp_state = EXP_IDLE;

    // (Initial assignments moved to declaration to avoid multi-driver errors)

    always_ff @(posedge lclk) begin
        case (exp_state)
            EXP_IDLE: begin
                if ((phyinrecenter !== exp_pl_phyinrecenter) || 
                    (inband_pres !== exp_pl_inband_pres) || 
                    (trainerror !== exp_pl_trainerror)) begin
                    exp_state <= EXP_CLK_HANDSHAKE;
                end else begin
                    exp_state <= EXP_IDLE;
                end
            end

            EXP_CLK_HANDSHAKE: begin
                if (clk_handshake_done) begin
                    exp_state <= EXP_IDLE;
                    exp_pl_phyinrecenter <= phyinrecenter;
                    exp_pl_inband_pres <= inband_pres;
                    exp_pl_trainerror <= trainerror;
                end else begin
                    exp_state <= EXP_CLK_HANDSHAKE;
                end
            end
        endcase
    end

    assign exp_signal_transition = (exp_state == EXP_CLK_HANDSHAKE);

    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs safely on negative clock edge
    task drive_inputs(
        input logic driven_phyinrecenter,
        input logic driven_inband_pres,
        input logic driven_trainerror,
        input logic driven_clk_handshake_done
    );
        begin
            @(negedge lclk); 
            phyinrecenter = driven_phyinrecenter;
            inband_pres = driven_inband_pres;
            trainerror = driven_trainerror;
            clk_handshake_done = driven_clk_handshake_done;
            $display("[%0t] DRIVER : Driven phyinrecenter=%b, inband_pres=%b, trainerror=%b, clk_handshake_done=%b", 
                $time, phyinrecenter, inband_pres, trainerror, clk_handshake_done);
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden model
    task check_outputs();
        begin
            @(negedge lclk); // Read on negative edge to allow propagation
            
            // Note: Since pl_* registers in DUT aren't initialized with reset, they will be 'x' initially in RTL simulation.
            // But after the first handshake, they will sync to '0' or '1'. So we'll skip checking 'x' using case equality '===' to check expected values explicitly.
            
            if (signal_transition !== exp_signal_transition || 
                pl_phyinrecenter !== exp_pl_phyinrecenter || 
                pl_inband_pres !== exp_pl_inband_pres || 
                pl_trainerror !== exp_pl_trainerror) begin
                
                $error("[%0t] CHECKER: MISMATCH! Expected (trans=%b, pl_phy=%b, pl_inb=%b, pl_trner=%b) | Actual (trans=%b, pl_phy=%b, pl_inb=%b, pl_trner=%b) [exp_state=%b]", 
                    $time, exp_signal_transition, exp_pl_phyinrecenter, exp_pl_inband_pres, exp_pl_trainerror, 
                    signal_transition, pl_phyinrecenter, pl_inband_pres, pl_trainerror, exp_state);
                err_count++;
            end else begin
                $display("[%0t] CHECKER: MATCH! trans=%b, pl_phy=%b, pl_inb=%b, pl_trner=%b [exp_state=%b]", 
                    $time, signal_transition, pl_phyinrecenter, pl_inband_pres, pl_trainerror, exp_state);
            end
        end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting unit_signal_transition_detector Testbench");
        $display("========================================");

        // Initialize inputs
        phyinrecenter = 0;
        inband_pres = 0;
        trainerror = 0;
        clk_handshake_done = 0;

        // Force initialize the design registers to avoid 'x' propagation issues since RTL has no reset
        // Also do this on falling edge of lclk equivalent
        #2;
        dut.pl_phyinrecenter = 0;
        dut.pl_inband_pres = 0;
        dut.pl_trainerror = 0;
        // Removed dut.cs = 0 since the default case in the DUT handles X to IDLE transition
        
        // Let system settle during initialization
        repeat(2) @(posedge lclk);
        
        // ----------------------------------------
        // Transaction 1: Initial state, no changes
        // ----------------------------------------
        $display("\n--- Test 1: Initial state, no changes ---");
        drive_inputs(1'b0, 1'b0, 1'b0, 1'b0);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 2: Trigger phyinrecenter
        // ----------------------------------------
        $display("\n--- Test 2: Trigger phyinrecenter ---");
        drive_inputs(1'b1, 1'b0, 1'b0, 1'b0);
        @(posedge lclk); // Detect mismatch
        check_outputs(); // Now in CLK_HANDSHAKE state

        // ----------------------------------------
        // Transaction 3: Finish handshake
        // ----------------------------------------
        $display("\n--- Test 3: Finish handshake ---");
        drive_inputs(1'b1, 1'b0, 1'b0, 1'b1);
        @(posedge lclk); // Update internal regs and return to IDLE
        check_outputs(); // Back in IDLE, pl_ registers updated

        // Lower handshake done
        drive_inputs(1'b1, 1'b0, 1'b0, 1'b0);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 4: Trigger inband_pres
        // ----------------------------------------
        $display("\n--- Test 4: Trigger inband_pres ---");
        drive_inputs(1'b1, 1'b1, 1'b0, 1'b0);
        @(posedge lclk);
        check_outputs(); 

        // Finish handshake
        drive_inputs(1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge lclk);
        check_outputs(); 

        drive_inputs(1'b1, 1'b1, 1'b0, 1'b0);
        check_outputs();

        // ----------------------------------------
        // Transaction 5: Trigger trainerror and phyinrecenter simultaneously
        // ----------------------------------------
        $display("\n--- Test 5: Trigger multiple (inband_pres=0, trainerror=1) ---");
        drive_inputs(1'b1, 1'b0, 1'b1, 1'b0);
        @(posedge lclk);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 6: Delayed handshake finish
        // ----------------------------------------
        $display("\n--- Test 6: Delayed handshake finish ---");
        repeat(3) begin
            drive_inputs(1'b1, 1'b0, 1'b1, 1'b0);
            @(posedge lclk);
            check_outputs();
        end

        // Finish handshake
        drive_inputs(1'b1, 1'b0, 1'b1, 1'b1);
        @(posedge lclk);
        check_outputs();

        drive_inputs(1'b1, 1'b0, 1'b1, 1'b0);
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
