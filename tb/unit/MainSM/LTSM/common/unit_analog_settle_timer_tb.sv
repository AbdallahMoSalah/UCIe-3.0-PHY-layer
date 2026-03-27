`timescale 1ns/1ps

module unit_analog_settle_timer_tb;
    logic lclk;
    logic rst_n;
    logic timer_en;
    logic timer_done;

    localparam SETTLE_DELAY = 16;
    localparam CLK_PERIOD = 10;

    internal_ltsm_if itf(lclk, rst_n);

    assign itf.analog_settle_timer_en = timer_en;
    assign timer_done = itf.analog_settle_time_done;

    analog_settle_timer #(
        .SETTLE_DELAY(SETTLE_DELAY)
    ) dut (
        .itf(itf.timer_analog_settle2state_mp)
    );

    // Clock generation
    initial forever #(CLK_PERIOD/2) lclk = ~lclk;

    int error_count = 0;

    task check_errors;
        if (error_count > 0) begin
            $display("FAILED: %0d errors found in unit_analog_settle_timer_tb", error_count);
            $stop;
        end else begin
            $display("PASSED: unit_analog_settle_timer_tb completed successfully.");
        end
    endtask

    task wait_and_check_done(input string test_name);
        for (int i = 0; i < SETTLE_DELAY; i++) begin
            @(posedge lclk);
            #1; // Sample after posedge
            if (timer_done !== 1'b0) begin
                $display("ERROR @%0t: timer_done asserted too early at cycle %0d in %s", $time, i, test_name);
                error_count++;
            end
        end
        @(posedge lclk);
        #1;
        if (timer_done !== 1'b1) begin
            $display("ERROR @%0t: timer_done NOT asserted at cycle %0d in %s", $time, SETTLE_DELAY, test_name);
            error_count++;
        end
    endtask

    initial begin
        lclk = 0;
        rst_n = 0;
        timer_en = 0;

        #25; // 2.5 cycles of reset
        rst_n = 1;
        @(posedge lclk);

        $display("---------------------------------------------------------");
        $display("Test 1: Full delay exactly %0d cycles", SETTLE_DELAY);
        timer_en = 1;
        wait_and_check_done("Test 1");

        // Ensure it stays 1 as long as timer_en is 1
        @(posedge lclk);
        #1;
        if (timer_done !== 1'b1) begin
            $display("ERROR @%0t: timer_done dropped while timer_en is high", $time);
            error_count++;
        end

        // Drop timer_en
        @(posedge lclk);
        timer_en = 0;
        @(posedge lclk); // Wait for clock edge to propagate
        #1;
        if (timer_done !== 1'b0) begin
            $display("ERROR @%0t: timer_done did not drop after timer_en went low", $time);
            error_count++;
        end

        $display("---------------------------------------------------------");
        $display("Test 2: Early termination (interrupt before delay)");
        @(posedge lclk);
        timer_en = 1;
        for (int i = 0; i < SETTLE_DELAY/2; i++) begin
            @(posedge lclk);
            #1;
            if (timer_done !== 1'b0) begin
                $display("ERROR @%0t: timer_done asserted early in Test 2", $time);
                error_count++;
            end
        end
        // Terminate early
        timer_en = 0;
        @(posedge lclk);
        #1;
        if (timer_done !== 1'b0) begin
            $display("ERROR @%0t: timer_done asserted despite early termination", $time);
            error_count++;
        end

        // Re-enable immediately to ensure counter was reset
        timer_en = 1;
        wait_and_check_done("Test 2");

        timer_en = 0;
        @(posedge lclk);

        $display("---------------------------------------------------------");
        $display("Test 3: Reset assertion during active timer");
        timer_en = 1;
        repeat(5) @(posedge lclk);
        @(negedge lclk);
        rst_n = 0; // async reset
        #1;
        if (timer_done !== 1'b0) begin
            $display("ERROR @%0t: timer_done did not drop asynchronously with rst_n", $time);
            error_count++;
        end
        repeat(3) @(negedge lclk);
        rst_n = 1;
        // The NEXT posedge is cycle 0!
        // timer_en is still 1, it should count again from 0
        wait_and_check_done("Test 3");
        timer_en = 0;

        repeat(5) @(posedge lclk);

        check_errors();
        // $finish;
        $stop;
    end
endmodule

