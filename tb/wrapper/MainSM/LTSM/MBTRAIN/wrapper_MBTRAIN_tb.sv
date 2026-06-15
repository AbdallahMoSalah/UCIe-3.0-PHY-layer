`timescale 1ns/1ps

// ====================================================================================================
// wrapper_MBTRAIN_tb.sv
//
// Integration Testbench for wrapper_MBTRAIN.
// Simulates two interconnected UCIe dies (Die 0 and Die 1) running the MBTRAIN sequence.
//
// Key Features:
//   - Instantiates two independent wrapper_MBTRAIN modules representing Die 0 and Die 1.
//   - Uses ltsm_tb_if and ltsm_tb_attachments to provide stimulus, behavioral delays,
//     and loopback models for sideband/mainband communication.
//   - Verifies the strict 1-cycle assertion rule for tx_sb_msg_valid with a low gap
//     between consecutive messages.
//   - Runs the sequence through all sub-states to a successful completion.
// ====================================================================================================

module wrapper_MBTRAIN_tb;

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // =========================================================================
    // Simulation Parameters
    // =========================================================================
    localparam real    CLK_PERIOD           = 1.0;
    localparam integer TIMEOUT_CYCLES       = 'D200_000;
    localparam integer ANALOG_SETTLE_CYCLES = 'D10;
    localparam integer SB_DELAY             = 2;
    localparam integer MB_DELAY             = 2;

    localparam int unsigned MAX_VAL_VREF_CODE  = 7'd16;
    localparam int unsigned MIN_VAL_VREF_CODE  = 7'd10;
    localparam int unsigned MAX_DATA_VREF_CODE = 7'd16;
    localparam int unsigned MIN_DATA_VREF_CODE = 7'd10;
    localparam int unsigned MAX_DATA_PI_CODE   = 6'd16;
    localparam int unsigned MIN_DATA_PI_CODE   = 6'd0;
    localparam int unsigned MAX_VAL_PI_CODE    = 6'd16;
    localparam int unsigned MIN_VAL_PI_CODE    = 6'd0;
    localparam int unsigned MAX_DESKEW_CODE    = 7'd16;
    localparam int unsigned MIN_DESKEW_CODE    = 7'd0;

    // =========================================================================
    // Clocks and Resets
    // =========================================================================
    logic lclk  = 1'b0;
    logic rst_n = 1'b0;

    always #(CLK_PERIOD/2.0) lclk = ~lclk;

    // =========================================================================
    // Interfaces for Die 0 and Die 1
    // =========================================================================
    ltsm_tb_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE)
    ) intf_die0 (
        .lclk  (lclk),
        .rst_n (rst_n)
    );

    ltsm_tb_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE)
    ) intf_die1 (
        .lclk  (lclk),
        .rst_n (rst_n)
    );

    // =========================================================================
    // Testbench Attachments (Simulation models for SB/MB/Timers)
    // =========================================================================
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .ENABLE_LOOPBACK     (1'b0) // We do explicit cross-die wiring below
    ) attach_die0 (
        .intf(intf_die0)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .ENABLE_LOOPBACK     (1'b0) // We do explicit cross-die wiring below
    ) attach_die1 (
        .intf(intf_die1)
    );

    // =========================================================================
    // Cross-Die Sideband Connection (with parameterized delay)
    // =========================================================================
    // Die 0 TX -> Die 1 RX
    logic [SB_DELAY-1:0] d0_to_d1_val_sr;
    logic [7:0]          d0_to_d1_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         d0_to_d1_info_sr [0:SB_DELAY-1];
    logic [63:0]         d0_to_d1_data_sr [0:SB_DELAY-1];

    // Die 1 TX -> Die 0 RX
    logic [SB_DELAY-1:0] d1_to_d0_val_sr;
    logic [7:0]          d1_to_d0_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         d1_to_d0_info_sr [0:SB_DELAY-1];
    logic [63:0]         d1_to_d0_data_sr [0:SB_DELAY-1];

    logic d0_tx_valid; logic [7:0] d0_tx_msg; logic [15:0] d0_tx_info; logic [63:0] d0_tx_data;
    logic d1_tx_valid; logic [7:0] d1_tx_msg; logic [15:0] d1_tx_info; logic [63:0] d1_tx_data;

    assign d0_tx_valid = dut_die0.substate_tx_sb_msg_valid | intf_die0.tb_muxed_tx_sb_msg_valid;
    assign d0_tx_msg   = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_sb_msg : intf_die0.tb_muxed_tx_sb_msg;
    assign d0_tx_info  = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_msginfo : intf_die0.tb_muxed_tx_msginfo;
    assign d0_tx_data  = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_data_field : intf_die0.tb_muxed_tx_data_field;

    assign d1_tx_valid = dut_die1.substate_tx_sb_msg_valid | intf_die1.tb_muxed_tx_sb_msg_valid;
    assign d1_tx_msg   = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_sb_msg : intf_die1.tb_muxed_tx_sb_msg;
    assign d1_tx_info  = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_msginfo : intf_die1.tb_muxed_tx_msginfo;
    assign d1_tx_data  = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_data_field : intf_die1.tb_muxed_tx_data_field;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            d0_to_d1_val_sr <= '0;
            d1_to_d0_val_sr <= '0;
            for (int i = 0; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i] <= '0; d0_to_d1_info_sr[i] <= '0; d0_to_d1_data_sr[i] <= '0;
                d1_to_d0_msg_sr[i] <= '0; d1_to_d0_info_sr[i] <= '0; d1_to_d0_data_sr[i] <= '0;
            end
            intf_die1.rx_sb_msg_valid <= 1'b0; intf_die1.rx_sb_msg <= '0; intf_die1.rx_msginfo <= '0; intf_die1.rx_data_field <= '0;
            intf_die0.rx_sb_msg_valid <= 1'b0; intf_die0.rx_sb_msg <= '0; intf_die0.rx_msginfo <= '0; intf_die0.rx_data_field <= '0;
        end else begin
            if (d0_tx_valid) $display("Time %0t | D0 TX Msg: %0h Info: %0h Data: %0h", $time, d0_tx_msg, d0_tx_info, d0_tx_data);
            if (d1_tx_valid) $display("Time %0t | D1 TX Msg: %0h Info: %0h Data: %0h", $time, d1_tx_msg, d1_tx_info, d1_tx_data);

            // Shift Die 0 -> Die 1
            d0_to_d1_val_sr <= {d0_to_d1_val_sr[SB_DELAY-2:0], d0_tx_valid};
            d0_to_d1_msg_sr[0] <= d0_tx_msg;
            d0_to_d1_info_sr[0] <= d0_tx_info;
            d0_to_d1_data_sr[0] <= d0_tx_data;
            for (int i = 1; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i] <= d0_to_d1_msg_sr[i-1];
                d0_to_d1_info_sr[i] <= d0_to_d1_info_sr[i-1];
                d0_to_d1_data_sr[i] <= d0_to_d1_data_sr[i-1];
            end
            intf_die1.rx_sb_msg_valid <= d0_to_d1_val_sr[SB_DELAY-1];
            intf_die1.rx_sb_msg       <= d0_to_d1_msg_sr[SB_DELAY-1];
            intf_die1.rx_msginfo      <= d0_to_d1_info_sr[SB_DELAY-1];
            intf_die1.rx_data_field   <= d0_to_d1_data_sr[SB_DELAY-1];

            if (d0_to_d1_val_sr[SB_DELAY-1]) $display("Time %0t | D1 RX Msg: %0h Info: %0h Data: %0h", $time, d0_to_d1_msg_sr[SB_DELAY-1], d0_to_d1_info_sr[SB_DELAY-1], d0_to_d1_data_sr[SB_DELAY-1]);

            // Shift Die 1 -> Die 0
            d1_to_d0_val_sr <= {d1_to_d0_val_sr[SB_DELAY-2:0], d1_tx_valid};
            d1_to_d0_msg_sr[0] <= d1_tx_msg;
            d1_to_d0_info_sr[0] <= d1_tx_info;
            d1_to_d0_data_sr[0] <= d1_tx_data;
            for (int i = 1; i < SB_DELAY; i++) begin
                d1_to_d0_msg_sr[i] <= d1_to_d0_msg_sr[i-1];
                d1_to_d0_info_sr[i] <= d1_to_d0_info_sr[i-1];
                d1_to_d0_data_sr[i] <= d1_to_d0_data_sr[i-1];
            end
            intf_die0.rx_sb_msg_valid <= d1_to_d0_val_sr[SB_DELAY-1];
            intf_die0.rx_sb_msg       <= d1_to_d0_msg_sr[SB_DELAY-1];
            intf_die0.rx_msginfo      <= d1_to_d0_info_sr[SB_DELAY-1];
            intf_die0.rx_data_field   <= d1_to_d0_data_sr[SB_DELAY-1];

            if (d1_to_d0_val_sr[SB_DELAY-1]) $display("Time %0t | D0 RX Msg: %0h Info: %0h Data: %0h", $time, d1_to_d0_msg_sr[SB_DELAY-1], d1_to_d0_info_sr[SB_DELAY-1], d1_to_d0_data_sr[SB_DELAY-1]);
        end
    end

    // =========================================================================
    // Declarations for unit_D2C_sweep and wrapper_D2C_PT_top
    // =========================================================================
    logic        local_test_d2c_done_d0;
    logic        partner_test_d2c_done_d0;
    logic [15:0] d2c_perlane_pass_d0;
    logic        d2c_aggr_pass_d0;
    logic        d2c_val_pass_d0;

    logic        local_test_d2c_done_d1;
    logic        partner_test_d2c_done_d1;
    logic [15:0] d2c_perlane_pass_d1;
    logic        d2c_aggr_pass_d1;
    logic        d2c_val_pass_d1;

    logic        local_tx_pt_en_d0;
    logic        local_rx_pt_en_d0;
    logic        partner_tx_pt_en_d0;
    logic        partner_rx_pt_en_d0;
    logic [1:0]  d2c_clk_sampling_d0;
    logic [2:0]  d2c_pattern_setup_d0;
    logic [1:0]  d2c_data_pattern_sel_d0;
    logic        d2c_val_pattern_sel_d0;
    logic        d2c_pattern_mode_d0;
    logic [15:0] d2c_burst_count_d0;
    logic [15:0] d2c_idle_count_d0;
    logic [15:0] d2c_iter_count_d0;
    logic [1:0]  d2c_compare_setup_d0;

    logic        local_tx_pt_en_d1;
    logic        local_rx_pt_en_d1;
    logic        partner_tx_pt_en_d1;
    logic        partner_rx_pt_en_d1;
    logic [1:0]  d2c_clk_sampling_d1;
    logic [2:0]  d2c_pattern_setup_d1;
    logic [1:0]  d2c_data_pattern_sel_d1;
    logic        d2c_val_pattern_sel_d1;
    logic        d2c_pattern_mode_d1;
    logic [15:0] d2c_burst_count_d1;
    logic [15:0] d2c_idle_count_d1;
    logic [15:0] d2c_iter_count_d1;
    logic [1:0]  d2c_compare_setup_d1;

    logic [1:0]  d2c_mb_tx_trk_lane_sel_d0;
    logic [1:0]  d2c_mb_tx_clk_lane_sel_d0;
    logic [1:0]  d2c_mb_tx_val_lane_sel_d0;
    logic [1:0]  d2c_mb_tx_data_lane_sel_d0;
    logic        d2c_mb_rx_trk_lane_sel_d0;
    logic        d2c_mb_rx_clk_lane_sel_d0;
    logic        d2c_mb_rx_val_lane_sel_d0;
    logic        d2c_mb_rx_data_lane_sel_d0;

    logic [1:0]  d2c_mb_tx_trk_lane_sel_d1;
    logic [1:0]  d2c_mb_tx_clk_lane_sel_d1;
    logic [1:0]  d2c_mb_tx_val_lane_sel_d1;
    logic [1:0]  d2c_mb_tx_data_lane_sel_d1;
    logic        d2c_mb_rx_trk_lane_sel_d1;
    logic        d2c_mb_rx_clk_lane_sel_d1;
    logic [1:0]  d2c_mb_rx_val_lane_sel_d1;
    logic        d2c_mb_rx_data_lane_sel_d1;

    state_n_e    d2c_state_n_d0;
    state_n_e    d2c_state_n_d1;

    // =========================================================================
    // Control & Initialization Signals per Die
    // =========================================================================
    logic mbtrain_en_d0, mbtrain_en_d1;
    logic mbtrain_done_d0, mbtrain_done_d1;
    state_n_e current_mbtrain_substate_d0, current_mbtrain_substate_d1;

    logic ltsm_trainerror_req_d0, ltsm_linkinit_req_d0, ltsm_phyretrain_req_d0, ltsm_repair_req_d0, ltsm_speedidle_req_d0;
    logic ltsm_trainerror_req_d1, ltsm_linkinit_req_d1, ltsm_phyretrain_req_d1, ltsm_repair_req_d1, ltsm_speedidle_req_d1;

    // We do not inject special re-entry requests in the normal flow.
    logic mbtrain_txselfcal_req = 0, mbtrain_speedidle_req = 0, mbtrain_repair_req = 0;

    // PHY and configuration signals
    logic [2:0] param_negotiated_max_speed = 3'b010;
    logic       is_continuous_clk_mode = 1'b0;
    logic       rf_cap_SPMW = 1'b0;
    logic [3:0] rf_ctrl_target_link_width = 4'h2;
    logic       param_UCIe_S_x8 = 1'b0;
    logic       PHY_IN_RETRAIN = 1'b0;
    logic       params_changed = 1'b0;
    logic [2:0] mbinit_rx_data_lane_mask = 3'b011;
    logic [2:0] mbinit_tx_data_lane_mask = 3'b011;
    logic [15:0] active_rx_lanes = 16'hFFFF;

    logic [6:0] sweep_swept_code_d0;
    logic [6:0] sweep_best_code_d0 [0:15];
    logic [6:0] sweep_min_eye_width_d0;

    logic [6:0] sweep_swept_code_d1;
    logic [6:0] sweep_best_code_d1 [0:15];
    logic [6:0] sweep_min_eye_width_d1;

    // =========================================================================
    // DUT Instances: Die 0 and Die 1
    // =========================================================================

    // Note: The wrapper_MBTRAIN uses interfaces/signals matching the attachments.
    // Since wrapper_MBTRAIN doesn't take an interface natively, we wire from intf.

    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE   (MIN_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die0 (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .mbtrain_en                 (mbtrain_en_d0),
        .mbtrain_done               (mbtrain_done_d0),
        .current_mbtrain_substate   (current_mbtrain_substate_d0),

        .ltsm_trainerror_req        (ltsm_trainerror_req_d0),
        .ltsm_linkinit_req          (ltsm_linkinit_req_d0),
        .ltsm_phyretrain_req        (ltsm_phyretrain_req_d0),
        .ltsm_repair_req            (ltsm_repair_req_d0),
        .ltsm_speedidle_req         (ltsm_speedidle_req_d0),

        .mbtrain_txselfcal_req      (mbtrain_txselfcal_req),
        .mbtrain_speedidle_req      (mbtrain_speedidle_req),
        .mbtrain_repair_req         (mbtrain_repair_req),

        .timeout_8ms_occured        (intf_die0.timeout_8ms_occured),
        .analog_settle_time_done    (intf_die0.analog_settle_time_done),
        .timeout_timer_en           (intf_die0.timeout_timer_en),
        .analog_settle_timer_en     (intf_die0.analog_settle_timer_en),

        .state_n                    (intf_die0.state_n),
        .param_negotiated_max_speed (param_negotiated_max_speed),
        .is_continuous_clk_mode     (is_continuous_clk_mode),
        .rf_cap_SPMW                (rf_cap_SPMW),
        .rf_ctrl_target_link_width  (rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (param_UCIe_S_x8),

        .PHY_IN_RETRAIN             (PHY_IN_RETRAIN),
        .params_changed             (params_changed),
        .PHY_IN_RETRAIN_rst         (),
        .busy_bit_rst               (),

        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (intf_die0.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (intf_die0.mb_tx_data_lane_mask),

        .local_sweep_en             (intf_die0.sweep_en),
        .partner_sweep_en           (intf_die0.partner_sweep_en),
        .sweep_active_lanes         (),
        .d2c_state_n                (d2c_state_n_d0),
        .sweep_done                 (intf_die0.sweep_done),
        .sweep_swept_code           (sweep_swept_code_d0),
        .sweep_best_code            (sweep_best_code_d0),
        .sweep_min_eye_width        (sweep_min_eye_width_d0),

        .d2c_perlane_pass           (intf_die0.d2c_perlane_pass),
        .d2c_aggr_pass              (intf_die0.d2c_aggr_pass),
        .d2c_val_pass               (intf_die0.d2c_val_pass),

        .phy_negotiated_speed       (intf_die0.phy_negotiated_speed),
        .phy_tx_selfcal_en          (),
        .phy_rx_clock_lock_en       (intf_die0.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en       (intf_die0.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en   (intf_die0.phy_rx_phase_detector_en),

        .phy_rx_tckn_shift          (5'd0),
        .phy_rx_decrement_shift     (1'b0),
        .phy_tx_tckn_shift_en       (intf_die0.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift          (intf_die0.phy_tx_tckn_shift),
        .phy_tx_decrement_shift     (intf_die0.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),

        .phy_rx_valvref_ctrl        (intf_die0.phy_rx_valvref_ctrl),
        .phy_rx_datavref_ctrl       (intf_die0.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl   (intf_die0.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl  (intf_die0.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl         (),
        .phy_tx_eq_preset_ctrl      (),
        .phy_tx_eq_preset_en        (),

        .substate_mb_tx_clk_lane_sel (intf_die0.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel(intf_die0.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel (intf_die0.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel (intf_die0.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel (intf_die0.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel(intf_die0.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel (intf_die0.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel (intf_die0.mb_rx_trk_lane_sel),

        .rxclkcal_mb_tx_pattern_en   (intf_die0.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup(intf_die0.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel(intf_die0.mb_tx_clk_pattern_sel),

        .substate_tx_sb_msg_valid   (intf_die0.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg         (intf_die0.wrapper_tx_sb_msg),
        .substate_tx_msginfo        (intf_die0.wrapper_tx_msginfo),
        .substate_tx_data_field     (intf_die0.wrapper_tx_data_field),

        .rx_sb_msg_valid            (intf_die0.rx_sb_msg_valid),
        .rx_sb_msg                  (intf_die0.rx_sb_msg),
        .rx_msginfo                 (intf_die0.rx_msginfo),
        .rx_data_field              (intf_die0.rx_data_field)
    );

    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE   (MIN_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die1 (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .mbtrain_en                 (mbtrain_en_d1),
        .mbtrain_done               (mbtrain_done_d1),
        .current_mbtrain_substate   (current_mbtrain_substate_d1),

        .ltsm_trainerror_req        (ltsm_trainerror_req_d1),
        .ltsm_linkinit_req          (ltsm_linkinit_req_d1),
        .ltsm_phyretrain_req        (ltsm_phyretrain_req_d1),
        .ltsm_repair_req            (ltsm_repair_req_d1),
        .ltsm_speedidle_req         (ltsm_speedidle_req_d1),

        .mbtrain_txselfcal_req      (mbtrain_txselfcal_req),
        .mbtrain_speedidle_req      (mbtrain_speedidle_req),
        .mbtrain_repair_req         (mbtrain_repair_req),

        .timeout_8ms_occured        (intf_die1.timeout_8ms_occured),
        .analog_settle_time_done    (intf_die1.analog_settle_time_done),
        .timeout_timer_en           (intf_die1.timeout_timer_en),
        .analog_settle_timer_en     (intf_die1.analog_settle_timer_en),

        .state_n                    (intf_die1.state_n),
        .param_negotiated_max_speed (param_negotiated_max_speed),
        .is_continuous_clk_mode     (is_continuous_clk_mode),
        .rf_cap_SPMW                (rf_cap_SPMW),
        .rf_ctrl_target_link_width  (rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (param_UCIe_S_x8),

        .PHY_IN_RETRAIN             (PHY_IN_RETRAIN),
        .params_changed             (params_changed),
        .PHY_IN_RETRAIN_rst         (),
        .busy_bit_rst               (),

        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (intf_die1.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (intf_die1.mb_tx_data_lane_mask),

        .local_sweep_en             (intf_die1.sweep_en),
        .partner_sweep_en           (intf_die1.partner_sweep_en),
        .sweep_active_lanes         (),
        .d2c_state_n                (d2c_state_n_d1),
        .sweep_done                 (intf_die1.sweep_done),
        .sweep_swept_code           (sweep_swept_code_d1),
        .sweep_best_code            (sweep_best_code_d1),
        .sweep_min_eye_width        (sweep_min_eye_width_d1),

        .d2c_perlane_pass           (intf_die1.d2c_perlane_pass),
        .d2c_aggr_pass              (intf_die1.d2c_aggr_pass),
        .d2c_val_pass               (intf_die1.d2c_val_pass),

        .phy_negotiated_speed       (intf_die1.phy_negotiated_speed),
        .phy_tx_selfcal_en          (),
        .phy_rx_clock_lock_en       (intf_die1.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en       (intf_die1.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en   (intf_die1.phy_rx_phase_detector_en),

        .phy_rx_tckn_shift          (5'd0),
        .phy_rx_decrement_shift     (1'b0),
        .phy_tx_tckn_shift_en       (intf_die1.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift          (intf_die1.phy_tx_tckn_shift),
        .phy_tx_decrement_shift     (intf_die1.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),

        .phy_rx_valvref_ctrl        (intf_die1.phy_rx_valvref_ctrl),
        .phy_rx_datavref_ctrl       (intf_die1.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl   (intf_die1.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl  (intf_die1.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl         (),
        .phy_tx_eq_preset_ctrl      (),
        .phy_tx_eq_preset_en        (),

        .substate_mb_tx_clk_lane_sel (intf_die1.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel(intf_die1.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel (intf_die1.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel (intf_die1.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel (intf_die1.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel(intf_die1.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel (intf_die1.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel (intf_die1.mb_rx_trk_lane_sel),

        .rxclkcal_mb_tx_pattern_en   (intf_die1.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup(intf_die1.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel(intf_die1.mb_tx_clk_pattern_sel),

        .substate_tx_sb_msg_valid   (intf_die1.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg         (intf_die1.wrapper_tx_sb_msg),
        .substate_tx_msginfo        (intf_die1.wrapper_tx_msginfo),
        .substate_tx_data_field     (intf_die1.wrapper_tx_data_field),

        .rx_sb_msg_valid            (intf_die1.rx_sb_msg_valid),
        .rx_sb_msg                  (intf_die1.rx_sb_msg),
        .rx_msginfo                 (intf_die1.rx_msginfo),
        .rx_data_field              (intf_die1.rx_data_field)
    );

    // =========================================================================
    // Check 1-cycle spacing rule for tx_sb_msg_valid
    // =========================================================================
    // The rule: tx_sb_msg_valid should be asserted for exactly 1 cycle, and there
    // must be at least 1 cycle of '0' before the next assertion.

    property p_die0_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            intf_die0.tb_muxed_tx_sb_msg_valid |=> !intf_die0.tb_muxed_tx_sb_msg_valid;
    endproperty
    assert property (p_die0_msg_spacing) else $error("Die 0 tx_sb_msg_valid violated 1-cycle spacing rule");

    property p_die1_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            intf_die1.tb_muxed_tx_sb_msg_valid |=> !intf_die1.tb_muxed_tx_sb_msg_valid;
    endproperty
    assert property (p_die1_msg_spacing) else $error("Die 1 tx_sb_msg_valid violated 1-cycle spacing rule");

    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    initial begin
        $display("Starting MBTRAIN Integration Test (Die 0 and Die 1)...");

        // Initialization
        mbtrain_en_d0 = 1'b0;
        mbtrain_en_d1 = 1'b0;

        intf_die0.tb_force_perlane_pass = 16'hffff;
        intf_die0.tb_force_aggr_pass    = 1'b1;
        intf_die0.tb_force_val_pass     = 1'b1;
        intf_die0.tb_wait_timeout       = 1'b0;
        intf_die0.tb_wrong_sb_msg_en    = 1'b0;

        intf_die1.tb_force_perlane_pass = 16'hffff;
        intf_die1.tb_force_aggr_pass    = 1'b1;
        intf_die1.tb_force_val_pass     = 1'b1;
        intf_die1.tb_wait_timeout       = 1'b0;
        intf_die1.tb_wrong_sb_msg_en    = 1'b0;

        // Initialize state_n array to LOG_RESET
        intf_die0.state_n_0 = LOG_RESET; intf_die0.state_n_1 = LOG_RESET; intf_die0.state_n_2 = LOG_RESET; intf_die0.state_n_3 = LOG_RESET;
        intf_die1.state_n_0 = LOG_RESET; intf_die1.state_n_1 = LOG_RESET; intf_die1.state_n_2 = LOG_RESET; intf_die1.state_n_3 = LOG_RESET;

        // Apply Reset
        rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // Sequence through the LTSM top-level states to un-reset the MBTRAIN sub-FSMs
        // Note: the wrapper maps intf.state_n[0:3] to wrapper state_n[3:0].
        // We must ensure the wrapper's state_n[0] matches the correct state.
        // That means we must drive intf.state_n_3.

        intf_die0.state_n_0 = LOG_RESET; intf_die0.state_n_1 = LOG_RESET; intf_die0.state_n_2 = LOG_RESET; intf_die0.state_n_3 = LOG_RESET;
        intf_die1.state_n_0 = LOG_RESET; intf_die1.state_n_1 = LOG_RESET; intf_die1.state_n_2 = LOG_RESET; intf_die1.state_n_3 = LOG_RESET;
        #(CLK_PERIOD * 10);

        intf_die0.state_n_0 = LOG_SBINIT; intf_die0.state_n_1 = LOG_SBINIT; intf_die0.state_n_2 = LOG_SBINIT; intf_die0.state_n_3 = LOG_SBINIT;
        intf_die1.state_n_0 = LOG_SBINIT; intf_die1.state_n_1 = LOG_SBINIT; intf_die1.state_n_2 = LOG_SBINIT; intf_die1.state_n_3 = LOG_SBINIT;
        #(CLK_PERIOD * 10);

        intf_die0.state_n_0 = LOG_MBINIT_REPAIRMB; intf_die0.state_n_1 = LOG_MBINIT_REPAIRMB; intf_die0.state_n_2 = LOG_MBINIT_REPAIRMB; intf_die0.state_n_3 = LOG_MBINIT_REPAIRMB;
        intf_die1.state_n_0 = LOG_MBINIT_REPAIRMB; intf_die1.state_n_1 = LOG_MBINIT_REPAIRMB; intf_die1.state_n_2 = LOG_MBINIT_REPAIRMB; intf_die1.state_n_3 = LOG_MBINIT_REPAIRMB;
        #(CLK_PERIOD * 10);

        intf_die0.state_n_0 = LOG_MBTRAIN_VALVREF; intf_die0.state_n_1 = LOG_MBTRAIN_VALVREF; intf_die0.state_n_2 = LOG_MBTRAIN_VALVREF; intf_die0.state_n_3 = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_0 = LOG_MBTRAIN_VALVREF; intf_die1.state_n_1 = LOG_MBTRAIN_VALVREF; intf_die1.state_n_2 = LOG_MBTRAIN_VALVREF; intf_die1.state_n_3 = LOG_MBTRAIN_VALVREF;
        #(CLK_PERIOD * 10);

        // Start MBTRAIN on both dies simultaneously
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;

        fork
            begin
                static state_n_e last_state_d0 = LOG_NOP;
                static state_n_e last_state_d1 = LOG_NOP;
                while (1) begin
                    @(posedge lclk);
                    if (current_mbtrain_substate_d0 != last_state_d0) begin
                        $display("Time %0t | D0 Substate: %s", $time, current_mbtrain_substate_d0.name());
                        last_state_d0 = current_mbtrain_substate_d0;
                    end
                    if (current_mbtrain_substate_d1 != last_state_d1) begin
                        $display("Time %0t | D1 Substate: %s", $time, current_mbtrain_substate_d1.name());
                        last_state_d1 = current_mbtrain_substate_d1;
                    end

                    if (dut_die0.trainerror_detected) begin
                        $display("Time %0t | D0 trainerror_detected asserted!", $time);
                        for (int i=0; i<13; i++) begin
                            if (dut_die0.ss_local_trainerror_req[i]) $display("  D0 Local Substate %0d req", i);
                            if (dut_die0.ss_partner_trainerror_req[i]) $display("  D0 Partner Substate %0d req", i);
                        end
                    end
                    if (dut_die1.trainerror_detected) begin
                        $display("Time %0t | D1 trainerror_detected asserted!", $time);
                        for (int i=0; i<13; i++) begin
                            if (dut_die1.ss_local_trainerror_req[i]) $display("  D1 Local Substate %0d req", i);
                            if (dut_die1.ss_partner_trainerror_req[i]) $display("  D1 Partner Substate %0d req", i);
                        end
                    end
                end
            end
        join_none

        fork
            begin
                static logic last_rst_d0 = 0;
                while (1) begin
                    @(posedge lclk);
                    if (dut_die0.is_ltsm_out_of_reset !== last_rst_d0) begin
                        $display("Time %0t | D0 is_ltsm_out_of_reset = %b, first_enter_flag = %b, state_n = %s", $time, dut_die0.is_ltsm_out_of_reset, dut_die0.first_enter_flag, intf_die0.state_n[0].name());
                        last_rst_d0 = dut_die0.is_ltsm_out_of_reset;
                    end
                end
            end
        join_none

        fork
            begin
                static logic [3:0] last_valvref_state_d0 = 4'hf;
                static logic last_rx_compare_en = 0;
                static logic last_rx_compare_done = 0;
                static logic last_local_test_d2c_done = 0;
                while (1) begin
                    @(posedge lclk);
                    if (dut_die0.u_VALVREF.u_VALVREF_local.current_state !== last_valvref_state_d0) begin
                        $display("Time %0t | D0 VALVREF_local State: %0d", $time, dut_die0.u_VALVREF.u_VALVREF_local.current_state);
                        last_valvref_state_d0 = dut_die0.u_VALVREF.u_VALVREF_local.current_state;
                    end
                    if (intf_die0.mb_rx_compare_en !== last_rx_compare_en) begin
                        $display("Time %0t | D0 mb_rx_compare_en: %b", $time, intf_die0.mb_rx_compare_en);
                        last_rx_compare_en = intf_die0.mb_rx_compare_en;
                    end
                    if (intf_die0.mb_rx_compare_done !== last_rx_compare_done) begin
                        $display("Time %0t | D0 mb_rx_compare_done: %b", $time, intf_die0.mb_rx_compare_done);
                        last_rx_compare_done = intf_die0.mb_rx_compare_done;
                    end
                    if (local_test_d2c_done_d0 !== last_local_test_d2c_done) begin
                        $display("Time %0t | D0 local_test_d2c_done: %b", $time, local_test_d2c_done_d0);
                        last_local_test_d2c_done = local_test_d2c_done_d0;
                    end
                    if (d2c_state_n_d0 !== d2c_state_n_d1) begin
                        // Just checking silently
                    end
                end
            end
        join_none

        fork
            begin
                static state_n_e last_d2c_state_n_d0 = LOG_NOP;
                static logic last_local_rx_pt_en_d0 = 0;
                static logic last_sweep_en_d0 = 0;
                while (1) begin
                    @(posedge lclk);
                    if (d2c_state_n_d0 !== last_d2c_state_n_d0) begin
                        $display("Time %0t | D0 d2c_state_n_d0: %s", $time, d2c_state_n_d0.name());
                        last_d2c_state_n_d0 = d2c_state_n_d0;
                    end
                    if (local_rx_pt_en_d0 !== last_local_rx_pt_en_d0) begin
                        $display("Time %0t | D0 local_rx_pt_en_d0: %b", $time, local_rx_pt_en_d0);
                        last_local_rx_pt_en_d0 = local_rx_pt_en_d0;
                    end
                    if (intf_die0.sweep_en !== last_sweep_en_d0) begin
                        $display("Time %0t | D0 sweep_en: %b", $time, intf_die0.sweep_en);
                        last_sweep_en_d0 = intf_die0.sweep_en;
                    end
                end
            end
        join_none

        // Wait for completion or error
        fork
            begin
                wait (mbtrain_done_d0 && mbtrain_done_d1);
                #(CLK_PERIOD * 10);
                if (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1) begin
                    $error("Test FAILED: MBTRAIN exited to TRAINERROR unexpectedly.");
                end else if (ltsm_linkinit_req_d0 && ltsm_linkinit_req_d1) begin
                    $display("Test PASSED: Both dies successfully reached LINKINIT routing request.");
                end else begin
                    $error("Test FAILED: Unexpected routing states. D0=%0b, D1=%0b", ltsm_linkinit_req_d0, ltsm_linkinit_req_d1);
                end
                $finish;
            end
            begin
                wait (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1);
                #(CLK_PERIOD * 10);
                $error("Test FAILED: Immediate TRAINERROR route requested. D0=%b, D1=%b", ltsm_trainerror_req_d0, ltsm_trainerror_req_d1);
                $finish;
            end
            begin
                #(CLK_PERIOD * TIMEOUT_CYCLES);
                $error("Test FAILED: Timeout reached. D0 state=%s, D1 state=%s", current_mbtrain_substate_d0.name(), current_mbtrain_substate_d1.name());
                $finish;
            end
        join
    end

endmodule
