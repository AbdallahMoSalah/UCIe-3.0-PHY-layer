`timescale 1ns/1ps

module mb_des_valid_tb;

    parameter DATA_WIDTH = 32;

    reg                   MB_clk;
    reg                   pll_clk;
    reg                   i_rst_n;
    reg                   ser_valid_en;
    reg                   ser_data_in;
    
    wire                  enable_des_valid_frame;
    wire [DATA_WIDTH-1:0] par_data_out;
    wire                  de_ser_done;

    // Instantiate the Unit Under Test (UUT)
    MB_DESERIALIZER_VALID #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .MB_clk(MB_clk),
        .pll_clk(pll_clk),
        .i_rst_n(i_rst_n),
        .ser_valid_en(ser_valid_en),
        .ser_data_in(ser_data_in),
        .enable_des_valid_frame(enable_des_valid_frame),
        .par_data_out(par_data_out),
        .de_ser_done(de_ser_done)
    );

    // Clock generation
    initial begin
        MB_clk = 0;
        forever #32 MB_clk = ~MB_clk; // 100MHz (period = 10ns)
    end

    initial begin
        pll_clk = 0;
        forever #1 pll_clk = ~pll_clk; // 500MHz (period = 2ns) -> DDR means 1ns per bit
    end

    // Task to send a frame
    task send_frame(input [31:0] data);
        integer i;
        begin
            @(posedge pll_clk);
            #0.1;
            ser_valid_en = 1;
            for (i = 0; i < 32; i = i + 1) begin
                ser_data_in = data[i];
                @(pll_clk); // Wait for the next edge (posedge or negedge)
                #0.1;       // Update immediately after the edge
            end
            ser_valid_en = 0;
            ser_data_in  = 0;
        end
    endtask

    // Test sequence
    initial begin
        // Initialize Inputs
        i_rst_n = 0;
        ser_valid_en = 0;
        ser_data_in = 0;

        // Reset the system
        #20;
        i_rst_n = 1;
        #20;

        // Test Case 1: Valid Frame (Non-Zero)
        $display("[%0t] Starting Test Case 1: Valid Frame", $time);
        send_frame(32'hDEADBEEF);
        
        // Wait for de_ser_done
        @(posedge de_ser_done);
        #0.1;
        $display("[%0t] de_ser_done asserted", $time);
        
        // Check outputs
        if (par_data_out === 32'hDEADBEEF && enable_des_valid_frame === 1'b1) begin
            $display("[%0t] Test Case 1 Passed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end else begin
            $display("[%0t] Test Case 1 Failed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end
        
        #50;

        // Test Case 2: Invalid Frame (All Zeros)
        $display("[%0t] Starting Test Case 2: Invalid Frame (All Zeros)", $time);
        send_frame(32'h00000000);
        
        // Wait for de_ser_done
        @(posedge de_ser_done);
        #0.1;
        $display("[%0t] de_ser_done asserted", $time);
        
        // Check outputs
        if (par_data_out === 32'h00000000 && enable_des_valid_frame === 1'b0) begin
            $display("[%0t] Test Case 2 Passed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end else begin
            $display("[%0t] Test Case 2 Failed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end

        #50;

        // Test Case 3: Another Valid Frame
        $display("[%0t] Starting Test Case 3: Another Valid Frame", $time);
        send_frame(32'hA5A5A5A5);
        
        // Wait for de_ser_done
        @(posedge de_ser_done);
        #0.1;
        $display("[%0t] de_ser_done asserted", $time);
        
        // Check outputs
        if (par_data_out === 32'hA5A5A5A5 && enable_des_valid_frame === 1'b1) begin
            $display("[%0t] Test Case 3 Passed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end else begin
            $display("[%0t] Test Case 3 Failed: par_data_out = %h, enable_des_valid_frame = %b", $time, par_data_out, enable_des_valid_frame);
        end

        #50;
        $display("[%0t] All Tests Completed.", $time);
        $finish;
    end

    // Dump waves
    initial begin
        $dumpfile("mb_des_valid_tb.vcd");
        $dumpvars(0, mb_des_valid_tb);
    end

    initial begin
        #10000;
        $display("Timeout");
        $finish;
    end

endmodule
