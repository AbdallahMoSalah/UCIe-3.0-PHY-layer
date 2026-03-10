module sb_mapper_tb;

    import sb_mapper_tb_pkg::*;

    bit clk;
    sb_mapper_if sb_mapperif(clk);

    sb_mapper dut(
        .clk(sb_mapperif.clk),
        .rst_n(sb_mapperif.rst_n),
        .Msg_word_send(sb_mapperif.Msg_word_send),
        .word_valid_s(sb_mapperif.word_valid_s),
        .ser_ready(sb_mapperif.ser_ready),
        .mapper_ready(sb_mapperif.mapper_ready),
        .msg_send(sb_mapperif.msg_send),
        .msg_vld_s(sb_mapperif.msg_vld_s)
    );


    sb_mapper_driver     drv;
    sb_mapper_monitor    mon;
    sb_mapper_scoreboard scb;


    // clock
    always #5 clk = ~clk;


    initial begin

        drv = new(sb_mapperif);
        mon = new(sb_mapperif);
        scb = new(mon);
        

        begin
            // 2. Reset Sequence
            sb_mapperif.Msg_word_send = 128'b0;
            sb_mapperif.word_valid_s  = 1'b0;
            sb_mapperif.rst_n         = 1'b0;

            // Wait for 2 negative edges, then release reset
            repeat(2) @(posedge clk);
            sb_mapperif.rst_n = 1'b1;
            $display("\nSystem Reset De-asserted. Starting Test...\n");

        end
        fork
            drv.run();
            mon.run();
            scb.run();
            scb.check();
         
        join_none
        repeat(10000)begin
            @(posedge clk);
        end

        // 4. Final Summary Report (???? ????? ?????? ????????)
        $display("\n==================================================");
        $display("            VERIFICATION SUMMARY REPORT             ");
        $display("==================================================");
        $display(" Total Packets Injected : %0d", (scb.pass + scb.fail));
        $display(" Packets Passed         : %0d", scb.pass);
        $display(" Packets Failed         : %0d", scb.fail);
        $display("==================================================\n");

        $stop;
    end

endmodule