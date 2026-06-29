// =============================================================================
// mbtrain_cb_if.sv — MBTRAIN Class-Based TB Interface
// All wrapper_MBTRAIN ports + TB-internal debug signals
// =============================================================================
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

interface mbtrain_cb_if (input logic lclk, input logic rst_n);

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    // lclk and rst_n are already module ports (passed to interface constructor)

    // =========================================================================
    // MBTRAIN Control
    // =========================================================================
    logic        mbtrain_en;
    logic        mbtrain_done;
    state_n_e    current_mbtrain_substate;

    logic        ltsm_trainerror_req;
    logic        ltsm_linkinit_req;
    logic        ltsm_phyretrain_req;

    logic        mbtrain_txselfcal_req;
    logic        mbtrain_speedidle_req;
    logic        mbtrain_repair_req;

    // =========================================================================
    // Analog settle timer
    // =========================================================================
    logic        analog_settle_time_done;
    logic        analog_settle_timer_en;

    // =========================================================================
    // LTSM state history
    // =========================================================================
    state_n_e    state_n_0;
    state_n_e    state_n_1;   // driven by TB wrapper combinational logic

    // =========================================================================
    // Configuration registers
    // =========================================================================
    logic [2:0]  param_negotiated_max_speed;
    logic        is_continuous_clk_mode;
    logic        rf_cap_SPMW;
    logic [3:0]  rf_ctrl_target_link_width;
    logic        param_UCIe_S_x8;

    // PHY retrain flags
    logic        PHY_IN_RETRAIN;
    logic        params_changed;
    logic        PHY_IN_RETRAIN_rst;
    logic        busy_bit_rst;

    // Lane masks
    logic [2:0]  mbinit_rx_data_lane_mask;
    logic [2:0]  mbinit_tx_data_lane_mask;
    logic [2:0]  mb_rx_data_lane_mask;
    logic [2:0]  mb_tx_data_lane_mask;

    // =========================================================================
    // D2C Sweep engine interface
    // =========================================================================
    logic        local_sweep_en;
    logic        partner_sweep_en;
    logic [15:0] sweep_active_lanes;
    logic        sweep_done;
    logic [4:0]  sweep_swept_code;
    logic [4:0]  sweep_best_code [0:15];
    logic [4:0]  sweep_min_eye_width;
    logic [15:0] d2c_perlane_pass;

    // =========================================================================
    // PHY controls (outputs from DUT that TB monitors)
    // =========================================================================
    logic [2:0]  phy_negotiated_speed;
    logic        phy_tx_selfcal_en;
    logic        phy_rx_clock_lock_en;
    logic        phy_rx_track_lock_en;
    logic        phy_rx_phase_detector_en;
    logic        phy_tx_tckn_shift_en;
    logic [4:0]  phy_tx_tckn_shift;
    logic        phy_tx_decrement_shift;

    logic [4:0]  phy_rx_val_vref_ctrl;
    logic [4:0]  phy_rx_data_vref_ctrl [0:15];
    logic [4:0]  phy_tx_val_pi_phase_ctrl;
    logic [4:0]  phy_tx_data_pi_phase_ctrl [0:15];
    logic [4:0]  phy_rx_deskew_ctrl        [0:15];
    logic [2:0]  phy_tx_eq_preset_ctrl;
    logic        phy_tx_eq_preset_en;

    // =========================================================================
    // Mainband lane selectors (monitored by TB)
    // =========================================================================
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

    // =========================================================================
    // Sideband signals
    // =========================================================================
    // DUT → TB  (what the DUT is transmitting)
    logic        substate_tx_sb_msg_valid;
    logic [7:0]  substate_tx_sb_msg;
    logic [15:0] substate_tx_msginfo;
    logic [63:0] substate_tx_data_field;

    // TB → DUT  (what the TB is injecting as received sideband)
    logic        rx_sb_msg_valid;
    logic [7:0]  rx_sb_msg;
    logic [15:0] rx_msginfo;

    // =========================================================================
    // Debug signals (hierarchy probes assigned in the top module)
    // =========================================================================
    logic        dbg_soft_rst_n;
    logic [2:0]  dbg_valvref_local_state;
    logic [2:0]  dbg_valvref_partner_state;
    logic        dbg_valvref_local_done;
    logic        dbg_valvref_partner_done;

    // =========================================================================
    // Tasks & functions
    // =========================================================================

    // Apply hard reset: hold for 10 cycles
    task automatic drive_reset();
        @(negedge lclk);
        state_n_0              = LOG_NOP;
        mbtrain_en             = 1'b0;
        mbtrain_txselfcal_req  = 1'b0;
        mbtrain_speedidle_req  = 1'b0;
        mbtrain_repair_req     = 1'b0;
        rx_sb_msg_valid        = 1'b0;
        rx_sb_msg              = 8'h00;
        rx_msginfo             = 16'h0000;
        analog_settle_time_done= 1'b0;
        sweep_done             = 1'b0;
        sweep_swept_code       = '0;
        foreach (sweep_best_code[i]) sweep_best_code[i] = '0;
        sweep_min_eye_width    = '0;
        d2c_perlane_pass       = 16'hFFFF;
        PHY_IN_RETRAIN         = 1'b0;
        params_changed         = 1'b0;
        is_continuous_clk_mode = 1'b0;
    endtask

    // Release the internal soft_rst_n by toggling state_n_0 LOG_RESET→LOG_SBINIT
    // (wrapper_MBTRAIN generates soft_rst_n from state_n_0 internally)
    task automatic release_soft_reset_sequence();
        @(negedge lclk);
        state_n_0 = LOG_RESET;
        repeat(3) @(posedge lclk);
        @(negedge lclk);
        state_n_0 = LOG_SBINIT;
        repeat(3) @(posedge lclk);
        @(negedge lclk);
        state_n_0 = LOG_MBTRAIN;
    endtask

    // Assert mbtrain_en
    task automatic start_mbtrain();
        @(negedge lclk);
        mbtrain_en = 1'b1;
    endtask

    // Deassert mbtrain_en
    task automatic stop_mbtrain();
        @(negedge lclk);
        mbtrain_en = 1'b0;
    endtask

    // Inject one sideband received message (1-cycle pulse)
    task automatic send_rx_msg(
        input logic [7:0]  msg,
        input logic [15:0] info  = 16'h0000,
        input logic [63:0] data  = 64'h0
    );
        @(negedge lclk);
        rx_sb_msg_valid = 1'b1;
        rx_sb_msg       = msg;
        rx_msginfo      = info;
        @(posedge lclk);
        @(negedge lclk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = 8'h00;
        rx_msginfo      = 16'h0000;
    endtask

    // Clear any pending RX pulse immediately
    task automatic clear_rx_msg();
        @(negedge lclk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = 8'h00;
        rx_msginfo      = 16'h0000;
    endtask

    // Drive D2C sweep result combinationally
    task automatic drive_d2c_result(input logic [15:0] perlane_pass);
        d2c_perlane_pass = perlane_pass;
    endtask

    // Wait N lclk cycles
    task automatic wait_lclk(input int cycles);
        repeat(cycles) @(posedge lclk);
    endtask

    // Wait for analog settle: assert after analog_settle_cycles posedges
    task automatic do_analog_settle(input int settle_cycles = 5);
        repeat(settle_cycles) @(posedge lclk);
        @(negedge lclk);
        analog_settle_time_done = 1'b1;
        @(posedge lclk);
        @(negedge lclk);
        analog_settle_time_done = 1'b0;
    endtask

endinterface
