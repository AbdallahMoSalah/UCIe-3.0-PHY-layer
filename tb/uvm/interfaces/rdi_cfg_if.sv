// =============================================================================
//  rdi_cfg_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface wrapping a single-directional RDI Config Link.
//  Encapsulates 32-bit config data, valid control, and credit return.
// =============================================================================

`timescale 1ns/1ps

interface rdi_cfg_if (
    input logic clk,
    input logic rst_n
);

    logic [31:0] cfg;
    logic        cfg_vld;
    logic        cfg_crd;

    // Master Driver clocking block (drives cfg & cfg_vld, reads cfg_crd)
    clocking drv_master_cb @(posedge clk);
        default input #1ps output #1ps;
        output cfg, cfg_vld;
        input  cfg_crd;
    endclocking

    // Slave Driver clocking block (drives cfg_crd, reads cfg & cfg_vld)
    clocking drv_slave_cb @(posedge clk);
        default input #1ps output #1ps;
        output cfg_crd;
        input  cfg, cfg_vld;
    endclocking

    // Monitor clocking block (samples all signals)
    clocking mon_cb @(posedge clk);
        default input #1ps output #1ps;
        input cfg, cfg_vld, cfg_crd;
    endclocking

    // Master Modport
    modport master_mp (
        clocking drv_master_cb,
        input clk, rst_n
    );

    // Slave Modport
    modport slave_mp (
        clocking drv_slave_cb,
        input clk, rst_n
    );

    // Monitor Modport
    modport mon_mp (
        clocking mon_cb,
        input clk, rst_n
    );

endinterface
