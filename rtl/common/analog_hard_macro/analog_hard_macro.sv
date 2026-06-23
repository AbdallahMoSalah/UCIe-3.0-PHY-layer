`timescale 1ns/1ps
// =============================================================================
// Module  : analog_hard_macro
// Project : UCIe 3.0 Physical Layer
//
// Purpose : The combined PHY analog hard macro. Bundles the two band-specific
//           analog macros into one physical block:
//             * sideband_analog_hard_macro  - SB PLL + ClkDiv + ser/des
//             * mainband_analog_hard_macro  - MB PLL + clocking + ser/des + tri-state
//
//           Everything digital (link controller, RDI, LTSM, mapper/lfsr/demapper,
//           comparators, clk-pattern-gen, ...) stays OUTSIDE and connects through
//           the parallel/control ports below. This is purely structural: it wires
//           the two sub-macros straight out to the top-level ports.
//  Simulation only.
// =============================================================================

module analog_hard_macro #(
    parameter int  DATA_WIDTH    = 32,                 // MB parallel lane-word width
    parameter int  NUM_LANES     = 16,                 // MB number of data lanes
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN = 32'h0F0F0F0F
)(
    //===========================================================================================
    // Sideband
    //===========================================================================================
    input  logic                    rst_sb_n,          // SB active-low reset
    output logic                    clk_sb,            // SB parallel clock (sb_pll / 8)

    input  logic                    pattern_mode,      // SB serializer pattern mode
    input  logic                    pmo_en,            // SB pattern-mode-output enable

    output logic [63:0]             des_data_rcvd,     // SB deserialized parallel data
    output logic                    des_vld_rcvd,      // SB deserialized data valid

    input  logic [63:0]             ser_data_send,     // SB parallel data to transmit
    input  logic                    ser_vld_send,      // SB transmit data valid
    output logic                    ser_rdy,           // SB serializer ready

    input  logic                    RXDATASB,          // SB serial data in
    output logic                    TXDATASB,          // SB serial data out
    input  logic                    RXCKSB,            // SB serial clock in
    output logic                    TXCKSB,            // SB serial clock out

    //===========================================================================================
    // Mainband - clocks / reset
    //===========================================================================================
    input  logic                    i_rst_n,               // MB active-low reset
    input  logic [2:0]              i_pll_speed_sel,       // 000=2G .. 11=16G
    input  logic                    lclk_g,                // debug clock-gate enable
    output logic                    lclk,                  // RDI LCLK (pll/16)
    output logic                    gated_lclk,            // gated lclk for MB TX
    output logic                    pll_clk,               // gated high-speed PLL clock
    output real                     pll_period,            // PLL period (ps) - debug / RX timing

    //------------------------------------------------------------------------- MB TX parallel in
    input  logic                    lfsr_ser_en,           // data-lane serializer enable
    input  logic [DATA_WIDTH-1:0]   lfsr_lane [0:NUM_LANES-1], // per-lane words to serialize
    input  logic                    valid_ser_en,          // valid-lane serializer enable
    input  logic [DATA_WIDTH-1:0]   valid_word,            // 32-bit TVLD pattern word

    //------------------------------------------------------------ MB clock-pattern pre-tri-state
    input  logic                    i_tckp_p_pre,          // differential clock +  pre tri-state
    input  logic                    i_tckn_p_pre,          // differential clock -  pre tri-state
    input  logic                    i_ttrk_p_pre,          // clock tracking        pre tri-state

    //--------------------------------------------------------------- MB TX tri-state per-group sel
    input  logic [1:0]              i_mb_tx_data_lane_sel, // data-lane tri-state enable
    input  logic [1:0]              i_mb_tx_val_lane_sel,  // valid-lane tri-state enable
    input  logic [1:0]              i_mb_tx_clk_lane_sel,  // clk_p/clk_n tri-state enable
    input  logic [1:0]              i_mb_tx_trk_lane_sel,  // track-lane tri-state enable

    //--------------------------------------------------------------------- MB TX serial out (DDR)
    output logic [NUM_LANES-1:0]    o_TD_P,                // serialized data lanes 0-15
    output logic                    o_TVLD_P,              // serialized valid lane
    output logic                    o_TCKP_P,              // differential clock +
    output logic                    o_TCKN_P,              // differential clock -
    output logic                    o_TTRK_P,              // clock tracking

    //----------------------------------------------------------------------- MB RX clocks/control
    input  logic [NUM_LANES-1:0]    i_rx_data_deser_en,    // per-lane data deserializer enable
    input  logic                    i_rx_valid_deser_en,   // valid deserializer enable
    input  logic                    i_vcmp_enable,         // valid-comparator enable (gates deser)
    input  logic                    i_vcmp_done,           // valid-comparator done (from digital MB)

    //--------------------------------------------------------------- MB RX serial in (partner TX)
    input  logic [NUM_LANES-1:0]    i_RD_P,                // serialized data lanes
    input  logic                    i_RVLD_P,              // serialized valid lane
    input  logic                    i_RCKP_P,              // forwarded sampling clock +

    //--------------------------------------------------------------------- MB RX parallel out
    output logic [DATA_WIDTH-1:0]   o_par_data [0:NUM_LANES-1], // descrambled-pending lane words
    output logic                    o_data_valid,          // any-lane deserialized word valid
    output logic [DATA_WIDTH-1:0]   valid_frame_data,      // recovered valid-frame word
    output logic                    valid_frame_vld        // recovered valid-frame strobe
);

    //===========================================================================================
    // Sideband analog macro
    //===========================================================================================
    sideband_analog_hard_macro u_sideband (
        .rst_sb_n      (rst_sb_n),
        .clk_sb        (clk_sb),
        .pattern_mode  (pattern_mode),
        .pmo_en        (pmo_en),
        .des_data_rcvd (des_data_rcvd),
        .des_vld_rcvd  (des_vld_rcvd),
        .ser_data_send (ser_data_send),
        .ser_vld_send  (ser_vld_send),
        .ser_rdy       (ser_rdy),
        .RXDATASB      (RXDATASB),
        .TXDATASB      (TXDATASB),
        .RXCKSB        (RXCKSB),
        .TXCKSB        (TXCKSB)
    );

    //===========================================================================================
    // Mainband analog macro
    //===========================================================================================
    mainband_analog_hard_macro #(
        .DATA_WIDTH    (DATA_WIDTH),
        .NUM_LANES     (NUM_LANES),
        .VALID_PATTERN (VALID_PATTERN)
    ) u_mainband (
        .i_rst_n               (i_rst_n),
        .i_pll_speed_sel       (i_pll_speed_sel),
        .lclk_g                (lclk_g),
        .lclk                  (lclk),
        .gated_lclk            (gated_lclk),
        .pll_clk               (pll_clk),
        .pll_period            (pll_period),

        .lfsr_ser_en           (lfsr_ser_en),
        .lfsr_lane             (lfsr_lane),
        .valid_ser_en          (valid_ser_en),
        .valid_word            (valid_word),

        .i_tckp_p_pre          (i_tckp_p_pre),
        .i_tckn_p_pre          (i_tckn_p_pre),
        .i_ttrk_p_pre          (i_ttrk_p_pre),

        .i_mb_tx_data_lane_sel (i_mb_tx_data_lane_sel),
        .i_mb_tx_val_lane_sel  (i_mb_tx_val_lane_sel),
        .i_mb_tx_clk_lane_sel  (i_mb_tx_clk_lane_sel),
        .i_mb_tx_trk_lane_sel  (i_mb_tx_trk_lane_sel),

        .o_TD_P                (o_TD_P),
        .o_TVLD_P              (o_TVLD_P),
        .o_TCKP_P              (o_TCKP_P),
        .o_TCKN_P              (o_TCKN_P),
        .o_TTRK_P              (o_TTRK_P),

        .i_rx_data_deser_en    (i_rx_data_deser_en),
        .i_rx_valid_deser_en   (i_rx_valid_deser_en),
        .i_vcmp_enable         (i_vcmp_enable),
        .i_vcmp_done           (i_vcmp_done),

        .i_RD_P                (i_RD_P),
        .i_RVLD_P              (i_RVLD_P),
        .i_RCKP_P              (i_RCKP_P),

        .o_par_data            (o_par_data),
        .o_data_valid          (o_data_valid),
        .valid_frame_data      (valid_frame_data),
        .valid_frame_vld       (valid_frame_vld)
    );

endmodule
