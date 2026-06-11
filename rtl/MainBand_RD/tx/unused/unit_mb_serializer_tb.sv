`timescale 1ns/1ps

module unit_mb_serializer_tb;

    parameter DATA_WIDTH = 32;

    // Control signals
    reg         rst_n;
    reg         ser_en;
    reg  [DATA_WIDTH-1:0] in_data;
    wire        ser_out;

    // PLL signals
    reg         pll_en;
    reg  [1:0]  speed_sel;
    wire        pll_clk;
    real        pll_period_val; // in ps

    // Clock Divider signals
    wire        mb_clk;

    // Stats
    integer     pass_count = 0;
    integer     fail_count = 0;

    // Queue for expected data verification
    reg [DATA_WIDTH-1:0] expected_words[$];

    // Instantiate PLL
    unit_mb_pll u_pll (
        .en(pll_en),
        .speed_sel(speed_sel),
        .clk(pll_clk),
        .local_period(pll_period_val)
    );

    // Instantiate Clock Divider (Ratio = 16)
    ClkDiv #(.RangeWidth(8)) u_clk_div (
        .i_ref_clk(pll_clk),
        .i_rst_n(rst_n),
        .i_clk_en(1'b1),
        .i_div_ratio(8'd16),
        .o_div_clk(mb_clk)
    );

    // Instantiate DUT (unit_mb_serializer)
    unit_mb_serializer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT (
        .mb_clk(mb_clk),
        .PLL_clk(pll_clk),
        .i_rst_n(rst_n),
        .Ser_en(ser_en),
        .in_data(in_data),
        .SER_out(ser_out)
    );

    // ============================================================
    // Monitor & Verification Thread
    // Spawns a verification thread for every serialization start
    // ============================================================
    always @(posedge pll_clk) begin
        if (rst_n && DUT.rising_ser_en_pll === 1'b1) begin
            fork
                automatic reg [DATA_WIDTH-1:0] exp_val = expected_words.pop_front();
                begin
                    real half_period_ns;
                    real mid_ns;
                    
                    // Wait for 1 PLL cycle startup latency of the retimed DDR mux
                    @(posedge pll_clk);

                    for (int j = 0; j < DATA_WIDTH; j = j + 1) begin
                        half_period_ns = pll_period_val / 2000.0;
                        mid_ns = half_period_ns / 2.0;

                        if (j % 2 == 0) begin
                            // ---- Even bit (High phase) ----
                            #(mid_ns);
                            if (ser_out !== exp_val[j]) begin
                                $display("[ERROR] T=%0t ns | Word mismatch at even bit %0d: expected=%b, got=%b (ExpWord: 0x%08h)", 
                                         $time, j, exp_val[j], ser_out, exp_val);
                                fail_count = fail_count + 1;
                            end else begin
                                pass_count = pass_count + 1;
                            end
                            @(negedge pll_clk);
                        end else begin
                            // ---- Odd bit (Low phase) ----
                            #(mid_ns);
                            if (ser_out !== exp_val[j]) begin
                                $display("[ERROR] T=%0t ns | Word mismatch at odd bit %0d: expected=%b, got=%b (ExpWord: 0x%08h)", 
                                         $time, j, exp_val[j], ser_out, exp_val);
                                fail_count = fail_count + 1;
                            end else begin
                                pass_count = pass_count + 1;
                            end
                            @(posedge pll_clk);
                        end
                    end
                end
            join_none
        end
    end

    // ============================================================
    // Test Stimulus
    // ============================================================
    initial begin
        $display("======================================================");
        $display("       UCIe Main-Band Serializer Unit Testbench       ");
        $display("======================================================");

        // Initialize
        rst_n      = 0;
        ser_en     = 0;
        in_data    = 0;
        pll_en     = 1;
        speed_sel  = 2'b00; // 2 GHz default (500 ps period)

        #50;
        rst_n = 1;
        #50;

        // ============================================================
        // TEST CASE 1: Single Word Serialization (Standard Speed 2 GHz)
        // ============================================================
        $display("\n--- TEST 1: Single Word (2 GHz) ---");
        @(posedge mb_clk);
        in_data = 32'hA5A5F0F0;
        ser_en  = 1;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0;
        in_data = 0;
        
        // Wait for serialization to finish (32 bits DDR at 2 GHz takes 16 cycles = 8ns)
        #50;

        // ============================================================
        // TEST CASE 2: Heavy Load - Back-to-Back Words (No Gap)
        // ============================================================
        $display("\n--- TEST 2: Heavy Load - Back-to-Back (2 GHz) ---");
        @(posedge mb_clk);
        ser_en  = 1;
        
        in_data = 32'hDEADBEEF;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        in_data = 32'hCAFEBABE;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        in_data = 32'h12345678;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        in_data = 32'h87654321;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0;
        in_data = 0;

        #100;

        // ============================================================
        // TEST CASE 3: Gapped Packets (1 and 2 cycle gaps)
        // ============================================================
        $display("\n--- TEST 3: Gapped Packets (2 GHz) ---");
        @(posedge mb_clk);
        ser_en  = 1;
        in_data = 32'h55555555;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0; // 1 cycle gap
        
        @(posedge mb_clk);
        ser_en  = 1;
        in_data = 32'hAAAAAAAA;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0; // 2 cycle gap
        @(posedge mb_clk);
        
        @(posedge mb_clk);
        ser_en  = 1;
        in_data = 32'hF0F0F0F0;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0;
        in_data = 0;

        #100;

        // ============================================================
        // TEST CASE 4: Different PLL Frequencies
        // ============================================================
        // 4 GHz Mode (speed_sel = 2'b01)
        $display("\n--- TEST 4: Heavy Load at 4 GHz (speed_sel = 2'b01) ---");
        @(posedge mb_clk);
        speed_sel = 2'b01;
        #50; // Wait for PLL to stabilize
        
        @(posedge mb_clk);
        ser_en  = 1;
        in_data = 32'h11111111;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        in_data = 32'h22222222;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0;
        in_data = 0;
        #50;

        // 8 GHz Mode (speed_sel = 2'b10)
        $display("\n--- TEST 5: Heavy Load at 8 GHz (speed_sel = 2'b10) ---");
        @(posedge mb_clk);
        speed_sel = 2'b10;
        #50;
        
        @(posedge mb_clk);
        ser_en  = 1;
        in_data = 32'h33333333;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        in_data = 32'h44444444;
        expected_words.push_back(in_data);
        
        @(posedge mb_clk);
        ser_en  = 0;
        in_data = 0;
        #50;

        // ============================================================
        // End of Simulation Summary
        // ============================================================
        #200;
        $display("\n======================================================");
        $display("                SIMULATION RESULTS                    ");
        $display("======================================================");
        $display("  Pass Bits: %0d", pass_count);
        $display("  Fail Bits: %0d", fail_count);
        $display("======================================================");
        if (fail_count == 0 && pass_count > 0) begin
            $display("  >>> ALL TESTS PASSED SUCCESSFULLY (NO FIFO NEEDED) <<<");
        end else begin
            $display("  >>> SOME TESTS FAILED <<<");
        end
        $display("======================================================");
        $finish;
    end

endmodule