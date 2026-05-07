module wrapper_D2C_PT (
        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        internal_ltsm_if.d2c2substate_mp       mbinit_if            ,
        internal_ltsm_if.d2c2substate_mp       mbtrain_if           ,
        internal_ltsm_if.current_ltsm_state_mp current_ltsm_state_if,

        //=====================================//
        // Control Signals for MB, SB, LTSM:   //
        //=====================================//
        internal_ltsm_if.d2c2mux_mp            mux_if
    );

    import LTSM_state_pkg::*;

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------      Internal Interfaces and Instances       ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    // Internal interfaces for the two FSM units
    internal_ltsm_if intf_tx (.lclk(mux_if.lclk), .rst_n(mux_if.rst_n));
    internal_ltsm_if intf_rx (.lclk(mux_if.lclk), .rst_n(mux_if.rst_n));

    unit_TX_D2C_PT TX_D2C_PT (
        .substate_if(intf_tx.tx_d2c2substate_mp),
        .mux_if     (intf_tx.d2c2mux_mp) // using the new d2c2mux_mp port mapping
    );

    unit_RX_D2C_PT RX_D2C_PT (
        .substate_if(intf_rx.rx_d2c2substate_mp),
        .mux_if     (intf_rx.d2c2mux_mp) // using the new d2c2mux_mp port mapping
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------       Substate MUX (MBINIT vs MBTRAIN)       ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    // =========================================================================
    // 1. MUX inputs from MBINIT or MBTRAIN to both sub-tests
    // =========================================================================
    always_comb begin : MBINIT_MBTRAIN_INPUTS_MUX
        if (current_ltsm_state_if.current_ltsm_state == MBTRAIN) begin
            // Broadcast MBTRAIN inputs to both TX and RX tests
            intf_tx.rx_pt_en             = mbtrain_if.rx_pt_en;
            intf_tx.tx_pt_en             = mbtrain_if.tx_pt_en;
            intf_tx.d2c_clk_sampling     = mbtrain_if.d2c_clk_sampling;
            intf_tx.d2c_lfsr_en          = mbtrain_if.d2c_lfsr_en;
            intf_tx.d2c_pattern_setup    = mbtrain_if.d2c_pattern_setup;
            intf_tx.d2c_data_pattern_sel = mbtrain_if.d2c_data_pattern_sel;
            intf_tx.d2c_val_pattern_sel  = mbtrain_if.d2c_val_pattern_sel;
            intf_tx.d2c_pattern_mode     = mbtrain_if.d2c_pattern_mode;
            intf_tx.d2c_burst_count      = mbtrain_if.d2c_burst_count;
            intf_tx.d2c_idle_count       = mbtrain_if.d2c_idle_count;
            intf_tx.d2c_iter_count       = mbtrain_if.d2c_iter_count;
            intf_tx.d2c_compare_setup    = mbtrain_if.d2c_compare_setup;

            intf_rx.rx_pt_en             = mbtrain_if.rx_pt_en;
            intf_rx.tx_pt_en             = mbtrain_if.tx_pt_en;
            intf_rx.d2c_clk_sampling     = mbtrain_if.d2c_clk_sampling;
            intf_rx.d2c_lfsr_en          = mbtrain_if.d2c_lfsr_en;
            intf_rx.d2c_pattern_setup    = mbtrain_if.d2c_pattern_setup;
            intf_rx.d2c_data_pattern_sel = mbtrain_if.d2c_data_pattern_sel;
            intf_rx.d2c_val_pattern_sel  = mbtrain_if.d2c_val_pattern_sel;
            intf_rx.d2c_pattern_mode     = mbtrain_if.d2c_pattern_mode;
            intf_rx.d2c_burst_count      = mbtrain_if.d2c_burst_count;
            intf_rx.d2c_idle_count       = mbtrain_if.d2c_idle_count;
            intf_rx.d2c_iter_count       = mbtrain_if.d2c_iter_count;
            intf_rx.d2c_compare_setup    = mbtrain_if.d2c_compare_setup;
        end else begin
            // Broadcast MBINIT inputs to both TX and RX tests
            intf_tx.rx_pt_en             = mbinit_if.rx_pt_en;
            intf_tx.tx_pt_en             = mbinit_if.tx_pt_en;
            intf_tx.d2c_clk_sampling     = mbinit_if.d2c_clk_sampling;
            intf_tx.d2c_lfsr_en          = mbinit_if.d2c_lfsr_en;
            intf_tx.d2c_pattern_setup    = mbinit_if.d2c_pattern_setup;
            intf_tx.d2c_data_pattern_sel = mbinit_if.d2c_data_pattern_sel;
            intf_tx.d2c_val_pattern_sel  = mbinit_if.d2c_val_pattern_sel;
            intf_tx.d2c_pattern_mode     = mbinit_if.d2c_pattern_mode;
            intf_tx.d2c_burst_count      = mbinit_if.d2c_burst_count;
            intf_tx.d2c_idle_count       = mbinit_if.d2c_idle_count;
            intf_tx.d2c_iter_count       = mbinit_if.d2c_iter_count;
            intf_tx.d2c_compare_setup    = mbinit_if.d2c_compare_setup;

            intf_rx.rx_pt_en             = mbinit_if.rx_pt_en;
            intf_rx.tx_pt_en             = mbinit_if.tx_pt_en;
            intf_rx.d2c_clk_sampling     = mbinit_if.d2c_clk_sampling;
            intf_rx.d2c_lfsr_en          = mbinit_if.d2c_lfsr_en;
            intf_rx.d2c_pattern_setup    = mbinit_if.d2c_pattern_setup;
            intf_rx.d2c_data_pattern_sel = mbinit_if.d2c_data_pattern_sel;
            intf_rx.d2c_val_pattern_sel  = mbinit_if.d2c_val_pattern_sel;
            intf_rx.d2c_pattern_mode     = mbinit_if.d2c_pattern_mode;
            intf_rx.d2c_burst_count      = mbinit_if.d2c_burst_count;
            intf_rx.d2c_idle_count       = mbinit_if.d2c_idle_count;
            intf_rx.d2c_iter_count       = mbinit_if.d2c_iter_count;
            intf_rx.d2c_compare_setup    = mbinit_if.d2c_compare_setup;
        end
    end

    // =========================================================================
    // 2. MUX outputs from the active test back to the MBINIT and MBTRAIN
    // =========================================================================
    always_comb begin : D2C_TESTS_OUTPUTS_MUX
        // Check which test is active based on the tx_pt_en signal.
        // We look at intf_tx.tx_pt_en because the inputs are already broadcasted to both tests.
        if (intf_tx.tx_pt_en) begin
            // TX test is active -> Use outputs from unit_TX_D2C_PT
            mbinit_if.test_d2c_done                    = intf_tx.test_d2c_done;
            mbinit_if.d2c_aggr_err                     = intf_tx.d2c_aggr_err;
            mbinit_if.d2c_perlane_err                  = intf_tx.d2c_perlane_err;
            mbinit_if.d2c_val_err                      = intf_tx.d2c_val_err;
            mbinit_if.d2c_clk_err                      = intf_tx.d2c_clk_err;
            // mbinit_if.partner_valtraincenter_fail_flag = intf_tx.partner_valtraincenter_fail_flag;

            mbtrain_if.test_d2c_done                   = intf_tx.test_d2c_done;
            mbtrain_if.d2c_aggr_err                    = intf_tx.d2c_aggr_err;
            mbtrain_if.d2c_perlane_err                 = intf_tx.d2c_perlane_err;
            mbtrain_if.d2c_val_err                     = intf_tx.d2c_val_err;
            mbtrain_if.d2c_clk_err                     = intf_tx.d2c_clk_err;
            // mbtrain_if.partner_valtraincenter_fail_flag= intf_tx.partner_valtraincenter_fail_flag;
        end else begin
            // RX test is active (or both are idle) -> Use outputs from unit_RX_D2C_PT
            mbinit_if.test_d2c_done                    = intf_rx.test_d2c_done;
            mbinit_if.d2c_aggr_err                     = intf_rx.d2c_aggr_err;
            mbinit_if.d2c_perlane_err                  = intf_rx.d2c_perlane_err;
            mbinit_if.d2c_val_err                      = intf_rx.d2c_val_err;
            mbinit_if.d2c_clk_err                      = intf_rx.d2c_clk_err;
            // mbinit_if.partner_valtraincenter_fail_flag = intf_rx.partner_valtraincenter_fail_flag;

            mbtrain_if.test_d2c_done                   = intf_rx.test_d2c_done;
            mbtrain_if.d2c_aggr_err                    = intf_rx.d2c_aggr_err;
            mbtrain_if.d2c_perlane_err                 = intf_rx.d2c_perlane_err;
            mbtrain_if.d2c_val_err                     = intf_rx.d2c_val_err;
            mbtrain_if.d2c_clk_err                     = intf_rx.d2c_clk_err;
            // mbtrain_if.partner_valtraincenter_fail_flag= intf_rx.partner_valtraincenter_fail_flag;
        end

        // partner_valtraincenter_fail_flag is only driven by unit_TX_D2C_PT (receives SB results).
        // unit_RX_D2C_PT does not drive it, so we always take it from intf_tx to avoid X propagation.
        mbinit_if.partner_valtraincenter_fail_flag  = intf_tx.partner_valtraincenter_fail_flag;
        mbtrain_if.partner_valtraincenter_fail_flag = intf_tx.partner_valtraincenter_fail_flag;
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------             MUX (MB, SB, RF) MUX             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    // =========================================================================
    // 3. Broadcast inputs FROM the MUX (MB/SB) to BOTH tests
    // =========================================================================
    always_comb begin : MUX_INPUTS_BROADCAST
        // Inputs from MB
        intf_tx.mb_tx_pattern_count_done          = mux_if.mb_tx_pattern_count_done;
        intf_tx.mb_rx_aggr_err                    = mux_if.mb_rx_aggr_err;
        intf_tx.mb_rx_perlane_err                 = mux_if.mb_rx_perlane_err;
        intf_tx.mb_rx_val_err                     = mux_if.mb_rx_val_err;
        intf_tx.mb_rx_clk_err                     = mux_if.mb_rx_clk_err;
        intf_tx.mb_rx_compare_done                = mux_if.mb_rx_compare_done;

        intf_rx.mb_tx_pattern_count_done          = mux_if.mb_tx_pattern_count_done;
        intf_rx.mb_rx_aggr_err                    = mux_if.mb_rx_aggr_err;
        intf_rx.mb_rx_perlane_err                 = mux_if.mb_rx_perlane_err;
        intf_rx.mb_rx_val_err                     = mux_if.mb_rx_val_err;
        intf_rx.mb_rx_clk_err                     = mux_if.mb_rx_clk_err;
        intf_rx.mb_rx_compare_done                = mux_if.mb_rx_compare_done;

        // Inputs from SB
        intf_tx.rx_sb_msg_valid                   = mux_if.rx_sb_msg_valid;
        intf_tx.rx_sb_msg                         = mux_if.rx_sb_msg;
        intf_tx.rx_msginfo                        = mux_if.rx_msginfo;
        intf_tx.rx_data_field                     = mux_if.rx_data_field;

        intf_rx.rx_sb_msg_valid                   = mux_if.rx_sb_msg_valid;
        intf_rx.rx_sb_msg                         = mux_if.rx_sb_msg;
        intf_rx.rx_msginfo                        = mux_if.rx_msginfo;
        intf_rx.rx_data_field                     = mux_if.rx_data_field;

        // Inputs from RF
        intf_tx.cfg_train4_max_err_thresh_perlane = mux_if.cfg_train4_max_err_thresh_perlane;
        intf_tx.cfg_train4_max_err_thresh_aggr    = mux_if.cfg_train4_max_err_thresh_aggr;

        intf_rx.cfg_train4_max_err_thresh_perlane = mux_if.cfg_train4_max_err_thresh_perlane;
        intf_rx.cfg_train4_max_err_thresh_aggr    = mux_if.cfg_train4_max_err_thresh_aggr;
    end

    // =========================================================================
    // 4. MUX outputs FROM the active test TO the MUX (MB/SB)
    // =========================================================================
    always_comb begin : MUX_OUTPUTS_MUX
        // Use tx_pt_en to determine if we should drive outputs from unit_TX_D2C_PT or unit_RX_D2C_PT
        if (intf_tx.tx_pt_en) begin
            // Route outputs from the TX test
            mux_if.mb_tx_clk_sampling_en       = intf_tx.mb_tx_clk_sampling_en;
            mux_if.mb_tx_clk_sampling          = intf_tx.mb_tx_clk_sampling;

            mux_if.mb_tx_pattern_en            = intf_tx.mb_tx_pattern_en;
            mux_if.mb_tx_pattern_setup         = intf_tx.mb_tx_pattern_setup;
            mux_if.mb_tx_data_pattern_sel      = intf_tx.mb_tx_data_pattern_sel;
            mux_if.mb_tx_val_pattern_sel       = intf_tx.mb_tx_val_pattern_sel;
            mux_if.mb_tx_lfsr_en               = intf_tx.mb_tx_lfsr_en;
            mux_if.mb_tx_lfsr_rst              = intf_tx.mb_tx_lfsr_rst;
            mux_if.mb_rx_lfsr_en               = intf_tx.mb_rx_lfsr_en;
            mux_if.mb_rx_lfsr_rst              = intf_tx.mb_rx_lfsr_rst;

            mux_if.mb_tx_pattern_mode          = intf_tx.mb_tx_pattern_mode;
            mux_if.mb_tx_burst_count           = intf_tx.mb_tx_burst_count;
            mux_if.mb_tx_idle_count            = intf_tx.mb_tx_idle_count;
            mux_if.mb_tx_iter_count            = intf_tx.mb_tx_iter_count;

            mux_if.mb_rx_compare_en            = intf_tx.mb_rx_compare_en;
            mux_if.mb_rx_max_err_thresh_aggr   = intf_tx.mb_rx_max_err_thresh_aggr;
            mux_if.mb_rx_max_err_thresh_perlane= intf_tx.mb_rx_max_err_thresh_perlane;
            mux_if.mb_rx_compare_setup         = intf_tx.mb_rx_compare_setup;

            mux_if.mb_tx_clk_lane_sel          = intf_tx.mb_tx_clk_lane_sel;
            mux_if.mb_tx_data_lane_sel         = intf_tx.mb_tx_data_lane_sel;
            mux_if.mb_tx_val_lane_sel          = intf_tx.mb_tx_val_lane_sel;
            mux_if.mb_tx_trk_lane_sel          = intf_tx.mb_tx_trk_lane_sel;
            mux_if.mb_rx_clk_lane_sel          = intf_tx.mb_rx_clk_lane_sel;
            mux_if.mb_rx_data_lane_sel         = intf_tx.mb_rx_data_lane_sel;
            mux_if.mb_rx_val_lane_sel          = intf_tx.mb_rx_val_lane_sel;
            mux_if.mb_rx_trk_lane_sel          = intf_tx.mb_rx_trk_lane_sel;

            mux_if.tx_sb_msg_valid             = intf_tx.tx_sb_msg_valid;
            mux_if.tx_sb_msg                   = intf_tx.tx_sb_msg;
            mux_if.tx_msginfo                  = intf_tx.tx_msginfo;
            mux_if.tx_data_field               = intf_tx.tx_data_field;
        end else begin
            // Route outputs from the RX test
            mux_if.mb_tx_clk_sampling_en       = intf_rx.mb_tx_clk_sampling_en;
            mux_if.mb_tx_clk_sampling          = intf_rx.mb_tx_clk_sampling;

            mux_if.mb_tx_pattern_en            = intf_rx.mb_tx_pattern_en;
            mux_if.mb_tx_pattern_setup         = intf_rx.mb_tx_pattern_setup;
            mux_if.mb_tx_data_pattern_sel      = intf_rx.mb_tx_data_pattern_sel;
            mux_if.mb_tx_val_pattern_sel       = intf_rx.mb_tx_val_pattern_sel;
            mux_if.mb_tx_lfsr_en               = intf_rx.mb_tx_lfsr_en;
            mux_if.mb_tx_lfsr_rst              = intf_rx.mb_tx_lfsr_rst;
            mux_if.mb_rx_lfsr_en               = intf_rx.mb_rx_lfsr_en;
            mux_if.mb_rx_lfsr_rst              = intf_rx.mb_rx_lfsr_rst;

            mux_if.mb_tx_pattern_mode          = intf_rx.mb_tx_pattern_mode;
            mux_if.mb_tx_burst_count           = intf_rx.mb_tx_burst_count;
            mux_if.mb_tx_idle_count            = intf_rx.mb_tx_idle_count;
            mux_if.mb_tx_iter_count            = intf_rx.mb_tx_iter_count;

            mux_if.mb_rx_compare_en            = intf_rx.mb_rx_compare_en;
            mux_if.mb_rx_max_err_thresh_aggr   = intf_rx.mb_rx_max_err_thresh_aggr;
            mux_if.mb_rx_max_err_thresh_perlane= intf_rx.mb_rx_max_err_thresh_perlane;
            mux_if.mb_rx_compare_setup         = intf_rx.mb_rx_compare_setup;

            mux_if.mb_tx_clk_lane_sel          = intf_rx.mb_tx_clk_lane_sel;
            mux_if.mb_tx_data_lane_sel         = intf_rx.mb_tx_data_lane_sel;
            mux_if.mb_tx_val_lane_sel          = intf_rx.mb_tx_val_lane_sel;
            mux_if.mb_tx_trk_lane_sel          = intf_rx.mb_tx_trk_lane_sel;
            mux_if.mb_rx_clk_lane_sel          = intf_rx.mb_rx_clk_lane_sel;
            mux_if.mb_rx_data_lane_sel         = intf_rx.mb_rx_data_lane_sel;
            mux_if.mb_rx_val_lane_sel          = intf_rx.mb_rx_val_lane_sel;
            mux_if.mb_rx_trk_lane_sel          = intf_rx.mb_rx_trk_lane_sel;

            mux_if.tx_sb_msg_valid             = intf_rx.tx_sb_msg_valid;
            mux_if.tx_sb_msg                   = intf_rx.tx_sb_msg;
            mux_if.tx_msginfo                  = intf_rx.tx_msginfo;
            mux_if.tx_data_field               = intf_rx.tx_data_field;
        end
    end

endmodule