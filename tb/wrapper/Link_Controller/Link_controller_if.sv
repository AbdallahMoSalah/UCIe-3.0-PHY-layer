interface Link_controller_if(input bit clk);
    

      logic         rst_n;
      logic [127:0] Link_msg_send;
      logic         Link_vld_send;
      logic [127:0] Adapter_msg_send;
      logic         Adapter_vld_send;
      logic         ser_ready;

      logic  [63:0] des_data_rcvd;
      logic         des_vld_rcvd;

      logic         pattern_mode;
      logic         start_pat_req;
      logic         send_4_iter;

      logic         four_iter_done;
      logic         det_pat_rcvd;

      logic [63:0]  ser_data_send;
      logic         ser_vld_send;

      logic [127:0] Adapter_msg_rcvd;
      logic         Adapter_vld_rcvd;
      logic [127:0] LINK_msg_rcvd;
      logic         Link_valid_rcvd;
      logic         Adapter_ready;
      logic         Link_ready;
      logic         mapper_ready;
endinterface