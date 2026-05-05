
`timescale 1ns/1ps

module ltsm_tb_attachments #(
        parameter real    SB_CLK_PERIOD        = 1.25       , // That means SB clk period = 1.25ns (800MHz). It's represented in 'ns' unit.
        parameter integer TIMEOUT_CYCLES       = 'D8_000_000, // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
        parameter integer ANALOG_SETTLE_CYCLES = 'D10         // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    ) (
        internal_ltsm_if intf
    );
    //  The Signals here can be accessed usnig "Hierarchical Reference" (XMR (Cross-Module Reference)).

    internal_ltsm_if d2c_mux_out_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // The d2c_mux collection interface.
    internal_ltsm_if d2c_mux_in1_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the module RX_D2C_PT
    internal_ltsm_if d2c_mux_in2_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the module TX_D2C_PT

    internal_ltsm_if to_tx_d2c_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the substate module to TX_D2C_PT module.
    internal_ltsm_if to_rx_d2c_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the substate module to RX_D2C_PT module.


