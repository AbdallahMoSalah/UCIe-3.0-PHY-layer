module rdi_de_aggregator_tb;

    import rdi_de_aggregator_tb_pkg::*;

    bit clk;
    rdi_de_aggregator_if rdi_de_aggregatorif(clk);

    rdi_de_aggregator dut(
        .clk(rdi_de_aggregatorif.clk),
        .rst_n(rdi_de_aggregatorif.rst_n),
        .pl_msg(rdi_de_aggregatorif.pl_msg),
        .pl_msg_vld(rdi_de_aggregatorif.pl_msg_vld),
        .pl_msg_ready(rdi_de_aggregatorif.pl_msg_ready),
        .traffic_req(rdi_de_aggregatorif.traffic_req),
        .traffic_ready(rdi_de_aggregatorif.traffic_ready),
        .pl_cfg(rdi_de_aggregatorif.pl_cfg),
        .pl_cfg_vld(rdi_de_aggregatorif.pl_cfg_vld)
    );


    rdi_de_aggregator_driver     drv;
    rdi_de_aggregator_monitor    mon;
    rdi_de_aggregator_scoreboard scb;


    // clock
    always #5 clk = ~clk;


    initial begin

        drv = new(rdi_de_aggregatorif);
        mon = new(rdi_de_aggregatorif);
        scb = new(mon);
        

        begin
            // 2. Reset Sequence
            rdi_de_aggregatorif.pl_msg      = 128'b0;
            rdi_de_aggregatorif.pl_msg_vld  = 1'b0;
            rdi_de_aggregatorif.rst_n       = 1'b0;

            // Wait for 2 negative edges, then release reset
            repeat(2) @(posedge clk);
            rdi_de_aggregatorif.rst_n = 1'b1;
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

        // 4. Final Summary Report
        $display("\n==================================================");
        $display("            VERIFICATION SUMMARY REPORT             ");
        $display("==================================================");
        $display(" Total Packets Checked  : %0d", (scb.pass + scb.fail));
        $display(" Packets Passed         : %0d", scb.pass);
        $display(" Packets Failed         : %0d", scb.fail);
        $display("==================================================\n");

        $stop;
    end

endmodule
