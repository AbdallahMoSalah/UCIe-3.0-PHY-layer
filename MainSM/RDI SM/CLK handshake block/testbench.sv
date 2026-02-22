module testbench();
    
//inputs and output
reg lp_clk_ack, clk_handshake_strt, lclk;
wire pl_clk_req, clk_handshake_done;

//
CLK_handshake_block DUT (lp_clk_ack, clk_handshake_strt, lclk,
                         pl_clk_req, clk_handshake_done);

//clk generation
initial begin
    lclk=0;
    forever begin
        #5 lclk=~lclk;
    end
end

//testing
initial begin
    //reset inputs 
    lp_clk_ack=0;
    clk_handshake_strt=0;

    //test vectors 
    repeat(10) @(negedge lclk);// wait for 10 clk cycles

    //begin handshake
    clk_handshake_strt=1;

    //ungating is done
    repeat (10) @(negedge lclk);
    lp_clk_ack=1;

    repeat (10) @(negedge lclk);
    #10 $stop;
end 
endmodule