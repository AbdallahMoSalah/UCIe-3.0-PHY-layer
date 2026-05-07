`timescale 1ns/1ps
import UCIe_pkg::*;

module SBINIT_tb;

    // Parameters
    parameter int CLK_FRQ_HZ = 100000; // 100 kHz (1ms = 100 cycles)
    
    // Signals
    logic clk;
    logic rst_n;
    
    // SBINIT signals
    logic sbinit_enable, sbinit_done, sbinit_error;
    logic sb_rx_valid;
    msg_no_e sb_rx_msg_id;
    logic four_iteration_done, sb_det_pattern_rcvd;
    logic sb_tx_valid;
    msg_no_e sb_tx_msg_id;
    logic sbinit_pattern_mode, sb_det_pattern_req, send_4_iteration;
    logic sbinit_timer_enable, sbinit_timeout_expired;

    // Clock Generation (10us period)
    initial clk = 0;
    always #5000 clk = ~clk;

    // Waveform Dumping
    initial begin
        $dumpfile("SBINIT_tb.vcd");
        $dumpvars(0, SBINIT_tb);
    end

    // Instantiate DUT
    SBINIT #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) dut (.*);

    // Helper: Send a message
    task send_msg(input msg_no_e msg);
        begin
            @(posedge clk);
            sb_rx_valid = 1; sb_rx_msg_id = msg;
            @(posedge clk);
            sb_rx_valid = 0; sb_rx_msg_id = msg_no_e'(NOTHING);
        end
    endtask

    // Helper: Reset sequence
    task perform_reset();
        begin
            rst_n = 0; sbinit_enable = 0; sb_rx_valid = 0;
            four_iteration_done = 0; sb_det_pattern_rcvd = 0;
            sbinit_timeout_expired = 0;
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    initial begin
        $display("[%0t] Starting SBINIT Functional Review", $time);

        // --- SCENARIO 1: Full Successful Handshake ---
        $display("\n--- SCENARIO 1: SUCCESS FLOW ---");
        perform_reset();
        sbinit_enable = 1;
        
        wait(sb_det_pattern_req);
        $display("[%0t] S1: Pattern request toggling started", $time);
        repeat(150) @(posedge clk); // Observe 1.5ms of toggling
        
        $display("[%0t] S1: Detecting pattern...", $time);
        sb_det_pattern_rcvd = 1;
        @(posedge clk);
        sb_det_pattern_rcvd = 0;
        
        // VERIFY: No toggling after detection
        repeat(50) @(posedge clk);
        if (sb_det_pattern_req) $display("[%0t] ERROR: Toggling detected after pattern_rcvd!", $time);
        else                    $display("[%0t] PASS: Toggling stopped immediately after detection.", $time);
        
        wait(send_4_iteration);
        $display("[%0t] S2: iteration request active", $time);
        repeat(10) @(posedge clk);
        four_iteration_done = 1; @(posedge clk); four_iteration_done = 0;

        wait(sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        $display("[%0t] S3: Out_of_Reset Handshake", $time);
        send_msg(SBINIT_Out_of_Reset);

        wait(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        $display("[%0t] S4: Completion Handshake", $time);
        send_msg(SBINIT_done_req);
        wait(sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        send_msg(SBINIT_done_resp);

        wait(sbinit_done);
        $display("[%0t] SUCCESS: SBINIT Done reached.", $time);
        sbinit_enable = 0; // Disable module at the end of success flow
        repeat(10) @(posedge clk);


        // // --- SCENARIO 2: Reset midway ---
        // $display("\n--- SCENARIO 2: RESET MIDWAY ---");
        // perform_reset();
        // sbinit_enable = 1;
        // wait(sb_det_pattern_req);
        // repeat(50) @(posedge clk);
        // $display("[%0t] Resetting module in the middle of S1...", $time);
        // sbinit_enable = 0;
        // repeat(5) @(posedge clk);
        // if (sb_det_pattern_req == 0 && !sbinit_done && !sbinit_error)
        //      $display("[%0t] PASS: Module returned to IDLE.", $time);


        // // --- SCENARIO 3: Protocol Error ---
        // $display("\n--- SCENARIO 3: PROTOCOL ERROR ---");
        // perform_reset();
        // sbinit_enable = 1;
        // wait(sb_det_pattern_req);
        // $display("[%0t] S1: Sending unexpected message (Done_Req)...", $time);
        // send_msg(SBINIT_done_req);
        // wait(sbinit_error);
        // $display("[%0t] PASS: Protocol error correctly flagged.", $time);

        // $display("\n[%0t] ALL SCENARIOS REVIEWED.", $time);
        $finish;
    end

endmodule
