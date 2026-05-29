package Mapper_tb_pkg;

    // Transaction classes
    class mapper_in_trans;
        rand bit [511:0] data;
        rand bit in_valid;
        rand bit in_irdy;
        rand bit [2:0] width_deg_map;
        logic mapper_ready;

        bit Prev_in_valid = 0;
        bit Prev_in_irdy = 0;

        constraint deg_map_c {
            width_deg_map inside {3'b011, 3'b001, 3'b010, 3'b100, 3'b101};
        }

        // Handshake stability constraint:
        // Valid & irdy once asserted cannot drop until mapper_ready goes high
        constraint valid_irdy_stability_c {
            if (Prev_in_valid && !mapper_ready) {
                in_valid == 1;
            } else {
                in_valid dist {1 := 30, 0 := 70};
            }

            if (Prev_in_irdy && !mapper_ready) {
                in_irdy == 1;
            } else {
                in_irdy dist {1 := 30, 0 := 70};
            }
        }

        // lp_irdy and lp_valid are normally identical but can sometimes be tested separately
        constraint irdy_valid_c {
            soft in_irdy == in_valid;
        }

        function void post_randomize();
            Prev_in_valid = in_valid;
            Prev_in_irdy = in_irdy;
        endfunction
    endclass

    class mapper_out_chunk;
        bit [31:0] lanes[16];
        bit scramble_en;
    endclass

    // Driver class
    class mapper_driver;
        virtual mapper_if vif;

        function new(virtual mapper_if vif);
            this.vif = vif;
        endfunction

        task run(int num_packets, logic [2:0] mode);
            mapper_in_trans pkt;
            pkt = new();
            vif.mapper_en <= 1'b1; // Keep enable asserted as control signal
            vif.i_width_deg_map <= mode;

            repeat (num_packets) begin
                @(posedge vif.clk);
                
                // Wait while there is an active unacknowledged handshake request.
                // If lp_valid or lp_irdy was 1 but ready was 0, we must hold all signals constant.
                while (vif.rst_n && vif.mapper_en && ((vif.lp_valid && !vif.mapper_ready) || (vif.lp_irdy && !vif.mapper_ready))) begin
                    @(posedge vif.clk);
                end

                if (!vif.rst_n) break;

                // We are ready for a new transaction, randomize it.
                pkt.mapper_ready = vif.mapper_ready;
                assert(pkt.randomize() with { width_deg_map == mode; });

                vif.lp_valid        <= pkt.in_valid;
                vif.lp_irdy         <= pkt.in_irdy;
                vif.i_in_data       <= pkt.data;
                vif.i_width_deg_map <= mode;
            end

            // After pushing the num_packets, wait for the last one to be acknowledged
            @(posedge vif.clk);
            while (vif.lp_valid || vif.lp_irdy) begin
                if (vif.mapper_ready) begin
                    vif.lp_valid <= 1'b0;
                    vif.lp_irdy  <= 1'b0;
                end
                @(posedge vif.clk);
            end
        endtask
    endclass

    // Monitor class
    class mapper_monitor;
        virtual mapper_if vif;
        mailbox #(mapper_in_trans) in_mbx;
        mailbox #(mapper_out_chunk) out_mbx;
        bit enable_check = 1; // Used to isolate manual directed testing

        function new(virtual mapper_if vif);
            this.vif = vif;
            this.in_mbx = new();
            this.out_mbx = new();
        endfunction

        task run();
            mapper_in_trans in_pkt;
            mapper_out_chunk out_pkt;

            forever begin
                @(posedge vif.clk);

                if (enable_check) begin
                    // Sample input handshakes and capture transaction
                    if (vif.lp_valid && vif.lp_irdy && vif.mapper_ready) begin
                        in_pkt = new();
                        in_pkt.data = vif.i_in_data;
                        in_pkt.width_deg_map = vif.i_width_deg_map;
                        in_mbx.put(in_pkt);
                    end

                    // Sample output chunk when active (sampled aligned to clock edge)
                    if (vif.out_scramble_en) begin
                        out_pkt = new();
                        out_pkt.scramble_en = vif.out_scramble_en;
                        out_pkt.lanes[0]  = vif.o_lane_0;
                        out_pkt.lanes[1]  = vif.o_lane_1;
                        out_pkt.lanes[2]  = vif.o_lane_2;
                        out_pkt.lanes[3]  = vif.o_lane_3;
                        out_pkt.lanes[4]  = vif.o_lane_4;
                        out_pkt.lanes[5]  = vif.o_lane_5;
                        out_pkt.lanes[6]  = vif.o_lane_6;
                        out_pkt.lanes[7]  = vif.o_lane_7;
                        out_pkt.lanes[8]  = vif.o_lane_8;
                        out_pkt.lanes[9]  = vif.o_lane_9;
                        out_pkt.lanes[10] = vif.o_lane_10;
                        out_pkt.lanes[11] = vif.o_lane_11;
                        out_pkt.lanes[12] = vif.o_lane_12;
                        out_pkt.lanes[13] = vif.o_lane_13;
                        out_pkt.lanes[14] = vif.o_lane_14;
                        out_pkt.lanes[15] = vif.o_lane_15;
                        out_mbx.put(out_pkt);
                    end
                end
            end
        endtask
    endclass

    // Scoreboard class
    class mapper_scoreboard;
        mapper_monitor mon;
        mailbox #(mapper_out_chunk) expected_mbx;
        int pass, fail;

        function new(mapper_monitor mon);
            this.mon = mon;
            this.expected_mbx = new();
            this.pass = 0;
            this.fail = 0;
        endfunction

        task run();
            mapper_in_trans pkt;
            mapper_out_chunk exp;
            int num_cycles;

            forever begin
                mon.in_mbx.get(pkt);

                case (pkt.width_deg_map)
                    3'b011:  num_cycles = 1;
                    3'b001,
                    3'b010:  num_cycles = 2;
                    3'b100,
                    3'b101:  num_cycles = 4;
                    default: num_cycles = 1;
                endcase

                for (int c = 0; c < num_cycles; c++) begin
                    exp = new();
                    exp.scramble_en = 1'b1;
                    
                    for (int i = 0; i < 16; i++) exp.lanes[i] = 32'd0;

                    case (pkt.width_deg_map)
                        3'b011: begin // x16 lanes 0-15 — 1 cycle
                            exp.lanes[0]  = {pkt.data[391:384], pkt.data[263:256], pkt.data[135:128], pkt.data[  7:  0]};
                            exp.lanes[1]  = {pkt.data[399:392], pkt.data[271:264], pkt.data[143:136], pkt.data[ 15:  8]};
                            exp.lanes[2]  = {pkt.data[407:400], pkt.data[279:272], pkt.data[151:144], pkt.data[ 23: 16]};
                            exp.lanes[3]  = {pkt.data[415:408], pkt.data[287:280], pkt.data[159:152], pkt.data[ 31: 24]};
                            exp.lanes[4]  = {pkt.data[423:416], pkt.data[295:288], pkt.data[167:160], pkt.data[ 39: 32]};
                            exp.lanes[5]  = {pkt.data[431:424], pkt.data[303:296], pkt.data[175:168], pkt.data[ 47: 40]};
                            exp.lanes[6]  = {pkt.data[439:432], pkt.data[311:304], pkt.data[183:176], pkt.data[ 55: 48]};
                            exp.lanes[7]  = {pkt.data[447:440], pkt.data[319:312], pkt.data[191:184], pkt.data[ 63: 56]};
                            exp.lanes[8]  = {pkt.data[455:448], pkt.data[327:320], pkt.data[199:192], pkt.data[ 71: 64]};
                            exp.lanes[9]  = {pkt.data[463:456], pkt.data[335:328], pkt.data[207:200], pkt.data[ 79: 72]};
                            exp.lanes[10] = {pkt.data[471:464], pkt.data[343:336], pkt.data[215:208], pkt.data[ 87: 80]};
                            exp.lanes[11] = {pkt.data[479:472], pkt.data[351:344], pkt.data[223:216], pkt.data[ 95: 88]};
                            exp.lanes[12] = {pkt.data[487:480], pkt.data[359:352], pkt.data[231:224], pkt.data[103: 96]};
                            exp.lanes[13] = {pkt.data[495:488], pkt.data[367:360], pkt.data[239:232], pkt.data[111:104]};
                            exp.lanes[14] = {pkt.data[503:496], pkt.data[375:368], pkt.data[247:240], pkt.data[119:112]};
                            exp.lanes[15] = {pkt.data[511:504], pkt.data[383:376], pkt.data[255:248], pkt.data[127:120]};
                        end

                        3'b001: begin // x8 lanes 0-7 — 2 cycles
                            if (c == 0) begin
                                exp.lanes[0] = {pkt.data[199:192], pkt.data[135:128], pkt.data[ 71: 64], pkt.data[  7:  0]};
                                exp.lanes[1] = {pkt.data[207:200], pkt.data[143:136], pkt.data[ 79: 72], pkt.data[ 15:  8]};
                                exp.lanes[2] = {pkt.data[215:208], pkt.data[151:144], pkt.data[ 87: 80], pkt.data[ 23: 16]};
                                exp.lanes[3] = {pkt.data[223:216], pkt.data[159:152], pkt.data[ 95: 88], pkt.data[ 31: 24]};
                                exp.lanes[4] = {pkt.data[231:224], pkt.data[167:160], pkt.data[103: 96], pkt.data[ 39: 32]};
                                exp.lanes[5] = {pkt.data[239:232], pkt.data[175:168], pkt.data[111:104], pkt.data[ 47: 40]};
                                exp.lanes[6] = {pkt.data[247:240], pkt.data[183:176], pkt.data[119:112], pkt.data[ 55: 48]};
                                exp.lanes[7] = {pkt.data[255:248], pkt.data[191:184], pkt.data[127:120], pkt.data[ 63: 56]};
                            end else begin
                                exp.lanes[0] = {pkt.data[455:448], pkt.data[391:384], pkt.data[327:320], pkt.data[263:256]};
                                exp.lanes[1] = {pkt.data[463:456], pkt.data[399:392], pkt.data[335:328], pkt.data[271:264]};
                                exp.lanes[2] = {pkt.data[471:464], pkt.data[407:400], pkt.data[343:336], pkt.data[279:272]};
                                exp.lanes[3] = {pkt.data[479:472], pkt.data[415:408], pkt.data[351:344], pkt.data[287:280]};
                                exp.lanes[4] = {pkt.data[487:480], pkt.data[423:416], pkt.data[359:352], pkt.data[295:288]};
                                exp.lanes[5] = {pkt.data[495:488], pkt.data[431:424], pkt.data[367:360], pkt.data[303:296]};
                                exp.lanes[6] = {pkt.data[503:496], pkt.data[439:432], pkt.data[375:368], pkt.data[311:304]};
                                exp.lanes[7] = {pkt.data[511:504], pkt.data[447:440], pkt.data[383:376], pkt.data[319:312]};
                            end
                        end

                        3'b010: begin // x8 lanes 8-15 — 2 cycles
                            if (c == 0) begin
                                exp.lanes[8]  = {pkt.data[199:192], pkt.data[135:128], pkt.data[ 71: 64], pkt.data[  7:  0]};
                                exp.lanes[9]  = {pkt.data[207:200], pkt.data[143:136], pkt.data[ 79: 72], pkt.data[ 15:  8]};
                                exp.lanes[10] = {pkt.data[215:208], pkt.data[151:144], pkt.data[ 87: 80], pkt.data[ 23: 16]};
                                exp.lanes[11] = {pkt.data[223:216], pkt.data[159:152], pkt.data[ 95: 88], pkt.data[ 31: 24]};
                                exp.lanes[12] = {pkt.data[231:224], pkt.data[167:160], pkt.data[103: 96], pkt.data[ 39: 32]};
                                exp.lanes[13] = {pkt.data[239:232], pkt.data[175:168], pkt.data[111:104], pkt.data[ 47: 40]};
                                exp.lanes[14] = {pkt.data[247:240], pkt.data[183:176], pkt.data[119:112], pkt.data[ 55: 48]};
                                exp.lanes[15] = {pkt.data[255:248], pkt.data[191:184], pkt.data[127:120], pkt.data[ 63: 56]};
                            end else begin
                                exp.lanes[8]  = {pkt.data[455:448], pkt.data[391:384], pkt.data[327:320], pkt.data[263:256]};
                                exp.lanes[9]  = {pkt.data[463:456], pkt.data[399:392], pkt.data[335:328], pkt.data[271:264]};
                                exp.lanes[10] = {pkt.data[471:464], pkt.data[407:400], pkt.data[343:336], pkt.data[279:272]};
                                exp.lanes[11] = {pkt.data[479:472], pkt.data[415:408], pkt.data[351:344], pkt.data[287:280]};
                                exp.lanes[12] = {pkt.data[487:480], pkt.data[423:416], pkt.data[359:352], pkt.data[295:288]};
                                exp.lanes[13] = {pkt.data[495:488], pkt.data[431:424], pkt.data[367:360], pkt.data[303:296]};
                                exp.lanes[14] = {pkt.data[503:496], pkt.data[439:432], pkt.data[375:368], pkt.data[311:304]};
                                exp.lanes[15] = {pkt.data[511:504], pkt.data[447:440], pkt.data[383:376], pkt.data[319:312]};
                            end
                        end

                        3'b100: begin // x4 lanes 0-3 — 4 cycles
                            if (c == 0) begin
                                exp.lanes[0] = {pkt.data[103: 96], pkt.data[ 71: 64], pkt.data[ 39: 32], pkt.data[  7:  0]};
                                exp.lanes[1] = {pkt.data[111:104], pkt.data[ 79: 72], pkt.data[ 47: 40], pkt.data[ 15:  8]};
                                exp.lanes[2] = {pkt.data[119:112], pkt.data[ 87: 80], pkt.data[ 55: 48], pkt.data[ 23: 16]};
                                exp.lanes[3] = {pkt.data[127:120], pkt.data[ 95: 88], pkt.data[ 63: 56], pkt.data[ 31: 24]};
                            end else if (c == 1) begin
                                exp.lanes[0] = {pkt.data[231:224], pkt.data[199:192], pkt.data[167:160], pkt.data[135:128]};
                                exp.lanes[1] = {pkt.data[239:232], pkt.data[207:200], pkt.data[175:168], pkt.data[143:136]};
                                exp.lanes[2] = {pkt.data[247:240], pkt.data[215:208], pkt.data[183:176], pkt.data[151:144]};
                                exp.lanes[3] = {pkt.data[255:248], pkt.data[223:216], pkt.data[191:184], pkt.data[159:152]};
                            end else if (c == 2) begin
                                exp.lanes[0] = {pkt.data[359:352], pkt.data[327:320], pkt.data[295:288], pkt.data[263:256]};
                                exp.lanes[1] = {pkt.data[367:360], pkt.data[335:328], pkt.data[303:296], pkt.data[271:264]};
                                exp.lanes[2] = {pkt.data[375:368], pkt.data[343:336], pkt.data[311:304], pkt.data[279:272]};
                                exp.lanes[3] = {pkt.data[383:376], pkt.data[351:344], pkt.data[319:312], pkt.data[287:280]};
                            end else begin
                                exp.lanes[0] = {pkt.data[487:480], pkt.data[455:448], pkt.data[423:416], pkt.data[391:384]};
                                exp.lanes[1] = {pkt.data[495:488], pkt.data[463:456], pkt.data[431:424], pkt.data[399:392]};
                                exp.lanes[2] = {pkt.data[503:496], pkt.data[471:464], pkt.data[439:432], pkt.data[407:400]};
                                exp.lanes[3] = {pkt.data[511:504], pkt.data[479:472], pkt.data[447:440], pkt.data[415:408]};
                            end
                        end

                        3'b101: begin // x4 lanes 4-7 — 4 cycles
                            if (c == 0) begin
                                exp.lanes[4] = {pkt.data[103: 96], pkt.data[ 71: 64], pkt.data[ 39: 32], pkt.data[  7:  0]};
                                exp.lanes[5] = {pkt.data[111:104], pkt.data[ 79: 72], pkt.data[ 47: 40], pkt.data[ 15:  8]};
                                exp.lanes[6] = {pkt.data[119:112], pkt.data[ 87: 80], pkt.data[ 55: 48], pkt.data[ 23: 16]};
                                exp.lanes[7] = {pkt.data[127:120], pkt.data[ 95: 88], pkt.data[ 63: 56], pkt.data[ 31: 24]};
                            end else if (c == 1) begin
                                exp.lanes[4] = {pkt.data[231:224], pkt.data[199:192], pkt.data[167:160], pkt.data[135:128]};
                                exp.lanes[5] = {pkt.data[239:232], pkt.data[207:200], pkt.data[175:168], pkt.data[143:136]};
                                exp.lanes[6] = {pkt.data[247:240], pkt.data[215:208], pkt.data[183:176], pkt.data[151:144]};
                                exp.lanes[7] = {pkt.data[255:248], pkt.data[223:216], pkt.data[191:184], pkt.data[159:152]};
                            end else if (c == 2) begin
                                exp.lanes[4] = {pkt.data[359:352], pkt.data[327:320], pkt.data[295:288], pkt.data[263:256]};
                                exp.lanes[5] = {pkt.data[367:360], pkt.data[335:328], pkt.data[303:296], pkt.data[271:264]};
                                exp.lanes[6] = {pkt.data[375:368], pkt.data[343:336], pkt.data[311:304], pkt.data[279:272]};
                                exp.lanes[7] = {pkt.data[383:376], pkt.data[351:344], pkt.data[319:312], pkt.data[287:280]};
                            end else begin
                                exp.lanes[4] = {pkt.data[487:480], pkt.data[455:448], pkt.data[423:416], pkt.data[391:384]};
                                exp.lanes[5] = {pkt.data[495:488], pkt.data[463:456], pkt.data[431:424], pkt.data[399:392]};
                                exp.lanes[6] = {pkt.data[503:496], pkt.data[471:464], pkt.data[439:432], pkt.data[407:400]};
                                exp.lanes[7] = {pkt.data[511:504], pkt.data[479:472], pkt.data[447:440], pkt.data[415:408]};
                            end
                        end
                    endcase

                    expected_mbx.put(exp);
                end
            end
        endtask

        task check();
            mapper_out_chunk actual;
            mapper_out_chunk expected;
            bit error_found;

            forever begin
                expected_mbx.get(expected);
                mon.out_mbx.get(actual);

                error_found = 0;
                for (int i = 0; i < 16; i++) begin
                    if (actual.lanes[i] !== expected.lanes[i]) begin
                        $display("[ERR Scoreboard] Lane %0d mismatch: expected=%h actual=%h", i, expected.lanes[i], actual.lanes[i]);
                        error_found = 1;
                    end
                end

                if (actual.scramble_en !== expected.scramble_en) begin
                    $display("[ERR Scoreboard] scramble_en mismatch: expected=%b actual=%b", expected.scramble_en, actual.scramble_en);
                    error_found = 1;
                end

                if (error_found) begin
                    fail++;
                end else begin
                    pass++;
                end
            end
        endtask
    endclass

endpackage
