interface mbtrain_cb_if(input logic lclk, output logic rst_n);
    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // MBTRAIN Control
    logic        mbtrain_en;
    logic        mbtrain_done;
    state_n_e    current_mbtrain_substate;

    // LTSM Requests
    logic        ltsm_trainerror_req;
    logic        ltsm_linkinit_req;
    logic        ltsm_phyretrain_req;

    // MBTRAIN Requests
    logic        mbtrain_txselfcal_req;
    logic        mbtrain_speedidle_req;
    logic        mbtrain_repair_req;

    // Timer Interface
    logic        analog_settle_time_done;
    logic        analog_settle_timer_en;

    // Configuration & State
    state_n_e    state_n_0;
    state_n_e    state_n_1;
    logic [2:0]  param_negotiated_max_speed;
    logic        is_continuous_clk_mode;
    logic        rf_cap_SPMW;
    logic [3:0]  rf_ctrl_target_link_width;
    logic        param_UCIe_S_x8;
    logic        PHY_IN_RETRAIN;
    logic        params_changed;
    logic        PHY_IN_RETRAIN_rst;
    logic        busy_bit_rst;

    // Lane Masks
    logic [2:0]  mbinit_rx_data_lane_mask;
    logic [2:0]  mbinit_tx_data_lane_mask;
    logic [2:0]  mb_rx_data_lane_mask;
    logic [2:0]  mb_tx_data_lane_mask;

    // Sweep Interface
    logic        local_sweep_en;
    logic        partner_sweep_en;
    logic [15:0] sweep_active_lanes;
    logic        sweep_done;
    logic [4:0]  sweep_swept_code;
    logic [4:0]  sweep_best_code [0:15];
    logic [4:0]  sweep_min_eye_width;

    // D2C Results
    logic [15:0] d2c_perlane_pass;
    logic        d2c_aggr_pass;
    logic        d2c_val_pass;

    // PHY Controls
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

    logic [4:0]  phy_rx_val_vref_ctrl;
    logic [4:0]  phy_rx_data_vref_ctrl [0:15];
    logic [4:0]  phy_tx_val_pi_phase_ctrl;
    logic [4:0]  phy_tx_data_pi_phase_ctrl [0:15];
    logic [4:0]  phy_rx_deskew_ctrl        [0:15];
    logic [2:0]  phy_tx_eq_preset_ctrl;
    logic        phy_tx_eq_preset_en;

    // Substate Monitoring
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

    // Sideband Interface
    logic        substate_tx_sb_msg_valid;
    logic [7:0]  substate_tx_sb_msg;
    logic [15:0] substate_tx_msginfo;
    logic [63:0] substate_tx_data_field;

    logic        rx_sb_msg_valid;
    logic [7:0]  rx_sb_msg;
    logic [15:0] rx_msginfo;
    logic [63:0] rx_data_field;

    // Debug-only probes driven from the TB top through hierarchical RTL paths.
    logic        dbg_soft_rst_n;
    logic [2:0]  dbg_valvref_local_state;
    logic [2:0]  dbg_valvref_partner_state;
    logic        dbg_valvref_local_done;
    logic        dbg_valvref_partner_done;

    initial begin
        rst_n = 1'b0;
    end

    // Tasks
    task drive_reset();
        rst_n = 0;
        mbtrain_en = 0;
        mbtrain_txselfcal_req = 0;
        mbtrain_speedidle_req = 0;
        mbtrain_repair_req = 0;
        state_n_0 = LOG_RESET;
        param_negotiated_max_speed = 3'b000;
        is_continuous_clk_mode = 0;
        rf_cap_SPMW = 0;
        rf_ctrl_target_link_width = 4'h0;
        param_UCIe_S_x8 = 0;
        PHY_IN_RETRAIN = 0;
        params_changed = 0;
        mbinit_rx_data_lane_mask = 3'b011;
        mbinit_tx_data_lane_mask = 3'b011;
        sweep_done = 0;
        sweep_swept_code = 0;
        for(int i=0; i<16; i++) sweep_best_code[i] = 0;
        sweep_min_eye_width = 0;
        d2c_perlane_pass = 16'h0000;
        analog_settle_time_done = 0;
        rx_sb_msg_valid = 0;
        rx_sb_msg = 0;
        rx_msginfo = 0;
        rx_data_field = 0;
        phy_rx_tckn_shift = 0;
        phy_rx_decrement_shift = 0;
        phy_tx_tckn_shift_out_of_range = 0;
        repeat(5) @(posedge lclk);
        rst_n = 1;
        repeat(2) @(posedge lclk);
    endtask

    task release_soft_reset_sequence(input state_n_e entry_state);
        @(negedge lclk);
        state_n_0 = LOG_RESET;
        repeat(5) @(posedge lclk);

        @(negedge lclk);
        state_n_0 = LOG_SBINIT;
        repeat(3) @(posedge lclk);

        @(negedge lclk);
        state_n_0 = entry_state;
        repeat(2) @(posedge lclk);
    endtask

    task start_mbtrain();
        @(posedge lclk);
        mbtrain_en = 1;
    endtask

    task stop_mbtrain();
        @(posedge lclk);
        mbtrain_en = 0;
    endtask

    task send_rx_msg(input logic [7:0] msg, input logic [15:0] info, input logic [63:0] data);
        @(posedge lclk);
        rx_sb_msg_valid = 1;
        rx_sb_msg = msg;
        rx_msginfo = info;
        rx_data_field = data;
        @(posedge lclk);
        rx_sb_msg_valid = 0;
    endtask

    task clear_rx_msg();
        rx_sb_msg_valid = 0;
        rx_sb_msg = 0;
        rx_msginfo = 0;
        rx_data_field = 0;
    endtask

    task drive_d2c_result(input logic [15:0] perlane_pass);
        d2c_perlane_pass = perlane_pass;
    endtask

    task wait_lclk(input int cycles);
        repeat(cycles) @(posedge lclk);
    endtask

endinterface
