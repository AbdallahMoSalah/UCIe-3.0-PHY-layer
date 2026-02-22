import RDI_SM_pkg::*;
module testbench();
    
    logic lclk, pl_phyinrecenter, pl_clk_req, ungating_req; 
    RDI_state pl_state_sts;
    logic lclk_g, ungating_done;

    integer error_c=0;
    GATING_block DUT (lclk, pl_phyinrecenter, pl_clk_req, ungating_req, 
                      pl_state_sts, lclk_g, ungating_done);

    initial begin
        lclk=0;
        forever begin
            #5 lclk=~lclk;
        end
    end

    initial begin
        pl_phyinrecenter = 0;
        pl_clk_req = 0;
        ungating_req = 0;
        pl_state_sts = Active;

        //test Reset
        @(negedge lclk) pl_state_sts = Reset;
        repeat (10) @(posedge lclk or negedge lclk)
            #0; 
            if (lclk_g != 0) begin
                $display("clk is not gated @ state %s,lclk_g=%b time = %t", pl_state_sts.name(), lclk_g, $time);
                error_c++;
            end
        //assert pl_phyinrecenter while in reset state
        @(negedge lclk) pl_phyinrecenter = 1;
        repeat (10) @(posedge lclk or negedge lclk)
            #0;
            if (lclk_g != lclk ) begin
                $display("clk is gated @ state %s, pl_phyinrecenter=%b time = %t", pl_state_sts.name(), pl_phyinrecenter, $time);
                error_c++;            
            end
        //assert ungating_req and deassert pl_phyinreceter
        @(negedge lclk) ungating_req = 1; pl_phyinrecenter=0;
        repeat (10) @(posedge lclk or negedge lclk)
            #0;
            if (lclk_g != lclk ) begin
                $display("clk is gated @ state %s, ungating_req=%b time = %t", pl_state_sts.name(), ungating_req, $time);
                error_c++;            
            end
        //assert pl_clk_req
        @(negedge lclk) ungating_req = 0; pl_clk_req=1;
        repeat (10) @(posedge lclk or negedge lclk)
            #0;
            if (lclk_g != lclk ) begin
                $display("clk is gated @ state %s, pl_clk_req=%b time = %t", pl_state_sts.name(), pl_clk_req, $time);
                error_c++;            
            end
        $display("errors= %0d", error_c);
        
        $stop;
        
    end
endmodule