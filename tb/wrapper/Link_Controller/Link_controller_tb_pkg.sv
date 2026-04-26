package Link_Controller_tb_pkg;

    import sb_pkg::*;

    class tx_transaction;
        rand sb_packet_t trn_msg_send;
        rand logic       trn_vld_send;
        rand sb_packet_t adapter_msg_send;
        rand logic       adapter_vld_send;
        rand logic       ser_rdy;

        // Control and Status
        logic mapper_rdy;
        logic pattern_mode;
        logic start_pat_req;
        logic send_4_iter;

        // Backpressure state
        sb_packet_t prev_Link_msg;
        logic       prev_Link_vld;
        sb_packet_t prev_Adapter_msg;
        logic       prev_Adapter_vld;

        function new();
            prev_Link_msg = '0;
            prev_Link_vld = 0;
            prev_Adapter_msg = '0;
            prev_Adapter_vld = 0;
        endfunction

        constraint c_basic {
            ser_rdy dist {0 := 80, 1 := 20};
        }

        // Adapter message constraints (Aggregator-like)
        constraint Adapter_msg_c {
            if (mapper_rdy) {
                adapter_msg_send.header.msg.opcode inside {
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

                adapter_msg_send.header.msg.srcid inside {
                    STACK0       ,
                    ADAPTER      ,
                    MNGT_PORT_SRC,
                    STACK1
                };

                if (adapter_msg_send.header.msg.srcid == ADAPTER || adapter_msg_send.header.msg.srcid == MNGT_PORT_SRC) {
                    adapter_msg_send.header.msg.dstid inside { 
                        LOCAL_PHY        ,
                        REMOTE_ADAPTER   ,
                        REMOTE_PHY       ,
                        REMOTE_REG_ACCESS,
                        MNGT_PORT_DST    
                    };
                } else {
                    adapter_msg_send.header.msg.dstid == LOCAL_PHY;
                }
            }
        }

        // Link message constraints (Packetizer-like)
        constraint Link_msg_c {
            if (mapper_rdy) {
                trn_msg_send.header.msg.opcode inside {SB_MSG_WITHOUT_DATA, SB_MSG_WITH_64_DATA};
                trn_msg_send.header.msg.srcid == PHY;
                trn_msg_send.header.msg.dstid == REMOTE_PHY;
            }
        }

        // Backpressure and Randomization Hold
        constraint backpressure_c {
            if (!mapper_rdy) {
                // Hold valid if it was 1
                if (prev_Link_vld) trn_vld_send == 1;
                if (prev_Adapter_vld) adapter_vld_send == 1;
            } else {
                // Normal randomization
                trn_vld_send    dist {1 := 40, 0 := 60};
                adapter_vld_send dist {1 := 40, 0 := 60};
            }
        }

        function void pre_randomize();
            if (!mapper_rdy) begin
                trn_msg_send.rand_mode(0);
                adapter_msg_send.rand_mode(0);
            end else begin
                trn_msg_send.rand_mode(1);
                adapter_msg_send.rand_mode(1);
            end
        endfunction

        function void post_randomize();
            prev_Link_msg    = trn_msg_send;
            prev_Link_vld    = trn_vld_send;
            prev_Adapter_msg = adapter_msg_send;
            prev_Adapter_vld = adapter_vld_send;
        endfunction
    endclass

    class rx_transaction;
        rand logic  [63:0] des_data_rcvd;
        rand logic         des_vld_rcvd;
        logic              pattern_mode;

        constraint c_basic {
            des_vld_rcvd dist {1 := 80, 0 := 20};
        }
    endclass

    class tx_monitor_pkt;
        logic [63:0]  ser_data_send;
        logic         ser_vld_send;
    endclass

    class rx_monitor_pkt;
        logic [127:0] adapter_msg_rcvd;
        logic         adapter_vld_rcvd;
        logic [127:0] trn_msg_rcvd;
        logic         trn_vld_rcvd;
        logic         det_pat_rcvd;
    endclass

    // =================================================================
    // Drivers
    // =================================================================

    class link_controller_tx_driver;
        virtual Link_controller_if vif;
        
        function new(virtual Link_controller_if vif);
            this.vif = vif;
        endfunction

        task run();
            tx_transaction pkt;
            pkt = new();
            forever begin
                @(posedge vif.clk);
                pkt.mapper_rdy = vif.mapper_rdy;
                assert(pkt.randomize());

                if ($time < 540) begin
                    vif.trn_vld_send <= 0;
                    vif.adapter_vld_send <= 0;
                end else begin
                    vif.trn_vld_send <= pkt.trn_vld_send;
                    vif.adapter_vld_send <= pkt.adapter_vld_send;
                end
                
                vif.trn_msg_send <= pkt.trn_msg_send;
                vif.adapter_msg_send <= pkt.adapter_msg_send;
                vif.ser_rdy <= pkt.ser_rdy;
            end
        endtask
    endclass

    class link_controller_rx_driver;
        virtual Link_controller_if vif;

        function new(virtual Link_controller_if vif);
            this.vif = vif;
        endfunction

        task run();
            rx_transaction pkt;
            forever begin
                @(negedge vif.clk);
                pkt = new();
                assert(pkt.randomize());

                vif.des_data_rcvd = pkt.des_data_rcvd;
                vif.des_vld_rcvd = pkt.des_vld_rcvd;
            end
        endtask
    endclass

    // =================================================================
    // Monitor
    // =================================================================

    class link_controller_monitor;
        virtual Link_controller_if vif;

        mailbox #(tx_transaction) tx_in_mbx;
        mailbox #(tx_monitor_pkt) tx_out_mbx;

        mailbox #(rx_transaction) rx_in_mbx;
        mailbox #(rx_monitor_pkt) rx_out_mbx;

        function new(virtual Link_controller_if vif);
            this.vif = vif;
            this.tx_in_mbx = new();
            this.tx_out_mbx = new();
            this.rx_in_mbx = new();
            this.rx_out_mbx = new();
        endfunction

        task run();
            tx_transaction tx_in;
            tx_monitor_pkt tx_out;
            rx_transaction rx_in;
            rx_monitor_pkt rx_out;

            forever begin
                @(posedge vif.clk);

                // Sample TX Side Inputs
                if (vif.trn_vld_send || vif.adapter_vld_send || vif.ser_rdy || vif.start_pat_req || vif.send_4_iter) begin
                    tx_in = new();
                    tx_in.trn_msg_send = vif.trn_msg_send;
                    tx_in.trn_vld_send = vif.trn_vld_send;
                    tx_in.adapter_msg_send = vif.adapter_msg_send;
                    tx_in.adapter_vld_send = vif.adapter_vld_send;
                    tx_in.ser_rdy = vif.ser_rdy;
                    tx_in.pattern_mode = vif.pattern_mode;
                    tx_in.start_pat_req = vif.start_pat_req;
                    tx_in.send_4_iter = vif.send_4_iter;
                    tx_in.mapper_rdy = vif.mapper_rdy;
                    tx_in_mbx.put(tx_in);
                end

                // Sample TX Side Outputs
                if (vif.ser_vld_send && vif.ser_rdy) begin
                    tx_out = new();
                    tx_out.ser_data_send = vif.ser_data_send;
                    tx_out.ser_vld_send = vif.ser_vld_send;
                    tx_out_mbx.put(tx_out);
                end

                // Sample RX Side Inputs
                if (vif.des_vld_rcvd) begin
                    rx_in = new();
                    rx_in.des_data_rcvd = vif.des_data_rcvd;
                    rx_in.des_vld_rcvd = vif.des_vld_rcvd;
                    rx_in.pattern_mode = vif.pattern_mode;
                    rx_in_mbx.put(rx_in);
                end

                // Sample RX Side Outputs
                if (vif.adapter_vld_rcvd || vif.trn_vld_rcvd || vif.det_pat_rcvd) begin
                    rx_out = new();
                    rx_out.adapter_msg_rcvd = vif.adapter_msg_rcvd;
                    rx_out.adapter_vld_rcvd = vif.adapter_vld_rcvd;
                    rx_out.trn_msg_rcvd = vif.trn_msg_rcvd;
                    rx_out.trn_vld_rcvd = vif.trn_vld_rcvd;
                    rx_out.det_pat_rcvd = vif.det_pat_rcvd;
                    rx_out_mbx.put(rx_out);
                end
            end
        endtask
    endclass

    // =================================================================
    // Scoreboard
    // =================================================================

    class link_controller_scoreboard;
        link_controller_monitor mon;

        mailbox #(tx_monitor_pkt) expected_tx_mbx;
        mailbox #(rx_monitor_pkt) expected_rx_mbx;

        int tx_pass, tx_fail;
        int rx_pass, rx_fail;

        function new(link_controller_monitor mon);
            this.mon = mon;
            this.expected_tx_mbx = new();
            this.expected_rx_mbx = new();
        endfunction

        task run();
            fork
                predict_tx();
                predict_rx();
                check_tx();
                check_rx();
            join_none
        endtask

        function bit is_128bit_opcode(sb_opcode_e opcode);
            case (opcode)
                SB_32_MEM_WRITE, SB_32_DMS_REG_WRITE, SB_32_CFG_WRITE,
                SB_64_MEM_WRITE, SB_64_DMS_REG_WRITE, SB_64_CFG_WRITE,
                SB_COMPLETION_WITH_32_DATA, SB_COMPLETION_WITH_64_DATA,
                SB_MSG_WITH_64_DATA, SB_MNGT_PORT_MSG_WITH_DATA: return 1;
                default: return 0;
            endcase
        endfunction

        task predict_tx();
            tx_transaction pkt;
            tx_monitor_pkt exp;
            sb_packet_t winner;
            forever begin
                mon.tx_in_mbx.get(pkt);
                
                if (pkt.pattern_mode) begin
					// Predictor aligns with RTL behavior: start_pat_req packet is preempted by send_4_iter, so only the 4 iterations transmit.
                    if (pkt.send_4_iter) begin
                         for (int i=0; i<4; i++) begin
                             exp = new();
                             exp.ser_data_send = 64'h5555_5555_5555_5555;
                             exp.ser_vld_send = 1;
                             expected_tx_mbx.put(exp);
                         end
                    end

                end else begin
                    if ((pkt.trn_vld_send || pkt.adapter_vld_send) && pkt.mapper_rdy) begin
                        winner = pkt.trn_vld_send ? pkt.trn_msg_send : pkt.adapter_msg_send;
                        
                        // Cycle 1: LSB (Header)
                        exp = new();
                        exp.ser_data_send = winner.header;
                        exp.ser_vld_send = 1;
                        expected_tx_mbx.put(exp);
                        
                        // Cycle 2: MSB (Payload) if 128-bit
                        if (is_128bit_opcode(winner.header.msg.opcode)) begin
                            exp = new();
                            exp.ser_data_send = winner.payload;
                            exp.ser_vld_send = 1;
                            expected_tx_mbx.put(exp);
                        end
                    end
                end
            end
        endtask

        task predict_rx();
            rx_transaction pkt;
            rx_monitor_pkt exp;
            sb_packet_t rcvd_pkt;
            int pattern_match_cnt = 0;
            forever begin
                mon.rx_in_mbx.get(pkt);
                
                if (pkt.pattern_mode) begin
                    if (pkt.des_vld_rcvd) begin
                        if (pkt.des_data_rcvd == 64'h5555_5555_5555_5555) begin
                            pattern_match_cnt++;
                            if (pattern_match_cnt >= 2) begin
                                exp = new();
                                exp.adapter_vld_rcvd = 0;
                                exp.trn_vld_rcvd = 0;
                                exp.det_pat_rcvd = 1;
                                expected_rx_mbx.put(exp);
                            end
                        end else begin
                            pattern_match_cnt = 0;
                        end
                    end
                end else begin
                    pattern_match_cnt = 0;
                    if (is_128bit_opcode(sb_opcode_e'(pkt.des_data_rcvd[4:0]))) begin
                        rcvd_pkt.header = pkt.des_data_rcvd;
                        // Wait for second half
                        do begin
                            mon.rx_in_mbx.get(pkt);
                        end while (!pkt.des_vld_rcvd);
                        rcvd_pkt.payload = pkt.des_data_rcvd;
                    end else begin
                        rcvd_pkt.header = pkt.des_data_rcvd;
                        rcvd_pkt.payload = '0;
                    end
                    
                    exp = new();
                    exp.adapter_vld_rcvd = 0;
                    exp.trn_vld_rcvd = 0;
                    exp.det_pat_rcvd = 0;
                    // Demux logic based on dstid
                    if (rcvd_pkt.header.msg.dstid == REMOTE_PHY) begin
                        exp.trn_msg_rcvd = rcvd_pkt;
                        exp.trn_vld_rcvd = 1;
                    end else begin
                        exp.adapter_msg_rcvd = rcvd_pkt;
                        exp.adapter_vld_rcvd = 1;
                    end
                    expected_rx_mbx.put(exp);
                end
            end
        endtask


        task check_tx();
            tx_monitor_pkt wd;
            tx_monitor_pkt exp;
            forever begin
                expected_tx_mbx.get(exp);
                mon.tx_out_mbx.get(wd);

                if (wd.ser_data_send !== exp.ser_data_send) begin
                    $display("[%0t] Link_Controller TX mismatch exp=%h got=%h", $time, exp.ser_data_send, wd.ser_data_send);
                    tx_fail++;
                end else begin
                    tx_pass++;
                end
            end
        endtask

        task check_rx();
            rx_monitor_pkt wd;
            rx_monitor_pkt exp;
            forever begin
                expected_rx_mbx.get(exp);
                mon.rx_out_mbx.get(wd);

                if (wd.adapter_vld_rcvd !== exp.adapter_vld_rcvd || 
                    wd.trn_vld_rcvd !== exp.trn_vld_rcvd ||
                    wd.det_pat_rcvd !== exp.det_pat_rcvd) begin
                    $display("[%0t] Link_Controller RX mismatch exp_vld={A:%0d, L:%0d, P:%0d} got_vld={A:%0d, L:%0d, P:%0d}", 
                             $time, exp.adapter_vld_rcvd, exp.trn_vld_rcvd, exp.det_pat_rcvd,
                             wd.adapter_vld_rcvd, wd.trn_vld_rcvd, wd.det_pat_rcvd);
                    rx_fail++;
                end else begin
                    rx_pass++;
                end
            end
        endtask
        
    endclass

endpackage