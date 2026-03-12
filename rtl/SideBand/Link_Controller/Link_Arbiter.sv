module Link_Arbiter (

    input  logic [127:0] Link_msg_send,
    input  logic         Link_vld_send,
    output logic         Link_ready,

    input  logic [127:0] Adapter_msg_send,
    input  logic         Adapter_vld_send,
    output logic         Adapter_ready,


    input  logic         mapper_ready,

    output logic [127:0] msg_word_send,
    output logic         word_vld_send
);

logic sel_link;
logic sel_Adapter;

assign sel_link    = Link_vld_send;
assign sel_Adapter = !Link_vld_send && Adapter_vld_send;

// output mux
assign msg_word_send = sel_link ? Link_msg_send : Adapter_msg_send;
assign word_vld_send  = sel_link | sel_Adapter;

// backpressure
assign Link_ready    = mapper_ready && sel_link;
assign Adapter_ready = mapper_ready && sel_Adapter;

endmodule

