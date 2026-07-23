///////////////////////////////////////////////////////////////////////////////
// File:        testbench.sv
// Author:      Cristian Florin Slav
// Date:        2023-06-27
// Description: Testbench module. It contains the instance of the DUT and the 
//              logic to start the UVM test and UVM phases.
///////////////////////////////////////////////////////////////////////////////
`include "cfs_algn_test_pkg.sv"

module testbench();
  
  localparam ALGN_DATA_WIDTH = `CFS_ALGN_TEST_ALGN_DATA_WIDTH;
  
  import uvm_pkg::*;
  import cfs_algn_test_pkg::*;
  
  //CLock signal
  reg clk;
  
  //Clock generator
  initial begin
    clk = 0;
    
    forever begin
      //Generate an 100MHz clock
      clk = #5ns ~clk;
    end
  end
  
  //Instance of the APB interface
  cfs_apb_if apb_if(.pclk(clk));
  
  //Instance of the MD RX interface
  cfs_md_if#(ALGN_DATA_WIDTH) md_rx_if(.clk(clk));
  
  //Instance of the MD TX interface
  cfs_md_if#(ALGN_DATA_WIDTH) md_tx_if(.clk(clk));
  
  //Initial reset generator
  initial begin
    apb_if.preset_n = 1;
    
    #3ns;
    
    apb_if.preset_n = 0;
    
    #30ns;
    apb_if.preset_n = 1;
  end
  
  assign md_rx_if.reset_n = apb_if.preset_n;
  assign md_tx_if.reset_n = apb_if.preset_n;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
    
    uvm_config_db#(virtual cfs_apb_if)::set(null, "uvm_test_top.env.apb_agent", "vif", apb_if);
    
    uvm_config_db#(virtual cfs_md_if#(ALGN_DATA_WIDTH))::set(null, "uvm_test_top.env.md_rx_agent", "vif", md_rx_if);
    uvm_config_db#(virtual cfs_md_if#(ALGN_DATA_WIDTH))::set(null, "uvm_test_top.env.md_tx_agent", "vif", md_tx_if);
    
    //Start UVM test and phases
    run_test("");
  end
  
  //Instantiate the DUT
  cfs_aligner#(.ALGN_DATA_WIDTH(`CFS_ALGN_TEST_ALGN_DATA_WIDTH)) dut(
    .clk(    clk),
    .reset_n(apb_if.preset_n),
    
    .paddr(  apb_if.paddr),
    .pwrite( apb_if.pwrite),
    .psel(   apb_if.psel),
    .penable(apb_if.penable),
    .pwdata( apb_if.pwdata),
    .pready( apb_if.pready),
    .prdata( apb_if.prdata),
    .pslverr(apb_if.pslverr),
    
    .md_rx_valid( md_rx_if.valid),
    .md_rx_data(  md_rx_if.data),
    .md_rx_offset(md_rx_if.offset),
    .md_rx_size(  md_rx_if.size),
    .md_rx_ready( md_rx_if.ready),
    .md_rx_err(   md_rx_if.err),
    
    .md_tx_valid( md_tx_if.valid),
    .md_tx_data(  md_tx_if.data),
    .md_tx_offset(md_tx_if.offset),
    .md_tx_size(  md_tx_if.size),
    .md_tx_ready( md_tx_if.ready),
    .md_tx_err(   md_tx_if.err)
    
  );
  
  
endmodule
