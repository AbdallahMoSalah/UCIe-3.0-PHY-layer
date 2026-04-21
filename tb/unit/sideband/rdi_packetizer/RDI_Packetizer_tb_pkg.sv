package RDI_Packetizer_tb_pkg;
    import sb_pkg::*;
    import rdi_codec_pkg::*;

    typedef enum bit [1:0]{WITHOUT_RESET, WITH_RESET, NORMAL} testType_t;
    class RDI_Packetizer_class;
        rand logic rst_n;
        rand sb_rdi_msg_no_e RDI_msg_no_send;
        rand logic stall_send;
        rand logic RDI_vld_send;
        rand logic push_ready;

        testType_t testtype = WITHOUT_RESET;
        sb_rdi_msg_no_e Prev_RDI_msg_no_send = NOP;
        logic Prev_push_ready = 1;
        logic Prev_RDI_vld_send = 0;

        sb_header_u exp_hdr;

        logic RDI_vld_out_exp;

        constraint rst_constraint{
            if(testtype == WITHOUT_RESET){
                rst_n == 1;
            }else if(testtype == WITH_RESET){
                rst_n == 0;
            }
            else {
                rst_n dist { 1 :/ 80, 0 :/20};
            }
            
        }

        constraint stall_constraint{
            if(RDI_msg_no_send >= ACTIVE_RSP && (RDI_msg_no_send != NOP)){
                stall_send dist { 1 :/ 70, 0 :/30};
            }
            else {
                stall_send dist { 1 :/ 10, 0 :/ 90};
            }
        }

        constraint push_ready_constraint{
            push_ready dist { 1 :/ 80, 0 :/ 20};
        }

        constraint RDI_msg_no_send_constraint{
            if(Prev_push_ready == 0 ){
                RDI_msg_no_send == Prev_RDI_msg_no_send;
            }
        }

        constraint RDI_vld_send_constraint{
            if(Prev_push_ready == 0  && Prev_RDI_vld_send == 1){
                RDI_vld_send == 1;
            }
            else {
                RDI_vld_send dist { 1 :/ 80, 0 :/ 20};
            }
        }


    function void build_expected();
        sb_header_u hdr;
        hdr = encode_rdi_header(RDI_msg_no_send, stall_send);

        if (!rst_n) begin
            RDI_vld_out_exp = 1'b0;  // No valid message on reset
            exp_hdr  = '0;  // Clear header on reset
        end else if (RDI_vld_send && push_ready) begin
            exp_hdr  = hdr;
            RDI_vld_out_exp = 1'b1;  // Indicate that the message is valid and ready to be sent  
        end else begin
            RDI_vld_out_exp = 1'b0;  // No valid message if not sending
        end
        
    endfunction

    function void post_randomize();
      Prev_RDI_msg_no_send = RDI_msg_no_send;
      Prev_push_ready = push_ready;
      Prev_RDI_vld_send = RDI_vld_send;
    endfunction

        
    endclass
endpackage