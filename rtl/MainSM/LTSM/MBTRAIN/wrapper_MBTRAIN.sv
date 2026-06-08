// ====================================================================================================
// wrapper_MBTRAIN.sv
//
// Top-level MBTRAIN integration wrapper.
// - No SystemVerilog interfaces are used inside this RTL wrapper.
// - The shared D2C sweep and D2C point-test wrappers remain outside this module.
// - This wrapper sequences the 13 MBTRAIN substates, gathers common requests, and exports one raw
//   sweep/D2C-facing port bundle for higher-level integration.
//
// Organization:
//   1. Port list.
//   2. Local parameters and shared wire/reg declarations.
//   3. Input-only preparation logic for instantiated modules.
//   4. Common-file instantiations.
//   5. Substate instantiations in MBTRAIN order.
//   6. Output arbitration, muxing, and retained PHY controls.
// ====================================================================================================

module wrapper_MBTRAIN #(
        parameter int unsigned MAX_VAL_VREF_CODE  = 7'd127,
        parameter int unsigned MIN_VAL_VREF_CODE  = 7'd10,
        parameter int unsigned MAX_DATA_VREF_CODE = 7'd127,
        parameter int unsigned MIN_DATA_VREF_CODE = 7'd10,
        parameter int unsigned MAX_DATA_PI_CODE   = 6'd63,
        parameter int unsigned MIN_DATA_PI_CODE   = 6'd0,
        parameter int unsigned MAX_VAL_PI_CODE    = 6'd63,
        parameter int unsigned MIN_VAL_PI_CODE    = 6'd0,
        parameter int unsigned MAX_DESKEW_CODE    = 7'd127,
        parameter int unsigned MIN_DESKEW_CODE    = 7'd0
    ) (
        // Clock, reset, and MBTRAIN state control
        input  logic        lclk,
        input  logic        rst_n,
        input  logic        is_ltsm_out_of_reset,
        input  logic        mbtrain_en,
        output logic        mbtrain_done,
        output logic [3:0]  current_mbtrain_substate,

        output logic        ltsm_trainerror_req,
        output logic        ltsm_linkinit_req,
        output logic        ltsm_phyretrain_req,
        output logic        ltsm_repair_req,
        output logic        ltsm_speedidle_req,

        input  logic        mbtrain_txselfcal_req,
        input  logic        mbtrain_speedidle_req,
        input  logic        mbtrain_repair_req,

        // Timer inputs and combined timer enables
        input  logic        timeout_8ms_occured,
        input  logic        analog_settle_time_done,
        output logic        timeout_timer_en,
        output logic        analog_settle_timer_en,

        // Register-file / LTSM configuration
        input  wire ltsm_state_n_pkg::state_n_e state_n [3:0],
        input  logic [2:0]  param_negotiated_max_speed,
        input  logic        is_continuous_clk_mode,
        input  logic        rf_cap_SPMW,
        input  logic [3:0]  rf_ctrl_target_link_width,
        input  logic        param_UCIe_S_x8,

        input  logic        PHY_IN_RETRAIN,
        input  logic        params_changed,
        output logic        PHY_IN_RETRAIN_rst,
        output logic        busy_bit_rst,

        // Lane-mask ownership
        input  logic [2:0]  mbinit_rx_data_lane_mask,
        input  logic [2:0]  mbinit_tx_data_lane_mask,
        output logic [2:0]  mb_rx_data_lane_mask,
        output logic [2:0]  mb_tx_data_lane_mask,

        // External D2C sweep engine interface
        output logic        local_sweep_en,
        output logic        partner_sweep_en,
        output logic [15:0] sweep_active_lanes,
        output ltsm_state_n_pkg::state_n_e d2c_state_n,
        input  logic        sweep_done,
        input  logic [6:0]  sweep_swept_code,
        input  wire logic [6:0] sweep_best_code [0:15],
        input  logic [6:0]  sweep_min_eye_width,

        // External D2C point-test results
        input  logic [15:0] d2c_perlane_pass,

        // PHY controls driven by MBTRAIN substates
        output logic [2:0]  phy_negotiated_speed,
        output logic        phy_tx_selfcal_en,
        output logic        phy_rx_clock_lock_en,
        output logic        phy_rx_track_lock_en,
        output logic        phy_rx_phase_detector_en,

        input  logic [4:0]  phy_rx_tckn_shift,
        input  logic        phy_rx_decrement_shift,
        output logic        phy_tx_tckn_shift_en,
        output logic [4:0]  phy_tx_tckn_shift,
        output logic        phy_tx_decrement_shift,
        input  logic        phy_tx_tckn_shift_out_of_range,

        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  phy_rx_valvref_ctrl,
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15],
        output logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]    phy_tx_val_pi_phase_ctrl,
        output logic [$clog2(MAX_DATA_PI_CODE+1)-1:0]   phy_tx_data_pi_phase_ctrl [0:15],
        output logic [6:0]  phy_rx_deskew_ctrl [15:0],
        output logic [2:0]  phy_tx_eq_preset_ctrl,
        output logic        phy_tx_eq_preset_en,

        // Selected substate mainband lane selectors
        output logic [1:0]  substate_mb_tx_clk_lane_sel,
        output logic [1:0]  substate_mb_tx_data_lane_sel,
        output logic [1:0]  substate_mb_tx_val_lane_sel,
        output logic [1:0]  substate_mb_tx_trk_lane_sel,
        output logic        substate_mb_rx_clk_lane_sel,
        output logic        substate_mb_rx_data_lane_sel,
        output logic        substate_mb_rx_val_lane_sel,
        output logic        substate_mb_rx_trk_lane_sel,

        // Selected substate pattern-control outputs, currently owned by RXCLKCAL
        output logic        rxclkcal_mb_tx_pattern_en,
        output logic [2:0]  rxclkcal_mb_tx_pattern_setup,
        output logic [1:0]  rxclkcal_mb_tx_clk_pattern_sel,

        // Selected substate sideband TX output
        output logic        substate_tx_sb_msg_valid,
        output logic [7:0]  substate_tx_sb_msg,
        output logic [15:0] substate_tx_msginfo,
        output logic [63:0] substate_tx_data_field,

        // Broadcast sideband RX input
        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    import ltsm_state_n_pkg::*;

    // ================================================================================================
    // 2. Local parameters and shared declarations
    // ================================================================================================
    localparam int unsigned NUM_SUBSTATES = 13;
    localparam int unsigned SS_VALVREF          = 0;
    localparam int unsigned SS_DATAVREF         = 1;
    localparam int unsigned SS_SPEEDIDLE        = 2;
    localparam int unsigned SS_TXSELFCAL        = 3;
    localparam int unsigned SS_RXCLKCAL         = 4;
    localparam int unsigned SS_VALTRAINCENTER   = 5;
    localparam int unsigned SS_VALTRAINVREF     = 6;
    localparam int unsigned SS_DTC1             = 7;
    localparam int unsigned SS_DATATRAINVREF    = 8;
    localparam int unsigned SS_RXDESKEW         = 9;
    localparam int unsigned SS_DTC2             = 10;
    localparam int unsigned SS_LINKSPEED        = 11;
    localparam int unsigned SS_REPAIR           = 12;

    localparam int unsigned VAL_VREF_W  = $clog2(MAX_VAL_VREF_CODE  + 1);
    localparam int unsigned DATA_VREF_W = $clog2(MAX_DATA_VREF_CODE + 1);
    localparam int unsigned VAL_PI_W    = $clog2(MAX_VAL_PI_CODE    + 1);
    localparam int unsigned DATA_PI_W   = $clog2(MAX_DATA_PI_CODE   + 1);

    // Controller handshakes.
    logic local_valvref_en,          local_valvref_done,          partner_valvref_en,          partner_valvref_done;
    logic local_datavref_en,         local_datavref_done,         partner_datavref_en,         partner_datavref_done;
    logic local_speedidle_en,        local_speedidle_done,        partner_speedidle_en,        partner_speedidle_done;
    logic local_txselfcal_en,        local_txselfcal_done,        partner_txselfcal_en,        partner_txselfcal_done;
    logic local_rxclkcal_en,         local_rxclkcal_done,         partner_rxclkcal_en,         partner_rxclkcal_done;
    logic local_valtraincenter_en,   local_valtraincenter_done,   partner_valtraincenter_en,   partner_valtraincenter_done;
    logic local_valtrainvref_en,     local_valtrainvref_done,     partner_valtrainvref_en,     partner_valtrainvref_done;
    logic local_dtc1_en,             local_dtc1_done,             partner_dtc1_en,             partner_dtc1_done;
    logic local_datatrainvref_en,    local_datatrainvref_done,    partner_datatrainvref_en,    partner_datatrainvref_done;
    logic local_rxdeskew_en,         local_rxdeskew_done,         partner_rxdeskew_en,         partner_rxdeskew_done;
    logic local_dtc2_en,             local_dtc2_done,             partner_dtc2_en,             partner_dtc2_done;
    logic local_linkspeed_en,        local_linkspeed_done,        partner_linkspeed_en,        partner_linkspeed_done;
    logic local_repair_en,           local_repair_done,           partner_repair_en,           partner_repair_done;

    // Per-substate requests and output bundles.
    logic [NUM_SUBSTATES-1:0] ss_active;
    logic [NUM_SUBSTATES-1:0] ss_local_trainerror_req;
    logic [NUM_SUBSTATES-1:0] ss_partner_trainerror_req;
    logic [NUM_SUBSTATES-1:0] ss_timeout_timer_en;
    logic [NUM_SUBSTATES-1:0] ss_analog_settle_timer_en;
    logic [NUM_SUBSTATES-1:0] ss_sweep_en;
    logic [NUM_SUBSTATES-1:0] ss_partner_sweep_en;
    logic [NUM_SUBSTATES-1:0] ss_update_lane_mask;

    logic [1:0]  ss_mb_tx_clk_lane_sel  [0:NUM_SUBSTATES-1];
    logic [1:0]  ss_mb_tx_data_lane_sel [0:NUM_SUBSTATES-1];
    logic [1:0]  ss_mb_tx_val_lane_sel  [0:NUM_SUBSTATES-1];
    logic [1:0]  ss_mb_tx_trk_lane_sel  [0:NUM_SUBSTATES-1];
    logic        ss_mb_rx_clk_lane_sel  [0:NUM_SUBSTATES-1];
    logic        ss_mb_rx_data_lane_sel [0:NUM_SUBSTATES-1];
    logic        ss_mb_rx_val_lane_sel  [0:NUM_SUBSTATES-1];
    logic        ss_mb_rx_trk_lane_sel  [0:NUM_SUBSTATES-1];

    logic        ss_tx_sb_msg_valid [0:NUM_SUBSTATES-1];
    logic [7:0]  ss_tx_sb_msg       [0:NUM_SUBSTATES-1];
    logic [15:0] ss_tx_msginfo      [0:NUM_SUBSTATES-1];
    logic [63:0] ss_tx_data_field   [0:NUM_SUBSTATES-1];

    // Common decoder outputs and lane-map degradation result.
    logic        is_high_speed;
    logic [15:0] active_rx_lanes;
    logic [15:0] active_tx_lanes;
    logic [15:0] linkspeed_success_lanes;
    logic [2:0]  degraded_lane_map_code;
    logic        degrade_feasible;

    // Output/control signals that need arbitration or value retention.
    logic [2:0]  speedidle_phy_negotiated_speed;
    logic        txselfcal_phy_tx_selfcal_en;
    logic        rxclkcal_phy_rx_clock_lock_en;
    logic        rxclkcal_phy_rx_track_lock_en;
    logic        rxclkcal_phy_rx_phase_detector_en;
    logic        rxclkcal_phy_tx_tckn_shift_en;
    logic [4:0]  rxclkcal_phy_tx_tckn_shift;
    logic        rxclkcal_phy_tx_decrement_shift;

    logic [VAL_VREF_W-1:0]  valvref_phy_rx_valvref_ctrl;
    logic [VAL_VREF_W-1:0]  valtrainvref_phy_rx_valvref_ctrl;
    logic [DATA_VREF_W-1:0] datavref_phy_rx_datavref_ctrl      [0:15];
    logic [DATA_VREF_W-1:0] datatrainvref_phy_rx_datavref_ctrl [0:15];
    logic [VAL_PI_W-1:0]    valtraincenter_phy_tx_val_pi_phase_ctrl;
    logic [DATA_PI_W-1:0]   dtc1_phy_tx_data_pi_phase_ctrl     [0:15];
    logic [DATA_PI_W-1:0]   dtc2_phy_tx_data_pi_phase_ctrl     [0:15];
    logic [6:0]             rxdeskew_phy_rx_deskew_ctrl        [15:0];
    logic [2:0]             rxdeskew_phy_tx_eq_preset_ctrl;
    logic                   rxdeskew_phy_tx_eq_preset_en;

    // Retained values keep externally visible PHY controls stable between substates.
    logic [2:0]             phy_negotiated_speed_r;
    logic [VAL_VREF_W-1:0]  phy_rx_valvref_ctrl_r;
    logic [DATA_VREF_W-1:0] phy_rx_datavref_ctrl_r [0:15];
    logic [VAL_PI_W-1:0]    phy_tx_val_pi_phase_ctrl_r;
    logic [DATA_PI_W-1:0]   phy_tx_data_pi_phase_ctrl_r [0:15];
    logic [6:0]             phy_rx_deskew_ctrl_r [15:0];
    logic [2:0]             phy_tx_eq_preset_ctrl_r;

    // Sliced versions of the shared 7-bit sweep bus for narrower substate wrappers.
    logic [VAL_VREF_W-1:0]  swept_val_vref_code;
    logic [DATA_VREF_W-1:0] swept_data_vref_code;
    logic [VAL_PI_W-1:0]    swept_val_pi_code;
    logic [DATA_PI_W-1:0]   swept_data_pi_code;
    logic [VAL_VREF_W-1:0]  best_val_vref_code  [0:15];
    logic [DATA_VREF_W-1:0] best_data_vref_code [0:15];
    logic [VAL_PI_W-1:0]    best_val_pi_code    [0:15];
    logic [DATA_PI_W-1:0]   best_data_pi_code   [0:15];

    // ================================================================================================
    // 3. Input-only preparation logic
    // ================================================================================================
    assign swept_val_vref_code  = sweep_swept_code[VAL_VREF_W-1:0];
    assign swept_data_vref_code = sweep_swept_code[DATA_VREF_W-1:0];
    assign swept_val_pi_code    = sweep_swept_code[VAL_PI_W-1:0];
    assign swept_data_pi_code   = sweep_swept_code[DATA_PI_W-1:0];

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane++) begin : g_sweep_code_slices
            assign best_val_vref_code [lane] = sweep_best_code[lane][VAL_VREF_W-1:0];
            assign best_data_vref_code[lane] = sweep_best_code[lane][DATA_VREF_W-1:0];
            assign best_val_pi_code   [lane] = sweep_best_code[lane][VAL_PI_W-1:0];
            assign best_data_pi_code  [lane] = sweep_best_code[lane][DATA_PI_W-1:0];
        end
    endgenerate

    assign ss_active[SS_VALVREF]        = local_valvref_en        | partner_valvref_en;
    assign ss_active[SS_DATAVREF]       = local_datavref_en       | partner_datavref_en;
    assign ss_active[SS_SPEEDIDLE]      = local_speedidle_en      | partner_speedidle_en;
    assign ss_active[SS_TXSELFCAL]      = local_txselfcal_en      | partner_txselfcal_en;
    assign ss_active[SS_RXCLKCAL]       = local_rxclkcal_en       | partner_rxclkcal_en;
    assign ss_active[SS_VALTRAINCENTER] = local_valtraincenter_en | partner_valtraincenter_en;
    assign ss_active[SS_VALTRAINVREF]   = local_valtrainvref_en   | partner_valtrainvref_en;
    assign ss_active[SS_DTC1]           = local_dtc1_en           | partner_dtc1_en;
    assign ss_active[SS_DATATRAINVREF]  = local_datatrainvref_en  | partner_datatrainvref_en;
    assign ss_active[SS_RXDESKEW]       = local_rxdeskew_en       | partner_rxdeskew_en;
    assign ss_active[SS_DTC2]           = local_dtc2_en           | partner_dtc2_en;
    assign ss_active[SS_LINKSPEED]      = local_linkspeed_en      | partner_linkspeed_en;
    assign ss_active[SS_REPAIR]         = local_repair_en         | partner_repair_en;

    logic trainerror_detected;
    logic local_dtc1_loopback_req;
    logic local_linkinit_route_req;
    logic local_speedidle_route_req;
    logic local_repair_route_req;
    logic local_phyretrain_route_req;
    logic local_repair_txselfcal_req;
    logic repair_update_lane_mask;

    assign trainerror_detected = |ss_local_trainerror_req | |ss_partner_trainerror_req;

    assign local_sweep_en     = |ss_sweep_en;
    assign partner_sweep_en   = |ss_partner_sweep_en;
    // assign timeout_timer_en   = |ss_timeout_timer_en;
    // assign analog_settle_timer_en = |ss_analog_settle_timer_en;
    assign sweep_active_lanes = active_rx_lanes;


    // ================================================================================================
    // 4. Common-file instantiations
    // ================================================================================================
    unit_MBTRAIN_ctrl u_MBTRAIN_ctrl (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .mbtrain_en                   (mbtrain_en),
        .mbtrain_done                 (mbtrain_done),
        .current_mbtrain_substate     (current_mbtrain_substate),
        .trainerror_detected          (trainerror_detected),
        .ltsm_trainerror_req          (ltsm_trainerror_req),
        .ltsm_linkinit_req            (ltsm_linkinit_req),
        .ltsm_phyretrain_req          (ltsm_phyretrain_req),
        .ltsm_repair_req              (ltsm_repair_req),
        .ltsm_speedidle_req           (ltsm_speedidle_req),
        .mbtrain_txselfcal_req        (mbtrain_txselfcal_req),
        .mbtrain_speedidle_req        (mbtrain_speedidle_req),
        .mbtrain_repair_req           (mbtrain_repair_req),
        .local_valvref_en             (local_valvref_en),
        .local_valvref_done           (local_valvref_done),
        .partner_valvref_en           (partner_valvref_en),
        .partner_valvref_done         (partner_valvref_done),
        .local_datavref_en            (local_datavref_en),
        .local_datavref_done          (local_datavref_done),
        .partner_datavref_en          (partner_datavref_en),
        .partner_datavref_done        (partner_datavref_done),
        .local_speedidle_en           (local_speedidle_en),
        .local_speedidle_done         (local_speedidle_done),
        .partner_speedidle_en         (partner_speedidle_en),
        .partner_speedidle_done       (partner_speedidle_done),
        .local_txselfcal_en           (local_txselfcal_en),
        .local_txselfcal_done         (local_txselfcal_done),
        .partner_txselfcal_en         (partner_txselfcal_en),
        .partner_txselfcal_done       (partner_txselfcal_done),
        .local_rxclkcal_en            (local_rxclkcal_en),
        .local_rxclkcal_done          (local_rxclkcal_done),
        .partner_rxclkcal_en          (partner_rxclkcal_en),
        .partner_rxclkcal_done        (partner_rxclkcal_done),
        .local_valtraincenter_en      (local_valtraincenter_en),
        .local_valtraincenter_done    (local_valtraincenter_done),
        .partner_valtraincenter_en    (partner_valtraincenter_en),
        .partner_valtraincenter_done  (partner_valtraincenter_done),
        .local_valtrainvref_en        (local_valtrainvref_en),
        .local_valtrainvref_done      (local_valtrainvref_done),
        .partner_valtrainvref_en      (partner_valtrainvref_en),
        .partner_valtrainvref_done    (partner_valtrainvref_done),
        .local_dtc1_en                (local_dtc1_en),
        .local_dtc1_done              (local_dtc1_done),
        .partner_dtc1_en              (partner_dtc1_en),
        .partner_dtc1_done            (partner_dtc1_done),
        .local_datatrainvref_en       (local_datatrainvref_en),
        .local_datatrainvref_done     (local_datatrainvref_done),
        .partner_datatrainvref_en     (partner_datatrainvref_en),
        .partner_datatrainvref_done   (partner_datatrainvref_done),
        .local_rxdeskew_en            (local_rxdeskew_en),
        .local_rxdeskew_done          (local_rxdeskew_done),
        .partner_rxdeskew_en          (partner_rxdeskew_en),
        .partner_rxdeskew_done        (partner_rxdeskew_done),
        .local_dtc1_loopback_req      (local_dtc1_loopback_req),
        .local_dtc2_en                (local_dtc2_en),
        .local_dtc2_done              (local_dtc2_done),
        .partner_dtc2_en              (partner_dtc2_en),
        .partner_dtc2_done            (partner_dtc2_done),
        .local_linkspeed_en           (local_linkspeed_en),
        .local_linkspeed_done         (local_linkspeed_done),
        .partner_linkspeed_en         (partner_linkspeed_en),
        .partner_linkspeed_done       (partner_linkspeed_done),
        .local_linkinit_route_req     (local_linkinit_route_req),
        .local_speedidle_route_req    (local_speedidle_route_req),
        .local_repair_route_req       (local_repair_route_req),
        .local_phyretrain_route_req   (local_phyretrain_route_req),
        .local_repair_en              (local_repair_en),
        .local_repair_done            (local_repair_done),
        .partner_repair_en            (partner_repair_en),
        .partner_repair_done          (partner_repair_done),
        .local_repair_txselfcal_req   (local_repair_txselfcal_req)
    );

    unit_negotiated_speed u_negotiated_speed (
        .phy_negotiated_speed (phy_negotiated_speed),
        .is_high_speed        (is_high_speed)
    );

    unit_negotiated_lanes u_negotiated_lanes (
        .mb_rx_data_lane_mask      (mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask      (mb_tx_data_lane_mask),
        .active_rx_lanes           (active_rx_lanes),
        .active_tx_lanes           (active_tx_lanes),
        .success_lanes             (linkspeed_success_lanes),
        .rf_cap_SPMW               (rf_cap_SPMW),
        .rf_ctrl_target_link_width (rf_ctrl_target_link_width),
        .param_UCIe_S_x8           (param_UCIe_S_x8),
        .degraded_lane_map_code    (degraded_lane_map_code),
        .degrade_feasible          (degrade_feasible)
    );

    // ================================================================================================
    // 5. Substate instantiations in MBTRAIN order
    // ================================================================================================
    wrapper_VALVREF #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE)
    ) u_VALVREF (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .is_ltsm_out_of_reset  (is_ltsm_out_of_reset),
        .timeout_8ms_occured   (timeout_8ms_occured),
        .local_valvref_en      (local_valvref_en),
        .local_valvref_done    (local_valvref_done),
        .local_trainerror_req  (ss_local_trainerror_req[SS_VALVREF]),
        .local_update_lane_mask(ss_update_lane_mask[SS_VALVREF]),
        .partner_valvref_en    (partner_valvref_en),
        .partner_valvref_done  (partner_valvref_done),
        .partner_trainerror_req(ss_partner_trainerror_req[SS_VALVREF]),
        .timeout_timer_en      (ss_timeout_timer_en[SS_VALVREF]),
        .phy_rx_valvref_ctrl   (valvref_phy_rx_valvref_ctrl),
        .partner_sweep_en      (ss_partner_sweep_en[SS_VALVREF]),
        .sweep_en              (ss_sweep_en[SS_VALVREF]),
        .swept_code            (swept_val_vref_code),
        .best_code             (best_val_vref_code),
        .sweep_done            (sweep_done),
        .mb_tx_clk_lane_sel    (ss_mb_tx_clk_lane_sel[SS_VALVREF]),
        .mb_tx_data_lane_sel   (ss_mb_tx_data_lane_sel[SS_VALVREF]),
        .mb_tx_val_lane_sel    (ss_mb_tx_val_lane_sel[SS_VALVREF]),
        .mb_tx_trk_lane_sel    (ss_mb_tx_trk_lane_sel[SS_VALVREF]),
        .mb_rx_clk_lane_sel    (ss_mb_rx_clk_lane_sel[SS_VALVREF]),
        .mb_rx_data_lane_sel   (ss_mb_rx_data_lane_sel[SS_VALVREF]),
        .mb_rx_val_lane_sel    (ss_mb_rx_val_lane_sel[SS_VALVREF]),
        .mb_rx_trk_lane_sel    (ss_mb_rx_trk_lane_sel[SS_VALVREF]),
        .tx_sb_msg_valid       (ss_tx_sb_msg_valid[SS_VALVREF]),
        .tx_sb_msg             (ss_tx_sb_msg[SS_VALVREF]),
        .tx_msginfo            (ss_tx_msginfo[SS_VALVREF]),
        .tx_data_field         (ss_tx_data_field[SS_VALVREF]),
        .rx_sb_msg_valid       (rx_sb_msg_valid),
        .rx_sb_msg             (rx_sb_msg),
        .rx_msginfo            (rx_msginfo),
        .rx_data_field         (rx_data_field)
    );

    wrapper_DATAVREF #(
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE (MIN_DATA_VREF_CODE)
    ) u_DATAVREF (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .is_ltsm_out_of_reset  (is_ltsm_out_of_reset),
        .timeout_8ms_occured   (timeout_8ms_occured),
        .local_datavref_en     (local_datavref_en),
        .local_datavref_done   (local_datavref_done),
        .local_trainerror_req  (ss_local_trainerror_req[SS_DATAVREF]),
        .local_update_lane_mask(ss_update_lane_mask[SS_DATAVREF]),
        .partner_datavref_en   (partner_datavref_en),
        .partner_datavref_done (partner_datavref_done),
        .partner_trainerror_req(ss_partner_trainerror_req[SS_DATAVREF]),
        .timeout_timer_en      (ss_timeout_timer_en[SS_DATAVREF]),
        .phy_rx_datavref_ctrl  (datavref_phy_rx_datavref_ctrl),
        .partner_sweep_en      (ss_partner_sweep_en[SS_DATAVREF]),
        .sweep_en              (ss_sweep_en[SS_DATAVREF]),
        .swept_code            (swept_data_vref_code),
        .best_code             (best_data_vref_code),
        .sweep_done            (sweep_done),
        .mb_tx_clk_lane_sel    (ss_mb_tx_clk_lane_sel[SS_DATAVREF]),
        .mb_tx_data_lane_sel   (ss_mb_tx_data_lane_sel[SS_DATAVREF]),
        .mb_tx_val_lane_sel    (ss_mb_tx_val_lane_sel[SS_DATAVREF]),
        .mb_tx_trk_lane_sel    (ss_mb_tx_trk_lane_sel[SS_DATAVREF]),
        .mb_rx_clk_lane_sel    (ss_mb_rx_clk_lane_sel[SS_DATAVREF]),
        .mb_rx_data_lane_sel   (ss_mb_rx_data_lane_sel[SS_DATAVREF]),
        .mb_rx_val_lane_sel    (ss_mb_rx_val_lane_sel[SS_DATAVREF]),
        .mb_rx_trk_lane_sel    (ss_mb_rx_trk_lane_sel[SS_DATAVREF]),
        .tx_sb_msg_valid       (ss_tx_sb_msg_valid[SS_DATAVREF]),
        .tx_sb_msg             (ss_tx_sb_msg[SS_DATAVREF]),
        .tx_msginfo            (ss_tx_msginfo[SS_DATAVREF]),
        .tx_data_field         (ss_tx_data_field[SS_DATAVREF]),
        .rx_sb_msg_valid       (rx_sb_msg_valid),
        .rx_sb_msg             (rx_sb_msg),
        .rx_msginfo            (rx_msginfo),
        .rx_data_field         (rx_data_field)
    );

    wrapper_SPEEDIDLE u_SPEEDIDLE (
        .lclk                    (lclk),
        .rst_n                   (rst_n),
        .is_ltsm_out_of_reset    (is_ltsm_out_of_reset),
        .timeout_8ms_occured     (timeout_8ms_occured),
        .local_speedidle_en      (local_speedidle_en),
        .local_speedidle_done    (local_speedidle_done),
        .local_trainerror_req    (ss_local_trainerror_req[SS_SPEEDIDLE]),
        .partner_speedidle_en    (partner_speedidle_en),
        .partner_speedidle_done  (partner_speedidle_done),
        .partner_trainerror_req  (ss_partner_trainerror_req[SS_SPEEDIDLE]),
        .timeout_timer_en        (ss_timeout_timer_en[SS_SPEEDIDLE]),
        .analog_settle_timer_en  (ss_analog_settle_timer_en[SS_SPEEDIDLE]),
        .analog_settle_time_done (analog_settle_time_done),
        .state_n                 (state_n),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .phy_negotiated_speed    (speedidle_phy_negotiated_speed),
        .mb_tx_clk_lane_sel      (ss_mb_tx_clk_lane_sel[SS_SPEEDIDLE]),
        .mb_tx_data_lane_sel     (ss_mb_tx_data_lane_sel[SS_SPEEDIDLE]),
        .mb_tx_val_lane_sel      (ss_mb_tx_val_lane_sel[SS_SPEEDIDLE]),
        .mb_tx_trk_lane_sel      (ss_mb_tx_trk_lane_sel[SS_SPEEDIDLE]),
        .mb_rx_clk_lane_sel      (ss_mb_rx_clk_lane_sel[SS_SPEEDIDLE]),
        .mb_rx_data_lane_sel     (ss_mb_rx_data_lane_sel[SS_SPEEDIDLE]),
        .mb_rx_val_lane_sel      (ss_mb_rx_val_lane_sel[SS_SPEEDIDLE]),
        .mb_rx_trk_lane_sel      (ss_mb_rx_trk_lane_sel[SS_SPEEDIDLE]),
        .tx_sb_msg_valid         (ss_tx_sb_msg_valid[SS_SPEEDIDLE]),
        .tx_sb_msg               (ss_tx_sb_msg[SS_SPEEDIDLE]),
        .tx_msginfo              (ss_tx_msginfo[SS_SPEEDIDLE]),
        .tx_data_field           (ss_tx_data_field[SS_SPEEDIDLE]),
        .rx_sb_msg_valid         (rx_sb_msg_valid),
        .rx_sb_msg               (rx_sb_msg),
        .rx_msginfo              (rx_msginfo),
        .rx_data_field           (rx_data_field)
    );

    wrapper_TXSELFCAL u_TXSELFCAL (
        .lclk                    (lclk),
        .rst_n                   (rst_n),
        .is_ltsm_out_of_reset    (is_ltsm_out_of_reset),
        .timeout_8ms_occured     (timeout_8ms_occured),
        .local_txselfcal_en      (local_txselfcal_en),
        .local_txselfcal_done    (local_txselfcal_done),
        .local_trainerror_req    (ss_local_trainerror_req[SS_TXSELFCAL]),
        .partner_txselfcal_en    (partner_txselfcal_en),
        .partner_txselfcal_done  (partner_txselfcal_done),
        .partner_trainerror_req  (ss_partner_trainerror_req[SS_TXSELFCAL]),
        .timeout_timer_en        (ss_timeout_timer_en[SS_TXSELFCAL]),
        .analog_settle_timer_en  (ss_analog_settle_timer_en[SS_TXSELFCAL]),
        .analog_settle_time_done (analog_settle_time_done),
        .phy_tx_selfcal_en       (txselfcal_phy_tx_selfcal_en),
        .mb_tx_clk_lane_sel      (ss_mb_tx_clk_lane_sel[SS_TXSELFCAL]),
        .mb_tx_data_lane_sel     (ss_mb_tx_data_lane_sel[SS_TXSELFCAL]),
        .mb_tx_val_lane_sel      (ss_mb_tx_val_lane_sel[SS_TXSELFCAL]),
        .mb_tx_trk_lane_sel      (ss_mb_tx_trk_lane_sel[SS_TXSELFCAL]),
        .mb_rx_clk_lane_sel      (ss_mb_rx_clk_lane_sel[SS_TXSELFCAL]),
        .mb_rx_data_lane_sel     (ss_mb_rx_data_lane_sel[SS_TXSELFCAL]),
        .mb_rx_val_lane_sel      (ss_mb_rx_val_lane_sel[SS_TXSELFCAL]),
        .mb_rx_trk_lane_sel      (ss_mb_rx_trk_lane_sel[SS_TXSELFCAL]),
        .tx_sb_msg_valid         (ss_tx_sb_msg_valid[SS_TXSELFCAL]),
        .tx_sb_msg               (ss_tx_sb_msg[SS_TXSELFCAL]),
        .tx_msginfo              (ss_tx_msginfo[SS_TXSELFCAL]),
        .tx_data_field           (ss_tx_data_field[SS_TXSELFCAL]),
        .rx_sb_msg_valid         (rx_sb_msg_valid),
        .rx_sb_msg               (rx_sb_msg),
        .rx_msginfo              (rx_msginfo),
        .rx_data_field           (rx_data_field)
    );

    wrapper_RXCLKCAL u_RXCLKCAL (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .phy_negotiated_speed         (phy_negotiated_speed),
        .is_high_speed                (is_high_speed),
        .is_continuous_clk_mode       (is_continuous_clk_mode),
        .local_rxclkcal_en            (local_rxclkcal_en),
        .local_rxclkcal_done          (local_rxclkcal_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_RXCLKCAL]),
        .partner_rxclkcal_en          (partner_rxclkcal_en),
        .partner_rxclkcal_done        (partner_rxclkcal_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_RXCLKCAL]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_RXCLKCAL]),
        .analog_settle_timer_en       (ss_analog_settle_timer_en[SS_RXCLKCAL]),
        .analog_settle_time_done      (analog_settle_time_done),
        .phy_rx_clock_lock_en         (rxclkcal_phy_rx_clock_lock_en),
        .phy_rx_track_lock_en         (rxclkcal_phy_rx_track_lock_en),
        .phy_rx_phase_detector_en     (rxclkcal_phy_rx_phase_detector_en),
        .phy_rx_tckn_shift            (phy_rx_tckn_shift),
        .phy_rx_decrement_shift       (phy_rx_decrement_shift),
        .phy_tx_tckn_shift_en         (rxclkcal_phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift            (rxclkcal_phy_tx_tckn_shift),
        .phy_tx_decrement_shift       (rxclkcal_phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range(phy_tx_tckn_shift_out_of_range),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_RXCLKCAL]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_RXCLKCAL]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_RXCLKCAL]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_RXCLKCAL]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_RXCLKCAL]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_RXCLKCAL]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_RXCLKCAL]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_RXCLKCAL]),
        .mb_tx_pattern_en             (rxclkcal_mb_tx_pattern_en),
        .mb_tx_pattern_setup          (rxclkcal_mb_tx_pattern_setup),
        .mb_tx_clk_pattern_sel        (rxclkcal_mb_tx_clk_pattern_sel),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_RXCLKCAL]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_RXCLKCAL]),
        .tx_msginfo                   (ss_tx_msginfo[SS_RXCLKCAL]),
        .tx_data_field                (ss_tx_data_field[SS_RXCLKCAL]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_VALTRAINCENTER #(
        .MAX_VAL_PI_CODE (MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE (MIN_VAL_PI_CODE)
    ) u_VALTRAINCENTER (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_valtraincenter_en      (local_valtraincenter_en),
        .local_valtraincenter_done    (local_valtraincenter_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_VALTRAINCENTER]),
        .local_update_lane_mask       (ss_update_lane_mask[SS_VALTRAINCENTER]),
        .partner_valtraincenter_en    (partner_valtraincenter_en),
        .partner_valtraincenter_done  (partner_valtraincenter_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_VALTRAINCENTER]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_VALTRAINCENTER]),
        .phy_tx_val_pi_phase_ctrl     (valtraincenter_phy_tx_val_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_VALTRAINCENTER]),
        .sweep_en                     (ss_sweep_en[SS_VALTRAINCENTER]),
        .swept_code                   (swept_val_pi_code),
        .best_code                    (best_val_pi_code),
        .sweep_done                   (sweep_done),
        .mb_tx_continuous_or_strobe_clk(is_continuous_clk_mode),
        .phy_negotiated_speed         (phy_negotiated_speed),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_VALTRAINCENTER]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_VALTRAINCENTER]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_VALTRAINCENTER]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_VALTRAINCENTER]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_VALTRAINCENTER]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_VALTRAINCENTER]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_VALTRAINCENTER]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_VALTRAINCENTER]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_VALTRAINCENTER]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_VALTRAINCENTER]),
        .tx_msginfo                   (ss_tx_msginfo[SS_VALTRAINCENTER]),
        .tx_data_field                (ss_tx_data_field[SS_VALTRAINCENTER]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_VALTRAINVREF #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE)
    ) u_VALTRAINVREF (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_valtrainvref_en        (local_valtrainvref_en),
        .local_valtrainvref_done      (local_valtrainvref_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_VALTRAINVREF]),
        .local_update_lane_mask       (ss_update_lane_mask[SS_VALTRAINVREF]),
        .partner_valtrainvref_en      (partner_valtrainvref_en),
        .partner_valtrainvref_done    (partner_valtrainvref_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_VALTRAINVREF]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_VALTRAINVREF]),
        .phy_rx_valvref_ctrl          (valtrainvref_phy_rx_valvref_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_VALTRAINVREF]),
        .sweep_en                     (ss_sweep_en[SS_VALTRAINVREF]),
        .swept_code                   (swept_val_vref_code),
        .best_code                    (best_val_vref_code),
        .sweep_done                   (sweep_done),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_VALTRAINVREF]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_VALTRAINVREF]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_VALTRAINVREF]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_VALTRAINVREF]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_VALTRAINVREF]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_VALTRAINVREF]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_VALTRAINVREF]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_VALTRAINVREF]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_VALTRAINVREF]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_VALTRAINVREF]),
        .tx_msginfo                   (ss_tx_msginfo[SS_VALTRAINVREF]),
        .tx_data_field                (ss_tx_data_field[SS_VALTRAINVREF]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_DATATRAINCENTER1 #(
        .MAX_DATA_PI_CODE (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE (MIN_DATA_PI_CODE)
    ) u_DATATRAINCENTER1 (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_datatraincenter1_en    (local_dtc1_en),
        .local_datatraincenter1_done  (local_dtc1_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_DTC1]),
        .local_update_lane_mask       (ss_update_lane_mask[SS_DTC1]),
        .partner_datatraincenter1_en  (partner_dtc1_en),
        .partner_datatraincenter1_done(partner_dtc1_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_DTC1]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_DTC1]),
        .phy_tx_data_pi_phase_ctrl    (dtc1_phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DTC1]),
        .sweep_en                     (ss_sweep_en[SS_DTC1]),
        .swept_code                   (swept_data_pi_code),
        .best_code                    (best_data_pi_code),
        .sweep_done                   (sweep_done),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_DTC1]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_DTC1]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_DTC1]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_DTC1]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_DTC1]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_DTC1]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_DTC1]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_DTC1]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DTC1]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DTC1]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DTC1]),
        .tx_data_field                (ss_tx_data_field[SS_DTC1]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_DATATRAINVREF #(
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE (MIN_DATA_VREF_CODE)
    ) u_DATATRAINVREF (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_datatrainvref_en       (local_datatrainvref_en),
        .local_datatrainvref_done     (local_datatrainvref_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_DATATRAINVREF]),
        .local_update_lane_mask       (ss_update_lane_mask[SS_DATATRAINVREF]),
        .partner_datatrainvref_en     (partner_datatrainvref_en),
        .partner_datatrainvref_done   (partner_datatrainvref_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_DATATRAINVREF]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_DATATRAINVREF]),
        .phy_rx_datavref_ctrl         (datatrainvref_phy_rx_datavref_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DATATRAINVREF]),
        .sweep_en                     (ss_sweep_en[SS_DATATRAINVREF]),
        .swept_code                   (swept_data_vref_code),
        .best_code                    (best_data_vref_code),
        .sweep_done                   (sweep_done),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_DATATRAINVREF]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_DATATRAINVREF]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_DATATRAINVREF]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_DATATRAINVREF]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_DATATRAINVREF]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_DATATRAINVREF]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_DATATRAINVREF]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_DATATRAINVREF]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DATATRAINVREF]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DATATRAINVREF]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DATATRAINVREF]),
        .tx_data_field                (ss_tx_data_field[SS_DATATRAINVREF]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_RXDESKEW #(
        .MAX_DESKEW_CODE (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE (MIN_DESKEW_CODE)
    ) u_RXDESKEW (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .is_high_speed                (is_high_speed),
        .is_continuous_clk_mode       (is_continuous_clk_mode),
        .local_rxdeskew_en            (local_rxdeskew_en),
        .local_rxdeskew_done          (local_rxdeskew_done),
        .local_datatraincenter1_req   (local_dtc1_loopback_req),
        .local_trainerror_req         (ss_local_trainerror_req[SS_RXDESKEW]),
        .partner_rxdeskew_en          (partner_rxdeskew_en),
        .partner_rxdeskew_done        (partner_rxdeskew_done),
        .partner_datatraincenter1_req (),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_RXDESKEW]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_RXDESKEW]),
        .phy_rx_deskew_ctrl           (rxdeskew_phy_rx_deskew_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_RXDESKEW]),
        .phy_tx_eq_preset_ctrl        (rxdeskew_phy_tx_eq_preset_ctrl),
        .phy_tx_eq_preset_en          (rxdeskew_phy_tx_eq_preset_en),
        .sweep_en                     (ss_sweep_en[SS_RXDESKEW]),
        .swept_code                   (sweep_swept_code),
        .best_code                    (sweep_best_code),
        .min_eye_width                (sweep_min_eye_width),
        .sweep_done                   (sweep_done),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_RXDESKEW]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_RXDESKEW]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_RXDESKEW]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_RXDESKEW]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_RXDESKEW]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_RXDESKEW]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_RXDESKEW]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_RXDESKEW]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_RXDESKEW]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_RXDESKEW]),
        .tx_msginfo                   (ss_tx_msginfo[SS_RXDESKEW]),
        .tx_data_field                (ss_tx_data_field[SS_RXDESKEW]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_DATATRAINCENTER2 #(
        .MAX_DATA_PI_CODE (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE (MIN_DATA_PI_CODE)
    ) u_DATATRAINCENTER2 (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_datatraincenter2_en    (local_dtc2_en),
        .local_datatraincenter2_done  (local_dtc2_done),
        .local_trainerror_req         (ss_local_trainerror_req[SS_DTC2]),
        .local_update_lane_mask       (ss_update_lane_mask[SS_DTC2]),
        .partner_datatraincenter2_en  (partner_dtc2_en),
        .partner_datatraincenter2_done(partner_dtc2_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_DTC2]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_DTC2]),
        .phy_tx_data_pi_phase_ctrl    (dtc2_phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DTC2]),
        .sweep_en                     (ss_sweep_en[SS_DTC2]),
        .swept_code                   (swept_data_pi_code),
        .best_code                    (best_data_pi_code),
        .sweep_done                   (sweep_done),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_DTC2]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_DTC2]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_DTC2]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_DTC2]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_DTC2]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_DTC2]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_DTC2]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_DTC2]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DTC2]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DTC2]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DTC2]),
        .tx_data_field                (ss_tx_data_field[SS_DTC2]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_LINKSPEED u_LINKSPEED (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .is_high_speed                (is_high_speed),
        .is_continuous_clk_mode       (is_continuous_clk_mode),
        .local_linkspeed_en           (local_linkspeed_en),
        .local_linkspeed_done         (local_linkspeed_done),
        .local_linkinit_req           (local_linkinit_route_req),
        .local_speedidle_req          (local_speedidle_route_req),
        .local_repair_req             (local_repair_route_req),
        .local_phyretrain_req         (local_phyretrain_route_req),
        .local_trainerror_req         (ss_local_trainerror_req[SS_LINKSPEED]),
        .partner_linkspeed_en         (partner_linkspeed_en),
        .partner_linkspeed_done       (partner_linkspeed_done),
        .partner_linkinit_req         (),
        .partner_speedidle_req        (),
        .partner_repair_req           (),
        .partner_phyretrain_req       (),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_LINKSPEED]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_LINKSPEED]),
        .active_rx_lanes              (active_rx_lanes),
        .width_degrade_feasible       (degrade_feasible),
        .PHY_IN_RETRAIN               (PHY_IN_RETRAIN),
        .params_changed               (params_changed),
        .PHY_IN_RETRAIN_rst           (PHY_IN_RETRAIN_rst),
        .busy_bit_rst                 (busy_bit_rst),
        .local_sweep_en               (ss_sweep_en[SS_LINKSPEED]),
        .partner_sweep_en             (ss_partner_sweep_en[SS_LINKSPEED]),
        .d2c_perlane_pass             (d2c_perlane_pass),
        .local_sweep_done             (sweep_done),
        .linkspeed_success_lanes      (linkspeed_success_lanes),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_LINKSPEED]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_LINKSPEED]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_LINKSPEED]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_LINKSPEED]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_LINKSPEED]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_LINKSPEED]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_LINKSPEED]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_LINKSPEED]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_LINKSPEED]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_LINKSPEED]),
        .tx_msginfo                   (ss_tx_msginfo[SS_LINKSPEED]),
        .tx_data_field                (ss_tx_data_field[SS_LINKSPEED]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    wrapper_REPAIR u_REPAIR (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .is_ltsm_out_of_reset         (is_ltsm_out_of_reset),
        .timeout_8ms_occured          (timeout_8ms_occured),
        .local_repair_en              (local_repair_en),
        .local_repair_done            (local_repair_done),
        .local_txselfcal_req          (local_repair_txselfcal_req),
        .local_trainerror_req         (ss_local_trainerror_req[SS_REPAIR]),
        .partner_repair_en            (partner_repair_en),
        .partner_repair_done          (partner_repair_done),
        .partner_trainerror_req       (ss_partner_trainerror_req[SS_REPAIR]),
        .timeout_timer_en             (ss_timeout_timer_en[SS_REPAIR]),
        .local_tx_lane_map_code       (degraded_lane_map_code),
        .width_degrade_feasible       (degrade_feasible),
        .mb_rx_data_lane_mask         (mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask         (mb_tx_data_lane_mask),
        .mbinit_rx_data_lane_mask     (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask     (mbinit_tx_data_lane_mask),
        .update_lane_mask             (repair_update_lane_mask),
        .mb_tx_clk_lane_sel           (ss_mb_tx_clk_lane_sel[SS_REPAIR]),
        .mb_tx_data_lane_sel          (ss_mb_tx_data_lane_sel[SS_REPAIR]),
        .mb_tx_val_lane_sel           (ss_mb_tx_val_lane_sel[SS_REPAIR]),
        .mb_tx_trk_lane_sel           (ss_mb_tx_trk_lane_sel[SS_REPAIR]),
        .mb_rx_clk_lane_sel           (ss_mb_rx_clk_lane_sel[SS_REPAIR]),
        .mb_rx_data_lane_sel          (ss_mb_rx_data_lane_sel[SS_REPAIR]),
        .mb_rx_val_lane_sel           (ss_mb_rx_val_lane_sel[SS_REPAIR]),
        .mb_rx_trk_lane_sel           (ss_mb_rx_trk_lane_sel[SS_REPAIR]),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_REPAIR]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_REPAIR]),
        .tx_msginfo                   (ss_tx_msginfo[SS_REPAIR]),
        .tx_data_field                (ss_tx_data_field[SS_REPAIR]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo),
        .rx_data_field                (rx_data_field)
    );

    // Substates without analog-settle or sweep/update ports get explicit inactive values.
    assign ss_analog_settle_timer_en[SS_VALVREF]        = 1'b0;
    assign ss_analog_settle_timer_en[SS_DATAVREF]       = 1'b0;
    assign ss_analog_settle_timer_en[SS_VALTRAINCENTER] = 1'b0;
    assign ss_analog_settle_timer_en[SS_VALTRAINVREF]   = 1'b0;
    assign ss_analog_settle_timer_en[SS_DTC1]           = 1'b0;
    assign ss_analog_settle_timer_en[SS_DATATRAINVREF]  = 1'b0;
    assign ss_analog_settle_timer_en[SS_RXDESKEW]       = 1'b0;
    assign ss_analog_settle_timer_en[SS_DTC2]           = 1'b0;
    assign ss_analog_settle_timer_en[SS_LINKSPEED]      = 1'b0;
    assign ss_analog_settle_timer_en[SS_REPAIR]         = 1'b0;

    assign ss_sweep_en[SS_SPEEDIDLE]     = 1'b0;
    assign ss_sweep_en[SS_TXSELFCAL]     = 1'b0;
    assign ss_sweep_en[SS_RXCLKCAL]      = 1'b0;
    assign ss_sweep_en[SS_REPAIR]        = 1'b0;
    assign ss_partner_sweep_en[SS_SPEEDIDLE] = 1'b0;
    assign ss_partner_sweep_en[SS_TXSELFCAL] = 1'b0;
    assign ss_partner_sweep_en[SS_RXCLKCAL]  = 1'b0;
    assign ss_partner_sweep_en[SS_REPAIR]    = 1'b0;

    assign ss_update_lane_mask[SS_SPEEDIDLE]  = 1'b0;
    assign ss_update_lane_mask[SS_TXSELFCAL]  = 1'b0;
    assign ss_update_lane_mask[SS_RXCLKCAL]   = 1'b0;
    assign ss_update_lane_mask[SS_RXDESKEW]   = 1'b0;
    assign ss_update_lane_mask[SS_LINKSPEED]  = 1'b0;
    assign ss_update_lane_mask[SS_REPAIR]     = 1'b0;

    // ================================================================================================
    // 6. Output Arbitration, Muxing, and Retained PHY Controls
    // ================================================================================================

    // Combine substate timer enables and other common requests
    assign timeout_timer_en        = |ss_timeout_timer_en;
    assign analog_settle_timer_en  = |ss_analog_settle_timer_en;
    assign repair_update_lane_mask = |ss_update_lane_mask;

    // Arbitration for D2C State Selection
    // Tells the external sweep engine which training substate we are currently in.
    always_comb begin : D2C_STATE_SELECT
        d2c_state_n = LOG_MBTRAIN_VALVREF;

        if      (ss_active[SS_VALVREF])        d2c_state_n = LOG_MBTRAIN_VALVREF;
        else if (ss_active[SS_DATAVREF])       d2c_state_n = LOG_MBTRAIN_DATAVREF;
        else if (ss_active[SS_VALTRAINCENTER]) d2c_state_n = LOG_MBTRAIN_VALTRAINCENTER;
        else if (ss_active[SS_VALTRAINVREF])   d2c_state_n = LOG_MBTRAIN_VALTRAINVREF;
        else if (ss_active[SS_DTC1])           d2c_state_n = LOG_MBTRAIN_DATATRAINCENTER1;
        else if (ss_active[SS_DATATRAINVREF])  d2c_state_n = LOG_MBTRAIN_DATATRAINVREF;
        else if (ss_active[SS_RXDESKEW])       d2c_state_n = LOG_MBTRAIN_RXDESKEW;
        else if (ss_active[SS_DTC2])           d2c_state_n = LOG_MBTRAIN_DATATRAINCENTER2;
        else if (ss_active[SS_LINKSPEED])      d2c_state_n = LOG_MBTRAIN_LINKSPEED;
    end

    // Selected Substate Output Muxing
    // Multiplexes MB lane selectors and SB TX messages from the active substate.
    always_comb begin : SUBSTATE_OUTPUT_MUX
        substate_mb_tx_clk_lane_sel  = 2'b00;
        substate_mb_tx_data_lane_sel = 2'b00;
        substate_mb_tx_val_lane_sel  = 2'b00;
        substate_mb_tx_trk_lane_sel  = 2'b00;
        substate_mb_rx_clk_lane_sel  = 1'b0;
        substate_mb_rx_data_lane_sel = 1'b0;
        substate_mb_rx_val_lane_sel  = 1'b0;
        substate_mb_rx_trk_lane_sel  = 1'b0;

        substate_tx_sb_msg_valid     = 1'b0;
        substate_tx_sb_msg           = 8'h00;
        substate_tx_msginfo          = 16'h0000;
        substate_tx_data_field       = 64'h0000_0000_0000_0000;

        for (int i = 0; i < NUM_SUBSTATES; i++) begin
            if (ss_active[i]) begin
                substate_mb_tx_clk_lane_sel  = ss_mb_tx_clk_lane_sel[i];
                substate_mb_tx_data_lane_sel = ss_mb_tx_data_lane_sel[i];
                substate_mb_tx_val_lane_sel  = ss_mb_tx_val_lane_sel[i];
                substate_mb_tx_trk_lane_sel  = ss_mb_tx_trk_lane_sel[i];
                substate_mb_rx_clk_lane_sel  = ss_mb_rx_clk_lane_sel[i];
                substate_mb_rx_data_lane_sel = ss_mb_rx_data_lane_sel[i];
                substate_mb_rx_val_lane_sel  = ss_mb_rx_val_lane_sel[i];
                substate_mb_rx_trk_lane_sel  = ss_mb_rx_trk_lane_sel[i];
            end

            if (ss_tx_sb_msg_valid[i]) begin
                substate_tx_sb_msg_valid = ss_tx_sb_msg_valid[i];
                substate_tx_sb_msg       = ss_tx_sb_msg[i];
                substate_tx_msginfo      = ss_tx_msginfo[i];
                substate_tx_data_field   = ss_tx_data_field[i];
            end
        end
    end

    // Retained PHY Output Registers
    // These registers capture and hold PHY settings found during training.
    logic                 phy_tx_selfcal_en_r;
    logic                 phy_rx_clock_lock_en_r;
    logic                 phy_rx_track_lock_en_r;
    logic                 phy_rx_phase_detector_en_r;
    logic                 phy_tx_tckn_shift_en_r;
    logic [4:0]           phy_tx_tckn_shift_r;
    logic                 phy_tx_decrement_shift_r;

    always_ff @(posedge lclk or negedge rst_n) begin : RETAINED_PHY_OUTPUTS
        if (!rst_n) begin
            phy_negotiated_speed_r       <= 3'b000;
            phy_tx_selfcal_en_r          <= 1'b0;
            phy_rx_clock_lock_en_r       <= 1'b0;
            phy_rx_track_lock_en_r       <= 1'b0;
            phy_rx_phase_detector_en_r   <= 1'b0;
            phy_tx_tckn_shift_en_r       <= 1'b0;
            phy_tx_tckn_shift_r          <= 5'd0;
            phy_tx_decrement_shift_r     <= 1'b0;
            phy_rx_valvref_ctrl_r        <= '0;
            phy_tx_val_pi_phase_ctrl_r   <= '0;
            phy_tx_eq_preset_ctrl_r      <= 3'b000;

            for (int i = 0; i < 16; i++) begin
                phy_rx_datavref_ctrl_r[i]      <= '0;
                phy_tx_data_pi_phase_ctrl_r[i] <= '0;
                phy_rx_deskew_ctrl_r[i]        <= 7'd0;
            end
        end else if (!is_ltsm_out_of_reset) begin
            phy_negotiated_speed_r       <= 3'b000;
            phy_tx_selfcal_en_r          <= 1'b0;
            phy_rx_clock_lock_en_r       <= 1'b0;
            phy_rx_track_lock_en_r       <= 1'b0;
            phy_rx_phase_detector_en_r   <= 1'b0;
            phy_tx_tckn_shift_en_r       <= 1'b0;
            phy_tx_tckn_shift_r          <= 5'd0;
            phy_tx_decrement_shift_r     <= 1'b0;
            phy_rx_valvref_ctrl_r        <= '0;
            phy_tx_val_pi_phase_ctrl_r   <= '0;
            phy_tx_eq_preset_ctrl_r      <= 3'b000;

            for (int i = 0; i < 16; i++) begin
                phy_rx_datavref_ctrl_r[i]      <= '0;
                phy_tx_data_pi_phase_ctrl_r[i] <= '0;
                phy_rx_deskew_ctrl_r[i]        <= 7'd0;
            end
        end else begin
            // Speed Negotiation
            if (ss_active[SS_SPEEDIDLE]) begin
                phy_negotiated_speed_r <= speedidle_phy_negotiated_speed;
            end

            // Self-Calibration
            if (ss_active[SS_TXSELFCAL]) begin
                phy_tx_selfcal_en_r <= txselfcal_phy_tx_selfcal_en;
            end

            // Clock & Tracking Lock
            if (ss_active[SS_RXCLKCAL]) begin
                phy_rx_clock_lock_en_r     <= rxclkcal_phy_rx_clock_lock_en;
                phy_rx_track_lock_en_r     <= rxclkcal_phy_rx_track_lock_en;
                phy_rx_phase_detector_en_r <= rxclkcal_phy_rx_phase_detector_en;
                phy_tx_tckn_shift_en_r     <= rxclkcal_phy_tx_tckn_shift_en;
                phy_tx_tckn_shift_r        <= rxclkcal_phy_tx_tckn_shift;
                phy_tx_decrement_shift_r   <= rxclkcal_phy_tx_decrement_shift;
            end

            // Vref Training
            if (ss_active[SS_VALVREF]) begin
                phy_rx_valvref_ctrl_r <= valvref_phy_rx_valvref_ctrl;
            end else if (ss_active[SS_VALTRAINVREF]) begin
                phy_rx_valvref_ctrl_r <= valtrainvref_phy_rx_valvref_ctrl;
            end

            // PI Centering
            if (ss_active[SS_VALTRAINCENTER]) begin
                phy_tx_val_pi_phase_ctrl_r <= valtraincenter_phy_tx_val_pi_phase_ctrl;
            end

            // EQ Preset Negotiation
            if (ss_active[SS_RXDESKEW] && rxdeskew_phy_tx_eq_preset_en) begin
                phy_tx_eq_preset_ctrl_r <= rxdeskew_phy_tx_eq_preset_ctrl;
            end

            // Per-Lane Controls
            for (int i = 0; i < 16; i++) begin
                if (ss_active[SS_DATAVREF]) begin
                    phy_rx_datavref_ctrl_r[i] <= datavref_phy_rx_datavref_ctrl[i];
                end else if (ss_active[SS_DATATRAINVREF]) begin
                    phy_rx_datavref_ctrl_r[i] <= datatrainvref_phy_rx_datavref_ctrl[i];
                end

                if (ss_active[SS_DTC1]) begin
                    phy_tx_data_pi_phase_ctrl_r[i] <= dtc1_phy_tx_data_pi_phase_ctrl[i];
                end else if (ss_active[SS_DTC2]) begin
                    phy_tx_data_pi_phase_ctrl_r[i] <= dtc2_phy_tx_data_pi_phase_ctrl[i];
                end

                if (ss_active[SS_RXDESKEW]) begin
                    phy_rx_deskew_ctrl_r[i] <= rxdeskew_phy_rx_deskew_ctrl[i];
                end
            end
        end
    end

    // PHY Output Selection Logic
    // Muxes between current substate outputs (when active) and retained registers.
    always_comb begin : PHY_OUTPUT_SELECT
        phy_negotiated_speed       = ss_active[SS_SPEEDIDLE] ? speedidle_phy_negotiated_speed : phy_negotiated_speed_r;
        phy_tx_selfcal_en          = ss_active[SS_TXSELFCAL] ? txselfcal_phy_tx_selfcal_en     : phy_tx_selfcal_en_r;
        phy_rx_clock_lock_en       = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_rx_clock_lock_en  : phy_rx_clock_lock_en_r;
        phy_rx_track_lock_en       = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_rx_track_lock_en  : phy_rx_track_lock_en_r;
        phy_rx_phase_detector_en   = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_rx_phase_detector_en : phy_rx_phase_detector_en_r;
        phy_tx_tckn_shift_en       = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_tx_tckn_shift_en  : phy_tx_tckn_shift_en_r;
        phy_tx_tckn_shift          = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_tx_tckn_shift     : phy_tx_tckn_shift_r;
        phy_tx_decrement_shift     = ss_active[SS_RXCLKCAL]  ? rxclkcal_phy_tx_decrement_shift : phy_tx_decrement_shift_r;

        phy_rx_valvref_ctrl        = ss_active[SS_VALVREF]        ? valvref_phy_rx_valvref_ctrl        :
            ss_active[SS_VALTRAINVREF]    ? valtrainvref_phy_rx_valvref_ctrl   :
            phy_rx_valvref_ctrl_r;

        phy_tx_val_pi_phase_ctrl   = ss_active[SS_VALTRAINCENTER] ? valtraincenter_phy_tx_val_pi_phase_ctrl :
            phy_tx_val_pi_phase_ctrl_r;

        phy_tx_eq_preset_ctrl      = ss_active[SS_RXDESKEW]       ? rxdeskew_phy_tx_eq_preset_ctrl :
            phy_tx_eq_preset_ctrl_r;

        phy_tx_eq_preset_en        = ss_active[SS_RXDESKEW]       ? rxdeskew_phy_tx_eq_preset_en   : 1'b0;

        for (int i = 0; i < 16; i++) begin
            phy_rx_datavref_ctrl[i] =
                ss_active[SS_DATAVREF]       ? datavref_phy_rx_datavref_ctrl[i]       :
                ss_active[SS_DATATRAINVREF]  ? datatrainvref_phy_rx_datavref_ctrl[i]  :
                phy_rx_datavref_ctrl_r[i];

            phy_tx_data_pi_phase_ctrl[i] =
                ss_active[SS_DTC1]           ? dtc1_phy_tx_data_pi_phase_ctrl[i]       :
                ss_active[SS_DTC2]           ? dtc2_phy_tx_data_pi_phase_ctrl[i]       :
                phy_tx_data_pi_phase_ctrl_r[i];

            phy_rx_deskew_ctrl[i] =
                ss_active[SS_RXDESKEW]       ? rxdeskew_phy_rx_deskew_ctrl[i]         :
                phy_rx_deskew_ctrl_r[i];
        end
    end

endmodule

