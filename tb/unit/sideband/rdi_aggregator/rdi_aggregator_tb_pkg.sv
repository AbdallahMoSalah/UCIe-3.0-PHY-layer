package rdi_aggregator_tb_pkg;

    import sb_pkg::*;


    function automatic logic [2:0] get_chunks(input logic [4:0] opcode);
        case(opcode)
            // header only
            SB_32_MEM_READ,
            SB_32_DMS_REG_READ,
            SB_32_CFG_READ,
            SB_64_MEM_READ,
            SB_64_DMS_REG_READ,
            SB_64_CFG_READ,
            SB_COMPLETION_WITHOUT_DATA,
            SB_MSG_WITHOUT_DATA,
            SB_MNGT_PORT_MSG_WITHOUT_DATA:
                return 2;
            // header + 32 data
            SB_32_MEM_WRITE,
            SB_32_DMS_REG_WRITE,
            SB_32_CFG_WRITE,
            SB_COMPLETION_WITH_32_DATA:
                return 3;
            // header + 64 data
            SB_64_MEM_WRITE,
            SB_64_DMS_REG_WRITE,
            SB_64_CFG_WRITE,
            SB_COMPLETION_WITH_64_DATA,
            SB_MSG_WITH_64_DATA:
                return 4;
            default:
                return 2;
        endcase
    endfunction

    class rdi_aggregator_in_trans;

        rand bit [31:0] data;
        rand sb_packet_t data_drive;

        int reverse_chunk_counter = 0;
        int chunk_counter = 0;
        rand bit in_valid = 0;

        sb_srcid_e prev_srcid = ADAPTER;
        sb_packet_t prev_data_drive = '0;


        constraint opcode_c {
            if((reverse_chunk_counter == 0) && (in_valid)){
                data_drive.header.msg.opcode inside {
                    SB_32_MEM_READ               ,
                    SB_32_MEM_WRITE              ,
                    SB_32_DMS_REG_READ           ,
                    SB_32_DMS_REG_WRITE          ,
                    SB_32_CFG_READ               ,
                    SB_32_CFG_WRITE              ,
                    SB_64_MEM_READ               ,
                    SB_64_MEM_WRITE              ,
                    SB_64_DMS_REG_READ           ,
                    SB_64_DMS_REG_WRITE          ,
                    SB_64_CFG_READ               ,
                    SB_64_CFG_WRITE              ,
                    SB_COMPLETION_WITHOUT_DATA   ,
                    SB_COMPLETION_WITH_32_DATA   ,
                    SB_MSG_WITHOUT_DATA          ,
                    SB_MNGT_PORT_MSG_WITHOUT_DATA,
                    SB_MNGT_PORT_MSG_WITH_DATA   ,
                    SB_COMPLETION_WITH_64_DATA   ,
                    SB_MSG_WITH_64_DATA          ,
                    SB_PRIORITY_MSG1             ,
                    SB_PRIORITY_MSG2             
                };
            }
            else {
                data_drive.header.msg.opcode == prev_data_drive.header.msg.opcode;
            }
            
        }

        constraint srcid_c {
            if((reverse_chunk_counter == 0) && (in_valid)){
                data_drive.header.msg.srcid inside {
                    STACK0       ,
                    ADAPTER      ,
                    MNGT_PORT_SRC,
                    STACK1
                };
            }
            else {
                data_drive.header.msg.srcid == prev_data_drive.header.msg.srcid;
            }
            
        }

        constraint msgcode_c {
            if(!((reverse_chunk_counter == 0) && (in_valid))){
                data_drive.header.msg.msgcode == prev_data_drive.header.msg.msgcode;
            }
        }


        constraint MsgSubcode_c {
            if(!((reverse_chunk_counter == 0) && (in_valid))){
                data_drive.header.msg.MsgSubcode == prev_data_drive.header.msg.MsgSubcode;
            }
            
        }

        constraint MsgInfo_c {
            if(!((reverse_chunk_counter == 0) && (in_valid))){
                data_drive.header.msg.MsgInfo == prev_data_drive.header.msg.MsgInfo;
            }
            
        }

        constraint dstid_c {

            if((reverse_chunk_counter == 0) && (in_valid)){
                if(data_drive.header.msg.srcid == ADAPTER || data_drive.header.msg.srcid == MNGT_PORT_SRC) {
                    data_drive.header.msg.dstid inside { 
                        LOCAL_PHY        ,
                        REMOTE_ADAPTER   ,
                        REMOTE_PHY       ,
                        REMOTE_REG_ACCESS,
                        MNGT_PORT_DST    
                    };
                }
                else {
                    data_drive.header.msg.dstid == LOCAL_PHY;
                }
            }
            else {
                data_drive.header.msg.dstid == prev_data_drive.header.msg.dstid;
            }
            
            
        }

        constraint payload_c {

            if((reverse_chunk_counter == 0) && (in_valid)){
                if(get_chunks(data_drive.header.msg.opcode) == 2){
                    data_drive.payload == 64'b0;
                }
                else if(get_chunks(data_drive.header.msg.opcode) == 3){
                    data_drive.payload[63:32] == 32'b0;
                }
            }
            else {
                data_drive.payload == prev_data_drive.payload;
            }
            
            
        }

        constraint rsvd_c {
            data_drive.header.rsvd0 == '0;
            data_drive.header.rsvd1 == '0;
            data_drive.header.rsvd2 == '0;
        }
        constraint parity_c {
            data_drive.header.msg.cp == (^data_drive.header.raw[61:0]);
            data_drive.header.msg.dp == (^data_drive.payload);
        }

        constraint valid_dist {
            if(reverse_chunk_counter == 0) {
                in_valid dist {1 := 40, 0 := 60};
            }
            else {
                in_valid == 1;
            }
            
        }

        function void post_randomize();
            if((reverse_chunk_counter == 0) && (in_valid)) begin
                reverse_chunk_counter = get_chunks(data_drive.header.msg.opcode);
                chunk_counter = 0;
            end
            if(reverse_chunk_counter != 0)begin
                reverse_chunk_counter--;
                chunk_counter++;
            end

            prev_data_drive = data_drive;
            
        endfunction

    endclass

    class rdi_aggregator_out_trans;

        sb_packet_t data;

    endclass
    class rdi_aggregator_driver;

        virtual rdi_aggregator_if vif;

        
        function new(virtual rdi_aggregator_if vif);
            this.vif = vif;
        endfunction


        task run();

            rdi_aggregator_in_trans pkt;
            pkt = new();

            forever begin

                @(negedge vif.clk);

                
                assert(pkt.randomize());

                
                vif.lp_cfg_vld = pkt.in_valid;
                
                if(pkt.in_valid) begin
                    vif.lp_cfg = pkt.data_drive[32*(pkt.chunk_counter-1) +: 32] ;
                end

            end

        endtask

    endclass


    class rdi_aggregator_monitor;

        virtual rdi_aggregator_if vif;

        mailbox #(rdi_aggregator_in_trans) in_mbx;
        mailbox #(rdi_aggregator_out_trans)  out_mbx;

        function new(virtual rdi_aggregator_if vif);
            this.vif = vif;
            this.in_mbx = new();
            this.out_mbx = new();
        endfunction


        task run();

            rdi_aggregator_in_trans pkt;
            rdi_aggregator_out_trans  wd;

            forever begin

                @(posedge vif.clk);

                // input handshake
                if(vif.lp_cfg_vld ) begin

                    pkt = new();
                    pkt.data = vif.lp_cfg;

                    in_mbx.put(pkt); // target 

                end

                // output handshake
                if(vif.lp_msg_vld ) begin

                    wd = new();
                    wd.data = vif.lp_msg;

                    out_mbx.put(wd); // target 

                end

            end

        endtask

    endclass


    class rdi_aggregator_scoreboard;

        rdi_aggregator_monitor mon;

        mailbox #(rdi_aggregator_out_trans) expected_mbx;
        int pass,fail;

        int num_chunks;

        function new(rdi_aggregator_monitor mon);
            this.mon = mon;
            this.expected_mbx = new();
        endfunction


        task run();

            rdi_aggregator_in_trans pkt;
            bit [127:0] data;
            rdi_aggregator_out_trans inter_pkt;
            int i = 0;
            forever begin
                data = '0;
                i = 0;

                mon.in_mbx.get(pkt);

                num_chunks = get_chunks(pkt.data[4:0]);
                
                for(; i < num_chunks - 1; i++) begin
                    data[32*i +: 32] = pkt.data;
                    mon.in_mbx.get(pkt);
                end
                data[32*i +: 32] = pkt.data;
                
                inter_pkt = new();
                inter_pkt.data = sb_packet_t'(data);

                expected_mbx.put(inter_pkt);
           
            end

        endtask



        task check();

            rdi_aggregator_out_trans wd;
            rdi_aggregator_out_trans exp;

            forever begin

                expected_mbx.get(exp);
                mon.out_mbx.get(wd);

                if(wd.data !== exp.data) begin
                    $display("rdi_aggregator mismatch exp=%h got=%h",exp.data,wd.data);
                    fail++;
                end
                else begin
                    pass++;
                end

            end

        endtask

    endclass 

    
endpackage