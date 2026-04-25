/*==============================================================================
 * Comprehensive Testbench: LFSR_TX  vs  LFSR_TX_golden
 * ============================================================================
 * - Instantiates both DUTs side-by-side with identical stimulus
 * - Compares every output port every clock cycle
 * - Covers ALL states and ALL degrade modes with and without lane reversal
 * - Reports PASS / FAIL per test with a final summary
 *============================================================================*/

`timescale 1ns/1ps

module LFSR_TX_tb;

    /*--------------------------------------------------------------------------
     * Parameters
     *------------------------------------------------------------------------*/
    parameter WIDTH     = 32;
    parameter CLK_PERIOD = 10;   // 10 ns → 100 MHz

    /*--------------------------------------------------------------------------
     * Clock & reset
     *------------------------------------------------------------------------*/
    logic clk;
    logic rst_n;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    /*--------------------------------------------------------------------------
     * Shared stimulus signals
     *------------------------------------------------------------------------*/
    logic [1:0]        i_state;
    logic              scramble_en;
    logic [2:0]        i_width_deg_lfsr;
    logic              reversal_en;

    logic [WIDTH-1:0]  i_lane [0:15];

    /*--------------------------------------------------------------------------
     * RTL DUT outputs
     *------------------------------------------------------------------------*/
    logic [WIDTH-1:0]  dut_o_lane [0:15];
    logic              dut_done;
    logic              dut_valid;

    /*--------------------------------------------------------------------------
     * Golden Model outputs
     *------------------------------------------------------------------------*/
    logic [WIDTH-1:0]  gld_o_lane [0:15];
    logic              gld_done;
    logic              gld_valid;

    /*--------------------------------------------------------------------------
     * Instantiate RTL DUT
     *------------------------------------------------------------------------*/
    LFSR_TX #(.WIDTH(WIDTH)) u_dut (
        .i_clk              (clk),
        .i_rst_n            (rst_n),
        .i_state            (i_state),
        .scramble_en        (scramble_en),
        .i_width_deg_lfsr   (i_width_deg_lfsr),
        .reversal_en        (reversal_en),
        .i_lane_0 (i_lane[0]),  .i_lane_1 (i_lane[1]),
        .i_lane_2 (i_lane[2]),  .i_lane_3 (i_lane[3]),
        .i_lane_4 (i_lane[4]),  .i_lane_5 (i_lane[5]),
        .i_lane_6 (i_lane[6]),  .i_lane_7 (i_lane[7]),
        .i_lane_8 (i_lane[8]),  .i_lane_9 (i_lane[9]),
        .i_lane_10(i_lane[10]), .i_lane_11(i_lane[11]),
        .i_lane_12(i_lane[12]), .i_lane_13(i_lane[13]),
        .i_lane_14(i_lane[14]), .i_lane_15(i_lane[15]),
        .o_lane_0 (dut_o_lane[0]),  .o_lane_1 (dut_o_lane[1]),
        .o_lane_2 (dut_o_lane[2]),  .o_lane_3 (dut_o_lane[3]),
        .o_lane_4 (dut_o_lane[4]),  .o_lane_5 (dut_o_lane[5]),
        .o_lane_6 (dut_o_lane[6]),  .o_lane_7 (dut_o_lane[7]),
        .o_lane_8 (dut_o_lane[8]),  .o_lane_9 (dut_o_lane[9]),
        .o_lane_10(dut_o_lane[10]), .o_lane_11(dut_o_lane[11]),
        .o_lane_12(dut_o_lane[12]), .o_lane_13(dut_o_lane[13]),
        .o_lane_14(dut_o_lane[14]), .o_lane_15(dut_o_lane[15]),
        .o_Lfsr_tx_done (dut_done),
        .valid_frame_en  (dut_valid)
    );

   /*--------------------------------------------------------------------------
 * Instantiate Golden Model (UPDATED PORTS)
 *------------------------------------------------------------------------*/
LFSR_TX_GOLD #(.WIDTH(WIDTH)) u_gold (
    .i_clk_g              (clk),
    .i_rst_n_g            (rst_n),
    .i_state_g            (i_state),
    .scramble_en_g        (scramble_en),
    .i_width_deg_lfsr_g   (i_width_deg_lfsr),
    .reversal_en_g        (reversal_en),

    .i_lane_0_g (i_lane[0]),   .i_lane_1_g (i_lane[1]),
    .i_lane_2_g (i_lane[2]),   .i_lane_3_g (i_lane[3]),
    .i_lane_4_g (i_lane[4]),   .i_lane_5_g (i_lane[5]),
    .i_lane_6_g (i_lane[6]),   .i_lane_7_g (i_lane[7]),
    .i_lane_8_g (i_lane[8]),   .i_lane_9_g (i_lane[9]),
    .i_lane_10_g(i_lane[10]),  .i_lane_11_g(i_lane[11]),
    .i_lane_12_g(i_lane[12]),  .i_lane_13_g(i_lane[13]),
    .i_lane_14_g(i_lane[14]),  .i_lane_15_g(i_lane[15]),

    .o_lane_0_g (gld_o_lane[0]),   .o_lane_1_g (gld_o_lane[1]),
    .o_lane_2_g (gld_o_lane[2]),   .o_lane_3_g (gld_o_lane[3]),
    .o_lane_4_g (gld_o_lane[4]),   .o_lane_5_g (gld_o_lane[5]),
    .o_lane_6_g (gld_o_lane[6]),   .o_lane_7_g (gld_o_lane[7]),
    .o_lane_8_g (gld_o_lane[8]),   .o_lane_9_g (gld_o_lane[9]),
    .o_lane_10_g(gld_o_lane[10]),  .o_lane_11_g(gld_o_lane[11]),
    .o_lane_12_g(gld_o_lane[12]),  .o_lane_13_g(gld_o_lane[13]),
    .o_lane_14_g(gld_o_lane[14]),  .o_lane_15_g(gld_o_lane[15]),

    .o_Lfsr_tx_done_g (gld_done),
    .valid_frame_en_g (gld_valid)
);

    /*--------------------------------------------------------------------------
     * Scoreboard — per-cycle automatic comparison
     *------------------------------------------------------------------------*/
    int total_cycles;
    int mismatch_count;
    int test_mismatches;   // mismatches inside a single test

    task automatic check_outputs(input string cont);
        logic fail;
        fail = 0;
        for (int i = 0; i < 16; i++) begin
            if (dut_o_lane[i] !== gld_o_lane[i]) begin
                $display("  [MISMATCH] %s @ %0t  o_lane_%0d  DUT=%0h  GOLD=%0h",
                         cont, $time, i, dut_o_lane[i], gld_o_lane[i]);
                fail = 1;
            end
        end
        if (dut_done !== gld_done) begin
            $display("  [MISMATCH] %s @ %0t  o_Lfsr_tx_done  DUT=%0b  GOLD=%0b",
                     cont, $time, dut_done, gld_done);
            fail = 1;
        end
        if (dut_valid !== gld_valid) begin
            $display("  [MISMATCH] %s @ %0t  valid_frame_en  DUT=%0b  GOLD=%0b",
                     cont, $time, dut_valid, gld_valid);
            fail = 1;
        end
        if (fail) begin
            mismatch_count++;
            test_mismatches++;
        end
        total_cycles++;
    endtask

    // Continuous per-posedge check (runs in parallel with stimulus)
    string current_test_name;
    always @(posedge clk) begin
        if (rst_n)
            check_outputs(current_test_name);
    end

    /*--------------------------------------------------------------------------
     * Helpers
     *------------------------------------------------------------------------*/

    // Function to compute the next LFSR state (from user request)
    function automatic [31:0] next_lfsr_state(input [22:0] current_state);
        logic [31:0] next_state;
        begin
            next_state[0]  = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[1]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[2]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[3]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[4]  = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[12] ^ current_state[14] ^ current_state[16] ^ current_state[18] ^ current_state[22];
            next_state[5]  = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[21];
            next_state[6]  = current_state[1] ^  current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20] ^ current_state[22];                        
            next_state[7]  = current_state[0] ^ current_state[3] ^current_state[4]  ^current_state[6]  ^current_state[7]  ^current_state[9]  ^current_state[11]  ^current_state[15]  ^current_state[16]  ^current_state[17]  ^current_state[18]  ^current_state[19]  ;
            next_state[8]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[9]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[10] = current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[12] ^ current_state[14] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[11] = current_state[0] ^ current_state[2] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[10] ^ current_state[11] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[12] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[11] ^ current_state[12] ^ current_state[14] ^ current_state[17] ^ current_state[20];
            next_state[13] = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[12] ^ current_state[13] ^ current_state[15] ^ current_state[18] ^ current_state[21];
            next_state[14] = current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[8] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[19] ^ current_state[22];
            next_state[15] = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[14] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[20] ^ current_state[21];
            next_state[16] = current_state[1] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[21] ^ current_state[22];
            next_state[17] = current_state[0] ^ current_state[4] ^ current_state[6] ^ current_state[10] ^ current_state[11] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21] ^ current_state[22];
            next_state[18] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[7] ^ current_state[8] ^ current_state[11] ^ current_state[12] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[19] = current_state[0] ^ current_state[1] ^ current_state[3] ^ current_state[5] ^ current_state[9] ^ current_state[12] ^ current_state[13] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[20] = current_state[0] ^ current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[10] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20];
            next_state[21] = current_state[1] ^ current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[11] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21];
            next_state[22] = current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[15] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[23] = next_state[0] ^ next_state[2] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[9] ^ next_state[11] ^ next_state[13] ^ next_state[17] ^ next_state[19] ^ next_state[20];
            next_state[24] = next_state[1] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[6] ^ next_state[8] ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[18] ^ next_state[20] ^ next_state[21];
            next_state[25] = next_state[2] ^ next_state[4] ^ next_state[5] ^ next_state[6] ^ next_state[7] ^ next_state[9] ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[19] ^ next_state[21] ^ next_state[22];
            next_state[26] = next_state[0] ^ next_state[2] ^ next_state[3] ^ next_state[6] ^ next_state[7] ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[20] ^ next_state[21] ^ next_state[22];
            next_state[27] = next_state[0] ^ next_state[1] ^ next_state[2] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[16] ^ next_state[22];
            next_state[28] = next_state[0] ^ next_state[1] ^ next_state[3] ^ next_state[4] ^ next_state[6] ^ next_state[12] ^ next_state[14] ^ next_state[17] ^ next_state[21];
            next_state[29] = next_state[1] ^ next_state[2] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[13] ^ next_state[15] ^ next_state[18] ^ next_state[22];
            next_state[30] = next_state[0] ^ next_state[3] ^ next_state[6] ^ next_state[14] ^ next_state[19] ^ next_state[21];
            next_state[31] = next_state[1] ^ next_state[4] ^ next_state[7] ^ next_state[15] ^ next_state[20] ^ next_state[22];
            return next_state;
        end
    endfunction

    // Monitor logic to display values on outputs
    always @(posedge clk) begin
        if (dut_valid) begin
            $display("Time: %0t | STATE: %b | DEGRADE_MODE: %b | SCRAMBLE: %b | REV: %b",
                     $time, i_state, i_width_deg_lfsr, scramble_en, reversal_en);
            $display("  => OUTPUT LANES (Valid Frame):");
            $display("     LANE_0 : %h | LANE_1 : %h | LANE_2 : %h | LANE_3 : %h", dut_o_lane[0], dut_o_lane[1], dut_o_lane[2], dut_o_lane[3]);
            $display("     LANE_4 : %h | LANE_5 : %h | LANE_6 : %h | LANE_7 : %h", dut_o_lane[4], dut_o_lane[5], dut_o_lane[6], dut_o_lane[7]);
            $display("     LANE_8 : %h | LANE_9 : %h | LANE_10: %h | LANE_11: %h", dut_o_lane[8], dut_o_lane[9], dut_o_lane[10], dut_o_lane[11]);
            $display("     LANE_12: %h | LANE_13: %h | LANE_14: %h | LANE_15: %h", dut_o_lane[12], dut_o_lane[13], dut_o_lane[14], dut_o_lane[15]);
            $display("----------------------------------------------------------------------------------");
        end
    end

    // Apply reset
    task do_reset();
        rst_n            = 0;
        i_state          = 2'b00;
        scramble_en      = 0;
        i_width_deg_lfsr = 3'b000;
        reversal_en      = 0;
        for (int i = 0; i < 16; i++) i_lane[i] = '0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);
    endtask

    // Random input lanes
    task randomize_input_lanes();
        for (int i = 0; i < 16; i++)
            i_lane[i] = $urandom();
    endtask

    // Trigger a state transition from IDLE (pulse new state for 1 cycle)
    task trigger_state(input logic [1:0] new_state);
        @(negedge clk);
        i_state = new_state;
        @(negedge clk);
        // keep i_state so FSM sees the change; RTL latches i_state_reg
    endtask

    // Wait until done flag asserts (with timeout)
    task wait_done(input int timeout_cycles = 500);
        int cnt;
        cnt = 0;
        while (!dut_done && cnt < timeout_cycles) begin
            @(posedge clk);
            cnt++;
        end
        if (cnt >= timeout_cycles)
            $display("  [WARN] wait_done timed out after %0d cycles", timeout_cycles);
        // extra cycle for outputs to settle
        @(posedge clk);
    endtask

    // Return to IDLE between tests
    task go_idle();
        @(negedge clk);
        i_state = 2'b00;
        repeat(3) @(posedge clk);
    endtask

    // Print test result
    task print_result(input string name);
        if (test_mismatches == 0)
            $display("  [PASS] %s", name);
        else
            $display("  [FAIL] %s  (%0d mismatches)", name, test_mismatches);
        test_mismatches = 0;
    endtask

    /*==========================================================================
     * MAIN TEST SEQUENCE
     *========================================================================*/
    initial begin
        $display("========================================================");
        $display("  LFSR_TX vs LFSR_TX_golden  —  Full Regression");
        $display("========================================================");
        total_cycles    = 0;
        mismatch_count  = 0;
        test_mismatches = 0;
        current_test_name = "reset";

        //----------------------------------------------------------------------
        // T0: Reset behaviour
        //----------------------------------------------------------------------
        current_test_name = "T0_reset";
        do_reset();
        repeat(5) @(posedge clk);
        print_result("T0: Reset (all outputs zeroed, seeds loaded)");

        //======================================================================
        // ---- CLEAR_LFSR -----
        //======================================================================

        //----------------------------------------------------------------------
        // T1: CLEAR_LFSR from IDLE
        //----------------------------------------------------------------------
        current_test_name = "T1_CLEAR_LFSR";
        test_mismatches = 0;
        trigger_state(2'b01);          // → CLEAR_LFSR
        repeat(5) @(posedge clk);      // CLEAR_LFSR lasts 1 cycle → back to IDLE
        go_idle();
        print_result("T1: CLEAR_LFSR (seed reload, back to IDLE)");

        //======================================================================
        // ---- PATTERN_LFSR  (scramble_en=0) ----
        //======================================================================

        // Loop over all 5 active degrade modes × reversal {0,1}
        begin
            automatic logic [2:0] modes [0:4] = '{3'b001,3'b010,3'b011,3'b100,3'b101};
            automatic string      mnames[0:4] = '{"0_TO_7","8_TO_15","0_TO_15","0_TO_3","4_TO_7"};

            for (int m = 0; m < 5; m++) begin
                for (int rev = 0; rev < 2; rev++) begin
                    automatic string tname;

                    // fresh reset for every sub-test
                    do_reset();
                    randomize_input_lanes();

                    scramble_en      = 0;
                    i_width_deg_lfsr = modes[m];
                    reversal_en      = rev[0];

                    tname = $sformatf("T_PATTERN_%s_rev%0d", mnames[m], rev);
                    current_test_name = tname;
                    test_mismatches   = 0;

                    // If reversal requested: assert in IDLE first
                    if (rev) begin
                        @(negedge clk); reversal_en = 1;
                        repeat(2) @(posedge clk);
                    end

                    trigger_state(2'b10);    // → PATTERN_LFSR
                    wait_done(300);          // runs 128 cycles
                    go_idle();
                    print_result(tname);
                end
            end
        end

        //======================================================================
        // ---- PATTERN_LFSR  (scramble_en=1) ----
        //======================================================================
        begin
            automatic logic [2:0] modes [0:4] = '{3'b001,3'b010,3'b011,3'b100,3'b101};
            automatic string      mnames[0:4] = '{"0_TO_7","8_TO_15","0_TO_15","0_TO_3","4_TO_7"};

            for (int m = 0; m < 5; m++) begin
                for (int rev = 0; rev < 2; rev++) begin
                    automatic string tname;

                    do_reset();
                    randomize_input_lanes();

                    scramble_en      = 1;
                    i_width_deg_lfsr = modes[m];
                    reversal_en      = rev[0];

                    tname = $sformatf("T_SCRAMBLE_%s_rev%0d", mnames[m], rev);
                    current_test_name = tname;
                    test_mismatches   = 0;

                    if (rev) begin
                        @(negedge clk); reversal_en = 1;
                        repeat(2) @(posedge clk);
                    end

                    trigger_state(2'b10);
                    // Scrambler mode runs forever; check for 20 cycles
                    repeat(20) @(posedge clk);
                    go_idle();
                    print_result(tname);
                end
            end
        end

        //======================================================================
        // ---- PER_LANE_IDE ----
        //======================================================================
        begin
            automatic logic [2:0] modes [0:4] = '{3'b001,3'b010,3'b011,3'b100,3'b101};
            automatic string      mnames[0:4] = '{"0_TO_7","8_TO_15","0_TO_15","0_TO_3","4_TO_7"};

            for (int m = 0; m < 5; m++) begin
                for (int rev = 0; rev < 2; rev++) begin
                    automatic string tname;

                    do_reset();

                    scramble_en      = 0;
                    i_width_deg_lfsr = modes[m];
                    reversal_en      = rev[0];

                    tname = $sformatf("T_PER_LANE_IDE_%s_rev%0d", mnames[m], rev);
                    current_test_name = tname;
                    test_mismatches   = 0;

                    if (rev) begin
                        @(negedge clk); reversal_en = 1;
                        repeat(2) @(posedge clk);
                    end

                    trigger_state(2'b11);    // → PER_LANE_IDE
                    wait_done(200);          // runs 64 cycles
                    go_idle();
                    print_result(tname);
                end
            end
        end

        //======================================================================
        // ---- Back-to-back state sequences ----
        //======================================================================

        //----------------------------------------------------------------------
        // T_SEQ1: CLEAR → PATTERN → PER_LANE_IDE  (no reversal)
        //----------------------------------------------------------------------
        current_test_name = "T_SEQ1_CLEAR_PATTERN_IDE";
        test_mismatches   = 0;
        do_reset();
        scramble_en      = 0;
        i_width_deg_lfsr = 3'b011;   // 0_TO_15
        reversal_en      = 0;

        trigger_state(2'b01); repeat(3)  @(posedge clk); go_idle();   // CLEAR
        trigger_state(2'b10); wait_done(300);             go_idle();   // PATTERN
        trigger_state(2'b11); wait_done(200);             go_idle();   // IDE
        print_result("T_SEQ1: CLEAR → PATTERN(0_TO_15) → IDE(0_TO_15)");

        //----------------------------------------------------------------------
        // T_SEQ2: CLEAR → PATTERN (scramble) → CLEAR again → PATTERN
        //         Check that CLEAR reloads seeds properly
        //----------------------------------------------------------------------
        current_test_name = "T_SEQ2_double_CLEAR";
        test_mismatches   = 0;
        do_reset();
        scramble_en      = 1;
        i_width_deg_lfsr = 3'b001;
        reversal_en      = 0;
        randomize_input_lanes();

        trigger_state(2'b01); repeat(3) @(posedge clk); go_idle();
        trigger_state(2'b10); repeat(20) @(posedge clk); go_idle();
        trigger_state(2'b01); repeat(3) @(posedge clk); go_idle();   // CLEAR again
        trigger_state(2'b10); repeat(20) @(posedge clk); go_idle();
        print_result("T_SEQ2: CLEAR→SCRAMBLE→CLEAR→SCRAMBLE (seed reload check)");

        //----------------------------------------------------------------------
        // T_SEQ3: Reversal enabled mid-simulation
        //----------------------------------------------------------------------
        current_test_name = "T_SEQ3_reversal_midway";
        test_mismatches   = 0;
        do_reset();
        scramble_en      = 0;
        i_width_deg_lfsr = 3'b001;
        reversal_en      = 0;

        trigger_state(2'b10); wait_done(300); go_idle();
        // now enable reversal
        @(negedge clk); reversal_en = 1; repeat(3) @(posedge clk);
        trigger_state(2'b10); wait_done(300); go_idle();
        print_result("T_SEQ3: PATTERN(no rev) → PATTERN(rev enabled midway)");

        //----------------------------------------------------------------------
        // T_SEQ4: All degrade modes in sequence without reset
        //----------------------------------------------------------------------
        current_test_name = "T_SEQ4_all_modes_no_reset";
        test_mismatches   = 0;
        do_reset();
        scramble_en = 0;
        reversal_en = 0;
        begin
            automatic logic [2:0] modes[0:4] = '{3'b001,3'b010,3'b011,3'b100,3'b101};
            for (int m = 0; m < 5; m++) begin
                i_width_deg_lfsr = modes[m];
                trigger_state(2'b10);
                wait_done(300);
                go_idle();
                trigger_state(2'b11);
                wait_done(200);
                go_idle();
            end
        end
        print_result("T_SEQ4: All degrade modes sequentially (no reset)");

        //----------------------------------------------------------------------
        // T_RANDOM: Random stimulus — random lanes, random degrade, random reversal
        //----------------------------------------------------------------------
        current_test_name = "T_RANDOM_stimulus";
        test_mismatches   = 0;
        begin
            for (int iter = 0; iter < 20; iter++) begin
                automatic logic [2:0] rmode;
                automatic logic       rrev;
                automatic logic [1:0] rstate;
                automatic int         rmode_idx;

                do_reset();

                // pick a valid degrade mode (1–5)
                rmode_idx = ($urandom % 5) + 1;
                rmode     = rmode_idx[2:0];
                rrev      = $urandom_range(0,1);
                // pick PATTERN or IDE
                rstate    = ($urandom_range(0,1)) ? 2'b10 : 2'b11;

                scramble_en      = $urandom_range(0,1);
                i_width_deg_lfsr = rmode;
                reversal_en      = rrev;
                randomize_input_lanes();

                if (rrev) begin
                    @(negedge clk); reversal_en = 1;
                    repeat(2) @(posedge clk);
                end

                trigger_state(rstate);
                if (scramble_en && rstate == 2'b10)
                    repeat(30) @(posedge clk);
                else
                    wait_done(300);
                go_idle();
            end
        end
        print_result("T_RANDOM: 20 random iterations");

        //----------------------------------------------------------------------
        // T_IDLE_STABILITY: Stay in IDLE for many cycles — nothing should change
        //----------------------------------------------------------------------
        current_test_name = "T_IDLE_stability";
        test_mismatches   = 0;
        do_reset();
        scramble_en = 0; i_width_deg_lfsr = 3'b001; reversal_en = 0;
        repeat(50) @(posedge clk);
        print_result("T_IDLE_stability: 50 cycles in IDLE (no spurious outputs)");

        //======================================================================
        // SUMMARY
        //======================================================================
        $display("========================================================");
        $display("  TOTAL CYCLES CHECKED : %0d", total_cycles);
        $display("  TOTAL MISMATCHES     : %0d", mismatch_count);
        if (mismatch_count == 0)
            $display("  OVERALL RESULT       : *** ALL TESTS PASSED ***");
        else
            $display("  OVERALL RESULT       : *** FAILURES DETECTED ***");
        $display("========================================================");
        $finish;
    end

    /*--------------------------------------------------------------------------
     * Timeout watchdog
     *------------------------------------------------------------------------*/
    initial begin
        #500_000;
        $display("[WATCHDOG] Simulation timeout — forcing finish");
        $finish;
    end

    /*--------------------------------------------------------------------------
     * Optional waveform dump (comment out if not needed)
     *------------------------------------------------------------------------*/
    initial begin
        $dumpfile("tb_LFSR_TX_vs_Golden.vcd");
        $dumpvars(0, LFSR_TX_tb);
    end

endmodule
