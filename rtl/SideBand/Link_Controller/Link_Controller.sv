module Link_Controller (
    //tx
    input   logic         clk,
    input   logic         rst_n,
    input   logic [127:0] trn_msg_send,
    input   logic         trn_vld_send,
    output  logic         trn_rdy,

    input   logic [127:0] adapter_msg_send,
    input   logic         adapter_vld_send,
    output  logic         adapter_rdy,

    
    input   logic         pattern_mode,
    input   logic         start_pat_req,
    input   logic         send_4_iter,

    output  logic         four_iter_done,

    input   logic         ser_rdy,
    output  logic [63:0]  ser_data_send,
    output  logic         ser_vld_send,
    
    //rx
    output  logic         det_pat_rcvd,

    input   logic  [63:0] des_data_rcvd,
    input   logic         des_vld_rcvd,

    output  logic [127:0] adapter_msg_rcvd,
    output  logic         adapter_vld_rcvd,
    output  logic [127:0] trn_msg_rcvd,
    output  logic         trn_vld_rcvd

);


logic [127:0] msg_word_rcvd;
logic word_vld_rcvd;

logic word_vld_send;
logic [127:0] msg_word_send;
logic mapper_rdy;

logic [63:0]  msg_send;
logic         msg_vld_send;

logic [63:0]  msg_rcvd;
logic         msg_vld_rcvd;

logic         msg_path_rdy;



sb_priority_arbiter #(
    .DATA_WIDTH(128)
) u_Link_Arbiter (
    .hip_msg           ( trn_msg_send     ),
    .hip_vld           ( trn_vld_send     ),
    .hip_rdy         ( trn_rdy        ),
    .lop_msg           ( adapter_msg_send  ),
    .lop_vld           ( adapter_vld_send  ),
    .lop_rdy         ( adapter_rdy     ),
    .out_msg           ( msg_word_send     ),
    .out_vld           ( word_vld_send     ),
    .out_rdy         ( mapper_rdy      )
);

LINK_Demux u_LINK_Demux(
    .msg_word_rcvd    (  msg_word_rcvd     ),
    .word_vld_rcvd    (  word_vld_rcvd     ),
    .adapter_msg_rcvd (  adapter_msg_rcvd  ),
    .adapter_vld_rcvd (  adapter_vld_rcvd  ),
    .trn_msg_rcvd    (  trn_msg_rcvd     ),
    .trn_vld_rcvd    (  trn_vld_rcvd   )
);

sb_mapper u_sb_mapper(
    .clk            ( clk            ),
    .rst_n          ( rst_n          ),
    .msg_word_send  ( msg_word_send  ),
    .word_vld_send  ( word_vld_send  ),
    .ser_rdy      ( msg_path_rdy ),
    .mapper_rdy   ( mapper_rdy   ),
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
    .mapper_rdy   ( msg_path_rdy ),
    .ser_rdy      ( ser_rdy      ),
    .ser_data       ( ser_data_send  ),
    .ser_valid      ( ser_vld_send   )
);


endmodule
