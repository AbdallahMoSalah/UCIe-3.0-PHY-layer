`timescale 1ns/1ps

// ============================================================================
// Module      : sb_upstream_arbiter
// Description : Priority-based arbiter for the Upstream path in the RDI protocol.
//               Routes traffic from two sources to a single upstream output.
// Priority    : 1. Remote Requests (Link Controller) -> STRICT HIGHER PRIORITY
//               2. Local Completions (Reg_access)    -> LOWER PRIORITY
// ============================================================================

module sb_upstream_arbiter (
    // ==========================================
    // 1. High Priority Input (From Link_Controller)
    // ==========================================
    // Note: No 'rdy' output is provided here as the Link Controller operates 
    // strictly on a credit-based flow control mechanism.
    input  logic [127:0] adapter_msg_rcvd,  // Remote Request Data
    input  logic         adapter_vld_rcvd,  // Remote Request Valid

    // ==========================================
    // 2. Low Priority Input (From Reg_access)
    // ==========================================
    // Local completions use standard valid/rdy handshaking.
    input  logic [127:0] completion_msg,    // Local Completion Data
    input  logic         completion_vld,    // Local Completion Valid
    output logic         completion_rdy,  // Backpressure to Reg_access

    // ==========================================
    // 3. Arbitrated Output (To Upstream Demux/FIFOs)
    // ==========================================
    output logic [127:0] Adapter_msg,       // Arbitrated Output Message
    output logic         Adapter_vld        // Arbitrated Output Valid
);

    // ==========================================
    // Task 1: Output Valid Generation
    // ==========================================
    // Assert the output valid signal if either of the input sources has a valid request.
    assign Adapter_vld = adapter_vld_rcvd | completion_vld;

    // ==========================================
    // Task 2: Data Multiplexing (Priority Routing)
    // ==========================================
    // Strict priority multiplexer: 
    // If the high-priority remote source is transmitting (adapter_vld_rcvd == 1), 
    // its data is routed. Otherwise, the low-priority local data is routed.
    assign Adapter_msg = adapter_vld_rcvd ? adapter_msg_rcvd : completion_msg;

    // ==========================================
    // Task 3: Low-Priority Backpressure (Rdy Logic)
    // ==========================================
    // Grant a 'rdy' signal to the local Reg_access ONLY if:
    // 1. It is actively requesting to send data (completion_vld == 1).
    // 2. The high-priority remote source is NOT sending data (~adapter_vld_rcvd).
    // This prevents the local source from dropping data during a collision.
    assign completion_rdy = completion_vld & (~adapter_vld_rcvd);

endmodule