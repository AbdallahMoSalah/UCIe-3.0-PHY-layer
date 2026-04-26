interface Link_controller_if(input bit clk);
    

      logic         rst_n;
      logic [127:0] trn_msg_send;
      logic         trn_vld_send;
      logic [127:0] adapter_msg_send;
      logic         adapter_vld_send;
      logic         ser_rdy;

      logic  [63:0] des_data_rcvd;
      logic         des_vld_rcvd;

      logic         pattern_mode;
      logic         start_pat_req;
      logic         send_4_iter;

      logic         four_iter_done;
      logic         det_pat_rcvd;

      logic [63:0]  ser_data_send;
      logic         ser_vld_send;

      logic [127:0] adapter_msg_rcvd;
      logic         adapter_vld_rcvd;
      logic [127:0] trn_msg_rcvd;
      logic         trn_vld_rcvd;
      logic         adapter_rdy;
      logic         trn_rdy;
      logic         mapper_rdy;
endinterface