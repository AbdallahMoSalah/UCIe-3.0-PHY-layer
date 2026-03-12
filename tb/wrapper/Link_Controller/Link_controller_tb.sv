module Link_Controller_tb();

logic         clk,
logic         rst_n,
logic [127:0] LINK_msg,
logic         LINK_valid,
logic [127:0] remote_msg,
logic         remote_vld,
logic         ser_ready,
logic [63:0]  msg_rcvd,
logic         msg_vld_r,
logic [127:0] Adapter_msg
logic         Adapter_val
logic [127:0] LINK_msg_rc
logic         LINK_valid_
logic         remote_read
logic         LINK_ready,
logic [63:0]  msg_send,
logic         msg_vld_s  

int pass_count = 0;
int fail_count = 0;

parameter Link =0,adapter=1 ;
//=====================================//
//                 DUT                 //
//=====================================//
Link_Controller u_Link_Controller(
    .clk               ( clk               ),
    .rst_n             ( rst_n             ),
    .LINK_msg          ( LINK_msg          ),
    .LINK_valid        ( LINK_valid        ),
    .remote_msg        ( remote_msg        ),
    .remote_vld        ( remote_vld        ),
    .ser_ready         ( ser_ready         ),
    .msg_rcvd          ( msg_rcvd          ),
    .msg_vld_r         ( msg_vld_r         ),
    .Adapter_msg_rcvd  ( Adapter_msg_rcvd  ),
    .Adapter_valid_r   ( Adapter_valid_r   ),
    .LINK_msg_rcvd     ( LINK_msg_rcvd     ),
    .LINK_valid_r      ( LINK_valid_r      ),
    .remote_ready      ( remote_ready      ),
    .LINK_ready        ( LINK_ready        ),
    .msg_send          ( msg_send          ),
    .msg_vld_s         ( msg_vld_s         )
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
    LINK_msg='0;
    LINK_valid=0;
    remote_msg=0;
    remote_vld=0;
    

    if (adapter)begin
        remote_msg= msg;
        remote_vld=1
    end
    else begin
        LINK_msg= msg;
        LINK_valid=1;
    end
    
end
endtask

endmodule