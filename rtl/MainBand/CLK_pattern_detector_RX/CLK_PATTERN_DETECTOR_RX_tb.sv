module CLK_PATTERN_DETECTOR_RX_tb;

    // Parameters matching RTL
    parameter MAIN   = 128;
    parameter TOGGLE = 16;
    parameter ZERO   = 8;


    // Inputs
    logic i_clk;
    logic i_rst_n;
    logic clk_detector_en;
    logic clk_p;
    logic clk_n;
    logic track;

    // Outputs
    logic clk_check_done;
    logic clk_pattern_error;

    // Instantiate UUT (Unit Under Test)
    CLK_PATTERN_DETECTOR_RX uut (.*);

    // Clock Generation
    initial begin
        i_clk = 0;
        uut.clk_p_d = 0;
    forever begin
        #5 i_clk = ~i_clk;
        uut.clk_p_d = i_clk;
    end 
    end 

    // Stimulus Task: Simulate one full Pattern (Toggle + Zero)
    task automatic drive_pattern();
        // Toggle Phase
        // The RTL compares inputs to clk_p_d 
        for (int i = 0; i < TOGGLE; i++) begin
            clk_p = uut.clk_p_d; 
            clk_n = ~uut.clk_p_d;
            track = uut.clk_p_d;
            @(negedge i_clk);
        end

        // Zero Phase
        for (int i = 0; i < ZERO; i++) begin
            clk_p = 0;
            clk_n = 0;
            track = 0;
            @(negedge i_clk);
        end
    endtask

    // Main Test Sequence
    initial begin
        // Initialize
        i_rst_n = 0;
        clk_detector_en = 0;
        clk_p = 0;
        clk_n = 0;
        track = 0;

        // Reset
        @(negedge i_clk);
        i_rst_n = 1;
        $display("Starting Pattern Detection Test...");
        clk_detector_en = 1;

        // Loop through MAIN number of patterns
        for (int m = 0; m < MAIN; m++) begin
            drive_pattern();
        end

        // Wait for done signal
        wait(clk_check_done || clk_pattern_error);

        if (clk_pattern_error) begin
            $display("TEST FAILED: Pattern error detected at time %t", $time);
        end else if (clk_check_done) begin
            $display("TEST PASSED: Pattern detection completed successfully at time %t", $time);
        end

        @(negedge i_clk);
       $stop;
    end

    // Monitor
    initial begin
        $monitor("Time: %t | Main: %d | Toggle: %d | Zero: %d | Error: %b | Done: %b", 
                 $time, uut.counter_main, uut.counter_toggle, uut.counter_zero, clk_pattern_error, clk_check_done);
    end

endmodule