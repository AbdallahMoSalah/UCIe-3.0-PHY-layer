package sb_mapper_tb_pkg;

    import sb_pkg::*;

    class sb_mapper_in_trans;

        rand bit [127:0] data;
        rand bit in_valid;
        rand bit in_ready;
        

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


        constraint ready_dist {
            in_ready dist {0 := 60, 1 := 40};
        }


    endclass

    class sb_mapper_chunk;

        bit [63:0] data;

    endclass
    class sb_mapper_driver;

        virtual sb_mapper_if vif;

        function new(virtual sb_mapper_if vif);
            this.vif = vif;
        endfunction


        task run();

            sb_mapper_in_trans pkt;

            forever begin

                @(negedge vif.clk);

                pkt = new();
                assert(pkt.randomize());

                // random valid & ready
                vif.word_valid_s = pkt.in_valid;
                vif.ser_ready = pkt.in_ready;

                if(pkt.in_valid && vif.mapper_ready) begin
                    vif.Msg_word_send = pkt.data;
                end

            end

        endtask

    endclass


    class sb_mapper_monitor;

        virtual sb_mapper_if vif;

        sb_mapper_in_trans in_q[$];
        sb_mapper_chunk  out_q[$];

        function new(virtual sb_mapper_if vif);
            this.vif = vif;
        endfunction


        task run();

            sb_mapper_in_trans pkt;
            sb_mapper_chunk  ch;

            forever begin

                @(posedge vif.clk);

                // input handshake
                if(vif.word_valid_s && vif.mapper_ready) begin

                    pkt = new();
                    pkt.data = vif.Msg_word_send;

                    in_q.push_back(pkt);

                end


                // output handshake
                if(vif.msg_vld_s && vif.ser_ready) begin

                    ch = new();
                    ch.data = vif.msg_send;

                    out_q.push_back(ch);

                end

            end

        endtask

    endclass


    class sb_mapper_scoreboard;

        sb_mapper_monitor mon;

        bit [63:0] expected_q[$];
        int pass,fail;

        function new(sb_mapper_monitor mon);
            this.mon = mon;
        endfunction

        function bit is_128bit(bit [127:0] pkt);

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

            sb_mapper_in_trans pkt;

            forever begin

                wait(mon.in_q.size() > 0);

                pkt = mon.in_q.pop_front();

                // header
                expected_q.push_back(pkt.data[63:0]);

                // payload
                if(is_128bit(pkt.data))
                    expected_q.push_back(pkt.data[127:64]);

            end

        endtask



        task check();

            sb_mapper_chunk ch;
            bit [63:0] exp;

            forever begin

                wait(expected_q.size() > 0);
                wait(mon.out_q.size() > 0);

                ch = mon.out_q.pop_front();

                exp = expected_q.pop_front();

                if(ch.data !== exp) begin
                    $display("sb_mapper mismatch exp=%h got=%h",exp,ch.data);
                    fail++;
                end
                else begin
                    pass++;
                end

            end

        endtask

    endclass 

    
endpackage