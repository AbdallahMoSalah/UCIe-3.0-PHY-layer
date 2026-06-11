
/////////////////////////////////////////////////////////////
/////////////////////// Clock Gating ////////////////////////
/////////////////////////////////////////////////////////////

module unit_clk_gate (
input      CLK_EN,
input      CLK,
output     GATED_CLK
);



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





endmodule
