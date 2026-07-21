// =============================================================================
//  rdi_cfg_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface wrapping the RDI Configuration Interface.
// =============================================================================

`timescale 1ns/1ps

interface rdi_cfg_if (
    input logic clk,
    input logic rst_n
);

    // Downstream (Adapter -> PHY)
    logic [31:0] lp_cfg;
    logic        lp_cfg_vld;
    logic        pl_cfg_crd; // credit return from PHY

    // Upstream (PHY -> Adapter)
    logic [31:0] pl_cfg;
    logic        pl_cfg_vld;
    logic        lp_cfg_crd; // credit grant from Adapter

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        default input #1ps output #1ps;
        output lp_cfg, lp_cfg_vld, lp_cfg_crd;
        input  pl_cfg_crd;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        default input #1ps output #1ps;
        input lp_cfg, lp_cfg_vld, pl_cfg_crd;
        input pl_cfg, pl_cfg_vld, lp_cfg_crd;
    endclocking

    // Initialization
    initial begin
        lp_cfg     = '0;
        lp_cfg_vld = 1'b0;
        lp_cfg_crd = 1'b0;
    end

endinterface
