`timescale 1ns/1ps

module ltsm_tb_attachments #(
        parameter real    SB_CLK_PERIOD        = 1.25       , // That means SB clk period = 1.25ns (800MHz).
        parameter integer TIMEOUT_CYCLES       = 'D8_000_000, // Number of lclk cycles to wait before declaring a timeout.
        parameter integer ANALOG_SETTLE_CYCLES = 'D10       , // Number of lclk cycles to wait the analog circuits in the MB to settle.
        parameter integer SB_DELAY             = 159        , // SB msg transmitting delay in lclk cycles.
        parameter bit     ENABLE_LOOPBACK      = 1'b1       , // 1: Enable local sideband loopback, 0: Disable.
        parameter integer MB_DELAY             = 10         ,
        parameter integer MIN_VAL_VREF_CODE    = 10         ,
        parameter integer MAX_VAL_VREF_CODE    = 16         ,
        parameter integer MIN_DATA_VREF_CODE   = 10         ,
        parameter integer MAX_DATA_VREF_CODE   = 16         ,
        parameter integer MIN_VAL_PI_CODE      = 1          ,
        parameter integer MAX_VAL_PI_CODE      = 16         ,
        parameter integer MIN_DATA_PI_CODE     = 1          ,
        parameter integer MAX_DATA_PI_CODE     = 16         ,
        parameter integer MIN_DESKEW_CODE      = 0          ,
        parameter integer MAX_DESKEW_CODE      = 16
    ) (
        interface intf
    );

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

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

    // =========================================================================
    // Wires between unit_D2C_sweep and wrapper_D2C_PT_top
    // =========================================================================
    wire        local_tx_pt_en;
    wire        local_rx_pt_en;
    wire        partner_tx_pt_en;
    wire        partner_rx_pt_en;
    wire [1:0]  d2c_clk_sampling;
    wire [2:0]  d2c_pattern_setup;
    wire [1:0]  d2c_data_pattern_sel;
    wire        d2c_val_pattern_sel;
    wire        d2c_pattern_mode;
    wire [15:0] d2c_burst_count;
    wire [15:0] d2c_idle_count;
    wire [15:0] d2c_iter_count;
    wire [1:0]  d2c_compare_setup;

    wire        wrapper_tx_sb_msg_valid;
    wire [7:0]  wrapper_tx_sb_msg;
    wire [15:0] wrapper_tx_msginfo;
    wire [63:0] wrapper_tx_data_field;
    wire        wrapper_partner_test_d2c_done;

    // ===================================================================== //
    //                      Sideband Propagation Delay Line                  //
    // ===================================================================== //
    generate
        if (ENABLE_LOOPBACK) begin : g_loopback
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
                    msg_shreg[0]  <= msg_no_e'(intf.tb_muxed_tx_sb_msg);
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
        end
    endgenerate

    // ===================================================================== //
    //                          MB Simulation Block.                         //
    // ===================================================================== //
    integer burst_counter = 0;
    integer idle_counter  = 0;
    integer iter_counter  = 0;

    wire real_mb_tx_pattern_en   = (mb_tx_pattern_en === 1'b1) || (intf.mb_tx_pattern_en === 1'b1);
    wire real_mb_rx_compare_en   = (mb_rx_compare_en === 1'b1) || (intf.mb_rx_compare_en === 1'b1);

    wire [15:0] real_mb_tx_burst_count = (mb_tx_pattern_en === 1'b1) ? mb_tx_burst_count : intf.mb_tx_burst_count;
    wire [15:0] real_mb_rx_burst_count = (mb_rx_compare_en === 1'b1) ? mb_rx_burst_count : intf.mb_rx_burst_count;
    wire [15:0] real_mb_tx_idle_count  = (mb_tx_pattern_en === 1'b1) ? mb_tx_idle_count  : intf.mb_tx_idle_count;
    wire [15:0] real_mb_rx_idle_count  = (mb_rx_compare_en === 1'b1) ? mb_rx_idle_count  : intf.mb_rx_idle_count;
    wire [15:0] real_mb_tx_iter_count  = (mb_tx_pattern_en === 1'b1) ? mb_tx_iter_count  : intf.mb_tx_iter_count;
    wire [15:0] real_mb_rx_iter_count  = (mb_rx_compare_en === 1'b1) ? mb_rx_iter_count  : intf.mb_rx_iter_count;

    wire [15:0] target_burst = real_mb_tx_pattern_en ? real_mb_tx_burst_count : real_mb_rx_burst_count;
    wire [15:0] target_idle  = real_mb_tx_pattern_en ? real_mb_tx_idle_count  : real_mb_rx_idle_count;
    wire [15:0] target_iter  = real_mb_tx_pattern_en ? real_mb_tx_iter_count  : real_mb_rx_iter_count;

    // Use MB_DELAY instead of 4096 to speed up data pattern transmission/reception in simulation
    wire [15:0] effective_target_burst = (target_burst == 4096) ? MB_DELAY : target_burst;


    wire mb_tx_pattern_count_done = (iter_counter >= target_iter && (intf.tb_wait_timeout == 0)) ? 1'b1 : 1'b0;

    // reg         mb_rx_compare_done;
    reg  [15:0] mb_rx_perlane_pass;
    reg          mb_rx_val_pass;
    wire         mb_rx_aggr_pass = ~(|intf.tb_aggr_err);

    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if(!intf.rst_n) begin
            burst_counter      <= 0;
            idle_counter       <= 0;
            iter_counter       <= 0;
            // mb_rx_compare_done <= 0;
            mb_rx_perlane_pass <= 16'hFFFF;
            mb_rx_val_pass     <= 1'b1;
            tb_partner_test_d2c_done_en <= 0;
            tb_partner_test_d2c_done    <= 0;
        end
        else begin
            if(real_mb_tx_pattern_en || local_rx_pt_en || partner_tx_pt_en || partner_rx_pt_en) begin
                if(burst_counter < effective_target_burst && iter_counter < target_iter) begin
                    burst_counter <= burst_counter + 1;
                end
                else if(idle_counter < target_idle && iter_counter < target_iter) begin
                    idle_counter <= idle_counter + 1;
                end
                else if(iter_counter < target_iter) begin
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
                // mb_rx_compare_done <= 1'b1;
                mb_rx_perlane_pass <= intf.tb_force_perlane_pass;
                mb_rx_val_pass     <= intf.tb_force_val_pass;
            end
            else begin
                // mb_rx_compare_done <= 1'b0;
            end
        end
    end

    // assign intf.mb_rx_compare_done       = mb_rx_compare_done;
    assign intf.mb_tx_pattern_count_done = mb_tx_pattern_count_done;
    assign intf.mb_rx_perlane_pass       = mb_rx_perlane_pass;
    assign intf.mb_rx_val_pass           = mb_rx_val_pass;
    assign intf.mb_rx_aggr_pass          = mb_rx_aggr_pass;

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

    // =========================================================================
    // 1. Instantiate unit_negotiated_speed
    // =========================================================================
    unit_negotiated_speed u_negotiated_speed (
        .phy_negotiated_speed (intf.phy_negotiated_speed),
        .is_high_speed        (intf.is_high_speed)
    );

    // =========================================================================
    // 2. Instantiate unit_negotiated_lanes
    // =========================================================================
    // is_x16_module: internal wire (not exposed via intf, only used here for
    // driving wrapper_REPAIR directly in unit-level tests where needed).
    wire is_x16_module_w;

    unit_negotiated_lanes u_negotiated_lanes (
        .mb_rx_data_lane_mask       (intf.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (intf.mb_tx_data_lane_mask),
        .active_rx_lanes            (intf.active_rx_lanes),
        .active_tx_lanes            (intf.active_tx_lanes),
        // Updated port names: success_lanes split into TX bitmask + RX encoding
        .success_tx_lanes           (intf.linkspeed_success_lanes),
        // .success_rx_lanes_encoding  (intf.mb_rx_data_lane_mask),  // RX enc = current RX mask
        .rf_cap_SPMW                (intf.rf_cap_SPMW),
        .rf_ctrl_target_link_width  (intf.rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (intf.param_UCIe_S_x8),
        .degraded_lane_map_code     (intf.degraded_lane_map_code),
        .degrade_feasible           (intf.degrade_feasible),
        .is_x16_module              (is_x16_module_w)
    );


    // =========================================================================
    // 3. Instantiate unit_D2C_sweep
    // =========================================================================
    reg [15:0] held_d2c_perlane_pass;
    reg        held_d2c_val_pass;
    always @(posedge intf.lclk or negedge intf.rst_n) begin
        if (!intf.rst_n) begin
            held_d2c_perlane_pass <= 16'hFFFF;
            held_d2c_val_pass     <= 1'b1;
        end else if (intf.local_test_d2c_done) begin
            held_d2c_perlane_pass <= intf.d2c_perlane_pass;
            held_d2c_val_pass     <= intf.d2c_val_pass;
        end
    end

    unit_D2C_sweep #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE),
        .MIN_VAL_PI_CODE   (MIN_VAL_PI_CODE),
        .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) u_D2C_sweep (
        .lclk                 (intf.lclk),
        .rst_n                (intf.rst_n),
        .active_lanes         (intf.active_rx_lanes),

        .local_sweep_en       (intf.sweep_en),
        .partner_sweep_en     (intf.partner_sweep_en),
        .state_n              (intf.state_n_0),

        .local_test_d2c_done  (intf.local_test_d2c_done),
        .partner_test_d2c_done(intf.partner_test_d2c_done),
        .d2c_perlane_pass     (held_d2c_perlane_pass),
        .d2c_val_pass         (held_d2c_val_pass),

        .local_tx_pt_en       (local_tx_pt_en),
        .local_rx_pt_en       (local_rx_pt_en),
        .partner_tx_pt_en     (partner_tx_pt_en),
        .partner_rx_pt_en     (partner_rx_pt_en),

        .d2c_clk_sampling     (d2c_clk_sampling),
        .d2c_pattern_setup    (d2c_pattern_setup),
        .d2c_data_pattern_sel (d2c_data_pattern_sel),
        .d2c_val_pattern_sel  (d2c_val_pattern_sel),
        .d2c_pattern_mode     (d2c_pattern_mode),
        .d2c_burst_count      (d2c_burst_count),
        .d2c_idle_count       (d2c_idle_count),
        .d2c_iter_count       (d2c_iter_count),
        .d2c_compare_setup    (d2c_compare_setup),

        .swept_code           (intf.swept_code),
        .best_code            (intf.best_code),
        .min_eye_width        (intf.min_eye_width),
        .sweep_done           (intf.sweep_done)
    );

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

        // Connect sweep signals to wrapper unified ports
        .local_tx_pt_en             (local_tx_pt_en),
        .partner_tx_pt_en           (partner_tx_pt_en),
        .local_rx_pt_en             (local_rx_pt_en),
        .partner_rx_pt_en           (partner_rx_pt_en),
        .d2c_clk_sampling           (d2c_clk_sampling),
        .d2c_pattern_setup          (d2c_pattern_setup),
        .d2c_data_pattern_sel       (d2c_data_pattern_sel),
        .d2c_val_pattern_sel        (d2c_val_pattern_sel),
        .d2c_pattern_mode           (d2c_pattern_mode),
        .d2c_burst_count            (d2c_burst_count),
        .d2c_idle_count             (d2c_idle_count),
        .d2c_iter_count             (d2c_iter_count),
        .d2c_compare_setup          (d2c_compare_setup),

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
        // .mb_rx_compare_done         (mb_rx_compare_done),
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
    assign intf.tb_muxed_tx_sb_msg_valid = (wrapper_tx_sb_msg_valid === 1'b1) || (intf.tx_sb_msg_valid === 1'b1);
    assign intf.tb_muxed_tx_sb_msg       = (wrapper_tx_sb_msg_valid === 1'b1) ? msg_no_e'(wrapper_tx_sb_msg) :
        ($isunknown(intf.tx_sb_msg) ? NOTHING : intf.tx_sb_msg);
    assign intf.tb_muxed_tx_msginfo      = (wrapper_tx_sb_msg_valid === 1'b1) ? wrapper_tx_msginfo :
        ($isunknown(intf.tx_msginfo) ? 16'h0000 : intf.tx_msginfo);
    assign intf.tb_muxed_tx_data_field   = (wrapper_tx_sb_msg_valid === 1'b1) ? wrapper_tx_data_field :
        ($isunknown(intf.tx_data_field) ? 64'h0000_0000_0000_0000 : intf.tx_data_field);

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
