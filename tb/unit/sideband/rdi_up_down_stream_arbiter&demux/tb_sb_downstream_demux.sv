`timescale 1ns/1ps

import sb_pkg::*; // Import definitions for enums and structs (Opcodes, DstIDs, etc.)

// ============================================================================
// Module      : tb_sb_downstream_demux
// Description : Directed Testbench for the Downstream Demux block.
//               Verifies normal routing logic (Opcode/DstID based), 
//               emergency reset force-routing, and ready/backpressure signals.
// ============================================================================

module tb_sb_downstream_demux();

    // ==========================================
    // 1. Testbench Signals Declaration
    // ==========================================
    // DUT Inputs (Stimulus)
    logic [127:0] rdi_msg;
    logic         rdi_vld;
    logic         reset;
    logic         reg_ready;
    logic         Adapter_ready;

    // DUT Outputs (Responses)
    logic         rdi_ready;
    logic [127:0] reg_msg;
    logic         reg_vld;
    logic [127:0] Adapter_msg_send;
    logic         Adapter_vld_send;

    // ==========================================
    // 2. Device Under Test (DUT) Instantiation
    // ==========================================
    sb_downstream_demux dut (
        .rdi_msg(rdi_msg),
        .rdi_vld(rdi_vld),
        .rdi_ready(rdi_ready),
        .reset(reset),
        .reg_msg(reg_msg),
        .reg_vld(reg_vld),
        .reg_ready(reg_ready),
        .Adapter_msg_send(Adapter_msg_send),
        .Adapter_vld_send(Adapter_vld_send),
        .Adapter_ready(Adapter_ready)
    );

    // ==========================================
    // 3. Stimulus Generation & Checking Tasks
    // ==========================================
    
    // Helper task to dynamically construct a 128-bit packet using the structured header
    task send_packet(input sb_dstid_e dst, input sb_opcode_e op);
        sb_header_u hdr;
        hdr = '0;           // Initialize all header fields to zero
        hdr.msg.dstid  = dst;   // Assign Destination ID
        hdr.msg.opcode = op;    // Assign Opcode

        // Concatenate a dummy 64-bit payload with the 64-bit header to form a full 128-bit message
        rdi_msg = {64'hDEADBEEF_CAFEBAFE, hdr}; 
        rdi_vld = 1'b1;
        #10; // Allow combinational logic to settle and propagate
    endtask

    // Helper task to automatically verify routing decisions and report Pass/Fail
    task check_routing(input logic exp_reg, input logic exp_adapter, string test_name);
        if (reg_vld === exp_reg && Adapter_vld_send === exp_adapter)
            $display("[PASS] %s", test_name);
        else
            $error("[FAIL] %s - Expected (Reg_vld:%b, Adapt_vld:%b), Got (Reg_vld:%b, Adapt_vld:%b)", 
                    test_name, exp_reg, exp_adapter, reg_vld, Adapter_vld_send);
    endtask

    // ==========================================
    // 4. Main Verification Sequence (Test Cases)
    // ==========================================
    initial begin
        $display("==================================================");
        $display("   STARTING DEMUX VERIFICATION...");
        $display("==================================================");

        // Initialize all stimulus signals to default/idle states
        rdi_msg = '0;
        rdi_vld = 0;
        reset   = 0;
        // Assume both downstream destinations are initially ready to accept data
        reg_ready     = 1; 
        Adapter_ready = 1; 
        #10;

        // --------------------------------------------------------
        // Test Case 1: Remote Message (Normal Mode)
        // Expected: Should be routed to the Link Controller (Adapter)
        // --------------------------------------------------------
        send_packet(REMOTE_ADAPTER, SB_32_MEM_READ);
        check_routing(1'b0, 1'b1, "TC1: Remote Memory Read");
        rdi_vld = 0; #10;

        // --------------------------------------------------------
        // Test Case 2: Local Register Access via Opcode (Normal Mode)
        // Expected: Should be routed to Reg_access (Opcode takes precedence over Remote DstID)
        // --------------------------------------------------------
        send_packet(REMOTE_ADAPTER, SB_32_CFG_WRITE); 
        check_routing(1'b1, 1'b0, "TC2: Local CFG Write (Opcode Override)");
        rdi_vld = 0; #10;

        // --------------------------------------------------------
        // Test Case 3: Local Completion via DstID (Normal Mode)
        // Expected: Should be routed to Reg_access based on the Local DstID
        // --------------------------------------------------------
        send_packet(LOCAL_ADAPTER, SB_COMPLETION_WITHOUT_DATA); 
        check_routing(1'b1, 1'b0, "TC3: Local Completion (DstID Override)");
        rdi_vld = 0; #10;

        // --------------------------------------------------------
        // Test Case 4: Emergency Reset Override (Force Routing)
        // Expected: Despite being a Remote Packet, the Emergency Reset must force routing to Reg_access
        // --------------------------------------------------------
        reset = 1'b1; // <--- Assert Emergency Reset
        send_packet(REMOTE_ADAPTER, SB_64_MEM_WRITE); 
        check_routing(1'b1, 1'b0, "TC4: Emergency Reset Forced Route to Reg_access");
        reset = 1'b0; // <--- De-assert Emergency Reset
        rdi_vld = 0; #10;

        // --------------------------------------------------------
        // Test Case 5: Flow Control (Ready Signal Feedback / Backpressure)
        // Expected: The upstream 'rdi_ready' should drop to 0 if the targeted downstream block is not ready.
        // --------------------------------------------------------
        reg_ready = 1'b0; // Simulate backpressure from Reg_access
        send_packet(LOCAL_ADAPTER, SB_32_DMS_REG_READ); // Route to Reg_access
        
        if (rdi_ready === 1'b0)
            $display("[PASS] TC5: Flow Control (Backpressure) working correctly.");
        else
            $error("[FAIL] TC5: Flow Control failed. rdi_ready should be 0.");
        
        reg_ready = 1'b1; // Restore readiness
        rdi_vld = 0; #10;

        $display("==================================================");
        $display("   VERIFICATION COMPLETE.");
        $display("==================================================");
        $finish;
    end

endmodule