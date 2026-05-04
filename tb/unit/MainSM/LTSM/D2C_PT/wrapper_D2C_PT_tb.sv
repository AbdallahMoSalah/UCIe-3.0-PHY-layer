`timescale 1ps / 1ps

module wrapper_D2C_PT_tb ();
    import UCIe_pkg::*;
    import LTSM_state_pkg::*;

    parameter LCLK_PERIOD    = 1*1000 ; // lclk = 1ns (1GHz), waveform x1000
    parameter TIMEOUT_LIMIT  = 100_000; // cycles for shortened timeout

    // Core clocks and resets
    reg lclk ;
    reg rst_n;

    // Interface Instantiation
    // 1. Interface simulating MBINIT
    internal_ltsm_if intf_mbinit (
        .lclk(lclk ),
        .rst_n(rst_n)
    );

    // 2. Interface simulating MBTRAIN
    internal_ltsm_if intf_mbtrain (
        .lclk(lclk ),
        .rst_n(rst_n)
    );

    // 3. Interface simulating MUX connection to MB and SB
    internal_ltsm_if intf_mux (
        .lclk(lclk ),
        .rst_n(rst_n)
    );

    // FSM State Mirroring for Monitoring
    typedef enum reg [3:0] {
        TX_PT_IDLE         = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_IDLE        ,
        TX_PT_START_REQ    = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_START_REQ   ,
        TX_PT_START_RESP   = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_START_RESP  ,
        TX_PT_CLR_ERR_REQ  = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_CLR_ERR_REQ ,
        TX_PT_CLR_ERR_RESP = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_CLR_ERR_RESP,
        TX_PT_PATTERN_GEN  = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_PATTERN_GEN ,
        TX_PT_RESULTS_REQ  = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_RESULTS_REQ ,
        TX_PT_RESULTS_RESP = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_RESULTS_RESP,
        TX_PT_END_REQ      = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_END_REQ     ,
        TX_PT_END_RESP     = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_END_RESP    ,
        TX_PT_DONE         = wrapper_D2C_PT_inst.TX_D2C_PT.TX_PT_DONE          
    } tx_fsm_state_t;

    typedef enum reg [3:0] {
        RX_PT_IDLE         = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_IDLE        ,
        RX_PT_START_REQ    = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_START_REQ   ,
        RX_PT_START_RESP   = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_START_RESP  ,
        RX_PT_CLR_ERR_REQ  = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_CLR_ERR_REQ ,
        RX_PT_CLR_ERR_RESP = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_CLR_ERR_RESP,
        RX_PT_PATTERN_GEN  = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_PATTERN_GEN ,
        RX_PT_COUNT_DONE_REQ  = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_COUNT_DONE_REQ ,
        RX_PT_COUNT_DONE_RESP = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_COUNT_DONE_RESP,
        RX_PT_END_REQ      = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_END_REQ     ,
        RX_PT_END_RESP     = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_END_RESP    ,
        RX_PT_DONE         = wrapper_D2C_PT_inst.RX_D2C_PT.RX_PT_DONE          
    } rx_fsm_state_t;

    tx_fsm_state_t tx_state_monitor;
    assign tx_state_monitor = tx_fsm_state_t'(wrapper_D2C_PT_inst.TX_D2C_PT.current_state);
    
    rx_fsm_state_t rx_state_monitor;
    assign rx_state_monitor = rx_fsm_state_t'(wrapper_D2C_PT_inst.RX_D2C_PT.current_state);

    // Sideband message Names from UCIe_pkg:
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::Start_Rx_Init_D_to_C_point_test_req;
    import UCIe_pkg::Start_Rx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::LFSR_clear_error_req;
    import UCIe_pkg::LFSR_clear_error_resp;
    import UCIe_pkg::Tx_Init_D_to_C_results_req;
    import UCIe_pkg::Tx_Init_D_to_C_results_resp;
    import UCIe_pkg::Rx_Init_D_to_C_results_req;
    import UCIe_pkg::Rx_Init_D_to_C_results_resp;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::End_Rx_Init_D_to_C_point_test_req;
    import UCIe_pkg::End_Rx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::NOTHING;

    // DUT Instantiation
    wrapper_D2C_PT wrapper_D2C_PT_inst (
        .mbinit_if(intf_mbinit.d2c2substate_mp),
        .mbtrain_if(intf_mbtrain.d2c2substate_mp),
        .current_ltsm_state_if(intf_mux.current_ltsm_state_mp),
        .mux_if(intf_mux.d2c2mux_mp)
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
    // Internal SB Responder (Echo Model on MUX interface)
    // -------------------------------------------------------------------------
    integer sb_delay_cnt = 0;
    msg_no_e capture_msg  = NOTHING;
    reg [15:0] capture_msginfo = 0;
    reg [63:0] capture_data_field = 0;
    reg        msg_responded= 0;

    // Testbench configuration variables for SB response
    msg_no_e tb_wrong_sb_msg = NOTHING;
    reg      tb_wrong_sb_msg_en = 0;
    reg      tb_wait_timeout = 0;
    reg [15:0] tb_rx_msginfo = 0;
    reg [63:0] tb_rx_data_field = 0;

    always @(posedge sb_clk or negedge rst_n) begin
        if (!rst_n) begin
            intf_mux.rx_sb_msg_valid <= 0;
            intf_mux.rx_sb_msg       <= msg_no_e'(0);
            intf_mux.rx_msginfo      <= 16'b0;
            intf_mux.rx_data_field   <= 64'b0;
            sb_delay_cnt         <= 0;
            capture_msg          <= NOTHING;
            capture_msginfo      <= 0;
            capture_data_field   <= 0;
            msg_responded        <= 0;
        end else begin
            if (intf_mux.rx_sb_msg_valid) begin
                intf_mux.rx_sb_msg_valid <= 0;
            end

            if (!intf_mux.tx_sb_msg_valid || intf_mux.tx_sb_msg != capture_msg) begin
                msg_responded <= 0;
            end

            if (intf_mux.tx_sb_msg_valid && sb_delay_cnt == 0 && !tb_wait_timeout && !msg_responded) begin
                capture_msg        <= intf_mux.tx_sb_msg;
                capture_msginfo    <= intf_mux.tx_msginfo;
                capture_data_field <= intf_mux.tx_data_field;
                sb_delay_cnt       <= 64; // Respond after 64 cycles
                msg_responded      <= 1;
            end else if (sb_delay_cnt > 1 && !tb_wait_timeout) begin
                sb_delay_cnt <= sb_delay_cnt - 1;
            end else if (sb_delay_cnt == 1 && !tb_wait_timeout) begin
                sb_delay_cnt <= 0;
                intf_mux.rx_sb_msg_valid <= 1;
                intf_mux.rx_sb_msg       <= (tb_wrong_sb_msg_en) ? msg_no_e'(tb_wrong_sb_msg) : capture_msg;
                intf_mux.rx_msginfo      <= (capture_msg == Tx_Init_D_to_C_results_resp || capture_msg == Rx_Init_D_to_C_results_resp || capture_msg == Start_Rx_Init_D_to_C_point_test_resp) ? tb_rx_msginfo : capture_msginfo;
                intf_mux.rx_data_field   <= (capture_msg == Tx_Init_D_to_C_results_resp || capture_msg == Rx_Init_D_to_C_results_resp || capture_msg == Start_Rx_Init_D_to_C_point_test_resp) ? tb_rx_data_field : capture_data_field;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Internal MB Behavioral Model (on MUX interface)
    // -------------------------------------------------------------------------
    reg [15:0] tb_aggr_err = 0;
    reg [15:0] tb_perlane_err = 0;
    reg        tb_val_err = 0;
    reg        tb_clk_err = 0;

    integer burst_cnt = 0, idle_cnt = 0, iter_cnt = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            burst_cnt <= 0;
            idle_cnt  <= 0;
            iter_cnt  <= 0;
            intf_mux.mb_tx_pattern_count_done <= 0;
            intf_mux.mb_rx_compare_done       <= 0;
            intf_mux.mb_rx_aggr_err           <= 0;
            intf_mux.mb_rx_perlane_err        <= 0;
            intf_mux.mb_rx_val_err            <= 0;
            intf_mux.mb_rx_clk_err            <= 0;
        end else if (intf_mux.mb_tx_pattern_en || intf_mux.mb_rx_compare_en) begin
            if (iter_cnt < intf_mux.mb_tx_iter_count) begin
                if (burst_cnt < intf_mux.mb_tx_burst_count) begin
                    burst_cnt <= burst_cnt + 1;
                end else if (idle_cnt < intf_mux.mb_tx_idle_count) begin
                    idle_cnt <= idle_cnt + 1;
                end else begin
                    iter_cnt  <= iter_cnt + 1;
                    burst_cnt <= 0;
                    idle_cnt  <= 0;
                end
            end else begin
                intf_mux.mb_tx_pattern_count_done <= 1;
                intf_mux.mb_rx_compare_done       <= 1;
                intf_mux.mb_rx_aggr_err           <= tb_aggr_err;
                intf_mux.mb_rx_perlane_err        <= tb_perlane_err;
                intf_mux.mb_rx_val_err            <= tb_val_err;
                intf_mux.mb_rx_clk_err            <= tb_clk_err;
            end
        end else begin
            intf_mux.mb_tx_pattern_count_done <= 0;
            intf_mux.mb_rx_compare_done       <= 0;
            burst_cnt <= 0;
            idle_cnt  <= 0;
            iter_cnt  <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // Timeout Counter
    // -------------------------------------------------------------------------
    integer timeout_cnt = 0;
    reg timeout_8ms_occured = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 0;
            timeout_8ms_occured <= 0;
        end else if ((tx_state_monitor != TX_PT_IDLE && tx_state_monitor != TX_PT_DONE) || 
                     (rx_state_monitor != RX_PT_IDLE && rx_state_monitor != RX_PT_DONE)) begin
            timeout_cnt <= timeout_cnt + 1;
            if (timeout_cnt >= TIMEOUT_LIMIT) timeout_8ms_occured <= 1;
        end else begin
            timeout_cnt <= 0;
            timeout_8ms_occured <= 0;
        end
    end

    // -------------------------------------------------------------------------
    // Test Control Tasks
    // -------------------------------------------------------------------------
    integer success_count         = 0; 
    integer fail_count            = 0; 

    task reset();
        rst_n = 0;
        
        intf_mbinit.tx_pt_en = 0;
        intf_mbinit.rx_pt_en = 0;
        intf_mbtrain.tx_pt_en = 0;
        intf_mbtrain.rx_pt_en = 0;
        intf_mux.current_ltsm_state = MBINIT;

        tb_wait_timeout = 0;
        tb_wrong_sb_msg_en = 0;
        tb_wrong_sb_msg = NOTHING;
        tb_aggr_err = 0;
        tb_perlane_err = 0;
        tb_val_err = 0;
        tb_clk_err = 0;
        tb_rx_msginfo = 0;
        tb_rx_data_field = 0;
        
        intf_mux.cfg_train4_max_err_thresh_perlane = 0;
        intf_mux.cfg_train4_max_err_thresh_aggr    = 0;
        
        repeat(5) @(posedge lclk);
        rst_n = 1;
        repeat(1) @(posedge lclk);
        $display("%12t ps: Reset released.", $time);
    endtask

    // Task to run the test and monitor the active substate interface
    // 'substate_idx': 0 for MBINIT, 1 for MBTRAIN
    // 'is_tx': 1 for TX test, 0 for RX test
    task start_test(input integer substate_idx, input integer is_tx);
        $display("%12t ps: Triggering test (Substate=%0s, Test=%0s).", $time, substate_idx==0 ? "MBINIT" : "MBTRAIN", is_tx==1 ? "TX" : "RX");
        @(posedge lclk);
        
        // Assert the correct enable signal based on arguments
        if (substate_idx == 0) begin
            if (is_tx) intf_mbinit.tx_pt_en = 1;
            else       intf_mbinit.rx_pt_en = 1;
        end else begin
            if (is_tx) intf_mbtrain.tx_pt_en = 1;
            else       intf_mbtrain.rx_pt_en = 1;
        end

        fork : test_execution
            begin
                // Wait for the correct test_d2c_done signal
                if (substate_idx == 0) begin
                    wait(intf_mbinit.test_d2c_done || timeout_8ms_occured);
                end else begin
                    wait(intf_mbtrain.test_d2c_done || timeout_8ms_occured);
                end

                @(posedge lclk);
                
                // De-assert signals
                if (substate_idx == 0) begin
                    intf_mbinit.tx_pt_en = 0;
                    intf_mbinit.rx_pt_en = 0;
                end else begin
                    intf_mbtrain.tx_pt_en = 0;
                    intf_mbtrain.rx_pt_en = 0;
                end

                if (timeout_8ms_occured) begin
                    if (tb_wait_timeout || tb_wrong_sb_msg_en) begin
                        $display("%12t ps: Test completed with expected timeout.", $time);
                        success_count++;
                    end else begin
                        repeat(5) $display("\t\t ************************** ERROR **************************");
                        $display("%12t ps: ERROR: Unexpected timeout occurred.", $time);
                        fail_count++;
                        $stop;
                    end
                end else begin // Done
                    if (tb_wait_timeout || tb_wrong_sb_msg_en) begin
                        repeat(5) $display("\t\t ************************** ERROR **************************");
                        $display("%12t ps: ERROR: Test completed but expected timeout.", $time);
                        fail_count++;
                        $stop;
                    end else begin
                        wait(tx_state_monitor == TX_PT_IDLE && rx_state_monitor == RX_PT_IDLE);
                        $display("%12t ps: Test completed successfully.", $time);
                        success_count++;
                    end
                end
                $display("________________________________(Success count = %0d, Fail count = %0d)________________________________\n", success_count, fail_count);
                disable test_execution;
            end
            begin
                #2_000_000_000; // Global watchdog 2ms
                $display("%12t ps: ERROR: Global watchdog timeout.", $time);
                fail_count++;
                disable test_execution;
            end
        join
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("==========================================================");
        $display("   STARTING D2C WRAPPER TESTBENCH                         ");
        $display("==========================================================");
        reset();

        // Configure default pattern params for tests
        intf_mbinit.d2c_pattern_mode  = 1;
        intf_mbinit.d2c_burst_count   = 100;
        intf_mbinit.d2c_idle_count    = 20;
        intf_mbinit.d2c_iter_count    = 5;
        intf_mbinit.d2c_clk_sampling  = 0;
        intf_mbinit.d2c_lfsr_en       = 0;
        intf_mbinit.d2c_pattern_setup = 3'b001; // Data pattern
        intf_mbinit.d2c_data_pattern_sel = 0;
        intf_mbinit.d2c_val_pattern_sel  = 0;
        intf_mbinit.d2c_compare_setup    = 0;

        intf_mbtrain.d2c_pattern_mode  = 1;
        intf_mbtrain.d2c_burst_count   = 50;
        intf_mbtrain.d2c_idle_count    = 10;
        intf_mbtrain.d2c_iter_count    = 3;
        intf_mbtrain.d2c_clk_sampling  = 0;
        intf_mbtrain.d2c_lfsr_en       = 0;
        intf_mbtrain.d2c_pattern_setup = 3'b010; // Valid pattern
        intf_mbtrain.d2c_data_pattern_sel = 0;
        intf_mbtrain.d2c_val_pattern_sel  = 0;
        intf_mbtrain.d2c_compare_setup    = 0;

        // -------------------------------------------------------------------------
        // Happy Scenario 1: MBINIT - TX Test
        // -------------------------------------------------------------------------
        $display("\n[Scenario 1] Running TX D2C Test from MBINIT...");
        intf_mux.current_ltsm_state = MBINIT;
        start_test(0, 1);

        // -------------------------------------------------------------------------
        // Happy Scenario 2: MBINIT - RX Test
        // -------------------------------------------------------------------------
        $display("\n[Scenario 2] Running RX D2C Test from MBINIT...");
        intf_mux.current_ltsm_state = MBINIT;
        start_test(0, 0);

        // -------------------------------------------------------------------------
        // Happy Scenario 3: MBTRAIN - TX Test
        // -------------------------------------------------------------------------
        $display("\n[Scenario 3] Running TX D2C Test from MBTRAIN...");
        intf_mux.current_ltsm_state = MBTRAIN;
        start_test(1, 1);

        // -------------------------------------------------------------------------
        // Happy Scenario 4: MBTRAIN - RX Test
        // -------------------------------------------------------------------------
        $display("\n[Scenario 4] Running RX D2C Test from MBTRAIN...");
        intf_mux.current_ltsm_state = MBTRAIN;
        start_test(1, 0);

        // -------------------------------------------------------------------------
        // End of Simulation
        // -------------------------------------------------------------------------
        if (fail_count == 0) begin
            $display("==========================================================");
            $display("   SIMULATION PASSED (%0d/%0d scenarios)", success_count, success_count);
            $display("==========================================================");
        end else begin
            $display("==========================================================");
            $display("   SIMULATION FAILED (%0d errors)", fail_count);
            $display("==========================================================");
        end
        $finish;
    end
endmodule
