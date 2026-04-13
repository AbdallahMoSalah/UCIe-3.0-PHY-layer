module Link_Controller (
    //tx
    input   logic         clk,
    input   logic         rst_n,
    input   logic [127:0] Link_msg_send,
    input   logic         Link_vld_send,
    input   logic [127:0] Adapter_msg_send,
    input   logic         Adapter_vld_send,
    input   logic         ser_ready,

    
    input   logic         pattern_mode,
    input   logic         start_pat_req,
    input   logic         send_4_iter,

    output  logic         four_iter_done,

    output  logic [63:0]  ser_data_send,
    output  logic         ser_vld_send,
    
    output  logic         Adapter_ready,
    output  logic         Link_ready,
    //rx
    output  logic         det_pat_rcvd,

    input   logic  [63:0] des_data_rcvd,
    input   logic         des_vld_rcvd,

    output  logic [127:0] Adapter_msg_rcvd,
    output  logic         Adapter_vld_rcvd,
    output  logic [127:0] LINK_msg_rcvd,
    output  logic         Link_valid_rcvd

);


logic [127:0] msg_word_rcvd;
logic word_vld_rcvd;

logic word_vld_send;
logic [127:0] msg_word_send;
logic mapper_ready;

logic [63:0]  msg_send;
logic         msg_vld_send;

logic [63:0]  msg_rcvd;
logic         msg_vld_rcvd;



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
    .Link_msg_rcvd    (  LINK_msg_rcvd     ),
    .Link_vld_rcvd    (  Link_valid_rcvd   )
);

sb_mapper u_sb_mapper(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .msg_word_send  ( msg_word_send  ),
    .word_vld_send  ( word_vld_send  ),
    .ser_ready      ( msg_path_ready ),
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

sb_pattern_detector#(
    .DATA_WIDTH     ( 64 )
)u_sb_pattern_detector(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .pattern_mode   ( pattern_mode   ),
    .des_data_rcvd  ( des_data_rcvd  ),
    .des_vld_rcvd   ( des_vld_rcvd   ),
    .det_pat_rcvd   ( det_pat_rcvd   ),
    .msg_rcvd       ( msg_rcvd       ),
    .msg_vld_rcvd   ( msg_vld_rcvd   )
);

sb_pattern_engine u_sb_pattern_engine(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .pattern_mode   ( pattern_mode   ),
    .start_pat_req  ( start_pat_req  ),
    .send_4_iter    ( send_4_iter    ),
    .four_iter_done ( four_iter_done ),
    .mapper_data    ( msg_send       ),
    .mapper_valid   ( msg_vld_send   ),
    .mapper_ready   ( msg_path_ready ),
    .ser_ready      ( ser_ready      ),
    .ser_data       ( ser_data_send  ),
    .ser_valid      ( ser_vld_send   )
);


endmodule
