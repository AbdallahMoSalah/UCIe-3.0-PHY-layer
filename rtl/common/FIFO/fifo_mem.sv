`timescale 1ns/1ps
// =============================================================================
// Module      : fifo_mem
// Description : Dual-port memory array for FIFO.
//               Write port is synchronous; read port is asynchronous (combinational).
//               Used by both sync and async FIFO configurations.
// =============================================================================
module fifo_mem #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                    wclk,
    input  logic                    wrst_n,
    input  logic                    winc,
    input  logic                    wfull,
    input  logic [ADDR_WIDTH-1:0]   waddr,
    input  logic [ADDR_WIDTH-1:0]   raddr,
    input  logic [DATA_WIDTH-1:0]   wdata,
    output logic [DATA_WIDTH-1:0]   rdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------------
    // Write – synchronous, gated by winc & !wfull
    // ------------------------------------------------------------------
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= '0;
        end else if (winc && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

    // ------------------------------------------------------------------
    // Read – asynchronous / combinational
    // ------------------------------------------------------------------
    assign rdata = mem[raddr];

endmodule
