`timescale 1ns / 1ps

import sb_pkg::*;

module rdi_router (

    input  logic         rst_n,
    input  logic         reset,       // Sideband or link reset flag
    
    // Inputs from Arbiter (RDI TX path)
    input  logic [127:0] rdi_msg,
    input  logic         rdi_vld,
    output logic         rdi_rdy,
    
    // Outputs to Register Access Block
    output logic [127:0] reg_msg,
    output logic         reg_vld,
    input  logic         reg_rdy,
    
    // Outputs to Link (Adapter down-to-Link)
    output logic [127:0] adapter_msg_send,
    output logic         adapter_vld_send,
    input  logic         adapter_rdy
);
    
    sb_opcode_e   opcode;
    sb_dstid_e    dstid;
    logic         is_req;
    logic         is_local_phy;
    logic         consumer_rdy;
    
    assign opcode       = sb_opcode_e'(rdi_msg[4:0]);
    assign dstid        = sb_dstid_e'(rdi_msg[58:56]);
    
    // opcode[4] == 0 means it's a request (MEM, CFG, DMS Read/Write)
    // opcode[4] == 1 means it's a message or completion
    assign is_req       = ~rdi_msg[4]; 
    
    assign is_local_phy = (dstid == LOCAL_PHY);

    // Buffer accepts data if it's empty or being consumed in the current cycle
    assign rdi_rdy = consumer_rdy;

    // Routing Logic based on reset flag and message fields
    always_comb begin
        // Defaults
        reg_vld          = 1'b0;
        adapter_vld_send = 1'b0;
        consumer_rdy   = 1'b0;
        
        reg_msg          = rdi_msg;
        adapter_msg_send = rdi_msg;

        
        if (reset) begin
            // In reset mode
            if (is_req) begin
                // Route all requests (local & remote) to Register Access Block
                // so it can generate a completion and return it.
                reg_vld        = rdi_vld;
                consumer_rdy = reg_rdy;
            end else begin
                // Drop normal messages / completions without sending to link
                // Assert consumer_rdy to pop it from buffer, freeing up space.
                consumer_rdy   = 1'b1;
                adapter_vld_send = 1'b0;
            end
        end else begin
            // Normal mode
            if (is_local_phy) begin
                reg_vld        = rdi_vld;
                consumer_rdy = reg_rdy;
            end else begin
                adapter_vld_send = rdi_vld;
                consumer_rdy   = adapter_rdy;
            end
        end
        
    end

endmodule