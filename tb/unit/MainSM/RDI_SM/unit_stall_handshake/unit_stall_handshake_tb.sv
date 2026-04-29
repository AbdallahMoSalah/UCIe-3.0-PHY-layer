`timescale 1ns/1ps

module unit_stall_handshake_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    logic lp_stallack;
    logic stall_req;
    
    logic pl_stallreq;
    logic stall_done;

    // Golden model signals
    logic exp_pl_stallreq;
    logic exp_stall_done;

    // ===============
    // DUT Instantiation
    // ===============
    unit_stall_handshake dut (
        .lclk(lclk),
        .lp_stallack(lp_stallack),
        .stall_req(stall_req),
        .pl_stallreq(pl_stallreq),
        .stall_done(stall_done)
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
    localparam bit [1:0] EXP_IDLE = 2'b00;
    localparam bit [1:0] EXP_STALLREQ = 2'b01;
    localparam bit [1:0] EXP_STALLACK = 2'b10;
    localparam bit [1:0] EXP_STALLDONE = 2'b11;
    
    logic [1:0] exp_state = EXP_IDLE;

    // Golden model state machine - models expected behavior
    always_ff @(posedge lclk) begin
        case (exp_state)
            EXP_IDLE: begin
                if (stall_req)
                    exp_state <= EXP_STALLREQ;
            end
            EXP_STALLREQ: begin
                if (lp_stallack)
                    exp_state <= EXP_STALLACK;
            end
            EXP_STALLACK: begin
                if (~stall_req)
                    exp_state <= EXP_STALLDONE;
            end
            EXP_STALLDONE: begin
                if (~lp_stallack)
                    exp_state <= EXP_IDLE;
            end
            default: exp_state <= EXP_IDLE;
        endcase
    end

    // Expected outputs based on golden model state
    assign exp_pl_stallreq = (exp_state == EXP_STALLREQ) || (exp_state == EXP_STALLACK);
    assign exp_stall_done = (exp_state == EXP_STALLACK);

    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs safely on negative clock edge
    task drive_inputs(
        input logic driven_stall_req,
        input logic driven_lp_stallack
    );
        begin
            @(negedge lclk); 
            stall_req = driven_stall_req;
            lp_stallack = driven_lp_stallack;
            $display("[%0t] DRIVER : Driven stall_req=%b, lp_stallack=%b", 
                $time, stall_req, lp_stallack);
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden model
    task check_outputs();
        begin
            @(negedge lclk); // Read on negative edge to allow propagation
            
            if (pl_stallreq !== exp_pl_stallreq || stall_done !== exp_stall_done) begin
                $error("[%0t] CHECKER: MISMATCH! Expected (req=%b, done=%b) | Actual (req=%b, done=%b) [exp_state=%b]", 
                    $time, exp_pl_stallreq, exp_stall_done, pl_stallreq, stall_done, exp_state);
                err_count++;
            end else begin
                $display("[%0t] CHECKER: MATCH! req=%b, done=%b [exp_state=%b]", 
                    $time, pl_stallreq, stall_done, exp_state);
            end
        end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting unit_stall_handshake Testbench");
        $display("========================================");

        // Initialize inputs
        stall_req = 0;
        lp_stallack = 0;

        // Force initialize design RTL state just in case since it uses declaration assignment
        // Removed dut.STALL_state = 2'b00; since the default block in RTL handles X to IDLE transition

        // Let system settle during initialization
        repeat(2) @(posedge lclk);
        
        // ----------------------------------------
        // Transaction 1: Idle state
        // ----------------------------------------
        $display("\n--- Test 1: Stay in IDLE ---");
        drive_inputs(1'b0, 1'b0);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 2: Full handshake sequence
        // ----------------------------------------
        $display("\n--- Test 2: Full seamless handshake ---");
        // Start request
        drive_inputs(1'b1, 1'b0);  // -> IDLE to STALLREQ
        @(posedge lclk);
        check_outputs(); 

        // Acknowledge
        drive_inputs(1'b1, 1'b1);  // -> STALLREQ to STALLACK
        @(posedge lclk);
        check_outputs(); 

        // De-assert request
        drive_inputs(1'b0, 1'b1);  // -> STALLACK to STALLDONE
        @(posedge lclk);
        check_outputs(); 

        // De-assert acknowledge
        drive_inputs(1'b0, 1'b0);  // -> STALLDONE to IDLE
        @(posedge lclk);
        check_outputs(); 

        // ----------------------------------------
        // Transaction 3: Delayed responses
        // ----------------------------------------
        $display("\n--- Test 3: Delayed handshake ---");
        // Request -> Wait in STALLREQ before ack
        drive_inputs(1'b1, 1'b0);
        repeat(3) begin
            @(posedge lclk);
            check_outputs(); 
        end

        // Ack -> Wait in STALLACK before dropping req
        drive_inputs(1'b1, 1'b1);
        repeat(3) begin
            @(posedge lclk);
            check_outputs(); 
        end

        // Drop Req -> Wait in STALLDONE before dropping ack
        drive_inputs(1'b0, 1'b1);
        repeat(3) begin
            @(posedge lclk);
            check_outputs(); 
        end

        // Drop Ack -> Arrive back at IDLE
        drive_inputs(1'b0, 1'b0);
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
