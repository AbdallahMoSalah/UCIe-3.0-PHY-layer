`timescale 1ns/1ps
// =============================================================================
// Testbench: MB_RX_TOP_TB
// Description:
//   Tests all major scenarios in the MB_RX_TOP design:
//   1. CLK Repair Pattern Detection (CLK_PATTERN_DETECTOR_RX)
//   2. Valid Pattern Reception (MB_DES_VALID + VALID_DETECTOR)
//      - 11110000 repeated 4 times = 32'hF0F0F0F0
//   3. Training Modes via LFSR_RX + PATTERN_COMPARATOR:
//      - PATTERN_LFSR (3'b010): LFSR pattern on lanes, goes to comparator
//      - PER_LANE_IDE (3'b011): Lane-ID tokens, goes to comparator
//   4. Active (Data) Mode via LFSR_RX:
//      - DATA_TRANSFER (i_active_state_entered=1): bypass comparator → Demapper
//
// Clock Relationship:
//   PLL_CLK period = 2ns (toggle every 1ns)
//   MB_CLK  period = 64ns (toggle every 32ns) = 32x PLL_CLK period
//
// DDR Deserializer key:
//   Shifts on BOTH posedge and negedge of pll_clk.
//   32 bits = 32 half-edges = 16 full pll_clk cycles = 0.5 MB_CLK cycle.
//   Data must be stable BEFORE each edge.
// =============================================================================

module MB_RX_TOP_TB;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 32;
    parameter N_BYTES    = 64;
    parameter PLL_HALF   = 1;   // 1ns → pll_clk period = 2ns
    parameter MB_HALF    = 16;  // 16ns → MB_clk period = 32ns = 16 * 2ns

    // =========================================================================
    // Signals
    // =========================================================================
    logic                  MB_clk;
    logic                  pll_clk;
    logic                  i_rst_n;

    // Valid lane serial input
    logic                  ser_valid_en;
    logic                  SER_out;

    // 16 data lanes serial input
    logic                  ser_data_en;
    logic [15:0]           ser_data_in;

    // CLK Pattern Detector
    logic                  clk_detector_en;
    logic                  clk_p;
    logic                  clk_n;
    logic                  track;

    // LFSR / LTSM controls
    logic [2:0]            i_state;
    logic [2:0]            i_width_deg_lfsr;
    logic                  i_active_state_entered;
    logic                  i_descramble_en;
    logic                  i_enable_buffer;

    // Valid detector controls
    logic [11:0]           i_max_error_threshold_valid;
    logic                  i_enable_cons;
    logic                  i_enable_128;
    logic                  i_enable_detector;

    // Pattern comparator controls
    logic [1:0]            i_type_of_com;
    logic [15:0]           i_max_error_threshold_per_lane_ID;
    logic [15:0]           i_max_error_threshold_aggergate;
    logic [2:0]            i_width_deg_comp;

    // Demapper controls
    logic                  demapper_en;
    logic                  rx_data_valid;
    logic [2:0]            i_width_deg_demap;

    // Outputs
    logic                  de_ser_done;
    logic                  de_ser_done_data_0,  de_ser_done_data_1;
    logic                  de_ser_done_data_2,  de_ser_done_data_3;
    logic                  de_ser_done_data_4,  de_ser_done_data_5;
    logic                  de_ser_done_data_6,  de_ser_done_data_7;
    logic                  de_ser_done_data_8,  de_ser_done_data_9;
    logic                  de_ser_done_data_10, de_ser_done_data_11;
    logic                  de_ser_done_data_12, de_ser_done_data_13;
    logic                  de_ser_done_data_14, de_ser_done_data_15;
    logic                  detection_result;
    logic                  o_valid_frame_detect;
    logic [15:0]           o_per_lane_error;
    logic [31:0]           o_error_counter;
    logic                  o_error_done;
    logic                  clk_p_pattern_pass;
    logic                  clk_n_pattern_pass;
    logic                  track_pattern_pass;
    logic                  pl_valid;
    logic [8*N_BYTES-1:0]  o_out_data;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    MB_RX_TOP #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_BYTES   (N_BYTES)
    ) dut (
        .MB_clk                      (MB_clk),
        .pll_clk                     (pll_clk),
        .i_rst_n                     (i_rst_n),
        .ser_valid_en                (ser_valid_en),
        .SER_out                     (SER_out),
        .ser_data_en                 (ser_data_en),
        .ser_data_in                 (ser_data_in),
        .clk_detector_en             (clk_detector_en),
        .clk_p                       (clk_p),
        .clk_n                       (clk_n),
        .track                       (track),
        .i_state                     (i_state),
        .i_width_deg_lfsr            (i_width_deg_lfsr),
        .i_active_state_entered      (i_active_state_entered),
        .i_descramble_en             (i_descramble_en),
        .i_enable_buffer             (i_enable_buffer),
        .i_max_error_threshold_valid (i_max_error_threshold_valid),
        .i_enable_cons               (i_enable_cons),
        .i_enable_128                (i_enable_128),
        .i_enable_detector           (i_enable_detector),
        .i_type_of_com               (i_type_of_com),
        .i_max_error_threshold_per_lane_ID  (i_max_error_threshold_per_lane_ID),
        .i_max_error_threshold_aggergate    (i_max_error_threshold_aggergate),
        .i_width_deg_comp            (i_width_deg_comp),
        .demapper_en                 (demapper_en),
        .rx_data_valid               (rx_data_valid),
        .i_width_deg_demap           (i_width_deg_demap),
        .de_ser_done                 (de_ser_done),
        .de_ser_done_data_0          (de_ser_done_data_0),
        .de_ser_done_data_1          (de_ser_done_data_1),
        .de_ser_done_data_2          (de_ser_done_data_2),
        .de_ser_done_data_3          (de_ser_done_data_3),
        .de_ser_done_data_4          (de_ser_done_data_4),
        .de_ser_done_data_5          (de_ser_done_data_5),
        .de_ser_done_data_6          (de_ser_done_data_6),
        .de_ser_done_data_7          (de_ser_done_data_7),
        .de_ser_done_data_8          (de_ser_done_data_8),
        .de_ser_done_data_9          (de_ser_done_data_9),
        .de_ser_done_data_10         (de_ser_done_data_10),
        .de_ser_done_data_11         (de_ser_done_data_11),
        .de_ser_done_data_12         (de_ser_done_data_12),
        .de_ser_done_data_13         (de_ser_done_data_13),
        .de_ser_done_data_14         (de_ser_done_data_14),
        .de_ser_done_data_15         (de_ser_done_data_15),
        .detection_result            (detection_result),
        .o_valid_frame_detect        (o_valid_frame_detect),
        .o_per_lane_error            (o_per_lane_error),
        .o_error_counter             (o_error_counter),
        .o_error_done                (o_error_done),
        .clk_p_pattern_pass          (clk_p_pattern_pass),
        .clk_n_pattern_pass          (clk_n_pattern_pass),
        .track_pattern_pass          (track_pattern_pass),
        .pl_valid                    (pl_valid),
        .o_out_data                  (o_out_data)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial pll_clk = 0;
    always #(PLL_HALF) pll_clk = ~pll_clk;   // Period = 2ns

    initial MB_clk = 0;
    always #(MB_HALF)  MB_clk  = ~MB_clk;    // Period = 64ns = 32 × PLL period

    // =========================================================================
    // Function: tb_next_lfsr_state
    // -------------------------------------------------------------------------
    // Golden model – mirrors next_lfsr_state() in LFSR_RX.sv exactly.
    // Input : 23-bit current LFSR state
    // Output: 32-bit word (bits[22:0]=new state, bits[31:23]=upper 9 bits)
    //
    // The RTL does:
    //   {o_lane_23[i], rx_lfsr_lane[i]} <= next_lfsr_state(rx_lfsr_lane[i])
    //   o_final_gene[i] = {rx_lfsr_lane[i], o_lane_23[i]}
    //                   = {out[22:0], out[31:23]}  ← shuffled 32-bit word
    // =========================================================================
    function automatic [31:0] tb_next_lfsr_state(input [22:0] cs);
        logic [31:0] ns;
        begin
            ns[0]  = cs[1]^cs[2]^cs[3]^cs[4]^cs[7]^cs[8]^cs[10]^cs[14]^cs[15]^cs[17]^cs[18]^cs[19]^cs[20]^cs[22];
            ns[1]  = cs[0]^cs[3]^cs[4]^cs[9]^cs[11]^cs[15]^cs[18]^cs[19]^cs[20];
            ns[2]  = cs[1]^cs[4]^cs[5]^cs[10]^cs[12]^cs[16]^cs[19]^cs[20]^cs[21];
            ns[3]  = cs[2]^cs[5]^cs[6]^cs[11]^cs[13]^cs[17]^cs[20]^cs[21]^cs[22];
            ns[4]  = cs[0]^cs[2]^cs[3]^cs[5]^cs[6]^cs[7]^cs[8]^cs[12]^cs[14]^cs[16]^cs[18]^cs[22];
            ns[5]  = cs[0]^cs[1]^cs[2]^cs[3]^cs[4]^cs[5]^cs[6]^cs[7]^cs[9]^cs[13]^cs[15]^cs[16]^cs[17]^cs[19]^cs[21];
            ns[6]  = cs[1]^cs[2]^cs[3]^cs[4]^cs[5]^cs[6]^cs[7]^cs[8]^cs[10]^cs[14]^cs[16]^cs[17]^cs[18]^cs[20]^cs[22];
            ns[7]  = cs[0]^cs[3]^cs[4]^cs[6]^cs[7]^cs[9]^cs[11]^cs[15]^cs[16]^cs[17]^cs[18]^cs[19];
            ns[8]  = cs[1]^cs[4]^cs[5]^cs[7]^cs[8]^cs[10]^cs[12]^cs[16]^cs[17]^cs[18]^cs[19]^cs[20];
            ns[9]  = cs[2]^cs[5]^cs[6]^cs[8]^cs[9]^cs[11]^cs[13]^cs[17]^cs[18]^cs[19]^cs[20]^cs[21];
            ns[10] = cs[3]^cs[6]^cs[7]^cs[9]^cs[10]^cs[12]^cs[14]^cs[18]^cs[19]^cs[20]^cs[21]^cs[22];
            ns[11] = cs[0]^cs[2]^cs[4]^cs[5]^cs[7]^cs[10]^cs[11]^cs[13]^cs[15]^cs[16]^cs[19]^cs[20]^cs[22];
            ns[12] = cs[0]^cs[1]^cs[2]^cs[3]^cs[6]^cs[11]^cs[12]^cs[14]^cs[17]^cs[20];
            ns[13] = cs[1]^cs[2]^cs[3]^cs[4]^cs[7]^cs[12]^cs[13]^cs[15]^cs[18]^cs[21];
            ns[14] = cs[2]^cs[3]^cs[4]^cs[5]^cs[8]^cs[13]^cs[14]^cs[16]^cs[19]^cs[22];
            ns[15] = cs[0]^cs[2]^cs[3]^cs[4]^cs[6]^cs[8]^cs[9]^cs[14]^cs[15]^cs[16]^cs[17]^cs[20]^cs[21];
            ns[16] = cs[1]^cs[3]^cs[4]^cs[5]^cs[7]^cs[9]^cs[10]^cs[15]^cs[16]^cs[17]^cs[18]^cs[21]^cs[22];
            ns[17] = cs[0]^cs[4]^cs[6]^cs[10]^cs[11]^cs[17]^cs[18]^cs[19]^cs[21]^cs[22];
            ns[18] = cs[0]^cs[1]^cs[2]^cs[7]^cs[8]^cs[11]^cs[12]^cs[16]^cs[18]^cs[19]^cs[20]^cs[21]^cs[22];
            ns[19] = cs[0]^cs[1]^cs[3]^cs[5]^cs[9]^cs[12]^cs[13]^cs[16]^cs[17]^cs[19]^cs[20]^cs[22];
            ns[20] = cs[0]^cs[1]^cs[4]^cs[5]^cs[6]^cs[8]^cs[10]^cs[13]^cs[14]^cs[16]^cs[17]^cs[18]^cs[20];
            ns[21] = cs[1]^cs[2]^cs[5]^cs[6]^cs[7]^cs[9]^cs[11]^cs[14]^cs[15]^cs[17]^cs[18]^cs[19]^cs[21];
            ns[22] = cs[2]^cs[3]^cs[6]^cs[7]^cs[8]^cs[10]^cs[12]^cs[15]^cs[16]^cs[18]^cs[19]^cs[20]^cs[22];
            ns[23] = ns[0]^ns[2]^ns[3]^ns[4]^ns[5]^ns[7]^ns[9]^ns[11]^ns[13]^ns[17]^ns[19]^ns[20];
            ns[24] = ns[1]^ns[3]^ns[4]^ns[5]^ns[6]^ns[8]^ns[10]^ns[12]^ns[14]^ns[18]^ns[20]^ns[21];
            ns[25] = ns[2]^ns[4]^ns[5]^ns[6]^ns[7]^ns[9]^ns[11]^ns[13]^ns[15]^ns[19]^ns[21]^ns[22];
            ns[26] = ns[0]^ns[2]^ns[3]^ns[6]^ns[7]^ns[10]^ns[12]^ns[14]^ns[20]^ns[21]^ns[22];
            ns[27] = ns[0]^ns[1]^ns[2]^ns[3]^ns[4]^ns[5]^ns[7]^ns[11]^ns[13]^ns[15]^ns[16]^ns[22];
            ns[28] = ns[0]^ns[1]^ns[3]^ns[4]^ns[6]^ns[12]^ns[14]^ns[17]^ns[21];
            ns[29] = ns[1]^ns[2]^ns[4]^ns[5]^ns[7]^ns[13]^ns[15]^ns[18]^ns[22];
            ns[30] = ns[0]^ns[3]^ns[6]^ns[14]^ns[19]^ns[21];
            ns[31] = ns[1]^ns[4]^ns[7]^ns[15]^ns[20]^ns[22];
            tb_next_lfsr_state = ns;
        end
    endfunction

    // =========================================================================
    // Function: tb_init_lane_23
    // -------------------------------------------------------------------------
    // Replicates the RTL's init_lane_23 function for cycle-0 seed mapping.
    // =========================================================================
    function automatic [8:0] tb_init_lane_23(input [22:0] s);
        logic [8:0] o;
        begin
            o[8] = s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            o[7] = s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0];
            o[6] = s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            o[5] = s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0];
            o[4] = s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0] ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            o[3] = s[17] ^ s[15] ^ s[10] ^ s[0] ^ s[2]  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1] ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3];
            o[2] = s[16] ^ s[14] ^ s[9]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0] ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0] ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            o[1] = s[15] ^ s[13] ^ s[8]  ^ s[0] ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1] ^ s[17] ^ s[15] ^ s[10] ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1] ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3];
            o[0] = s[14] ^ s[12] ^ s[7] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1] ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0] ^ s[16] ^ s[14] ^ s[9]  ^ s[1] ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0] ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0] ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2] ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            tb_init_lane_23 = o;
        end
    endfunction

    // =========================================================================
    // Task: send_valid_frame
    // -------------------------------------------------------------------------
    // Sends a 32-bit word serially on the VALID lane (SER_out) using DDR:
    //   - Captures happen on EVERY edge of pll_clk
    //   - So we place new data BEFORE each edge (setup time = 0.2ns)
    //   - 32 bits × 1 edge each = 32 half-periods = 16 pll_clk cycles
    // =========================================================================
    task automatic send_valid_frame(input logic [31:0] valid_word);
        integer b;
        begin
            ser_valid_en = 1'b1;
            for (b = 0; b < 32; b++) begin
                // Place bit before the next edge (setup of 0.2ns before the edge)
                #(PLL_HALF - 0.2);
                SER_out = valid_word[b];  // LSB first
                // Small hold then align to next edge
                #0.2;
                // Now the edge fires and DUT captures - we loop to next bit
            end
            // After last bit, hold for one more half-period then de-assert
            #(PLL_HALF);
            ser_valid_en = 1'b0;
            SER_out      = 1'b0;
        end
    endtask

    // =========================================================================
    // Task: send_data_frame
    // -------------------------------------------------------------------------
    // Sends a 32-bit word serially to ALL 16 data lanes simultaneously.
    // Each lane can have a different word (data_words[0..15]).
    // Same DDR timing as send_valid_frame.
    // =========================================================================
    task automatic send_data_frame(input logic [31:0] data_words [0:15]);
        integer b, lane;
        begin
            ser_data_en = 1'b1;
            for (b = 0; b < 32; b++) begin
                #(PLL_HALF - 0.2);
                for (lane = 0; lane < 16; lane++)
                    ser_data_in[lane] = data_words[lane][b];  // LSB first
                #0.2;
            end
            #(PLL_HALF);
            ser_data_en  = 1'b0;
            ser_data_in  = 16'd0;
        end
    endtask

    // =========================================================================
    // Task: send_full_frame
    // -------------------------------------------------------------------------
    // Sends valid word and all 16 data lanes simultaneously (they share pll_clk)
    // =========================================================================
    task automatic send_full_frame(
        input logic [31:0] valid_word,
        input logic [31:0] data_words [0:15]
    );
        integer b, lane;
        begin
            ser_valid_en = 1'b1;
            ser_data_en  = 1'b1;
            for (b = 0; b < 32; b++) begin
                #(PLL_HALF - 0.2);
                SER_out = valid_word[b];
                for (lane = 0; lane < 16; lane++)
                    ser_data_in[lane] = data_words[lane][b];
                #0.2;
            end
            #(PLL_HALF);
            ser_valid_en = 1'b0;
            ser_data_en  = 1'b0;
            SER_out      = 1'b0;
            ser_data_in  = 16'd0;
        end
    endtask

    // =========================================================================
    // Task: send_clk_repair_pattern
    // -------------------------------------------------------------------------
    // UCIe Spec: 128 iterations of (16 toggle cycles + 8 zero cycles)
    //   - Toggle = clk alternates between 0 and 1 every MB_clk cycle
    //   - Zero   = clk stays 0
    // The pattern is NOT scrambled.
    // Applied to clk_p, clk_n (complementary), and track.
    // =========================================================================
    task automatic send_clk_repair_pattern();
        integer iter, cycle;
        begin
            $display("[%0t] CLK Detector: Sending 128 iterations of clock repair pattern", $time);
            for (iter = 0; iter < 128; iter++) begin
                // 16 toggle cycles (each cycle = 1 MB_clk period)
                for (cycle = 0; cycle < 16; cycle++) begin
                    @(posedge MB_clk);
                    clk_p =  cycle[0]; // alternates 0,1,0,1...
                    clk_n = ~cycle[0]; // complementary
                    track =  cycle[0];
                end
                // 8 zero cycles
                for (cycle = 0; cycle < 8; cycle++) begin
                    @(posedge MB_clk);
                    clk_p = 1'b0;
                    clk_n = 1'b1; // clk_n stays high when clk_p = 0
                    track = 1'b0;
                end
            end
            $display("[%0t] CLK Detector: Pattern sent.", $time);
        end
    endtask

    // =========================================================================
    // Helper: wait for de_ser_done (valid lane CDC complete)
    // =========================================================================
    task automatic wait_for_valid_done(input integer timeout_cycles);
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i++) begin
                @(posedge MB_clk);
                if (de_ser_done) begin
                    $display("[%0t] de_ser_done asserted (valid lane data ready in MB_clk domain)", $time);
                    return;
                end
            end
            $display("[%0t] WARNING: Timeout waiting for de_ser_done", $time);
        end
    endtask

    // =========================================================================
    // Helper: wait for data de_ser_done (lane 0 as reference)
    // =========================================================================
    task automatic wait_for_data_done(input integer timeout_cycles);
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i++) begin
                @(posedge MB_clk);
                if (de_ser_done_data_0) begin
                    $display("[%0t] de_ser_done_data_0 asserted (data lanes ready in MB_clk domain)", $time);
                    return;
                end
            end
            $display("[%0t] WARNING: Timeout waiting for de_ser_done_data_0", $time);
        end
    endtask

    // =========================================================================
    // Default (safe) signal values
    // =========================================================================
    task automatic apply_defaults();
        begin
            ser_valid_en                 = 1'b0;
            SER_out                      = 1'b0;
            ser_data_en                  = 1'b0;
            ser_data_in                  = 16'd0;
            clk_detector_en              = 1'b0;
            clk_p                        = 1'b0;
            clk_n                        = 1'b1;
            track                        = 1'b0;
            i_state                      = 3'b000; // IDLE
            i_width_deg_lfsr             = 3'b011; // x16 (all 16 lanes)
            i_active_state_entered       = 1'b0;
            i_descramble_en              = 1'b0;
            i_enable_buffer              = 1'b1;
            i_max_error_threshold_valid  = 12'd10;
            i_enable_cons                = 1'b1;
            i_enable_128                 = 1'b0;
            i_enable_detector            = 1'b0;
            i_type_of_com                = 2'b00;
            i_max_error_threshold_per_lane_ID  = 16'd50;
            i_max_error_threshold_aggergate    = 16'd800;
            i_width_deg_comp             = 3'b011; // x16
            demapper_en                  = 1'b0;
            rx_data_valid                = 1'b0;
            i_width_deg_demap            = 3'b011; // x16
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        apply_defaults();

        // Reset
        i_rst_n = 1'b0;
        repeat (10) @(posedge MB_clk);
        i_rst_n = 1'b1;
        repeat (5) @(posedge MB_clk);

        $display("==========================================================");
        $display("[%0t] SIMULATION START", $time);
        $display("==========================================================");

        // ==================================================================
        // TEST 1: CLK Repair Pattern Detection
        // ------------------------------------------------------------------
        // Send 128 iterations of (16-toggle + 8-zero) on clk_p/clk_n/track.
        // Detection succeeds if at least 16 consecutive valid patterns seen.
        // ==================================================================
        $display("\n--- TEST 1: CLK Repair Pattern Detection ---");
        @(posedge MB_clk);
        clk_detector_en = 1'b1;
        send_clk_repair_pattern();

        // Give a few MB_clk cycles for detector to latch result
        repeat (5) @(posedge MB_clk);
        $display("[%0t] CLK Results → clk_p_pass=%b  clk_n_pass=%b  track_pass=%b",
                  $time, clk_p_pattern_pass, clk_n_pattern_pass, track_pattern_pass);
        if (clk_p_pattern_pass && clk_n_pattern_pass && track_pattern_pass) begin
            $display("[%0t] TEST 1 PASSED: All clock patterns detected successfully.", $time);
        end else begin
            $display("[%0t] TEST 1 FAILED: Clock pattern detection failed.", $time);
            $fatal("Test 1 Failed");
        end
        clk_detector_en = 1'b0;

        // ==================================================================
        // TEST 2: Valid Pattern Reception (CONSEC_16 mode)
        // ------------------------------------------------------------------
        // Send valid pattern = 11110000 × 4 = 32'hF0F0F0F0 on SER_out
        // for 16 consecutive times so VALID_DETECTOR can confirm detection.
        // ==================================================================
        $display("\n--- TEST 2: Valid Pattern Reception (CONSEC_16 mode) ---");
        i_enable_detector = 1'b1;
        i_enable_cons     = 1'b1;
        i_enable_128      = 1'b0;

        repeat (20) begin
            // Align to beginning of a pll_clk cycle
            @(posedge pll_clk);
            // Send 32-bit valid pattern (11110000 × 4 times = 32'hF0F0F0F0) serially
            send_valid_frame(32'hF0F0F0F0);
            // Wait for CDC to MB_clk domain (3 MB_clk cycles for sync chain)
            wait_for_valid_done(8);
            repeat (2) @(posedge MB_clk);
        end

        repeat (5) @(posedge MB_clk);
        $display("[%0t] Valid Detector → detection_result=%b  o_valid_frame_detect=%b",
                  $time, detection_result, o_valid_frame_detect);
        if (detection_result && !o_valid_frame_detect) begin
            $display("[%0t] TEST 2 PASSED: Valid pattern detected.", $time);
        end else begin
            $display("[%0t] TEST 2 FAILED: Valid pattern detection failed.", $time);
            $fatal("Test 2 Failed");
        end
        i_enable_detector = 1'b0;

        // ==================================================================
        // TEST 3: Training Mode — PATTERN_LFSR
        // ------------------------------------------------------------------
        // i_state = 3'b010 → LFSR_RX enters PATTERN_LFSR
        // LFSR generates reference words → Pattern Comparator compares
        // Data in: send known data frames, comparator checks vs LFSR output
        // We send 135 frames to allow the comparator to complete its 128 cycles.
        // ==================================================================
        $display("\n--- TEST 3: PATTERN_LFSR - Mismatching Scenario (Expect Errors) ---");
        begin
            logic [31:0] tx_data [0:15];
            integer lane;
            integer frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // First: clear LFSR seeds
            i_state = 3'b001; // CLEAR_LFSR
            @(posedge MB_clk);
            @(posedge MB_clk);

            // Now enter PATTERN_LFSR
            i_state                = 3'b010; // PATTERN_LFSR
            i_active_state_entered = 1'b0;   // Not active → goes to comparator
            i_enable_buffer        = 1'b1;

            @(posedge MB_clk);
            @(posedge pll_clk);

            fork
                begin
                    // Send 135 frames back-to-back (64ns spacing)
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        // Simple incrementing data per lane (mismatches the LFSR seeds)
                        for (lane = 0; lane < 16; lane++) tx_data[lane] = lane * 32'h01010101 + frame_idx;
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);
            $display("[%0t] PATTERN_LFSR → per_lane_err=%h, err_cnt=%0d, o_error_done=%b",
                      $time, captured_per_lane_error, captured_error_counter, captured_error_done);
            
            if (captured_error_done && captured_error_counter > 0) begin
                $display("[%0t] TEST 3 PASSED: LFSR training comparison completed with expected errors.", $time);
            end else begin
                $display("[%0t] TEST 3 FAILED: LFSR comparison did not complete or had no errors.", $time);
                $fatal("Test 3 Failed");
            end

            // Return to IDLE
            i_state = 3'b000;
            @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 4: Training Mode — PER_LANE_IDE
        // ------------------------------------------------------------------
        // i_state = 3'b011 → LFSR_RX drives Lane-ID tokens as reference
        // Pattern: 1010_<lane_index_8bit>_1010 for each lane (repeated twice to fill 32 bits)
        // ==================================================================
        $display("\n--- TEST 4: LFSR Training Mode - PER_LANE_IDE ---");
        begin
            logic [31:0] tx_data [0:15];
            integer lane;
            integer frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Correct Lane-ID tokens matching {LANE_ID, LANE_ID}
            for (lane = 0; lane < 16; lane++)
                tx_data[lane] = { {4'hA, lane[7:0], 4'hA}, {4'hA, lane[7:0], 4'hA} };

            i_state                = 3'b011; // PER_LANE_IDE
            i_active_state_entered = 1'b0;

            fork
                begin
                    repeat (135) begin
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);
            $display("[%0t] PER_LANE_IDE → per_lane_err=%h, err_cnt=%0d, o_error_done=%b", 
                      $time, captured_per_lane_error, captured_error_counter, captured_error_done);
            
            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 4 PASSED: Lane-ID matched reference with 0 errors.", $time);
            end else begin
                $display("[%0t] TEST 4 FAILED: Lane-ID comparison failed or had errors.", $time);
                $fatal("Test 4 Failed");
            end

            // Return to IDLE
            i_state = 3'b000;
            @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 5: Active (Data Transfer) Mode
        // ------------------------------------------------------------------
        // i_active_state_entered = 1 → LFSR_RX enters DATA_TRANSFER
        // Pattern Comparator BYPASSES all 16 lanes → data goes to Demapper
// Demapper (x16 mode) assembles one 512-bit flit in 1 MB_clk cycle
        // ==================================================================
        $display("\n--- TEST 5: Active Mode - DATA_TRANSFER + Demapper ---");
        begin
            logic [31:0] tx_data [0:15];
            integer lane;

            // Unique recognizable data per lane
            tx_data[0]  = 32'hDEAD_0001;
            tx_data[1]  = 32'hBEEF_0002;
            tx_data[2]  = 32'hCAFE_0003;
            tx_data[3]  = 32'hFACE_0004;
            tx_data[4]  = 32'hABCD_0005;
            tx_data[5]  = 32'h1234_0006;
            tx_data[6]  = 32'h5678_0007;
            tx_data[7]  = 32'h9ABC_0008;
            tx_data[8]  = 32'hDEF0_0009;
            tx_data[9]  = 32'h1111_000A;
            tx_data[10] = 32'h2222_000B;
            tx_data[11] = 32'h3333_000C;
            tx_data[12] = 32'h4444_000D;
            tx_data[13] = 32'h5555_000E;
            tx_data[14] = 32'h6666_000F;
            tx_data[15] = 32'h7777_0010;

            // Enter Active State
            i_state                = 3'b100; // DATA_TRANSFER
            i_active_state_entered = 1'b1;   // Bypass comparator!
            i_enable_buffer        = 1'b1;
            i_descramble_en        = 1'b0;

            // Enable demapper BEFORE sending (it samples when rx_data_valid)
            demapper_en       = 1'b1;
            i_width_deg_demap = 3'b011; // x16 → 1 cycle to fill 512 bits

            $display("[%0t] Sending Active Mode frame (bypass comparator → demapper)...", $time);
            fork
                // Thread 1: send the frame
                begin
                    @(posedge pll_clk);
                    send_full_frame(32'hF0F0F0F0, tx_data);
                end
                // Thread 2: assert rx_data_valid when data lanes are ready
                begin
                    wait_for_data_done(20);
                    // data is now in MB_clk domain, tell Demapper it's valid
                    @(posedge MB_clk);
                    rx_data_valid = 1'b1;
                    @(posedge MB_clk);
                    rx_data_valid = 1'b0;
                end
            join

            // Wait for Demapper output
            fork
                begin
                    if (pl_valid) @(negedge pl_valid);
                    wait(pl_valid == 1'b1);
                    $display("[%0t] pl_valid asserted! Demapper output ready.", $time);
                    
                    // Verify all lanes
                    begin
                        logic [31:0] reconstructed_lane;
                        logic failed;
                        failed = 0;
                        for (lane = 0; lane < 16; lane++) begin
                            reconstructed_lane = {
                                o_out_data[384 + 8*lane +: 8],
                                o_out_data[256 + 8*lane +: 8],
                                o_out_data[128 + 8*lane +: 8],
                                o_out_data[0   + 8*lane +: 8]
                            };
                            if (reconstructed_lane !== tx_data[lane]) begin
                                $display("ERROR: Lane %0d mismatch! Sent: %h, Recv: %h", lane, tx_data[lane], reconstructed_lane);
                                failed = 1;
                            end
                        end
                        if (!failed) begin
                            $display("[%0t] TEST 5 PASSED: Demapper output verified successfully.", $time);
                        end else begin
                            $display("[%0t] TEST 5 FAILED: Demapper mismatch.", $time);
                            $fatal("Test 5 Failed");
                        end
                    end
                end
                begin
                    repeat (50) @(posedge MB_clk);
                    $display("[%0t] TEST 5 FAILED: Timeout waiting for pl_valid.", $time);
                    $fatal("Test 5 Failed");
                end
            join_any
            disable fork;
        end

        // ==================================================================
        // TEST 5A: Active Mode - x8 Mode (Lanes 0-7, 3'b001)
        // ------------------------------------------------------------------
        // Both Demapper and LFSR width_deg are set to 3'b001.
        // Demapper (x8 mode) assembles 512 bits in 2 cycles.
        // ==================================================================
        $display("\n--- TEST 5A: Active Mode - x8 Mode (Lanes 0-7, 3'b001) ---");
        begin
            logic [31:0] tx_data_1 [0:15];
            logic [31:0] tx_data_2 [0:15];
            integer lane;

            // Initialize frames
            for (lane = 0; lane < 16; lane++) begin
                tx_data_1[lane] = 32'hAAAA_0000 + lane;
                tx_data_2[lane] = 32'hBBBB_0000 + lane;
            end

            // Enter Active State
            i_state                = 3'b100; // DATA_TRANSFER
            i_active_state_entered = 1'b1;   // Bypass comparator
            i_enable_buffer        = 1'b1;
            i_descramble_en        = 1'b0;

            demapper_en       = 1'b1;
            i_width_deg_demap = 3'b001; // x8 (Lanes 0-7)
            i_width_deg_lfsr  = 3'b001; // x8 (Lanes 0-7)
            i_width_deg_comp  = 3'b001; // x8 (Lanes 0-7)

            $display("[%0t] Sending x8 Mode frames...", $time);
            fork
                // Thread 1: send 2 frames
                begin
                    @(posedge pll_clk);
                    send_full_frame(32'hF0F0F0F0, tx_data_1);
                    wait_for_data_done(20);
                    @(posedge MB_clk);
                    rx_data_valid = 1'b1;
                    @(posedge MB_clk);
                    rx_data_valid = 1'b0;

                    repeat (2) @(posedge MB_clk);

                    @(posedge pll_clk);
                    send_full_frame(32'hF0F0F0F0, tx_data_2);
                    wait_for_data_done(20);
                    @(posedge MB_clk);
                    rx_data_valid = 1'b1;
                    @(posedge MB_clk);
                    rx_data_valid = 1'b0;
                end
                // Thread 2: monitor demapper output
                begin
                    if (pl_valid) @(negedge pl_valid);
                    wait(pl_valid == 1'b1);
                    $display("[%0t] pl_valid asserted for x8 mode!", $time);
                    
                    // Verify lanes 0 to 7
                    begin
                        logic [31:0] recon_1, recon_2;
                        logic failed;
                        failed = 0;
                        for (lane = 0; lane < 8; lane++) begin
                            recon_1 = {
                                o_out_data[192 + 8*lane +: 8],
                                o_out_data[128 + 8*lane +: 8],
                                o_out_data[64  + 8*lane +: 8],
                                o_out_data[0   + 8*lane +: 8]
                            };
                            recon_2 = {
                                o_out_data[256 + 192 + 8*lane +: 8],
                                o_out_data[256 + 128 + 8*lane +: 8],
                                o_out_data[256 + 64  + 8*lane +: 8],
                                o_out_data[256 + 0   + 8*lane +: 8]
                            };
                            if (recon_1 !== tx_data_1[lane]) begin
                                $display("ERROR: x8 Lane %0d Frame 1 mismatch! Sent: %h, Recv: %h", lane, tx_data_1[lane], recon_1);
                                failed = 1;
                            end
                            if (recon_2 !== tx_data_2[lane]) begin
                                $display("ERROR: x8 Lane %0d Frame 2 mismatch! Sent: %h, Recv: %h", lane, tx_data_2[lane], recon_2);
                                failed = 1;
                            end
                        end
                        if (!failed) begin
                            $display("[%0t] TEST 5A PASSED: Demapper x8 output verified successfully.", $time);
                        end else begin
                            $display("[%0t] TEST 5A FAILED: Demapper x8 mismatch.", $time);
                            $fatal("Test 5A Failed");
                        end
                    end
                end
                // Thread 3: timeout
                begin
                    repeat (100) @(posedge MB_clk);
                    $display("[%0t] TEST 5A FAILED: Timeout waiting for pl_valid.", $time);
                    $fatal("Test 5A Failed");
                end
            join_any
            disable fork;
            demapper_en = 1'b0;
            apply_defaults();
            repeat (5) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 5B: Active Mode - x4 Mode (Lanes 0-3, 3'b100)
        // ------------------------------------------------------------------
        // Both Demapper and LFSR width_deg are set to 3'b100.
        // Demapper (x4 mode) assembles 512 bits in 4 cycles.
        // ==================================================================
        $display("\n--- TEST 5B: Active Mode - x4 Mode (Lanes 0-3, 3'b100) ---");
        begin
            logic [31:0] tx_data [0:3][0:15];
            integer lane, frame_idx;

            // Initialize 4 frames
            for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                for (lane = 0; lane < 16; lane++) begin
                    tx_data[frame_idx][lane] = ((frame_idx + 1) * 32'h1111_0000) + lane;
                end
            end

            // Enter Active State
            i_state                = 3'b100; // DATA_TRANSFER
            i_active_state_entered = 1'b1;   // Bypass comparator
            i_enable_buffer        = 1'b1;
            i_descramble_en        = 1'b0;

            demapper_en       = 1'b1;
            i_width_deg_demap = 3'b100; // x4 (Lanes 0-3)
            i_width_deg_lfsr  = 3'b100; // x4 (Lanes 0-3)
            i_width_deg_comp  = 3'b100; // x4 (Lanes 0-3)

            $display("[%0t] Sending x4 Mode frames...", $time);
            fork
                // Thread 1: send 4 frames
                begin
                    for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data[frame_idx]);
                        wait_for_data_done(20);
                        @(posedge MB_clk);
                        rx_data_valid = 1'b1;
                        @(posedge MB_clk);
                        rx_data_valid = 1'b0;
                        repeat (2) @(posedge MB_clk);
                    end
                end
                // Thread 2: monitor demapper output
                begin
                    if (pl_valid) @(negedge pl_valid);
                    wait(pl_valid == 1'b1);
                    $display("[%0t] pl_valid asserted for x4 mode!", $time);
                    
                    // Verify lanes 0 to 3 across all 4 frames
                    begin
                        logic [31:0] recon;
                        logic failed;
                        failed = 0;
                        for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                            for (lane = 0; lane < 4; lane++) begin
                                recon = {
                                    o_out_data[frame_idx*128 + 96 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 64 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 32 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 0  + 8*lane +: 8]
                                };
                                if (recon !== tx_data[frame_idx][lane]) begin
                                    $display("ERROR: x4 Lane %0d Frame %0d mismatch! Sent: %h, Recv: %h", lane, frame_idx, tx_data[frame_idx][lane], recon);
                                    failed = 1;
                                end
                            end
                        end
                        if (!failed) begin
                            $display("[%0t] TEST 5B PASSED: Demapper x4 output verified successfully.", $time);
                        end else begin
                            $display("[%0t] TEST 5B FAILED: Demapper x4 mismatch.", $time);
                            $fatal("Test 5B Failed");
                        end
                    end
                end
                // Thread 3: timeout
                begin
                    repeat (200) @(posedge MB_clk);
                    $display("[%0t] TEST 5B FAILED: Timeout waiting for pl_valid.", $time);
                    $fatal("Test 5B Failed");
                end
            join_any
            disable fork;
            demapper_en = 1'b0;
            apply_defaults();
            repeat (5) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 6: PATTERN_LFSR with MATCHING TX data → Comparator = 0 errors
        // ------------------------------------------------------------------
        // We compute the EXACT pattern the LFSR_RX generates locally using
        // tb_next_lfsr_state() (same polynomial as RTL) and send it as TX.
        // o_Data_by == o_final_gene → Pattern Comparator must report 0 errors.
        //
        // Seed values from LFSR_RX.sv (x16 mode: lanes 8-15 reuse seeds 0-7)
        // ==================================================================
        $display("\n--- TEST 6: PATTERN_LFSR - Matching Scenario (Expect 0 Errors) ---");
        begin
            logic [22:0] seeds [0:7];
            logic [22:0] cur_state [0:7];
            logic [31:0] raw   [0:7];
            logic [31:0] tx_data [0:15];
            integer      lane, frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Fixed seeds (must match LFSR_RX.sv)
            seeds[0] = 23'h1DBFBC;  seeds[1] = 23'h0607BB;
            seeds[2] = 23'h1EC760;  seeds[3] = 23'h18C0DB;
            seeds[4] = 23'h010F12;  seeds[5] = 23'h19CFC9;
            seeds[6] = 23'h0277CE;  seeds[7] = 23'h1BB807;

            for (lane = 0; lane < 8; lane++) begin
                cur_state[lane] = seeds[lane];
            end

            // Return FSM to IDLE first so it can register the state change to CLEAR_LFSR
            i_active_state_entered = 1'b0;
            i_state = 3'b000; // IDLE
            @(posedge MB_clk);

            // Now enter CLEAR_LFSR (clear seeds)
            i_state = 3'b001; // CLEAR_LFSR → reloads seeds
            @(posedge MB_clk);
            @(posedge MB_clk);

            // Now transition to PATTERN_LFSR
            i_state = 3'b010; // PATTERN_LFSR
            i_enable_buffer = 1'b1;
            @(posedge MB_clk);

            fork
                begin
                    // Loop 135 times with safe spacing
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        // Compute next LFSR state and output word
                        for (lane = 0; lane < 8; lane++) begin
                            if (frame_idx == 0) begin
                                // For the very first frame, the DUT o_final_gene uses the initial/reset states: SEED and init_lane_23(SEED)
                                tx_data[lane]     = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                tx_data[lane + 8] = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                // Note: do not advance cur_state here, so that frame 1 uses the first next state
                            end else begin
                                raw[lane] = tb_next_lfsr_state(cur_state[lane]);
                                tx_data[lane]     = {raw[lane][22:0], raw[lane][31:23]};
                                tx_data[lane + 8] = {raw[lane][22:0], raw[lane][31:23]};
                                cur_state[lane]   = raw[lane][22:0]; // update state
                            end
                        end

                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    integer print_count;
                    print_count = 0;
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (print_count < 15 && dut.u_LFSR_RX.pattern_comp_en) begin
                            $display("[%0t] MONITOR: i_local_gen_0=%h, i_data_0=%h, de_ser_done=%b, rx_lfsr_lane[0]=%h",
                                     $time, dut.u_MB_Pattern_comparator.i_local_gen_0, dut.u_MB_Pattern_comparator.i_data_0, de_ser_done, dut.u_LFSR_RX.rx_lfsr_lane[0]);
                            print_count++;
                        end
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);

            // Check comparator result
            $display("[%0t] Comparator results after matching TX:", $time);
            $display("  o_error_counter  = %0d  (expect 0)", captured_error_counter);
            $display("  o_per_lane_error = %h  (expect 0000)", captured_per_lane_error);
            $display("  o_error_done     = %b  (expect 1)", captured_error_done);

            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 6 PASSED: Zero errors - TX matched LFSR pattern perfectly.", $time);
            end else begin
                $display("[%0t] TEST 6 FAILED: Errors detected in LFSR matching.", $time);
                $fatal("Test 6 Failed");
            end

            // Return LFSR to IDLE
            i_state = 3'b000;
            repeat (3) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 6A: PATTERN_LFSR - Matching Scenario (x8 Mode - Lanes 0-7, 3'b001)
        // ------------------------------------------------------------------
        // We set i_width_deg_lfsr = 3'b001 → LFSR generates patterns on lanes 0-7.
        // Lanes 8-15 must be 32'h0000_0000 to match local reference o_final_gene.
        // ==================================================================
        $display("\n--- TEST 6A: PATTERN_LFSR - Matching Scenario (x8 Mode - Lanes 0-7, 3'b001) ---");
        begin
            logic [22:0] seeds [0:7];
            logic [22:0] cur_state [0:7];
            logic [31:0] raw   [0:7];
            logic [31:0] tx_data [0:15];
            integer      lane, frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Fixed seeds (must match LFSR_RX.sv)
            seeds[0] = 23'h1DBFBC;  seeds[1] = 23'h0607BB;
            seeds[2] = 23'h1EC760;  seeds[3] = 23'h18C0DB;
            seeds[4] = 23'h010F12;  seeds[5] = 23'h19CFC9;
            seeds[6] = 23'h0277CE;  seeds[7] = 23'h1BB807;

            for (lane = 0; lane < 8; lane++) begin
                cur_state[lane] = seeds[lane];
            end

            // Return FSM to IDLE first so it can register the state change to CLEAR_LFSR
            i_active_state_entered = 1'b0;
            i_state = 3'b000; // IDLE
            @(posedge MB_clk);

            // Now enter CLEAR_LFSR (clear seeds)
            i_state = 3'b001; // CLEAR_LFSR → reloads seeds
            @(posedge MB_clk);
            @(posedge MB_clk);

            // Now transition to PATTERN_LFSR
            i_state = 3'b010; // PATTERN_LFSR
            i_width_deg_lfsr  = 3'b001; // x8 Mode (Lanes 0-7)
            i_width_deg_demap = 3'b001; // x8 Mode (Lanes 0-7)
            i_width_deg_comp  = 3'b001; // x8 Mode (Lanes 0-7)
            i_enable_buffer = 1'b1;
            @ (posedge MB_clk);

            fork
                begin
                    // Loop 135 times with safe spacing
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        // Compute next LFSR state and output word
                        for (lane = 0; lane < 16; lane++) begin
                            if (lane < 8) begin
                                if (frame_idx == 0) begin
                                    tx_data[lane] = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                end else begin
                                    raw[lane] = tb_next_lfsr_state(cur_state[lane]);
                                    tx_data[lane] = {raw[lane][22:0], raw[lane][31:23]};
                                    cur_state[lane] = raw[lane][22:0]; // update state
                                end
                            end else begin
                                // Inactive lanes are driven to 0 to match reference generator o_final_gene
                                tx_data[lane] = 32'h0000_0000;
                            end
                        end

                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);

            // Check comparator result
            $display("[%0t] Comparator results after x8 matching TX:", $time);
            $display("  o_error_counter  = %0d  (expect 0)", captured_error_counter);
            $display("  o_per_lane_error = %h  (expect 0000)", captured_per_lane_error);
            $display("  o_error_done     = %b  (expect 1)", captured_error_done);

            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 6A PASSED: Zero errors - TX matched LFSR x8 pattern perfectly.", $time);
            end else begin
                $display("[%0t] TEST 6A FAILED: Errors detected in LFSR x8 matching.", $time);
                $fatal("Test 6A Failed");
            end

            // Return LFSR to IDLE
            i_state = 3'b000;
            repeat (3) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 6B: PATTERN_LFSR - Matching Scenario (x4 Mode - Lanes 0-3, 3'b100)
        // ------------------------------------------------------------------
        // We set i_width_deg_lfsr = 3'b100 → LFSR generates patterns on lanes 0-3.
        // Lanes 4-15 must be 32'h0000_0000 to match local reference o_final_gene.
        // ==================================================================
        $display("\n--- TEST 6B: PATTERN_LFSR - Matching Scenario (x4 Mode - Lanes 0-3, 3'b100) ---");
        begin
            logic [22:0] seeds [0:7];
            logic [22:0] cur_state [0:7];
            logic [31:0] raw   [0:7];
            logic [31:0] tx_data [0:15];
            integer      lane, frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Fixed seeds (must match LFSR_RX.sv)
            seeds[0] = 23'h1DBFBC;  seeds[1] = 23'h0607BB;
            seeds[2] = 23'h1EC760;  seeds[3] = 23'h18C0DB;
            seeds[4] = 23'h010F12;  seeds[5] = 23'h19CFC9;
            seeds[6] = 23'h0277CE;  seeds[7] = 23'h1BB807;

            for (lane = 0; lane < 8; lane++) begin
                cur_state[lane] = seeds[lane];
            end

            // Return FSM to IDLE first so it can register the state change to CLEAR_LFSR
            i_active_state_entered = 1'b0;
            i_state = 3'b000; // IDLE
            @(posedge MB_clk);

            // Now enter CLEAR_LFSR (clear seeds)
            i_state = 3'b001; // CLEAR_LFSR → reloads seeds
            @(posedge MB_clk);
            @(posedge MB_clk);

            // Now transition to PATTERN_LFSR
            i_state = 3'b010; // PATTERN_LFSR
            i_width_deg_lfsr  = 3'b100; // x4 Mode (Lanes 0-3)
            i_width_deg_demap = 3'b100; // x4 Mode (Lanes 0-3)
            i_width_deg_comp  = 3'b100; // x4 Mode (Lanes 0-3)
            i_enable_buffer = 1'b1;
            @ (posedge MB_clk);

            fork
                begin
                    // Loop 135 times with safe spacing
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        // Compute next LFSR state and output word
                        for (lane = 0; lane < 16; lane++) begin
                            if (lane < 4) begin
                                if (frame_idx == 0) begin
                                    tx_data[lane] = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                end else begin
                                    raw[lane] = tb_next_lfsr_state(cur_state[lane]);
                                    tx_data[lane] = {raw[lane][22:0], raw[lane][31:23]};
                                    cur_state[lane] = raw[lane][22:0]; // update state
                                end
                            end else begin
                                // Inactive lanes are driven to 0 to match reference generator o_final_gene
                                tx_data[lane] = 32'h0000_0000;
                            end
                        end

                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);

            // Check comparator result
            $display("[%0t] Comparator results after x4 matching TX:", $time);
            $display("  o_error_counter  = %0d  (expect 0)", captured_error_counter);
            $display("  o_per_lane_error = %h  (expect 0000)", captured_per_lane_error);
            $display("  o_error_done     = %b  (expect 1)", captured_error_done);

            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 6B PASSED: Zero errors - TX matched LFSR x4 pattern perfectly.", $time);
            end else begin
                $display("[%0t] TEST 6B FAILED: Errors detected in LFSR x4 matching.", $time);
                $fatal("Test 6B Failed");
            end

            // Return LFSR to IDLE
            i_state = 3'b000;
            repeat (3) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 7A: Active Mode - Width Degradation x8 (All 3 signals = 3'b001)
        // ------------------------------------------------------------------
        // Verify that data flows through LFSR_RX → (bypass) PATTERN_COMPARATOR
        // → Demapper correctly when ALL width_deg signals are set to x8.
        // ==================================================================
        $display("\n--- TEST 7A: Active Mode - Full Width Deg x8 (3'b001) ---");
        begin
            logic [31:0] tx_data_1 [0:15];
            logic [31:0] tx_data_2 [0:15];
            integer lane;

            // Initialize frames: unique data per lane
            for (lane = 0; lane < 8; lane++) begin
                tx_data_1[lane] = 32'hCC00_0000 + lane;
                tx_data_2[lane] = 32'hDD00_0000 + lane;
            end
            for (lane = 8; lane < 16; lane++) begin
                tx_data_1[lane] = 32'h0000_0000; // inactive lanes = 0
                tx_data_2[lane] = 32'h0000_0000;
            end

            // Enter Active State with x8 degradation on ALL blocks
            i_state                = 3'b100; // DATA_TRANSFER
            i_active_state_entered = 1'b1;   // Bypass comparator
            i_enable_buffer        = 1'b1;
            i_descramble_en        = 1'b0;

            demapper_en       = 1'b1;
            i_width_deg_demap = 3'b001; // x8 (Lanes 0-7)
            i_width_deg_lfsr  = 3'b001; // x8 (Lanes 0-7)
            i_width_deg_comp  = 3'b001; // x8 (Lanes 0-7)

            $display("[%0t] Sending Active x8 frames (all width_deg = 3'b001)...", $time);
            fork
                // Thread 1: send 2 frames (x8 needs 2 cycles for 512 bits)
                begin
                    @(posedge pll_clk);
                    send_full_frame(32'hF0F0F0F0, tx_data_1);
                    wait_for_data_done(20);
                    @(posedge MB_clk);
                    rx_data_valid = 1'b1;
                    @(posedge MB_clk);
                    rx_data_valid = 1'b0;

                    repeat (2) @(posedge MB_clk);

                    @(posedge pll_clk);
                    send_full_frame(32'hF0F0F0F0, tx_data_2);
                    wait_for_data_done(20);
                    @(posedge MB_clk);
                    rx_data_valid = 1'b1;
                    @(posedge MB_clk);
                    rx_data_valid = 1'b0;
                end
                // Thread 2: monitor demapper output
                begin
                    if (pl_valid) @(negedge pl_valid);
                    wait(pl_valid == 1'b1);
                    $display("[%0t] pl_valid asserted for Test 7A!", $time);
                    
                    begin
                        logic [31:0] recon_1, recon_2;
                        logic failed;
                        failed = 0;
                        for (lane = 0; lane < 8; lane++) begin
                            recon_1 = {
                                o_out_data[192 + 8*lane +: 8],
                                o_out_data[128 + 8*lane +: 8],
                                o_out_data[64  + 8*lane +: 8],
                                o_out_data[0   + 8*lane +: 8]
                            };
                            recon_2 = {
                                o_out_data[256 + 192 + 8*lane +: 8],
                                o_out_data[256 + 128 + 8*lane +: 8],
                                o_out_data[256 + 64  + 8*lane +: 8],
                                o_out_data[256 + 0   + 8*lane +: 8]
                            };
                            if (recon_1 !== tx_data_1[lane]) begin
                                $display("ERROR: T7A x8 Lane %0d Frame 1 mismatch! Sent: %h, Recv: %h", lane, tx_data_1[lane], recon_1);
                                failed = 1;
                            end
                            if (recon_2 !== tx_data_2[lane]) begin
                                $display("ERROR: T7A x8 Lane %0d Frame 2 mismatch! Sent: %h, Recv: %h", lane, tx_data_2[lane], recon_2);
                                failed = 1;
                            end
                        end
                        if (!failed) begin
                            $display("[%0t] TEST 7A PASSED: Active x8 mode verified.", $time);
                        end else begin
                            $display("[%0t] TEST 7A FAILED: Active x8 mismatch.", $time);
                            $fatal("Test 7A Failed");
                        end
                    end
                end
                // Thread 3: timeout
                begin
                    repeat (100) @(posedge MB_clk);
                    $display("[%0t] TEST 7A FAILED: Timeout.", $time);
                    $fatal("Test 7A Failed");
                end
            join_any
            disable fork;
            demapper_en = 1'b0;
            apply_defaults();
            repeat (5) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 7B: Active Mode - Width Degradation x4 (All 3 signals = 3'b100)
        // ==================================================================
        $display("\n--- TEST 7B: Active Mode - Full Width Deg x4 (3'b100) ---");
        begin
            logic [31:0] tx_data [0:3][0:15];
            integer lane, frame_idx;

            // Initialize 4 frames (x4 needs 4 cycles for 512 bits)
            for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                for (lane = 0; lane < 4; lane++) begin
                    tx_data[frame_idx][lane] = 32'hEE00_0000 + (frame_idx << 8) + lane;
                end
                for (lane = 4; lane < 16; lane++) begin
                    tx_data[frame_idx][lane] = 32'h0000_0000; // inactive
                end
            end

            // Enter Active State with x4 degradation on ALL blocks
            i_state                = 3'b100;
            i_active_state_entered = 1'b1;
            i_enable_buffer        = 1'b1;
            i_descramble_en        = 1'b0;

            demapper_en       = 1'b1;
            i_width_deg_demap = 3'b100; // x4 (Lanes 0-3)
            i_width_deg_lfsr  = 3'b100; // x4 (Lanes 0-3)
            i_width_deg_comp  = 3'b100; // x4 (Lanes 0-3)

            $display("[%0t] Sending Active x4 frames (all width_deg = 3'b100)...", $time);
            fork
                // Thread 1: send 4 frames
                begin
                    for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data[frame_idx]);
                        wait_for_data_done(20);
                        @(posedge MB_clk);
                        rx_data_valid = 1'b1;
                        @(posedge MB_clk);
                        rx_data_valid = 1'b0;
                        repeat (2) @(posedge MB_clk);
                    end
                end
                // Thread 2: monitor demapper output
                begin
                    if (pl_valid) @(negedge pl_valid);
                    wait(pl_valid == 1'b1);
                    $display("[%0t] pl_valid asserted for Test 7B!", $time);
                    
                    begin
                        logic [31:0] recon;
                        logic failed;
                        failed = 0;
                        for (frame_idx = 0; frame_idx < 4; frame_idx++) begin
                            for (lane = 0; lane < 4; lane++) begin
                                recon = {
                                    o_out_data[frame_idx*128 + 96 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 64 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 32 + 8*lane +: 8],
                                    o_out_data[frame_idx*128 + 0  + 8*lane +: 8]
                                };
                                if (recon !== tx_data[frame_idx][lane]) begin
                                    $display("ERROR: T7B x4 Lane %0d Frame %0d mismatch! Sent: %h, Recv: %h", lane, frame_idx, tx_data[frame_idx][lane], recon);
                                    failed = 1;
                                end
                            end
                        end
                        if (!failed) begin
                            $display("[%0t] TEST 7B PASSED: Active x4 mode verified.", $time);
                        end else begin
                            $display("[%0t] TEST 7B FAILED: Active x4 mismatch.", $time);
                            $fatal("Test 7B Failed");
                        end
                    end
                end
                // Thread 3: timeout
                begin
                    repeat (200) @(posedge MB_clk);
                    $display("[%0t] TEST 7B FAILED: Timeout.", $time);
                    $fatal("Test 7B Failed");
                end
            join_any
            disable fork;
            demapper_en = 1'b0;
            apply_defaults();
            repeat (5) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 8A: Training LFSR Matching x8 (All 3 width_deg = 3'b001)
        // ------------------------------------------------------------------
        // Verify that PATTERN_COMPARATOR correctly ignores inactive lanes 8-15
        // and reports 0 errors when active lanes 0-7 match the LFSR reference.
        // ==================================================================
        $display("\n--- TEST 8A: Training LFSR - Full Width Deg x8 Matching (3'b001) ---");
        begin
            logic [22:0] seeds [0:7];
            logic [22:0] cur_state [0:7];
            logic [31:0] raw   [0:7];
            logic [31:0] tx_data [0:15];
            integer      lane, frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Fixed seeds
            seeds[0] = 23'h1DBFBC;  seeds[1] = 23'h0607BB;
            seeds[2] = 23'h1EC760;  seeds[3] = 23'h18C0DB;
            seeds[4] = 23'h010F12;  seeds[5] = 23'h19CFC9;
            seeds[6] = 23'h0277CE;  seeds[7] = 23'h1BB807;

            for (lane = 0; lane < 8; lane++)
                cur_state[lane] = seeds[lane];

            // IDLE → CLEAR_LFSR → PATTERN_LFSR
            i_active_state_entered = 1'b0;
            i_state = 3'b000; // IDLE
            @(posedge MB_clk);

            i_state = 3'b001; // CLEAR_LFSR
            @(posedge MB_clk);
            @(posedge MB_clk);

            i_state = 3'b010; // PATTERN_LFSR
            i_width_deg_lfsr  = 3'b001; // x8
            i_width_deg_demap = 3'b001; // x8
            i_width_deg_comp  = 3'b001; // x8 — comparator only checks lanes 0-7
            i_enable_buffer = 1'b1;
            @(posedge MB_clk);

            fork
                begin
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        for (lane = 0; lane < 16; lane++) begin
                            if (lane < 8) begin
                                if (frame_idx == 0) begin
                                    tx_data[lane] = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                end else begin
                                    raw[lane] = tb_next_lfsr_state(cur_state[lane]);
                                    tx_data[lane] = {raw[lane][22:0], raw[lane][31:23]};
                                    cur_state[lane] = raw[lane][22:0];
                                end
                            end else begin
                                tx_data[lane] = 32'h0000_0000;
                            end
                        end
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);

            $display("[%0t] T8A → err_cnt=%0d, per_lane=%h, done=%b", $time, captured_error_counter, captured_per_lane_error, captured_error_done);

            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 8A PASSED: Training LFSR x8 with width_deg_comp — 0 errors.", $time);
            end else begin
                $display("[%0t] TEST 8A FAILED: Errors in training LFSR x8.", $time);
                $fatal("Test 8A Failed");
            end

            i_state = 3'b000;
            repeat (3) @(posedge MB_clk);
        end

        // ==================================================================
        // TEST 8B: Training LFSR Matching x4 (All 3 width_deg = 3'b100)
        // ------------------------------------------------------------------
        // Verify that PATTERN_COMPARATOR correctly ignores inactive lanes 4-15
        // and reports 0 errors when active lanes 0-3 match the LFSR reference.
        // ==================================================================
        $display("\n--- TEST 8B: Training LFSR - Full Width Deg x4 Matching (3'b100) ---");
        begin
            logic [22:0] seeds [0:7];
            logic [22:0] cur_state [0:7];
            logic [31:0] raw   [0:7];
            logic [31:0] tx_data [0:15];
            integer      lane, frame_idx;
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;

            captured_error_done = 0;
            captured_error_counter = 0;
            captured_per_lane_error = 0;

            // Fixed seeds
            seeds[0] = 23'h1DBFBC;  seeds[1] = 23'h0607BB;
            seeds[2] = 23'h1EC760;  seeds[3] = 23'h18C0DB;
            seeds[4] = 23'h010F12;  seeds[5] = 23'h19CFC9;
            seeds[6] = 23'h0277CE;  seeds[7] = 23'h1BB807;

            for (lane = 0; lane < 8; lane++)
                cur_state[lane] = seeds[lane];

            // IDLE → CLEAR_LFSR → PATTERN_LFSR
            i_active_state_entered = 1'b0;
            i_state = 3'b000; // IDLE
            @(posedge MB_clk);

            i_state = 3'b001; // CLEAR_LFSR
            @(posedge MB_clk);
            @(posedge MB_clk);

            i_state = 3'b010; // PATTERN_LFSR
            i_width_deg_lfsr  = 3'b100; // x4
            i_width_deg_demap = 3'b100; // x4
            i_width_deg_comp  = 3'b100; // x4 — comparator only checks lanes 0-3
            i_enable_buffer = 1'b1;
            @(posedge MB_clk);

            fork
                begin
                    for (frame_idx = 0; frame_idx < 135; frame_idx++) begin
                        for (lane = 0; lane < 16; lane++) begin
                            if (lane < 4) begin
                                if (frame_idx == 0) begin
                                    tx_data[lane] = {cur_state[lane], tb_init_lane_23(cur_state[lane])};
                                end else begin
                                    raw[lane] = tb_next_lfsr_state(cur_state[lane]);
                                    tx_data[lane] = {raw[lane][22:0], raw[lane][31:23]};
                                    cur_state[lane] = raw[lane][22:0];
                                end
                            end else begin
                                tx_data[lane] = 32'h0000_0000;
                            end
                        end
                        @(posedge pll_clk);
                        send_full_frame(32'hF0F0F0F0, tx_data);
                        wait_for_data_done(8);
                        repeat (2) @(posedge MB_clk);
                    end
                end
                begin
                    while (!captured_error_done) begin
                        @(posedge MB_clk);
                        if (o_error_done) begin
                            captured_error_done    = 1;
                            captured_error_counter  = o_error_counter;
                            captured_per_lane_error = o_per_lane_error;
                        end
                    end
                end
            join_any
            disable fork;
            apply_defaults();

            repeat (5) @(posedge MB_clk);

            $display("[%0t] T8B → err_cnt=%0d, per_lane=%h, done=%b", $time, captured_error_counter, captured_per_lane_error, captured_error_done);

            if (captured_error_done && captured_error_counter == 0 && captured_per_lane_error == 16'h0000) begin
                $display("[%0t] TEST 8B PASSED: Training LFSR x4 with width_deg_comp — 0 errors.", $time);
            end else begin
                $display("[%0t] TEST 8B FAILED: Errors in training LFSR x4.", $time);
                $fatal("Test 8B Failed");
            end

            i_state = 3'b000;
            repeat (3) @(posedge MB_clk);
        end

        // ==================================================================
        // Simulation End
        // ==================================================================
        $display("\n==========================================================");
        $display("[%0t] ALL TESTS COMPLETE - ALL PASSED", $time);
        $display("==========================================================");
        repeat (10) @(posedge MB_clk);
        $finish;
    end

endmodule
