// =============================================================================
//  ucie_tb_top
// -----------------------------------------------------------------------------
//  Top-level SystemVerilog testbench for the UCIe UVM environment.
//  Instantiates local and partner PHYs connected back-to-back, maps the
//  package channel models, performs handshake loopbacks, and executes UVM tests.
// =============================================================================

`timescale 1ns/1ps

module ucie_tb_top;

    import uvm_pkg::*;
    import ucie_uvm_pkg::*;

    localparam int NUM_LANES = 16;
    localparam int FLITW = 256;
    localparam int LTSM_CLK_FRQ = 200_000;   // scaled: 4ms/8ms timers ~800/1600 cyc
    localparam int RDI_CLK_FRQ  = 200_000;   // scaled RDI timers (1us/16ms)

    // --- Global Controls ---
    logic rst_n;

    // --- Per-Die nets (0 = local/Die 0, 1 = partner/Die 1) ---
    logic lclk0, lclk1;

    // MainBand serial
    logic [NUM_LANES-1:0] o_TD_P0, o_TD_P1, i_RD_P0, i_RD_P1;
    logic                 o_TVLD_P0, o_TVLD_P1, i_RVLD_P0, i_RVLD_P1;
    logic                 o_TCKP_P0, o_TCKP_P1, i_RCKP_P0, i_RCKP_P1;
    logic                 o_TCKN_P0, o_TCKN_P1, i_RCKN_P0, i_RCKN_P1;
    logic                 o_TTRK_P0, o_TTRK_P1, i_RTRK_P0, i_RTRK_P1;

    // Sideband serial
    logic                 TXCKSB0, TXCKSB1, RXCKSB0, RXCKSB1;
    logic                 TXDATASB0, TXDATASB1, RXDATASB0, RXDATASB1;

    // MainBand flit dummy connections
    logic [FLITW-1:0]     lp_data0, lp_data1, o_out_data0, o_out_data1;
    logic                 lp_valid0, lp_valid1, lp_irdy0, lp_irdy1;
    logic                 o_pl_valid0, o_pl_valid1;
    logic                 pl_trdy0, pl_trdy1, pl_error0, pl_error1;

    // Adapter config buses
    logic [31:0]          lp_cfg_bus [2];
    logic                 lp_cfg_vld [2];
    logic                 lp_cfg_crd [2];
    logic [31:0]          pl_cfg_bus [2];
    logic                 pl_cfg_vld [2];

    // RDI adapter handshake nets
    RDI_SM_pkg::RDI_state lp_state_req0, lp_state_req1;
    logic                 lp_clk_ack0,   lp_clk_ack1;
    logic                 lp_stallack0,  lp_stallack1;
    logic                 lp_wake_req0,  lp_wake_req1;
    logic                 lp_linkerror0, lp_linkerror1;

    RDI_SM_pkg::RDI_state pl_state_sts0, pl_state_sts1;
    logic                 pl_clk_req0,   pl_clk_req1;
    logic                 pl_stallreq0,  pl_stallreq1;
    logic                 pl_trainerror0,pl_trainerror1;
    logic                 pl_wake_ack0,  pl_wake_ack1;
    logic                 pl_inband_pres0, pl_inband_pres1;

    // =========================================================================
    // Virtual Interface Instantiations
    // =========================================================================
    
    // Config interface L & P running on respective sideband clocks
    wire clk_sb0 = u_die0.clk_sb;
    wire clk_sb1 = u_die1.clk_sb;

    rdi_cfg_if vif_cfg_L (.clk(clk_sb0), .rst_n(rst_n));
    rdi_cfg_if vif_cfg_P (.clk(clk_sb1), .rst_n(rst_n));

    // LTSM monitor and RDI interfaces running on core clocks lclk0 & lclk1
    ucie_ltsm_monitor_if vif_ltsm (.clk0(lclk0), .clk1(lclk1));
    ucie_rdi_if          vif_rdi  (.clk0(lclk0), .clk1(lclk1));

    // Mainband virtual interfaces for Die 0 (Local) and Die 1 (Partner)
    ucie_mainband_if #(FLITW) vif_mb_L (.clk(lclk0), .rst_n(rst_n));
    ucie_mainband_if #(FLITW) vif_mb_P (.clk(lclk1), .rst_n(rst_n));

    // Channel modeling interface
    ucie_channel_if #(NUM_LANES) vif_channel ();

    // =========================================================================
    // Physical Channel Mapping with Fault Injections
    // =========================================================================
    
    // Sideband cross-connect
    assign RXCKSB0   = vif_channel.block_sideband ? 1'b0 : TXCKSB1;
    assign RXDATASB0 = vif_channel.block_sideband ? 1'b0 : TXDATASB1;
    assign RXCKSB1   = vif_channel.block_sideband ? 1'b0 : TXCKSB0;
    assign RXDATASB1 = vif_channel.block_sideband ? 1'b0 : TXDATASB0;

    // MainBand cross-connect (corruptions & reversals)
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            i_RD_P1[i] = vif_channel.corrupt_0to1[i] ? 1'b0 : 
                         (vif_channel.reverse_0to1 ? o_TD_P0[NUM_LANES-1-i] : o_TD_P0[i]);
            i_RD_P0[i] = vif_channel.corrupt_1to0[i] ? 1'b0 : 
                         (vif_channel.reverse_1to0 ? o_TD_P1[NUM_LANES-1-i] : o_TD_P1[i]);
        end
    end
    assign i_RVLD_P1 = o_TVLD_P0 ^ vif_channel.rx_vld_error_inject_0_to_1;
    assign i_RVLD_P0 = o_TVLD_P1;
    assign i_RCKP_P1 = o_TCKP_P0;
    assign i_RCKP_P0 = o_TCKP_P1;
    assign i_RCKN_P1 = o_TCKN_P0;
    assign i_RCKN_P0 = o_TCKN_P1;
    assign i_RTRK_P1 = o_TTRK_P0;
    assign i_RTRK_P0 = o_TTRK_P1;

    // =========================================================================
    // DUT Instantiations (Local & Partner wrappers)
    // =========================================================================
    
    UCIe_PHY_wrapper #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(0)) u_die0 (
        .rst_n(rst_n),
        .lp_data(lp_data0), .lp_irdy(lp_irdy0), .lp_valid(lp_valid0), .pl_trdy(pl_trdy0), .pl_error(pl_error0),
        .lclk(lclk0), .pl_data(o_out_data0), .pl_valid(o_pl_valid0),
        .i_RD_P(i_RD_P0), .i_RVLD_P(i_RVLD_P0), .i_RCKP_P(i_RCKP_P0), .i_RCKN_P(i_RCKN_P0), .i_RTRK_P(i_RTRK_P0),
        .o_TD_P(o_TD_P0), .o_TVLD_P(o_TVLD_P0), .o_TCKP_P(o_TCKP_P0), .o_TCKN_P(o_TCKN_P0), .o_TTRK_P(o_TTRK_P0),
        .RXCKSB(RXCKSB0), .TXCKSB(TXCKSB0), .TXDATASB(TXDATASB0), .RXDATASB(RXDATASB0),
        .lp_cfg(lp_cfg_bus[0]), .lp_cfg_vld(lp_cfg_vld[0]), .pl_cfg_crd(), .lp_cfg_crd(lp_cfg_crd[0]), .pl_cfg(pl_cfg_bus[0]), .pl_cfg_vld(pl_cfg_vld[0]),
        .lp_state_req(lp_state_req0), .lp_clk_ack(lp_clk_ack0), .lp_wake_req(lp_wake_req0),
        .lp_stallack(lp_stallack0), .lp_linkerror(lp_linkerror0),
        .pl_clk_req(pl_clk_req0), .pl_stallreq(pl_stallreq0), .pl_wake_ack(pl_wake_ack0),
        .pl_trainerror(pl_trainerror0), .pl_inband_pres(pl_inband_pres0), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts0), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg()
    );

    UCIe_PHY_wrapper #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(1)) u_die1 (
        .rst_n(rst_n),
        .lp_data(lp_data1), .lp_irdy(lp_irdy1), .lp_valid(lp_valid1), .pl_trdy(pl_trdy1), .pl_error(pl_error1),
        .lclk(lclk1), .pl_data(o_out_data1), .pl_valid(o_pl_valid1),
        .i_RD_P(i_RD_P1), .i_RVLD_P(i_RVLD_P1), .i_RCKP_P(i_RCKP_P1), .i_RCKN_P(i_RCKN_P1), .i_RTRK_P(i_RTRK_P1),
        .o_TD_P(o_TD_P1), .o_TVLD_P(o_TVLD_P1), .o_TCKP_P(o_TCKP_P1), .o_TCKN_P(o_TCKN_P1), .o_TTRK_P(o_TTRK_P1),
        .RXCKSB(RXCKSB1), .TXCKSB(TXCKSB1), .TXDATASB(TXDATASB1), .RXDATASB(RXDATASB1),
        .lp_cfg(lp_cfg_bus[1]), .lp_cfg_vld(lp_cfg_vld[1]), .pl_cfg_crd(), .lp_cfg_crd(lp_cfg_crd[1]), .pl_cfg(pl_cfg_bus[1]), .pl_cfg_vld(pl_cfg_vld[1]),
        .lp_state_req(lp_state_req1), .lp_clk_ack(lp_clk_ack1), .lp_wake_req(lp_wake_req1),
        .lp_stallack(lp_stallack1), .lp_linkerror(lp_linkerror1),
        .pl_clk_req(pl_clk_req1), .pl_stallreq(pl_stallreq1), .pl_wake_ack(pl_wake_ack1),
        .pl_trainerror(pl_trainerror1), .pl_inband_pres(pl_inband_pres1), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts1), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg()
    );

    // Shrink the RDI timers so they are simulatable
    defparam u_die0.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die0.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;
    defparam u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // =========================================================================
    // Interface Connections (RDI configuration, status, and control)
    // =========================================================================
    
    // Connect config inputs/outputs to vif_cfg interfaces
    assign lp_cfg_bus[0]  = vif_cfg_L.lp_cfg;
    assign lp_cfg_vld[0]  = vif_cfg_L.lp_cfg_vld;
    assign vif_cfg_L.pl_cfg_crd = lp_cfg_crd[0]; // local grant
    assign vif_cfg_L.pl_cfg     = pl_cfg_bus[0];
    assign vif_cfg_L.pl_cfg_vld = pl_cfg_vld[0];

    assign lp_cfg_bus[1]  = vif_cfg_P.lp_cfg;
    assign lp_cfg_vld[1]  = vif_cfg_P.lp_cfg_vld;
    assign vif_cfg_P.pl_cfg_crd = lp_cfg_crd[1];
    assign vif_cfg_P.pl_cfg     = pl_cfg_bus[1];
    assign vif_cfg_P.pl_cfg_vld = pl_cfg_vld[1];

    // Connect Mainband virtual interfaces
    assign lp_data0          = vif_mb_L.lp_data;
    assign lp_valid0         = vif_mb_L.lp_valid;
    assign lp_irdy0          = vif_mb_L.lp_irdy;
    assign vif_mb_L.pl_trdy  = pl_trdy0;
    assign vif_mb_L.pl_error = pl_error0;
    assign vif_mb_L.pl_data  = o_out_data0;
    assign vif_mb_L.pl_valid = o_pl_valid0;

    assign lp_data1          = vif_mb_P.lp_data;
    assign lp_valid1         = vif_mb_P.lp_valid;
    assign lp_irdy1          = vif_mb_P.lp_irdy;
    assign vif_mb_P.pl_trdy  = pl_trdy1;
    assign vif_mb_P.pl_error = pl_error1;
    assign vif_mb_P.pl_data  = o_out_data1;
    assign vif_mb_P.pl_valid = o_pl_valid1;

    // Connect RDI handshake virtual interface
    assign lp_state_req0        = vif_rdi.lp_state_req0;
    assign lp_wake_req0         = vif_rdi.lp_wake_req0;
    assign lp_linkerror0        = vif_rdi.lp_linkerror0;
    assign vif_rdi.pl_state_sts0= pl_state_sts0;
    assign vif_rdi.pl_clk_req0  = pl_clk_req0;
    assign vif_rdi.pl_stallreq0 = pl_stallreq0;
    assign vif_rdi.pl_wake_ack0 = pl_wake_ack0;
    assign vif_rdi.pl_trainerror0=pl_trainerror0;
    assign vif_rdi.pl_inband_pres0=pl_inband_pres0;

    assign lp_state_req1        = vif_rdi.lp_state_req1;
    assign lp_wake_req1         = vif_rdi.lp_wake_req1;
    assign lp_linkerror1        = vif_rdi.lp_linkerror1;
    assign vif_rdi.pl_state_sts1= pl_state_sts1;
    assign vif_rdi.pl_clk_req1  = pl_clk_req1;
    assign vif_rdi.pl_stallreq1 = pl_stallreq1;
    assign vif_rdi.pl_wake_ack1 = pl_wake_ack1;
    assign vif_rdi.pl_trainerror1=pl_trainerror1;
    assign vif_rdi.pl_inband_pres1=pl_inband_pres1;

    // Connect LTSM monitor interface to internal hierarchical nets
    assign vif_ltsm.state0       = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign vif_ltsm.ctrl_state0  = u_die0.u_digital_ucie.u_main_sm.current_ltsm_state;

    assign vif_ltsm.state1       = u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign vif_ltsm.ctrl_state1  = u_die1.u_digital_ucie.u_main_sm.current_ltsm_state;

    // =========================================================================
    // Automatic Handshake Loopbacks in Testbench
    // =========================================================================
    
    always_ff @(posedge lclk0 or negedge rst_n) begin
        if (!rst_n) begin
            lp_clk_ack0  <= 1'b0;
            lp_stallack0 <= 1'b0;
        end else begin
            lp_clk_ack0  <= pl_clk_req0;
            lp_stallack0 <= pl_stallreq0;
        end
    end

    always_ff @(posedge lclk1 or negedge rst_n) begin
        if (!rst_n) begin
            lp_clk_ack1  <= 1'b0;
            lp_stallack1 <= 1'b0;
        end else begin
            lp_clk_ack1  <= pl_clk_req1;
            lp_stallack1 <= pl_stallreq1;
        end
    end

    // =========================================================================
    // Reset and UVM execution entry point
    // =========================================================================
    
    initial begin
        rst_n = 1'b0;
        vif_ltsm.rst_n = 1'b0;
        #100ns;
        rst_n = 1'b1;
        vif_ltsm.rst_n = 1'b1;
    end

    initial begin
        // Set all interfaces to config DB
        uvm_config_db#(virtual rdi_cfg_if)::set(null, "*", "vif_cfg_L", vif_cfg_L);
        uvm_config_db#(virtual rdi_cfg_if)::set(null, "*", "vif_cfg_P", vif_cfg_P);
        uvm_config_db#(virtual ucie_ltsm_monitor_if)::set(null, "*", "vif_ltsm", vif_ltsm);
        uvm_config_db#(virtual ucie_channel_if)::set(null, "*", "vif_channel", vif_channel);
        uvm_config_db#(virtual ucie_rdi_if)::set(null, "*", "vif_rdi", vif_rdi);
        uvm_config_db#(virtual ucie_mainband_if)::set(null, "*mainband_agt_L*", "vif", vif_mb_L);
        uvm_config_db#(virtual ucie_mainband_if)::set(null, "*mainband_agt_P*", "vif", vif_mb_P);

        // Run UVM
        run_test();
    end

endmodule
