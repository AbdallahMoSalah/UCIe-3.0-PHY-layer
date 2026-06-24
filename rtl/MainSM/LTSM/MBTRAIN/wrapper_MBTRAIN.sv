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
        parameter int unsigned MAX_VAL_VREF_CODE  = 'd16,
        parameter int unsigned MAX_DATA_VREF_CODE = 'd16,
        parameter int unsigned MAX_DATA_PI_CODE   = 'd16,
        parameter int unsigned MAX_VAL_PI_CODE    = 'd16,
        parameter int unsigned MAX_DESKEW_CODE    = 'd16,
        parameter int unsigned MIN_DATA_PI_CODE   = 'd1 ,
        parameter int unsigned MIN_DESKEW_CODE    = 'd1 ,

        parameter int unsigned MAX_CODE =
            (MAX_VAL_VREF_CODE >= MAX_DATA_VREF_CODE && MAX_VAL_VREF_CODE >= MAX_DATA_PI_CODE && MAX_VAL_VREF_CODE >= MAX_VAL_PI_CODE && MAX_VAL_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_VAL_VREF_CODE :
            (MAX_DATA_VREF_CODE >= MAX_DATA_PI_CODE && MAX_DATA_VREF_CODE >= MAX_VAL_PI_CODE && MAX_DATA_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_VREF_CODE :
            (MAX_DATA_PI_CODE >= MAX_VAL_PI_CODE && MAX_DATA_PI_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_PI_CODE :
            (MAX_VAL_PI_CODE >= MAX_DESKEW_CODE) ? MAX_VAL_PI_CODE : MAX_DESKEW_CODE // Maximum code value (inclusive). Sets counter width.
    ) (
        // Clock, reset, and MBTRAIN state control
        input  logic        lclk,
        input  logic        rst_n,
        // NOTE: soft_rst_n is generated INTERNALLY from state_n_0.
        // It is NOT a port – the higher-level LTSM passes state_n instead.
        input  logic        mbtrain_en,
        output logic        mbtrain_done,
        output ltsm_state_n_pkg::state_n_e current_mbtrain_substate,

        output logic        ltsm_trainerror_req,
        output logic        ltsm_linkinit_req,
        output logic        ltsm_phyretrain_req,
        // output logic        ltsm_repair_req,  <== Not used in mbtrain.
        // output logic        ltsm_speedidle_req, <== Not used in mbtrain.

        input  logic        mbtrain_txselfcal_req,
        input  logic        mbtrain_speedidle_req,
        input  logic        mbtrain_repair_req   ,

        input  logic        analog_settle_time_done,
        output logic        analog_settle_timer_en,

        // Register-file / LTSM configuration
        input  wire ltsm_state_n_pkg::state_n_e state_n_0,
        input  wire ltsm_state_n_pkg::state_n_e state_n_1,

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
        // output ltsm_state_n_pkg::state_n_e d2c_state_n,
        input  logic        sweep_done,
        input       logic [$clog2(MAX_CODE+1)-1:0] sweep_swept_code,
        input  wire logic [$clog2(MAX_CODE+1)-1:0] sweep_best_code [0:15],
        input       logic [$clog2(MAX_DESKEW_CODE+1)-1:0] sweep_min_eye_width,

        // External D2C point-test results
        input  logic [15:0] d2c_perlane_pass,
        // NOTE: d2c_aggr_pass and d2c_val_pass are not consumed by any substate wrapper
        // and have been removed from this port list per the implementation plan.

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

        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1 :0] phy_rx_val_vref_ctrl,
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_data_vref_ctrl [0:15],
        output logic [$clog2(MAX_VAL_PI_CODE+1)-1   :0] phy_tx_val_pi_phase_ctrl,
        output logic [$clog2(MAX_DATA_PI_CODE+1)-1  :0] phy_tx_data_pi_phase_ctrl [0:15],
        output logic [$clog2(MAX_DESKEW_CODE+1)-1   :0] phy_rx_deskew_ctrl        [0:15],
        output logic [2:0]                              phy_tx_eq_preset_ctrl,
        output logic                                    phy_tx_eq_preset_en,

        // Selected substate mainband lane selectors
        // output logic [1:0]  substate_mb_tx_clk_lane_sel,
        // output logic [1:0]  substate_mb_tx_data_lane_sel,
        // output logic [1:0]  substate_mb_tx_val_lane_sel,
        // output logic [1:0]  substate_mb_tx_trk_lane_sel,

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
        input  logic [15:0] rx_msginfo
        // input  logic [63:0] rx_data_field
    );


    import ltsm_state_n_pkg::*;

    // =========================================================================
    // Internal Software Reset Generation
    // soft_rst_n is generated here using state_n_0.
    // It deasserts when the LTSM enters RESET (so all substate FSMs soft-reset),
    // and asserts when the LTSM reaches SBINIT (unblocking all substate FSMs).
    // =========================================================================
    logic soft_rst_n;
    logic first_enter_flag;

    always_ff @(posedge lclk or negedge rst_n) begin : SOFT_RESET_GEN
        if (!rst_n) begin
            soft_rst_n <= 1'b0;
            first_enter_flag     <= 1'b0;
        end else if (state_n_0 == LOG_RESET && !first_enter_flag) begin
            // First time we see RESET → assert soft-reset to all substates
            soft_rst_n <= 1'b0;
            first_enter_flag     <= 1'b1;
        end else if (state_n_0 == LOG_SBINIT && first_enter_flag) begin
            // LTSM has left RESET and entered SBINIT → release soft-reset
            soft_rst_n <= 1'b1;
            first_enter_flag     <= 1'b0;
        end
    end

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

    localparam int unsigned VAL_VREF_W    = $clog2(MAX_VAL_VREF_CODE  + 1);
    localparam int unsigned DATA_VREF_W   = $clog2(MAX_DATA_VREF_CODE + 1);
    localparam int unsigned VAL_PI_W      = $clog2(MAX_VAL_PI_CODE    + 1);
    localparam int unsigned DATA_PI_W     = $clog2(MAX_DATA_PI_CODE   + 1);
    localparam int unsigned DATA_DESKEW_W = $clog2(MAX_DESKEW_CODE    + 1);


    // Controller handshakes.
    logic valvref_en       ;
    logic datavref_en      ;
    logic speedidle_en     ;
    logic txselfcal_en     ;
    logic rxclkcal_en      ;
    logic valtraincenter_en;
    logic valtrainvref_en  ;
    logic dtc1_en          ;
    logic datatrainvref_en ;
    logic rxdeskew_en      ;
    logic dtc2_en          ;
    logic linkspeed_en     ;
    logic repair_en        ;

    logic rx_clk_active;
    // logic tx_clk_active;
    // logic lcl_tx_elec_idle;
    logic ptr_rx_elec_idle;

    logic valvref_done       ;
    logic datavref_done      ;
    logic speedidle_done     ;
    logic txselfcal_done     ;
    logic rxclkcal_done      ;
    logic valtraincenter_done;
    logic valtrainvref_done  ;
    logic dtc1_done          ;
    logic datatrainvref_done ;
    logic rxdeskew_done      ;
    logic dtc2_done          ;
    logic linkspeed_done     ;
    logic repair_done        ;

    logic rxdeskew_dtc1_req         ;
    // repair_trainerror_req_w: driven by wrapper_REPAIR's trainerror_req output.
    logic repair_trainerror_req_w   ;
    // rxdeskew_trainerror_req_w: driven by wrapper_RXDESKEW's trainerror_req output.
    // BUG FIX: was previously undriven (missing from both the tied-0 group and the assigned group).
    logic rxdeskew_trainerror_req_w ;



    // Per-substate combined trainerror request (each substate wrapper already ORs
    // its local|partner trainerror flags internally before driving this array).
    logic [NUM_SUBSTATES-1:0] ss_en            ;
    logic [NUM_SUBSTATES-1:0] ss_trainerror_req;
    // ss_analog_settle_timer_en: active for substates that use an analog-settle wait
    // (SPEEDIDLE, TXSELFCAL, RXCLKCAL); all others are tied 1'b0 below.
    // NOTE: ss_timeout_timer_en (8 ms MBTRAIN timeout) intentionally absent —
    // the future LTSM controller reads current_mbtrain_substate for that purpose.
    logic [NUM_SUBSTATES-1:0] ss_analog_settle_timer_en;
    logic [NUM_SUBSTATES-1:0] ss_local_sweep_en        ;
    logic [NUM_SUBSTATES-1:0] ss_partner_sweep_en      ;


    logic        ss_tx_sb_msg_valid     [0:NUM_SUBSTATES-1];
    logic [7:0]  ss_tx_sb_msg           [0:NUM_SUBSTATES-1];
    logic [15:0] ss_tx_msginfo          [0:NUM_SUBSTATES-1];
    logic [63:0] ss_tx_data_field       [0:NUM_SUBSTATES-1];

    // Common decoder outputs and lane-map info.
    logic        is_high_speed;
    // active_rx_lanes: driven by wrapper_REPAIR's exposed output (from its internal unit_negotiated_lanes). Connected to sweep_active_lanes and wrapper_LINKSPEED.
    logic [15:0] active_rx_lanes;
    logic [15:0] active_tx_lanes;
    logic [15:0] linkspeed_success_lanes;
    // degrade_feasible: from wrapper_REPAIR's exposed output → wrapper_LINKSPEED.width_degrade_feasible
    logic        degrade_feasible;
    // degraded_lane_map_code is NOT declared here: wrapper_REPAIR computes it internally
    // via its own unit_negotiated_lanes instance for the REPAIR FSMs.

    // Output/control signals that need arbitration or value retention.
    logic [2:0]  speedidle_phy_negotiated_speed;
    logic        txselfcal_phy_tx_selfcal_en;
    logic        rxclkcal_phy_rx_clock_lock_en;
    logic        rxclkcal_phy_rx_track_lock_en;
    logic        rxclkcal_phy_rx_phase_detector_en;
    logic        rxclkcal_phy_tx_tckn_shift_en;
    logic [4:0]  rxclkcal_phy_tx_tckn_shift;
    logic        rxclkcal_phy_tx_decrement_shift;

    logic [VAL_VREF_W-1:0]    valvref_phy_rx_valvref_ctrl;
    logic [VAL_VREF_W-1:0]    valtrainvref_phy_rx_valvref_ctrl;
    logic [DATA_VREF_W-1:0]   datavref_phy_rx_datavref_ctrl      [0:15];
    logic [DATA_VREF_W-1:0]   datatrainvref_phy_rx_datavref_ctrl [0:15];
    logic [VAL_PI_W-1:0]      valtraincenter_phy_tx_val_pi_phase_ctrl;
    logic [DATA_PI_W-1:0]     dtc1_phy_tx_data_pi_phase_ctrl     [0:15];
    logic [DATA_PI_W-1:0]     dtc2_phy_tx_data_pi_phase_ctrl     [0:15];
    logic [DATA_DESKEW_W-1:0] rxdeskew_phy_rx_deskew_ctrl        [0:15];
    logic [2:0]               rxdeskew_phy_tx_eq_preset_ctrl;
    logic                     rxdeskew_phy_tx_eq_preset_en;

    // Sliced versions of the shared 7-bit sweep bus for narrower substate wrappers.
    logic [VAL_VREF_W-1:0]  swept_val_vref_code;
    logic [DATA_VREF_W-1:0] swept_data_vref_code;
    logic [VAL_PI_W-1:0]    swept_val_pi_code;
    logic [DATA_PI_W-1:0]   swept_data_pi_code;
    logic [VAL_VREF_W-1:0]  best_val_vref_code;
    logic [DATA_VREF_W-1:0] best_data_vref_code [0:15];
    logic [VAL_PI_W-1:0]    best_val_pi_code;
    logic [DATA_PI_W-1:0]   best_data_pi_code   [0:15];

    // ================================================================================================
    // 3. Input-only preparation logic
    // ================================================================================================
    assign swept_val_vref_code  = sweep_swept_code[VAL_VREF_W-1:0];
    assign swept_data_vref_code = sweep_swept_code[DATA_VREF_W-1:0];
    assign swept_val_pi_code    = sweep_swept_code[VAL_PI_W-1:0];
    assign swept_data_pi_code   = sweep_swept_code[DATA_PI_W-1:0];

    assign best_val_vref_code   = sweep_best_code[0][VAL_VREF_W-1:0];
    assign best_val_pi_code     = sweep_best_code[0][VAL_PI_W-1:0];

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane++) begin : g_sweep_code_slices
            assign best_data_vref_code[lane] = sweep_best_code[lane][DATA_VREF_W-1:0];
            assign best_data_pi_code  [lane] = sweep_best_code[lane][DATA_PI_W-1:0];
        end
    endgenerate

    assign ss_en[SS_VALVREF]        = valvref_en;
    assign ss_en[SS_DATAVREF]       = datavref_en;
    assign ss_en[SS_SPEEDIDLE]      = speedidle_en;
    assign ss_en[SS_TXSELFCAL]      = txselfcal_en;
    assign ss_en[SS_RXCLKCAL]       = rxclkcal_en;
    assign ss_en[SS_VALTRAINCENTER] = valtraincenter_en;
    assign ss_en[SS_VALTRAINVREF]   = valtrainvref_en;
    assign ss_en[SS_DTC1]           = dtc1_en;
    assign ss_en[SS_DATATRAINVREF]  = datatrainvref_en;
    assign ss_en[SS_RXDESKEW]       = rxdeskew_en;
    assign ss_en[SS_DTC2]           = dtc2_en;
    assign ss_en[SS_LINKSPEED]      = linkspeed_en;
    assign ss_en[SS_REPAIR]         = repair_en;

    logic trainerror_detected;

    logic linkspeed_linkinit_req   ;
    logic linkspeed_speedidle_req  ;
    logic linkspeed_repair_req     ;
    logic linkspeed_phyretrain_req ;

    assign trainerror_detected = |ss_trainerror_req;

    // // === DEBUG: ss_trainerror_req vector monitoring ===
    // // synopsys translate_off
    // always @(*) begin
    //     if (trainerror_detected)
    //         $display("T=%0t | [MBTRAIN WRAPPER DEBUG %m] trainerror_detected=1! ss_trainerror_req=%b (VALVREF[0]..REPAIR[12])",
    //                  $time, ss_trainerror_req);
    // end
    // // synopsys translate_on

    assign local_sweep_en     = |ss_local_sweep_en;
    assign partner_sweep_en   = |ss_partner_sweep_en;
    logic [15:0] sweep_active_lanes_w;
    always_comb begin
        case (current_mbtrain_substate)
            LOG_MBTRAIN_VALTRAINCENTER,
            LOG_MBTRAIN_DATATRAINCENTER1,
            LOG_MBTRAIN_DATATRAINCENTER2,
            LOG_MBTRAIN_LINKSPEED: begin
                sweep_active_lanes_w = active_tx_lanes;
            end
            default: begin
                sweep_active_lanes_w = active_rx_lanes;
            end
        endcase
    end
    assign sweep_active_lanes = sweep_active_lanes_w;

    // ================================================================================================
    // 4. Common-file instantiations
    // ================================================================================================
    unit_MBTRAIN_ctrl u_MBTRAIN_ctrl (
        .lclk                          (lclk),
        .rst_n                         (rst_n),
        .soft_rst_n                    (soft_rst_n),
        .mbtrain_en                    (mbtrain_en),
        .mbtrain_done                  (mbtrain_done),
        .current_mbtrain_substate      (current_mbtrain_substate),
        .trainerror_detected           (trainerror_detected),
        .ltsm_trainerror_req           (ltsm_trainerror_req),
        .ltsm_linkinit_req             (ltsm_linkinit_req),
        .ltsm_phyretrain_req           (ltsm_phyretrain_req),
        .mbtrain_txselfcal_req         (mbtrain_txselfcal_req),
        .mbtrain_speedidle_req         (mbtrain_speedidle_req),
        .mbtrain_repair_req            (mbtrain_repair_req),
        // Sub-state enables (one per substate — wrapper handles internal local/partner fan-out)
        .valvref_en                    (valvref_en),
        .valvref_done                  (valvref_done),
        .datavref_en                   (datavref_en),
        .datavref_done                 (datavref_done),
        .speedidle_en                  (speedidle_en),
        .speedidle_done                (speedidle_done),
        .txselfcal_en                  (txselfcal_en),
        .txselfcal_done                (txselfcal_done),
        .rxclkcal_en                   (rxclkcal_en),
        .rxclkcal_done                 (rxclkcal_done),
        .valtraincenter_en             (valtraincenter_en),
        .valtraincenter_done           (valtraincenter_done),
        .valtrainvref_en               (valtrainvref_en),
        .valtrainvref_done             (valtrainvref_done),
        .dtc1_en                       (dtc1_en),
        .dtc1_done                     (dtc1_done),
        .datatrainvref_en              (datatrainvref_en),
        .datatrainvref_done            (datatrainvref_done),
        .rxdeskew_en                   (rxdeskew_en),
        .rxdeskew_done                 (rxdeskew_done),
        .dtc1_loopback_req             (rxdeskew_dtc1_req),
        .dtc2_en                       (dtc2_en),
        .dtc2_done                     (dtc2_done),
        .linkspeed_en                  (linkspeed_en),
        .linkspeed_done                (linkspeed_done),
        // LINKSPEED routing outputs (fed back to ctrl)
        .linkspeed_linkinit_req        (linkspeed_linkinit_req),
        .linkspeed_speedidle_req       (linkspeed_speedidle_req),
        .linkspeed_repair_req          (linkspeed_repair_req),
        .linkspeed_phyretrain_req      (linkspeed_phyretrain_req),
        .repair_en                     (repair_en),
        .repair_done                   (repair_done)
    );


    // ===========================================================================================
    // 5. Substate instantiations in MBTRAIN order
    // ===========================================================================================

    wrapper_VALVREF #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE)
    ) u_VALVREF (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .soft_rst_n            (soft_rst_n),
        .valvref_en            (ss_en[SS_VALVREF]),
        .valvref_done          (valvref_done),
        .phy_rx_valvref_ctrl   (valvref_phy_rx_valvref_ctrl),
        .partner_sweep_en      (ss_partner_sweep_en[SS_VALVREF]),
        .local_sweep_en        (ss_local_sweep_en[SS_VALVREF]),
        .swept_code            (swept_val_vref_code),
        .best_code             (best_val_vref_code),
        .sweep_done            (sweep_done),
        .tx_sb_msg_valid       (ss_tx_sb_msg_valid[SS_VALVREF]),
        .tx_sb_msg             (ss_tx_sb_msg[SS_VALVREF]),
        .tx_msginfo            (ss_tx_msginfo[SS_VALVREF]),
        .tx_data_field         (ss_tx_data_field[SS_VALVREF]),
        .rx_sb_msg_valid       (rx_sb_msg_valid),
        .rx_sb_msg             (rx_sb_msg)
    );

    wrapper_DATAVREF #(
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE)
    ) u_DATAVREF (
        .lclk                  (lclk),
        .rst_n                 (rst_n),
        .soft_rst_n            (soft_rst_n),
        .datavref_en           (ss_en[SS_DATAVREF]),
        .datavref_done         (datavref_done),
        .phy_rx_datavref_ctrl  (datavref_phy_rx_datavref_ctrl),
        .partner_sweep_en      (ss_partner_sweep_en[SS_DATAVREF]),
        .local_sweep_en        (ss_local_sweep_en[SS_DATAVREF]),
        .swept_code            (swept_data_vref_code),
        .best_code             (best_data_vref_code),
        .sweep_done            (sweep_done),
        .tx_sb_msg_valid       (ss_tx_sb_msg_valid[SS_DATAVREF]),
        .tx_sb_msg             (ss_tx_sb_msg[SS_DATAVREF]),
        .tx_msginfo            (ss_tx_msginfo[SS_DATAVREF]),
        .tx_data_field         (ss_tx_data_field[SS_DATAVREF]),
        .rx_sb_msg_valid       (rx_sb_msg_valid),
        .rx_sb_msg             (rx_sb_msg)
    );

    wrapper_SPEEDIDLE u_SPEEDIDLE (
        .lclk                    (lclk),
        .rst_n                   (rst_n),
        .soft_rst_n              (soft_rst_n),
        .speedidle_en            (ss_en[SS_SPEEDIDLE]),
        .speedidle_done          (speedidle_done),
        .trainerror_req          (ss_trainerror_req[SS_SPEEDIDLE]),
        .analog_settle_timer_en  (ss_analog_settle_timer_en[SS_SPEEDIDLE]),
        .analog_settle_time_done (analog_settle_time_done),
        .state_n_1               (state_n_1),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .phy_negotiated_speed    (speedidle_phy_negotiated_speed),
        .tx_sb_msg_valid         (ss_tx_sb_msg_valid[SS_SPEEDIDLE]),
        .tx_sb_msg               (ss_tx_sb_msg[SS_SPEEDIDLE]),
        .tx_msginfo              (ss_tx_msginfo[SS_SPEEDIDLE]),
        .tx_data_field           (ss_tx_data_field[SS_SPEEDIDLE]),
        .rx_sb_msg_valid         (rx_sb_msg_valid),
        .rx_sb_msg               (rx_sb_msg)
    );

    wrapper_TXSELFCAL u_TXSELFCAL (
        .lclk                    (lclk),
        .rst_n                   (rst_n),
        .soft_rst_n              (soft_rst_n),
        .txselfcal_en            (ss_en[SS_TXSELFCAL]),
        .txselfcal_done          (txselfcal_done),
        .analog_settle_timer_en  (ss_analog_settle_timer_en[SS_TXSELFCAL]),
        .analog_settle_time_done (analog_settle_time_done),
        .phy_tx_selfcal_en       (txselfcal_phy_tx_selfcal_en),
        .tx_sb_msg_valid         (ss_tx_sb_msg_valid[SS_TXSELFCAL]),
        .tx_sb_msg               (ss_tx_sb_msg[SS_TXSELFCAL]),
        .tx_msginfo              (ss_tx_msginfo[SS_TXSELFCAL]),
        .tx_data_field           (ss_tx_data_field[SS_TXSELFCAL]),
        .rx_sb_msg_valid         (rx_sb_msg_valid),
        .rx_sb_msg               (rx_sb_msg)
    );

    wrapper_RXCLKCAL u_RXCLKCAL (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .is_high_speed                (is_high_speed),
        // .is_continuous_clk_mode       (is_continuous_clk_mode),
        .rxclkcal_en                  (ss_en[SS_RXCLKCAL]),
        .rxclkcal_done                (rxclkcal_done),
        .trainerror_req               (ss_trainerror_req[SS_RXCLKCAL]),
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
        .rx_clk_active                (rx_clk_active),
        // .tx_clk_active                (tx_clk_active),
        .mb_tx_pattern_en             (rxclkcal_mb_tx_pattern_en),
        .mb_tx_pattern_setup          (rxclkcal_mb_tx_pattern_setup),
        .mb_tx_clk_pattern_sel        (rxclkcal_mb_tx_clk_pattern_sel),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_RXCLKCAL]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_RXCLKCAL]),
        .tx_msginfo                   (ss_tx_msginfo[SS_RXCLKCAL]),
        .tx_data_field                (ss_tx_data_field[SS_RXCLKCAL]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo)
    );

    wrapper_VALTRAINCENTER #(
        .MAX_VAL_PI_CODE (MAX_VAL_PI_CODE)
    ) u_VALTRAINCENTER (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .valtraincenter_en            (ss_en[SS_VALTRAINCENTER]),
        .valtraincenter_done          (valtraincenter_done),
        .phy_tx_val_pi_phase_ctrl     (valtraincenter_phy_tx_val_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_VALTRAINCENTER]),
        .local_sweep_en               (ss_local_sweep_en[SS_VALTRAINCENTER]),
        .swept_code                   (swept_val_pi_code),
        .best_code                    (best_val_pi_code),
        .sweep_done                   (sweep_done),
        .mb_tx_continuous_or_strobe_clk(is_continuous_clk_mode),
        .phy_negotiated_speed         (phy_negotiated_speed),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_VALTRAINCENTER]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_VALTRAINCENTER]),
        .tx_msginfo                   (ss_tx_msginfo[SS_VALTRAINCENTER]),
        .tx_data_field                (ss_tx_data_field[SS_VALTRAINCENTER]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg)
    );

    wrapper_VALTRAINVREF #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE)
    ) u_VALTRAINVREF (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .valtrainvref_en              (ss_en[SS_VALTRAINVREF]),
        .valtrainvref_done            (valtrainvref_done),
        .phy_rx_valvref_ctrl          (valtrainvref_phy_rx_valvref_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_VALTRAINVREF]),
        .local_sweep_en               (ss_local_sweep_en[SS_VALTRAINVREF]),
        .swept_code                   (swept_val_vref_code),
        .best_code                    (best_val_vref_code),
        .sweep_done                   (sweep_done),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_VALTRAINVREF]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_VALTRAINVREF]),
        .tx_msginfo                   (ss_tx_msginfo[SS_VALTRAINVREF]),
        .tx_data_field                (ss_tx_data_field[SS_VALTRAINVREF]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg)
    );

    wrapper_DATATRAINCENTER1 #(
        .MAX_DATA_PI_CODE (MAX_DATA_PI_CODE)
    ) u_DATATRAINCENTER1 (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .datatraincenter1_en          (ss_en[SS_DTC1]),
        .datatraincenter1_done        (dtc1_done),
        .phy_tx_data_pi_phase_ctrl    (dtc1_phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DTC1]),
        .local_sweep_en               (ss_local_sweep_en[SS_DTC1]),
        .swept_code                   (swept_data_pi_code),
        .best_code                    (best_data_pi_code),
        .sweep_done                   (sweep_done),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DTC1]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DTC1]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DTC1]),
        .tx_data_field                (ss_tx_data_field[SS_DTC1]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg)
    );

    wrapper_DATATRAINVREF #(
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE)
    ) u_DATATRAINVREF (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .datatrainvref_en             (ss_en[SS_DATATRAINVREF]),
        .datatrainvref_done           (datatrainvref_done),
        .phy_rx_datavref_ctrl         (datatrainvref_phy_rx_datavref_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DATATRAINVREF]),
        .local_sweep_en               (ss_local_sweep_en[SS_DATATRAINVREF]),
        .swept_code                   (swept_data_vref_code),
        .best_code                    (best_data_vref_code),
        .sweep_done                   (sweep_done),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DATATRAINVREF]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DATATRAINVREF]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DATATRAINVREF]),
        .tx_data_field                (ss_tx_data_field[SS_DATATRAINVREF]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg)
    );

    logic [DATA_DESKEW_W-1:0] swept_deskew_code_with_safe_width;
    logic [DATA_DESKEW_W-1:0] best_deskew_code_with_safe_width [0:15];

    assign swept_deskew_code_with_safe_width = sweep_swept_code[DATA_DESKEW_W-1:0];
    for(lane = 0; lane < 16; lane++) begin
        assign best_deskew_code_with_safe_width[lane] = sweep_best_code[lane][DATA_DESKEW_W-1:0];
    end

    wrapper_RXDESKEW #(
        .MAX_DESKEW_CODE (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE (MIN_DESKEW_CODE)
    ) u_RXDESKEW (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .is_high_speed                (is_high_speed),
        .is_continuous_clk_mode       (is_continuous_clk_mode),
        .rxdeskew_en                  (ss_en[SS_RXDESKEW]),
        .rxdeskew_done                (rxdeskew_done),
        .datatraincenter1_req         (rxdeskew_dtc1_req),
        .trainerror_req               (rxdeskew_trainerror_req_w),
        .phy_rx_deskew_ctrl           (rxdeskew_phy_rx_deskew_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_RXDESKEW]),
        .phy_tx_eq_preset_ctrl        (rxdeskew_phy_tx_eq_preset_ctrl),
        .phy_tx_eq_preset_en          (rxdeskew_phy_tx_eq_preset_en),
        .local_sweep_en               (ss_local_sweep_en[SS_RXDESKEW]),
        .swept_code                   (swept_deskew_code_with_safe_width),
        .best_code                    (best_deskew_code_with_safe_width),
        .min_eye_width                (sweep_min_eye_width),
        .sweep_done                   (sweep_done),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_RXDESKEW]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_RXDESKEW]),
        .tx_msginfo                   (ss_tx_msginfo[SS_RXDESKEW]),
        .tx_data_field                (ss_tx_data_field[SS_RXDESKEW]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo)
    );

    wrapper_DATATRAINCENTER2 #(
        .MAX_DATA_PI_CODE (MAX_DATA_PI_CODE)
    ) u_DATATRAINCENTER2 (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .datatraincenter2_en          (ss_en[SS_DTC2]),
        .datatraincenter2_done        (dtc2_done),
        .phy_tx_data_pi_phase_ctrl    (dtc2_phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en             (ss_partner_sweep_en[SS_DTC2]),
        .local_sweep_en               (ss_local_sweep_en[SS_DTC2]),
        .swept_code                   (swept_data_pi_code),
        .best_code                    (best_data_pi_code),
        .sweep_done                   (sweep_done),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_DTC2]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_DTC2]),
        .tx_msginfo                   (ss_tx_msginfo[SS_DTC2]),
        .tx_data_field                (ss_tx_data_field[SS_DTC2]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg)
    );

    wrapper_LINKSPEED u_LINKSPEED (
        .lclk                          (lclk),
        .rst_n                         (rst_n),
        .soft_rst_n                    (soft_rst_n),
        .linkspeed_en                  (ss_en[SS_LINKSPEED]),
        .linkspeed_done                (linkspeed_done),

        .linkspeed_linkinit_req        (linkspeed_linkinit_req),
        .linkspeed_speedidle_req       (linkspeed_speedidle_req),
        .linkspeed_repair_req          (linkspeed_repair_req),
        .linkspeed_phyretrain_req      (linkspeed_phyretrain_req),

        .active_rx_lanes               (active_tx_lanes),
        .width_degrade_feasible        (degrade_feasible),
        .PHY_IN_RETRAIN                (PHY_IN_RETRAIN),
        .params_changed                (params_changed),
        .PHY_IN_RETRAIN_rst            (PHY_IN_RETRAIN_rst),
        .busy_bit_rst                  (busy_bit_rst),
        .local_sweep_en                (ss_local_sweep_en[SS_LINKSPEED]),
        .partner_sweep_en              (ss_partner_sweep_en[SS_LINKSPEED]),
        .d2c_perlane_pass              (d2c_perlane_pass),
        .local_sweep_done              (sweep_done),
        .linkspeed_success_lanes       (linkspeed_success_lanes),
        // .lcl_tx_elec_idle              (lcl_tx_elec_idle),
        .ptr_rx_elec_idle              (ptr_rx_elec_idle),
        .tx_sb_msg_valid               (ss_tx_sb_msg_valid[SS_LINKSPEED]),
        .tx_sb_msg                     (ss_tx_sb_msg[SS_LINKSPEED]),
        .tx_msginfo                    (ss_tx_msginfo[SS_LINKSPEED]),
        .tx_data_field                 (ss_tx_data_field[SS_LINKSPEED]),
        .rx_sb_msg_valid               (rx_sb_msg_valid),
        .rx_sb_msg                     (rx_sb_msg)
        // .rx_msginfo                    (rx_msginfo),
        // .rx_data_field                 (rx_data_field)
    );
    assign ss_trainerror_req[SS_LINKSPEED] = 1'b0;

    wrapper_REPAIR u_REPAIR (
        .lclk                         (lclk),
        .rst_n                        (rst_n),
        .soft_rst_n                   (soft_rst_n),
        .repair_en                    (ss_en[SS_REPAIR]),
        .repair_done                  (repair_done),
        .trainerror_req               (repair_trainerror_req_w),
        .success_tx_lanes             (linkspeed_success_lanes),
        .rf_cap_SPMW                  (rf_cap_SPMW),
        .rf_ctrl_target_link_width    (rf_ctrl_target_link_width),
        .param_UCIe_S_x8              (param_UCIe_S_x8),
        .mb_rx_data_lane_mask         (mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask         (mb_tx_data_lane_mask),
        .active_rx_lanes              (active_rx_lanes),
        .active_tx_lanes              (active_tx_lanes),
        .degrade_feasible             (degrade_feasible),
        .mbinit_rx_data_lane_mask     (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask     (mbinit_tx_data_lane_mask),
        .state_n_0                    (state_n_0),
        .tx_sb_msg_valid              (ss_tx_sb_msg_valid[SS_REPAIR]),
        .tx_sb_msg                    (ss_tx_sb_msg[SS_REPAIR]),
        .tx_msginfo                   (ss_tx_msginfo[SS_REPAIR]),
        .tx_data_field                (ss_tx_data_field[SS_REPAIR]),
        .rx_sb_msg_valid              (rx_sb_msg_valid),
        .rx_sb_msg                    (rx_sb_msg),
        .rx_msginfo                   (rx_msginfo)
        // .rx_data_field                (rx_data_field)
    );

    assign ss_trainerror_req[SS_REPAIR]  = repair_trainerror_req_w;
    assign ss_trainerror_req[SS_RXDESKEW]= rxdeskew_trainerror_req_w; // BUG FIX: was undriven

    // All remaining substates have no trainerror_req output — tied to 0.
    assign ss_trainerror_req[SS_VALVREF]        = 1'b0;
    assign ss_trainerror_req[SS_DATAVREF]       = 1'b0;
    assign ss_trainerror_req[SS_TXSELFCAL]      = 1'b0;
    assign ss_trainerror_req[SS_VALTRAINCENTER] = 1'b0;
    assign ss_trainerror_req[SS_VALTRAINVREF]   = 1'b0;
    assign ss_trainerror_req[SS_DTC1]           = 1'b0;
    assign ss_trainerror_req[SS_DATATRAINVREF]  = 1'b0;
    assign ss_trainerror_req[SS_DTC2]           = 1'b0;

    // Substates without analog-settle ports get explicit inactive values.
    // (SPEEDIDLE, TXSELFCAL, and RXCLKCAL drive ss_analog_settle_timer_en through their ports above.)
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

    // Substates without D2C sweep capability get sweep enables tied to 0.
    assign ss_local_sweep_en[SS_SPEEDIDLE]   = 1'b0;
    assign ss_local_sweep_en[SS_TXSELFCAL]   = 1'b0;
    assign ss_local_sweep_en[SS_RXCLKCAL]    = 1'b0;
    assign ss_local_sweep_en[SS_REPAIR]      = 1'b0;
    assign ss_partner_sweep_en[SS_SPEEDIDLE] = 1'b0;
    assign ss_partner_sweep_en[SS_TXSELFCAL] = 1'b0;
    assign ss_partner_sweep_en[SS_RXCLKCAL]  = 1'b0;
    assign ss_partner_sweep_en[SS_REPAIR]    = 1'b0;

    // ================================================================================================
    // 6. Output Arbitration, Muxing, and Retained PHY Controls
    // ================================================================================================

    // Combine substate analog-settle timer enables.
    // NOTE: The 8 ms MBTRAIN-state timeout timer is NOT managed here.
    // The future LTSM controller reads current_mbtrain_substate to control it.
    assign analog_settle_timer_en  = |ss_analog_settle_timer_en;

    // Selected Substate Output Muxing
    // Multiplexes MB lane selectors and SB TX messages from the active substate.
    always_comb begin : SUBSTATE_OUTPUT_MUX
        substate_tx_sb_msg_valid     = 1'b0;
        substate_tx_sb_msg           = 8'h00;
        substate_tx_msginfo          = 16'h0000;
        substate_tx_data_field       = 64'h0000_0000_0000_0000;

        for (int i = 0; i < NUM_SUBSTATES; i++) begin
            if (ss_en[i]) begin
                substate_tx_sb_msg_valid     = ss_tx_sb_msg_valid[i];
                substate_tx_sb_msg           = ss_tx_sb_msg[i];
                substate_tx_msginfo          = ss_tx_msginfo[i];
                substate_tx_data_field       = ss_tx_data_field[i];
            end
        end
    end

    unit_MBTRAIN_lane_sel u_MBTRAIN_lane_sel (
        .state_n_0              (state_n_0),
        // .is_high_speed          (is_high_speed),
        // .is_continuous_clk_mode (is_continuous_clk_mode),
        .rx_clk_active          (rx_clk_active),
        // .tx_clk_active          (tx_clk_active),
        // .lcl_tx_elec_idle       (lcl_tx_elec_idle),
        .ptr_rx_elec_idle       (ptr_rx_elec_idle),

        // .mb_tx_clk_lane_sel     (substate_mb_tx_clk_lane_sel),
        // .mb_tx_data_lane_sel    (substate_mb_tx_data_lane_sel),
        // .mb_tx_val_lane_sel     (substate_mb_tx_val_lane_sel),
        // .mb_tx_trk_lane_sel     (substate_mb_tx_trk_lane_sel),

        .mb_rx_clk_lane_sel     (substate_mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel    (substate_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (substate_mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel     (substate_mb_rx_trk_lane_sel)
    );

    // Retained PHY Output Registers
    // These registers capture and hold PHY settings found during training.
    logic is_valtrainvref_entered;
    logic is_dtvref_entered      ;
    logic is_dtc1_entered        ;
    logic is_dtc2_entered        ;

    always_ff @(posedge lclk or negedge rst_n) begin : RETAINED_PHY_OUTPUTS
        if (!rst_n) begin
            // is_valvref_entered        <= 1'b0; <== Not needed
            // is_datavref_entered       <= 1'b0; <== Not needed
            // is_valtraincenter_entered <= 1'b0; <== Not needed
            is_valtrainvref_entered <= 1'b0;
            is_dtvref_entered       <= 1'b0;
            is_dtc1_entered         <= 1'b0;
            is_dtc2_entered         <= 1'b0;
        end else if (!soft_rst_n) begin
            // is_valvref_entered        <= 1'b0; <== Not needed
            // is_datavref_entered       <= 1'b0; <== Not needed
            // is_valtraincenter_entered <= 1'b0; <== Not needed
            is_valtrainvref_entered <= 1'b0;
            is_dtvref_entered       <= 1'b0;
            is_dtc1_entered         <= 1'b0;
            is_dtc2_entered         <= 1'b0;
        end
        // Vref Training
        else if (current_mbtrain_substate == LOG_MBTRAIN_VALTRAINVREF) begin
            // is_valvref_entered      <= 1'b0; <== Not needed
            is_valtrainvref_entered <= 1'b1;
        end
        else if (current_mbtrain_substate == LOG_MBTRAIN_DATATRAINVREF) begin
            // is_datavref_entered <= 1'b0; <== Not needed
            is_dtvref_entered   <= 1'b1;
        end
        else if (current_mbtrain_substate == LOG_MBTRAIN_DATATRAINCENTER1) begin
            is_dtc1_entered <= 1'b1;
            is_dtc2_entered <= 1'b0;
        end
        else if (current_mbtrain_substate == LOG_MBTRAIN_DATATRAINCENTER2) begin
            is_dtc1_entered <= 1'b0;
            is_dtc2_entered <= 1'b1;
        end
    end

// PHY Output Selection Logic
// Muxes between current substate outputs (when active) and retained registers.
    assign phy_negotiated_speed     = speedidle_phy_negotiated_speed   ;
    assign phy_tx_selfcal_en        = txselfcal_phy_tx_selfcal_en      ;
    assign phy_rx_clock_lock_en     = rxclkcal_phy_rx_clock_lock_en    ;
    assign phy_rx_track_lock_en     = rxclkcal_phy_rx_track_lock_en    ;
    assign phy_rx_phase_detector_en = rxclkcal_phy_rx_phase_detector_en;
    assign phy_tx_tckn_shift_en     = rxclkcal_phy_tx_tckn_shift_en    ;
    assign phy_tx_tckn_shift        = rxclkcal_phy_tx_tckn_shift       ;
    assign phy_tx_decrement_shift   = rxclkcal_phy_tx_decrement_shift  ;

    assign phy_rx_val_vref_ctrl       = (!is_valtrainvref_entered)? valvref_phy_rx_valvref_ctrl : valtrainvref_phy_rx_valvref_ctrl;//Valvref is not needed in training mode
    assign phy_tx_val_pi_phase_ctrl   = valtraincenter_phy_tx_val_pi_phase_ctrl;
    for (genvar i = 0; i < 16; i++) begin : DATA_PI_CODE_MUX
        assign phy_rx_data_vref_ctrl[i] = (!is_dtvref_entered)? datavref_phy_rx_datavref_ctrl[i] : datatrainvref_phy_rx_datavref_ctrl[i];
        assign phy_tx_data_pi_phase_ctrl[i] =
            (!is_dtc1_entered && !is_dtc2_entered)? MIN_DATA_PI_CODE[DATA_PI_W-1:0] : // This condition happens at first entry of MBTRAIN
            (is_dtc1_entered)? dtc1_phy_tx_data_pi_phase_ctrl[i] : dtc2_phy_tx_data_pi_phase_ctrl[i];
    end
    assign phy_rx_deskew_ctrl       = rxdeskew_phy_rx_deskew_ctrl;
    assign phy_tx_eq_preset_ctrl    = rxdeskew_phy_tx_eq_preset_ctrl;
    assign phy_tx_eq_preset_en      = rxdeskew_phy_tx_eq_preset_en;





    // =============================================================================
    // Speed encoding (per internal_ltsm_if.sv / UCIe Spec Table 4-1):
    //   3'b000 →  4 GT/s
    //   3'b001 →  8 GT/s
    //   3'b010 → 12 GT/s
    //   3'b011 → 16 GT/s
    //   3'b100 → 24 GT/s
    //   3'b101 → 32 GT/s   ← boundary (≤ 32 GT/s = "standard speed", > 32 GT/s = "high speed")
    //   3'b110 → 48 GT/s   ← HIGH SPEED: requires EQ preset negotiation in RXDESKEW
    //   3'b111 → 64 GT/s   ← HIGH SPEED
    //
    // The critical flag `is_high_speed` is used in RXDESKEW to determine whether
    // EQ Preset negotiation (Step 2) is required, and whether the DTC1 arc loop
    // and exit_to_DTC1 messages are enabled.
    //
    // Memory Reference:
    //   See: target_implementation_technique/null/what_we_will_do_next/memory_for_RXDESKEW_local.md
    //        Section 7 — unit_negotiated_speed.sv Design
    // =========================================================================
    // High-Speed Flag
    // speed > 32 GT/s means encoding is 3'b110 (48 GT/s) or 3'b111 (64 GT/s)
    // =========================================================================
    localparam [2:0] SPEED_32G = 3'b101;
    assign is_high_speed = (phy_negotiated_speed > SPEED_32G);


endmodule
