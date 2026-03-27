module Link_Controller (
    input   logic         clk,
    input   logic         rst_n,
    input   logic [127:0] Link_msg_send,
    input   logic         Link_vld_send,
    input   logic [127:0] Adapter_msg_send,
    input   logic         Adapter_vld_send,
    input   logic         ser_ready,
    input   logic [63:0]  msg_rcvd,
    input   logic         msg_vld_rcvd,

    output  logic [127:0] Adapter_msg_rcvd,
    output  logic         Adapter_vld_rcvd,
    output  logic [127:0] LINK_msg_rcvd,
    output  logic         Link_valid_rcvd,
    output  logic         Adapter_ready,
    output  logic         Link_ready,
    output  logic [63:0]  msg_send,
    output  logic         msg_vld_send  
);


logic [127:0] msg_word_rcvd;
logic word_vld_rcvd;

logic word_vld_send;
logic [127:0] msg_word_send;
logic mapper_ready;






Link_Arbiter u_Link_Arbiter (
    .Link_msg_send     ( Link_msg_send     ),
    .Link_vld_send     ( Link_vld_send     ),
    .Link_ready        ( Link_ready        ),
    .Adapter_msg_send  ( Adapter_msg_send  ),
    .Adapter_vld_send  ( Adapter_vld_send  ),
    .Adapter_ready     ( Adapter_ready     ),
    .mapper_ready      ( mapper_ready      ),
    .msg_word_send     ( msg_word_send     ),
    .word_vld_send     ( word_vld_send     )
);

LINK_Demux u_LINK_Demux(
    .msg_word_rcvd    (  msg_word_rcvd     ),
    .word_vld_rcvd    (  word_vld_rcvd     ),
    .Adapter_msg_rcvd (  Adapter_msg_rcvd  ),
    .Adapter_vld_rcvd (  Adapter_vld_rcvd  ),
    .LINK_msg_rcvd    (  LINK_msg_rcvd     ),
    .Link_valid_rcvd  (  Link_valid_rcvd   )
);

sb_mapper u_sb_mapper(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .msg_word_send  ( msg_word_send  ),
    .word_vld_send  ( word_vld_send  ),
    .ser_ready      ( ser_ready      ),
    .mapper_ready   ( mapper_ready   ),
    .msg_send       ( msg_send       ),
    .msg_vld_send   ( msg_vld_send   )
);

sb_demapper u_DEMAPPER(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .msg_rcvd       ( msg_rcvd       ),
    .msg_vld_rcvd   ( msg_vld_rcvd   ),
    .msg_word_rcvd  ( msg_word_rcvd  ),
    .word_vld_rcvd  ( word_vld_rcvd  )
);


endmodule
