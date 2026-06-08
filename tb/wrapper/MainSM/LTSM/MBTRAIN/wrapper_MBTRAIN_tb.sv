`timescale 1ps/1ps

// ====================================================================================================
// wrapper_MBTRAIN_tb.sv
//
// Raw-wire integration smoke test for wrapper_MBTRAIN.
// Instantiates:
//   1. wrapper_MBTRAIN
//   2. unit_D2C_sweep
//   3. wrapper_D2C_PT_top
//
// The RTL path is interface-free. This testbench keeps the behavioral models small and explicit:
//   - A sideband loopback delay returns the muxed MBTRAIN/D2C sideband stream.
//   - A compact mainband model completes point tests after MB_DELAY cycles.
//   - Timer counters create analog-settle completion and 8ms timeout indications.
// ====================================================================================================

module wrapper_MBTRAIN_tb;

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // ================================================================================================
    // 1. Fast simulation parameters
    // ================================================================================================
    localparam int LCLK_PERIOD          = 1000;
    localparam int SB_DELAY             = 8;
    localparam int MB_DELAY             = 12;
    localparam int ANALOG_SETTLE_CYCLES = 10;
    localparam int TIMEOUT_CYCLES       = 200000;

    localparam int MAX_VAL_VREF_CODE    = 7'd16;
    localparam int MIN_VAL_VREF_CODE    = 7'd10;
    localparam int MAX_DATA_VREF_CODE   = 7'd16;
    localparam int MIN_DATA_VREF_CODE   = 7'd10;
    localparam int MAX_DATA_PI_CODE     = 6'd16;
    localparam int MIN_DATA_PI_CODE     = 6'd0;
    localparam int MAX_VAL_PI_CODE      = 6'd16;
    localparam int MIN_VAL_PI_CODE      = 6'd0;
    localparam int MAX_DESKEW_CODE      = 7'd16;
    localparam int MIN_DESKEW_CODE      = 7'd0;

    // ================================================================================================
    // 2. Clock, reset, and top-level controls
    // ================================================================================================
    logic lclk = 1'b0;
    logic rst_n = 1'b0;

    always #(LCLK_PERIOD/2) lclk = ~lclk;

    logic        is_ltsm_out_of_reset;
    logic        mbtrain_en;
    logic        mbtrain_done;
    logic [3:0]  current_mbtrain_substate;
    logic        ltsm_trainerror_req;
    logic        ltsm_linkinit_req;
    logic        ltsm_phyretrain_req;
    logic        ltsm_repair_req;
    logic        ltsm_speedidle_req;
    logic        mbtrain_txselfcal_req;
    logic        mbtrain_speedidle_req;
    logic        mbtrain_repair_req;

    // ================================================================================================
    // 3. Configuration and PHY-facing signals
    // ================================================================================================
    state_n_e state_n [3:0];

    logic [2:0]  param_negotiated_max_speed;
    logic        is_continuous_clk_mode;
    logic        rf_cap_SPMW;
    logic [3:0]  rf_ctrl_target_link_width;
    logic        param_UCIe_S_x8;
    logic        PHY_IN_RETRAIN;
    logic        params_changed;
    logic        PHY_IN_RETRAIN_rst;
    logic        busy_bit_rst;
    logic [2:0]  mbinit_rx_data_lane_mask;
    logic [2:0]  mbinit_tx_data_lane_mask;
    logic [2:0]  mb_rx_data_lane_mask;
    logic [2:0]  mb_tx_data_lane_mask;

    logic [2:0]  phy_negotiated_speed;
    logic        phy_tx_selfcal_en;
    logic        phy_rx_clock_lock_en;
    logic        phy_rx_track_lock_en;
    logic        phy_rx_phase_detector_en;
    logic [4:0]  phy_rx_tckn_shift;
    logic        phy_rx_decrement_shift;
    logic        phy_tx_tckn_shift_en;
    logic [4:0]  phy_tx_tckn_shift;
    logic        phy_tx_decrement_shift;
    logic        phy_tx_tckn_shift_out_of_range;
    logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  phy_rx_valvref_ctrl;
    logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15];
    logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]    phy_tx_val_pi_phase_ctrl;
    logic [$clog2(MAX_DATA_PI_CODE+1)-1:0]   phy_tx_data_pi_phase_ctrl [0:15];
    logic [6:0]  phy_rx_deskew_ctrl [15:0];
    logic [2:0]  phy_tx_eq_preset_ctrl;
    logic        phy_tx_eq_preset_en;

    // ================================================================================================
    // 4. Timer, sideband, mainband, and D2C raw wires
    // ================================================================================================
    logic        timeout_8ms_occured;
    logic        analog_settle_time_done;
    logic        timeout_timer_en;
    logic        analog_settle_timer_en;

    logic        local_sweep_en;
    logic        partner_sweep_en;
    logic [15:0] sweep_active_lanes;
    state_n_e    d2c_state_n;
    logic        sweep_done;
    logic [6:0]  sweep_swept_code;
    wire  [6:0]  sweep_best_code [0:15];
    wire  [6:0]  sweep_min_eye_width;

    logic        local_tx_pt_en;
    logic        local_rx_pt_en;
    logic        partner_tx_pt_en;
    logic        partner_rx_pt_en;
    logic [1:0]  d2c_clk_sampling;
    logic [2:0]  d2c_pattern_setup;
    logic [1:0]  d2c_data_pattern_sel;
    logic        d2c_val_pattern_sel;
    logic        d2c_pattern_mode;
    logic [15:0] d2c_burst_count;
    logic [15:0] d2c_idle_count;
    logic [15:0] d2c_iter_count;
    logic [1:0]  d2c_compare_setup;

    logic        local_test_d2c_done;
    logic        partner_test_d2c_done;
    logic [15:0] d2c_perlane_pass;
    logic        d2c_aggr_pass;
    logic        d2c_val_pass;

    logic [1:0]  substate_mb_tx_clk_lane_sel;
    logic [1:0]  substate_mb_tx_data_lane_sel;
    logic [1:0]  substate_mb_tx_val_lane_sel;
    logic [1:0]  substate_mb_tx_trk_lane_sel;
    logic        substate_mb_rx_clk_lane_sel;
    logic        substate_mb_rx_data_lane_sel;
    logic        substate_mb_rx_val_lane_sel;
    logic        substate_mb_rx_trk_lane_sel;
    logic        rxclkcal_mb_tx_pattern_en;
    logic [2:0]  rxclkcal_mb_tx_pattern_setup;
    logic [1:0]  rxclkcal_mb_tx_clk_pattern_sel;
    logic        substate_tx_sb_msg_valid;
    logic [7:0]  substate_tx_sb_msg;
    logic [15:0] substate_tx_msginfo;
    logic [63:0] substate_tx_data_field;

    logic [1:0]  d2c_mb_tx_trk_lane_sel;
    logic [1:0]  d2c_mb_tx_clk_lane_sel;
    logic [1:0]  d2c_mb_tx_val_lane_sel;
    logic [1:0]  d2c_mb_tx_data_lane_sel;
    logic        d2c_mb_rx_trk_lane_sel;
    logic        d2c_mb_rx_clk_lane_sel;
    logic        d2c_mb_rx_val_lane_sel;
    logic        d2c_mb_rx_data_lane_sel;

    logic        mb_tx_pattern_en;
    logic [2:0]  mb_tx_pattern_setup;
    logic [2:0]  mb_rx_pattern_setup;
    logic        mb_tx_lfsr_en;
    logic        mb_tx_lfsr_rst;
    logic        mb_rx_lfsr_en;
    logic        mb_rx_lfsr_rst;
    logic [15:0] mb_rx_iter_count;
    logic [15:0] mb_rx_idle_count;
    logic [15:0] mb_rx_burst_count;
    logic        mb_rx_pattern_mode;
    logic        mb_rx_val_pattern_sel;
    logic [1:0]  mb_rx_data_pattern_sel;
    logic        mb_rx_compare_en;
    logic [1:0]  mb_rx_compare_setup;
    logic [11:0] mb_rx_max_err_thresh_perlane;
    logic [15:0] mb_rx_max_err_thresh_aggr;
    logic        mb_tx_clk_sampling_en;
    logic [1:0]  mb_tx_clk_sampling;
    logic        mb_tx_pattern_mode;
    logic [15:0] mb_tx_burst_count;
    logic [15:0] mb_tx_idle_count;
    logic [15:0] mb_tx_iter_count;
    logic [1:0]  mb_tx_data_pattern_sel;
    logic        mb_tx_val_pattern_sel;

    logic        mb_tx_pattern_count_done;
    logic        mb_rx_compare_done;
    logic        mb_rx_aggr_pass;
    logic [15:0] mb_rx_perlane_pass;
    logic        mb_rx_val_pass;

    logic        d2c_tx_sb_msg_valid;
    logic [7:0]  d2c_tx_sb_msg;
    logic [15:0] d2c_tx_msginfo;
    logic [63:0] d2c_tx_data_field;

    logic        rx_sb_msg_valid;
    logic [7:0]  rx_sb_msg;
    logic [15:0] rx_msginfo;
    logic [63:0] rx_data_field;

    // ================================================================================================
    // 5. DUT, sweep, and D2C point-test instantiations
    // ================================================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE  (MIN_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE (MIN_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE   (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE   (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE    (MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE    (MIN_VAL_PI_CODE),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE    (MIN_DESKEW_CODE)
    ) dut (
        .*
    );

    unit_D2C_sweep #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE   (MAX_DATA_PI_CODE),
        .MAX_VAL_PI_CODE    (MAX_VAL_PI_CODE),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE),
        .MIN_VAL_VREF_CODE  (MIN_VAL_VREF_CODE),
        .MIN_DATA_VREF_CODE (MIN_DATA_VREF_CODE),
        .MIN_DATA_PI_CODE   (MIN_DATA_PI_CODE),
        .MIN_VAL_PI_CODE    (MIN_VAL_PI_CODE),
        .MIN_DESKEW_CODE    (MIN_DESKEW_CODE)
    ) u_D2C_sweep (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .active_lanes          (sweep_active_lanes),
        .local_sweep_en        (local_sweep_en),
        .partner_sweep_en      (partner_sweep_en),
        .sweep_done            (sweep_done),
        .state_n               (d2c_state_n),
        .local_test_d2c_done   (local_test_d2c_done),
        .partner_test_d2c_done (partner_test_d2c_done),
        .d2c_perlane_pass      (d2c_perlane_pass),
        .d2c_val_pass          (d2c_val_pass),
        .local_tx_pt_en        (local_tx_pt_en),
        .local_rx_pt_en        (local_rx_pt_en),
        .partner_tx_pt_en      (partner_tx_pt_en),
        .partner_rx_pt_en      (partner_rx_pt_en),
        .d2c_clk_sampling      (d2c_clk_sampling),
        .d2c_pattern_setup     (d2c_pattern_setup),
        .d2c_data_pattern_sel  (d2c_data_pattern_sel),
        .d2c_val_pattern_sel   (d2c_val_pattern_sel),
        .d2c_pattern_mode      (d2c_pattern_mode),
        .d2c_burst_count       (d2c_burst_count),
        .d2c_idle_count        (d2c_idle_count),
        .d2c_iter_count        (d2c_iter_count),
        .d2c_compare_setup     (d2c_compare_setup),
        .swept_code            (sweep_swept_code),
        .best_code             (sweep_best_code),
        .min_eye_width         (sweep_min_eye_width)
    );

    wrapper_D2C_PT_top u_D2C_PT_top (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .mb_rx_data_lane_mask         (mb_rx_data_lane_mask),
        .local_test_d2c_done          (local_test_d2c_done),
        .partner_test_d2c_done        (partner_test_d2c_done),
        .d2c_perlane_pass             (d2c_perlane_pass),
        .d2c_aggr_pass                (d2c_aggr_pass),
        .d2c_val_pass                 (d2c_val_pass),
        .local_tx_pt_en               (local_tx_pt_en),
        .partner_tx_pt_en             (partner_tx_pt_en),
        .local_rx_pt_en               (local_rx_pt_en),
        .partner_rx_pt_en             (partner_rx_pt_en),
        .d2c_clk_sampling             (d2c_clk_sampling),
        .d2c_pattern_setup            (d2c_pattern_setup),
        .d2c_data_pattern_sel         (d2c_data_pattern_sel),
        .d2c_val_pattern_sel          (d2c_val_pattern_sel),
        .d2c_pattern_mode             (d2c_pattern_mode),
        .d2c_burst_count              (d2c_burst_count),
        .d2c_idle_count               (d2c_idle_count),
        .d2c_iter_count               (d2c_iter_count),
        .d2c_compare_setup            (d2c_compare_setup),
        .cfg_max_err_thresh_perlane   (12'hfff),
        .cfg_max_err_thresh_aggr      (16'hffff),
        .mb_tx_trk_lane_sel           (d2c_mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel           (d2c_mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel           (d2c_mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel          (d2c_mb_tx_data_lane_sel),
        .mb_rx_trk_lane_sel           (d2c_mb_rx_trk_lane_sel),
        .mb_rx_clk_lane_sel           (d2c_mb_rx_clk_lane_sel),
        .mb_rx_val_lane_sel           (d2c_mb_rx_val_lane_sel),
        .mb_rx_data_lane_sel          (d2c_mb_rx_data_lane_sel),
        .mb_tx_pattern_en             (mb_tx_pattern_en),
        .mb_tx_pattern_setup          (mb_tx_pattern_setup),
        .mb_rx_pattern_setup          (mb_rx_pattern_setup),
        .mb_tx_lfsr_en                (mb_tx_lfsr_en),
        .mb_tx_lfsr_rst               (mb_tx_lfsr_rst),
        .mb_rx_lfsr_en                (mb_rx_lfsr_en),
        .mb_rx_lfsr_rst               (mb_rx_lfsr_rst),
        .mb_rx_iter_count             (mb_rx_iter_count),
        .mb_rx_idle_count             (mb_rx_idle_count),
        .mb_rx_burst_count            (mb_rx_burst_count),
        .mb_rx_pattern_mode           (mb_rx_pattern_mode),
        .mb_rx_val_pattern_sel        (mb_rx_val_pattern_sel),
        .mb_rx_data_pattern_sel       (mb_rx_data_pattern_sel),
        .mb_rx_compare_en             (mb_rx_compare_en),
        .mb_rx_compare_setup          (mb_rx_compare_setup),
        .mb_rx_max_err_thresh_perlane (mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr    (mb_rx_max_err_thresh_aggr),
        .mb_tx_clk_sampling_en        (mb_tx_clk_sampling_en),
        .mb_tx_clk_sampling           (mb_tx_clk_sampling),
        .mb_tx_pattern_mode           (mb_tx_pattern_mode),
        .mb_tx_burst_count            (mb_tx_burst_count),
        .mb_tx_idle_count             (mb_tx_idle_count),
        .mb_tx_iter_count             (mb_tx_iter_count),
        .mb_tx_data_pattern_sel       (mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel        (mb_tx_val_pattern_sel),
        .mb_tx_pattern_count_done     (mb_tx_pattern_count_done),
        .mb_rx_compare_done           (mb_rx_compare_done),
        .mb_rx_aggr_pass              (mb_rx_aggr_pass),
        .mb_rx_perlane_pass           (mb_rx_perlane_pass),
        .mb_rx_val_pass               (mb_rx_val_pass),
        .tx_sb_msg_valid              (d2c_tx_sb_msg_valid),
        .tx_sb_msg                    (d2c_tx_sb_msg),
        .tx_msginfo                   (d2c_tx_msginfo),
        .tx_data_field                (d2c_tx_data_field),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    // ================================================================================================
    // 6. Behavioral timer, sideband, and mainband models
    // ================================================================================================
    int timeout_counter;
    int analog_settle_counter;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_counter          <= 0;
            analog_settle_counter    <= 0;
            timeout_8ms_occured      <= 1'b0;
            analog_settle_time_done  <= 1'b0;
        end else begin
            timeout_counter <= timeout_timer_en ? timeout_counter + 1 : 0;
            timeout_8ms_occured <= (timeout_counter >= TIMEOUT_CYCLES);

            if (analog_settle_timer_en) begin
                analog_settle_counter <= analog_settle_counter + 1;
            end else begin
                analog_settle_counter <= 0;
            end
            analog_settle_time_done <= analog_settle_timer_en && (analog_settle_counter >= ANALOG_SETTLE_CYCLES);
        end
    end

    logic        muxed_tx_valid;
    logic [7:0]  muxed_tx_msg;
    logic [15:0] muxed_tx_info;
    logic [63:0] muxed_tx_data;

    assign muxed_tx_valid = d2c_tx_sb_msg_valid | substate_tx_sb_msg_valid;
    assign muxed_tx_msg   = d2c_tx_sb_msg_valid ? d2c_tx_sb_msg       : substate_tx_sb_msg;
    assign muxed_tx_info  = d2c_tx_sb_msg_valid ? d2c_tx_msginfo      : substate_tx_msginfo;
    assign muxed_tx_data  = d2c_tx_sb_msg_valid ? d2c_tx_data_field   : substate_tx_data_field;

    logic [SB_DELAY-1:0] sb_valid_sr;
    logic [7:0]          sb_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         sb_info_sr [0:SB_DELAY-1];
    logic [63:0]         sb_data_sr [0:SB_DELAY-1];

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            sb_valid_sr <= '0;
            rx_sb_msg_valid <= 1'b0;
            rx_sb_msg       <= '0;
            rx_msginfo      <= '0;
            rx_data_field   <= '0;
            for (int i = 0; i < SB_DELAY; i++) begin
                sb_msg_sr[i]  <= '0;
                sb_info_sr[i] <= '0;
                sb_data_sr[i] <= '0;
            end
        end else begin
            sb_valid_sr <= {sb_valid_sr[SB_DELAY-2:0], muxed_tx_valid};
            sb_msg_sr[0]  <= muxed_tx_msg;
            sb_info_sr[0] <= muxed_tx_info;
            sb_data_sr[0] <= muxed_tx_data;

            for (int i = 1; i < SB_DELAY; i++) begin
                sb_msg_sr[i]  <= sb_msg_sr[i-1];
                sb_info_sr[i] <= sb_info_sr[i-1];
                sb_data_sr[i] <= sb_data_sr[i-1];
            end

            rx_sb_msg_valid <= sb_valid_sr[SB_DELAY-1];
            rx_sb_msg       <= sb_msg_sr[SB_DELAY-1];
            rx_msginfo      <= sb_info_sr[SB_DELAY-1];
            rx_data_field   <= sb_data_sr[SB_DELAY-1];
        end
    end

    int mb_counter;
    wire d2c_pt_active = local_tx_pt_en | local_rx_pt_en | partner_tx_pt_en | partner_rx_pt_en;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            mb_counter                 <= 0;
            mb_tx_pattern_count_done   <= 1'b0;
            mb_rx_compare_done         <= 1'b0;
            mb_rx_perlane_pass         <= 16'hffff;
            mb_rx_aggr_pass            <= 1'b1;
            mb_rx_val_pass             <= 1'b1;
        end else begin
            mb_tx_pattern_count_done <= 1'b0;
            mb_rx_compare_done       <= 1'b0;

            if (d2c_pt_active || mb_tx_pattern_en || rxclkcal_mb_tx_pattern_en) begin
                if (mb_counter < MB_DELAY) begin
                    mb_counter <= mb_counter + 1;
                end else begin
                    mb_counter               <= 0;
                    mb_tx_pattern_count_done <= 1'b1;
                    mb_rx_compare_done       <= 1'b1;
                    mb_rx_perlane_pass       <= 16'hffff;
                    mb_rx_aggr_pass          <= 1'b1;
                    mb_rx_val_pass           <= 1'b1;
                end
            end else begin
                mb_counter <= 0;
            end
        end
    end

    // ================================================================================================
    // 7. Reset, configuration, and smoke scenario
    // ================================================================================================
    initial begin
        is_ltsm_out_of_reset        = 1'b0;
        mbtrain_en                  = 1'b0;
        mbtrain_txselfcal_req       = 1'b0;
        mbtrain_speedidle_req       = 1'b0;
        mbtrain_repair_req          = 1'b0;
        param_negotiated_max_speed  = 3'b010;
        is_continuous_clk_mode      = 1'b0;
        rf_cap_SPMW                 = 1'b0;
        rf_ctrl_target_link_width   = 4'h2;
        param_UCIe_S_x8             = 1'b0;
        PHY_IN_RETRAIN              = 1'b0;
        params_changed              = 1'b0;
        mbinit_rx_data_lane_mask    = 3'b011;
        mbinit_tx_data_lane_mask    = 3'b011;
        phy_rx_tckn_shift           = 5'd2;
        phy_rx_decrement_shift      = 1'b0;
        phy_tx_tckn_shift_out_of_range = 1'b0;

        // Correct state history: state_n[1] is the PREVIOUS state.
        // SPEEDIDLE checks (state_n[1] == LOG_MBTRAIN_DATAVREF) to set max speed.
        state_n[0] = LOG_MBTRAIN_VALVREF;
        state_n[1] = LOG_MBTRAIN_DATAVREF;
        state_n[2] = LOG_RESET;
        state_n[3] = LOG_RESET;

        repeat (5) @(posedge lclk);
        rst_n = 1'b1;
        repeat (5) @(posedge lclk);
        is_ltsm_out_of_reset = 1'b1;
        mbtrain_en = 1'b1;

        fork
            begin
                wait (mbtrain_done || ltsm_trainerror_req || ltsm_linkinit_req || ltsm_phyretrain_req);
                repeat (5) @(posedge lclk);
                if (ltsm_trainerror_req) begin
                    $error("wrapper_MBTRAIN requested TRAINERROR during smoke run");
                end else begin
                    $display("wrapper_MBTRAIN smoke run reached a legal completion/route request.");
                end
                $finish;
            end
            begin
                repeat (TIMEOUT_CYCLES) @(posedge lclk);
                $error("wrapper_MBTRAIN smoke run timed out");
                $finish;
            end
        join
    end

endmodule
