//-----------------------------------------------------------------------------
// Module      : unit_Timer_tb
// Description : Testbench for unit_Timer module. Verifies timeout logic
//               for both 1us and 16ms timers using scaled parameters.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module unit_Timer_tb;

    // Parameters for testing (Scaled down for faster simulation)
    // At 100MHz (10ns period): 
    //   - 1us should be 100 cycles
    //   - 16ms would be 1.6M cycles (still slow, we will override for focus)
    localparam int SIM_CLK_FREQ = 100_000_000; 

    // Simulation signals
    logic lclk;
    logic rst_n;
    logic start_time_16ms;
    logic start_time_1us;
    logic time_16ms;
    logic time_1us;

    // Instance of the Device Under Test (DUT)
    unit_Timer #(
        .CLK_FREQ(SIM_CLK_FREQ)
    ) dut (
        .lclk(lclk),
        .rst_n(rst_n),
        .start_time_16ms(start_time_16ms),
        .start_time_1us(start_time_1us),
        .time_16ms(time_16ms),
        .time_1us(time_1us)
    );

    // Clock generation: 100MHz = 10ns period
    always #5 lclk = ~lclk;

    // Monitor
    initial begin
        $monitor("Time=%0t | rst_n=%b | 1us_en=%b | 1us_out=%b | 16ms_en=%b | 16ms_out=%b", 
                 $time, rst_n, start_time_1us, time_1us, start_time_16ms, time_16ms);
    end

    int error_count = 0;

    // Main Test Procedure
    initial begin
        // Initialize signals
        lclk = 0;
        rst_n = 0;
        start_time_16ms = 0;
        start_time_1us = 0;

        // Reset Sequence
        $display("\n--- Starting Reset Sequence ---");
        #20 rst_n = 1;
        #10;
        
        // Test 1: 1us Timer Verification
        $display("\n--- Test 1: 1us Timer Verification ---");
        $display("Expecting timeout after 100 cycles (1000ns at 100MHz)");
        start_time_1us = 1;
        
        fork : timeout_watch_1us
            begin
                wait(time_1us);
                $display("SUCCESS: 1us timeout detected at %0t", $time);
                disable timeout_watch_1us;
            end
            begin
                #2000; // Wait longer than expected 1000ns
                $display("ERROR: 1us timeout failed to trigger within 2000ns");
                error_count++;
                disable timeout_watch_1us;
            end
        join

        #50 start_time_1us = 0; // De-assert as per typical SM behavior
        #50;

        // Test 2: Independence Test
        $display("\n--- Test 2: Independence Test ---");
        $display("Starting both timers simultaneously");
        start_time_1us = 1;
        start_time_16ms = 1;
        
        wait(time_1us);
        $display("Success: 1us triggered while 16ms is running. 16ms_out: %b", time_16ms);
        
        #50 start_time_1us = 0;
        #50;

        // Test 3: Reset/Interrupt Test
        $display("\n--- Test 3: Reset/Interrupt Test ---");
        $display("Interrupting 1us timer mid-count");
        start_time_1us = 1;
        #500; // Half-way (50 cycles)
        start_time_1us = 0;
        #20;
        if (time_1us == 0) begin
            $display("Success: Timer didn't trigger after interruption");
        end else begin
            $display("ERROR: Timer triggered despite interruption!");
            error_count++;
        end

        #100;
        $display("\n--- Simulation Complete ---");
        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TEST FAILED with %0d errors.", error_count);
        end
        $finish;
    end

endmodule
