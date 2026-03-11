package Packetizer_tb_pkg;
    import sb_pkg::*;
    import UCIe_pkg::*;
    import msg_codec_pkg::*;

class Packetizer_class;

    rand logic rst_n;

    rand logic [63:0] msg_data_send;
    rand logic [15:0] msg_info_send;
    rand msg_no_e msg_no_send;
    rand logic valid_send;
    rand logic stall_send;
    
    rand logic LINK_ready;

    msg_no_e prev_msg_no_send=NOP;
    logic prev_valid_send=1'b0;
    logic [127:0] prev_msg;
    logic prev_LINK_ready;

    logic [127:0] exp_msg;
    logic exp_vld,exp_ready;
    sb_header_t hdr;

    
    constraint rst_constraint{
        rst_n dist { 1 :/ 80, 0 :/20};
    }

    constraint LINK_ready_constraint{
        LINK_ready dist { 1 :/ 80, 0 :/ 20};
    }

    constraint stall_constraint{
        if(msg_no_send >= RDI_ACTIVE_RSP && (msg_no_send <= RDI_PMNAK_RSP)){
            stall_send dist { 1 :/ 70, 0 :/30};
        }
        else {
            stall_send dist { 1 :/ 10, 0 :/ 90};
        }
    }

    constraint msg_no_send_constraint{
        if(LINK_ready == 0 ){
            msg_no_send == prev_msg_no_send;
        }
    }

    constraint valid_send_constraint{
        if(LINK_ready == 0){
            valid_send == prev_valid_send;
        }
        else {
            valid_send dist { 1 :/ 80, 0 :/ 20};
        }
    }

    function void build_expected();  // Build expected header based on the input message number
        hdr =encode_msg_header(msg_no_send, msg_info_send, msg_data_send, stall_send);
        exp_ready = LINK_ready;

        if (rst_n == 1'b0) begin
            exp_msg = 128'h0;
            exp_vld = 1'b0;
        end
        else begin 
            if (valid_send && LINK_ready) begin
                exp_msg = {msg_data_send, hdr};
                exp_vld = 1'b1;
            end
            else begin
                exp_vld = 1'b0;
            end
        end
    endfunction       
    function void post_randomize();
        prev_msg_no_send = msg_no_send;
        prev_valid_send = valid_send;
        prev_LINK_ready = LINK_ready;
    endfunction


endclass
endpackage