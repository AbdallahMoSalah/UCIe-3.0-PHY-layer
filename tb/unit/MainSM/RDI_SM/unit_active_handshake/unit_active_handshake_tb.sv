`timescale 1ns / 1ps

module unit_active_handshake_tb;

    // Inputs
    logic lclk;
    logic Active_resp_r;
    logic Active_req_r;
    logic Active_handshake_strt;

    // Outputs
    logic Active_resp_s;
    logic Active_req_s;
    logic Active_handshake_done;

    // Instantiate the Unit Under Test (UUT)
    unit_active_handshake uut (
        .lclk(lclk),
        .Active_resp_r(Active_resp_r),
        .Active_req_r(Active_req_r),
        .Active_handshake_strt(Active_handshake_strt),
        .Active_resp_s(Active_resp_s),
        .Active_req_s(Active_req_s),
        .Active_handshake_done(Active_handshake_done)
    );

    // Clock generation
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk;
    end

    // Test sequence
    initial begin
        // Initialize Inputs
        Active_resp_r = 0;
        Active_req_r = 0;
        Active_handshake_strt = 0;

        // Wait 100 ns for global initialization
        #100;

    // --- Scenario 1: Local-Initiated Handshake ---
    // Start locally, send request, then receive response from peer.
    // Also tests receiving a peer request after the handshake is underway.
    $display("[%0t] Starting Scenario 1: Local-Initiated Handshake", $time);
    @(negedge lclk);
    Active_handshake_strt = 1;

    // UUT should move to SEND_REQ and then CHECK_MSG
    wait(Active_req_s == 1'b1);
    @(negedge lclk);
    Active_handshake_strt = 0;

    // Wait a few cycles to simulate network delay
    #20;

    // Simulate peer sending its response
    @(negedge lclk);
    Active_resp_r = 1;
    @(negedge lclk);
    Active_resp_r = 0;
    
    // Simulate a peer request arriving late (collision or subsequent request)
    #20;
    Active_req_r = 1;
    @(negedge lclk);
    @(negedge lclk);
    Active_req_r = 0;

    // Handshake should complete once response is processed
    wait(Active_handshake_done == 1'b1);
    @(negedge lclk);
    $display("[%0t] Scenario 1 completed successfully.", $time);

    #50;

    // --- Scenario 2: Handshake Collision (Simultaneous Start) ---
    // Both sides initiate at the same time. Priority and flow handling should resolve it.
    $display("[%0t] Starting Scenario 2: Handshake Collision", $time);
    @(negedge lclk);
    Active_handshake_strt = 1;
    Active_req_r = 1;
    @(negedge lclk);
    Active_handshake_strt = 0;
    Active_req_r = 0;

    // UUT should detect the incoming request and prioritize sending a response
    wait(Active_resp_s == 1'b1);
    @(negedge lclk);
    Active_req_r = 0;

    #20;
    
    // Simulate peer acknowledging our request with a response
    @(negedge lclk);
    Active_resp_r = 1;
    @(negedge lclk);
    Active_resp_r = 0;
    Active_handshake_strt = 0;

    // Handshake finishes after mutual request-response exchange
    wait(Active_handshake_done == 1'b1);
    @(negedge lclk);
    $display("[%0t] Scenario 2 completed successfully.", $time);

    #50;

    // --- Scenario 3: Peer-Initiated Handshake ---
    // Peer starts first, then local side responds and initiates its own request.
    $display("[%0t] Starting Scenario 3: Peer-Initiated Handshake", $time);

    // Peer request arrives
    @(negedge lclk);
    Active_req_r = 1;
    @(negedge lclk);
    Active_req_r = 0;
    
    // Local side starts handshake in response
    Active_handshake_strt = 1;
    @(negedge lclk);
    Active_handshake_strt = 0;
    
    // Simulate peer response after some delay
    repeat (20) @(negedge lclk);
    Active_resp_r = 1;
    @(negedge lclk);
    Active_resp_r = 0;

    // Wait for completion
    wait(Active_handshake_done == 1'b1);
    $display("[%0t] Scenario 3 completed successfully.", $time);

    #50;
    $display("[%0t] All test cases passed.", $time);
    $stop;
end

// Global Monitor to track handshake progress
initial begin
    $monitor("Time=%0t | State=%0d | Flow=%0d | Strt=%b | Req_r=%b | Resp_r=%b || Req_s=%b | Resp_s=%b | Done=%b", 
             $time, uut.state, uut.flow, Active_handshake_strt, Active_req_r, Active_resp_r,
             Active_req_s, Active_resp_s, Active_handshake_done);
end

endmodule
