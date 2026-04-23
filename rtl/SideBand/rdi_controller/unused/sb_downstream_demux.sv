`timescale 1ns/1ps

import sb_pkg::*; // Import protocol package containing Enums, Structs, and Opcodes

// ============================================================================
// Module      : sb_downstream_demux
// Description : Downstream routing demultiplexer for the RDI protocol.
//               Routes incoming 128-bit packets to either a local register 
//               access block or a remote link controller.
// Features    : 1. Opcode & DstID based routing.
//               2. Emergency reset override to prevent system deadlocks.
//               3. Combinational backpressure propagation.
// ============================================================================

module sb_downstream_demux (
    // ==========================================
    // 1. Ingress Interface (From Upstream Arbiter)
    // ==========================================
    input  logic [127:0] rdi_msg,       // Incoming 128-bit payload
    input  logic         rdi_vld,       // Incoming valid signal
    output logic         rdi_rdy,     // Upstream backpressure (rdy)

    // ==========================================
    // 2. Out-of-Band Control Signal (From RDI_SM)
    // ==========================================
    input  logic         reset,         // Emergency override signal

    // ==========================================
    // 3. Local Egress Interface (To Reg_access)
    // ==========================================
    output logic [127:0] reg_msg,       // Local targeted payload
    output logic         reg_vld,       // Local valid signal
    input  logic         reg_rdy,     // Downstream local backpressure

    // ==========================================
    // 4. Remote Egress Interface (To Link_Controller)
    // ==========================================
    output logic [127:0] adapter_msg_send,  // Remote targeted payload
    output logic         adapter_vld_send,  // Remote valid signal
    input  logic         adapter_rdy      // Downstream remote backpressure
);

    // ==========================================
    // Packet Decoding & Internal Signals
    // ==========================================
    sb_header_u header;
    // Cast the lower 64 bits of the incoming payload to the protocol header struct
    assign header = rdi_msg[63:0]; 

    // Routing decision flag: 1 = Route Locally, 0 = Route Remotely
    logic route_to_local_reg; 

    // ==========================================
    // Combinational Routing & Override Logic
    // ==========================================
    always_comb begin
        // Default routing: Forward traffic to the remote link controller
        route_to_local_reg = 1'b0; 

        // Condition 1: Route locally based on Destination ID.
        // This ensures local Completions and adapter-targeted messages are caught.
        if (header.msg.dstid == LOCAL_PHY || header.msg.dstid == LOCAL_ADAPTER) begin
            route_to_local_reg = 1'b1;
        end
        // Condition 2: Route locally based on specific Register/Config Opcodes.
        // Covers both 32-bit and 64-bit Sideband access formats.
        else if (header.msg.opcode == SB_32_DMS_REG_READ  || 
                 header.msg.opcode == SB_32_DMS_REG_WRITE || 
                 header.msg.opcode == SB_32_CFG_READ      || 
                 header.msg.opcode == SB_32_CFG_WRITE     ||
                 header.msg.opcode == SB_64_DMS_REG_READ  || 
                 header.msg.opcode == SB_64_DMS_REG_WRITE || 
                 header.msg.opcode == SB_64_CFG_READ      || 
                 header.msg.opcode == SB_64_CFG_WRITE) begin
            
            route_to_local_reg = 1'b1;
        end

        // Emergency Override: 
        // If reset is asserted, forcefully route EVERYTHING to the local Reg_access 
        // to trigger an internal flush/completion and prevent system hang.
        if (reset == 1'b1) begin
            route_to_local_reg = 1'b1; 
        end
    end

    // ==========================================
    // Payload Demultiplexing & Valid Gating
    // ==========================================
    // Broadcast the data bus to both egress ports to avoid unnecessary muxing logic.
    // The 'valid' signals act as the actual datapath enables (Valid Gating).
    assign reg_msg          = rdi_msg;
    assign adapter_msg_send = rdi_msg;
    //valid gating

    assign reg_vld          = route_to_local_reg  ? rdi_vld : 1'b0;
    assign adapter_vld_send = ~route_to_local_reg ? rdi_vld : 1'b0;

    // ==========================================
    // Flow Control / Backpressure Propagation
    // ==========================================
    // Multiplex the downstream 'rdy' signal back to the ingress port 
    // strictly based on the active routing decision.
    assign rdi_rdy = route_to_local_reg ? reg_rdy : adapter_rdy;

endmodule