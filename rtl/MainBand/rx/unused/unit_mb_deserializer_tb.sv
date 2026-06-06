// =============================================================================
// Testbench : unit_mb_deserializer_tb
// Purpose   : Spec-check MB_DESERIALIZER (data lane). Drives a clean DDR serial
//             stream that is a faithful model of MB_SERIALIZER's output --
//             LSB first, 2 bits per pll_clk cycle, even bit word[2n] in the
//             pll_clk HIGH phase, odd bit word[2n+1] in the LOW phase -- and
//             checks that par_data_out reconstructs the original word.
//
//             deserialize(stream(word)) must equal word. The production copy
//             fails this (it pairs each even bit with the PREVIOUS odd bit, so
//             the word comes out shifted left by 1 with bit31 dropped); the
//             fixed copy in unsued/ passes.
//
//   Drive is race-free: ser_data_in changes #0.1 AFTER each clock edge, so the
//   DUT samples the value that was stable across the edge.
// =============================================================================
`timescale 1ns/1ps

module unit_mb_deserializer_tb;

    localparam int DATA_WIDTH = 32;
    localparam int HALF       = DATA_WIDTH/2;   // 16 DDR cycles per word

    // ---- clocks / reset ----
    logic MB_clk;
    logic pll_clk;
    logic i_rst_n;

    initial begin
        pll_clk = 1'b0;
        forever #1 pll_clk = ~pll_clk;          // 2 ns period
    end
    initial begin
        MB_clk = 1'b0;
        forever #(DATA_WIDTH/2) MB_clk = ~MB_clk; // 32 ns period = 16 pll cycles
    end

    // ---- DUT I/O ----
    logic                   ser_data_en;
    logic                   ser_data_in;
    logic                   enable_des_valid_frame;
    logic [DATA_WIDTH-1:0]  par_data_out;
    logic                   de_ser_done;

    unit_mb_deserializer #(.DATA_WIDTH(DATA_WIDTH)) DUT (
        .MB_clk                 (MB_clk),
        .pll_clk                (pll_clk),
        .i_rst_n                (i_rst_n),
        .ser_data_en            (ser_data_en),
        .ser_data_in            (ser_data_in),
        .enable_des_valid_frame (enable_des_valid_frame),
        .par_data_out           (par_data_out),
        .de_ser_done            (de_ser_done)
    );

    // ---- test vectors ----
    localparam int NVEC = 8;
    logic [DATA_WIDTH-1:0] VEC [0:NVEC-1] = '{
        32'hA5A5_5A5A,
        32'hDEAD_BEEF,
        32'h0000_0001,   // bit0  : exposes left-shift bug -> 0x2
        32'h8000_0000,   // bit31 : dropped by the bug      -> 0x0
        32'h1234_5678,
        32'hFFFF_FFFF,   // all ones: bug -> 0xFFFFFFFE
        32'h0000_00FF,
        32'hCAFE_F00D
    };

    integer vi, j, fails;
    logic [DATA_WIDTH-1:0] cap;
    logic got;

    // -------------------------------------------------------------------------
    // Drive one 32-bit word as a DDR stream (LSB first).
    //  even bit word[2k] is stable across posedge k, odd bit word[2k+1] across
    //  negedge k. ser_data_en spans posedge0 .. negedge15 so both the posedge
    //  (production) and negedge (fixed) capture/shift logic see a full window.
    // -------------------------------------------------------------------------
    task automatic send_word(input logic [DATA_WIDTH-1:0] w);
        integer k;
        begin
            @(negedge pll_clk);
            #0.1;
            ser_data_in = w[0];          // even[0] ready for posedge0
            ser_data_en = 1'b1;
            for (k = 0; k < HALF; k = k + 1) begin
                @(posedge pll_clk);                 // even[k] sampled
                #0.1; ser_data_in = w[2*k+1];       // present odd[k]
                @(negedge pll_clk);                 // odd[k] sampled
                if (k < HALF-1) begin
                    #0.1; ser_data_in = w[2*(k+1)]; // present even[k+1]
                end
            end
            #0.1; ser_data_en = 1'b0;    // release; deserializer re-aligns next word
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        i_rst_n                = 1'b0;
        ser_data_en            = 1'b0;
        ser_data_in            = 1'b0;
        enable_des_valid_frame = 1'b1;
        fails                  = 0;

        repeat (3) @(posedge MB_clk);
        i_rst_n = 1'b1;
        @(posedge MB_clk);

        $display("==============================================================");
        $display("  unit_mb_deserializer  DDR round-trip check (LSB-first, 2 bits/cyc)");
        $display("  vec |   sent word  | par_data_out | result");
        $display("  ----+--------------+--------------+-------");

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            send_word(VEC[vi]);

            // wait for the pll->MB CDC pulse (de_ser_done), bounded
            got = 1'b0;
            cap = 'x;
            for (j = 0; j < 10 && !got; j = j + 1) begin
                @(posedge MB_clk);
                #0.1;
                if (de_ser_done) begin
                    got = 1'b1;
                    cap = par_data_out;
                end
            end

            if (!got) begin
                fails = fails + 1;
                $display("   %0d  |  0x%08h  |   (no de_ser_done) | TIMEOUT",
                         vi, VEC[vi]);
            end else begin
                if (cap !== VEC[vi]) fails = fails + 1;
                $display("   %0d  |  0x%08h  |  0x%08h  | %s",
                         vi, VEC[vi], cap,
                         (cap === VEC[vi]) ? "MATCH" : "MISMATCH");
            end
        end

        $display("==============================================================");
        if (fails == 0)
            $display("  RESULT: PASS  (all %0d words deserialized correctly)", NVEC);
        else
            $display("  RESULT: FAIL  (%0d/%0d words wrong)", fails, NVEC);
        $display("==============================================================");

        $stop;
    end

    // safety net
    initial begin
        #20000;
        $display("  RESULT: FAIL  (global timeout)");
        $stop;
    end

endmodule