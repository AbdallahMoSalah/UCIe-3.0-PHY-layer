module Link_Controller_tb();

logic         clk;
logic         rst_n;
logic [127:0] Link_msg_send;
logic         Link_vld_send;
logic [127:0] Adapter_msg_send;
logic         Adapter_vld_send;
logic         ser_ready;        // input
logic [63:0]  msg_rcvd;
logic         msg_vld_rcvd;


logic [127:0] Adapter_msg_rcvd;
logic         Adapter_vld_rcvd;
logic [127:0] Link_msg_rcvd;
logic         Link_vld_rcvd;
logic         Adapter_ready;
logic         Link_ready;
logic [63:0]  msg_send;     //output
logic         msg_vld_send;

int pass_count = 0;
int fail_count = 0;

parameter Link =0,Adapter=1 ;
//=====================================//
///////////////////DUT///////////////////
//=====================================//
Link_Controller u_Link_Controller(
    .clk               ( clk               ),
    .rst_n             ( rst_n             ),
    .Link_msg_send     ( Link_msg_send     ),
    .Link_vld_send     ( Link_vld_send     ),
    .Adapter_msg_send  ( Adapter_msg_send  ),
    .Adapter_vld_send  ( Adapter_vld_send  ),
    .ser_ready         ( ser_ready         ),
    .msg_rcvd          ( msg_rcvd          ),
    .msg_vld_rcvd      ( msg_vld_rcvd      ),
    .Adapter_msg_rcvd  ( Adapter_msg_rcvd  ),
    .Adapter_vld_rcvd  ( Adapter_vld_rcvd  ),
    .Link_msg_rcvd     ( Link_msg_rcvd     ),
    .Link_vld_rcvd     ( Link_vld_rcvd     ),
    .Adapter_ready     ( Adapter_ready     ),
    .Link_ready        ( Link_ready        ),
    .msg_send          ( msg_send          ),
    .msg_vld_send      ( msg_vld_send      )
);

//============================//
////////////tasks///////////////
//============================//

task automatic apply_reset();
    begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end
endtask

task automatic send_msg(
    input logic [127:0] msg,
    input logic         type_m, // link =0 , adapter = 1
);
begin
    Link_msg_send='0;
    Link_vld_send=0;
    Adapter_msg_send='0;
    Adapter_vld_send=0;
    
@(posedge clk);
    if (type_m==Adapter)begin
        Adapter_msg_send= msg;
        Adapter_vld_send=1;
    end
    else if (type_m==Link) begin
        Link_msg_send= msg;
        Link_vld_send=1;
    end
    if(Link_vld_send || Adapter_vld_send) begin
    @(posedge clk);
        if (type_m==Link) begin
            if (Link_ready) begin
                Link_vld_send = 0;
            end
        end
        else if (type_m==Adapter) begin
            if (Adapter_ready) begin
                Adapter_vld_send = 0;
            end
        end
    end

end
endtask

task automatic receive_msg(
    input logic [63:0] recived_half,
);
@(posedge clk);
    msg_rcvd = recived_half;
    msg_vld_rcvd = 1;
@(posedge clk);
endtask 


//=====================================//
/////////////initial block///////////////
//=====================================//
initial begin
    clk = 0;
    forever #5 clk = ~clk;  
end


initial begin
    ser_ready = 1;
    apply_reset();
    
    send_msg(128'h1234567890abcdef1234567890abcdef,Link);
    receive_msg(64'h1234567890abcdef);
    #20 $display("PASS = %0d", pass_count);
    $display("FAIL = %0d", fail_count);

    
end  

endmodule