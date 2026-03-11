module Link_Arbiter (

    input  logic [127:0] LINK_msg,
    input  logic         LINK_vld,
    output logic         LINK_ready,

    input  logic [127:0] adapter_msg,
    input  logic         adapter_not_empty,
    output logic         adapter_rd_en,


    input  logic         mapper_ready,

    output logic [127:0] msg_word_send,
    output logic         valid_s
);

logic sel_link;
logic sel_adapter;

assign sel_link    = LINK_vld;
assign sel_adapter = !LINK_vld && adapter_not_empty;

// output mux
assign msg_word_send = sel_link ? LINK_msg : adapter_msg;
assign valid_s       = sel_link | sel_adapter;

// backpressure
assign LINK_ready    = mapper_ready && sel_link;
assign adapter_rd_en = mapper_ready && sel_adapter;

endmodule

