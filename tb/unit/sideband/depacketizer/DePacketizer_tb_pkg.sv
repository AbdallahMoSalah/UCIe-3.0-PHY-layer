package DePacketizer_tb_pkg;

    import sb_pkg::*;
    import UCIe_pkg::*;
    import msg_codec_pkg::*;

    typedef enum bit [2:0] {
        NO_ERROR,
        CP_ERROR,
        DP_ERROR,
        OPCODE_ERROR,
        MSGCODE_ERROR,
        MSGSUBCODE_ERROR
    } error_type_t;

    typedef enum bit [1:0] {WITHOUT_RESET, WITH_RESET, NORMAL} testType_t;

    class DePacketizer_class;

        rand logic rst_n;
        rand msg_no_e msg_no;
        rand logic stall;
        rand logic vld_in;
        rand logic [15:0] msg_info;
        rand logic [63:0] data;

        rand error_type_t error_type;
        testType_t testtype = WITHOUT_RESET;
        rand sb_opcode_e error_opcode;
        logic affects_decode;

        rand logic [7:0] not_msgcode;
        rand logic [7:0] not_msgsubcode;

        msg_code_e valid_msgcode[] =        {SBINIT_OFFRESET_DOMAIN,
                                            RX_TEST_SWEEP_DONE_RESULT,
                                            SBINIT_REQ_DOMAIN,     
                                            SBINIT_RESP_DOMAIN,    
                                            MBINIT_REQ_DOMAIN,     
                                            MBINIT_RESP_DOMAIN,    
                                            MBTRAIN_REQ_DOMAIN,    
                                            MBTRAIN_RESP_DOMAIN,   
                                            RECAL_REQ_DOMAIN,      
                                            RECAL_RESP_DOMAIN,     
                                            PHYRETRAIN_REQ_DOMAIN, 
                                            PHYRETRAIN_RESP_DOMAIN,
                                            TRAINERROR_REQ_DOMAIN, 
                                            TRAINERROR_RESP_DOMAIN,
                                            RDI_REQ_DOMAIN,        
                                            RDI_RESP_DOMAIN,       
                                            TEST_REQ_DOMAIN,       
                                            TEST_RESP_DOMAIN};

        sb_header_t hdr;
        logic [127:0] msg_in;

        // Expected
        msg_no_e     exp_msg_no;
        logic [15:0] exp_msginfo;
        logic [63:0] exp_payload;
        logic exp_vld;
        logic exp_stall;

        constraint rst_c {
            if (testtype == WITHOUT_RESET)
                rst_n == 1;
            else if (testtype == WITH_RESET)
                rst_n == 0;
            else
                rst_n dist {1:/80, 0:/20};
        }

        constraint vld_c { vld_in dist {1:/80, 0:/20}; }

        constraint op_c {
            !(error_opcode inside  {SB_MSG_WITHOUT_DATA, SB_MSG_WITH_64_DATA});
        }
        constraint error_c {  
            !(not_msgcode inside {valid_msgcode});
            !(not_msgsubcode inside {[8'h00 : 8'h19],[8'h1B : 8'h22]});
        }

        constraint error_dist {
            soft error_type dist {
                NO_ERROR        :/ 70,
                CP_ERROR        :/ 10,
                DP_ERROR        :/ 5,
                OPCODE_ERROR    :/ 5,
                MSGCODE_ERROR   :/ 5,
                MSGSUBCODE_ERROR:/ 5
            };
        }


        // -----------------------------
        // Expected model
        // -----------------------------
        function void build_expected();

            // 1) Build correct header
            hdr = encode_msg_header(msg_no, msg_info, data, stall);

            affects_decode = 1;
            // 2) Inject errors
            case (error_type)

                CP_ERROR: hdr.cp = ~hdr.cp;

                DP_ERROR: begin 
                    affects_decode = 0;
                    if (hdr.opcode == SB_MSG_WITH_64_DATA) begin
                        hdr.dp = ~hdr.dp;
                        affects_decode = 1;
                    end
                end

                OPCODE_ERROR: hdr.opcode = error_opcode;

                MSGCODE_ERROR: hdr.msgcode = msg_code_e'(not_msgcode);

                MSGSUBCODE_ERROR: hdr.MsgSubcode = not_msgsubcode;

                default: affects_decode = 0;
            endcase

            msg_in[63:0]   = hdr;
            msg_in[127:64] = data;

            // ---------------------------------
            // Expected output logic
            // ---------------------------------

            if (!rst_n) begin
                exp_vld      = 0;
                exp_msg_no   = NOTHING;
                exp_msginfo  = 0;
                exp_payload  = 0;
                exp_stall    = 0;
            end
            else if (vld_in && !affects_decode && msg_no != NOTHING && msg_no != NOP) begin
                exp_vld      = 1;
                exp_msg_no   = msg_no;
                exp_msginfo  = hdr.MsgInfo;
                exp_payload  = data;
                exp_stall    = (hdr.MsgInfo == 16'hFFFF);
            end
            else begin
                exp_vld      = 0;
                exp_msg_no   = NOTHING;
                exp_msginfo  = 0;
                exp_payload  = 0;
                exp_stall    = 0;
            end

        endfunction

    endclass

endpackage