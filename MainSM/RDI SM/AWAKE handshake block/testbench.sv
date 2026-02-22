module testbench();
    //inputs outputs decalearation 
    reg lclk, lp_awak_req, ungating_done;
    wire pl_awak_ack, ungating_req;

    //instansiation
    AWAKE_handshake_block DUT (lp_awak_req, ungating_done, lclk, 
                               pl_awak_ack, ungating_req);
    
    //clk generation
    initial begin  
    lclk=0;
    forever
        #5 lclk=~lclk;
    end

    //test vectors
    initial begin
        //reset inputs 
        lp_awak_req=0;
        ungating_done=0;
        
        repeat (10) @(negedge lclk); //wait for 50 clk cycle

        //start handshake
        lp_awak_req=1;
        #50 ungating_done=1;
        wait (pl_awak_ack)begin //wait till ungaing is done and response with ack
            repeat (5) begin 
                @(negedge lclk);//wait for 5 clk cycles to make sure pl_awak_req is not deasserted till lp_awak_req is deasserted
                if (~pl_awak_ack)
                    $display("pl_awak_ack is deasserted before lp_awak_req is deasserted");
            end 
            lp_awak_req=0;
        end
    
    #50 $stop;
    end
endmodule