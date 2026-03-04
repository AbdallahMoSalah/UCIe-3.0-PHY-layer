package RDI_DePacketizer_tb_pkg;

    import sb_pkg::*;
    import rdi_codec_pkg::*;

    typedef enum bit [1:0] {WITHOUT_RESET, WITH_RESET, NORMAL} testType_t;

    typedef enum bit [2:0] {
        NO_ERROR,
        PARITY_ERROR,
        OPCODE_ERROR,
        MSGCODE_ERROR,
        MSGSUBCODE_ERROR
    } error_type_t;

    class RDI_DePacketizer_class;

        rand logic rst_n;
        rand sb_rdi_msg_no_e msg_no;
        rand logic stall;
        rand logic LINK_vld_rcvd;

        testType_t testtype = WITHOUT_RESET;

        logic [127:0] LINK_msg;

        rand error_type_t error_type;
        logic affects_decode;

        rand sb_opcode_e error_opcode;

        rand logic [7:0] not_msgcode;
        rand logic [7:0] not_msgsubcode;

        sb_header_t hdr;
        
        int bit_pos;
        // expected
        sb_rdi_msg_no_e exp_msg_no;
        logic exp_stall;
        logic exp_vld;

        // --------------------------
        // Constraints
        // --------------------------

        constraint rst_c {
            if (testtype == WITHOUT_RESET)
                rst_n == 1;
            else if (testtype == WITH_RESET)
                rst_n == 0;
            else
                rst_n dist {1:/80, 0:/20};
        }

        constraint vld_c {
            LINK_vld_rcvd dist {1:/80, 0:/20};
        }
        constraint op_c {
            error_opcode != SB_MSG_WITHOUT_DATA;
        }
        constraint error_c {  
            !(not_msgcode inside {8'h01, 8'h02});
            !(not_msgsubcode inside {8'h01, 8'h02, 8'h04, [8'h08 : 8'h0C]});
        }

        constraint error_dist {
            soft error_type dist {
                NO_ERROR        :/ 75,
                PARITY_ERROR    :/ 10,
                OPCODE_ERROR    :/ 5,
                MSGCODE_ERROR   :/ 5,
                MSGSUBCODE_ERROR:/ 5
            };
        }

        // --------------------------
        // Expected model
        // --------------------------

        function void build_expected();

            
            affects_decode = 0;

            hdr = encode_rdi_header(msg_no, stall);

            case (error_type)

                PARITY_ERROR: begin
                    hdr.cp = ~hdr.cp;
                    affects_decode = 1;
                end
                    
                OPCODE_ERROR: begin
                    hdr.opcode = error_opcode;
                    affects_decode = 1;
                end

                MSGCODE_ERROR: begin
                    hdr.msgcode = msg_code_e'(not_msgcode);
                    affects_decode = 1;
                end
                MSGSUBCODE_ERROR: begin
                    hdr.MsgSubcode = not_msgsubcode;
                    affects_decode = 1;
                end

                default: affects_decode = 0;

            endcase
            LINK_msg[63:0]   = hdr;
            LINK_msg[127:64] = 64'b0;

            if (!rst_n) begin
                exp_vld     = 0;
                exp_msg_no  = NOP;
                exp_stall   = 0;
            end
            else if (LINK_vld_rcvd && msg_no != NOP) begin

                if (affects_decode == 0) begin
                    exp_vld     = 1;
                    exp_msg_no  = msg_no;
                    exp_stall   = (msg_no >= ACTIVE_RSP ) ? stall : 0;
                end
                else begin
                    exp_vld    = 0;
                    exp_msg_no = NOP;
                    exp_stall  = 0;
                end
            end
            else begin
                exp_vld     = 0;
                exp_msg_no = NOP;
                exp_stall = 0;
            end

        endfunction

    endclass

endpackage