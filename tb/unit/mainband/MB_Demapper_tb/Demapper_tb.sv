module Demapper_tb;
    //============================================================
    // Parameters (same as DUT)
    //============================================================
    localparam N_BYTES   = 64;
    localparam WIDTH     = 32;
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;
    
    //============================================================
    // Signals
    //============================================================
    logic i_clk;
    logic i_rst_n;
    
    // unit_mapper Inputs
    logic [8*N_BYTES-1:0] i_in_data;
    logic                 mapper_en;
    logic [2:0]           i_width_deg;
    logic                 lp_irdy;
    logic                 lp_valid;
    
    // unit_mapper Outputs / unit_demapper Inputs
    wire [WIDTH-1:0] m_lane [0:15];
    wire             out_scramble_en;
    wire             mapper_ready;
    
    // unit_demapper Outputs
    wire                 pl_valid;
    wire [8*N_BYTES-1:0] o_out_data;
    
    integer correct_count = 0;
    integer error_count   = 0;

    //============================================================
    // Clock Generation (100 MHz)
    //============================================================
    initial i_clk = 0;
    always #5 i_clk = ~i_clk;

    //============================================================
    // Instantiations
    //============================================================
    unit_mapper #(
        .WIDTH(WIDTH),
        .NUM_LANES(16),
        .N_BYTES(N_BYTES)
    ) mapper_inst (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_in_data(i_in_data),
        .mapper_en(mapper_en),
        .i_width_deg_map(i_width_deg),
        .lp_irdy(lp_irdy),
        .lp_valid(lp_valid),
        .o_lane_0 (m_lane[0]),
        .o_lane_1 (m_lane[1]),
        .o_lane_2 (m_lane[2]),
        .o_lane_3 (m_lane[3]),
        .o_lane_4 (m_lane[4]),
        .o_lane_5 (m_lane[5]),
        .o_lane_6 (m_lane[6]),
        .o_lane_7 (m_lane[7]),
        .o_lane_8 (m_lane[8]),
        .o_lane_9 (m_lane[9]),
        .o_lane_10(m_lane[10]),
        .o_lane_11(m_lane[11]),
        .o_lane_12(m_lane[12]),
        .o_lane_13(m_lane[13]),
        .o_lane_14(m_lane[14]),
        .o_lane_15(m_lane[15]),
        .out_scramble_en(out_scramble_en),
        .mapper_ready(mapper_ready)
    );

    unit_demapper #(
        .N_BYTES(N_BYTES),
        .WIDTH(WIDTH)
    ) demapper_inst (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_lane_0 (m_lane[0]),
        .i_lane_1 (m_lane[1]),
        .i_lane_2 (m_lane[2]),
        .i_lane_3 (m_lane[3]),
        .i_lane_4 (m_lane[4]),
        .i_lane_5 (m_lane[5]),
        .i_lane_6 (m_lane[6]),
        .i_lane_7 (m_lane[7]),
        .i_lane_8 (m_lane[8]),
        .i_lane_9 (m_lane[9]),
        .i_lane_10(m_lane[10]),
        .i_lane_11(m_lane[11]),
        .i_lane_12(m_lane[12]),
        .i_lane_13(m_lane[13]),
        .i_lane_14(m_lane[14]),
        .i_lane_15(m_lane[15]),
        .demapper_en(mapper_en),
        .rx_data_valid(out_scramble_en),
        .i_width_deg_demap(i_width_deg),
        .pl_valid(pl_valid),
        .o_out_data(o_out_data)
    );

    //============================================================
    // Test Task
    //============================================================
    task test_mode;
        input [2:0] mode;
        input integer num_cycles;
        input [8*N_BYTES-1:0] test_data;
        integer timeout;
        logic [8*N_BYTES-1:0] expected_data;
        integer i;
    begin
        $display("Testing Mode %b (%0d cycles)", mode, num_cycles);
        
        // unit_demapper is now a faithful inverse of unit_mapper: the recovered
        // flit equals the original (i_in_data[7:0] -> o_out_data[7:0]). So the
        // expected result is simply test_data unchanged.
        expected_data = test_data;

        i_width_deg = mode;
        i_in_data   = test_data;
        mapper_en   = 1;
        lp_irdy     = 1;
        lp_valid    = 1;
        
        timeout = 0;
        // Wait for pl_valid
        while (!pl_valid && timeout < 20) begin
            @(posedge i_clk); #1;
            timeout = timeout + 1;
        end
        
        if (timeout == 20) begin
            $display("[ERR] Timeout waiting for pl_valid in mode %b", mode);
            error_count = error_count + 1;
        end else begin
            // Check data
            if (o_out_data !== expected_data) begin
                $display("[ERR] Data mismatch in mode %b", mode);
                $display("Expected: %h", expected_data);
                $display("Actual:   %h", o_out_data);
                error_count = error_count + 1;
            end else begin
                correct_count = correct_count + 1;
            end
            
            // Allow pl_valid to clear
            @(posedge i_clk); #1;
        end
        
        mapper_en = 0;
        lp_irdy   = 0;
        lp_valid  = 0;
        repeat(5) @(posedge i_clk);
    end
    endtask

    //============================================================
    // Stimulus
    //============================================================
    logic [511:0] rand_data;
    initial begin
        // Init
        i_rst_n     = 1'b1;
        mapper_en   = 0;
        lp_irdy     = 0;
        lp_valid    = 0;
        i_width_deg = DEGRADE_LANES_0_TO_15;
        i_in_data   = 0;
        
        // Reset
        #10 i_rst_n = 1'b0;
        #10 i_rst_n = 1'b1;
        repeat(5) @(posedge i_clk);

        // Generate a random 512-bit payload for testing
        rand_data = {
            32'h11112222, 32'h33334444, 32'h55556666, 32'h77778888,
            32'h9999AAAA, 32'hBBBBCCCC, 32'hDDDDEEEE, 32'hFFFF0000,
            32'h12345678, 32'h9ABCDEF0, 32'h0FEDCBA9, 32'h87654321,
            32'hCAFEF00D, 32'hDEADBEEF, 32'h8BADF00D, 32'hC0DEFACE
        };

        // Test x16 mode
        test_mode(DEGRADE_LANES_0_TO_15, 1, rand_data);
        // Test x8 mode (0 to 7)
        test_mode(DEGRADE_LANES_0_TO_7, 2, rand_data);
        // Test x8 mode (8 to 15)
        test_mode(DEGRADE_LANES_8_TO_15, 2, rand_data);
        // Test x4 mode (0 to 3)
        test_mode(DEGRADE_LANES_0_TO_3, 4, rand_data);
        // Test x4 mode (4 to 7)
        test_mode(DEGRADE_LANES_4_TO_7, 4, rand_data);

        // Result summary
        $display("=================================");
        $display("Correct Count = %0d", correct_count);
        $display("Error Count   = %0d", error_count);
        $display("=================================");
        
        if (error_count == 0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED (%0d errors)", error_count);
        
        $stop;
    end
endmodule