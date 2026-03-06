`timescale 1ns/1ps

module unit_clk_handshake_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    logic clk_handshake_strt;
    logic lp_clk_ack;

    logic pl_clk_req;
    logic clk_handshake_done;

    // Golden model signals
    logic exp_pl_clk_req;
    logic exp_clk_handshake_done;

    // ===============
    // DUT Instantiation
    // ===============
    unit_clk_handshake dut (
        .lclk(lclk),
        .clk_handshake_strt(clk_handshake_strt),
        .lp_clk_ack(lp_clk_ack),
        .pl_clk_req(pl_clk_req),
        .clk_handshake_done(clk_handshake_done)
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
    typedef enum bit [1:0] {IDLE=2'b00, REQ=2'b01, DONE=2'b10} state_t;
    state_t exp_state = IDLE;

    // Golden model state machine - models expected behavior
    always_ff @(posedge lclk) begin
        case (exp_state)
            IDLE: begin
                if (clk_handshake_strt)
                    exp_state <= REQ;
            end
            REQ: begin
                if (lp_clk_ack)
                    exp_state <= DONE;
            end
            DONE: begin
                if (~clk_handshake_strt)
                    exp_state <= IDLE;
            end
        endcase
    end

    // Expected outputs based on golden model state
    assign exp_clk_handshake_done = (exp_state == DONE);
    assign exp_pl_clk_req  = (exp_state == REQ);

    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs safely on negative clock edge
    task drive_inputs(input logic strt, input logic ack);
        begin
            @(negedge lclk); 
            clk_handshake_strt = strt;
            lp_clk_ack = ack;
            $display("[%0t] DRIVER : Driven clk_handshake_strt=%b, lp_clk_ack=%b", $time, strt, ack);
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden model
    task check_outputs();
        begin
            @(negedge lclk); // Read on negative edge to allow propagation after posedge
            if (pl_clk_req !== exp_pl_clk_req || clk_handshake_done !== exp_clk_handshake_done) begin
                $error("[%0t] CHECKER: MISMATCH! Expected (req=%b, done=%b) | Actual (req=%b, done=%b)", 
                    $time, exp_pl_clk_req, exp_clk_handshake_done, pl_clk_req, clk_handshake_done);
                err_count++;
            end else begin
                $display("[%0t] CHECKER: MATCH! req=%b, done=%b", $time, pl_clk_req, clk_handshake_done);
            end
        end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting unit_clk_handshake Testbench");
        $display("========================================");

        // Initialize inputs
        clk_handshake_strt = 0;
        lp_clk_ack = 0;
        
        // Let system settle during initialization
        repeat(2) @(posedge lclk);
        check_outputs();

        // ----------------------------------------
        // Transaction 1: Full seamless handshake sequence
        // ----------------------------------------
        $display("\n--- Test 1: Full Handshake ---");
        // Start handshake
        drive_inputs(.strt(1'b1), .ack(1'b0));
        @(posedge lclk); // Allow state to update on posedge
        check_outputs(); // Check results on the following negedge 

        // Acknowledge handshake
        drive_inputs(.strt(1'b1), .ack(1'b1));
        @(posedge lclk); 
        check_outputs(); 

        // End handshake
        drive_inputs(.strt(1'b0), .ack(1'b1)); 
        @(posedge lclk);
        check_outputs();

        // De-assert ack
        drive_inputs(.strt(1'b0), .ack(1'b0));
        @(posedge lclk);
        check_outputs();

        // ----------------------------------------
        // Transaction 2: Delayed acknowledge response
        // ----------------------------------------
        $display("\n--- Test 2: Delayed Acknowledge ---");
        drive_inputs(.strt(1'b1), .ack(1'b0)); // Request start
        @(posedge lclk);
        check_outputs(); 
        
        // Wait a few cycles without acknowledge
        repeat(3) begin
            drive_inputs(.strt(1'b1), .ack(1'b0)); 
            @(posedge lclk);
            check_outputs();
        end

        drive_inputs(.strt(1'b1), .ack(1'b1)); // Finally acknowledge
        @(posedge lclk); 
        check_outputs();

        // ----------------------------------------
        // Transaction 3: Return to IDLE phase completion
        // ----------------------------------------
        $display("\n--- Test 3: Return to IDLE ---");
        drive_inputs(.strt(1'b0), .ack(1'b0)); // Finish transaction
        @(posedge lclk); 
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
