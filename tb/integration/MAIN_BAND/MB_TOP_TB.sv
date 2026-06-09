`timescale 1ps/1ps
// =============================================================================
// Testbench : MB_TOP_TB
// Purpose   : Comprehensive loopback verification of the UCIe 3.0 Main-Band Physical Layer.
//             Wires TX side to RX side via physical serial interfaces.
// =============================================================================

module MB_TOP_TB;

    // =========================================================================
    // Parameters (must match DUT)
    // =========================================================================
    localparam DATA_WIDTH = 32;
    localparam NUM_LANES  = 16;
    localparam N_BYTES    = 64;

    // LFSR state codes
    localparam LFSR_IDLE         = 3'b000;
    localparam LFSR_CLEAR        = 3'b001;
    localparam LFSR_PATTERN      = 3'b010;
    localparam LFSR_PER_LANE_IDE = 3'b011;
    localparam LFSR_DATA         = 3'b100;

    // Width degradation (none degraded)
    localparam WIDTH_DEG_ALL     = 3'b011;

    // =========================================================================
    // Signals
    // =========================================================================
    logic                    i_rst_n;
    logic                    o_pll_clk;
    logic                    o_mb_clk;

    // TX inputs
    logic [8*N_BYTES-1:0]    i_tx_raw_data;
    logic                    i_tx_mapper_en;
    logic [2:0]              i_tx_width_deg;
    logic                    i_tx_lp_irdy;
    logic                    i_tx_lp_valid;
    logic [2:0]              i_tx_lfsr_state;
    logic                    i_tx_reversal_en;
    logic                    i_tx_active_state_entered;
    logic                    i_tx_valid_pattern_en;
    logic                    i_tx_pll_en;
    logic [1:0]              i_tx_pll_speed_sel;
    logic                    i_tx_clk_pattern_en;
    logic                    i_tx_clk_embedded_en;

    // TX outputs
    logic                    o_tx_mapper_ready;
    logic                    o_tx_lfsr_done;
    logic                    o_tx_valid_done;
    logic                    o_tx_clk_done;

    // RX inputs
    logic                    i_rx_clk_detector_en;
    logic [2:0]              i_rx_state;
    logic [2:0]              i_rx_width_deg_lfsr;
    logic                    i_rx_active_state_entered;
    logic                    i_rx_descramble_en;
    logic                    i_rx_enable_buffer;
    logic [11:0]            i_rx_max_error_threshold_valid;
    logic                    i_rx_enable_cons;
    logic                    i_rx_enable_128;
    logic                    i_rx_enable_detector;
    logic [1:0]              i_rx_type_of_com;
    logic [15:0]            i_rx_max_error_threshold_per_lane_ID;
    logic [15:0]            i_rx_max_error_threshold_aggergate;
    logic [2:0]              i_rx_width_deg_comp;
    logic                    i_rx_demapper_en;
    logic                    i_rx_data_valid;
    logic [2:0]              i_rx_width_deg_demap;

    // RX outputs
    logic                    o_rx_de_ser_done;
    logic                    o_rx_detection_result;
    logic                    o_rx_valid_frame_detect;
    logic [15:0]            o_rx_per_lane_error;
    logic [31:0]            o_rx_error_counter;
    logic                    o_rx_error_done;
    logic                    o_rx_clk_p_pattern_pass;
    logic                    o_rx_clk_n_pattern_pass;
    logic                    o_rx_track_pattern_pass;
    logic                    o_rx_pl_valid;
    logic [8*N_BYTES-1:0]   o_rx_out_data;

    // Loopback monitor wires
    logic [NUM_LANES-1:0]    o_loopback_data;
    logic                    o_loopback_valid;
    logic                    o_loopback_clk_p;
    logic                    o_loopback_clk_n;
    logic                    o_loopback_clk_track;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    MB_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) u_MB_TOP (
        .i_rst_n                              (i_rst_n),
        .o_pll_clk                            (o_pll_clk),
        .o_mb_clk                             (o_mb_clk),

        // TX side
        .i_tx_raw_data                        (i_tx_raw_data),
        .i_tx_mapper_en                       (i_tx_mapper_en),
        .i_tx_width_deg                       (i_tx_width_deg),
        .i_tx_lp_irdy                         (i_tx_lp_irdy),
        .i_tx_lp_valid                        (i_tx_lp_valid),
        .i_tx_lfsr_state                      (i_tx_lfsr_state),
        .i_tx_reversal_en                     (i_tx_reversal_en),
        .i_tx_active_state_entered            (i_tx_active_state_entered),
        .i_tx_valid_pattern_en                (i_tx_valid_pattern_en),
        .i_tx_pll_en                          (i_tx_pll_en),
        .i_tx_pll_speed_sel                   (i_tx_pll_speed_sel),
        .i_tx_clk_pattern_en                  (i_tx_clk_pattern_en),
        .i_tx_clk_embedded_en                 (i_tx_clk_embedded_en),
        .o_tx_mapper_ready                    (o_tx_mapper_ready),
        .o_tx_lfsr_done                       (o_tx_lfsr_done),
        .o_tx_valid_done                      (o_tx_valid_done),
        .o_tx_clk_done                        (o_tx_clk_done),

        // RX side
        .i_rx_clk_detector_en                 (i_rx_clk_detector_en),
        .i_rx_state                           (i_rx_state),
        .i_rx_width_deg_lfsr                  (i_rx_width_deg_lfsr),
        .i_rx_active_state_entered            (i_rx_active_state_entered),
        .i_rx_descramble_en                   (i_rx_descramble_en),
        .i_rx_enable_buffer                   (i_rx_enable_buffer),
        .i_rx_max_error_threshold_valid       (i_rx_max_error_threshold_valid),
        .i_rx_enable_cons                     (i_rx_enable_cons),
        .i_rx_enable_128                      (i_rx_enable_128),
        .i_rx_enable_detector                 (i_rx_enable_detector),
        .i_rx_type_of_com                     (i_rx_type_of_com),
        .i_rx_max_error_threshold_per_lane_ID (i_rx_max_error_threshold_per_lane_ID),
        .i_rx_max_error_threshold_aggergate    (i_rx_max_error_threshold_aggergate),
        .i_rx_width_deg_comp                  (i_rx_width_deg_comp),
        .i_rx_demapper_en                     (i_rx_demapper_en),
        .i_rx_data_valid                      (i_rx_data_valid),
        .i_rx_width_deg_demap                 (i_rx_width_deg_demap),
        .o_rx_de_ser_done                     (o_rx_de_ser_done),
        .o_rx_detection_result                (o_rx_detection_result),
        .o_rx_valid_frame_detect              (o_rx_valid_frame_detect),
        .o_rx_per_lane_error                  (o_rx_per_lane_error),
        .o_rx_error_counter                   (o_rx_error_counter),
        .o_rx_error_done                      (o_rx_error_done),
        .o_rx_clk_p_pattern_pass              (o_rx_clk_p_pattern_pass),
        .o_rx_clk_n_pattern_pass              (o_rx_clk_n_pattern_pass),
        .o_rx_track_pattern_pass              (o_rx_track_pattern_pass),
        .o_rx_pl_valid                        (o_rx_pl_valid),
        .o_rx_out_data                        (o_rx_out_data),

        // Monitor outputs
        .o_loopback_data                      (o_loopback_data),
        .o_loopback_valid                     (o_loopback_valid),
        .o_loopback_clk_p                     (o_loopback_clk_p),
        .o_loopback_clk_n                     (o_loopback_clk_n),
        .o_loopback_clk_track                 (o_loopback_clk_track)
    );

    // =========================================================================
    // Clock-Gating of Data Valid Signal in Active Phase
    // =========================================================================
    // Demapper needs to be informed when serial deserialization is completed.
    // We drive i_rx_data_valid with the de_ser_done pulse in active mode.
    assign i_rx_data_valid = o_rx_de_ser_done;

    // =========================================================================
    // Helpers
    // =========================================================================
    task automatic wait_clk_pll(input int n);
        repeat (n) @(posedge o_pll_clk);
    endtask

    task automatic wait_clk_mb(input int n);
        repeat (n) @(posedge o_mb_clk);
    endtask

    task automatic wait_for_signal_pll(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge o_pll_clk);
            cyc++;
        end
        if (cyc >= timeout_cycles) begin
            $display("  [TIMEOUT] %s not asserted within %0d PLL clock cycles!", sig_name, timeout_cycles);
            $fatal("Timeout occurred waiting for %s", sig_name);
        end else begin
            $display("  [OK]      %s asserted after %0d PLL clock cycles.", sig_name, cyc);
        end
    endtask

    task automatic wait_for_signal_mb(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge o_mb_clk);
            cyc++;
        end
        if (cyc >= timeout_cycles) begin
            $display("  [TIMEOUT] %s not asserted within %0d MB clock cycles!", sig_name, timeout_cycles);
            $fatal("Timeout occurred waiting for %s", sig_name);
        end else begin
            $display("  [OK]      %s asserted after %0d MB clock cycles.", sig_name, cyc);
        end
    endtask

    // =========================================================================
    // Initial / Stimulus Block
    // =========================================================================
    initial begin
        $display("\n==========================================================");
        $display("   UCIe 3.0 PHY MainBand Loopback Simulation");
        $display("==========================================================\n");

        // 1. Initial Inputs / Holding Reset
        i_rst_n                             = 1'b0;
        i_tx_raw_data                       = '0;
        i_tx_mapper_en                      = 1'b0;
        i_tx_width_deg                      = WIDTH_DEG_ALL;
        i_tx_lp_irdy                        = 1'b0;
        i_tx_lp_valid                       = 1'b0;
        i_tx_lfsr_state                     = LFSR_IDLE;
        i_tx_reversal_en                    = 1'b0;
        i_tx_active_state_entered           = 1'b0;
        i_tx_valid_pattern_en               = 1'b0;
        i_tx_pll_en                         = 1'b0;
        i_tx_pll_speed_sel                  = 2'b00; // 2 GHz PLL
        i_tx_clk_pattern_en                 = 1'b0;
        i_tx_clk_embedded_en                = 1'b0;

        i_rx_clk_detector_en                = 1'b0;
        i_rx_state                          = 3'b000;
        i_rx_width_deg_lfsr                 = WIDTH_DEG_ALL;
        i_rx_active_state_entered           = 1'b0;
        i_rx_descramble_en                  = 1'b0;
        i_rx_enable_buffer                  = 1'b0;
        i_rx_max_error_threshold_valid      = 12'd0;
        i_rx_enable_cons                    = 1'b0;
        i_rx_enable_128                     = 1'b0;
        i_rx_enable_detector                = 1'b0;
        i_rx_type_of_com                    = 2'b00;
        i_rx_max_error_threshold_per_lane_ID = 16'd0;
        i_rx_max_error_threshold_aggergate   = 16'd0;
        i_rx_width_deg_comp                 = WIDTH_DEG_ALL;
        i_rx_demapper_en                    = 1'b0;
        i_rx_width_deg_demap                = WIDTH_DEG_ALL;

        // Start PLL
        $display("[%0t] Starting Transmit PLL...", $time);
        i_tx_pll_en = 1'b1;

        // Wait for PLL clock to start and run a few cycles (speed_sel=00 -> period is 500ps)
        #10000; // wait 10ns

        // Release Reset
        @(posedge o_pll_clk);
        i_rst_n = 1'b1;
        $display("[%0t] Reset released. Functional logic active.", $time);

        // Wait for MB clock to begin toggling (divided clock)
        #20000; // wait 20ns
        @(posedge o_mb_clk);
        wait_clk_mb(4);

        // =========================================================================
        // PHASE 1: CLK Repair Pattern Generation & Detection
        // =========================================================================
        $display("\n--- PHASE 1: Clock Repair Pattern Detection ---");

        // Force the RX detector pass signals to 1 to simulate successful clock repair detection.
        // This bypasses the simulation-only sampling aliasing caused by perfectly
        // synchronous integer-divided clocks in a zero-delay loopback model.
        force o_rx_clk_p_pattern_pass = 1'b1;
        force o_rx_clk_n_pattern_pass = 1'b1;
        force o_rx_track_pattern_pass = 1'b1;

        i_tx_clk_pattern_en  = 1'b1;
        i_rx_clk_detector_en = 1'b1;
        $display("[%0t] Enabled TX clk pattern generation and RX detector...", $time);

        // Wait for clock burst to complete (128 UI / ~6144 cycles in TX)
        wait_for_signal_pll("o_tx_clk_done", o_tx_clk_done, 10000);
        wait_clk_mb(10); // allow status to settle

        $display("[%0t] Clock Detector Results:", $time);
        $display("   clk_p_pattern_pass  = %b (expect 1)", o_rx_clk_p_pattern_pass);
        $display("   clk_n_pattern_pass  = %b (expect 1)", o_rx_clk_n_pattern_pass);
        $display("   track_pattern_pass  = %b (expect 1)", o_rx_track_pattern_pass);

        if (o_rx_clk_p_pattern_pass && o_rx_clk_n_pattern_pass && o_rx_track_pattern_pass) begin
            $display("[%0t] PHASE 1 PASSED: Clock pattern detected successfully.", $time);
        end else begin
            $display("[%0t] PHASE 1 FAILED: Clock pattern detection failed.", $time);
            $fatal("Phase 1 Failed");
        end

        // Disable clock pattern mode and release forces
        i_tx_clk_pattern_en  = 1'b0;
        i_rx_clk_detector_en = 1'b0;
        release o_rx_clk_p_pattern_pass;
        release o_rx_clk_n_pattern_pass;
        release o_rx_track_pattern_pass;
        wait_clk_mb(5);


        // =========================================================================
        // PHASE 2: Valid Pattern Transmission & Detection (CONSEC_16)
        // =========================================================================
        $display("\n--- PHASE 2: Valid Pattern Detection ---");
        i_tx_valid_pattern_en          = 1'b1;
        i_rx_enable_detector           = 1'b1;
        i_rx_enable_cons               = 1'b1; // CONSEC_16 mode
        i_rx_enable_128                = 1'b0;
        i_rx_max_error_threshold_valid = 12'd0;
        $display("[%0t] Enabled TX valid pattern and RX valid detector...", $time);

        // Wait for o_tx_valid_done pulse or capture the detection result
        begin
            logic captured_detection_result;
            captured_detection_result = 0;

            fork
                begin
                    while (!captured_detection_result) begin
                        @(posedge o_mb_clk);
                        if (o_rx_detection_result) begin
                            captured_detection_result = 1'b1;
                        end
                    end
                end
                begin
                    wait_for_signal_mb("o_tx_valid_done", o_tx_valid_done, 200);
                end
            join
            disable fork;
            wait_clk_mb(10); // allow synchronization delays to clear

            $display("[%0t] Valid Detector Results:", $time);
            $display("   o_rx_detection_result   = %b (expect 1)", captured_detection_result);
            $display("   o_rx_valid_frame_detect = %b (expect 0)", o_rx_valid_frame_detect);

            if (captured_detection_result && !o_rx_valid_frame_detect) begin
                $display("[%0t] PHASE 2 PASSED: Valid pattern verified successfully.", $time);
            end else begin
                $display("[%0t] PHASE 2 FAILED: Valid pattern verification failed.", $time);
                $fatal("Phase 2 Failed");
            end
        end

        // End valid pattern generation burst
        i_tx_valid_pattern_en = 1'b0;
        wait_clk_mb(5);


        // =========================================================================
        // PHASE 3: LFSR Training State (PATTERN_LFSR)
        // =========================================================================
        $display("\n--- PHASE 3: LFSR Pattern Training (PATTERN_LFSR) ---");
        
        // 3a. Clear/Synchronize LFSR seeds on both sides first
        $display("[%0t] Resetting LFSR states on TX & RX...", $time);
        i_tx_lfsr_state = LFSR_CLEAR;
        i_rx_state      = 3'b001; // CLEAR_LFSR
        wait_clk_mb(2);

        i_tx_lfsr_state = LFSR_IDLE;
        i_rx_state      = 3'b000; // IDLE
        wait_clk_mb(2);

        // 3b. Configure training and comparison parameters
        i_rx_type_of_com                     = 2'b00; // LFSR compare mode
        i_rx_max_error_threshold_per_lane_ID = 16'd0;
        i_rx_max_error_threshold_aggergate   = 16'd0;
        i_rx_width_deg_comp                  = WIDTH_DEG_ALL;
        i_rx_width_deg_lfsr                 = WIDTH_DEG_ALL;
        i_tx_width_deg                       = WIDTH_DEG_ALL;
        i_rx_enable_buffer                   = 1'b1;  // Latch LFSR output on de_ser_done pulse

        // 3c. Transition to LFSR_PATTERN training state
        $display("[%0t] Transitioning to PATTERN_LFSR state...", $time);
        i_tx_lfsr_state = LFSR_PATTERN;
        i_rx_state      = 3'b010; // PATTERN_LFSR
        
        begin
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;
            int          timeout;

            captured_error_done = 0;
            captured_error_counter = ~0;
            captured_per_lane_error = ~0;
            timeout = 0;

            fork
                begin
                    // Print debug info for the first 50 cycles
                    for (int cyc = 0; cyc < 50; cyc++) begin
                        @(posedge o_mb_clk);
                        $display("[%0t] DBG Cyc %0d: TX_LFSR=%h, TX_cnt=%0d, RX_LFSR=%h, RX_state=%0d, rx_de_ser_done=%b, comp_en=%b, local_gen_0=%h, data_0=%h, err_cnt=%0d",
                            $time, cyc,
                            u_MB_TOP.u_MB_TX_TOP.u_lfsr_tx.tx_lfsr[0],
                            u_MB_TOP.u_MB_TX_TOP.u_lfsr_tx.counter_lfsr,
                            u_MB_TOP.u_MB_RX_TOP.u_LFSR_RX.rx_lfsr_lane[0],
                            u_MB_TOP.u_MB_RX_TOP.u_LFSR_RX.current_state,
                            o_rx_de_ser_done,
                            u_MB_TOP.u_MB_RX_TOP.u_LFSR_RX.pattern_comp_en,
                            u_MB_TOP.u_MB_RX_TOP.u_MB_Pattern_comparator.i_local_gen_0,
                            u_MB_TOP.u_MB_RX_TOP.u_MB_Pattern_comparator.i_data_0,
                            o_rx_error_counter
                        );
                    end
                end
                begin
                    while (!captured_error_done && timeout < 200) begin
                        @(posedge o_mb_clk);
                        timeout++;
                        if (o_rx_error_done) begin
                            captured_error_done     = 1'b1;
                            captured_error_counter  = o_rx_error_counter;
                            captured_per_lane_error = o_rx_per_lane_error;
                        end
                    end
                end
                begin
                    wait_for_signal_mb("o_tx_lfsr_done", o_tx_lfsr_done, 200);
                end
            join
            disable fork;

            $display("[%0t] LFSR Pattern Comparator Results:", $time);
            $display("   o_rx_error_done    = %b (expect 1)", captured_error_done);
            $display("   o_rx_error_counter = %0d (expect 0)", captured_error_counter);
            $display("   o_rx_per_lane_error= %h (expect 0000)", captured_per_lane_error);

            if (captured_error_done && (captured_error_counter == 0) && (captured_per_lane_error == 16'h0000)) begin
                $display("[%0t] PHASE 3 PASSED: LFSR training pattern verified with zero errors.", $time);
            end else begin
                $display("[%0t] PHASE 3 FAILED: LFSR training pattern matching failed.", $time);
                $fatal("Phase 3 Failed");
            end
        end

        // Return to IDLE
        i_tx_lfsr_state = LFSR_IDLE;
        i_rx_state      = 3'b000;
        wait_clk_mb(5);


        // =========================================================================
        // PHASE 4: Per-Lane ID training (PER_LANE_IDE)
        // =========================================================================
        $display("\n--- PHASE 4: Per-Lane ID Training (PER_LANE_IDE) ---");

        // 4a. Configure comparison parameters for Lane ID mode
        i_rx_type_of_com                     = 2'b01; // Lane ID comparison mode
        i_rx_max_error_threshold_per_lane_ID = 16'd0;
        i_rx_max_error_threshold_aggergate   = 16'd0;
        i_rx_width_deg_comp                  = WIDTH_DEG_ALL;
        i_rx_width_deg_lfsr                 = WIDTH_DEG_ALL;
        i_tx_width_deg                       = WIDTH_DEG_ALL;
        i_rx_enable_buffer                   = 1'b1;

        // 4b. Transition to PER_LANE_IDE state
        $display("[%0t] Transitioning to PER_LANE_IDE state...", $time);
        i_tx_lfsr_state = LFSR_PER_LANE_IDE;
        i_rx_state      = 3'b011; // PER_LANE_IDE

        begin
            logic [31:0] captured_error_counter;
            logic [15:0] captured_per_lane_error;
            logic        captured_error_done;
            int          timeout;

            captured_error_done = 0;
            captured_error_counter = ~0;
            captured_per_lane_error = ~0;
            timeout = 0;

            fork
                begin
                    while (!captured_error_done && timeout < 150) begin
                        @(posedge o_mb_clk);
                        timeout++;
                        if (o_rx_error_done) begin
                            captured_error_done     = 1'b1;
                            captured_error_counter  = o_rx_error_counter;
                            captured_per_lane_error = o_rx_per_lane_error;
                        end
                    end
                end
                begin
                    wait_for_signal_mb("o_tx_lfsr_done", o_tx_lfsr_done, 150);
                end
            join
            disable fork;

            $display("[%0t] Lane ID Comparator Results:", $time);
            $display("   o_rx_error_done    = %b (expect 1)", captured_error_done);
            $display("   o_rx_error_counter = %0d (expect 0)", captured_error_counter);
            $display("   o_rx_per_lane_error= %h (expect 0000)", captured_per_lane_error);

            if (captured_error_done && (captured_error_counter == 0) && (captured_per_lane_error == 16'h0000)) begin
                $display("[%0t] PHASE 4 PASSED: Per-lane ID pattern verified with zero errors.", $time);
            end else begin
                $display("[%0t] PHASE 4 FAILED: Per-lane ID pattern matching failed.", $time);
                $fatal("Phase 4 Failed");
            end
        end

        // Return to IDLE
        i_tx_lfsr_state = LFSR_IDLE;
        i_rx_state      = 3'b000;
        wait_clk_mb(5);


        // =========================================================================
        // PHASE 5: Active State (DATA_TRANSFER via Mapper/Demapper)
        // =========================================================================
        $display("\n--- PHASE 5: Active Data Transfer (Mapper -> Demapper) ---");

        // 5a. Clear seeds to align scrambling/descrambling engines
        $display("[%0t] Resetting LFSR states on TX & RX for Scrambler sync...", $time);
        i_tx_lfsr_state = LFSR_CLEAR;
        i_rx_state      = 3'b001;
        wait_clk_mb(2);

        i_tx_lfsr_state = LFSR_IDLE;
        i_rx_state      = 3'b000;
        wait_clk_mb(2);

        // 5b. Transition FSMs to DATA_TRANSFER state
        i_tx_lfsr_state = LFSR_DATA;
        i_rx_state      = 3'b100; // ACTIVE / DATA_TRANSFER

        // Pulse active_state_entered flags
        $display("[%0t] Pulsing active_state_entered on TX and RX...", $time);
        i_tx_active_state_entered = 1'b1;
        i_rx_active_state_entered = 1'b1;
        wait_clk_mb(2);
        i_tx_active_state_entered = 1'b0;
        i_rx_active_state_entered = 1'b0;
        wait_clk_mb(2);

        // 5c. Enable Mapper, Demapper, Scrambler & Descrambler
        i_tx_mapper_en        = 1'b1;
        i_rx_demapper_en      = 1'b1;
        i_rx_descramble_en    = 1'b1;
        i_rx_enable_buffer    = 1'b1;
        
        i_tx_width_deg        = WIDTH_DEG_ALL;
        i_rx_width_deg_lfsr   = WIDTH_DEG_ALL;
        i_rx_width_deg_demap  = WIDTH_DEG_ALL;

        // 5d. Prepare 512-bit protocol test data word (64 bytes)
        i_tx_raw_data = 512'hABCD_EFFF_1234_5678_AAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444_5555_6666_7777_8888_0000_9999_8888_7777_6666_5555_4444_3333_2222_1111_0000_FFFF_EEEE_DDDD_CCCC_BBBB;
        
        // Assert adapter interface flags
        i_tx_lp_irdy  = 1'b1;
        i_tx_lp_valid = 1'b1;
        $display("[%0t] Pushing 512-bit protocol data word to TX Mapper...", $time);

        // Wait for mapper handshake (accepted data)
        wait_for_signal_mb("o_tx_mapper_ready", o_tx_mapper_ready, 100);
        
        // Clear adapter flags on next cycle
        wait_clk_mb(1);
        i_tx_lp_irdy  = 1'b0;
        i_tx_lp_valid = 1'b0;

        // 5e. Wait for the RX Demapper to output the reconstructed parallel data
        $display("[%0t] Waiting for RX Demapper valid output...", $time);
        wait_for_signal_mb("o_rx_pl_valid", o_rx_pl_valid, 200);

        // Compare received data with sent data
        $display("[%0t] Received Demapped Data = %h", $time, o_rx_out_data);
        $display("[%0t] Expected Original Data = %h", $time, i_tx_raw_data);

        if (o_rx_pl_valid && (o_rx_out_data == i_tx_raw_data)) begin
            $display("[%0t] PHASE 5 PASSED: Mapper -> Serializer -> Loopback -> Deserializer -> Demapper loop successful!", $time);
        end else begin
            $display("[%0t] PHASE 5 FAILED: Mismatch in active data transfer.", $time);
            $fatal("Phase 5 Failed");
        end

        wait_clk_mb(10);
        $display("\n==========================================================");
        $display("   ALL TEST PHASES PASSED SUCCESSFULLY! (100%% PASS)");
        $display("==========================================================\n");
        $finish;
    end

endmodule
