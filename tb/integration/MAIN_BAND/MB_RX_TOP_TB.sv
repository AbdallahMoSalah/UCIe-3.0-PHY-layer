`timescale 1ns/1ps

module MB_RX_TOP_TB;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter N_BYTES = 64;

    // Clock and Reset
    logic MB_clk;
    logic pll_clk;
    logic i_rst_n;

    // Serial Data Inputs
    logic ser_valid_en;
    logic SER_out;
    logic ser_data_en;
    logic [15:0] ser_data_in;

    // Clock Pattern Detector Inputs
    logic clk_detector_en;
    logic clk_p;
    logic clk_n;
    logic track;

    // LTSM & Control Inputs
    logic [2:0] i_state;
    logic [2:0] i_width_deg_lfsr;
    logic i_active_state_entered;
    logic i_descramble_en;
    logic i_enable_buffer;

    logic [11:0] i_max_error_threshold_valid;
    logic i_enable_cons;
    logic i_enable_128;
    logic i_enable_detector;

    logic [1:0] i_type_of_com;
    logic [15:0] i_max_error_threshold_per_lane_ID;
    logic [15:0] i_max_error_threshold_aggergate;

    logic demapper_en;
    logic rx_data_valid;
    logic [2:0] i_width_deg_demap;

    // Outputs
    logic de_ser_done;
    logic de_ser_done_data_0;
    logic de_ser_done_data_1;
    logic de_ser_done_data_2;
    logic de_ser_done_data_3;
    logic de_ser_done_data_4;
    logic de_ser_done_data_5;
    logic de_ser_done_data_6;
    logic de_ser_done_data_7;
    logic de_ser_done_data_8;
    logic de_ser_done_data_9;
    logic de_ser_done_data_10;
    logic de_ser_done_data_11;
    logic de_ser_done_data_12;
    logic de_ser_done_data_13;
    logic de_ser_done_data_14;
    logic de_ser_done_data_15;

    logic detection_result;
    logic o_valid_frame_detect;

    logic [15:0] o_per_lane_error;
    logic [31:0] o_error_counter;
    logic o_error_done;

    logic clk_p_pattern_error;
    logic clk_n_pattern_error;
    logic track_pattern_error;

    logic pl_valid;
    logic [8*N_BYTES-1:0] o_out_data;

    // Assign rx_data_valid to de_ser_done so Demapper only operates when a valid frame arrives
    assign rx_data_valid = de_ser_done;

    // Instantiate the Top Module
    MB_RX_TOP #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_BYTES(N_BYTES)
    ) dut (
        .MB_clk(MB_clk),
        .pll_clk(pll_clk),
        .i_rst_n(i_rst_n),

        .ser_valid_en(ser_valid_en),
        .SER_out(SER_out),
        .ser_data_en(ser_data_en),
        .ser_data_in(ser_data_in),

        .clk_detector_en(clk_detector_en),
        .clk_p(clk_p),
        .clk_n(clk_n),
        .track(track),

        .i_state(i_state),
        .i_width_deg_lfsr(i_width_deg_lfsr),
        .i_active_state_entered(i_active_state_entered),
        .i_descramble_en(i_descramble_en),
        .i_enable_buffer(i_enable_buffer),

        .i_max_error_threshold_valid(i_max_error_threshold_valid),
        .i_enable_cons(i_enable_cons),
        .i_enable_128(i_enable_128),
        .i_enable_detector(i_enable_detector),

        .i_type_of_com(i_type_of_com),
        .i_max_error_threshold_per_lane_ID(i_max_error_threshold_per_lane_ID),
        .i_max_error_threshold_aggergate(i_max_error_threshold_aggergate),

        .demapper_en(demapper_en),
        .rx_data_valid(rx_data_valid),
        .i_width_deg_demap(i_width_deg_demap),

        .de_ser_done(de_ser_done),
        .de_ser_done_data_0(de_ser_done_data_0),
        .de_ser_done_data_1(de_ser_done_data_1),
        .de_ser_done_data_2(de_ser_done_data_2),
        .de_ser_done_data_3(de_ser_done_data_3),
        .de_ser_done_data_4(de_ser_done_data_4),
        .de_ser_done_data_5(de_ser_done_data_5),
        .de_ser_done_data_6(de_ser_done_data_6),
        .de_ser_done_data_7(de_ser_done_data_7),
        .de_ser_done_data_8(de_ser_done_data_8),
        .de_ser_done_data_9(de_ser_done_data_9),
        .de_ser_done_data_10(de_ser_done_data_10),
        .de_ser_done_data_11(de_ser_done_data_11),
        .de_ser_done_data_12(de_ser_done_data_12),
        .de_ser_done_data_13(de_ser_done_data_13),
        .de_ser_done_data_14(de_ser_done_data_14),
        .de_ser_done_data_15(de_ser_done_data_15),

        .detection_result(detection_result),
        .o_valid_frame_detect(o_valid_frame_detect),

        .o_per_lane_error(o_per_lane_error),
        .o_error_counter(o_error_counter),
        .o_error_done(o_error_done),

        .clk_p_pattern_error(clk_p_pattern_error),
        .clk_n_pattern_error(clk_n_pattern_error),
        .track_pattern_error(track_pattern_error),

        .pl_valid(pl_valid),
        .o_out_data(o_out_data)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    
    // PLL Clock: Fast clock. Deserializer shifts on BOTH edges (DDR).
    // Let's set a 2ns period (toggles every 1ns).
    initial begin
        pll_clk = 0;
        forever #1 pll_clk = ~pll_clk;
    end

    // Main Band Clock: 32x slower than PLL clock frequency.
    // Period = 32 * 2ns = 64ns -> Toggle every 32ns.
    initial begin
        MB_clk = 0;
        forever #32 MB_clk = ~MB_clk;
    end

    // =========================================================================
    // Task: Send Serial Frame (DDR Aware)
    // =========================================================================
    // Since the DUT deserializer shifts on BOTH posedge and negedge of pll_clk,
    // we must supply a new bit every 1ns (half period).
    task send_serial_frame(input logic [31:0] valid_word, input logic [31:0] data_words [0:15]);
        begin
            // Align with a clock edge to start cleanly
            @(posedge pll_clk);
            
            ser_valid_en = 1;
            ser_data_en = 1;
            
            // Send 32 bits (16 pll_clk cycles total due to DDR)
            for (int i = 0; i < 32; i++) begin
                // Wait 0.5ns (middle of the phase) to assign data safely, 
                // avoiding race conditions with the next clock edge at 1.0ns
                #0.5; 
                SER_out = valid_word[i];
                for (int j = 0; j < 16; j++) begin
                    ser_data_in[j] = data_words[j][i];
                end
                
                // Wait the remaining 0.5ns exactly hitting the clock edge where DUT captures
                #0.5;
            end
            
            // Wait slightly after the last capture edge, then clear inputs
            #0.5;
            SER_out = 0;
            ser_data_in = 16'd0;
            ser_valid_en = 0;
            ser_data_en  = 0;
            
            // Wait until the edge to stay aligned
            #0.5;
        end
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        // Initialize Inputs
        i_rst_n = 0;
        ser_valid_en = 0;
        SER_out = 0;
        ser_data_en = 0;
        ser_data_in = 0;
        
        clk_detector_en = 1;
        clk_p = 0; clk_n = 1; track = 0;

        // Configure modules for Active mode bypass test
        i_state = 3'b100; // DATA_TRANSFER
        i_width_deg_lfsr = 3'b011; // x16 mode
        i_active_state_entered = 1; // ACTIVE STATE -> will trigger Bypass in Comparator
        i_descramble_en = 0;
        i_enable_buffer = 1;

        i_max_error_threshold_valid = 12'd10;
        i_enable_cons = 1;
        i_enable_128  = 0;
        i_enable_detector = 1;

        i_type_of_com = 2'b00;
        i_max_error_threshold_per_lane_ID = 16'd10;
        i_max_error_threshold_aggergate = 16'd100;

        demapper_en = 1;
        i_width_deg_demap = 3'b011; // x16 mode

        // Reset Pulse
        #100;
        i_rst_n = 1;
        #100;

        $display("[%0t] Starting Simulation...", $time);

        // Send a frame
        begin
            logic [31:0] tx_valid_word;
            logic [31:0] tx_data_words [0:15];
            
            tx_valid_word = 32'hF0F0F0F0; // Valid pattern

            // Fill data lanes with recognizable patterns
            tx_data_words[0]  = 32'h0000_1111;
            tx_data_words[1]  = 32'h0001_2222;
            tx_data_words[2]  = 32'h0002_3333;
            tx_data_words[3]  = 32'h0003_4444;
            tx_data_words[4]  = 32'h0004_5555;
            tx_data_words[5]  = 32'h0005_6666;
            tx_data_words[6]  = 32'h0006_7777;
            tx_data_words[7]  = 32'h0007_8888;
            tx_data_words[8]  = 32'h0008_9999;
            tx_data_words[9]  = 32'h0009_AAAA;
            tx_data_words[10] = 32'h000A_BBBB;
            tx_data_words[11] = 32'h000B_CCCC;
            tx_data_words[12] = 32'h000C_DDDD;
            tx_data_words[13] = 32'h000D_EEEE;
            tx_data_words[14] = 32'h000E_FFFF;
            tx_data_words[15] = 32'h000F_0000;

            $display("[%0t] Sending Frame...", $time);
            send_serial_frame(tx_valid_word, tx_data_words);
        end

        // Wait for Demapper to process (takes a few MB_clk cycles due to CDC)
        fork
            begin
                wait(pl_valid == 1'b1);
                $display("[%0t] SUCCESS! Frame Demapped! pl_valid received.", $time);
                $display("---------------------------------------------------");
                $display("Demapper Output [31:0]   (Lane 0) : %h", o_out_data[31:0]);
                $display("Demapper Output [63:32]  (Lane 1) : %h", o_out_data[63:32]);
                $display("Demapper Output [95:64]  (Lane 2) : %h", o_out_data[95:64]);
                $display("Demapper Output [127:96] (Lane 3) : %h", o_out_data[127:96]);
                $display("---------------------------------------------------");
            end
            begin
                #5000;
                $display("[%0t] ERROR: Timeout waiting for pl_valid!", $time);
            end
        join_any
        disable fork;

        #200;
        $display("[%0t] Simulation Finished.", $time);
        $stop;
    end

endmodule
