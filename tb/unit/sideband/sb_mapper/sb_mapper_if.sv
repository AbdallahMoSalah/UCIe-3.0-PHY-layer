interface sb_mapper_if(input bit clk);

    logic rst_n;

    logic [127:0] Msg_word_send;
    logic word_valid_s;

    logic ser_ready;

    logic mapper_ready;
    logic [63:0] msg_send;
    logic msg_vld_s;

endinterface