///////////////////////////////////////////////////////////////////////////////
// File:        cfs_md_if.sv
// Author:      Cristian Florin Slav
// Date:        2023-12-02
// Description: MD interface.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_MD_IF_SV
  `define CFS_MD_IF_SV

  interface cfs_md_if#(int unsigned DATA_WIDTH = 32)(input clk);
    
    //Width of the offset signal
    localparam OFFSET_WIDTH = $clog2(DATA_WIDTH/8) < 1 ? 1 : $clog2(DATA_WIDTH/8);
    
    //Width of the size signal
    localparam SIZE_WIDTH = $clog2(DATA_WIDTH/8) + 1;
    
    logic reset_n;

    logic valid;

    logic[DATA_WIDTH-1:0] data;

    logic[OFFSET_WIDTH-1:0] offset;

    logic[SIZE_WIDTH-1:0] size;
    
    logic ready;
    
    logic err;

    //Switch to enable checks
    bit has_checks;
    
    initial begin
      has_checks = 1;
    end
    
    //Rule #1: DATA_WIDTH must be a power of 2. 

    //initial begin
    //  if($countones(DATA_WIDTH) != 1) begin
    //    $error("DATA_WIDTH is not a power of two - value in binary: 'b%0b, in hex is 'h%0h, in dec is %0d", DATA_WIDTH, DATA_WIDTH, DATA_WIDTH);
    //  end
    //end
    
    if($log10(DATA_WIDTH)/$log10(2) - $clog2(DATA_WIDTH) != 0) begin
      $error("DATA_WIDTH is not a power of two - value in binary: 'b%0b, in hex is 'h%0h, in dec is %0d", DATA_WIDTH, DATA_WIDTH, DATA_WIDTH);
    end
    
    //Rule #2: DATA_WIDTH minimum legal value is 8. 
    
    if(DATA_WIDTH < 8) begin
      $error($sformatf("DATA_WIDTH must be bigger than 8 but detected value %0d", DATA_WIDTH));
    end
    
    //Rule #3: Once valid becomes high, it must stay high until ready becomes high. 

    property valid_high_until_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      $fell(valid) |-> $past(ready) == 1;
    endproperty
    
    VALID_HIGH_UNTIL_READY_A : assert property(valid_high_until_ready_p) else
      $error("valid signal did not stay high until ready became high");
    
    //Rule #4: data is valid while valid is high. 
      
    property unknown_value_data_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> $isunknown(data) == 0;
    endproperty
    
    UNKNOWN_VALUE_DATA_A : assert property(unknown_value_data_p) else
      $error("Detected unknown value for MD signal data");

    
    //Rule #5: data must remain constant until ready becomes high. 

    property stable_data_until_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid & $past(valid) & !$past(ready) |-> $stable(data) == 1;
    endproperty
    
    STABLE_DATA_UNTIL_READY_A : assert property(stable_data_until_ready_p) else
      $error("data signal did not remain stable until the end of the transfer");

    
    //Rule #6: offset is valid while valid is high. 

    property unknown_value_offset_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> $isunknown(offset) == 0;
    endproperty
    
    UNKNOWN_VALUE_OFFSET_A : assert property(unknown_value_offset_p) else
      $error("Detected unknown value for MD signal offset");

    
    //Rule #7: offset must remain constant until ready becomes high. 	

    property stable_offset_until_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid & $past(valid) & !$past(ready) |-> $stable(offset) == 1;
    endproperty
    
    STABLE_OFFSET_UNTIL_READY_A : assert property(stable_offset_until_ready_p) else
      $error("offset signal did not remain stable until the end of the transfer");

    
    //Rule #8: size is valid while valid is high. 

    property unknown_value_size_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> $isunknown(size) == 0;
    endproperty
    
    UNKNOWN_VALUE_SIZE_A : assert property(unknown_value_size_p) else
      $error("Detected unknown value for MD signal size");

    
    //Rule #9: size must remain constant until ready becomes high. 	

    property stable_size_until_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid & $past(valid) & !$past(ready) |-> $stable(size) == 1;
    endproperty
    
    STABLE_SIZE_UNTIL_READY_A : assert property(stable_size_until_ready_p) else
      $error("size signal did not remain stable until the end of the transfer");

    
    //Rule #10: size can not have value 0.

    property size_eq_0_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> size != 0;
    endproperty
    
    SIZE_EQ_0_A : assert property(size_eq_0_p) else
      $error("Detected value 0 for MD signal size");

    
    //Rule #11: err is valid only when both valid and ready are high.

    property unknown_value_err_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid & ready |-> $isunknown(err) == 0;
    endproperty
    
    UNKNOWN_VALUE_ERR_A : assert property(unknown_value_err_p) else
      $error("Detected unknown value for MD signal err");

    
    //Rule #12: err can be high only when valid and ready are high.

    property err_high_at_valid_and_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      err |-> valid & ready;
    endproperty
    
    ERR_HIGH_AT_VALID_AND_READY_A : assert property(err_high_at_valid_and_ready_p) else
      $error("Detected err signal high when ready & valid != 1");

    
    //Rule #13: valid can not have an unknown value

    property unknown_value_valid_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      $isunknown(valid) == 0;
    endproperty

    UNKNOWN_VALUE_VALID_A : assert property(unknown_value_valid_p) else
      $error("Detected unknown value for MD signal valid");

    
    //Rule #14: ready is valid while valid is high. 

    property unknown_value_ready_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> $isunknown(ready) == 0;
    endproperty
    
    UNKNOWN_VALUE_READY_A : assert property(unknown_value_ready_p) else
      $error("Detected unknown value for MD signal ready");

    
    //Rule #15: offset + size can not be bigger than the data width in bytes.

    property size_plus_offset_gt_data_width_p;
      @(posedge clk) disable iff(!reset_n || !has_checks)
      valid |-> size + offset <= (DATA_WIDTH / 8);
    endproperty
    
    SIZE_PLUS_OFFSET_GT_DATA_WIDTH_A : assert property(size_plus_offset_gt_data_width_p) else
      $error("Detected that size + offset is greater than the data width, in bytes.");

  endinterface

`endif