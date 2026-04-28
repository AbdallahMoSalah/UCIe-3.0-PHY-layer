
`timescale 1ps / 1ps

module unit_TX_D2C_PT_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD    = 1*1000 ; // lclk = 1ns (1GHz), waveform x1000
    parameter TIMEOUT_LIMIT  = 100_000; // cycles for shortened timeout

    // Core clocks and resets
    reg lclk ;
    reg rst_n;

    // Interface Instantiation
    internal_ltsm_if intf (
        .lclk(lclk ),
        .rst_n(rst_n)
    );

    // FSM State Mirroring for Monitoring
    typedef enum reg [3:0] {
        TX_PT_IDLE         = unit_TX_D2C_PT_inst.TX_PT_IDLE        , // (S0)
        TX_PT_START_REQ    = unit_TX_D2C_PT_inst.TX_PT_START_REQ   , // (S1)
        TX_PT_START_RESP   = unit_TX_D2C_PT_inst.TX_PT_START_RESP  , // (S2)
        TX_PT_CLR_ERR_REQ  = unit_TX_D2C_PT_inst.TX_PT_CLR_ERR_REQ , // (S3)
        TX_PT_CLR_ERR_RESP = unit_TX_D2C_PT_inst.TX_PT_CLR_ERR_RESP, // (S4)
        TX_PT_PATTERN_GEN  = unit_TX_D2C_PT_inst.TX_PT_PATTERN_GEN , // (S5)
        TX_PT_RESULTS_REQ  = unit_TX_D2C_PT_inst.TX_PT_RESULTS_REQ , // (S6)
        TX_PT_RESULTS_RESP = unit_TX_D2C_PT_inst.TX_PT_RESULTS_RESP, // (S7)
        TX_PT_END_REQ      = unit_TX_D2C_PT_inst.TX_PT_END_REQ     , // (S8)
        TX_PT_END_RESP     = unit_TX_D2C_PT_inst.TX_PT_END_RESP    , // (S9)
        TX_PT_DONE         = unit_TX_D2C_PT_inst.TX_PT_DONE        , // (S10)
        TO_TRAINERROR      = unit_TX_D2C_PT_inst.TO_TRAINERROR       // (S11)
    } fsm_state_t;

    fsm_state_t state_monitor;
    assign state_monitor = fsm_state_t'(unit_TX_D2C_PT_inst.current_state);

    // Sideband message Names from UCIe_pkg:
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::LFSR_clear_error_req;
    import UCIe_pkg::LFSR_clear_error_resp;
    import UCIe_pkg::Tx_Init_D_to_C_results_req;
    import UCIe_pkg::Tx_Init_D_to_C_results_resp;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING;

    // DUT Instantiation
    unit_TX_D2C_PT unit_TX_D2C_PT_inst (
        .substate_if(intf.d2c2substate_mp),
        .mux_if(intf.d2c2mux_mp)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // SB Clock Simulation (Internal logic)
    reg sb_clk;
    parameter SB_CLK_PERIOD = 1.25*1000;
    initial begin
        sb_clk = 0;
        forever #(SB_CLK_PERIOD/2) sb_clk = ~sb_clk;
    end

    // -------------------------------------------------------------------------
    // Internal SB Responder (Echo Model)
    // -------------------------------------------------------------------------
    integer sb_wait_cnt = 0;
    msg_no_e resp_msg; // Declare resp_msg
    msg_no_e last_tx_msg = NOTHING;

    always @(posedge sb_clk or negedge rst_n) begin
        if (!rst_n) begin
            intf.rx_sb_msg_valid <= 0;
            intf.rx_sb_msg       <= msg_no_e'(0);
            intf.rx_msginfo      <= 16'b0;
            intf.rx_data_field   <= 64'b0;
            sb_wait_cnt          <= 0;
            last_tx_msg          <= NOTHING;
        end else if (intf.tx_sb_msg != last_tx_msg) begin
            // Whenever the FSM changes the message, reset the responder counter
            sb_wait_cnt          <= 0;
            intf.rx_sb_msg_valid <= 0;
            last_tx_msg          <= intf.tx_sb_msg;
        end else if (intf.tb_wait_timeout) begin
            intf.rx_sb_msg_valid <= 0;
        end else if (intf.tx_sb_msg_valid && sb_wait_cnt < 64) begin
            sb_wait_cnt <= sb_wait_cnt + 1;
        end else if (intf.tx_sb_msg_valid && sb_wait_cnt == 64) begin
            intf.rx_sb_msg_valid <= 1;
            // Symmetric Handshake Echo Responder
            case (intf.tx_sb_msg)
                Start_Tx_Init_D_to_C_point_test_req:  resp_msg = Start_Tx_Init_D_to_C_point_test_req;
                Start_Tx_Init_D_to_C_point_test_resp: resp_msg = Start_Tx_Init_D_to_C_point_test_resp;
                LFSR_clear_error_req:                 resp_msg = LFSR_clear_error_req;
                LFSR_clear_error_resp:                resp_msg = LFSR_clear_error_resp;
                Tx_Init_D_to_C_results_req:           resp_msg = Tx_Init_D_to_C_results_req;
                Tx_Init_D_to_C_results_resp:          resp_msg = Tx_Init_D_to_C_results_resp;
                End_Tx_Init_D_to_C_point_test_req:    resp_msg = End_Tx_Init_D_to_C_point_test_req;
                End_Tx_Init_D_to_C_point_test_resp:   resp_msg = End_Tx_Init_D_to_C_point_test_resp;
                default:                              resp_msg = NOTHING;
            endcase
            intf.rx_sb_msg       <= (intf.tb_wrong_sb_msg_en) ? msg_no_e'(intf.tb_wrong_sb_msg) : resp_msg;
            intf.rx_msginfo      <= (intf.tx_sb_msg == Tx_Init_D_to_C_results_resp) ? intf.tb_rx_msginfo : intf.tx_msginfo;
            intf.rx_data_field   <= (intf.tx_sb_msg == Tx_Init_D_to_C_results_resp) ? intf.tb_rx_data_field : intf.tx_data_field;
            sb_wait_cnt          <= sb_wait_cnt + 1;
        end else if (sb_wait_cnt > 64) begin
            intf.rx_sb_msg_valid <= 0;
            if (!intf.tx_sb_msg_valid) sb_wait_cnt <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // Internal MB Behavioral Model
    // -------------------------------------------------------------------------
    integer burst_cnt = 0, idle_cnt = 0, iter_cnt = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            burst_cnt <= 0;
            idle_cnt  <= 0;
            iter_cnt  <= 0;
            intf.mb_tx_pattern_count_done <= 0;
            intf.mb_rx_compare_done       <= 0;
            intf.mb_rx_aggr_err           <= 0;
            intf.mb_rx_perlane_err        <= 0;
            intf.mb_rx_val_err            <= 0;
            intf.mb_rx_clk_err            <= 0;
        end else if (intf.mb_tx_pattern_en) begin
            if (iter_cnt < intf.mb_tx_iter_count) begin
                if (burst_cnt < intf.mb_tx_burst_count) begin
                    burst_cnt <= burst_cnt + 1;
                end else if (idle_cnt < intf.mb_tx_idle_count) begin
                    idle_cnt <= idle_cnt + 1;
                end else begin
                    iter_cnt  <= iter_cnt + 1;
                    burst_cnt <= 0;
                    idle_cnt  <= 0;
                end
            end else begin
                intf.mb_tx_pattern_count_done <= 1;
                intf.mb_rx_compare_done       <= 1;
                intf.mb_rx_aggr_err           <= intf.tb_aggr_err;
                intf.mb_rx_perlane_err        <= intf.tb_perlane_err;
                intf.mb_rx_val_err            <= intf.tb_val_err;
                intf.mb_rx_clk_err            <= intf.tb_clk_err;
            end
        end else begin
            intf.mb_tx_pattern_count_done <= 0;
            intf.mb_rx_compare_done       <= 0;
            burst_cnt <= 0;
            idle_cnt  <= 0;
            iter_cnt  <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // Timeout Counter
    // -------------------------------------------------------------------------
    integer timeout_cnt = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 0;
            intf.substate_timeout_8ms_occured <= 0;
        end else if (state_monitor != TX_PT_IDLE && state_monitor != TX_PT_DONE) begin
            timeout_cnt <= timeout_cnt + 1;
            if (timeout_cnt >= TIMEOUT_LIMIT) intf.substate_timeout_8ms_occured <= 1;
        end else begin
            timeout_cnt <= 0;
            intf.substate_timeout_8ms_occured <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // Test Control Tasks
    // -------------------------------------------------------------------------
    integer success_count         = 0; // A counter to track the number of successful tests.
    integer fail_count            = 0; // A counter to track the number of failed tests.
    integer test_scenario_no      = 1;

    task reset();
        rst_n = 0;
        intf.tx_pt_en = 0;
        intf.tb_wait_timeout = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg = NOTHING;
        intf.tb_aggr_err = 0;
        intf.tb_perlane_err = 0;
        intf.tb_val_err = 0;
        intf.tb_clk_err = 0;
        intf.tb_rx_msginfo = 0;
        intf.tb_rx_data_field = 0;
        intf.cfg_train4_max_err_thresh_perlane = 0;
        intf.cfg_train4_max_err_thresh_aggr    = 0;
        repeat(5) @(posedge lclk);
        rst_n = 1;
        repeat(1) @(posedge lclk);
        $display("%12t ps: Reset released.", $time);
    endtask

    task start_test();
        $display("%12t ps: Triggering tx_pt_en.", $time);
        @(posedge lclk);
        intf.tx_pt_en = 1;
        
        wait(intf.test_d2c_done || intf.d2c_timeout_or_error || state_monitor == TO_TRAINERROR);
        @(posedge lclk);
        intf.tx_pt_en = 0;
        
        if (intf.test_d2c_done) begin
            if (intf.tb_wait_timeout || intf.tb_wrong_sb_msg_en) begin
                repeat(5) $display("\t\t ************************** ERROR **************************");
                $display("%12t ps: ERROR: Test completed but expected error/timeout. <================================= [Error]", $time);
                fail_count++;
                $stop;
            end else begin
                wait(state_monitor == TX_PT_IDLE);
                $display("%12t ps: Test completed successfully.", $time);
                success_count++;
            end
        end else begin
            if (intf.tb_wait_timeout || intf.tb_wrong_sb_msg_en) begin
                $display("%12t ps: Test transitioned to TO_TRAINERROR as expected.", $time);
                success_count++;
            end else begin
                repeat(5) $display("\t\t ************************** ERROR **************************");
                $display("%12t ps: wait unblocked! test_d2c_done=%b, d2c_timeout_or_error=%b, state_monitor=%s, timeout_cnt=%0d, rx_sb_valid=%b, rx_sb_msg=%s", $time, intf.test_d2c_done, intf.d2c_timeout_or_error, state_monitor.name(), timeout_cnt, intf.rx_sb_msg_valid, intf.rx_sb_msg.name());
                $display("%12t ps: ERROR: Test transitioned to TO_TRAINERROR unexpectedly. <================================= [Error]", $time);
                fail_count++;
                $stop;
            end
        end
        $display("________________________________(Success count = %0d, Fail count = %0d)________________________________\n", success_count, fail_count);
    endtask

    task set_d2c_configuration(
        input [1:0]  task_clk_sampling,
        input [2:0]  task_pattern_setup,
        input [1:0]  task_data_pattern_sel,
        input        task_val_pattern_sel,
        input        task_lfsr_en,
        input        task_pattern_mode,
        input [15:0] task_burst_count,
        input [15:0] task_idle_count,
        input [15:0] task_iter_count,
        input [1:0]  task_compare_setup
    );
        intf.d2c_clk_sampling     = task_clk_sampling;
        intf.d2c_pattern_setup    = task_pattern_setup;
        intf.d2c_data_pattern_sel = task_data_pattern_sel;
        intf.d2c_val_pattern_sel  = task_val_pattern_sel;
        intf.d2c_lfsr_en          = task_lfsr_en;
        intf.d2c_pattern_mode     = task_pattern_mode;
        intf.d2c_burst_count      = task_burst_count;
        intf.d2c_idle_count       = task_idle_count;
        intf.d2c_iter_count       = task_iter_count;
        intf.d2c_compare_setup    = task_compare_setup;
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("\n========================================");
        $display("  TX_D2C_PT Self-Contained Testbench");
        $display("========================================\n");
        
        // Scenario 1: Basic Happy Path
        $display("\n=========>  Test Scenario (%0d): Happy Path (Continuous Mode). <=========", test_scenario_no++);
        reset();
        set_d2c_configuration(
            .task_clk_sampling    (2'b00 ),
            .task_pattern_setup   (3'b001),
            .task_data_pattern_sel(2'b00 ),
            .task_val_pattern_sel (2'b00 ),
            .task_lfsr_en         (1'b1  ),
            .task_pattern_mode    (1'b0  ),
            .task_burst_count     (16'd100),
            .task_idle_count      (16'd0 ),
            .task_iter_count      (16'd1 ),
            .task_compare_setup   (2'b00 )
        );
        start_test();

        // Scenario 2: Timeout Test
        $display("\n=========>  Test Scenario (%0d): Timeout Test (SB suppressed). <=========", test_scenario_no++);
        reset();
        intf.tb_wait_timeout = 1;
        start_test();

        // Scenario 3: Partner Error Injection
        $display("\n=========>  Test Scenario (%0d): Partner Error Injection. <=========", test_scenario_no++);
        reset();
        intf.tb_wrong_sb_msg_en = 1;
        intf.tb_wrong_sb_msg    = TRAINERROR_Entry_req;
        start_test();

        // Scenario 4: Results Transfer Verification
        $display("\n=========>  Test Scenario (%0d): Results Transfer (Aggregate Error). <=========", test_scenario_no++);
        reset();
        intf.tb_aggr_err = 16'hAAAA;
        intf.tb_rx_msginfo = 16'h0010; // partner_aggr_err = 1
        intf.tb_rx_data_field = 64'hBBBB;
        set_d2c_configuration(
            .task_clk_sampling    (2'b00 ),
            .task_pattern_setup   (3'b011),
            .task_data_pattern_sel(2'b00 ),
            .task_val_pattern_sel (2'b00 ),
            .task_lfsr_en         (1'b1  ),
            .task_pattern_mode    (1'b1  ),
            .task_burst_count     (16'd10),
            .task_idle_count      (16'd5 ),
            .task_iter_count      (16'd2 ),
            .task_compare_setup   (2'b01 )
        );
        start_test();
        if (intf.d2c_aggr_err == 16'h0001) $display("  MATCH: Aggregate error bit received correctly.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Aggregate error mismatch!"); fail_count++; $stop; end
        
        if (intf.d2c_perlane_err == 16'hBBBB) $display("  MATCH: Per-lane error field received correctly.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Per-lane error mismatch!"); fail_count++; $stop; end

        // Scenario 5: VALTRAINCENTER-like config (compare_setup=2, valid-lane mode)
        $display("\n=========>  Test Scenario (%0d): VALTRAINCENTER Config (Valid Lane). <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0020; // partner val_err=1 at bit[5]
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b010),
            .task_data_pattern_sel(2'b11), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b0), .task_pattern_mode(1'b0),
            .task_burst_count(16'd8), .task_idle_count(16'd0),
            .task_iter_count(16'd128), .task_compare_setup(2'd2)
        );
        start_test();
        if (intf.d2c_val_err == 1'b1 && intf.partner_valtraincenter_fail_flag == 1'b1)
            $display("  MATCH: Valid-lane fail flag set correctly.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Valid-lane fail flag mismatch!"); fail_count++; $stop; end

        // Scenario 6: DATATRAINCENTER1-like config (compare_setup=0, per-lane mode)
        $display("\n=========>  Test Scenario (%0d): DATATRAINCENTER1 Config (Per-Lane). <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0000_0000_0000_0004; // lane 2 fail
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b011),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd4096), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();
        if (intf.d2c_perlane_err == 16'h0004 && intf.partner_datatraincenter_fail_flag == 1'b1)
            $display("  MATCH: Per-lane fail flag set correctly for lane 2.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Per-lane fail flag mismatch!"); fail_count++; $stop; end

        // Scenario 7: Per-lane ALL PASS (fail_flag must be 0)
        $display("\n=========>  Test Scenario (%0d): Per-Lane All Pass. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0; // no lane errors
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd50), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();
        if (intf.partner_datatraincenter_fail_flag == 1'b0)
            $display("  MATCH: Per-lane all-pass, fail_flag=0.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Per-lane all-pass fail_flag mismatch!"); fail_count++; $stop; end

        // Scenario 8: Aggregate mode pass (bit[4]=0)
        $display("\n=========>  Test Scenario (%0d): Aggregate Mode Pass. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0000; // bit[4]=0 -> pass
        intf.tb_rx_data_field = 64'hFFFF; // per-lane irrelevant for aggr mode
        set_d2c_configuration(
            .task_clk_sampling(2'b01), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd50), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd1)
        );
        start_test();
        if (intf.partner_datatraincenter_fail_flag == 1'b0)
            $display("  MATCH: Aggregate pass, fail_flag=0.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Aggregate pass fail_flag mismatch!"); fail_count++; $stop; end

        // Scenario 9: Valid-lane pass (bit[5]=0, fail_flag must be 0)
        $display("\n=========>  Test Scenario (%0d): Valid Lane Pass. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0000; // bit[5]=0
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b010),
            .task_data_pattern_sel(2'b11), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b0), .task_pattern_mode(1'b0),
            .task_burst_count(16'd8), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd2)
        );
        start_test();
        if (intf.partner_valtraincenter_fail_flag == 1'b0)
            $display("  MATCH: Valid-lane pass, fail_flag=0.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Valid pass fail_flag mismatch!"); fail_count++; $stop; end

        // Scenario 10: Back-to-back without reset
        $display("\n=========>  Test Scenario (%0d): Back-to-Back #1 (no reset). <=========", test_scenario_no++);
        // Don't call reset() -- reuse previous state
        intf.tb_wait_timeout = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_rx_msginfo    = 16'h0010; // aggr fail
        intf.tb_rx_data_field = 64'hDEAD;
        set_d2c_configuration(
            .task_clk_sampling(2'b10), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b01), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd20), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd1)
        );
        start_test();
        if (intf.partner_datatraincenter_fail_flag == 1'b1 && intf.d2c_aggr_err == 16'h0001)
            $display("  MATCH: Back-to-back #1 aggr fail correct.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Back-to-back #1 mismatch!"); fail_count++; $stop; end

        $display("\n=========>  Test Scenario (%0d): Back-to-Back #2 (no reset). <=========", test_scenario_no++);
        intf.tb_rx_msginfo    = 16'h0000;
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd10), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();
        if (intf.partner_datatraincenter_fail_flag == 1'b0)
            $display("  MATCH: Back-to-back #2 all-pass correct.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Back-to-back #2 mismatch!"); fail_count++; $stop; end

        // Scenario 12: Burst mode
        $display("\n=========>  Test Scenario (%0d): Burst Mode. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b1),
            .task_burst_count(16'd10), .task_idle_count(16'd5),
            .task_iter_count(16'd3), .task_compare_setup(2'd0)
        );
        start_test();

        // Scenario 13: All lanes fail (0xFFFF)
        $display("\n=========>  Test Scenario (%0d): All Lanes Fail. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0030; // both val and aggr fail
        intf.tb_rx_data_field = 64'h0000_0000_0000_FFFF;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd50), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();
        if (intf.d2c_perlane_err == 16'hFFFF && intf.partner_datatraincenter_fail_flag == 1'b1)
            $display("  MATCH: All lanes fail correctly.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("All lanes fail mismatch!"); fail_count++; $stop; end

        // Scenario 14: Single lane fail (lane 15 only)
        $display("\n=========>  Test Scenario (%0d): Single Lane 15 Fail. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0000_0000_0000_8000;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd50), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();
        if (intf.d2c_perlane_err == 16'h8000 && intf.partner_datatraincenter_fail_flag == 1'b1)
            $display("  MATCH: Lane 15 fail correctly detected.");
        else begin repeat(5) $display("\t\t ************************** ERROR **************************"); $display("Lane 15 fail mismatch!"); fail_count++; $stop; end

        // Scenario 15: Clock sampling = Right Edge
        $display("\n=========>  Test Scenario (%0d): Clock Sampling Right Edge. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b10), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b00), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b1), .task_pattern_mode(1'b0),
            .task_burst_count(16'd50), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();

        // Scenario 16: Per-Lane ID pattern
        $display("\n=========>  Test Scenario (%0d): Per-Lane ID Pattern. <=========", test_scenario_no++);
        reset();
        intf.tb_rx_msginfo    = 16'h0;
        intf.tb_rx_data_field = 64'h0;
        set_d2c_configuration(
            .task_clk_sampling(2'b00), .task_pattern_setup(3'b001),
            .task_data_pattern_sel(2'b01), .task_val_pattern_sel(1'b0),
            .task_lfsr_en(1'b0), .task_pattern_mode(1'b0),
            .task_burst_count(16'd2048), .task_idle_count(16'd0),
            .task_iter_count(16'd1), .task_compare_setup(2'd0)
        );
        start_test();

        // Randomized Logic (200 iterations)
        $display("\nStarting 200 Randomized Iterations...");
        for (int i = 0; i < 200; i++) begin
            $display("\n=========>  Test Scenario (%0d): Randomized Test. <=========", test_scenario_no++);
            reset();
            intf.tb_wait_timeout    = ($urandom_range(0, 9) == 0); // 10%
            intf.tb_wrong_sb_msg_en = ($urandom_range(0, 9) == 0); // 10%
            intf.tb_wrong_sb_msg    = TRAINERROR_Entry_req;
            
            set_d2c_configuration(
                .task_clk_sampling    ($urandom_range(0, 2)),
                .task_pattern_setup   ($urandom_range(0, 7)),
                .task_data_pattern_sel($urandom_range(0, 2)),
                .task_val_pattern_sel ($urandom_range(0, 1)),
                .task_lfsr_en         ($urandom_range(0, 1)),
                .task_pattern_mode    ($urandom_range(0, 1)),
                .task_burst_count     ($urandom_range(1, 100)),
                .task_idle_count      ($urandom_range(0, 100)),
                .task_iter_count      ($urandom_range(1, 10)),
                .task_compare_setup   ($urandom_range(0, 2))
            );
            
            intf.tb_aggr_err    = $urandom();
            intf.tb_perlane_err = $urandom();
            intf.tb_val_err     = $urandom_range(0,1);
            intf.tb_clk_err     = $urandom_range(0,1);
            
            intf.tb_rx_msginfo    = $urandom();
            intf.tb_rx_data_field = $urandom();

            start_test();
        end

        if(fail_count == 0) begin
            $display("\n        ============================================       ");
            $display("      ==============                    ==============     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  The tests passed  ================== ");
            $display("    ================    Successfully    ================   ");
            $display("      ==============                    ==============     ");
            $display("        ============================================       \n\n"); 
        end else begin
            $display("\n        ============================================       ");
            $display("      ==============                    ==============     ");
            $display("    ================       FAILED       ================   ");
            $display("  ==================  Tests had errors  ================== ");
            $display("    ================    Check Log       ================   ");
            $display("      ==============                    ==============     ");
            $display("        ============================================       \n\n");
        end

        $display("\n========================================");
        $display("  Simulation Done!");
        $display("========================================\n");
        $stop;
    end

    // FSM State Monitor display
    always @(state_monitor) begin
        $display("%12t ps: FSM State = %s", $time, state_monitor.name());
    end

endmodule



