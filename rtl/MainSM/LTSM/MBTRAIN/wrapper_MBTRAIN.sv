// =============================================================================
// Module  : wrapper_MBTRAIN
// Purpose : Centralized wrapper for MBTRAIN sub-states and control logic.
//           Instantiates all 13 sub-state FSMs, unit_MBTRAIN_ctrl, and
//           the shared D2C test modules (via wrapper_D2C_PT).
//           Implements MUX/DEMUX logic for D2C handshakes and MB/SB/PHY signals.
// =============================================================================

// This module is a wrapper for the MBTRAIN module
// It instantiates these Substates Modules:
//    .------.---------------------------.----------------------------------------------------.
//    |  No. |      Substate Name        |                      Modules                       |
//    '------'---------------------------'----------------------------------------------------'
//    |   1.    MBTRAIN.VALVREF          | unit_VALVREF                                       |
//    |   2.    MBTRAIN.DATAVREF         | unit_DATAVREF                                      |
//    |   3.    MBTRAIN.SPEEDIDLE        | unit_SPEEDIDLE                                     |
//    |   4.    MBTRAIN.TXSELFCAL        | unit_TXSELFCAL                                     |
//    |   5.    MBTRAIN.RXCLKCAL         | unit_RXCLKCAL                                      |
//    |   6.    MBTRAIN.VALTRAINCENTER   | unit_VALTRAINCENTER                                |
//    |   7.    MBTRAIN.VALTRAINVREF     | unit_VALTRAINVREF                                  |
//    |   8.    MBTRAIN.DATATRAINCENTER1 | unit_DATATRAINCENTER1                              |
//    |   9.    MBTRAIN.DATATRAINVREF    | unit_DATATRAINVREF                                 |
//    |   10.   MBTRAIN.RXDESKEW         | unit_RXDESKEW & unit_phase_interpolator_for_deskew |
//    |   11.   MBTRAIN.DATATRAINCENTER2 | unit_DATATRAINCENTER2                              |
//    |   12.   MBTRAIN.LINKSPEED        | unit_LINKSPEED                                     |
//    |   13.   MBTRAIN.REPAIR           | unit_REPAIR                                        |
//    |   --             ---             | unit_MBTRAIN_ctrl                                  |
//    '----------------------------------'----------------------------------------------------'
module wrapper_MBTRAIN #(
        // Sweep-range parameters – synthesis defaults are full-range spec values.
        // Override to smaller values in simulation to keep run-time manageable.
        parameter integer MAX_VAL_VREF_CODE  = 127 , // unit_VALVREF / unit_VALTRAINVREF upper bound
        parameter integer MIN_VAL_VREF_CODE  = 0   , // unit_VALVREF / unit_VALTRAINVREF lower bound
        parameter integer MAX_DATA_VREF_CODE = 127 , // unit_DATAVREF / unit_DATATRAINVREF upper bound
        parameter integer MIN_DATA_VREF_CODE = 0   , // unit_DATAVREF / unit_DATATRAINVREF lower bound
        parameter integer MAX_PI_PHASE_CODE  = 127 , // PI phase upper bound (VALTRAINCENTER, DTC1/2)
        parameter integer MIN_PI_PHASE_CODE  = 0   , // PI phase lower bound
        parameter integer MAX_DESKEW_CODE    = 127 , // for Deskew control. For the MB Rx Data Lanes.
        parameter integer MIN_DESKEW_CODE    = 0     // for Deskew control. For the MB Rx Data Lanes.
    ) (
        internal_ltsm_if.mbtrain_mp          mbtrain_if,
        internal_ltsm_if.substate2d2c_mp     d2c_if
    );

    import ltsm_state_n_pkg::*;

    // =========================================================================
    // 1. Internal Interface Declarations (23 Total)
    // =========================================================================
    parameter VAL_VREF_CODE_WIDTH  = $clog2(MAX_VAL_VREF_CODE + 1);
    parameter DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE + 1);
    parameter PI_PHASE_WIDTH       = $clog2(MAX_PI_PHASE_CODE + 1);

    // Per-substate Control Interfaces (13) – fully parameterized
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_valvref          (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_datavref         (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_speedidle        (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_txselfcal        (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_rxclkcal         (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_valtraincenter   (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_valtrainvref     (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_datatraincenter1 (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_datatrainvref    (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_rxdeskew         (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_datatraincenter2 (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_linkspeed        (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) intf_repair           (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));

    // Per-substate D2C Handshake Interfaces (9) – parameterized for type consistency
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_valvref          (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_datavref         (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_valtraincenter   (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_valtrainvref     (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_datatraincenter1 (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_datatrainvref    (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_rxdeskew         (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_datatraincenter2 (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) d2c_linkspeed        (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));

    // -- unit_MBTRAIN_ctrl control interface --
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   )
    ) ctrl_if              (.lclk(mbtrain_if.lclk), .rst_n(mbtrain_if.rst_n));

    // =========================================================================
    // 2. Module Instantiations
    // =========================================================================


    // MBTRAIN Controller
    unit_MBTRAIN_ctrl #() MBTRAIN_CTRL (
        .itf (ctrl_if.mbtrain_ctrl_mp)
    );

    // Sub-state FSMs
    // 1. MBTRAIN.VALVREF
    unit_VALVREF #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) VALVREF (
        .valvref_if (intf_valvref.valvref_mp),
        .d2c_if     (d2c_valvref.substate2d2c_mp)
    );

    // 2. MBTRAIN.DATAVREF
    unit_DATAVREF  #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE)
    ) DATAVREF (
        .datavref_if (intf_datavref.datavref_mp),
        .d2c_if      (d2c_datavref.substate2d2c_mp)
    );

    // 3. MBTRAIN.SPEEDIDLE
    unit_SPEEDIDLE #() SPEEDIDLE (
        .speedidle_if (intf_speedidle.speedidle_mp)
    );

    // 4. MBTRAIN.TXSELFCAL
    unit_TXSELFCAL #() TXSELFCAL (
        .txselfcal_if (intf_txselfcal.txselfcal_mp)
    );

    // 5. MBTRAIN.RXCLKCAL
    unit_RXCLKCAL #() RXCLKCAL (
        .rxclkcal_if (intf_rxclkcal.rxclkcal_mp)
    );

    // 6. MBTRAIN.VALTRAINCENTER
    unit_VALTRAINCENTER #(
        .MAX_PHASE_CODE(MAX_PI_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PI_PHASE_CODE)
    ) VALTRAINCENTER (
        .valtraincenter_if (intf_valtraincenter.valtraincenter_mp),
        .d2c_if            (d2c_valtraincenter.substate2d2c_mp)
    );

    // 7. MBTRAIN.VALTRAINVREF
    unit_VALTRAINVREF #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) VALTRAINVREF (
        .valtrainvref_if (intf_valtrainvref.valtrainvref_mp),
        .d2c_if          (d2c_valtrainvref.substate2d2c_mp)
    );

    // 8. MBTRAIN.DATATRAINCENTER1
    unit_DATATRAINCENTER1 #(
        .MAX_PHASE_CODE(MAX_PI_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PI_PHASE_CODE)
    ) DTC1 (
        .dtc1_if (intf_datatraincenter1.datatraincenter1_mp),
        .d2c_if  (d2c_datatraincenter1.substate2d2c_mp     )
    );

    // 9. MBTRAIN.DATATRAINVREF
    unit_DATATRAINVREF #(
        .MAX_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_VREF_CODE(MIN_DATA_VREF_CODE)
    ) DTVREF (
        .dtvref_if (intf_datatrainvref.datatrainvref_mp),
        .d2c_if    (d2c_datatrainvref.substate2d2c_mp  )
    );

    // 10. MBTRAIN.RXDESKEW
    unit_RXDESKEW #(
        .MAX_DESKEW_CODE (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE (MIN_DESKEW_CODE)
    ) RXDESKEW (
        .rxdeskew_if (intf_rxdeskew.rxdeskew_mp),
        .d2c_if      (d2c_rxdeskew.substate2d2c_mp)
    );

    // 11. MBTRAIN.DATATRAINCENTER2
    unit_DATATRAINCENTER2 #(
        .MAX_PHASE_CODE(MAX_PI_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PI_PHASE_CODE)
    ) DTC2 (
        .dtc2_if (intf_datatraincenter2.datatraincenter2_mp),
        .d2c_if  (d2c_datatraincenter2.substate2d2c_mp)
    );

    // 12. MBTRAIN.LINKSPEED
    unit_LINKSPEED #() LINKSPEED (
        .ls_if  (intf_linkspeed.linkspeed_mp),
        .d2c_if (d2c_linkspeed.substate2d2c_mp)
    );

    // 13. MBTRAIN.REPAIR
    unit_REPAIR #() REPAIR (
        .rp_if (intf_repair.repair_mp)
    );

    reg is_ltsm_out_of_reset; // We use this signal to apply reset for all needed signal in the MBTRAIN substates to add the feature of the software reset.

    always @(posedge mbtrain_if.lclk or negedge mbtrain_if.rst_n) begin
        if (!mbtrain_if.rst_n) begin
            is_ltsm_out_of_reset <= 1'b0;
        end
        else if (mbtrain_if.current_ltsm_state == LTSM_state_pkg::SBINIT) begin
            is_ltsm_out_of_reset <= 1'b1;
        end
    end
    assign intf_valvref.is_ltsm_out_of_reset          = is_ltsm_out_of_reset;
    assign intf_datavref.is_ltsm_out_of_reset         = is_ltsm_out_of_reset;
    assign intf_speedidle.is_ltsm_out_of_reset        = is_ltsm_out_of_reset;
    assign intf_txselfcal.is_ltsm_out_of_reset        = is_ltsm_out_of_reset;
    assign intf_rxclkcal.is_ltsm_out_of_reset         = is_ltsm_out_of_reset;
    assign intf_valtraincenter.is_ltsm_out_of_reset   = is_ltsm_out_of_reset;
    assign intf_valtrainvref.is_ltsm_out_of_reset     = is_ltsm_out_of_reset;
    assign intf_datatraincenter1.is_ltsm_out_of_reset = is_ltsm_out_of_reset;
    assign intf_datatrainvref.is_ltsm_out_of_reset    = is_ltsm_out_of_reset;
    assign intf_rxdeskew.is_ltsm_out_of_reset         = is_ltsm_out_of_reset;
    assign intf_datatraincenter2.is_ltsm_out_of_reset = is_ltsm_out_of_reset;
    assign intf_linkspeed.is_ltsm_out_of_reset        = is_ltsm_out_of_reset;
    assign intf_repair.is_ltsm_out_of_reset           = is_ltsm_out_of_reset;
    assign ctrl_if.is_ltsm_out_of_reset               = is_ltsm_out_of_reset;



    // =========================================================================
    // 3. Handshake Wiring (Controller <-> Sub-states)
    // =========================================================================
    assign ctrl_if.mbtrain_en                  = mbtrain_if.mbtrain_en;
    assign mbtrain_if.mbtrain_done             = ctrl_if.mbtrain_done;
    assign mbtrain_if.current_mbtrain_substate = ctrl_if.current_mbtrain_substate;

    // EN signals (Output from Controller)
    assign intf_valvref.valvref_en                   = ctrl_if.valvref_en;
    assign intf_datavref.datavref_en                 = ctrl_if.datavref_en;
    assign intf_speedidle.speedidle_en               = ctrl_if.speedidle_en;
    assign intf_txselfcal.txselfcal_en               = ctrl_if.txselfcal_en;
    assign intf_rxclkcal.rxclkcal_en                 = ctrl_if.rxclkcal_en;
    assign intf_valtraincenter.valtraincenter_en     = ctrl_if.valtraincenter_en;
    assign intf_valtrainvref.valtrainvref_en         = ctrl_if.valtrainvref_en;
    assign intf_datatraincenter1.datatraincenter1_en = ctrl_if.datatraincenter1_en;
    assign intf_datatrainvref.datatrainvref_en       = ctrl_if.datatrainvref_en;
    assign intf_rxdeskew.rxdeskew_en                 = ctrl_if.rxdeskew_en;
    assign intf_datatraincenter2.datatraincenter2_en = ctrl_if.datatraincenter2_en;
    assign intf_linkspeed.linkspeed_en               = ctrl_if.linkspeed_en;
    assign intf_repair.repair_en                     = ctrl_if.repair_en;

    // DONE signals (Input to Controller)
    assign ctrl_if.valvref_done          = intf_valvref.valvref_done;
    assign ctrl_if.datavref_done         = intf_datavref.datavref_done;
    assign ctrl_if.speedidle_done        = intf_speedidle.speedidle_done;
    assign ctrl_if.txselfcal_done        = intf_txselfcal.txselfcal_done;
    assign ctrl_if.rxclkcal_done         = intf_rxclkcal.rxclkcal_done;
    assign ctrl_if.valtraincenter_done   = intf_valtraincenter.valtraincenter_done;
    assign ctrl_if.valtrainvref_done     = intf_valtrainvref.valtrainvref_done;
    assign ctrl_if.datatraincenter1_done = intf_datatraincenter1.datatraincenter1_done;
    assign ctrl_if.datatrainvref_done    = intf_datatrainvref.datatrainvref_done;
    assign ctrl_if.rxdeskew_done         = intf_rxdeskew.rxdeskew_done;
    assign ctrl_if.datatraincenter2_done = intf_datatraincenter2.datatraincenter2_done;
    assign ctrl_if.linkspeed_done        = intf_linkspeed.linkspeed_done;
    assign ctrl_if.repair_done           = intf_repair.repair_done;

    // (Inputs from outside blocks)
    assign ctrl_if.mbtrain_repair_req    = mbtrain_if.mbtrain_repair_req   ;
    assign ctrl_if.mbtrain_speedidle_req = mbtrain_if.mbtrain_speedidle_req;
    assign ctrl_if.mbtrain_txselfcal_req = mbtrain_if.mbtrain_txselfcal_req;

    // REQ signals (Input to Controller)
    assign ctrl_if.trainerror_req =
        intf_valvref.trainerror_req          | intf_datavref.trainerror_req         |
        intf_speedidle.trainerror_req        | intf_txselfcal.trainerror_req        |
        intf_rxclkcal.trainerror_req         | intf_valtraincenter.trainerror_req   |
        intf_valtrainvref.trainerror_req     | intf_datatraincenter1.trainerror_req |
        intf_datatrainvref.trainerror_req    | intf_rxdeskew.trainerror_req         |
        intf_datatraincenter2.trainerror_req | intf_linkspeed.trainerror_req        |
        intf_repair.trainerror_req;

    assign mbtrain_if.trainerror_req = ctrl_if.trainerror_req ;

    assign ctrl_if.speedidle_req         = intf_linkspeed.speedidle_req;
    assign ctrl_if.repair_req            = intf_linkspeed.repair_req;
    assign ctrl_if.phyretrain_req        = intf_linkspeed.phyretrain_req;
    assign ctrl_if.linkinit_req          = intf_linkspeed.linkinit_req;
    assign ctrl_if.txselfcal_req         = intf_repair.txselfcal_req;
    assign ctrl_if.datatraincenter1_req  = intf_rxdeskew.datatraincenter1_req;



    // =========================================================================
    // 4. D2C Bridge MUX/DEMUX (9-to-1)
    // =========================================================================

    mbtrain_substate_e active_substate;
    assign active_substate = ctrl_if.current_mbtrain_substate;

    // Input signals from wrapper_D2C_PT (Sub-state <- D2C): We receives:
    //     1. test_d2c_done
    //     2. d2c_aggr_err
    //     3. d2c_perlane_err
    //     4. d2c_val_err
    //     5. d2c_clk_err
    //     6. partner_valtraincenter_fail_flag

    // 1. [test_d2c_done]
    assign d2c_valvref         .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_datavref        .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_valtraincenter  .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_valtrainvref    .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_datatraincenter1.test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_datatrainvref   .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_rxdeskew        .test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_datatraincenter2.test_d2c_done = d2c_if.test_d2c_done;
    assign d2c_linkspeed       .test_d2c_done = d2c_if.test_d2c_done;

    // 2. [d2c_aggr_err]
    assign d2c_valvref         .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_datavref        .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_valtraincenter  .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_valtrainvref    .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_datatraincenter1.d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_datatrainvref   .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_rxdeskew        .d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_datatraincenter2.d2c_aggr_err = d2c_if.d2c_aggr_err;
    assign d2c_linkspeed       .d2c_aggr_err = d2c_if.d2c_aggr_err;

    // 3. [d2c_perlane_err]
    assign d2c_valvref         .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_datavref        .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_valtraincenter  .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_valtrainvref    .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_datatraincenter1.d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_datatrainvref   .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_rxdeskew        .d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_datatraincenter2.d2c_perlane_err = d2c_if.d2c_perlane_err;
    assign d2c_linkspeed       .d2c_perlane_err = d2c_if.d2c_perlane_err;

    // 4. [d2c_val_err]
    assign d2c_valvref         .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_datavref        .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_valtraincenter  .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_valtrainvref    .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_datatraincenter1.d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_datatrainvref   .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_rxdeskew        .d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_datatraincenter2.d2c_val_err = d2c_if.d2c_val_err;
    assign d2c_linkspeed       .d2c_val_err = d2c_if.d2c_val_err;

    // 5. [d2c_clk_err]
    assign d2c_valvref         .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_datavref        .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_valtraincenter  .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_valtrainvref    .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_datatraincenter1.d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_datatrainvref   .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_rxdeskew        .d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_datatraincenter2.d2c_clk_err = d2c_if.d2c_clk_err;
    assign d2c_linkspeed       .d2c_clk_err = d2c_if.d2c_clk_err;

    // 6. [partner_valtraincenter_fail_flag]
    assign d2c_valvref         .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_datavref        .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_valtraincenter  .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_valtrainvref    .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_datatraincenter1.partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_datatrainvref   .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_rxdeskew        .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_datatraincenter2.partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;
    assign d2c_linkspeed       .partner_valtraincenter_fail_flag = d2c_if.partner_valtraincenter_fail_flag;


    // =========================================================================
    // 4. Substate -> D2C Mux (Continuous Assignments)
    // =====================================================================
    assign d2c_if.rx_pt_en =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.rx_pt_en :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.rx_pt_en :
        1'b0;

    assign d2c_if.tx_pt_en =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.tx_pt_en :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.tx_pt_en :
        1'b0;

    assign d2c_if.d2c_clk_sampling =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_clk_sampling :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_clk_sampling :
        2'b00;

    assign d2c_if.d2c_lfsr_en =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_lfsr_en :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_lfsr_en :
        1'b0;

    assign d2c_if.d2c_pattern_setup =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_pattern_setup :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_pattern_setup :
        3'b000;

    assign d2c_if.d2c_data_pattern_sel =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_data_pattern_sel :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_data_pattern_sel :
        2'b00;

    assign d2c_if.d2c_val_pattern_sel =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_val_pattern_sel :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_val_pattern_sel :
        1'b0;

    assign d2c_if.d2c_pattern_mode =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_pattern_mode :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_pattern_mode :
        1'b0;

    assign d2c_if.d2c_burst_count =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_burst_count :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_burst_count :
        16'h0000;

    assign d2c_if.d2c_idle_count =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_idle_count :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_idle_count :
        16'h0000;

    assign d2c_if.d2c_iter_count =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_iter_count :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_iter_count :
        16'h0000;

    assign d2c_if.d2c_compare_setup =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? d2c_valvref.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? d2c_datavref.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? d2c_valtraincenter.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? d2c_valtrainvref.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? d2c_datatraincenter1.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? d2c_datatrainvref.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? d2c_rxdeskew.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? d2c_datatraincenter2.d2c_compare_setup :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? d2c_linkspeed.d2c_compare_setup :
        2'b00;
    // ================================================================================= //
    // ================================================================================= //
    // ===============                                                    ============== //
    // ===========      Now these interfaceses their logic is completed:      ========== //
    // ======                  "ctrl_if" (for unit_LTSM_ctrl)                     ====== //
    // ===========             "d2c_if"  (for wrapper_D2C_PT)                 ========== //
    // ===============                                                    ============== //
    // ================================================================================= //
    // ================================================================================= //

    // =========================================================================
    // 5. Global Signal Broadcasting
    // =========================================================================
    always_comb begin : BROADCAST_LOGIC
        // Timer Broadcast
        intf_valvref.timeout_8ms_occured              = mbtrain_if.timeout_8ms_occured    ;
        intf_valvref.analog_settle_time_done          = mbtrain_if.analog_settle_time_done;
        // ... repeat for all 13 ...
        intf_datavref.timeout_8ms_occured             = mbtrain_if.timeout_8ms_occured    ;
        intf_datavref.analog_settle_time_done         = mbtrain_if.analog_settle_time_done;
        intf_speedidle.timeout_8ms_occured            = mbtrain_if.timeout_8ms_occured    ;
        intf_speedidle.analog_settle_time_done        = mbtrain_if.analog_settle_time_done;
        intf_txselfcal.timeout_8ms_occured            = mbtrain_if.timeout_8ms_occured    ;
        intf_txselfcal.analog_settle_time_done        = mbtrain_if.analog_settle_time_done;
        intf_rxclkcal.timeout_8ms_occured             = mbtrain_if.timeout_8ms_occured    ;
        intf_rxclkcal.analog_settle_time_done         = mbtrain_if.analog_settle_time_done;
        intf_valtraincenter.timeout_8ms_occured       = mbtrain_if.timeout_8ms_occured    ;
        intf_valtraincenter.analog_settle_time_done   = mbtrain_if.analog_settle_time_done;
        intf_valtrainvref.timeout_8ms_occured         = mbtrain_if.timeout_8ms_occured    ;
        intf_valtrainvref.analog_settle_time_done     = mbtrain_if.analog_settle_time_done;
        intf_datatraincenter1.timeout_8ms_occured     = mbtrain_if.timeout_8ms_occured    ;
        intf_datatraincenter1.analog_settle_time_done = mbtrain_if.analog_settle_time_done;
        intf_datatrainvref.timeout_8ms_occured        = mbtrain_if.timeout_8ms_occured    ;
        intf_datatrainvref.analog_settle_time_done    = mbtrain_if.analog_settle_time_done;
        intf_rxdeskew.timeout_8ms_occured             = mbtrain_if.timeout_8ms_occured    ;
        intf_rxdeskew.analog_settle_time_done         = mbtrain_if.analog_settle_time_done;
        intf_datatraincenter2.timeout_8ms_occured     = mbtrain_if.timeout_8ms_occured    ;
        intf_datatraincenter2.analog_settle_time_done = mbtrain_if.analog_settle_time_done;
        intf_linkspeed.timeout_8ms_occured            = mbtrain_if.timeout_8ms_occured    ;
        intf_linkspeed.analog_settle_time_done        = mbtrain_if.analog_settle_time_done;
        intf_repair.timeout_8ms_occured               = mbtrain_if.timeout_8ms_occured    ;
        intf_repair.analog_settle_time_done           = mbtrain_if.analog_settle_time_done;

        // SB RX Broadcast
        intf_valvref.rx_sb_msg_valid          = mbtrain_if.rx_sb_msg_valid;
        intf_valvref.rx_sb_msg                = mbtrain_if.rx_sb_msg      ;
        intf_valvref.rx_msginfo               = mbtrain_if.rx_msginfo     ;
        intf_valvref.rx_data_field            = mbtrain_if.rx_data_field  ;
        // ... (repeated for all 13 substates)
        intf_datavref.rx_sb_msg_valid         = mbtrain_if.rx_sb_msg_valid;
        intf_datavref.rx_sb_msg               = mbtrain_if.rx_sb_msg      ;
        intf_datavref.rx_msginfo              = mbtrain_if.rx_msginfo     ;
        intf_datavref.rx_data_field           = mbtrain_if.rx_data_field  ;
        intf_speedidle.rx_sb_msg_valid        = mbtrain_if.rx_sb_msg_valid;
        intf_speedidle.rx_sb_msg              = mbtrain_if.rx_sb_msg      ;
        intf_speedidle.rx_msginfo             = mbtrain_if.rx_msginfo     ;
        intf_speedidle.rx_data_field          = mbtrain_if.rx_data_field  ;
        intf_txselfcal.rx_sb_msg_valid        = mbtrain_if.rx_sb_msg_valid;
        intf_txselfcal.rx_sb_msg              = mbtrain_if.rx_sb_msg      ;
        intf_txselfcal.rx_msginfo             = mbtrain_if.rx_msginfo     ;
        intf_txselfcal.rx_data_field          = mbtrain_if.rx_data_field  ;
        intf_rxclkcal.rx_sb_msg_valid         = mbtrain_if.rx_sb_msg_valid;
        intf_rxclkcal.rx_sb_msg               = mbtrain_if.rx_sb_msg      ;
        intf_rxclkcal.rx_msginfo              = mbtrain_if.rx_msginfo     ;
        intf_rxclkcal.rx_data_field           = mbtrain_if.rx_data_field  ;
        intf_valtraincenter.rx_sb_msg_valid   = mbtrain_if.rx_sb_msg_valid;
        intf_valtraincenter.rx_sb_msg         = mbtrain_if.rx_sb_msg      ;
        intf_valtraincenter.rx_msginfo        = mbtrain_if.rx_msginfo     ;
        intf_valtraincenter.rx_data_field     = mbtrain_if.rx_data_field  ;
        intf_valtrainvref.rx_sb_msg_valid     = mbtrain_if.rx_sb_msg_valid;
        intf_valtrainvref.rx_sb_msg           = mbtrain_if.rx_sb_msg      ;
        intf_valtrainvref.rx_msginfo          = mbtrain_if.rx_msginfo     ;
        intf_valtrainvref.rx_data_field       = mbtrain_if.rx_data_field  ;
        intf_datatraincenter1.rx_sb_msg_valid = mbtrain_if.rx_sb_msg_valid;
        intf_datatraincenter1.rx_sb_msg       = mbtrain_if.rx_sb_msg      ;
        intf_datatraincenter1.rx_msginfo      = mbtrain_if.rx_msginfo     ;
        intf_datatraincenter1.rx_data_field   = mbtrain_if.rx_data_field  ;
        intf_datatrainvref.rx_sb_msg_valid    = mbtrain_if.rx_sb_msg_valid;
        intf_datatrainvref.rx_sb_msg          = mbtrain_if.rx_sb_msg      ;
        intf_datatrainvref.rx_msginfo         = mbtrain_if.rx_msginfo     ;
        intf_datatrainvref.rx_data_field      = mbtrain_if.rx_data_field  ;
        intf_rxdeskew.rx_sb_msg_valid         = mbtrain_if.rx_sb_msg_valid;
        intf_rxdeskew.rx_sb_msg               = mbtrain_if.rx_sb_msg      ;
        intf_rxdeskew.rx_msginfo              = mbtrain_if.rx_msginfo     ;
        intf_rxdeskew.rx_data_field           = mbtrain_if.rx_data_field  ;
        intf_datatraincenter2.rx_sb_msg_valid = mbtrain_if.rx_sb_msg_valid;
        intf_datatraincenter2.rx_sb_msg       = mbtrain_if.rx_sb_msg      ;
        intf_datatraincenter2.rx_msginfo      = mbtrain_if.rx_msginfo     ;
        intf_datatraincenter2.rx_data_field   = mbtrain_if.rx_data_field  ;
        intf_linkspeed.rx_sb_msg_valid        = mbtrain_if.rx_sb_msg_valid;
        intf_linkspeed.rx_sb_msg              = mbtrain_if.rx_sb_msg      ;
        intf_linkspeed.rx_msginfo             = mbtrain_if.rx_msginfo     ;
        intf_linkspeed.rx_data_field          = mbtrain_if.rx_data_field  ;
        intf_repair.rx_sb_msg_valid           = mbtrain_if.rx_sb_msg_valid;
        intf_repair.rx_sb_msg                 = mbtrain_if.rx_sb_msg      ;
        intf_repair.rx_msginfo                = mbtrain_if.rx_msginfo     ;
        intf_repair.rx_data_field             = mbtrain_if.rx_data_field  ;

        // MB RX Broadcast
        intf_datavref.mb_rx_data_lane_mask         = mbtrain_if.mb_rx_data_lane_mask;
        intf_datatraincenter1.mb_rx_data_lane_mask = mbtrain_if.mb_rx_data_lane_mask;
        intf_datatrainvref.mb_rx_data_lane_mask    = mbtrain_if.mb_rx_data_lane_mask;
        intf_rxdeskew.mb_rx_data_lane_mask         = mbtrain_if.mb_rx_data_lane_mask;
        intf_datatraincenter2.mb_rx_data_lane_mask = mbtrain_if.mb_rx_data_lane_mask;
        intf_linkspeed.mb_rx_data_lane_mask        = mbtrain_if.mb_rx_data_lane_mask;
        intf_repair.mbinit_rx_data_lane_mask       = mbtrain_if.mbinit_rx_data_lane_mask;
        intf_repair.mbinit_tx_data_lane_mask       = mbtrain_if.mbinit_tx_data_lane_mask;

        // REPAIR needs special width inputs
        intf_repair.rf_cap_SPMW               = mbtrain_if.rf_cap_SPMW;
        intf_repair.rf_ctrl_target_link_width = mbtrain_if.rf_ctrl_target_link_width;
        intf_repair.param_UCIe_S_x8           = mbtrain_if.param_UCIe_S_x8;

        // LINKSPEED also needs RF capability signals (Bug 9 fix)
        intf_linkspeed.rf_cap_SPMW               = mbtrain_if.rf_cap_SPMW;
        intf_linkspeed.rf_ctrl_target_link_width = mbtrain_if.rf_ctrl_target_link_width;

        // Cross-substate Flags
        intf_valtrainvref.valtraincenter_fail_flag  = intf_valtraincenter.valtraincenter_fail_flag;
        intf_datatrainvref.valtraincenter_fail_flag = intf_valtraincenter.valtraincenter_fail_flag;
        intf_rxdeskew.valtraincenter_fail_flag      = intf_valtraincenter.valtraincenter_fail_flag;

        intf_repair.linkspeed_success_lanes = intf_linkspeed.linkspeed_success_lanes;
        intf_repair.update_lane_mask        = intf_valvref.update_lane_mask         ;

        intf_rxclkcal.phy_negotiated_speed  = intf_speedidle.phy_negotiated_speed;
        intf_rxdeskew.phy_negotiated_speed  = intf_speedidle.phy_negotiated_speed;
        intf_linkspeed.phy_negotiated_speed = intf_speedidle.phy_negotiated_speed;

        // RXDESKEW needs top-level LTSM state for RESET detection (Bug 8 fix)
        intf_rxdeskew.current_ltsm_state = mbtrain_if.current_ltsm_state;

        // From MBINIT: max negotiated speed read by SPEEDIDLE
        intf_speedidle.param_negotiated_max_speed = mbtrain_if.param_negotiated_max_speed;

        intf_speedidle.state_n                    = mbtrain_if.state_n;
    end

    // =========================================================================
    // 6. Sub-state Output MUX (13-to-1) to Global MUX
    // =========================================================================

    reg is_first_vref_source_ok         ;
    reg is_first_datavref_source_ok     ;
    reg is_first_data_pi_phase_source_ok;
    always @(posedge mbtrain_if.lclk or negedge mbtrain_if.rst_n) begin
        if (!mbtrain_if.rst_n) begin
            is_first_vref_source_ok          <= 1'b1;
            is_first_datavref_source_ok      <= 1'b1;
            is_first_data_pi_phase_source_ok <= 1'b1;
        end
        else if (active_substate == ltsm_state_n_pkg::VALVREF) begin // Reset all flags.
            is_first_vref_source_ok          <= 1'b1;
            is_first_datavref_source_ok      <= 1'b1;
            is_first_data_pi_phase_source_ok <= 1'b1;
        end
        else if (active_substate == ltsm_state_n_pkg::DATATRAINVREF) begin
            is_first_datavref_source_ok <= 1'b0;
        end
        else if (active_substate == ltsm_state_n_pkg::VALTRAINVREF) begin
            is_first_vref_source_ok <= 1'b0;
        end
        else if (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) begin
            is_first_data_pi_phase_source_ok <= 1'b0;
        end
    end

    assign mbtrain_if.timeout_timer_en =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? intf_valvref.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? intf_datavref.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::SPEEDIDLE)        ? intf_speedidle.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::TXSELFCAL)        ? intf_txselfcal.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::RXSELFCAL)        ? intf_rxclkcal.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? intf_valtraincenter.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? intf_valtrainvref.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? intf_datatraincenter1.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? intf_datatrainvref.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? intf_rxdeskew.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? intf_datatraincenter2.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? intf_linkspeed.timeout_timer_en :
        (active_substate == ltsm_state_n_pkg::REPAIR)           ? intf_repair.timeout_timer_en : 1'b0;

    assign mbtrain_if.analog_settle_timer_en =
        (active_substate == ltsm_state_n_pkg::VALVREF)          ? intf_valvref.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::DATAVREF)         ? intf_datavref.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::SPEEDIDLE)        ? intf_speedidle.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::TXSELFCAL)        ? intf_txselfcal.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::RXSELFCAL)        ? intf_rxclkcal.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINCENTER)   ? intf_valtraincenter.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::VALTRAINVREF)     ? intf_valtrainvref.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER1) ? intf_datatraincenter1.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINVREF)    ? intf_datatrainvref.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::RXDESKEW)         ? intf_rxdeskew.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::DATATRAINCENTER2) ? intf_datatraincenter2.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::LINKSPEED)        ? intf_linkspeed.analog_settle_timer_en :
        (active_substate == ltsm_state_n_pkg::REPAIR)           ? intf_repair.analog_settle_timer_en : 1'b0;

    // 1. VALVREF & 7. VALTRAINVREF analog signals:
    assign mbtrain_if.phy_rx_valvref_ctrl  = (is_first_vref_source_ok) ? intf_valvref.phy_rx_valvref_ctrl : intf_valtrainvref.phy_rx_valvref_ctrl;

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : PHY_RX_DATAVREF_CTRL_GEN
            // 2. DATAVREF & 9. DATATRAINVREF analog signals:
            assign mbtrain_if.phy_rx_datavref_ctrl[lane]      = (is_first_datavref_source_ok)? intf_datavref.phy_rx_datavref_ctrl[lane] : intf_datatrainvref.phy_rx_datavref_ctrl[lane];

            // 8. DATATRAINCENTER1 & 12. DATATRAINCENTER2 analog signals:
            assign mbtrain_if.phy_tx_data_pi_phase_ctrl[lane] = (is_first_data_pi_phase_source_ok) ? intf_datatraincenter1.phy_tx_data_pi_phase_ctrl[lane] : intf_datatraincenter2.phy_tx_data_pi_phase_ctrl[lane];

            // 10. RXDESKEW analog signals:
            assign mbtrain_if.phy_rx_deskew_ctrl[lane]        = intf_rxdeskew.phy_rx_deskew_ctrl[lane];
        end
    endgenerate

    // 6. VALTRAINCENTER analog signals:
    assign mbtrain_if.phy_tx_val_pi_phase_ctrl          = intf_valtraincenter.phy_tx_val_pi_phase_ctrl;

    // 10. RXDESKEW analog signals:
    assign mbtrain_if.phy_tx_eq_preset_ctrl             = intf_rxdeskew.phy_tx_eq_preset_ctrl;



    // 4. TXSELFCAL analog signals:
    assign mbtrain_if.phy_tx_selfcal_en                 = intf_txselfcal.phy_tx_selfcal_en;

    // 5. RXCLKCAL analog signals:
    assign mbtrain_if.phy_rx_clock_lock_en              = intf_rxclkcal.phy_rx_clock_lock_en;
    assign mbtrain_if.phy_rx_track_lock_en              = intf_rxclkcal.phy_rx_track_lock_en;
    assign mbtrain_if.phy_rx_phase_detector_en          = intf_rxclkcal.phy_rx_phase_detector_en;
    assign mbtrain_if.phy_tx_tckn_shift_en              = intf_rxclkcal.phy_tx_tckn_shift_en;
    assign intf_rxclkcal.phy_rx_tckn_shift              = mbtrain_if.phy_rx_tckn_shift ;  // Be careful with this signal....
    assign intf_rxclkcal.phy_rx_decrement_shift         = mbtrain_if.phy_rx_decrement_shift;
    assign mbtrain_if.phy_tx_tckn_shift                 = intf_rxclkcal.phy_tx_tckn_shift;
    assign mbtrain_if.phy_tx_decrement_shift            = intf_rxclkcal.phy_tx_decrement_shift;
    assign intf_rxclkcal.phy_tx_tckn_shift_out_of_range = mbtrain_if.phy_tx_tckn_shift_out_of_range;

    // 3. SPEEDIDLE analog signals:
    assign mbtrain_if.phy_negotiated_speed              = intf_speedidle.phy_negotiated_speed;

    // REPAIR drives the active lane masks (updated once at start of MBTRAIN, stable thereafter)
    assign mbtrain_if.mb_rx_data_lane_mask = intf_repair.mb_rx_data_lane_mask;
    assign mbtrain_if.mb_tx_data_lane_mask = intf_repair.mb_tx_data_lane_mask;

    // RXCLKCAL drives the MB clock pattern signals (unique to clock calibration phase)
    assign mbtrain_if.mb_tx_pattern_en      = intf_rxclkcal.mb_tx_pattern_en;
    assign mbtrain_if.mb_tx_pattern_setup   = intf_rxclkcal.mb_tx_pattern_setup;
    assign mbtrain_if.mb_tx_clk_pattern_sel = intf_rxclkcal.mb_tx_clk_pattern_sel;

    // ======================================================================== //
    // PHY_IN_RETRAIN interface (spec 4.5.3.4.12)                               //
    // Sampled once at LINKSPEED_START_REQ; used in EVAL_RESULT to decide       //
    // whether to exit via phy_retrain path (if params changed during retrain). //
    // ======================================================================== //
    assign intf_linkspeed.phyretrain_PHY_IN_RETRAIN = mbtrain_if.phyretrain_PHY_IN_RETRAIN   ; // From PHYRETRAIN state: was PHY_IN_RETRAIN asserted?
    assign mbtrain_if.linkspeed_PHY_IN_RETRAIN      = intf_linkspeed.linkspeed_PHY_IN_RETRAIN; // Sampled copy held stable through the sub-state.
    assign intf_linkspeed.params_changed            = mbtrain_if.params_changed              ; // Were link parameters changed during PHYRETRAIN?
    // ======================================================================== //

    // MB/SB Signals MUX to Global MUX
    always_comb begin : MUX_TO_GLOBAL
        mbtrain_if.tx_sb_msg_valid = 1'b0;
        mbtrain_if.tx_sb_msg       = UCIe_pkg::NOTHING;
        mbtrain_if.tx_msginfo      = 16'h0;
        mbtrain_if.tx_data_field   = 64'h0;

        mbtrain_if.mb_tx_clk_lane_sel  = 2'b00;
        mbtrain_if.mb_tx_data_lane_sel = 2'b00;
        mbtrain_if.mb_tx_val_lane_sel  = 2'b00;
        mbtrain_if.mb_tx_trk_lane_sel  = 2'b00;
        mbtrain_if.mb_rx_clk_lane_sel  = 1'b0;
        mbtrain_if.mb_rx_data_lane_sel = 1'b0;
        mbtrain_if.mb_rx_val_lane_sel  = 1'b0;
        mbtrain_if.mb_rx_trk_lane_sel  = 1'b0;

        case (active_substate)
            ltsm_state_n_pkg::VALVREF: begin
                mbtrain_if.tx_sb_msg_valid     = intf_valvref.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_valvref.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_valvref.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_valvref.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_valvref.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_valvref.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_valvref.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_valvref.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_valvref.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_valvref.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_valvref.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_valvref.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::DATAVREF: begin
                mbtrain_if.tx_sb_msg_valid     = intf_datavref.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_datavref.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_datavref.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_datavref.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_datavref.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_datavref.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_datavref.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_datavref.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_datavref.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_datavref.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_datavref.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_datavref.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::SPEEDIDLE: begin
                mbtrain_if.tx_sb_msg_valid     = intf_speedidle.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_speedidle.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_speedidle.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_speedidle.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_speedidle.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_speedidle.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_speedidle.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_speedidle.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_speedidle.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_speedidle.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_speedidle.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_speedidle.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::TXSELFCAL: begin
                mbtrain_if.tx_sb_msg_valid = intf_txselfcal.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg       = intf_txselfcal.tx_sb_msg;
                mbtrain_if.tx_msginfo      = intf_txselfcal.tx_msginfo;
                mbtrain_if.tx_data_field   = intf_txselfcal.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel = intf_txselfcal.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_txselfcal.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel = intf_txselfcal.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel = intf_txselfcal.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel = intf_txselfcal.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_txselfcal.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel = intf_txselfcal.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel = intf_txselfcal.mb_rx_trk_lane_sel;
            end
            RXSELFCAL: begin
                mbtrain_if.tx_sb_msg_valid     = intf_rxclkcal.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_rxclkcal.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_rxclkcal.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_rxclkcal.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_rxclkcal.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_rxclkcal.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_rxclkcal.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_rxclkcal.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_rxclkcal.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_rxclkcal.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_rxclkcal.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_rxclkcal.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::VALTRAINCENTER: begin
                mbtrain_if.tx_sb_msg_valid     = intf_valtraincenter.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_valtraincenter.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_valtraincenter.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_valtraincenter.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_valtraincenter.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_valtraincenter.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_valtraincenter.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_valtraincenter.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_valtraincenter.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_valtraincenter.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_valtraincenter.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_valtraincenter.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::VALTRAINVREF: begin
                mbtrain_if.tx_sb_msg_valid     = intf_valtrainvref.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_valtrainvref.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_valtrainvref.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_valtrainvref.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_valtrainvref.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_valtrainvref.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_valtrainvref.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_valtrainvref.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_valtrainvref.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_valtrainvref.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_valtrainvref.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_valtrainvref.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::DATATRAINCENTER1: begin
                mbtrain_if.tx_sb_msg_valid     = intf_datatraincenter1.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_datatraincenter1.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_datatraincenter1.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_datatraincenter1.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_datatraincenter1.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_datatraincenter1.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_datatraincenter1.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_datatraincenter1.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_datatraincenter1.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_datatraincenter1.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_datatraincenter1.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_datatraincenter1.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::DATATRAINVREF: begin
                mbtrain_if.tx_sb_msg_valid     = intf_datatrainvref.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_datatrainvref.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_datatrainvref.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_datatrainvref.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_datatrainvref.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_datatrainvref.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_datatrainvref.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_datatrainvref.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_datatrainvref.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_datatrainvref.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_datatrainvref.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_datatrainvref.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::RXDESKEW: begin
                mbtrain_if.tx_sb_msg_valid     = intf_rxdeskew.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_rxdeskew.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_rxdeskew.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_rxdeskew.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_rxdeskew.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_rxdeskew.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_rxdeskew.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_rxdeskew.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_rxdeskew.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_rxdeskew.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_rxdeskew.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_rxdeskew.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::DATATRAINCENTER2: begin
                mbtrain_if.tx_sb_msg_valid     = intf_datatraincenter2.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_datatraincenter2.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_datatraincenter2.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_datatraincenter2.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_datatraincenter2.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_datatraincenter2.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_datatraincenter2.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_datatraincenter2.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_datatraincenter2.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_datatraincenter2.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_datatraincenter2.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_datatraincenter2.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::LINKSPEED: begin
                mbtrain_if.tx_sb_msg_valid     = intf_linkspeed.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_linkspeed.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_linkspeed.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_linkspeed.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_linkspeed.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_linkspeed.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_linkspeed.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_linkspeed.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_linkspeed.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_linkspeed.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_linkspeed.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_linkspeed.mb_rx_trk_lane_sel;
            end
            ltsm_state_n_pkg::REPAIR: begin
                mbtrain_if.tx_sb_msg_valid     = intf_repair.tx_sb_msg_valid;
                mbtrain_if.tx_sb_msg           = intf_repair.tx_sb_msg;
                mbtrain_if.tx_msginfo          = intf_repair.tx_msginfo;
                mbtrain_if.tx_data_field       = intf_repair.tx_data_field;
                mbtrain_if.mb_tx_clk_lane_sel  = intf_repair.mb_tx_clk_lane_sel;
                mbtrain_if.mb_tx_data_lane_sel = intf_repair.mb_tx_data_lane_sel;
                mbtrain_if.mb_tx_val_lane_sel  = intf_repair.mb_tx_val_lane_sel;
                mbtrain_if.mb_tx_trk_lane_sel  = intf_repair.mb_tx_trk_lane_sel;
                mbtrain_if.mb_rx_clk_lane_sel  = intf_repair.mb_rx_clk_lane_sel;
                mbtrain_if.mb_rx_data_lane_sel = intf_repair.mb_rx_data_lane_sel;
                mbtrain_if.mb_rx_val_lane_sel  = intf_repair.mb_rx_val_lane_sel;
                mbtrain_if.mb_rx_trk_lane_sel  = intf_repair.mb_rx_trk_lane_sel;
            end
            default: ;
        endcase
    end

endmodule
