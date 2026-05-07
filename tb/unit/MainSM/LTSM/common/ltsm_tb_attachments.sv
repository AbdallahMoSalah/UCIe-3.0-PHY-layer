
`timescale 1ns/1ps

module ltsm_tb_attachments #(
        parameter real    SB_CLK_PERIOD        = 1.25       , // That means SB clk period = 1.25ns (800MHz). It's represented in 'ns' unit.
        parameter integer TIMEOUT_CYCLES       = 'D8_000_000, // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
        parameter integer ANALOG_SETTLE_CYCLES = 'D10         // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    ) (
        internal_ltsm_if intf
    );
    //  The Signals here can be accessed usnig "Hierarchical Reference" (XMR (Cross-Module Reference)).

    internal_ltsm_if d2c_mux_out_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // The d2c_mux collection interface.
    internal_ltsm_if d2c_mux_in1_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the module RX_D2C_PT
    internal_ltsm_if d2c_mux_in2_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the module TX_D2C_PT

    internal_ltsm_if to_tx_d2c_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the substate module to TX_D2C_PT module.
    internal_ltsm_if to_rx_d2c_if (.lclk(intf.lclk), .rst_n(intf.rst_n)); // It's from the substate module to RX_D2C_PT module.


    // ===================================================================== //
    //   __      ____      ____      ____      ____      ____      ____      //
    //     |____|    |____|    |____|    |____|    |____|    |____|    |__   //
    //                                                                       //
    //                          SB Clock Generation.                         //
    //      ____      ____      ____      ____      ____      ____      __   //
    //   __|    |____|    |____|    |____|    |____|    |____|    |____|     //
    // ===================================================================== //
    //For SB clk:
    reg sb_clk;
    initial begin
        sb_clk = 0;
        forever #(SB_CLK_PERIOD/2) sb_clk = ~sb_clk;
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (SB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    import UCIe_pkg::*;

    reg       rx_sb_msg_valid_reg  ; // A register to hold the valid signal for the received SB message.
    reg       tx_sb_msg_valid_pulse; // Pulse flag for tx_sb_msg_valid, stretched across SB_TX_PULSE_WIDTH lclk cycles.
    integer   sb_msg_waiting_time  ; // Counts SB clk cycles after activate.
    reg       activate_sb_tx_rx    ;
    msg_no_e  stable_tx_sb_msg     ; // lclk-registered copy of active TX message, safe to read on any edge.
    reg       first_sb_clk_edge = 1'b1;

    // Sample the active TX message every lclk cycle into a stable register.
    // This avoids cross-domain race when the sb_clk block reads it at cycle 127.
    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if (!intf.rst_n) begin
            stable_tx_sb_msg <= NOTHING;
        end else begin
            // When rx_pt_en=1: unit_RX_D2C_PT owns SB; tx_pt_en=1: unit_TX_D2C_PT owns SB; else RXDESKEW FSM owns SB.
            stable_tx_sb_msg <= intf.rx_pt_en ? d2c_mux_in1_if.tx_sb_msg :
                intf.tx_pt_en ? d2c_mux_in2_if.tx_sb_msg :
                intf.tx_sb_msg;
        end
    end

    reg first_lclk_edge = 1'b1;
    always @(posedge intf.lclk) begin
        if (first_lclk_edge) begin
            //$display("[%0t ps] ltsm_tb_attachments: LCLK is toggling!", $realtime);
            first_lclk_edge <= 1'b0;
        end
        if (tx_sb_msg_valid_pulse) begin
            //$display("[%0t ps] ltsm_tb_attachments: LCLK domain: tx_sb_msg_valid_pulse=1, stable_tx_sb_msg=%h, intf.tx_sb_msg=%h, d2c_mux_in1_if.tx_sb_msg=%h, rx_pt_en=%b",
            //    $realtime, stable_tx_sb_msg, intf.tx_sb_msg, d2c_mux_in1_if.tx_sb_msg, intf.rx_pt_en);
        end
    end

    always @(posedge sb_clk or negedge intf.rst_n) begin
        if (first_sb_clk_edge && intf.rst_n) begin
            //$display("[%0t ps] ltsm_tb_attachments: sb_clk is toggling!", $realtime);
            first_sb_clk_edge <= 1'b0;
        end

        if(!intf.rst_n) begin
            rx_sb_msg_valid_reg            <= 1'b0   ;
            d2c_mux_out_if.rx_sb_msg_valid <= 1'b0   ;
            sb_msg_waiting_time            <= 0      ;
            d2c_mux_out_if.rx_sb_msg       <= NOTHING;
            activate_sb_tx_rx              <= 1'b0   ;
        end
        else begin
            d2c_mux_out_if.rx_sb_msg_valid <= rx_sb_msg_valid_reg;
            intf.is_ltsm_out_of_reset      <= 1'b1; // Default to 'out of reset' for unit tests.

            if(intf.tb_wait_timeout == 1'b0) begin
                // Activate echo-back on the first SB clock where tx_sb_msg_valid_pulse is high.
                // stable_tx_sb_msg holds the lclk-registered active TX message — safe across domains.
                if(tx_sb_msg_valid_pulse == 1'b1 && activate_sb_tx_rx == 1'b0 && stable_tx_sb_msg != NOTHING) begin
                    activate_sb_tx_rx <= 1;
                end

                if(activate_sb_tx_rx == 1'b1) begin
                    sb_msg_waiting_time <= sb_msg_waiting_time + 1;

                    // Echo the captured stable TX message back as the partner's response:
                    if(sb_msg_waiting_time == 127) begin
                        rx_sb_msg_valid_reg            <=  1'b1;
                        d2c_mux_out_if.rx_sb_msg       <= (intf.tb_wrong_sb_msg_en) ? intf.tb_wrong_sb_msg : stable_tx_sb_msg;
                        d2c_mux_out_if.rx_msginfo      <=  intf.tb_rx_msginfo   ;
                        d2c_mux_out_if.rx_data_field   <=  intf.tb_rx_data_field;
                    end
                    // Deassert valid after 1 SB clk cycle:
                    else if(sb_msg_waiting_time == (127 + 1)) begin
                        rx_sb_msg_valid_reg <= 1'b0;
                        sb_msg_waiting_time <= 0;
                        activate_sb_tx_rx   <= 0;
                    end
                    else if (sb_msg_waiting_time == 10 || sb_msg_waiting_time == 50 || sb_msg_waiting_time == 100) begin
                        //$display("[%0t ps] ltsm_tb_attachments: sb_msg_waiting_time=%0d, stable_tx_sb_msg=%h", $realtime, sb_msg_waiting_time, stable_tx_sb_msg);
                    end
                end

            end else begin
                rx_sb_msg_valid_reg <= 1'b0;
            end

        end
    end

    // Pulse Generator module for the signal: "tx_sb_msg_valid".
    // Note we have to receive just a pulse of "tx_sb_msg_valid" for a 1 SB clk cycle at least using lclk because this module has to be inside the LTSM.
    // The generate pule on "tx_sb_msg_valid_pulse" will be High of 8 lclk cycles. Why 8 lclk cycles? because the number of happening sb_clk cycles will be > 1. (sb_clk cycles = 8 lclk period / 1 sb_clk period):
    //      - If lclk frequence = 1GHz:  ==>  sb_clk cycles = (8*1ns    / 1.25ns) = 6.4 cycles.
    //      - If lclk frequence = 2GHz:  ==>  sb_clk cycles = (8*0.5ns  / 1.25ns) = 3.2 cycles.
    //      - If lclk frequence = 4GHz:  ==>  sb_clk cycles = (8*0.25ns / 1.25ns) = 1.6 cycles.
    parameter SB_TX_PULSE_WIDTH = 8;
    reg [$clog2(SB_TX_PULSE_WIDTH-1):0] tx_sb_msg_valid_pulse_counter;
    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if(!intf.rst_n) begin
            tx_sb_msg_valid_pulse         <= 1'b0;
            tx_sb_msg_valid_pulse_counter <=  '0;
        end
        else begin
            // Monitor the mux output: covers both RXDESKEW FSM (2'b00) and unit_RX_D2C_PT (2'b01).
            // In 2'b00: intf.tx_sb_msg_valid is set by the RXDESKEW FSM.
            // In 2'b01: d2c_mux_in1_if.tx_sb_msg_valid is set by unit_RX_D2C_PT.
            // In 2'b10: d2c_mux_in2_if.tx_sb_msg_valid is set by unit_TX_D2C_PT.
            if ((intf.tx_sb_msg_valid || d2c_mux_in1_if.tx_sb_msg_valid || d2c_mux_in2_if.tx_sb_msg_valid) == 1'b1 || (tx_sb_msg_valid_pulse_counter > 0 && tx_sb_msg_valid_pulse_counter != SB_TX_PULSE_WIDTH-1)) begin
                tx_sb_msg_valid_pulse <= 1'b1;
                tx_sb_msg_valid_pulse_counter <= tx_sb_msg_valid_pulse_counter + 1'b1;
            end
            else if (tx_sb_msg_valid_pulse_counter == SB_TX_PULSE_WIDTH-1) begin
                tx_sb_msg_valid_pulse         <= 1'b0;
                tx_sb_msg_valid_pulse_counter <=  '0; // Reset so next assertion starts fresh
            end
            else begin
                tx_sb_msg_valid_pulse_counter <=  '0;
                tx_sb_msg_valid_pulse         <= 1'b0;
            end
        end
    end


    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (MB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    integer burst_counter, idle_counter, iter_counter; // Counters to track the number of "Burst", "Idle", and "Iteration" count in the MB.

    assign d2c_mux_out_if.mb_tx_pattern_count_done = (iter_counter == d2c_mux_out_if.mb_tx_iter_count && (intf.tb_wait_timeout == 0))? 1 : 0; // pattern count is done if (iteration completed) and (we don't want to test timeout)

    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if(!intf.rst_n) begin
            // Reset all the control signals to MB to their default values.
            burst_counter           <= 0;
            idle_counter            <= 0;
            iter_counter            <= 0;

            d2c_mux_out_if.mb_rx_perlane_err  <= 0;
            d2c_mux_out_if.mb_rx_val_err      <= 0;
            d2c_mux_out_if.mb_rx_clk_err      <= 0;
            d2c_mux_out_if.mb_rx_compare_done <= 0;
            d2c_mux_out_if.mb_rx_aggr_err     <= 0;
            d2c_mux_out_if.mb_rx_perlane_err  <= 0;
            d2c_mux_out_if.mb_rx_val_err      <= 0;
            d2c_mux_out_if.mb_rx_clk_err      <= 0;

        end
        // Here we can add any sequential behavior of the MB control signals if needed for the test scenarios.
        else begin
            // Send the data pattern:
            if(d2c_mux_out_if.mb_tx_pattern_en || intf.rx_pt_en) begin
                if(burst_counter != d2c_mux_out_if.mb_tx_burst_count && iter_counter != d2c_mux_out_if.mb_tx_iter_count) begin
                    burst_counter <= burst_counter + 1; // Increment the burst counter when the pattern is enabled (indicating a burst is being sent).
                end
                else if(idle_counter != d2c_mux_out_if.mb_tx_idle_count && iter_counter != d2c_mux_out_if.mb_tx_iter_count) begin
                    idle_counter <= idle_counter + 1; // Increment the idle counter when the burst count is reached.
                end
                else if(iter_counter != d2c_mux_out_if.mb_tx_iter_count) begin
                    iter_counter  <= iter_counter + 1; // Increment the iteration counter when both burst count and idle count are reached.
                    burst_counter <= 0               ; // Reset the burst counter at the end of each iteration.
                    idle_counter  <= 0               ; // Reset the idle counter at the end of each iteration.
                end
            end
            else begin
                burst_counter <= 0;
                idle_counter  <= 0;
                iter_counter  <= 0;
            end

            // Get the receiver result:
            if(d2c_mux_out_if.mb_tx_pattern_count_done == 1'b1) begin
                d2c_mux_out_if.mb_rx_compare_done <= 1                  ; // Indicate that the comparison is done after the pattern count is done.
                d2c_mux_out_if.mb_rx_aggr_err     <= intf.tb_aggr_err   ; // Update the aggregate error from the D2C block to MB after the comparison is done.
                d2c_mux_out_if.mb_rx_perlane_err  <= intf.tb_perlane_err;
                d2c_mux_out_if.mb_rx_val_err      <= intf.tb_val_err    ;
                d2c_mux_out_if.mb_rx_clk_err      <= intf.tb_clk_err    ;
            end
            else begin
                d2c_mux_out_if.mb_rx_compare_done <= 0; // Indicate that the comparison is done after the pattern count is done.
            end
        end
    end



    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------         (timeout_8ms_counter module)         ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer timeout_8ms_counter;
    always @(posedge intf.lclk or negedge intf.rst_n) begin : Timeout_8ms_counter_block
        if(!intf.rst_n) begin
            timeout_8ms_counter      <= 0;
            intf.timeout_8ms_occured <= 0;
        end
        else begin
            timeout_8ms_counter      <= (intf.timeout_timer_en)? timeout_8ms_counter + 1 : 0;
            intf.timeout_8ms_occured <= (timeout_8ms_counter < TIMEOUT_CYCLES)? 0 : 1; // Set timeout_8ms to 1 if the TIMEOUT counter reaches the defined TIMEOUT_CYCLES, otherwise keep it at 0.
        end
    end


    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------         (timeout_8ms_counter module)         ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer analog_settle_counter;
    always_ff @(posedge intf.lclk or negedge intf.rst_n) begin
        if (!intf.rst_n) begin
            analog_settle_counter <= '0;
        end else begin
            if (intf.analog_settle_timer_en) begin
                if (analog_settle_counter < ANALOG_SETTLE_CYCLES) begin
                    analog_settle_counter <= analog_settle_counter + 1;
                end
            end else begin
                analog_settle_counter <= '0;
            end
        end
    end
    assign intf.analog_settle_time_done = (analog_settle_counter >= ANALOG_SETTLE_CYCLES) && intf.analog_settle_timer_en; // Set timeout_8ms to 1 if the TIMEOUT counter reaches the defined TIMEOUT_CYCLES, otherwise keep it at 0.


    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               (D2C PT modules)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    assign d2c_mux_in1_if.cfg_train4_max_err_thresh_perlane = intf.cfg_train4_max_err_thresh_perlane;
    assign d2c_mux_in1_if.cfg_train4_max_err_thresh_aggr    = intf.cfg_train4_max_err_thresh_aggr;

    unit_RX_D2C_PT unit_RX_D2C_PT_inst (
        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        .substate_if(to_rx_d2c_if.rx_d2c2substate_mp),

        //=====================================//
        // Control Signals for the MB and SB:  //
        //=====================================//
        .mux_if(d2c_mux_in1_if.d2c2mux_mp)
    );

    unit_TX_D2C_PT unit_TX_D2C_PT_inst (
        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        .substate_if(to_tx_d2c_if.tx_d2c2substate_mp),

        //=====================================//
        // Control Signals for the MB and SB:  //
        //=====================================//
        .mux_if(d2c_mux_in2_if.d2c2mux_mp)
    );

    //   ====================================================================================================   //
    //   ========  This module to enable the connection for both of TX_D2C_PT and RX_D2C_PT modules  ========   //
    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\  //
    // |  -------------------------           (substate to d2c module)           ---------------------------  | //
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/  //
    //   ====================================================================================================   //
    //   ====================================================================================================   //
    always @(*) begin
        case({intf.tx_pt_en, intf.rx_pt_en})
            2'b00,
            2'b11,
            2'b01: begin
                intf.test_d2c_done        = to_rx_d2c_if.test_d2c_done;
                intf.d2c_aggr_err    = to_rx_d2c_if.d2c_aggr_err   ;
                intf.d2c_perlane_err = to_rx_d2c_if.d2c_perlane_err;
                intf.d2c_val_err     = to_rx_d2c_if.d2c_val_err    ;
                intf.d2c_clk_err     = to_rx_d2c_if.d2c_clk_err    ;
                intf.partner_valtraincenter_fail_flag  = to_tx_d2c_if.partner_valtraincenter_fail_flag ;
            end
            2'b10: begin // for TX_D2C_PT
                intf.test_d2c_done        = to_tx_d2c_if.test_d2c_done       ;
                intf.d2c_aggr_err         = to_tx_d2c_if.d2c_aggr_err        ;
                intf.d2c_perlane_err      = to_tx_d2c_if.d2c_perlane_err     ;
                intf.d2c_val_err          = to_tx_d2c_if.d2c_val_err         ;
                intf.d2c_clk_err          = to_tx_d2c_if.d2c_clk_err         ;
                intf.partner_valtraincenter_fail_flag  = to_tx_d2c_if.partner_valtraincenter_fail_flag ;
            end
        endcase
        to_rx_d2c_if.rx_pt_en          = intf.rx_pt_en          ;
        to_rx_d2c_if.tx_pt_en          = intf.tx_pt_en          ;
        // substate_timeout_8ms_occured removed from modport
        to_rx_d2c_if.d2c_clk_sampling  = intf.d2c_clk_sampling  ;
        to_rx_d2c_if.d2c_lfsr_en                  = intf.d2c_lfsr_en                 ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        to_rx_d2c_if.d2c_pattern_setup            = intf.d2c_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        to_rx_d2c_if.d2c_data_pattern_sel         = intf.d2c_data_pattern_sel        ; // Data pattern used during training: LFSR, ID, or all 0.
        to_rx_d2c_if.d2c_val_pattern_sel          = intf.d2c_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Held Low.
        to_rx_d2c_if.d2c_pattern_mode             = intf.d2c_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        to_rx_d2c_if.d2c_burst_count              = intf.d2c_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
        to_rx_d2c_if.d2c_idle_count               = intf.d2c_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        to_rx_d2c_if.d2c_iter_count               = intf.d2c_iter_count              ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
        to_rx_d2c_if.d2c_compare_setup            = intf.d2c_compare_setup           ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.

        to_tx_d2c_if.rx_pt_en          = intf.rx_pt_en          ;
        to_tx_d2c_if.tx_pt_en          = intf.tx_pt_en          ;
        // substate_timeout_8ms_occured removed from modport
        to_tx_d2c_if.d2c_clk_sampling  = intf.d2c_clk_sampling  ;
        to_tx_d2c_if.d2c_lfsr_en                  = intf.d2c_lfsr_en                 ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        to_tx_d2c_if.d2c_pattern_setup            = intf.d2c_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        to_tx_d2c_if.d2c_data_pattern_sel         = intf.d2c_data_pattern_sel        ; // Data pattern used during training: LFSR, ID, or all 0.
        to_tx_d2c_if.d2c_val_pattern_sel          = intf.d2c_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Held Low.
        to_tx_d2c_if.d2c_pattern_mode             = intf.d2c_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        to_tx_d2c_if.d2c_burst_count              = intf.d2c_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
        to_tx_d2c_if.d2c_idle_count               = intf.d2c_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        to_tx_d2c_if.d2c_iter_count               = intf.d2c_iter_count              ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
        to_tx_d2c_if.d2c_compare_setup            = intf.d2c_compare_setup           ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
    end







    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               (d2c_mux module)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    always @(*) begin
        case({intf.tx_pt_en, intf.rx_pt_en})
            2'b00: begin
                //=======================================================================================//
                // Control Signals from the LTSM to the MB direction: (LTSM prespective)                 //
                // LTSM -> MB                                                                            //
                //=======================================================================================//
                //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
                // Clock Sampling and Shapes Details Group:
                d2c_mux_out_if.mb_tx_clk_shape                = intf.mb_tx_clk_shape               ; // 0: Differential clocking, 1: Quadrature clocking.
                d2c_mux_out_if.mb_tx_continuous_or_strobe_clk = intf.mb_tx_continuous_or_strobe_clk; // 0: continuous mode clock, 1: strobe mode clock.
                d2c_mux_out_if.mb_tx_clk_sampling_en          = intf.mb_tx_clk_sampling_en         ; // Enable changing Clock sampling/PI phase control state.
                d2c_mux_out_if.mb_tx_clk_sampling             = intf.mb_tx_clk_sampling            ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

                // Tx Pattern Generator Setup Group:
                d2c_mux_out_if.mb_tx_pattern_en               = intf.mb_tx_pattern_en              ; // 1: Send pattern immediately, 0: Don't send pattern.
                d2c_mux_out_if.mb_tx_pattern_setup            = intf.mb_tx_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_mux_out_if.mb_tx_data_pattern_sel         = intf.mb_tx_data_pattern_sel        ; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
                d2c_mux_out_if.mb_tx_val_pattern_sel          = intf.mb_tx_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Held Low.
                d2c_mux_out_if.mb_tx_lfsr_en                  = intf.mb_tx_lfsr_en                 ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
                d2c_mux_out_if.mb_tx_lfsr_rst                 = intf.mb_tx_lfsr_rst                ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
                d2c_mux_out_if.mb_rx_lfsr_en                  = intf.mb_rx_lfsr_en                 ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
                d2c_mux_out_if.mb_rx_lfsr_rst                 = intf.mb_rx_lfsr_rst                ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

                // Tx Pattern Mode Setup Group:
                d2c_mux_out_if.mb_tx_pattern_mode             = intf.mb_tx_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_mux_out_if.mb_tx_burst_count              = intf.mb_tx_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_mux_out_if.mb_tx_idle_count               = intf.mb_tx_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_mux_out_if.mb_tx_iter_count               = intf.mb_tx_iter_count              ; // Iterations: Indicates the iteration count of bursts followed by idle.
                // input  mb_tx_pattern_count_done      ; // Asserted (=1) once MB completes the iter_count.

                // Receiver Comparison Setup & Errors
                d2c_mux_out_if.mb_rx_compare_en               = intf.mb_rx_compare_en              ; // 1: Enable the Rx comparison circuit, 0: Disable.
                d2c_mux_out_if.mb_rx_max_err_thresh_aggr      = intf.mb_rx_max_err_thresh_aggr     ; // Max error Threshold in aggregate comparison.
                d2c_mux_out_if.mb_rx_max_err_thresh_perlane   = intf.mb_rx_max_err_thresh_perlane  ; // Max error Threshold in per Lane comparison.
                d2c_mux_out_if.mb_rx_compare_setup            = intf.mb_rx_compare_setup           ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
                // input  mb_rx_aggr_err                ; // The total calculated Aggregate Errors on Rx.
                // input  mb_rx_perlane_err             ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
                // input  mb_rx_val_err                 ; // The error coming from Valid Lane receiver in MB.
                // input  mb_rx_clk_err                 ; // The error coming from Clock Lane receiver in MB.
                // input  mb_rx_compare_done            ; // From MB to LTSM to tell that comparison of burst_count is done.

                //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
                // MB Lane Control
                d2c_mux_out_if.mb_rx_data_lane_mask           = intf.mb_rx_data_lane_mask          ; // Describes the Functional Rx Lanes (Active Lanes).
                d2c_mux_out_if.mb_tx_data_lane_mask           = intf.mb_tx_data_lane_mask          ; // Describes the Functional Tx Lanes (Active Lanes).
                d2c_mux_out_if.mb_mapper_en                   = intf.mb_mapper_en                  ; // 0: Disable the mapper, 1: Enable the mapper.

                // Lane Behavior Control
                d2c_mux_out_if.mb_tx_clk_lane_sel             = intf.mb_tx_clk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                d2c_mux_out_if.mb_tx_data_lane_sel            = intf.mb_tx_data_lane_sel           ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                d2c_mux_out_if.mb_tx_val_lane_sel             = intf.mb_tx_val_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                d2c_mux_out_if.mb_tx_trk_lane_sel             = intf.mb_tx_trk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
                d2c_mux_out_if.mb_rx_clk_lane_sel             = intf.mb_rx_clk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
                d2c_mux_out_if.mb_rx_data_lane_sel            = intf.mb_rx_data_lane_sel           ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
                d2c_mux_out_if.mb_rx_val_lane_sel             = intf.mb_rx_val_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
                d2c_mux_out_if.mb_rx_trk_lane_sel             = intf.mb_rx_trk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

                // PHY Level Control & Analog Interface
                d2c_mux_out_if.phy_negotiated_speed           = intf.phy_negotiated_speed          ; // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
                d2c_mux_out_if.phy_rx_clock_lock_en           = intf.phy_rx_clock_lock_en          ; // Allow analog Rx circuit to Lock the coming clock.
                d2c_mux_out_if.phy_rx_track_lock_en           = intf.phy_rx_track_lock_en          ; // Allow analog Rx circuit to Lock the coming Track.
                d2c_mux_out_if.phy_rx_phase_detector_en       = intf.phy_rx_phase_detector_en      ; // Activate Phase Detector Circuit for IQ clock phase shift test.
                d2c_mux_out_if.phy_tx_tckn_shift_en           = intf.phy_tx_tckn_shift_en          ; // Activate circuits to calculate shift on partner TCKN_L.
                // input  phy_rx_tclkn_shift            ; // The required shift of the partner TCKN_L (range 0 to 12).
                // input  phy_rx_decrement_shift        ; // Direction of shift: 1b (earlier), 0b (later).
                d2c_mux_out_if.phy_rx_valvref_ctrl            = intf.phy_rx_valvref_ctrl           ; // Tell ADC the Rx Valid Lane Vref level to operate in.
                d2c_mux_out_if.phy_tx_val_pi_phase_ctrl       = intf.phy_tx_val_pi_phase_ctrl      ; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                for (int i = 0; i < 16; i++) begin
                    d2c_mux_out_if.phy_rx_datavref_ctrl[i]      = intf.phy_rx_datavref_ctrl[i]     ; // Tell ADC the Rx Data Lane Vref level to operate in.
                    d2c_mux_out_if.phy_tx_data_pi_phase_ctrl[i] = intf.phy_tx_data_pi_phase_ctrl[i]; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                end
                d2c_mux_out_if.phy_rx_deskew_ctrl             = intf.phy_rx_deskew_ctrl            ; // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
                d2c_mux_out_if.phy_tx_eq_preset_ctrl          = intf.phy_tx_eq_preset_ctrl         ; // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
                // input  phy_rx_clk_drift_cal_state    ; // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
                // input  phy_rx_clk_drift_cal_valid    ; // Tells LTSM if phy_rx_clk_drift_cal_state is ready.


                //=======================================================================================//
                // Control Signals from the LTSM states to the SB direction: (LTSM prespective)          //
                // LTSM -> SB                                                                            //
                //=======================================================================================//
                // For SB TX:
                d2c_mux_out_if.tx_sb_msg_valid = intf.tx_sb_msg_valid; // Tell the SB that the selected message is valid.
                d2c_mux_out_if.tx_sb_msg       = intf.tx_sb_msg      ; // Tell the Sideband the message that it should to send.
                d2c_mux_out_if.tx_msginfo      = intf.tx_msginfo     ; // MsgInfo field of the SB message.
                d2c_mux_out_if.tx_data_field   = intf.tx_data_field  ; // Data field of the SB message.

                // For SB RX:
                // input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
                // input rx_sb_msg      , // Get the Received SB msg.
                // input rx_msginfo     , // MsgInfo field of the SB message received.
                // input rx_data_field    // Data field of the SB message.
            end
            2'b11, // This case (2'b11) won't happen at all but I put it here to avoid unintentional latchs.
            2'b01: begin //if(intf.tx_pt_en == 0 && intf.rx_pt_en == 1)
                //=======================================================================================//
                // Control Signals from the LTSM to the MB direction: (LTSM prespective)                 //
                // LTSM -> MB                                                                            //
                //=======================================================================================//
                //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
                // Clock Sampling and Shapes Details Group:
                d2c_mux_out_if.mb_tx_clk_shape                = d2c_mux_in1_if.mb_tx_clk_shape               ; // 0: Differential clocking, 1: Quadrature clocking.
                d2c_mux_out_if.mb_tx_continuous_or_strobe_clk = d2c_mux_in1_if.mb_tx_continuous_or_strobe_clk; // 0: continuous mode clock, 1: strobe mode clock.
                d2c_mux_out_if.mb_tx_clk_sampling_en          = d2c_mux_in1_if.mb_tx_clk_sampling_en         ; // Enable changing Clock sampling/PI phase control state.
                d2c_mux_out_if.mb_tx_clk_sampling             = d2c_mux_in1_if.mb_tx_clk_sampling            ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

                // Tx Pattern Generator Setup Group:
                d2c_mux_out_if.mb_tx_pattern_en               = d2c_mux_in1_if.mb_tx_pattern_en              ; // 1: Send pattern immediately, 0: Don't send pattern.
                d2c_mux_out_if.mb_tx_pattern_setup            = d2c_mux_in1_if.mb_tx_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_mux_out_if.mb_tx_data_pattern_sel         = d2c_mux_in1_if.mb_tx_data_pattern_sel        ; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
                d2c_mux_out_if.mb_tx_val_pattern_sel          = d2c_mux_in1_if.mb_tx_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Held Low.
                d2c_mux_out_if.mb_tx_lfsr_en                  = d2c_mux_in1_if.mb_tx_lfsr_en                 ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
                d2c_mux_out_if.mb_tx_lfsr_rst                 = d2c_mux_in1_if.mb_tx_lfsr_rst                ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
                d2c_mux_out_if.mb_rx_lfsr_en                  = d2c_mux_in1_if.mb_rx_lfsr_en                 ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
                d2c_mux_out_if.mb_rx_lfsr_rst                 = d2c_mux_in1_if.mb_rx_lfsr_rst                ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

                // Tx Pattern Mode Setup Group:
                d2c_mux_out_if.mb_tx_pattern_mode             = d2c_mux_in1_if.mb_tx_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_mux_out_if.mb_tx_burst_count              = d2c_mux_in1_if.mb_tx_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_mux_out_if.mb_tx_idle_count               = d2c_mux_in1_if.mb_tx_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_mux_out_if.mb_tx_iter_count               = d2c_mux_in1_if.mb_tx_iter_count              ; // Iterations: Indicates the iteration count of bursts followed by idle.
                // input  mb_tx_pattern_count_done      ; // Asserted (=1) once MB completes the iter_count.

                // Receiver Comparison Setup & Errors
                d2c_mux_out_if.mb_rx_compare_en               = d2c_mux_in1_if.mb_rx_compare_en              ; // 1: Enable the Rx comparison circuit, 0: Disable.
                d2c_mux_out_if.mb_rx_max_err_thresh_aggr      = d2c_mux_in1_if.mb_rx_max_err_thresh_aggr     ; // Max error Threshold in aggregate comparison.
                d2c_mux_out_if.mb_rx_max_err_thresh_perlane   = d2c_mux_in1_if.mb_rx_max_err_thresh_perlane  ; // Max error Threshold in per Lane comparison.
                d2c_mux_out_if.mb_rx_compare_setup            = d2c_mux_in1_if.mb_rx_compare_setup           ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
                // input  mb_rx_aggr_err                ; // The total calculated Aggregate Errors on Rx.
                // input  mb_rx_perlane_err             ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
                // input  mb_rx_val_err                 ; // The error coming from Valid Lane receiver in MB.
                // input  mb_rx_clk_err                 ; // The error coming from Clock Lane receiver in MB.
                // input  mb_rx_compare_done            ; // From MB to LTSM to tell that comparison of burst_count is done.

                //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
                // MB Lane Control
                d2c_mux_out_if.mb_rx_data_lane_mask           = d2c_mux_in1_if.mb_rx_data_lane_mask          ; // Describes the Functional Rx Lanes (Active Lanes).
                d2c_mux_out_if.mb_tx_data_lane_mask           = d2c_mux_in1_if.mb_tx_data_lane_mask          ; // Describes the Functional Tx Lanes (Active Lanes).
                d2c_mux_out_if.mb_mapper_en                   = d2c_mux_in1_if.mb_mapper_en                  ; // 0: Disable the mapper, 1: Enable the mapper.

                // Lane Behavior Control
                d2c_mux_out_if.mb_tx_clk_lane_sel             = d2c_mux_in1_if.mb_tx_clk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                d2c_mux_out_if.mb_tx_data_lane_sel            = d2c_mux_in1_if.mb_tx_data_lane_sel           ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                d2c_mux_out_if.mb_tx_val_lane_sel             = d2c_mux_in1_if.mb_tx_val_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                d2c_mux_out_if.mb_tx_trk_lane_sel             = d2c_mux_in1_if.mb_tx_trk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
                d2c_mux_out_if.mb_rx_clk_lane_sel             = d2c_mux_in1_if.mb_rx_clk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
                d2c_mux_out_if.mb_rx_data_lane_sel            = d2c_mux_in1_if.mb_rx_data_lane_sel           ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
                d2c_mux_out_if.mb_rx_val_lane_sel             = d2c_mux_in1_if.mb_rx_val_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
                d2c_mux_out_if.mb_rx_trk_lane_sel             = d2c_mux_in1_if.mb_rx_trk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

                // PHY Level Control & Analog Interface
                d2c_mux_out_if.phy_negotiated_speed           = d2c_mux_in1_if.phy_negotiated_speed          ; // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
                d2c_mux_out_if.phy_rx_clock_lock_en           = d2c_mux_in1_if.phy_rx_clock_lock_en          ; // Allow analog Rx circuit to Lock the coming clock.
                d2c_mux_out_if.phy_rx_track_lock_en           = d2c_mux_in1_if.phy_rx_track_lock_en          ; // Allow analog Rx circuit to Lock the coming Track.
                d2c_mux_out_if.phy_rx_phase_detector_en       = d2c_mux_in1_if.phy_rx_phase_detector_en      ; // Activate Phase Detector Circuit for IQ clock phase shift test.
                d2c_mux_out_if.phy_tx_tckn_shift_en           = d2c_mux_in1_if.phy_tx_tckn_shift_en          ; // Activate circuits to calculate shift on partner TCKN_L.
                // input  phy_rx_tclkn_shift            ; // The required shift of the partner TCKN_L (range 0 to 12).
                // input  phy_rx_decrement_shift        ; // Direction of shift: 1b (earlier), 0b (later).
                d2c_mux_out_if.phy_rx_valvref_ctrl            = d2c_mux_in1_if.phy_rx_valvref_ctrl           ; // Tell ADC the Rx Valid Lane Vref level to operate in.
                d2c_mux_out_if.phy_tx_val_pi_phase_ctrl       = d2c_mux_in1_if.phy_tx_val_pi_phase_ctrl      ; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                for (int i = 0; i < 16; i++) begin
                    d2c_mux_out_if.phy_rx_datavref_ctrl[i]      = d2c_mux_in1_if.phy_rx_datavref_ctrl[i]     ; // Tell ADC the Rx Data Lane Vref level to operate in.
                    d2c_mux_out_if.phy_tx_data_pi_phase_ctrl[i] = d2c_mux_in1_if.phy_tx_data_pi_phase_ctrl[i]; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                end
                d2c_mux_out_if.phy_rx_deskew_ctrl             = d2c_mux_in1_if.phy_rx_deskew_ctrl            ; // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
                d2c_mux_out_if.phy_tx_eq_preset_ctrl          = d2c_mux_in1_if.phy_tx_eq_preset_ctrl         ; // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
                // input  phy_rx_clk_drift_cal_state    ; // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
                // input  phy_rx_clk_drift_cal_valid    ; // Tells LTSM if phy_rx_clk_drift_cal_state is ready.


                //=======================================================================================//
                // Control Signals from the LTSM states to the SB direction: (LTSM prespective)          //
                // LTSM -> SB                                                                            //
                //=======================================================================================//
                // For SB TX:
                d2c_mux_out_if.tx_sb_msg_valid                = d2c_mux_in1_if.tx_sb_msg_valid               ; // Tell the SB that the selected message is valid.
                d2c_mux_out_if.tx_sb_msg                      = d2c_mux_in1_if.tx_sb_msg                     ; // Tell the Sideband the message that it should to send.
                d2c_mux_out_if.tx_msginfo                     = d2c_mux_in1_if.tx_msginfo                    ; // MsgInfo field of the SB message.
                d2c_mux_out_if.tx_data_field                  = d2c_mux_in1_if.tx_data_field                 ; // Data field of the SB message.

                // For SB RX:
                // input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
                // input rx_sb_msg      , // Get the Received SB msg.
                // input rx_msginfo     , // MsgInfo field of the SB message received.
                // input rx_data_field    // Data field of the SB message.
            end
            2'b10: begin //if(intf.tx_pt_en == 1 && intf.rx_pt_en == 0)
                //=======================================================================================//
                // Control Signals from the LTSM to the MB direction: (LTSM prespective)                 //
                // LTSM -> MB                                                                            //
                //=======================================================================================//
                //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
                // Clock Sampling and Shapes Details Group:
                d2c_mux_out_if.mb_tx_clk_shape                = d2c_mux_in2_if.mb_tx_clk_shape               ; // 0: Differential clocking, 1: Quadrature clocking.
                d2c_mux_out_if.mb_tx_continuous_or_strobe_clk = d2c_mux_in2_if.mb_tx_continuous_or_strobe_clk; // 0: continuous mode clock, 1: strobe mode clock.
                d2c_mux_out_if.mb_tx_clk_sampling_en          = d2c_mux_in2_if.mb_tx_clk_sampling_en         ; // Enable changing Clock sampling/PI phase control state.
                d2c_mux_out_if.mb_tx_clk_sampling             = d2c_mux_in2_if.mb_tx_clk_sampling            ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

                // Tx Pattern Generator Setup Group:
                d2c_mux_out_if.mb_tx_pattern_en               = d2c_mux_in2_if.mb_tx_pattern_en              ; // 1: Send pattern immediately, 0: Don't send pattern.
                d2c_mux_out_if.mb_tx_pattern_setup            = d2c_mux_in2_if.mb_tx_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                d2c_mux_out_if.mb_tx_data_pattern_sel         = d2c_mux_in2_if.mb_tx_data_pattern_sel        ; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
                d2c_mux_out_if.mb_tx_val_pattern_sel          = d2c_mux_in2_if.mb_tx_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Held Low.
                d2c_mux_out_if.mb_tx_lfsr_en                  = d2c_mux_in2_if.mb_tx_lfsr_en                 ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
                d2c_mux_out_if.mb_tx_lfsr_rst                 = d2c_mux_in2_if.mb_tx_lfsr_rst                ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
                d2c_mux_out_if.mb_rx_lfsr_en                  = d2c_mux_in2_if.mb_rx_lfsr_en                 ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
                d2c_mux_out_if.mb_rx_lfsr_rst                 = d2c_mux_in2_if.mb_rx_lfsr_rst                ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

                // Tx Pattern Mode Setup Group:
                d2c_mux_out_if.mb_tx_pattern_mode             = d2c_mux_in2_if.mb_tx_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                d2c_mux_out_if.mb_tx_burst_count              = d2c_mux_in2_if.mb_tx_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
                d2c_mux_out_if.mb_tx_idle_count               = d2c_mux_in2_if.mb_tx_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                d2c_mux_out_if.mb_tx_iter_count               = d2c_mux_in2_if.mb_tx_iter_count              ; // Iterations: Indicates the iteration count of bursts followed by idle.
                // input  mb_tx_pattern_count_done      ; // Asserted (=1) once MB completes the iter_count.

                // Receiver Comparison Setup & Errors
                d2c_mux_out_if.mb_rx_compare_en               = d2c_mux_in2_if.mb_rx_compare_en              ; // 1: Enable the Rx comparison circuit, 0: Disable.
                d2c_mux_out_if.mb_rx_max_err_thresh_aggr      = d2c_mux_in2_if.mb_rx_max_err_thresh_aggr     ; // Max error Threshold in aggregate comparison.
                d2c_mux_out_if.mb_rx_max_err_thresh_perlane   = d2c_mux_in2_if.mb_rx_max_err_thresh_perlane  ; // Max error Threshold in per Lane comparison.
                d2c_mux_out_if.mb_rx_compare_setup            = d2c_mux_in2_if.mb_rx_compare_setup           ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
                // input  mb_rx_aggr_err                ; // The total calculated Aggregate Errors on Rx.
                // input  mb_rx_perlane_err             ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
                // input  mb_rx_val_err                 ; // The error coming from Valid Lane receiver in MB.
                // input  mb_rx_clk_err                 ; // The error coming from Clock Lane receiver in MB.
                // input  mb_rx_compare_done            ; // From MB to LTSM to tell that comparison of burst_count is done.

                //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
                // MB Lane Control
                d2c_mux_out_if.mb_rx_data_lane_mask           = d2c_mux_in2_if.mb_rx_data_lane_mask          ; // Describes the Functional Rx Lanes (Active Lanes).
                d2c_mux_out_if.mb_tx_data_lane_mask           = d2c_mux_in2_if.mb_tx_data_lane_mask          ; // Describes the Functional Tx Lanes (Active Lanes).
                d2c_mux_out_if.mb_mapper_en                   = d2c_mux_in2_if.mb_mapper_en                  ; // 0: Disable the mapper, 1: Enable the mapper.

                // Lane Behavior Control
                d2c_mux_out_if.mb_tx_clk_lane_sel             = d2c_mux_in2_if.mb_tx_clk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                d2c_mux_out_if.mb_tx_data_lane_sel            = d2c_mux_in2_if.mb_tx_data_lane_sel           ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                d2c_mux_out_if.mb_tx_val_lane_sel             = d2c_mux_in2_if.mb_tx_val_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                d2c_mux_out_if.mb_tx_trk_lane_sel             = d2c_mux_in2_if.mb_tx_trk_lane_sel            ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
                d2c_mux_out_if.mb_rx_clk_lane_sel             = d2c_mux_in2_if.mb_rx_clk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
                d2c_mux_out_if.mb_rx_data_lane_sel            = d2c_mux_in2_if.mb_rx_data_lane_sel           ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
                d2c_mux_out_if.mb_rx_val_lane_sel             = d2c_mux_in2_if.mb_rx_val_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
                d2c_mux_out_if.mb_rx_trk_lane_sel             = d2c_mux_in2_if.mb_rx_trk_lane_sel            ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

                // PHY Level Control & Analog Interface
                d2c_mux_out_if.phy_negotiated_speed           = d2c_mux_in2_if.phy_negotiated_speed          ; // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
                d2c_mux_out_if.phy_rx_clock_lock_en           = d2c_mux_in2_if.phy_rx_clock_lock_en          ; // Allow analog Rx circuit to Lock the coming clock.
                d2c_mux_out_if.phy_rx_track_lock_en           = d2c_mux_in2_if.phy_rx_track_lock_en          ; // Allow analog Rx circuit to Lock the coming Track.
                d2c_mux_out_if.phy_rx_phase_detector_en       = d2c_mux_in2_if.phy_rx_phase_detector_en      ; // Activate Phase Detector Circuit for IQ clock phase shift test.
                d2c_mux_out_if.phy_tx_tckn_shift_en           = d2c_mux_in2_if.phy_tx_tckn_shift_en          ; // Activate circuits to calculate shift on partner TCKN_L.
                // input  phy_rx_tclkn_shift            ; // The required shift of the partner TCKN_L (range 0 to 12).
                // input  phy_rx_decrement_shift        ; // Direction of shift: 1b (earlier), 0b (later).
                d2c_mux_out_if.phy_rx_valvref_ctrl            = d2c_mux_in2_if.phy_rx_valvref_ctrl           ; // Tell ADC the Rx Valid Lane Vref level to operate in.
                d2c_mux_out_if.phy_tx_val_pi_phase_ctrl       = d2c_mux_in2_if.phy_tx_val_pi_phase_ctrl      ; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                for (int i = 0; i < 16; i++) begin
                    d2c_mux_out_if.phy_rx_datavref_ctrl[i]      = d2c_mux_in2_if.phy_rx_datavref_ctrl[i]     ; // Tell ADC the Rx Data Lane Vref level to operate in.
                    d2c_mux_out_if.phy_tx_data_pi_phase_ctrl[i] = d2c_mux_in2_if.phy_tx_data_pi_phase_ctrl[i]; // Tell ADC the Tx Data Lane PI phase level (per-lane).
                end
                d2c_mux_out_if.phy_rx_deskew_ctrl             = d2c_mux_in2_if.phy_rx_deskew_ctrl            ; // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
                d2c_mux_out_if.phy_tx_eq_preset_ctrl          = d2c_mux_in2_if.phy_tx_eq_preset_ctrl         ; // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
                // input  phy_rx_clk_drift_cal_state    ; // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
                // input  phy_rx_clk_drift_cal_valid    ; // Tells LTSM if phy_rx_clk_drift_cal_state is ready.


                //=======================================================================================//
                // Control Signals from the LTSM states to the SB direction: (LTSM prespective)          //
                // LTSM -> SB                                                                            //
                //=======================================================================================//
                // For SB TX:
                d2c_mux_out_if.tx_sb_msg_valid                = d2c_mux_in2_if.tx_sb_msg_valid               ; // Tell the SB that the selected message is valid.
                d2c_mux_out_if.tx_sb_msg                      = d2c_mux_in2_if.tx_sb_msg                     ; // Tell the Sideband the message that it should to send.
                d2c_mux_out_if.tx_msginfo                     = d2c_mux_in2_if.tx_msginfo                    ; // MsgInfo field of the SB message.
                d2c_mux_out_if.tx_data_field                  = d2c_mux_in2_if.tx_data_field                 ; // Data field of the SB message.

                // For SB RX:
                // input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
                // input rx_sb_msg      , // Get the Received SB msg.
                // input rx_msginfo     , // MsgInfo field of the SB message received.
                // input rx_data_field    // Data field of the SB message.
            end
        endcase

        // These signals in comming from the MB and SB and pathing through the d2c_mux module.
        // For the LTSM, these signals are inputs so, they path directly to LTSM FSMs.
        intf.mb_tx_pattern_count_done   = d2c_mux_out_if.mb_tx_pattern_count_done  ; // Asserted (=1) once MB completes the iter_count.

        intf.mb_rx_aggr_err                       = d2c_mux_out_if.mb_rx_aggr_err            ; // The total calculated Aggregate Errors on Rx.
        intf.mb_rx_perlane_err                    = d2c_mux_out_if.mb_rx_perlane_err         ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
        intf.mb_rx_val_err                        = d2c_mux_out_if.mb_rx_val_err             ; // The error coming from Valid Lane receiver in MB.
        intf.mb_rx_clk_err                        = d2c_mux_out_if.mb_rx_clk_err             ; // The error coming from Clock Lane receiver in MB.
        intf.mb_rx_compare_done                   = d2c_mux_out_if.mb_rx_compare_done        ; // From MB to LTSM to tell that comparison of burst_count is done.

        // intf.phy_rx_tckn_shift                    = d2c_mux_out_if.phy_rx_tckn_shift         ; // The required shift of the partner TCKN_L (range 0 to 12).
        // intf.phy_rx_decrement_shift               = d2c_mux_out_if.phy_rx_decrement_shift    ; // Direction of shift: 1b (earlier), 0b (later).
        // intf.phy_rx_clk_drift_cal_state           = d2c_mux_out_if.phy_rx_clk_drift_cal_state; // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
        // intf.phy_rx_clk_drift_cal_valid           = d2c_mux_out_if.phy_rx_clk_drift_cal_valid; // Tells LTSM if phy_rx_clk_drift_cal_state is ready.

        intf.rx_sb_msg_valid                      = d2c_mux_out_if.rx_sb_msg_valid           ; // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        intf.rx_sb_msg                            = d2c_mux_out_if.rx_sb_msg                 ; // Get the Received SB msg.
        intf.rx_msginfo                           = d2c_mux_out_if.rx_msginfo                ; // MsgInfo field of the SB message received.
        intf.rx_data_field                        = d2c_mux_out_if.rx_data_field             ; // Data field of the SB message.


        d2c_mux_in1_if.mb_tx_pattern_count_done   = d2c_mux_out_if.mb_tx_pattern_count_done  ;
        d2c_mux_in1_if.mb_rx_aggr_err             = d2c_mux_out_if.mb_rx_aggr_err            ;
        d2c_mux_in1_if.mb_rx_perlane_err          = d2c_mux_out_if.mb_rx_perlane_err         ;
        d2c_mux_in1_if.mb_rx_val_err              = d2c_mux_out_if.mb_rx_val_err             ;
        d2c_mux_in1_if.mb_rx_clk_err              = d2c_mux_out_if.mb_rx_clk_err             ;
        d2c_mux_in1_if.mb_rx_compare_done         = d2c_mux_out_if.mb_rx_compare_done        ;
        d2c_mux_in1_if.phy_rx_tckn_shift          = d2c_mux_out_if.phy_rx_tckn_shift         ;
        d2c_mux_in1_if.phy_rx_decrement_shift     = d2c_mux_out_if.phy_rx_decrement_shift    ;
        // d2c_mux_in1_if.phy_rx_clk_drift_cal_state = d2c_mux_out_if.phy_rx_clk_drift_cal_state;
        // d2c_mux_in1_if.phy_rx_clk_drift_cal_valid = d2c_mux_out_if.phy_rx_clk_drift_cal_valid;
        d2c_mux_in1_if.rx_sb_msg_valid            = d2c_mux_out_if.rx_sb_msg_valid           ;
        d2c_mux_in1_if.rx_sb_msg                  = d2c_mux_out_if.rx_sb_msg                 ;
        d2c_mux_in1_if.rx_msginfo                 = d2c_mux_out_if.rx_msginfo                ;
        d2c_mux_in1_if.rx_data_field              = d2c_mux_out_if.rx_data_field             ;


        d2c_mux_in2_if.mb_tx_pattern_count_done   = d2c_mux_out_if.mb_tx_pattern_count_done  ;
        d2c_mux_in2_if.mb_rx_aggr_err             = d2c_mux_out_if.mb_rx_aggr_err            ;
        d2c_mux_in2_if.mb_rx_perlane_err          = d2c_mux_out_if.mb_rx_perlane_err         ;
        d2c_mux_in2_if.mb_rx_val_err              = d2c_mux_out_if.mb_rx_val_err             ;
        d2c_mux_in2_if.mb_rx_clk_err              = d2c_mux_out_if.mb_rx_clk_err             ;
        d2c_mux_in2_if.mb_rx_compare_done         = d2c_mux_out_if.mb_rx_compare_done        ;
        d2c_mux_in2_if.phy_rx_tckn_shift          = d2c_mux_out_if.phy_rx_tckn_shift         ;
        d2c_mux_in2_if.phy_rx_decrement_shift     = d2c_mux_out_if.phy_rx_decrement_shift    ;
        // d2c_mux_in2_if.phy_rx_clk_drift_cal_state = d2c_mux_out_if.phy_rx_clk_drift_cal_state;
        // d2c_mux_in2_if.phy_rx_clk_drift_cal_valid = d2c_mux_out_if.phy_rx_clk_drift_cal_valid;
        d2c_mux_in2_if.rx_sb_msg_valid            = d2c_mux_out_if.rx_sb_msg_valid           ;
        d2c_mux_in2_if.rx_sb_msg                  = d2c_mux_out_if.rx_sb_msg                 ;
        d2c_mux_in2_if.rx_msginfo                 = d2c_mux_out_if.rx_msginfo                ;
        d2c_mux_in2_if.rx_data_field              = d2c_mux_out_if.rx_data_field             ;
    end

endmodule

