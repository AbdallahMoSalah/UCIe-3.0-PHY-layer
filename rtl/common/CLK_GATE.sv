
/////////////////////////////////////////////////////////////
/////////////////////// Clock Gating ////////////////////////
/////////////////////////////////////////////////////////////

module CLK_GATE (
input      CLK_EN,
input      CLK,
output     GATED_CLK
);

`ifdef FPGA
// ---------------------------------------------------------------------------
// FPGA target: use the Xilinx BUFGCE global-clock buffer with clock enable.
// BUFGCE is a glitch-free clock gate that drives the GLOBAL clock network
// (it captures CE internally on the falling edge, matching the low-phase
// latch model below). This is the ONLY correct way to gate a clock on FPGA;
// a LUT-driven "CLK & latch" net causes glitches and clock-routing warnings.
// ---------------------------------------------------------------------------
BUFGCE u_bufgce (
    .I  (CLK),
    .CE (CLK_EN),
    .O  (GATED_CLK)
);
`else
// ---------------------------------------------------------------------------
// Simulation / ASIC model: low-phase latch + AND (integrated clock-gate cell).
// ---------------------------------------------------------------------------
//internal connections
reg     Latch_Out ;

//latch (Level Sensitive Device)
always @(CLK or CLK_EN)
 begin
  if(!CLK)      // active low
   begin
    Latch_Out <= CLK_EN ;
   end
 end


// ANDING
assign  GATED_CLK = CLK & Latch_Out ;




/*
TLATNCAX12M U0_TLATNCAX12M (
.E(CLK_EN),
.CK(CLK),
.ECK(GATED_CLK)
);
*/

`endif


endmodule
