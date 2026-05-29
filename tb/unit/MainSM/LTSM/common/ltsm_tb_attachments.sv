`timescale 1ns/1ps

module ltsm_tb_attachments #(
        parameter real    SB_CLK_PERIOD        = 1.25       , // That means SB clk period = 1.25ns (800MHz).
        parameter integer TIMEOUT_CYCLES       = 'D8_000_000, // Number of lclk cycles to wait before declaring a timeout.
        parameter integer ANALOG_SETTLE_CYCLES = 'D10       , // Number of lclk cycles to wait the analog circuits in the MB to settle.
        parameter integer SB_DELAY             = 159          // SB msg transmitting delay in lclk cycles.
    ) (
        internal_ltsm_if intf
    );

    import UCIe_pkg::*;

    // Testbench overrides for partner completion
    reg       tb_partner_test_d2c_done_en;
    reg       tb_partner_test_d2c_done;

    // Local wires to capture wrapper outputs
    wire [1:0]  wrapper_mb_tx_trk_lane_sel;
    wire [1:0]  wrapper_mb_tx_clk_lane_sel;
    wire [1:0]  wrapper_mb_tx_val_lane_sel;
    wire [1:0]  wrapper_mb_tx_data_lane_sel;
    wire        wrapper_mb_rx_trk_lane_sel;
    wire        wrapper_mb_rx_clk_lane_sel;
    wire        wrapper_mb_rx_val_lane_sel;
    wire        wrapper_mb_rx_data_lane_sel;

    wire        mb_tx_pattern_en;
    wire [2:0]  mb_tx_pattern_setup;
    wire [2:0]  mb_rx_pattern_setup;
    wire        mb_tx_lfsr_en;
    wire        mb_tx_lfsr_rst;
    wire        mb_rx_lfsr_en;
    wire        mb_rx_lfsr_rst;
    wire [15:0] mb_rx_iter_count;
    wire [15:0] mb_rx_idle_count;
    wire [15:0] mb_rx_burst_count;
    wire        mb_rx_pattern_mode;
    wire        mb_rx_val_pattern_sel;
    wire [1:0]  mb_rx_data_pattern_sel;
    wire        mb_rx_compare_en;
    wire [1:0]  mb_rx_compare_setup;
    wire [11:0] mb_rx_max_err_thresh_perlane;
    wire [15:0] mb_rx_max_err_thresh_aggr;
    wire        mb_tx_clk_sampling_en;
    wire [1:0]  mb_tx_clk_sampling;
    wire        mb_tx_pattern_mode;
    wire [15:0] mb_tx_burst_count;
    wire [15:0] mb_tx_idle_count;
    wire [15:0] mb_tx_iter_count;
    wire [1:0]  mb_tx_data_pattern_sel;
    wire        mb_tx_val_pattern_sel;

    wire        wrapper_tx_sb_msg_valid;
    wire [7:0]  wrapper_tx_sb_msg;
    wire [15:0] wrapper_tx_msginfo;
    wire [63:0] wrapper_tx_data_field;
    wire        wrapper_partner_test_d2c_done;

    // ===================================================================== //
    //                      Sideband Propagation Delay Line                  //
    // ===================================================================== //
    localparam SB_DELAY_STAGES = SB_DELAY; // 127 SB cycles * 1.25ns / 1.0ns lclk period
    reg        val_shreg  [SB_DELAY_STAGES];
    msg_no_e   msg_shreg  [SB_DELAY_STAGES];
    reg [15:0] info_shreg [SB_DELAY_STAGES];
    reg [63:0] data_shreg [SB_DELAY_STAGES];

    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if (!intf.rst_n) begin
            for (int i = 0; i < SB_DELAY_STAGES; i++) begin
                val_shreg[i]  <= 1'b0;
                msg_shreg[i]  <= NOTHING;
                info_shreg[i] <= 16'h0;
                data_shreg[i] <= 64'h0;
            end
            intf.rx_sb_msg_valid <= 1'b0;
            intf.rx_sb_msg       <= NOTHING;
            intf.rx_msginfo      <= 16'h0;
            intf.rx_data_field   <= 64'h0;
        end else begin
            // Shift the registers
            for (int i = SB_DELAY_STAGES-1; i > 0; i--) begin
                val_shreg[i]  <= val_shreg[i-1];
                msg_shreg[i]  <= msg_shreg[i-1];
                info_shreg[i] <= info_shreg[i-1];
                data_shreg[i] <= data_shreg[i-1];
            end

            val_shreg[0]  <= intf.tb_muxed_tx_sb_msg_valid;
            msg_shreg[0]  <= intf.tb_muxed_tx_sb_msg;
            info_shreg[0] <= intf.tb_muxed_tx_msginfo;
            data_shreg[0] <= intf.tb_muxed_tx_data_field;

            // Output from delay line
            if (intf.tb_wait_timeout == 1'b0) begin
                intf.rx_sb_msg_valid <= val_shreg[SB_DELAY_STAGES-1];
                intf.rx_sb_msg       <= (intf.tb_wrong_sb_msg_en) ? intf.tb_wrong_sb_msg : msg_shreg[SB_DELAY_STAGES-1];
                intf.rx_msginfo      <= intf.tb_wrong_msginfo;
                intf.rx_data_field   <= intf.tb_wrong_data_field;

                if (!intf.tb_wrong_sb_msg_en) begin
                    intf.rx_msginfo      <= info_shreg[SB_DELAY_STAGES-1];
                    intf.rx_data_field   <= data_shreg[SB_DELAY_STAGES-1];
                end
            end else begin
                intf.rx_sb_msg_valid <= 1'b0;
            end
        end
    end

    // ===================================================================== //
    //                          MB Simulation Block.                         //
    // ===================================================================== //
    integer burst_counter, idle_counter, iter_counter;

    wire mb_tx_pattern_count_done = (iter_counter == mb_rx_iter_count && (intf.tb_wait_timeout == 0)) ? 1'b1 : 1'b0;

    reg         mb_rx_compare_done;
    reg  [15:0] mb_rx_perlane_pass;
    reg          mb_rx_val_pass;
    wire         mb_rx_aggr_pass = ~(|intf.tb_aggr_err);

    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if(!intf.rst_n) begin
            burst_counter      <= 0;
            idle_counter       <= 0;
            iter_counter       <= 0;
            mb_rx_compare_done <= 0;
            mb_rx_perlane_pass <= 16'hFFFF;
            mb_rx_val_pass     <= 1'b1;
            tb_partner_test_d2c_done_en <= 0;
            tb_partner_test_d2c_done    <= 0;
        end
        else begin
            if(mb_tx_pattern_en || intf.local_rx_pt_en) begin
                if(burst_counter != mb_rx_burst_count && iter_counter != mb_rx_iter_count) begin
                    burst_counter <= burst_counter + 1;
                end
                else if(idle_counter != mb_rx_idle_count && iter_counter != mb_rx_iter_count) begin
                    idle_counter <= idle_counter + 1;
                end
                else if(iter_counter != mb_rx_iter_count) begin
                    iter_counter  <= iter_counter + 1;
                    burst_counter <= 0;
                    idle_counter  <= 0;
                end
            end
            else begin
                burst_counter <= 0;
                idle_counter  <= 0;
                iter_counter  <= 0;
            end

            if(mb_tx_pattern_count_done == 1'b1) begin
                mb_rx_compare_done <= 1'b1;
                mb_rx_perlane_pass <= intf.tb_perlane_pass;
                mb_rx_val_pass     <= intf.tb_val_pass;
            end
            else begin
                mb_rx_compare_done <= 1'b0;
            end
        end
    end

    assign intf.mb_rx_compare_done       = mb_rx_compare_done;
    assign intf.mb_tx_pattern_count_done = mb_tx_pattern_count_done;
    assign intf.mb_rx_perlane_pass       = mb_rx_perlane_pass;
    assign intf.mb_rx_val_pass           = mb_rx_val_pass;
    assign intf.mb_rx_aggr_err           = intf.tb_aggr_err;

    // ===================================================================== //
    //                          Timeout 8ms Counter                          //
    // ===================================================================== //
    integer timeout_8ms_counter;
    always @(posedge intf.lclk or negedge intf.rst_n) begin : Timeout_8ms_counter_block
        if(!intf.rst_n) begin
            timeout_8ms_counter      <= 0;
            intf.timeout_8ms_occured <= 0;
        end
        else begin
            timeout_8ms_counter      <= (intf.timeout_timer_en)? timeout_8ms_counter + 1 : 0;
            intf.timeout_8ms_occured <= (timeout_8ms_counter < TIMEOUT_CYCLES)? 0 : 1;
        end
    end

    // ===================================================================== //
    //                          Analog Settle Counter                        //
    // ===================================================================== //
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
    assign intf.analog_settle_time_done = (analog_settle_counter >= ANALOG_SETTLE_CYCLES) && intf.analog_settle_timer_en;

    // ===================================================================== //
    //                      Wrapper D2C PT Top Instance                      //
    // ===================================================================== //
    wrapper_D2C_PT_top wrapper_D2C_PT_top_inst (
        .lclk                       (intf.lclk),
        .rst_n                      (intf.rst_n),

        .mb_rx_data_lane_mask       (intf.mb_rx_data_lane_mask),
        .local_test_d2c_done        (intf.local_test_d2c_done),
        .partner_test_d2c_done      (wrapper_partner_test_d2c_done),
        .d2c_perlane_pass           (intf.d2c_perlane_pass),
        .d2c_aggr_pass              (intf.d2c_aggr_pass),
        .d2c_val_pass               (intf.d2c_val_pass),

        // Tie mbinit_* to 0
        .mbinit_local_tx_pt_en      (1'b0),
        .mbinit_partner_tx_pt_en    (1'b0),
        .mbinit_d2c_clk_sampling    (2'b00),
        .mbinit_d2c_pattern_setup   (3'b000),
        .mbinit_d2c_data_pattern_sel(2'b00),
        .mbinit_d2c_val_pattern_sel (1'b0),
        .mbinit_d2c_pattern_mode    (1'b0),
        .mbinit_d2c_burst_count     (16'd0),
        .mbinit_d2c_idle_count      (16'd0),
        .mbinit_d2c_iter_count      (16'd0),
        .mbinit_d2c_compare_setup   (2'b00),

        // Connect mbtrain_* to corresponding intf.d2c_*
        .mbtrain_local_tx_pt_en     (intf.local_tx_pt_en),
        .mbtrain_partner_tx_pt_en   (intf.partner_tx_pt_en),
        .mbtrain_local_rx_pt_en     (intf.local_rx_pt_en),
        .mbtrain_partner_rx_pt_en   (intf.partner_rx_pt_en),
        .mbtrain_d2c_clk_sampling   (intf.d2c_clk_sampling),
        .mbtrain_d2c_pattern_setup  (intf.d2c_pattern_setup),
        .mbtrain_d2c_data_pattern_sel(intf.d2c_data_pattern_sel),
        .mbtrain_d2c_val_pattern_sel(intf.d2c_val_pattern_sel),
        .mbtrain_d2c_pattern_mode   (intf.d2c_pattern_mode),
        .mbtrain_d2c_burst_count    (intf.d2c_burst_count),
        .mbtrain_d2c_idle_count     (intf.d2c_idle_count),
        .mbtrain_d2c_iter_count     (intf.d2c_iter_count),
        .mbtrain_d2c_compare_setup  (intf.d2c_compare_setup),

        .cfg_max_err_thresh_perlane (intf.cfg_train4_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr    (intf.cfg_train4_max_err_thresh_aggr),

        // Mainband outputs connected to local wires to avoid multi-driver conflict
        .mb_tx_trk_lane_sel         (wrapper_mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel         (wrapper_mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel         (wrapper_mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel        (wrapper_mb_tx_data_lane_sel),
        .mb_rx_trk_lane_sel         (wrapper_mb_rx_trk_lane_sel),
        .mb_rx_clk_lane_sel         (wrapper_mb_rx_clk_lane_sel),
        .mb_rx_val_lane_sel         (wrapper_mb_rx_val_lane_sel),
        .mb_rx_data_lane_sel        (wrapper_mb_rx_data_lane_sel),

        .mb_tx_pattern_en           (mb_tx_pattern_en),
        .mb_tx_pattern_setup        (mb_tx_pattern_setup),
        .mb_rx_pattern_setup        (mb_rx_pattern_setup),
        .mb_tx_lfsr_en              (mb_tx_lfsr_en),
        .mb_tx_lfsr_rst             (mb_tx_lfsr_rst),
        .mb_rx_lfsr_en              (mb_rx_lfsr_en),
        .mb_rx_lfsr_rst             (mb_rx_lfsr_rst),
        .mb_rx_iter_count           (mb_rx_iter_count),
        .mb_rx_idle_count           (mb_rx_idle_count),
        .mb_rx_burst_count          (mb_rx_burst_count),
        .mb_rx_pattern_mode         (mb_rx_pattern_mode),
        .mb_rx_val_pattern_sel      (mb_rx_val_pattern_sel),
        .mb_rx_data_pattern_sel     (mb_rx_data_pattern_sel),
        .mb_rx_compare_en           (mb_rx_compare_en),
        .mb_rx_compare_setup        (mb_rx_compare_setup),
        .mb_rx_max_err_thresh_perlane(mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr  (mb_rx_max_err_thresh_aggr),
        .mb_tx_clk_sampling_en      (mb_tx_clk_sampling_en),
        .mb_tx_clk_sampling         (mb_tx_clk_sampling),
        .mb_tx_pattern_mode         (mb_tx_pattern_mode),
        .mb_tx_burst_count          (mb_tx_burst_count),
        .mb_tx_idle_count           (mb_tx_idle_count),
        .mb_tx_iter_count           (mb_tx_iter_count),
        .mb_tx_data_pattern_sel     (mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel      (mb_tx_val_pattern_sel),

        .mb_tx_pattern_count_done   (mb_tx_pattern_count_done),
        .mb_rx_compare_done         (mb_rx_compare_done),
        .mb_rx_aggr_pass            (mb_rx_aggr_pass),
        .mb_rx_perlane_pass         (mb_rx_perlane_pass),
        .mb_rx_val_pass             (mb_rx_val_pass),

        // SB outputs connected to local wires to avoid multi-driver conflict
        .tx_sb_msg_valid            (wrapper_tx_sb_msg_valid),
        .tx_sb_msg                  (wrapper_tx_sb_msg),
        .tx_msginfo                 (wrapper_tx_msginfo),
        .tx_data_field              (wrapper_tx_data_field),

        .rx_sb_msg_valid            (intf.rx_sb_msg_valid),
        .rx_sb_msg                  (intf.rx_sb_msg),
        .rx_msginfo                 (intf.rx_msginfo),
        .rx_data_field              (intf.rx_data_field)
    );

    // MUX wrapper and substate sideband messages onto tb_muxed signals
    assign intf.tb_muxed_tx_sb_msg_valid = wrapper_tx_sb_msg_valid || intf.tx_sb_msg_valid;
    assign intf.tb_muxed_tx_sb_msg       = wrapper_tx_sb_msg_valid ? msg_no_e'(wrapper_tx_sb_msg) : intf.tx_sb_msg;
    assign intf.tb_muxed_tx_msginfo      = wrapper_tx_sb_msg_valid ? wrapper_tx_msginfo : intf.tx_msginfo;
    assign intf.tb_muxed_tx_data_field   = wrapper_tx_sb_msg_valid ? wrapper_tx_data_field : intf.tx_data_field;

    // Procedural assignments to intf to avoid structural multi-driver conflicts.
    reg ptn_test_d2c_done_val;
    assign intf.partner_test_d2c_done = ptn_test_d2c_done_val;

    always @(*) begin
        if (tb_partner_test_d2c_done_en) begin
            ptn_test_d2c_done_val = tb_partner_test_d2c_done;
        end else begin
            ptn_test_d2c_done_val = wrapper_partner_test_d2c_done;
        end
    end

endmodule
