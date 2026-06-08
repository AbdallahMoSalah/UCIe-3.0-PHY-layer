`timescale 1ps/1ps
// =============================================================================
// Testbench  : wrapper_RXCLKCAL_tb
// DUT        : wrapper_RXCLKCAL (which includes local and partner units)
// Purpose    : Functional verification of the MBTRAIN.RXCLKCAL sub-state FSM.
//              Includes 20 randomized scenarios with cycle-by-cycle self-checking.
// =============================================================================

module wrapper_RXCLKCAL_tb ();
    import UCIe_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter  LCLK_PERIOD          = 1000;    // 1 GHz lclk (1000 ps period)
    parameter  TIMEOUT_CYCLES       = 1000;    // Reduced for fast simulation
    parameter  ANALOG_SETTLE_CYCLES = 10;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    reg lclk;
    reg rst_n;

    // Instantiate the standard interface used by attachments
    ltsm_tb_if intf(.lclk(lclk), .rst_n(rst_n));

    // =========================================================================
    // lclk Generator
    // =========================================================================
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // =========================================================================
    // DUT: wrapper_RXCLKCAL
    // =========================================================================
    // Internal wires for local/partner control
    logic local_rxclkcal_en;
    logic local_rxclkcal_done;
    logic local_trainerror_req;

    logic partner_rxclkcal_en;
    logic partner_rxclkcal_done;
    logic partner_trainerror_req;

    // Link configurations
    logic is_high_speed;
    logic is_continuous_clk_mode;

    assign is_high_speed = (intf.phy_negotiated_speed > 3'd5);

    // PHY signals
    logic [4:0] phy_rx_tckn_shift;
    logic       phy_rx_decrement_shift;
    logic       phy_tx_tckn_shift_out_of_range;

    wrapper_RXCLKCAL dut (
        .lclk                           (lclk                        ),
        .rst_n                          (rst_n                       ),
        .is_ltsm_out_of_reset           (intf.is_ltsm_out_of_reset   ),
        .timeout_8ms_occured            (intf.timeout_8ms_occured    ),
        .phy_negotiated_speed           (intf.phy_negotiated_speed   ),
        .is_high_speed                  (is_high_speed               ),
        .is_continuous_clk_mode         (is_continuous_clk_mode      ),
        .local_rxclkcal_en              (local_rxclkcal_en           ),
        .local_rxclkcal_done            (local_rxclkcal_done         ),
        .local_trainerror_req           (local_trainerror_req        ),
        .partner_rxclkcal_en            (partner_rxclkcal_en         ),
        .partner_rxclkcal_done          (partner_rxclkcal_done       ),
        .partner_trainerror_req         (partner_trainerror_req      ),
        .timeout_timer_en               (intf.timeout_timer_en       ),
        .analog_settle_timer_en         (intf.analog_settle_timer_en ),
        .analog_settle_time_done        (intf.analog_settle_time_done),
        .phy_rx_clock_lock_en           (intf.phy_rx_clock_lock_en   ),
        .phy_rx_track_lock_en           (intf.phy_rx_track_lock_en   ),
        .phy_rx_phase_detector_en       (intf.phy_rx_phase_detector_en),
        .phy_rx_tckn_shift              (phy_rx_tckn_shift           ),
        .phy_rx_decrement_shift         (phy_rx_decrement_shift      ),
        .phy_tx_tckn_shift_en           (intf.phy_tx_tckn_shift_en   ),
        .phy_tx_tckn_shift              (intf.phy_tx_tckn_shift      ),
        .phy_tx_decrement_shift         (intf.phy_tx_decrement_shift ),
        .phy_tx_tckn_shift_out_of_range (phy_tx_tckn_shift_out_of_range),
        .mb_tx_clk_lane_sel             (intf.mb_tx_clk_lane_sel     ),
        .mb_tx_data_lane_sel            (intf.mb_tx_data_lane_sel    ),
        .mb_tx_val_lane_sel             (intf.mb_tx_val_lane_sel     ),
        .mb_tx_trk_lane_sel             (intf.mb_tx_trk_lane_sel     ),
        .mb_rx_clk_lane_sel             (intf.mb_rx_clk_lane_sel     ),
        .mb_rx_data_lane_sel            (intf.mb_rx_data_lane_sel    ),
        .mb_rx_val_lane_sel             (intf.mb_rx_val_lane_sel     ),
        .mb_rx_trk_lane_sel             (intf.mb_rx_trk_lane_sel     ),
        .mb_tx_pattern_en               (intf.mb_tx_pattern_en       ),
        .mb_tx_pattern_setup            (intf.mb_tx_pattern_setup    ),
        .mb_tx_clk_pattern_sel          (intf.mb_tx_clk_pattern_sel  ),
        .tx_sb_msg_valid                (intf.tx_sb_msg_valid        ),
        .tx_sb_msg                      (intf.tx_sb_msg              ),
        .tx_msginfo                     (intf.tx_msginfo             ),
        .tx_data_field                  (intf.tx_data_field          ),
        .rx_sb_msg_valid                (intf.rx_sb_msg_valid        ),
        .rx_sb_msg                      (intf.rx_sb_msg              ),
        .rx_msginfo                     (intf.rx_msginfo             ),
        .rx_data_field                  (intf.rx_data_field          )
    );

    // =========================================================================
    // Attachments (Loopback, timers, negotiated logic)
    // =========================================================================
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (10                  )
    ) attachments (
        .intf(intf)
    );

    // Score-keeping
    integer success_count = 0;
    integer fail_count    = 0;

    // Test variables
    logic [2:0] rand_speed;
    logic       rand_continuous_clk;
    integer     rand_error_mode; // 0 = happy, 1 = partner OOR, 2 = local timeout
    integer     rand_num_iters;
    logic       check_fail;

    // Task to apply reset with randomized inputs
    task apply_reset_rand(input logic [2:0] speed, input logic continuous, input integer error_mode);
        rst_n = 1'b0;
        intf.is_ltsm_out_of_reset = 1'b0;
        local_rxclkcal_en = 1'b0;
        partner_rxclkcal_en = 1'b0;
        phy_rx_tckn_shift = 5'd0;
        phy_rx_decrement_shift = 1'b0;
        phy_tx_tckn_shift_out_of_range = 1'b0;
        intf.phy_negotiated_speed = speed;
        is_continuous_clk_mode = continuous;
        intf.tb_wrong_sb_msg_en = 1'b0;
        intf.timeout_8ms_occured = 1'b0;
        
        // If error mode 2, enable tb_wait_timeout to trigger a watchdog timeout
        if (error_mode == 2) begin
            intf.tb_wait_timeout = 1'b1;
        end else begin
            intf.tb_wait_timeout = 1'b0;
        end

        #(10*LCLK_PERIOD);
        rst_n = 1'b1;
        #(2*LCLK_PERIOD);
        intf.is_ltsm_out_of_reset = 1'b1;
        #(2*LCLK_PERIOD);
    endtask

    // =========================================================================
    // Cycle-by-Cycle Self-Checking Assertions
    // =========================================================================
    always @(posedge lclk) begin
        if (rst_n && intf.is_ltsm_out_of_reset) begin
            // -------------------------------------------------------------
            // Assertion 1: Verify mb_tx signals according to speed/mode
            // -------------------------------------------------------------
            if (!partner_rxclkcal_en) begin
                // When Partner is not active, behavior depends solely on static config
                if (!is_high_speed && !is_continuous_clk_mode) begin
                    if (intf.mb_tx_clk_lane_sel !== 2'b00 || intf.mb_tx_trk_lane_sel !== 2'b00 || intf.mb_tx_pattern_en !== 1'b0) begin
                        $display("[ERROR] Idle mb_tx signals incorrect for low-speed strobe. Expected 0, Got clk=%b trk=%b pat=%b", 
                                  intf.mb_tx_clk_lane_sel, intf.mb_tx_trk_lane_sel, intf.mb_tx_pattern_en);
                        check_fail = 1'b1;
                    end
                end else begin
                    if (intf.mb_tx_clk_lane_sel !== 2'b01 || intf.mb_tx_trk_lane_sel !== 2'b01 || intf.mb_tx_pattern_en !== 1'b1) begin
                        $display("[ERROR] Idle mb_tx signals incorrect for high-speed/continuous. Expected clk=01 trk=01 pat=1, Got clk=%b trk=%b pat=%b", 
                                  intf.mb_tx_clk_lane_sel, intf.mb_tx_trk_lane_sel, intf.mb_tx_pattern_en);
                        check_fail = 1'b1;
                    end
                end
            end else begin
                // When Partner is active, behavior depends on handshake progress (tx_clk_active_r)
                if (dut.u_RXCLKCAL_partner.tx_clk_active_r) begin
                    if (intf.mb_tx_clk_lane_sel !== 2'b01 || intf.mb_tx_trk_lane_sel !== 2'b01 || intf.mb_tx_pattern_en !== 1'b1) begin
                        $display("[ERROR] Active mb_tx signals incorrect. Expected clk=01 trk=01 pat=1, Got clk=%b trk=%b pat=%b", 
                                  intf.mb_tx_clk_lane_sel, intf.mb_tx_trk_lane_sel, intf.mb_tx_pattern_en);
                        check_fail = 1'b1;
                    end
                end else begin
                    // Not active yet (or stopped after done_req on low speed strobe)
                    if (!is_high_speed && !is_continuous_clk_mode) begin
                        if (intf.mb_tx_clk_lane_sel !== 2'b00 || intf.mb_tx_trk_lane_sel !== 2'b00 || intf.mb_tx_pattern_en !== 1'b0) begin
                            $display("[ERROR] Inactive partner mb_tx signals incorrect for low-speed strobe. Expected 0, Got clk=%b trk=%b pat=%b", 
                                      intf.mb_tx_clk_lane_sel, intf.mb_tx_trk_lane_sel, intf.mb_tx_pattern_en);
                            check_fail = 1'b1;
                        end
                    end else begin
                        if (intf.mb_tx_clk_lane_sel !== 2'b01 || intf.mb_tx_trk_lane_sel !== 2'b01 || intf.mb_tx_pattern_en !== 1'b1) begin
                            $display("[ERROR] Inactive partner mb_tx signals incorrect for high-speed/continuous. Expected clk=01 trk=01 pat=1, Got clk=%b trk=%b pat=%b", 
                                      intf.mb_tx_clk_lane_sel, intf.mb_tx_trk_lane_sel, intf.mb_tx_pattern_en);
                            check_fail = 1'b1;
                        end
                    end
                end
            end

            // -------------------------------------------------------------
            // Assertion 2: Verify mb_rx signals
            // -------------------------------------------------------------
            if (local_rxclkcal_en) begin
                // When local is active, we check depending on local state
                if (dut.u_RXCLKCAL_local.current_state >= 4'd3 && dut.u_RXCLKCAL_local.current_state <= 4'd6) begin
                    if (intf.mb_rx_clk_lane_sel !== 1'b1 || intf.mb_rx_trk_lane_sel !== 1'b1) begin
                        $display("[ERROR] Active mb_rx signals incorrect. Expected 1, Got clk=%b trk=%b", 
                                  intf.mb_rx_clk_lane_sel, intf.mb_rx_trk_lane_sel);
                        check_fail = 1'b1;
                    end
                end else begin
                    if (intf.mb_rx_clk_lane_sel !== 1'b0 || intf.mb_rx_trk_lane_sel !== 1'b0) begin
                        $display("[ERROR] Inactive phase mb_rx signals incorrect. Expected 0, Got clk=%b trk=%b", 
                                  intf.mb_rx_clk_lane_sel, intf.mb_rx_trk_lane_sel);
                        check_fail = 1'b1;
                    end
                end
            end else begin
                // Default: Rx disabled
                if (intf.mb_rx_clk_lane_sel !== 1'b0 || intf.mb_rx_trk_lane_sel !== 1'b0) begin
                    $display("[ERROR] Idle mb_rx signals incorrect. Expected 0, Got clk=%b trk=%b", 
                              intf.mb_rx_clk_lane_sel, intf.mb_rx_trk_lane_sel);
                    check_fail = 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Test Scenarios Control Loop
    // =========================================================================
    initial begin
        check_fail = 1'b0;

        $display("\n==================================================");
        $display("STARTING 20 RANDOMIZED SELF-CHECKING TEST RUNS");
        $display("==================================================");

        for (int test_idx = 1; test_idx <= 20; test_idx++) begin
            // Capture variables for done and error signals
            logic loc_done_captured;
            logic ptn_done_captured;
            logic loc_err_captured;
            logic ptn_err_captured;

            // 1. Randomize parameters
            rand_speed = $urandom_range(0, 7); // Speed code: 0 to 7
            rand_continuous_clk = $urandom_range(0, 1);
            
            // Random error mode: 
            // 70% probability happy path (0), 
            // 15% OOR error (1), 
            // 15% watchdog timeout (2)
            rand_error_mode = $urandom_range(0, 9);
            if (rand_error_mode < 7)       rand_error_mode = 0;
            else if (rand_error_mode == 7) rand_error_mode = 1;
            else                           rand_error_mode = 2;

            rand_num_iters = $urandom_range(1, 5); // 1 to 5 IQ loop iterations

            $display("\n---> Running Test #%0d: Speed=%0d (HighSpeed=%0d), ContClk=%0d, ErrorMode=%0d, IQ_Iters=%0d",
                     test_idx, rand_speed, (rand_speed > 3'd5), rand_continuous_clk, rand_error_mode, rand_num_iters);

            apply_reset_rand(rand_speed, rand_continuous_clk, rand_error_mode);

            loc_done_captured = 1'b0;
            ptn_done_captured = 1'b0;
            loc_err_captured  = 1'b0;
            ptn_err_captured  = 1'b0;

            // Concurrent execution of Local initiator and Partner responder
            fork : run_fork
                begin : local_driver
                    local_rxclkcal_en = 1'b1;
                    
                    // If operating speed > 32 GT/s, simulate IQ phase detector adjustments
                    if (is_high_speed) begin
                        for (int iter = 1; iter <= rand_num_iters; iter++) begin
                            // Wait for phase detector to enable
                            wait(intf.phy_rx_phase_detector_en || local_trainerror_req);
                            if (local_trainerror_req) break;

                            // If Iteration is not the final converged one, randomize shift requirement
                            if (iter < rand_num_iters) begin
                                phy_rx_tckn_shift = $urandom_range(1, 15);
                                phy_rx_decrement_shift = $urandom_range(0, 1);
                            end else begin
                                // Final iteration: either converge (0) or trigger OOR if error mode 1
                                if (rand_error_mode == 1) begin
                                    phy_rx_tckn_shift = 5'd31; // Max shift to push partner OOR
                                    phy_rx_decrement_shift = 1'b0;
                                end else begin
                                    phy_rx_tckn_shift = 5'd0; // Converged
                                end
                            end

                            // Wait for phase detector to go inactive
                            wait(!intf.phy_rx_phase_detector_en || local_trainerror_req);
                            if (local_trainerror_req) break;
                        end
                    end

                    wait(local_rxclkcal_done);
                    loc_done_captured = local_rxclkcal_done;
                    loc_err_captured  = local_trainerror_req;
                    local_rxclkcal_en = 1'b0;
                    $display("Local Side Finished.");
                end

                begin : partner_driver
                    partner_rxclkcal_en = 1'b1;

                    // If error mode is OOR (1), trigger out-of-range flag on the partner when shift requested
                    if (rand_error_mode == 1 && is_high_speed) begin
                        wait(intf.phy_tx_tckn_shift_en || partner_trainerror_req);
                        if (!partner_trainerror_req) begin
                            // Wait some time, then inject OOR
                            #(5*LCLK_PERIOD);
                            phy_tx_tckn_shift_out_of_range = 1'b1;
                        end
                    end

                    // Wait for either partner done or local initiator done (to handle initiator watchdog timeout)
                    wait(partner_rxclkcal_done || local_rxclkcal_done);
                    ptn_done_captured = partner_rxclkcal_done;
                    ptn_err_captured  = partner_trainerror_req;
                    partner_rxclkcal_en = 1'b0;
                    $display("Partner Side Finished.");
                end
            join

            // Check results for this test run
            #(10 * LCLK_PERIOD); // Settle time
            
            if (rand_error_mode == 0 || (rand_error_mode == 1 && !is_high_speed)) begin
                // Happy path: both sides must finish successfully without training errors
                if (loc_err_captured || ptn_err_captured || !loc_done_captured || !ptn_done_captured) begin
                    $display("[ERROR] Happy path check failed! train_error loc=%b ptn=%b done loc=%b ptn=%b",
                             loc_err_captured, ptn_err_captured, loc_done_captured, ptn_done_captured);
                    check_fail = 1'b1;
                end else begin
                    $display("Test #%0d PASS (Happy Path converged successfully)", test_idx);
                end
            end
            else if (rand_error_mode == 1 && is_high_speed) begin
                // Out of range error at high speed: both sides must exit to TRAINERROR
                if (!loc_err_captured || !ptn_err_captured) begin
                    $display("[ERROR] Partner Out of Range error injection failed! train_error loc=%b ptn=%b",
                             loc_err_captured, ptn_err_captured);
                    check_fail = 1'b1;
                end else begin
                    $display("Test #%0d PASS (Out of Range error handled successfully)", test_idx);
                end
            end
            else if (rand_error_mode == 2) begin
                // Local timeout error: initiator exits to TRAINERROR
                if (!loc_err_captured) begin
                    $display("[ERROR] Watchdog 8ms timeout error injection failed! local_trainerror_req=%b",
                             loc_err_captured);
                    check_fail = 1'b1;
                end else begin
                    $display("Test #%0d PASS (Watchdog timeout handled successfully)", test_idx);
                end
            end
        end

        // Final report
        $display("\n==================================================");
        if (check_fail) begin
            fail_count = 1;
            $display("TEST SUITE FAILED - SELF-CHECKING ERRORS OCCURRED");
        end else begin
            success_count = 20;
            $display("TEST SUITE PASSED - ALL 20 RANDOMIZED TESTS PASSED");
        end
        $display("==================================================");
        $stop;
    end

endmodule
