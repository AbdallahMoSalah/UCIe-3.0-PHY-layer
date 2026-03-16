module sb_demapper_tb;

    import sb_demapper_tb_pkg::*;

    bit clk;
    sb_demapper_if sb_demapperif(clk);

    DEMAPPER dut(
        .clk(sb_demapperif.clk),
        .rst_n(sb_demapperif.rst_n),
        .msg_word_rcvd(sb_demapperif.msg_word_rcvd),
        .word_vld_rcvd(sb_demapperif.word_vld_rcvd),
        .msg_rcvd(sb_demapperif.msg_rcvd),
        .msg_vld_rcvd(sb_demapperif.msg_vld_rcvd)
    );


    sb_demapper_driver     drv;
    sb_demapper_monitor    mon;
    sb_demapper_scoreboard scb;


    // clock
    always #5 clk = ~clk;


    initial begin

        drv = new(sb_demapperif);
        mon = new(sb_demapperif);
        scb = new(mon);
        

        begin
            // 2. Reset Sequence
            sb_demapperif.msg_rcvd = 64'b0;
            sb_demapperif.msg_vld_rcvd  = 1'b0;
            sb_demapperif.rst_n         = 1'b0;

            // Wait for 2 negative edges, then release reset
            repeat(2) @(posedge clk);
            sb_demapperif.rst_n = 1'b1;
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