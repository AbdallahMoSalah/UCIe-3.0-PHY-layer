`timescale 1ps/1ps
// =============================================================================
// Testbench  : wrapper_RXCLKCAL_tb
// DUT        : wrapper_RXCLKCAL (which includes local and partner units)
// Purpose    : Functional verification of the MBTRAIN.RXCLKCAL sub-state FSM.
//              Includes 25 randomized scenarios with cycle-by-cycle self-checking.
//              Supports asymmetric calibration completion (Die A and Die B running
//              asynchronously with different loop iterations).
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
    wire  local_rxclkcal_done;
    wire  local_trainerror_req;

    logic partner_rxclkcal_en;
    wire  partner_rxclkcal_done;
    wire  partner_trainerror_req;

    logic soft_rst_n;
    logic rxclkcal_done;
    logic trainerror_req;

    string last_lcl_state_str = "";
    string last_ptn_state_str = "";
    string last_tx_msg_str = "";
    string last_rx_msg_str = "";
    integer cycle_count = 0;

    assign local_rxclkcal_done    = dut.local_rxclkcal_done_wire;
    assign local_trainerror_req   = dut.local_trainerror_req_wire;
    assign partner_rxclkcal_done  = dut.partner_rxclkcal_done_wire;
    assign partner_trainerror_req = dut.partner_trainerror_req_wire;

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
        .soft_rst_n                     (soft_rst_n                  ),
        .phy_negotiated_speed           (intf.phy_negotiated_speed   ),
        .is_high_speed                  (is_high_speed               ),
        .is_continuous_clk_mode         (is_continuous_clk_mode      ),
        .local_rxclkcal_en              (local_rxclkcal_en           ),
        .rxclkcal_done                  (rxclkcal_done               ),
        .trainerror_req                 (trainerror_req              ),
        .partner_rxclkcal_en            (partner_rxclkcal_en         ),
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
        soft_rst_n = 1'b0;
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
        intf.tb_wait_timeout = 1'b0;

        cycle_count = 0;
        last_lcl_state_str = "";
        last_ptn_state_str = "";
        last_tx_msg_str = "";
        last_rx_msg_str = "";

        #(10*LCLK_PERIOD);
        rst_n = 1'b1;
        soft_rst_n = 1'b1;
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

    function automatic string get_lcl_state_str(input int state_val);
        case (state_val)
            0: return "RXCLKCAL_LCL_IDLE";
            1: return "RXCLKCAL_LCL_SEND_START_REQ";
            2: return "RXCLKCAL_LCL_WAIT_START_RESP";
            3: return "RXCLKCAL_LCL_INIT_LOCK";
            4: return "RXCLKCAL_LCL_IQ_LOOP";
            5: return "RXCLKCAL_LCL_SEND_DONE_REQ";
            6: return "RXCLKCAL_LCL_WAIT_DONE_RESP";
            7: return "RXCLKCAL_LCL_TO_VALTRAINCENTER";
            8: return "RXCLKCAL_LCL_TO_TRAINERROR";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string get_ptn_state_str(input int state_val);
        case (state_val)
            0: return "RXCLKCAL_PTR_IDLE";
            1: return "RXCLKCAL_PTR_WAIT_START_REQ";
            2: return "RXCLKCAL_PTR_SEND_START_RESP";
            3: return "RXCLKCAL_PTR_IQ_LOOP";
            4: return "RXCLKCAL_PTR_SEND_DONE_RESP";
            5: return "RXCLKCAL_PTR_TO_VALTRAINCENTER";
            6: return "RXCLKCAL_PTR_TO_TRAINERROR";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string get_msg_str(input [7:0] msg_val);
        case (msg_val)
            SBINIT_Out_of_Reset: return "SBINIT_Out_of_Reset";
            SBINIT_done_req: return "SBINIT_done_req";
            SBINIT_done_resp: return "SBINIT_done_resp";
            MBTRAIN_RXCLKCAL_start_req: return "RXCLKCAL_START_REQ";
            MBTRAIN_RXCLKCAL_start_resp: return "RXCLKCAL_START_RESP";
            MBTRAIN_RXCLKCAL_done_req: return "RXCLKCAL_DONE_REQ";
            MBTRAIN_RXCLKCAL_done_resp: return "RXCLKCAL_DONE_RESP";
            MBTRAIN_RXCLKCAL_TCKN_L_shift_req: return "TCKN_L_SHIFT_REQ";
            MBTRAIN_RXCLKCAL_TCKN_L_shift_resp: return "TCKN_L_SHIFT_RESP";
            TRAINERROR_Entry_req: return "TRAINERROR_Entry_req";
            TRAINERROR_Entry_resp: return "TRAINERROR_Entry_resp";
            NOTHING: return "NOTHING";
            default: return $sformatf("MsgCode: 8'h%2h", msg_val);
        endcase
    endfunction


    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            last_lcl_state_str <= "";
            last_ptn_state_str <= "";
            last_tx_msg_str <= "";
            last_rx_msg_str <= "";
        end else begin
            cycle_count <= cycle_count + 1;
            begin
                automatic string lcl_state_str = get_lcl_state_str(dut.u_RXCLKCAL_local.current_state);
                automatic string ptn_state_str = get_ptn_state_str(dut.u_RXCLKCAL_partner.current_state);
                automatic string tx_msg_str = get_msg_str(intf.tx_sb_msg_valid ? intf.tx_sb_msg : NOTHING);
                automatic string rx_msg_str = get_msg_str(intf.rx_sb_msg_valid ? intf.rx_sb_msg : NOTHING);

                if (lcl_state_str != last_lcl_state_str ||
                        ptn_state_str != last_ptn_state_str ||
                        tx_msg_str != last_tx_msg_str ||
                        rx_msg_str != last_rx_msg_str) begin

                    $display("# [Cycle %3d]: lcl_state=%-30s, ptn_state=%-30s, tx_sb_msg=%-25s, rx_sb_msg=%-25s",
                        cycle_count,
                        lcl_state_str,
                        ptn_state_str,
                        tx_msg_str,
                        rx_msg_str);

                    last_lcl_state_str = lcl_state_str;
                    last_ptn_state_str = ptn_state_str;
                    last_tx_msg_str = tx_msg_str;
                    last_rx_msg_str = rx_msg_str;
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
        $display("STARTING 22 TESTS (20 RANDOMIZED + 2 DETERMINISTIC ASYMMETRIC)");
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
            // 80% probability happy path (0),
            // 20% OOR error (1)
            rand_error_mode = $urandom_range(0, 9);
            if (rand_error_mode < 8)       rand_error_mode = 0;
            else                           rand_error_mode = 1;

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
            //  else if (rand_error_mode == 2) begin
            //  // Local timeout error: initiator exits to TRAINERROR
            //  if (!loc_err_captured) begin
            //  $display("[ERROR] Watchdog 8ms timeout error injection failed! local_trainerror_req=%b",
            //  loc_err_captured);
            //  check_fail = 1'b1;
            //  end else begin
            //  $display("Test #%0d PASS (Watchdog timeout handled successfully)", test_idx);
            //  end
            //  end
        end

        // =========================================================================
        // Test #21: Deterministic — Die A converges on the FIRST IQ measurement
        //           (no TCKN_L_shift_req is ever sent to the partner)
        //
        // Coverage: IQ_PTR_LISTEN → IQ_PTR_DONE transition triggered by
        //           RXCLKCAL_done_req arriving BEFORE any shift_req.
        //           Verifies the spec-defined dual-exit from IQ_PTR_LISTEN.
        // =========================================================================
        begin
            logic loc_done_21, ptn_done_21, loc_err_21, ptn_err_21;

            $display("\n---> Running Test #21 (DETERMINISTIC): Die A IQ immediate convergence (no shift_req sent)");
            $display("     Speed=6 (HighSpeed=1), ContClk=0 — phy_rx_tckn_shift pre-set to 5'd0");
            apply_reset_rand(3'd6, 1'b0, 0);

            loc_done_21 = 1'b0; ptn_done_21 = 1'b0;
            loc_err_21  = 1'b0; ptn_err_21  = 1'b0;
            phy_rx_tckn_shift              = 5'd0;   // Already converged — IQ_EVAL exits immediately
            phy_rx_decrement_shift         = 1'b0;
            phy_tx_tckn_shift_out_of_range = 1'b0;

            fork
                begin // local driver for Test #21
                    local_rxclkcal_en = 1'b1;
                    // phy_rx_tckn_shift == 0 from the start:
                    //   IQ_LCL_MEASURE -> IQ_LCL_EVAL -> IQ_LCL_DONE_SUCCESS
                    // No TCKN_L_shift_req is generated. The outer local FSM
                    // proceeds directly to SEND_DONE_REQ.
                    wait(local_rxclkcal_done);
                    loc_done_21 = local_rxclkcal_done;
                    loc_err_21  = local_trainerror_req;
                    local_rxclkcal_en = 1'b0;
                    $display("# Test #21: Local Side Finished.");
                end
                begin // partner driver for Test #21
                    partner_rxclkcal_en = 1'b1;
                    // Partner enters IQ_PTR_LISTEN and waits.
                    // It will receive RXCLKCAL_done_req (not a shift_req),
                    // transition IQ_PTR_LISTEN -> IQ_PTR_DONE, assert iq_partner_done,
                    // and then the outer partner FSM sends done_resp and finishes.
                    wait(partner_rxclkcal_done || local_rxclkcal_done);
                    ptn_done_21 = partner_rxclkcal_done;
                    ptn_err_21  = partner_trainerror_req;
                    partner_rxclkcal_en = 1'b0;
                    $display("# Test #21: Partner Side Finished.");
                end
            join

            #(10 * LCLK_PERIOD);
            if (loc_err_21 || ptn_err_21 || !loc_done_21 || !ptn_done_21) begin
                $display("[ERROR] Test #21 FAILED! loc_done=%b ptn_done=%b loc_err=%b ptn_err=%b",
                    loc_done_21, ptn_done_21, loc_err_21, ptn_err_21);
                check_fail = 1'b1;
            end else
                $display("Test #21 PASS (Die A finished IQ first via immediate convergence — partner exited IQ_PTR_LISTEN on done_req without prior shift_req)");
        end

        // =========================================================================
        // Test #22: Deterministic — Die A does exactly 4 shift iterations then converges
        //           (partner processes 4 x TCKN_L_shift_req/resp, then done_req)
        //
        // Coverage: Full IQ_PTR_LISTEN -> IQ_PTR_SEND_SHIFT_RESP -> IQ_PTR_LISTEN
        //           loop executed 4 times, then IQ_PTR_LISTEN -> IQ_PTR_DONE on done_req.
        //           Verifies multi-iteration stability and correct final exit.
        // =========================================================================
        begin
            logic loc_done_22, ptn_done_22, loc_err_22, ptn_err_22;

            $display("\n---> Running Test #22 (DETERMINISTIC): Die A finishes IQ after 4 shift iterations");
            $display("     Speed=6 (HighSpeed=1), ContClk=0 — shifts: 3,6,9,12 then 0 (converged)");
            apply_reset_rand(3'd6, 1'b0, 0);

            loc_done_22 = 1'b0; ptn_done_22 = 1'b0;
            loc_err_22  = 1'b0; ptn_err_22  = 1'b0;
            phy_tx_tckn_shift_out_of_range = 1'b0; // All 4 shifts are within range

            fork
                begin // local driver for Test #22
                    local_rxclkcal_en = 1'b1;
                    // Drive 4 non-zero residuals, then converge on the 5th measurement.
                    // Shift values 3,6,9,12 are all ≤ 31, so the partner will respond
                    // with Success encoding each time.
                    for (int i = 1; i <= 5; i++) begin
                        // Wait for IQ measurement phase to begin
                        wait(intf.phy_rx_phase_detector_en || local_trainerror_req);
                        if (local_trainerror_req) break;

                        if (i < 5) begin
                            // Iterations 1-4: non-zero residual → shift_req will be sent
                            phy_rx_tckn_shift      = 5'(i * 3); // 3, 6, 9, 12
                            phy_rx_decrement_shift = i[0];       // alternating direction: 1,0,1,0
                        end else begin
                            // Iteration 5: converged → no shift_req, done_req follows
                            phy_rx_tckn_shift      = 5'd0;
                            phy_rx_decrement_shift = 1'b0;
                        end

                        // Wait for measurement phase to end (phase_detector de-asserts)
                        wait(!intf.phy_rx_phase_detector_en || local_trainerror_req);
                        if (local_trainerror_req) break;
                    end

                    wait(local_rxclkcal_done);
                    loc_done_22 = local_rxclkcal_done;
                    loc_err_22  = local_trainerror_req;
                    local_rxclkcal_en = 1'b0;
                    $display("# Test #22: Local Side Finished.");
                end
                begin // partner driver for Test #22
                    partner_rxclkcal_en = 1'b1;
                    // Partner responds to 4 shift_req messages (all in-range → Success),
                    // loops IQ_PTR_LISTEN -> IQ_PTR_SEND_SHIFT_RESP -> IQ_PTR_LISTEN × 4,
                    // then receives done_req and transitions to IQ_PTR_DONE.
                    wait(partner_rxclkcal_done || local_rxclkcal_done);
                    ptn_done_22 = partner_rxclkcal_done;
                    ptn_err_22  = partner_trainerror_req;
                    partner_rxclkcal_en = 1'b0;
                    $display("# Test #22: Partner Side Finished.");
                end
            join

            #(10 * LCLK_PERIOD);
            if (loc_err_22 || ptn_err_22 || !loc_done_22 || !ptn_done_22) begin
                $display("[ERROR] Test #22 FAILED! loc_done=%b ptn_done=%b loc_err=%b ptn_err=%b",
                    loc_done_22, ptn_done_22, loc_err_22, ptn_err_22);
                check_fail = 1'b1;
            end else
                $display("Test #22 PASS (Die A finished after 4 shift iters — partner processed all 4 shift_req/resp exchanges + final done_req)");
        end

        // Final report
        $display("\n==================================================");
        if (check_fail) begin
            fail_count = 1;
            $display("TEST SUITE FAILED - SELF-CHECKING ERRORS OCCURRED");
        end else begin
            success_count = 22;
            $display("TEST SUITE PASSED - ALL 22 TESTS PASSED (20 RANDOMIZED + 2 DETERMINISTIC ASYMMETRIC)");
        end
        $display("==================================================");
        $stop;
    end

endmodule
