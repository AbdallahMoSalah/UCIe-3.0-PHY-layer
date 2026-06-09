`timescale 1ns/1ps
// =============================================================================
// Testbench: mb_des_valid_tb
// Purpose  : Unit-level tests for MB_DESERIALIZER_VALID.
//
// Design key points:
//   - No ser_valid_en port. Module is free-running.
//   - Frame alignment: FSM triggers on rising edge (0→1) of ser_data_in.
//   - Valid pattern: 32'h0F0F0F0F (LSB-first: bits 0..31 = 1111 0000 ...)
//     ⇒ bit[0] = 1, so FSM fires on the very first bit after reset.
//   - 16 negedge pll_clk cycles = one 32-bit DDR frame.
//   - Outputs arrive in MB_clk domain after 3-FF CDC (≈ 3 MB_clk cycles).
//
// Clock relationship:
//   pll_clk : period = 2 ns  (toggle every 1 ns)
//   MB_clk  : period = 64 ns (toggle every 32 ns) = 32 × pll_clk periods
//
// Test Cases:
//   TC-1 : send 0x0F0F0F0F → enable_des_valid_frame=1, par_data_out=0x0F0F0F0F
//   TC-2 : send 0x00000000 → enable_des_valid_frame=0, par_data_out=0 (no rising edge → no CDC trigger!)
//   TC-3 : send 0x0F0F0F0F again → re-confirms enable=1
//   TC-4 : send 3 back-to-back 0x0F0F0F0F frames → all produce enable=1
// =============================================================================

module mb_des_valid_tb;

    parameter DATA_WIDTH = 32;
    parameter PLL_HALF   = 1;   // 1 ns → pll_clk period = 2 ns
    parameter MB_HALF    = 32;  // 32 ns → MB_clk period = 64 ns

    // ── Signals ───────────────────────────────────────────────────────────────
    reg                   MB_clk;
    reg                   pll_clk;
    reg                   i_rst_n;
    reg                   ser_data_in;

    wire                  enable_des_valid_frame;
    wire [DATA_WIDTH-1:0] par_data_out;
    wire                  de_ser_done;

    // ── DUT Instantiation ─────────────────────────────────────────────────────
    MB_DESERIALIZER_VALID #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .MB_clk                (MB_clk),
        .pll_clk               (pll_clk),
        .i_rst_n               (i_rst_n),
        .ser_data_in           (ser_data_in),
        .enable_des_valid_frame(enable_des_valid_frame),
        .par_data_out          (par_data_out),
        .de_ser_done           (de_ser_done)
    );

    // ── Clock Generation ─────────────────────────────────────────────────────
    initial begin pll_clk = 0; forever #(PLL_HALF) pll_clk = ~pll_clk; end
    initial begin MB_clk  = 0; forever #(MB_HALF)  MB_clk  = ~MB_clk;  end

    // ── Task: send_ddr_frame ──────────────────────────────────────────────────
    // Sends a 32-bit word in DDR LSB-first.
    // Timing: drive even bit before negedge (captured by DUT on negedge),
    //         drive odd bit before posedge (captured as r_data_pos).
    // The FSM triggers on the 0→1 transition of ser_data_in sensed at negedge.
    // For 0x0F0F0F0F: bit[0]=1, so the first negedge after the first bit sees
    //   ser_data_in=1 and prev=0 → FSM goes RUNNING immediately.
    task automatic send_ddr_frame(input [31:0] data);
        integer i;
        begin
            // Ensure we start on a posedge boundary (DUT negedge follows)
            @(posedge pll_clk);
            #0.1;
            for (i = 0; i < 16; i = i + 1) begin
                // even bit: captured at negedge of pll_clk
                ser_data_in = data[2*i];
                @(negedge pll_clk);
                #0.1;
                // odd bit: captured as r_data_pos at next posedge
                ser_data_in = data[2*i+1];
                @(posedge pll_clk);
                #0.1;
            end
            ser_data_in = 1'b0;
        end
    endtask

    // ── Task: check_output ────────────────────────────────────────────────────
    // Waits for de_ser_done, then checks expected values.
    task automatic check_output(
        input string       tc_name,
        input logic [31:0] exp_par_data,
        input logic        exp_enable
    );
        begin
            @(posedge de_ser_done);
            #0.1;
            if (par_data_out === exp_par_data && enable_des_valid_frame === exp_enable) begin
                $display("[%0t] %s PASSED → par_data=%h  enable=%b",
                          $time, tc_name, par_data_out, enable_des_valid_frame);
            end else begin
                $display("[%0t] %s FAILED!", $time, tc_name);
                $display("  par_data_out : got %h  exp %h", par_data_out, exp_par_data);
                $display("  enable       : got %b  exp %b", enable_des_valid_frame, exp_enable);
                $fatal(1, "%s failed", tc_name);
            end
        end
    endtask

    // ── Main Test ─────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("mb_des_valid_tb.vcd");
        $dumpvars(0, mb_des_valid_tb);

        // Initialise
        i_rst_n     = 1'b0;
        ser_data_in = 1'b0;
        repeat (6) @(posedge MB_clk);
        @(negedge MB_clk);
        i_rst_n = 1'b1;
        repeat (2) @(posedge MB_clk);

        $display("=================================================");
        $display("[%0t] MB_DESERIALIZER_VALID – Unit Tests", $time);
        $display("=================================================");

        // ------------------------------------------------------------------
        // TC-1: First valid pattern 0x0F0F0F0F
        //   Expected: par_data_out=0x0F0F0F0F, enable_des_valid_frame=1
        // ------------------------------------------------------------------
        $display("\n[TC-1] First valid pattern 0x0F0F0F0F");
        fork
            send_ddr_frame(32'h0F0F0F0F);
            check_output("TC-1", 32'h0F0F0F0F, 1'b1);
        join
        repeat(2) @(posedge MB_clk);

        // ------------------------------------------------------------------
        // TC-2: All-zeros frame (00000000)
        //   bit[0]=0 → no rising edge on ser_data_in → FSM stays IDLE.
        //   The DUT will NOT produce a de_ser_done pulse for this frame.
        //   We just send it and wait a few cycles to confirm no output.
        // Note: The all-zeros pattern has no rising edge so the FSM never
        //       triggers. de_ser_done will NOT fire → we just check it is
        //       still 0 after the frame duration.
        // ------------------------------------------------------------------
        $display("\n[TC-2] All-zeros frame (no frame start → no output expected)");
        begin
            integer t;
            // Drive zeros for 16 pll_clk cycles (= 1 DDR frame duration)
            @(posedge pll_clk); #0.1;
            for (t = 0; t < 32; t = t + 1) begin
                ser_data_in = 1'b0;
                @(pll_clk); #0.1;
            end
            ser_data_in = 1'b0;
            // Wait and confirm no output
            repeat(6) @(posedge MB_clk);
            if (de_ser_done === 1'b0) begin
                $display("[%0t] TC-2 PASSED → no de_ser_done for all-zeros (correct, no rising edge)", $time);
            end else begin
                $display("[%0t] TC-2 FAILED → unexpected de_ser_done!", $time);
                $fatal(1, "TC-2 failed");
            end
        end
        repeat(2) @(posedge MB_clk);

        // ------------------------------------------------------------------
        // TC-3: Repeat valid pattern 0x0F0F0F0F → confirm enable stays 1
        // ------------------------------------------------------------------
        $display("\n[TC-3] Repeat valid pattern 0x0F0F0F0F");
        fork
            send_ddr_frame(32'h0F0F0F0F);
            check_output("TC-3", 32'h0F0F0F0F, 1'b1);
        join
        repeat(2) @(posedge MB_clk);

        // ------------------------------------------------------------------
        // TC-4: 3 back-to-back valid frames
        // ------------------------------------------------------------------
        $display("\n[TC-4] 3 back-to-back valid frames");
        begin
            integer k;
            string  lbl;
            for (k = 0; k < 3; k = k + 1) begin
                $sformat(lbl, "TC-4[%0d]", k);
                fork
                    send_ddr_frame(32'h0F0F0F0F);
                    check_output(lbl, 32'h0F0F0F0F, 1'b1);
                join
                repeat(1) @(posedge MB_clk);
            end
        end

        // ------------------------------------------------------------------
        // TC-5: Reset mid-stream then re-send → enable must restart from 0→1
        // ------------------------------------------------------------------
        $display("\n[TC-5] Reset then re-lock");
        i_rst_n = 1'b0;
        ser_data_in = 1'b0;
        repeat(4) @(posedge MB_clk);
        @(negedge MB_clk);
        i_rst_n = 1'b1;
        // Confirm cleared
        @(posedge MB_clk); #0.1;
        if (enable_des_valid_frame !== 1'b0) begin
            $display("[%0t] TC-5 FAILED: enable not cleared after reset", $time);
            $fatal(1, "TC-5 reset check failed");
        end
        $display("[%0t] TC-5: Reset confirmed. Sending 0x0F0F0F0F...", $time);
        fork
            send_ddr_frame(32'h0F0F0F0F);
            check_output("TC-5", 32'h0F0F0F0F, 1'b1);
        join
        repeat(2) @(posedge MB_clk);

        // Done
        $display("\n=================================================");
        $display("[%0t] ALL TESTS PASSED", $time);
        $display("=================================================");
        repeat(4) @(posedge MB_clk);
        $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin
        #500000;
        $display("[%0t] WATCHDOG TIMEOUT", $time);
        $fatal(1, "Watchdog");
    end

endmodule