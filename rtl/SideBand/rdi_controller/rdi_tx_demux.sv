`timescale 1ns / 1ps

import sb_pkg::*;

module rdi_tx_demux (

    input  logic         rst_n,
    input  logic         reset,       // Sideband or link reset flag
    
    // Inputs from Arbiter (RDI TX path)
    input  logic [127:0] rdi_msg,
    input  logic         rdi_vld,
    output logic         rdi_ready,
    
    // Outputs to Register Access Block
    output logic [127:0] reg_msg,
    output logic         reg_vld,
    input  logic         reg_ready,
    
    // Outputs to Link (Adapter down-to-Link)
    output logic [127:0] Adapter_msg_send,
    output logic         Adapter_vld_send,
    input  logic         Adapter_ready
);
    
    sb_opcode_e   opcode;
    sb_dstid_e    dstid;
    logic         is_req;
    logic         is_local_phy;
    logic         consumer_ready;
    
    assign opcode       = sb_opcode_e'(rdi_msg[4:0]);
    assign dstid        = sb_dstid_e'(rdi_msg[58:56]);
    
    // opcode[4] == 0 means it's a request (MEM, CFG, DMS Read/Write)
    // opcode[4] == 1 means it's a message or completion
    assign is_req       = ~rdi_msg[4]; 
    
    assign is_local_phy = (dstid == LOCAL_PHY);

    // Buffer accepts data if it's empty or being consumed in the current cycle
    assign rdi_ready = consumer_ready;

    // Routing Logic based on reset flag and message fields
    always_comb begin
        // Defaults
        reg_vld          = 1'b0;
        Adapter_vld_send = 1'b0;
        consumer_ready   = 1'b0;
        
        reg_msg          = rdi_msg;
        Adapter_msg_send = rdi_msg;

        
        if (reset) begin
            // In reset mode
            if (is_req) begin
                // Route all requests (local & remote) to Register Access Block
                // so it can generate a completion and return it.
                reg_vld        = rdi_vld;
                consumer_ready = reg_ready;
            end else begin
                // Drop normal messages / completions without sending to link
                // Assert consumer_ready to pop it from buffer, freeing up space.
                consumer_ready   = 1'b1;
                Adapter_vld_send = 1'b0;
            end
        end else begin
            // Normal mode
            if (is_local_phy) begin
                reg_vld        = rdi_vld;
                consumer_ready = reg_ready;
            end else begin
                Adapter_vld_send = rdi_vld;
                consumer_ready   = Adapter_ready;
            end
        end
        
    end

endmodule