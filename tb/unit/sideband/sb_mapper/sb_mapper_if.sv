interface sb_mapper_if(input bit clk);

    logic rst_n;

    logic [127:0] msg_word_send;
    logic word_vld_send;

    logic ser_ready;

    logic mapper_ready;
    logic [63:0] msg_send;
    logic msg_vld_send;

endinterface