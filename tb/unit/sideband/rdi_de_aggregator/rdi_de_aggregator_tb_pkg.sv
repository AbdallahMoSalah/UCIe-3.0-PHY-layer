package rdi_de_aggregator_tb_pkg;

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

    class rdi_de_aggregator_in_trans;

        rand sb_packet_t data_drive;

        rand bit in_valid = 0;

        sb_srcid_e prev_srcid = ADAPTER;
        sb_packet_t prev_data_drive = '0;


        constraint opcode_c {
            data_drive.header.opcode inside {
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

        constraint srcid_c {
            data_drive.header.srcid inside {
                STACK0       ,
                ADAPTER      ,
                MNGT_PORT_SRC,
                STACK1
            };
        }

        constraint dstid_c {

            if(data_drive.header.srcid == ADAPTER || data_drive.header.srcid == MNGT_PORT_SRC) {
                data_drive.header.dstid inside { 
                    LOCAL_PHY        ,
                    REMOTE_ADAPTER   ,
                    REMOTE_PHY       ,
                    REMOTE_REG_ACCESS,
                    MNGT_PORT_DST    
                };
            }
            else {
                data_drive.header.dstid == LOCAL_PHY;
            }
        }

        constraint payload_c {

            if(get_chunks(data_drive.header.opcode) == 2){
                data_drive.payload == 64'b0;
            }
            else if(get_chunks(data_drive.header.opcode) == 3){
                data_drive.payload[63:32] == 32'b0;
            }
            
        }

        constraint rsvd_c {
            data_drive.header.rsvd0 == '0;
            data_drive.header.rsvd1 == '0;
            data_drive.header.rsvd2 == '0;
        }

        constraint parity_c {
            data_drive.header.cp == (^data_drive.header[61:0]);
            data_drive.header.dp == (^data_drive.payload);
        }

        constraint valid_dist {
            in_valid dist {1 := 60, 0 := 40};
        }

        function void post_randomize();
            prev_data_drive = data_drive;
        endfunction

    endclass

    class rdi_de_aggregator_out_trans;

        logic [31:0] data;

    endclass

    class rdi_de_aggregator_driver;

        virtual rdi_de_aggregator_if vif;

        
        function new(virtual rdi_de_aggregator_if vif);
            this.vif = vif;
        endfunction


        task run();

            rdi_de_aggregator_in_trans pkt;
            pkt = new();
            vif.pl_msg_vld = 0;
            vif.pl_msg = '0;

            forever begin

                @(negedge vif.clk);

                if(vif.pl_msg_ready || !vif.pl_msg_vld) begin
                    assert(pkt.randomize());
                    vif.pl_msg_vld = pkt.in_valid;
                    vif.pl_msg = pkt.data_drive;
                end

            end

        endtask

    endclass


    class rdi_de_aggregator_monitor;

        virtual rdi_de_aggregator_if vif;

        mailbox #(rdi_de_aggregator_in_trans) in_mbx;
        mailbox #(rdi_de_aggregator_out_trans)  out_mbx;

        function new(virtual rdi_de_aggregator_if vif);
            this.vif = vif;
            this.in_mbx = new();
            this.out_mbx = new();
        endfunction


        task run();

            rdi_de_aggregator_in_trans pkt;
            rdi_de_aggregator_out_trans  wd;

            forever begin

                @(posedge vif.clk);

                // input handshake
                if(vif.pl_msg_vld && vif.pl_msg_ready) begin

                    pkt = new();
                    pkt.data_drive = sb_packet_t'(vif.pl_msg);

                    in_mbx.put(pkt); // target 

                end

                // output handshake
                if(vif.pl_cfg_vld) begin

                    wd = new();
                    wd.data = vif.pl_cfg;

                    out_mbx.put(wd); // target 

                end

            end

        endtask

    endclass


    class rdi_de_aggregator_scoreboard;

        rdi_de_aggregator_monitor mon;

        mailbox #(rdi_de_aggregator_out_trans) expected_mbx;
        int pass,fail;

        logic [2:0] num_chunks;

        function new(rdi_de_aggregator_monitor mon);
            this.mon = mon;
            this.expected_mbx = new();
        endfunction


        task run();

            rdi_de_aggregator_in_trans pkt;
            logic [127:0] data;
            rdi_de_aggregator_out_trans inter_pkt;
            int i = 0;
            
            forever begin

                mon.in_mbx.get(pkt);

                data = pkt.data_drive;
                num_chunks = get_chunks(pkt.data_drive.header.opcode);
                
                for(i = 0; i < num_chunks; i++) begin
                    inter_pkt = new();
                    inter_pkt.data = data[32*i +: 32];
                    expected_mbx.put(inter_pkt);
                end
           
            end

        endtask



        task check();

            rdi_de_aggregator_out_trans wd;
            rdi_de_aggregator_out_trans exp;

            forever begin

                expected_mbx.get(exp);
                mon.out_mbx.get(wd);

                if(wd.data !== exp.data) begin
                    $display("rdi_de_aggregator mismatch exp=%h got=%h",exp.data,wd.data);
                    fail++;
                end
                else begin
                    pass++;
                end

            end

        endtask

    endclass 

    
endpackage
