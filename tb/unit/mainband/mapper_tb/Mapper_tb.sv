`timescale 1ns/1ps

interface mapper_if(input bit clk);
    logic          rst_n;
    logic          mapper_en;
    logic [2:0]    i_width_deg_map;
    logic [511:0]  i_in_data;
    logic          lp_irdy;
    logic          lp_valid;

    logic [31:0]   o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
    logic [31:0]   o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
    logic [31:0]   o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
    logic [31:0]   o_lane_12, o_lane_13, o_lane_14, o_lane_15;
    logic          out_scramble_en;
    logic          mapper_ready;
endinterface

module Mapper_tb;

    import Mapper_tb_pkg::*;

    bit clk;
    mapper_if mif(clk);

    // Clock generator (period = 10 ns)
    always #5 clk = ~clk;

    // DUT Instantiation
    unit_mapper #(
        .WIDTH(32),
        .NUM_LANES(16),
        .N_BYTES(64)
    ) DUT (
        .i_clk(mif.clk),
        .i_rst_n(mif.rst_n),
        .i_in_data(mif.i_in_data),
        .mapper_en(mif.mapper_en),
        .i_width_deg_map(mif.i_width_deg_map),
        .lp_irdy(mif.lp_irdy),
        .lp_valid(mif.lp_valid),

        .o_lane_0(mif.o_lane_0),   .o_lane_1(mif.o_lane_1),   .o_lane_2(mif.o_lane_2),   .o_lane_3(mif.o_lane_3),
        .o_lane_4(mif.o_lane_4),   .o_lane_5(mif.o_lane_5),   .o_lane_6(mif.o_lane_6),   .o_lane_7(mif.o_lane_7),
        .o_lane_8(mif.o_lane_8),   .o_lane_9(mif.o_lane_9),   .o_lane_10(mif.o_lane_10), .o_lane_11(mif.o_lane_11),
        .o_lane_12(mif.o_lane_12), .o_lane_13(mif.o_lane_13), .o_lane_14(mif.o_lane_14), .o_lane_15(mif.o_lane_15),
        .out_scramble_en(mif.out_scramble_en),
        .mapper_ready(mif.mapper_ready)
    );

    mapper_driver     drv;
    mapper_monitor    mon;
    mapper_scoreboard scb;

    // Direct assertions for the handshake protocol rules (as requested by user)
    // 1. lp_valid once asserted cannot drop until mapper_ready goes high
    always @(posedge clk) begin
        if (mif.rst_n && $past(mif.rst_n) && mif.mapper_en && $past(mif.mapper_en) && $past(mif.lp_valid) && !$past(mif.mapper_ready)) begin
            assert(mif.lp_valid === 1'b1) else $error("[Protocol Assertion Violation] lp_valid went low before ready went high!");
        end
    end

    // 2. lp_irdy once asserted cannot drop until mapper_ready goes high
    always @(posedge clk) begin
        if (mif.rst_n && $past(mif.rst_n) && mif.mapper_en && $past(mif.mapper_en) && $past(mif.lp_irdy) && !$past(mif.mapper_ready)) begin
            assert(mif.lp_irdy === 1'b1) else $error("[Protocol Assertion Violation] lp_irdy went low before ready went high!");
        end
    end

    // // 3. lp_irdy and lp_valid must BOTH be 1 for a push to occur (tested at the DUT input)
    // always @(posedge clk) begin
    //     if (mif.rst_n && mif.mapper_en && DUT.push) begin
    //         assert(mif.lp_valid === 1'b1 && mif.lp_irdy === 1'b1) else $error("[Protocol Assertion Violation] Push occurred but lp_valid or lp_irdy was low!");
    //     end
    // end

    // Helper task to run active traffic tests for a given degradation mode
    task automatic run_mode_test(input logic [2:0] mode, input string name);
        $display("\n[TB] Starting test for degradation mode: %s", name);
        drv.run(700, mode); // Run 40 randomized packets for this mode
        repeat(100) @(posedge clk); // Allow time for scoreboard queue to drain
        $display("[TB] Completed test for %s. Current scoreboard status: Pass=%0d, Fail=%0d", name, scb.pass, scb.fail);
    endtask

    initial begin
        drv = new(mif);
        mon = new(mif);
        scb = new(mon);

        // 1. Reset Sequence (completely ref to posedge clk as requested)
        mif.i_in_data       <= 512'b0;
        mif.lp_valid        <= 1'b0;
        mif.lp_irdy         <= 1'b0;
        mif.mapper_en       <= 1'b0;
        mif.i_width_deg_map <= 3'b011;
        mif.rst_n           <= 1'b0;

        repeat(3) @(posedge clk);
        #1;
        mif.rst_n <= 1'b1;
        $display("\n[TB] System Reset De-asserted. Starting Class-Based Structured Tests...\n");

        // Start all verification components
        fork
            mon.run();
            scb.run();
            scb.check();
        join_none

        // Test 1: Run active traffic tests for all 5 degradation modes
        // During these tests, mapper_en remains high as a stable control signal
        run_mode_test(3'b011, "x16 lanes (0 to 15)");
        run_mode_test(3'b001, "x8 lanes (0 to 7)");
        run_mode_test(3'b010, "x8 lanes (8 to 15)");
        run_mode_test(3'b100, "x4 lanes (0 to 3)");
        run_mode_test(3'b101, "x4 lanes (4 to 7)");

        // Disable monitor/scoreboard checking during manual directed/failure tests
        mon.enable_check = 0;

        // Test 2: Test mapper_ready when disabled (mapper_en = 0)
        // Verify that ready stays 0 and no data gets latched or mapped.
        $display("\n[TB] Test 2: Testing ready-when-disabled behaviour (mapper_en = 0)...");
        @(posedge clk);
        mif.mapper_en <= 1'b0;
        mif.lp_valid  <= 1'b1;
        mif.lp_irdy   <= 1'b1;
        mif.i_in_data <= 512'hDEAF_BEEF_DEAF_BEEF;
        repeat(5) begin
            @(posedge clk);
            #1;
            assert(mif.mapper_ready === 1'b0) else $error("[TB ERR] mapper_ready is not low when mapper_en is low!");
            assert(mif.out_scramble_en === 1'b0) else $error("[TB ERR] out_scramble_en is high when mapper_en is low!");
        end
        mif.lp_valid  <= 1'b0;
        mif.lp_irdy   <= 1'b0;
        mif.mapper_en <= 1'b1; // Re-enable for subsequent tests

        // Test 3: Test that BOTH valid and irdy must be 1 for a push/latch
        $display("\n[TB] Test 3: Testing that BOTH lp_valid and lp_irdy must be 1 to latch data...");
        
        // Wait for ready
        @(posedge clk);
        while (!mif.mapper_ready) @(posedge clk);

        // Drive lp_valid = 1, lp_irdy = 0
        $display("   -> Driving lp_valid=1, lp_irdy=0...");
        mif.lp_valid  <= 1'b1;
        mif.lp_irdy   <= 1'b0;
        mif.i_in_data <= 512'hAAAA_BBBB_CCCC_DDDD;
        repeat(3) @(posedge clk);
        #1;
        assert(mif.out_scramble_en === 1'b0) else $error("[TB ERR] Data latched when lp_irdy was 0!");

        // Drive lp_valid = 0, lp_irdy = 1
        $display("   -> Driving lp_valid=0, lp_irdy=1...");
        mif.lp_valid  <= 1'b0;
        mif.lp_irdy   <= 1'b1;
        mif.i_in_data <= 512'h1111_2222_3333_4444;
        repeat(3) @(posedge clk);
        #1;
        assert(mif.out_scramble_en === 1'b0) else $error("[TB ERR] Data latched when lp_valid was 0!");

        // Drive both to 1 to complete the handshake
        $display("   -> Driving both lp_valid=1, lp_irdy=1...");
        mif.lp_valid  <= 1'b1;
        mif.lp_irdy   <= 1'b1;
        mif.i_in_data <= 512'h5555_6666_7777_8888;
        @(posedge clk);
        while (!mif.mapper_ready) @(posedge clk);
        mif.lp_valid  <= 1'b0;
        mif.lp_irdy   <= 1'b0;
        repeat(5) @(posedge clk); // Allow it to finish mapping

        // Test 4: Test mid-transfer reset
        $display("\n[TB] Test 4: Testing reset during an active transfer...");
        @(posedge clk);
        mif.mapper_en       <= 1'b1;
        mif.i_width_deg_map <= 3'b100; // x4 mode, 4 cycles
        mif.lp_valid        <= 1'b1;
        mif.lp_irdy         <= 1'b1;
        mif.i_in_data       <= 512'hCAFE_BABE;
        
        // Let it run for 2 cycles
        repeat(2) @(posedge clk);
        #1;
        
        // Assert reset mid-transfer
        mif.rst_n <= 1'b0;
        @(posedge clk);
        #1;
        mif.rst_n <= 1'b1;
        #1;

        // Verify outputs are zeroed immediately
        assert(mif.o_lane_0 === 0 && mif.o_lane_15 === 0 && mif.out_scramble_en === 0)
            else $error("[TB ERR] Outputs not cleared after synchronous/asynchronous reset!");

        repeat(10) @(posedge clk);

        // Final Summary Report
        $display("\n==================================================");
        $display("            VERIFICATION SUMMARY REPORT             ");
        $display("==================================================");
        $display(" Total Packets Checked  : %0d", (scb.pass + scb.fail));
        $display(" Packets Passed         : %0d", scb.pass);
        $display(" Packets Failed         : %0d", scb.fail);
        $display("==================================================\n");

        if (scb.fail == 0 && scb.pass > 0)
            $display("ALL TESTS PASSED SUCCESSFULLY");
        else
            $display("TEST FAILURE: %0d packets failed verification!", scb.fail);

        $stop;
    end

endmodule