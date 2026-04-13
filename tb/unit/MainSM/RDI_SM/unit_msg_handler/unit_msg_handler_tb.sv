`timescale 1ns / 1ps
import UCIe_pkg::*;

module unit_msg_handler_tb();

  // Inputs
  logic lclk;
  logic Active_resp_s;
  logic Active_req_s;
  logic valid_r;
msg_no_e Link_Mgmt_Msg_Recieved;
  msg_no_e Massage_send;

  // Outputs
  logic Active_resp_r;
  logic Active_req_r;
  logic valid_s;
  msg_no_e Link_Mgmt_Msg_Send;
  msg_no_e Massage_recieve;

  // Instantiate the Unit Under Test (UUT)
  unit_msg_handler uut (
    .lclk(lclk),
    .Active_resp_s(Active_resp_s),
    .Active_req_s(Active_req_s),
    .valid_r(valid_r),
    .Link_Mgmt_Msg_Recieved(Link_Mgmt_Msg_Recieved),
    .Massage_send(Massage_send),
    .Active_resp_r(Active_resp_r),
    .Active_req_r(Active_req_r),
    .valid_s(valid_s),
    .Link_Mgmt_Msg_Send(Link_Mgmt_Msg_Send),
    .Massage_recieve(Massage_recieve)
  );

  // Clock generation
  initial begin
    lclk = 0;
    forever #5 lclk = ~lclk;
  end

  // Test stimulus
  initial begin
    // Initialize Inputs
    Active_resp_s = 0;
    Active_req_s = 0;
    valid_r = 0;
    Link_Mgmt_Msg_Recieved = NOTHING;
    Massage_send = NOTHING;

    // Wait 20 ns for global reset to finish
    #20;

    // ==========================================
    // Test Case 1: Send a message
    // ==========================================
    $display("[%0t] Starting Test Case 1: Send a message", $time);
    @(posedge lclk);
    Massage_send = RDI_L1_REQ;
    @(posedge lclk);
    Massage_send = NOTHING;
    repeat(3) @(posedge lclk);

    // ==========================================
    // Test Case 2: Receive generic message (not RDI_ACTIVE_REQ or RDI_ACTIVE_RSP)
    // ==========================================
    $display("[%0t] Starting Test Case 2: Receive generic message", $time);
    @(posedge lclk);
    valid_r = 1;
    Link_Mgmt_Msg_Recieved = RDI_L1_RSP;
    @(posedge lclk);
    valid_r = 0;
    Link_Mgmt_Msg_Recieved = NOTHING;
    repeat(3) @(posedge lclk);

    // ==========================================
    // Test Case 3: Receive RDI_ACTIVE_REQ message
    // ==========================================
    $display("[%0t] Starting Test Case 3: Receive RDI_ACTIVE_REQ message", $time);
    @(posedge lclk);
    valid_r = 1;
    Link_Mgmt_Msg_Recieved = RDI_ACTIVE_REQ;
    @(posedge lclk);
    valid_r = 0;
    Link_Mgmt_Msg_Recieved = NOTHING;
    repeat(5) @(posedge lclk);

    // ==========================================
    // Test Case 4: Receive RDI_ACTIVE_RSP message
    // ==========================================
    $display("[%0t] Starting Test Case 4: Receive RDI_ACTIVE_RSP message", $time);
    @(posedge lclk);
    valid_r = 1;
    Link_Mgmt_Msg_Recieved = RDI_ACTIVE_RSP;
    @(posedge lclk);
    valid_r = 0;
    Link_Mgmt_Msg_Recieved = NOTHING;
    repeat(5) @(posedge lclk);

    // ==========================================
    // Test Case 5: Send Active Request
    // ==========================================
    $display("[%0t] Starting Test Case 5: Send Active Request", $time);
    @(posedge lclk);
    Active_req_s = 1;
    @(posedge lclk);
    Active_req_s = 0;
    repeat(4) @(posedge lclk);

    // ==========================================
    // Test Case 6: Send Active Response
    // ==========================================
    $display("[%0t] Starting Test Case 6: Send Active Response", $time);
    @(posedge lclk);
    Active_resp_s = 1;
    @(posedge lclk);
    Active_resp_s = 0;
    repeat(4) @(posedge lclk);
    // ==========================================
    // Test Case 7: Send two messages back-to-back
    // ==========================================
    $display("[%0t] Starting Test Case 7: Send two messages back-to-back", $time);
    @(posedge lclk);
    Massage_send = RDI_L1_REQ;
    @(posedge lclk); 
    // SM goes to LMS, valid_s=1 for MSG1
    Massage_send = RDI_L2_REQ; // Change to MSG2 immediately
    @(posedge lclk); 
    // SM goes to IDLE
    @(posedge lclk); 
    // SM goes to LMS, valid_s=1 for MSG2
    Massage_send = NOTHING;
    repeat(4) @(posedge lclk);

    $display("[%0t] Simulation finished", $time);
    $finish;
  end

  // Monitor changes
  initial begin
    $monitor("Time=%0t | cs=%0s | valid_s=%b | Send_Msg=%0s | Receive_Msg=%0s | req_r=%b | resp_r=%b", 
             $time, uut.cs.name(), valid_s, Link_Mgmt_Msg_Send.name(), Massage_recieve.name(), Active_req_r, Active_resp_r);
  end

endmodule
