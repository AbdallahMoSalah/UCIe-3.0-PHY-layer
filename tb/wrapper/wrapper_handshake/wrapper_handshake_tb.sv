`timescale 1ns/1ps

module wrapper_handshake_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    
    // Inputs
    logic lp_clk_ack;
    logic clk_handshake_strt;
    logic signal_transition;
    logic traffic_req;
    
    logic lp_awak_req;
    logic ungating_done;
    
    logic lp_stallack;
    logic stall_req;

    // Outputs
    logic pl_clk_req;
    logic clk_handshake_done;
    
    logic pl_awak_ack;
    logic ungating_req;
    
    logic pl_stallreq;
    logic stall_done;

    // Golden model signals
    logic exp_pl_clk_req;
    logic exp_clk_handshake_done;
    
    logic exp_pl_awak_ack;
    logic exp_ungating_req;
    
    logic exp_pl_stallreq;
    logic exp_stall_done;

    // ===============
    // DUT Instantiation
    // ===============
    wrapper_handshake dut (
        .lp_clk_ack(lp_clk_ack),
        .lp_awak_req(lp_awak_req),
        .lp_stallack(lp_stallack),
        .lclk(lclk),
        .clk_handshake_strt(clk_handshake_strt),
        .ungating_done(ungating_done),
        .stall_req(stall_req),
        .signal_transition(signal_transition),
        .traffic_req(traffic_req),
        
        .pl_clk_req(pl_clk_req),
        .pl_awak_ack(pl_awak_ack),
        .pl_stallreq(pl_stallreq),
        .ungating_req(ungating_req),
        .stall_done(stall_done),
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
    // Golden Models
    // ===============
    
    // 1. Clock Handshake Golden Model
    logic [1:0] exp_clk_state = 2'b00; // IDLE=00, REQ=01, DONE=10
    logic comb_strt;
    assign comb_strt = clk_handshake_strt | signal_transition | traffic_req;
    
    always_ff @(posedge lclk) begin
        case (exp_clk_state)
            2'b00: if (comb_strt)  exp_clk_state <= 2'b01; // -> REQ
            2'b01: if (lp_clk_ack) exp_clk_state <= 2'b10; // -> DONE
            2'b10: if (~comb_strt) exp_clk_state <= 2'b00; // -> IDLE
        endcase
    end
    assign exp_clk_handshake_done = (exp_clk_state == 2'b10);
    assign exp_pl_clk_req         = (exp_clk_state == 2'b01);

    // 2. Awake Handshake Golden Model
    logic [1:0] exp_awak_state = 2'b00; // IDLE=00, UNGATING=01, ACK=10
    always_ff @(posedge lclk) begin
        case (exp_awak_state)
            2'b00: if (lp_awak_req)   exp_awak_state <= 2'b01;
            2'b01: if (ungating_done) exp_awak_state <= 2'b10;
            2'b10: if (~lp_awak_req)  exp_awak_state <= 2'b00;
        endcase
    end
    assign exp_ungating_req = (exp_awak_state == 2'b01);
    assign exp_pl_awak_ack  = (exp_awak_state == 2'b10);

    // 3. Stall Handshake Golden Model
    logic [1:0] exp_stall_state = 2'b00; // IDLE=00, STALLREQ=01, STALLACK=10, STALLDONE=11
    always_ff @(posedge lclk) begin
        case (exp_stall_state)
            2'b00: if (stall_req)    exp_stall_state <= 2'b01;
            2'b01: if (lp_stallack)  exp_stall_state <= 2'b10;
            2'b10: if (~stall_req)   exp_stall_state <= 2'b11;
            2'b11: if (~lp_stallack) exp_stall_state <= 2'b00;
        endcase
    end
    assign exp_pl_stallreq = (exp_stall_state == 2'b01) || (exp_stall_state == 2'b10);
    assign exp_stall_done  = (exp_stall_state == 2'b10);


    // ===============
    // Tasks
    // ===============
    
    // Task: Drive inputs safely on negative clock edge
    task drive_inputs(
        // clk inputs
        input logic in_clk_ack, input logic in_clk_strt, input logic in_sig_trans, input logic in_traff_req,
        // awak inputs
        input logic in_awak_req, input logic in_ungate_done,
        // stall inputs
        input logic in_stall_ack, input logic in_stall_req
    );
        begin
            @(negedge lclk); 
            // CLK Handshake
            lp_clk_ack = in_clk_ack;
            clk_handshake_strt = in_clk_strt;
            signal_transition = in_sig_trans;
            traffic_req = in_traff_req;
            // Awak Handshake
            lp_awak_req = in_awak_req;
            ungating_done = in_ungate_done;
            // Stall Handshake
            lp_stallack = in_stall_ack;
            stall_req = in_stall_req;
        end
    endtask

    int err_count = 0;
    
    // Task: Check outputs against golden models
    task check_outputs(input string context_str);
        begin
            @(negedge lclk); // Read on negative edge to allow propagation
            
            // Checking CLK Block
            if (pl_clk_req !== exp_pl_clk_req || clk_handshake_done !== exp_clk_handshake_done) begin
                $error("[%0t] %s CLK CHECK MISMATCH! Exp (req=%b, done=%b) Act (req=%b, done=%b)", 
                    $time, context_str, exp_pl_clk_req, exp_clk_handshake_done, pl_clk_req, clk_handshake_done);
                err_count++;
            end
            
            // Checking AWAK Block
            if (pl_awak_ack !== exp_pl_awak_ack || ungating_req !== exp_ungating_req) begin
                $error("[%0t] %s AWAK CHECK MISMATCH! Exp (ack=%b, ureq=%b) Act (ack=%b, ureq=%b)", 
                    $time, context_str, exp_pl_awak_ack, exp_ungating_req, pl_awak_ack, ungating_req);
                err_count++;
            end

            // Checking STALL Block
            if (pl_stallreq !== exp_pl_stallreq || stall_done !== exp_stall_done) begin
                $error("[%0t] %s STALL CHECK MISMATCH! Exp (req=%b, done=%b) Act (req=%b, done=%b)", 
                    $time, context_str, exp_pl_stallreq, exp_stall_done, pl_stallreq, stall_done);
                err_count++;
            end
        end
    endtask

    // Helper task to clear all
    task clear_all_inputs();
    begin
        drive_inputs(0,0,0,0,  0,0,  0,0);
    end
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting wrapper_handshake Testbench");
        $display("========================================");

        // Initialize inputs
        clear_all_inputs();

        // Let system settle during initialization
        repeat(2) @(posedge lclk);
        
        $display("\n--- Test 1: IDLE All ---");
        check_outputs("T1"); 

        // ----------------------------------------
        // Test parallel isolated transactions
        // ----------------------------------------
        $display("\n--- Test 2: Trigger CLK via traffic_req ---");
        drive_inputs(
            0, 0, 0, 1,
            0, 0,
            0, 0
        );
        @(posedge lclk);
        check_outputs("T2 req"); 

        $display("\n--- Test 3: Trigger AWAK and ACK CLK ---");
        drive_inputs(
            1, 0, 0, 1,
            1, 0,
            0, 0
        );
        @(posedge lclk);
        check_outputs("T3 ack clk, ungate req");

        $display("\n--- Test 4: Trigger STALL and Finish AWAK Ungating ---");
        drive_inputs(
            1, 0, 0, 0,
            1, 1,
            0, 1
        );
        @(posedge lclk);
        check_outputs("T4 stall req, awak ack, clk done");

        $display("\n--- Test 5: STALL ACK, AWAK Finish ---");
        drive_inputs(
            0, 0, 0, 0,
            0, 0,
            1, 1
        );
        @(posedge lclk);
        check_outputs("T5 stall ack, awak done");

        $display("\n--- Test 6: Clear all ---");
        drive_inputs(
            0, 0, 0, 0,
            0, 0,
            1, 0
        );
        @(posedge lclk);
        check_outputs("T6 clear reqs");

        drive_inputs(0,0,0,0,  0,0,  0,0);
        @(posedge lclk);
        check_outputs("T6 clear acks");

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
