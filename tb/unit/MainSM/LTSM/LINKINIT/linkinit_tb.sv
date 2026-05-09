`timescale 1ns/1ps

module linkinit_tb;
    import RDI_SM_pkg::*;

    // Inputs
    logic clk;
    logic rst_n;
    RDI_state rdi_state_sts;
    logic Linkinit_enable;
    logic start_ucie_link_training;

    // Outputs
    logic linkinit_done;
    logic timeout_rst_n;
    logic enable_timeout;
    logic linkinit_error;

    // Internal signals for timeout counter
    logic timeout_expired;

    // Clock Generation
    always #5 clk = ~clk;

    // DUT Instance
    linkinit dut (
        .clk(clk),
        .rst_n(rst_n),
        .rdi_state_sts(rdi_state_sts),
        .timeout_expired(timeout_expired),
        .Linkinit_enable(Linkinit_enable),
        .start_ucie_link_training(start_ucie_link_training),
        .linkinit_done(linkinit_done),
        .timeout_rst_n(timeout_rst_n),
        .enable_timeout(enable_timeout),
        .linkinit_error(linkinit_error)
    );

    // Timeout Counter Instance
    // Using small parameters for faster simulation
    timeout_counter #(
        .CLK_FRQ_HZ(1000), 
        .TIME_OUT(10)      // Should expire after ~10 cycles (1000/1000 * 10)
    ) timeout_inst (
        .clk(clk),
        .timeout_rst_n(timeout_rst_n),
        .enable_timeout(enable_timeout),
        .timeout_expired(timeout_expired)
    );

    // Test Sequence
    initial begin
        // Initialize Signals
        clk = 0;
        rst_n = 0;
        rdi_state_sts = Reset;
        Linkinit_enable = 0;
        start_ucie_link_training = 0;

        // Reset the system
        #20 rst_n = 1;
        #10;

        //---------------------------------------------------------
        // Case 1: Successful Initialization
        //---------------------------------------------------------
        $display("[%0t] Starting Case 1: Successful Init", $time);
        Linkinit_enable = 1;
        #20;
        @(posedge clk);
        rdi_state_sts = Active;
        
        wait(linkinit_done);
        $display("[%0t] Success: linkinit_done asserted", $time);
        
        #20;
        Linkinit_enable = 0; // Return to idle
        @(posedge clk);
        rdi_state_sts = Reset;
        #20;

        //---------------------------------------------------------
        // Case 2: Timeout condition
        //---------------------------------------------------------
        $display("[%0t] Starting Case 2: Timeout Init", $time);
        Linkinit_enable = 1;
        
        wait(linkinit_error);
        if (timeout_expired)
            $display("[%0t] Success: linkinit_error asserted due to timeout", $time);
        else
            $display("[%0t] Error: linkinit_error asserted but not due to timeout", $time);

        #20;
        Linkinit_enable = 0; // Clear error
        #20;

        //---------------------------------------------------------
        // Case 3: Start UCIE Link Training trigger
        //---------------------------------------------------------
        $display("[%0t] Starting Case 3: Training Trigger Init", $time);
        Linkinit_enable = 1;
        #30;
        @(posedge clk);
        start_ucie_link_training = 1;
        
        wait(linkinit_error);
        $display("[%0t] Success: linkinit_error asserted due to training trigger", $time);

        #20;
        Linkinit_enable = 0;
        start_ucie_link_training = 0;
        #20;

        $display("[%0t] All test cases completed", $time);
        $finish;
    end

    // Monitor
    initial begin
        $monitor("[%0t] State: %s | Done: %b | Error: %b | Timeout Exp: %b", 
                 $time, dut.cs.name(), linkinit_done, linkinit_error, timeout_expired);
    end

endmodule
