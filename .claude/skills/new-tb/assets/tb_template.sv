// ============================================================================
//  Testbench : __TB__
//  DUT       : __DUT__
//  Run       : make run CONFIG=__CONFIG__ TOP=__TB__
//
//  Verdict tokens (kept compatible with the sim-run / regression skills):
//    per-check : [PASS] / [FAIL]
//    epilogue  : ">>> PASS ..."  or  ">>> FAIL ..."
//    guard     : "[WATCHDOG] timeout! pass=%0d fail=%0d"
// ============================================================================
`timescale 1ns/1ps

module __TB__;

  // ---- clock / reset --------------------------------------------------------
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;          // 100 MHz; match the DUT's intended rate

  // ---- DUT I/O --------------------------------------------------------------
  // __PORTS__  (declare the real DUT signals here)

  // ---- DUT instance ---------------------------------------------------------
  __DUT__ dut (
    // .clk   (clk),
    // .rst_n (rst_n),
    // __PORTS__  (connect the real ports here)
  );

  // ---- scoreboard counters --------------------------------------------------
  int pass = 0;
  int fail = 0;

  task automatic check(input bit cond, input string what);
    if (cond) begin pass++; $display("  [PASS] %s", what); end
    else      begin fail++; $display("  [FAIL] %s", what); end
  endtask

  // ---- watchdog -------------------------------------------------------------
  localparam int TIMEOUT_NS = 100_000;   // tune per TB
  initial begin
    #(TIMEOUT_NS);
    $display("[WATCHDOG] timeout! pass=%0d fail=%0d", pass, fail);
    $finish;
  end

  // ---- stimulus -------------------------------------------------------------
  initial begin
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;

    // ---------------------------------------------------------------
    // SCENARIOS — drive inputs, then check(...) expected outputs.
    // Example:
    //   @(posedge clk); drive(...);
    //   @(posedge clk); check(dut.o_result === expected, "result after X");
    // ---------------------------------------------------------------

    // ---- epilogue ----
    $display("----------------------------------------------------------------");
    if (fail == 0)
      $display(">>> PASS : __TB__  (%0d/%0d checks)", pass, pass);
    else
      $display(">>> FAIL : __TB__  (%0d passed, %0d failed)", pass, fail);
    $finish;
  end

endmodule
