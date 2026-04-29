module rdi_aggregator_tb;

    import rdi_aggregator_tb_pkg::*;

    bit clk;
    rdi_aggregator_if rdi_aggregatorif(clk);

    rdi_aggregator dut(
        .clk(rdi_aggregatorif.clk),
        .rst_n(rdi_aggregatorif.rst_n),
        .lp_cfg(rdi_aggregatorif.lp_cfg),
        .lp_cfg_vld(rdi_aggregatorif.lp_cfg_vld),
        .lp_msg(rdi_aggregatorif.lp_msg),
        .lp_msg_vld(rdi_aggregatorif.lp_msg_vld)
    );


    rdi_aggregator_driver     drv;
    rdi_aggregator_monitor    mon;
    rdi_aggregator_scoreboard scb;


    // clock
    always #5 clk = ~clk;


    initial begin

        drv = new(rdi_aggregatorif);
        mon = new(rdi_aggregatorif);
        scb = new(mon);
        

        begin
            // 2. Reset Sequence
            rdi_aggregatorif.lp_cfg = 64'b0;
            rdi_aggregatorif.lp_cfg_vld  = 1'b0;
            rdi_aggregatorif.rst_n         = 1'b0;

            // Wait for 2 negative edges, then release reset
            repeat(2) @(posedge clk);
            rdi_aggregatorif.rst_n = 1'b1;
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