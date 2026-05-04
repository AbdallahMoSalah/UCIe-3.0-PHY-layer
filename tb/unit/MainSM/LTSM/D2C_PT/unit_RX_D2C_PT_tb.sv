`timescale 1ps/1ps
module unit_RX_D2C_PT_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD    = 1*1000 ; // lclk = 1ns (1GHz), waveform x1000
    parameter TIMEOUT_LIMIT  = 700_000 ; // cycles for "8ms" timeout (shortened)

    // Core clocks and resets
    reg lclk ;
    reg rst_n;

    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // ===================================================================== //
    //                           Clock Generation                            //
    // ===================================================================== //
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // ===================================================================== //
    //   States names (mirror RTL localparams exactly)                        //
    // ===================================================================== //
    typedef enum reg [3:0] {
        RX_PT_IDLE            = unit_RX_D2C_PT_inst.RX_PT_IDLE           ,
        RX_PT_START_REQ       = unit_RX_D2C_PT_inst.RX_PT_START_REQ      ,
        RX_PT_START_RESP      = unit_RX_D2C_PT_inst.RX_PT_START_RESP     ,
        RX_PT_CLR_ERR_REQ     = unit_RX_D2C_PT_inst.RX_PT_CLR_ERR_REQ   ,
        RX_PT_CLR_ERR_RESP    = unit_RX_D2C_PT_inst.RX_PT_CLR_ERR_RESP  ,
        RX_PT_PATTERN_GEN     = unit_RX_D2C_PT_inst.RX_PT_PATTERN_GEN   ,
        RX_PT_COUNT_DONE_REQ  = unit_RX_D2C_PT_inst.RX_PT_COUNT_DONE_REQ,
        RX_PT_COUNT_DONE_RESP = unit_RX_D2C_PT_inst.RX_PT_COUNT_DONE_RESP,
        RX_PT_END_REQ         = unit_RX_D2C_PT_inst.RX_PT_END_REQ        ,
        RX_PT_END_RESP        = unit_RX_D2C_PT_inst.RX_PT_END_RESP       ,
        RX_PT_DONE            = unit_RX_D2C_PT_inst.RX_PT_DONE
    } fsm_state_t;

    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_RX_D2C_PT_inst.current_state);

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------      (Instance of the RX_D2C_PT module)      ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    unit_RX_D2C_PT unit_RX_D2C_PT_inst (
        .substate_if(intf.rx_d2c2substate_mp),
        .mux_if     (intf.d2c2mux_mp        )
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------             (Internal SB Responder)           ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    reg [7:0] sb_delay_cnt = 0;
    msg_no_e  echo_msg     = NOTHING;
    reg       msg_responded= 0;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            intf.rx_sb_msg_valid <= 0;
            intf.rx_sb_msg       <= NOTHING;
            sb_delay_cnt         <= 0;
            echo_msg             <= NOTHING;
            msg_responded        <= 0;
        end else begin
            if (intf.rx_sb_msg_valid) begin
                intf.rx_sb_msg_valid <= 0;
            end

            if (!intf.tx_sb_msg_valid || intf.tx_sb_msg != echo_msg) begin
                msg_responded <= 0;
            end

            if (intf.tx_sb_msg_valid && sb_delay_cnt == 0 && !intf.tb_wait_timeout && !msg_responded) begin
                echo_msg      <= intf.tx_sb_msg;
                sb_delay_cnt  <= 10; // Respond after 10 cycles
                msg_responded <= 1;
            end else if (sb_delay_cnt > 1 && !intf.tb_wait_timeout) begin
                sb_delay_cnt <= sb_delay_cnt - 1;
            end else if (sb_delay_cnt == 1 && !intf.tb_wait_timeout) begin
                sb_delay_cnt <= 0;
                intf.rx_sb_msg_valid <= 1;
                if (intf.tb_wrong_sb_msg_en) begin
                    intf.rx_sb_msg <= intf.tb_wrong_sb_msg;
                    $display("%10t ps: SB Echoing WRONG message: %s", $realtime(), intf.tb_wrong_sb_msg.name());
                end else begin
                    intf.rx_sb_msg <= echo_msg;
                    $display("%10t ps: SB Echoing message: %s", $realtime(), echo_msg.name());
                end
            end
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               (Internal MB Model)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    reg [31:0] mb_delay_cnt = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            intf.mb_tx_pattern_count_done <= 0;
            intf.mb_rx_compare_done       <= 0;
            mb_delay_cnt                  <= 0;
        end else begin
            // Pattern generation simulation
            if (intf.mb_tx_pattern_en && mb_delay_cnt == 0) begin
                mb_delay_cnt <= 50; // Simulate pattern gen for 50 cycles
                intf.mb_tx_pattern_count_done <= 0;
            end else if (mb_delay_cnt > 0) begin
                mb_delay_cnt <= mb_delay_cnt - 1;
                if (mb_delay_cnt == 1) begin
                    intf.mb_tx_pattern_count_done <= 1;
                end
            end else if (!intf.mb_tx_pattern_en) begin
                intf.mb_tx_pattern_count_done <= 0;
            end

            // RX Comparison simulation
            if (intf.mb_rx_compare_en) begin
                intf.mb_rx_compare_done <= 1; // Always done if enabled for unit test
            end else begin
                intf.mb_rx_compare_done <= 0;
            end
        end
    end

    // Error and Config signals
    assign intf.mb_rx_aggr_err    = intf.tb_aggr_err;
    assign intf.mb_rx_perlane_err = intf.tb_perlane_err;
    assign intf.mb_rx_val_err     = intf.tb_val_err;
    assign intf.mb_rx_clk_err     = intf.tb_clk_err;

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (Internal Timer)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer timeout_cnt = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 0;
            intf.timeout_8ms_occured <= 0;
        end else if (intf.tb_wait_timeout || intf.tb_wrong_sb_msg_en) begin
            if (timeout_cnt < TIMEOUT_LIMIT) begin
                timeout_cnt <= timeout_cnt + 1;
                intf.timeout_8ms_occured <= 0;
            end else begin
                intf.timeout_8ms_occured <= 1;
            end
        end else begin
            timeout_cnt <= 0;
            intf.timeout_8ms_occured <= 0;
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task:)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        $display("%10t ps: Resetting...", $realtime());
        @(posedge lclk);
        rst_n                          <= 0;
        intf.rx_pt_en                  <= 0;
        intf.tx_pt_en                  <= 0;
        intf.tb_aggr_err               <= 0;
        intf.tb_perlane_err            <= 0;
        intf.tb_val_err                <= 0;
        intf.tb_clk_err                <= 0;
        intf.tb_wait_timeout           <= 0;
        intf.tb_wrong_sb_msg_en        <= 0;
        intf.tb_wrong_sb_msg           <= NOTHING;
        intf.tb_rx_msginfo             <= 16'b0;
        intf.tb_rx_data_field          <= 64'b0;

        // D2C Configuration
        intf.d2c_clk_sampling          <= 0;
        intf.d2c_lfsr_en               <= 0;
        intf.d2c_pattern_setup         <= 0;
        intf.d2c_data_pattern_sel      <= 0;
        intf.d2c_val_pattern_sel       <= 0;
        intf.d2c_pattern_mode          <= 0;
        intf.d2c_burst_count           <= 0;
        intf.d2c_idle_count            <= 0;
        intf.d2c_iter_count            <= 0;
        intf.d2c_compare_setup         <= 0;
        intf.cfg_train4_max_err_thresh_perlane <= 0;
        intf.cfg_train4_max_err_thresh_aggr    <= 0;
        repeat(5) @(posedge lclk);
        rst_n <= 1;
        repeat(5) @(posedge lclk);
        $display("%10t ps: Reset released.", $realtime());
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------           (Set D2C Configurations)           ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task set_d2c_configuration (
            input reg [1:0]  task_clk_sampling        ,
            input reg [2:0]  task_pattern_setup        ,
            input reg [1:0]  task_data_pattern_sel     ,
            input reg        task_val_pattern_sel      ,
            input reg        task_lfsr_en              ,
            input reg        task_pattern_mode         ,
            input reg [15:0] task_burst_count          ,
            input reg [15:0] task_idle_count           ,
            input reg [15:0] task_iter_count           ,
            input reg [1:0]  task_compare_setup        ,
            input reg [15:0] task_aggr_err_thresh      ,
            input reg [15:0] task_perlane_err_thresh
        );
        intf.d2c_clk_sampling                  = task_clk_sampling      ;
        intf.d2c_pattern_setup                 = task_pattern_setup      ;
        intf.d2c_data_pattern_sel              = task_data_pattern_sel   ;
        intf.d2c_val_pattern_sel               = task_val_pattern_sel    ;
        intf.d2c_lfsr_en                       = task_lfsr_en            ;
        intf.d2c_pattern_mode                  = task_pattern_mode       ;
        intf.d2c_burst_count                   = task_burst_count        ;
        intf.d2c_idle_count                    = task_idle_count         ;
        intf.d2c_iter_count                    = task_iter_count         ;
        intf.d2c_compare_setup                 = task_compare_setup      ;
        intf.cfg_train4_max_err_thresh_aggr    = task_aggr_err_thresh    ;
        intf.cfg_train4_max_err_thresh_perlane = task_perlane_err_thresh ;
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               ( Start Test Task)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer success_count = 0;
    integer fail_count    = 0;
    integer test_no       = 1;

    task start_test();
        $display("\n=========> Test Scenario (%0d) <==========", test_no++);
        fork : test_execution
            begin
                @(posedge lclk);
                intf.rx_pt_en <= 1'b1;
                $display("%10t ps: rx_pt_en asserted.", $realtime());

                // Wait for done or error
                wait(intf.test_d2c_done || intf.timeout_8ms_occured);
                @(posedge lclk);
                intf.rx_pt_en <= 1'b0;

                if (intf.timeout_8ms_occured) begin
                    if (intf.tb_wait_timeout || intf.tb_wrong_sb_msg_en) begin
                        $display("%10t ps: Test passed: Timeout/Abort reached as expected.", $realtime());
                        success_count++;
                    end else begin
                        $display("%10t ps: Test FAILED: Unexpected timeout.", $realtime());
                        fail_count++;
                    end
                end else begin
                    wait(current_state == RX_PT_IDLE); // Stay for 1 cycle as per RTL
                    $display("%10t ps: Test passed: Done successfully.", $realtime());
                    success_count++;
                end
                disable test_execution;
            end
            begin
                #1_000_000_000; // Global watchdog (1ms)
                $display("%10t ps: Test FAILED: Watchdog timeout.", $realtime());
                fail_count++;
                disable test_execution;
            end
        join
    endtask

    // Main initial block
    initial begin
        reset();
        $monitor("%10t ps : FSM state = \"%s\".", $realtime(), current_state.name());

        // Scenario 1: Happy path
        $display("Scenario 1: Happy Path - Valid Lane Compare");
        set_d2c_configuration(
            .task_clk_sampling    (2'b00 ),
            .task_pattern_setup   (3'b010),
            .task_data_pattern_sel(2'b00 ),
            .task_val_pattern_sel (1'b0  ),
            .task_lfsr_en         (1'b0  ),
            .task_pattern_mode    (1'b0  ),
            .task_burst_count     (16'd1 ),
            .task_idle_count      (16'd0 ),
            .task_iter_count      (16'd1 ),
            .task_compare_setup   (2'b10 ),
            .task_aggr_err_thresh   (16'h0000),
            .task_perlane_err_thresh(16'h0000)
        );
        start_test();
        reset();

        // Scenario 2: Timeout Test (No SB response)
        $display("Scenario 2: Timeout Test - No SB response");
        intf.tb_wait_timeout = 1;
        start_test();
        reset();

        // Scenario 3: Aggregate Compare
        $display("Scenario 3: Aggregate Compare");
        set_d2c_configuration(
            .task_clk_sampling    (2'b01 ),
            .task_pattern_setup   (3'b001),
            .task_data_pattern_sel(2'b00 ),
            .task_val_pattern_sel (1'b0  ),
            .task_lfsr_en         (1'b1  ),
            .task_pattern_mode    (1'b0  ),
            .task_burst_count     (16'd10),
            .task_idle_count      (16'd0 ),
            .task_iter_count      (16'd1 ),
            .task_compare_setup   (2'b01 ),
            .task_aggr_err_thresh   (16'h00FF),
            .task_perlane_err_thresh(16'h0000)
        );
        intf.tb_aggr_err = 16'h00AA;
        start_test();
        reset();

        // Scenario 4: Partner sends TRAINERROR Entry req (Now expecting an abort/timeout since state is removed)
        $display("Scenario 4: Partner sends TRAINERROR Entry req");
        intf.tb_wrong_sb_msg_en = 1;
        intf.tb_wrong_sb_msg    = TRAINERROR_Entry_req;
        set_d2c_configuration(
            .task_clk_sampling    (2'b00 ),
            .task_pattern_setup   (3'b010),
            .task_data_pattern_sel(2'b00 ),
            .task_val_pattern_sel (1'b0  ),
            .task_lfsr_en         (1'b0  ),
            .task_pattern_mode    (1'b0  ),
            .task_burst_count     (16'd1 ),
            .task_idle_count      (16'd0 ),
            .task_iter_count      (16'd1 ),
            .task_compare_setup   (2'b10 ),
            .task_aggr_err_thresh   (16'h0000),
            .task_perlane_err_thresh(16'h0000)
        );
        start_test();
        reset();

        // -----------------------------------------------------------------
        // Randomized Logic (100 iterations)
        // -----------------------------------------------------------------
        for (int i = 0; i < 100; i++) begin
            $display("\n--- Random Iteration %0d ---", i+1);

            // Randomize flags (with lower probability for errors/timeouts to see more "happy" paths)
            intf.tb_wait_timeout    = ($urandom_range(0, 9) == 0); // 10% chance
            intf.tb_wrong_sb_msg_en = ($urandom_range(0, 9) == 0); // 10% chance
            intf.tb_wrong_sb_msg    = TRAINERROR_Entry_req;

            set_d2c_configuration(
                .task_clk_sampling    ($urandom_range(0, 2)),
                .task_pattern_setup   ($urandom_range(0, 7)),
                .task_data_pattern_sel($urandom_range(0, 2)),
                .task_val_pattern_sel ($urandom_range(0, 2)),
                .task_lfsr_en         ($urandom_range(0, 1)),
                .task_pattern_mode    ($urandom_range(0, 1)),
                .task_burst_count     ($urandom_range(1, 100)), // Limited to keep sim fast
                .task_idle_count      ($urandom_range(0, 2000)),
                .task_iter_count      ($urandom_range(1, 40)),
                .task_compare_setup   ($urandom_range(0, 3)),
                .task_aggr_err_thresh   ($urandom()),
                .task_perlane_err_thresh($urandom())
            );

            // Randomize error signals from PHY/MB
            intf.tb_aggr_err    = $urandom();
            intf.tb_perlane_err = $urandom();
            intf.tb_val_err     = $urandom_range(0,1);
            intf.tb_clk_err     = $urandom_range(0,1);

            start_test();
            reset();
        end

        // Summary
        $display("\n========================================");
        $display("  Simulation Done!");
        $display("  Success: %0d", success_count);
        $display("  Fail:    %0d", fail_count);
        $display("========================================\n");

        if (fail_count == 0) begin
            $display("CONGRATULATIONS! ALL TESTS PASSED.");
        end

        $stop;
    end

endmodule


