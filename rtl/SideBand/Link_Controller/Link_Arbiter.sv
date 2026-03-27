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

    sb_priority_arbiter #(
        .DATA_WIDTH(128)
    ) u_sb_priority_arbiter (
        .hp_msg   (Link_msg_send),
        .hp_vld   (Link_vld_send),
        .hp_ready (Link_ready),

        .lp_msg   (Adapter_msg_send),
        .lp_vld   (Adapter_vld_send),
        .lp_ready (Adapter_ready),

        .out_msg  (msg_word_send),
        .out_vld  (word_vld_send),
        .out_ready(mapper_ready)
    );

endmodule

