`timescale 1ns/1ps

// ============================================================================
// File Name    : arbiter_tb.sv
// Description  : Testbench for the Link Management Round-Robin Arbiter.
//                This testbench verifies the arbitration logic between LTSM 
//                and RDI FIFOs, ensuring fair scheduling (Round-Robin) and 
//                correct flow control (Handshake) with the Link Controller.
// ============================================================================

module arbiter_tb;

    // ====================================================================
    // 1. Signal Declarations
    // ====================================================================
    // System Signals
    logic         clk;
    logic         reset_n;

    // Main Link Controller Interface
    logic         LINK_ready;
    logic [127:0] LINK_msg;
    logic         LINK_msg_valid;

    // RDI FIFO Interface
    logic [127:0] rdi_msg_fifo;
    logic         rdi_not_empty;
    logic         rdi_pop;

    // LTSM FIFO Interface
    logic [127:0] ltsm_msg_fifo;
    logic         ltsm_not_empty;
    logic         ltsm_pop;

    // ====================================================================
    // 2. Device Under Test (DUT) Instantiation
    // ====================================================================
    // Connect testbench signals to the arbiter module using wildcard (.*)
    arbiter dut (.*);

    // ====================================================================
    // 3. Clock Generation
    // ====================================================================
    // Generate a clock with a period of 10ns (5ns high, 5ns low)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ====================================================================
    // 4. Test Stimulus (Simulation Scenarios)
    // ====================================================================
    initial begin
        // Setup VCD file for waveform viewing in GTKWave
        $dumpfile("arbiter_waves.vcd");
        $dumpvars(0, arbiter_tb);

        // ----------------------------------------------------------------
        // Initialize all inputs to default safe values
        // ----------------------------------------------------------------
        reset_n        = 0;
        LINK_ready     = 1; // Assume Link Controller is initially ready
        rdi_msg_fifo   = 128'b0;
        rdi_not_empty  = 0;
        ltsm_msg_fifo  = 128'b0;
        ltsm_not_empty = 0;

        // Release reset after 15ns to start normal operation
        #15 reset_n = 1;

        // ----------------------------------------------------------------
        // Test Case 1: Only LTSM has pending data
        // Expected Behavior: Arbiter should route LTSM data and assert pop
        // ----------------------------------------------------------------
        @(posedge clk);
        ltsm_not_empty = 1;
        ltsm_msg_fifo  = 128'hAAAA_BBBB_CCCC_DDDD; // Dummy LTSM payload
        @(posedge clk);
        ltsm_not_empty = 0; // Clear request
        
        #20; // Wait and observe idle state

        // ----------------------------------------------------------------
        // Test Case 2: Only RDI has pending data
        // Expected Behavior: Arbiter should route RDI data and assert pop
        // ----------------------------------------------------------------
        @(posedge clk);
        rdi_not_empty = 1;
        rdi_msg_fifo  = 128'h1111_2222_3333_4444; // Dummy RDI payload
        @(posedge clk);
        rdi_not_empty = 0; // Clear request

        #20; // Wait and observe idle state

        // ----------------------------------------------------------------
        // Test Case 3: Both FIFOs have data simultaneously (Round-Robin Test)
        // Expected Behavior: Arbiter should alternate between LTSM and RDI
        // to ensure fair access and prevent starvation.
        // ----------------------------------------------------------------
        @(posedge clk);
        ltsm_not_empty = 1;
        rdi_not_empty  = 1;
        ltsm_msg_fifo  = 128'hFFFF_FFFF_FFFF_FFFF; // LTSM Payload
        rdi_msg_fifo   = 128'h9999_9999_9999_9999; // RDI Payload
        
        // Wait for 4 clock cycles to observe the switching mechanism
        repeat(4) @(posedge clk); 
        
        // Clear requests from both FIFOs
        ltsm_not_empty = 0;
        rdi_not_empty  = 0;

        // ----------------------------------------------------------------
        // End of Simulation
        // ----------------------------------------------------------------
        #50 $finish;
    end

endmodule