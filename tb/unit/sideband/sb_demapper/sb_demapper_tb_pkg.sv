package sb_demapper_tb_pkg;

    import sb_pkg::*;

    class sb_demapper_in_trans;

        rand bit [63:0] data;
        rand bit in_valid;
        

        constraint opcode_c {
            data[4:0] inside {
                // Valid 64-bit opcodes
                5'b00000, 5'b00010, 5'b00100, 5'b01000, 5'b01010, 5'b01100, 5'b10000, 5'b10010, 5'b10111,
                // Valid 128-bit opcodes
                5'b00001, 5'b00011, 5'b00101, 5'b01001, 5'b01011, 5'b01101, 5'b10001, 5'b11001, 5'b11000, 5'b11011
            };
        }


        constraint valid_dist {
            in_valid dist {1 := 60, 0 := 40};
        }



    endclass

    class sb_demapper_word;

        bit [127:0] data;

    endclass
    class sb_demapper_driver;

        virtual sb_demapper_if vif;

        
        function new(virtual sb_demapper_if vif);
            this.vif = vif;
        endfunction


        task run();

            sb_demapper_in_trans pkt;

            forever begin

                @(negedge vif.clk);

                pkt = new();
                assert(pkt.randomize());

                // random valid & ready
                vif.msg_vld_rcvd = pkt.in_valid;
                
                if(pkt.in_valid ) begin
                    vif.msg_rcvd = pkt.data;
                end

            end

        endtask

    endclass


    class sb_demapper_monitor;

        virtual sb_demapper_if vif;

        sb_demapper_in_trans in_q[$];
        sb_demapper_word  out_q[$];

        function new(virtual sb_demapper_if vif);
            this.vif = vif;
        endfunction


        task run();

            sb_demapper_in_trans pkt;
            sb_demapper_word  wd;

            forever begin

                @(posedge vif.clk);

                // input handshake
                if(vif.msg_vld_rcvd ) begin

                    pkt = new();
                    pkt.data = vif.msg_rcvd;

                    in_q.push_back(pkt); // target 

                end


                // output handshake
                if(vif.word_vld_rcvd ) begin

                    wd = new();
                    wd.data = vif.msg_word_rcvd;

                    out_q.push_back(wd); // target 

                end

            end

        endtask

    endclass


    class sb_demapper_scoreboard;

        sb_demapper_monitor mon;

        sb_demapper_word expected_q[$];
        int pass,fail;

        function new(sb_demapper_monitor mon);
            this.mon = mon;
        endfunction

        function bit is_128bit(bit [63:0] pkt);

            bit [4:0] opcode;

            opcode = pkt[4:0];

            case(opcode)
                SB_32_MEM_WRITE,
                SB_32_DMS_REG_WRITE,
                SB_32_CFG_WRITE,
                SB_64_MEM_WRITE,
                SB_64_DMS_REG_WRITE,
                SB_64_CFG_WRITE,
                SB_COMPLETION_WITH_32_DATA,
                SB_COMPLETION_WITH_64_DATA,
                SB_MSG_WITH_64_DATA,
                SB_MNGT_PORT_MSG_WITH_DATA:
                    return 1;

                default:
                    return 0;
            endcase

        endfunction


        task run();

            sb_demapper_in_trans pkt;
            sb_demapper_in_trans pkt1;
            sb_demapper_word inter_pkt;
            forever begin

                wait(mon.in_q.size() > 0);

                pkt = mon.in_q.pop_front();

                // 64 bit header only
                
                if(!is_128bit(pkt.data)) begin
                    inter_pkt = new();
                    inter_pkt.data = {64'b0,pkt.data};
                    expected_q.push_back(inter_pkt);
                end
                // header + payload for 128 bit messages
                else begin                    
                    wait(mon.in_q.size() > 0);

                    pkt1 = mon.in_q.pop_front();
                    inter_pkt = new();
                    inter_pkt.data = {pkt1.data,pkt.data};
                    expected_q.push_back(inter_pkt); // push header with payload
                end
           
            end

        endtask



        task check();

            sb_demapper_word wd;
            sb_demapper_word exp;

            forever begin

                wait(expected_q.size() > 0);
                wait(mon.out_q.size() > 0);

                wd = mon.out_q.pop_front();

                exp = expected_q.pop_front();

                if(wd.data !== exp.data) begin
                    $display("sb_demapper mismatch exp=%h got=%h",exp.data,wd.data);
                    fail++;
                end
                else begin
                    pass++;
                end

            end

        endtask

    endclass 

    
endpackage