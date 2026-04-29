import UCIe_pkg::*;

module MBINIT_WRAPPER
#(parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // From / To LTSM
    // =========================================================================
    input  logic mbinit_enable,
    output logic mbinit_done,
    output logic mbinit_error,

    // =========================================================================
    // Capability interface (driven by MBINIT_PARAM, consumed by others)
    // =========================================================================
    ucie_mb_cap_if cap_if,

    // =========================================================================
    // D2C point-test interface (for MBINIT_REPAIRMB)
    // =========================================================================
    internal_ltsm_if d2c_test_if,

    // =========================================================================
    // RX / TX mainband message bus
    // =========================================================================
    input  logic        mb_rx_valid,
    input  msg_no_e     mb_rx_msg_id,
    input  logic [15:0] mb_rx_MsgInfo,
    input  logic [63:0] mb_rx_data_Field,

    output logic        mb_tx_valid,
    output msg_no_e     mb_tx_msg_id,
    output logic [15:0] mb_tx_MsgInfo,
    output logic [63:0] mb_tx_data_Field,

    // =========================================================================
    // PHY control bus (muxed from active submodule)
    // =========================================================================
    output logic mb_tx_valid_status,
    output logic mb_tx_track_status,
    output logic mb_tx_clk_status,
    output logic mb_tx_data_status,

    output logic mb_rx_valid_status,
    output logic mb_rx_track_status,
    output logic mb_rx_clk_status,
    output logic mb_rx_data_status,

    // =========================================================================
    // REPAIRCLK pattern / compare
    // =========================================================================
    output logic [2:0] repairclk_tx_pattern_setup,
    output logic [1:0] repairclk_tx_clk_pattern_sel,
    output logic [1:0] repairclk_rx_compare_setup,
    output logic       repairclk_tx_pattern_en,
    output logic       repairclk_rx_compare_en,
    input  logic       repairclk_rtrk_pass,
    input  logic       repairclk_rckn_pass,
    input  logic       repairclk_rckp_pass,
    input  logic       repairclk_rx_compare_done,

    // =========================================================================
    // REVERSALMB pattern / compare
    // =========================================================================
    output logic [2:0] reversalmb_tx_pattern_setup,
    output logic [1:0] reversalmb_tx_data_pattern_sel,
    output logic [1:0] reversalmb_rx_compare_setup,
    output logic       reversalmb_tx_pattern_en,
    output logic       reversalmb_rx_compare_en,
    input  logic [15:0] reversalmb_rx_perlane_err,
    input  logic        reversalmb_rx_compare_done,
    output logic        mb_lane_reversal_req,
    output logic        mb_x8_mode_req,
    output logic        clear_error_req,

    // =========================================================================
    // REPAIRVAL pattern / compare
    // =========================================================================
    output logic [2:0] repairval_tx_pattern_setup,
    output logic       repairval_tx_val_pattern_sel,
    output logic [1:0] repairval_rx_compare_setup,
    output logic       repairval_tx_pattern_en,
    output logic       repairval_rx_compare_en,
    input  logic       repairval_RVLD_L_pass,
    input  logic       repairval_rx_compare_done,

    // =========================================================================
    // Aggregated timeout error
    // =========================================================================
    output logic timeout_error
);

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    logic param_enable,      param_done,      param_error,      param_timeout;
    logic repairclk_enable,  repairclk_done,  repairclk_error,  repairclk_timeout;
    logic reversalmb_enable, reversalmb_done, reversalmb_error, reversalmb_timeout;
    logic repairmb_enable,   repairmb_done,   repairmb_error,   repairmb_timeout;
    logic repairval_enable,  repairval_done,  repairval_error,  repairval_timeout;
    logic cal_enable,        cal_done,        cal_error,        cal_timeout;

    // TX Buses
    logic        param_tx_valid;      msg_no_e param_tx_msg_id;      logic [15:0] param_tx_MsgInfo;      logic [63:0] param_tx_data_Field;
    logic        repairclk_tx_valid;  msg_no_e repairclk_tx_msg_id;  logic [15:0] repairclk_tx_MsgInfo;  logic [63:0] repairclk_tx_data_Field;
    logic        reversalmb_tx_valid; msg_no_e reversalmb_tx_msg_id; logic [15:0] reversalmb_tx_MsgInfo; logic [63:0] reversalmb_tx_data_Field;
    logic        repairmb_tx_valid;   msg_no_e repairmb_tx_msg_id;   logic [15:0] repairmb_tx_MsgInfo;   logic [63:0] repairmb_tx_data_Field;
    logic        repairval_tx_valid;  msg_no_e repairval_tx_msg_id;  logic [15:0] repairval_tx_MsgInfo;  logic [63:0] repairval_tx_data_Field;
    logic        cal_tx_valid;        msg_no_e cal_tx_msg_id;        logic [15:0] cal_tx_MsgInfo;        logic [63:0] cal_tx_data_Field;

    // PHY Status Buses
    logic param_tx_valid_s, param_tx_track_s, param_tx_clk_s, param_tx_data_s;
    logic param_rx_valid_s, param_rx_track_s, param_rx_clk_s, param_rx_data_s;
    
    logic rev_tx_valid_s, rev_tx_track_s, rev_tx_clk_s, rev_tx_data_s;
    logic rev_rx_valid_s, rev_rx_track_s, rev_rx_clk_s, rev_rx_data_s;

    logic rmb_tx_valid_s, rmb_tx_track_s, rmb_tx_clk_s, rmb_tx_data_s;
    logic rmb_rx_valid_s, rmb_rx_track_s, rmb_rx_clk_s, rmb_rx_data_s;

    // =========================================================================
    // CONTROLLER INSTANTIATION
    // =========================================================================
    MBINIT_CONTROLLER u_controller (
        .clk(clk),
        .rst_n(rst_n),

        // LTSM Interface
        .mbinit_enable(mbinit_enable),
        .mbinit_done(mbinit_done),
        .mbinit_error(mbinit_error),
        .timeout_error(timeout_error),

        // Mainband Muxed Outputs
        .mb_tx_valid(mb_tx_valid),
        .mb_tx_msg_id(mb_tx_msg_id),
        .mb_tx_MsgInfo(mb_tx_MsgInfo),
        .mb_tx_data_Field(mb_tx_data_Field),

        // PHY Status Muxed Outputs
        .mb_tx_valid_status(mb_tx_valid_status),
        .mb_tx_track_status(mb_tx_track_status),
        .mb_tx_clk_status(mb_tx_clk_status),
        .mb_tx_data_status(mb_tx_data_status),
        .mb_rx_valid_status(mb_rx_valid_status),
        .mb_rx_track_status(mb_rx_track_status),
        .mb_rx_clk_status(mb_rx_clk_status),
        .mb_rx_data_status(mb_rx_data_status),

        // PARAM
        .param_enable(param_enable),
        .param_done(param_done),
        .param_error(param_error),
        .param_timeout(param_timeout),
        .param_tx_valid(param_tx_valid),
        .param_tx_msg_id(param_tx_msg_id),
        .param_tx_MsgInfo(param_tx_MsgInfo),
        .param_tx_data_Field(param_tx_data_Field),
        .param_tx_valid_s(param_tx_valid_s), .param_tx_track_s(param_tx_track_s), .param_tx_clk_s(param_tx_clk_s), .param_tx_data_s(param_tx_data_s),
        .param_rx_valid_s(param_rx_valid_s), .param_rx_track_s(param_rx_track_s), .param_rx_clk_s(param_rx_clk_s), .param_rx_data_s(param_rx_data_s),

        // CAL
        .cal_enable(cal_enable),
        .cal_done(cal_done),
        .cal_error(cal_error),
        .cal_timeout(cal_timeout),
        .cal_tx_valid(cal_tx_valid),
        .cal_tx_msg_id(cal_tx_msg_id),
        .cal_tx_MsgInfo(cal_tx_MsgInfo),
        .cal_tx_data_Field(cal_tx_data_Field),

        // REPAIRCLK
        .repairclk_enable(repairclk_enable),
        .repairclk_done(repairclk_done),
        .repairclk_error(repairclk_error),
        .repairclk_timeout(repairclk_timeout),
        .repairclk_tx_valid(repairclk_tx_valid),
        .repairclk_tx_msg_id(repairclk_tx_msg_id),
        .repairclk_tx_MsgInfo(repairclk_tx_MsgInfo),
        .repairclk_tx_data_Field(repairclk_tx_data_Field),

        // REPAIRVAL
        .repairval_enable(repairval_enable),
        .repairval_done(repairval_done),
        .repairval_error(repairval_error),
        .repairval_timeout(repairval_timeout),
        .repairval_tx_valid(repairval_tx_valid),
        .repairval_tx_msg_id(repairval_tx_msg_id),
        .repairval_tx_MsgInfo(repairval_tx_MsgInfo),
        .repairval_tx_data_Field(repairval_tx_data_Field),

        // REVERSALMB
        .reversalmb_enable(reversalmb_enable),
        .reversalmb_done(reversalmb_done),
        .reversalmb_error(reversalmb_error),
        .reversalmb_timeout(reversalmb_timeout),
        .reversalmb_tx_valid(reversalmb_tx_valid),
        .reversalmb_tx_msg_id(reversalmb_tx_msg_id),
        .reversalmb_tx_MsgInfo(reversalmb_tx_MsgInfo),
        .reversalmb_tx_data_Field(reversalmb_tx_data_Field),
        .rev_tx_valid_s(rev_tx_valid_s), .rev_tx_track_s(rev_tx_track_s), .rev_tx_clk_s(rev_tx_clk_s), .rev_tx_data_s(rev_tx_data_s),
        .rev_rx_valid_s(rev_rx_valid_s), .rev_rx_track_s(rev_rx_track_s), .rev_rx_clk_s(rev_rx_clk_s), .rev_rx_data_s(rev_rx_data_s),

        // REPAIRMB
        .repairmb_enable(repairmb_enable),
        .repairmb_done(repairmb_done),
        .repairmb_error(repairmb_error),
        .repairmb_timeout(repairmb_timeout),
        .repairmb_tx_valid(repairmb_tx_valid),
        .repairmb_tx_msg_id(repairmb_tx_msg_id),
        .repairmb_tx_MsgInfo(repairmb_tx_MsgInfo),
        .repairmb_tx_data_Field(repairmb_tx_data_Field),
        .rmb_tx_valid_s(rmb_tx_valid_s), .rmb_tx_track_s(rmb_tx_track_s), .rmb_tx_clk_s(rmb_tx_clk_s), .rmb_tx_data_s(rmb_tx_data_s),
        .rmb_rx_valid_s(rmb_rx_valid_s), .rmb_rx_track_s(rmb_rx_track_s), .rmb_rx_clk_s(rmb_rx_clk_s), .rmb_rx_data_s(rmb_rx_data_s)
    );

    // =========================================================================
    // SUBMODULE INSTANTIATIONS
    // =========================================================================

    // S1: PARAM
    MBINIT_PARAM #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_param (
        .clk(clk),
        .rst_n(rst_n),
        .mb_param_enable(param_enable),
        .cap_if(cap_if),
        .mb_param_done(param_done),
        .mb_param_error(param_error),
        .mb_tx_valid_status(param_tx_valid_s),
        .mb_tx_track_status(param_tx_track_s),
        .mb_tx_clk_status(param_tx_clk_s),
        .mb_tx_data_status(param_tx_data_s),
        .mb_rx_valid_status(param_rx_valid_s),
        .mb_rx_track_status(param_rx_track_s),
        .mb_rx_clk_status(param_rx_clk_s),
        .mb_rx_data_status(param_rx_data_s),
        .mb_param_rx_valid(mb_rx_valid),
        .mb_param_rx_msg_id(mb_rx_msg_id),
        .mb_param_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_param_rx_data_Field(mb_rx_data_Field),
        .mb_param_tx_valid(param_tx_valid),
        .mb_param_tx_msg_id(param_tx_msg_id),
        .mb_param_tx_MsgInfo(param_tx_MsgInfo),
        .mb_param_tx_data_Field(param_tx_data_Field),
        .timeout_error(param_timeout)
    );

    // S2: CAL
    MBINIT_CAL #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_cal (
        .clk(clk),
        .rst_n(rst_n),
        .mb_cal_enable(cal_enable),
        .mb_cal_done(cal_done),
        .mb_cal_error(cal_error),
        .mb_cal_rx_valid(mb_rx_valid),
        .mb_cal_rx_msg_id(mb_rx_msg_id),
        .mb_cal_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_cal_rx_data_Field(mb_rx_data_Field),
        .mb_cal_tx_valid(cal_tx_valid),
        .mb_cal_tx_msg_id(cal_tx_msg_id),
        .mb_cal_tx_MsgInfo(cal_tx_MsgInfo),
        .mb_cal_tx_data_Field(cal_tx_data_Field),
        .timeout_error(cal_timeout)
    );

    // S3: REPAIRCLK
    MBINIT_REPAIRCLK #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairclk (
        .clk(clk),
        .rst_n(rst_n),
        .mb_repairclk_enable(repairclk_enable),
        .mb_repairclk_done(repairclk_done),
        .mb_repairclk_error(repairclk_error),
        .mb_repairclk_rx_valid(mb_rx_valid),
        .mb_repairclk_rx_msg_id(mb_rx_msg_id),
        .mb_repairclk_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_repairclk_rx_data_Field(mb_rx_data_Field),
        .mb_repairclk_tx_valid(repairclk_tx_valid),
        .mb_repairclk_tx_msg_id(repairclk_tx_msg_id),
        .mb_repairclk_tx_MsgInfo(repairclk_tx_MsgInfo),
        .mb_repairclk_tx_data_Field(repairclk_tx_data_Field),
        .timeout_error(repairclk_timeout),
        .mb_tx_pattern_setup(repairclk_tx_pattern_setup),
        .mb_tx_clk_pattern_sel(repairclk_tx_clk_pattern_sel),
        .mb_rx_compare_setup(repairclk_rx_compare_setup),
        .mb_tx_pattern_en(repairclk_tx_pattern_en),
        .mb_rx_compare_en(repairclk_rx_compare_en),
        .rtrk_pass(repairclk_rtrk_pass),
        .rckn_pass(repairclk_rckn_pass),
        .rckp_pass(repairclk_rckp_pass),
        .mb_rx_compare_done(repairclk_rx_compare_done)
    );

    // S4: REPAIRVAL
    MBINIT_REPAIRVAL #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairval (
        .clk(clk),
        .rst_n(rst_n),
        .mb_repairval_enable(repairval_enable),
        .mb_repairval_done(repairval_done),
        .mb_repairval_error(repairval_error),
        .mb_repairval_rx_valid(mb_rx_valid),
        .mb_repairval_rx_msg_id(mb_rx_msg_id),
        .mb_repairval_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_repairval_rx_data_Field(mb_rx_data_Field),
        .mb_repairval_tx_valid(repairval_tx_valid),
        .mb_repairval_tx_msg_id(repairval_tx_msg_id),
        .mb_repairval_tx_MsgInfo(repairval_tx_MsgInfo),
        .mb_repairval_tx_data_Field(repairval_tx_data_Field),
        .timeout_error(repairval_timeout),
        .mb_tx_pattern_setup(repairval_tx_pattern_setup),
        .mb_tx_val_pattern_sel(repairval_tx_val_pattern_sel),
        .mb_rx_compare_setup(repairval_rx_compare_setup),
        .mb_tx_pattern_en(repairval_tx_pattern_en),
        .mb_rx_compare_en(repairval_rx_compare_en),
        .RVLD_L_pass(repairval_RVLD_L_pass),
        .mb_rx_compare_done(repairval_rx_compare_done)
    );

    // S5: REVERSALMB
    MBINIT_REVERSALMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_reversalmb (
        .cap_if(cap_if),
        .clk(clk),
        .rst_n(rst_n),
        .mb_reversal_enable(reversalmb_enable),
        .mb_reversal_done(reversalmb_done),
        .mb_reversal_error(reversalmb_error),
        .mb_reversal_rx_valid(mb_rx_valid),
        .mb_reversal_rx_msg_id(mb_rx_msg_id),
        .mb_reversal_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_reversal_rx_data_Field(mb_rx_data_Field),
        .mb_reversal_tx_valid(reversalmb_tx_valid),
        .mb_reversal_tx_msg_id(reversalmb_tx_msg_id),
        .mb_reversal_tx_MsgInfo(reversalmb_tx_MsgInfo),
        .mb_reversal_tx_data_Field(reversalmb_tx_data_Field),
        .timeout_error(reversalmb_timeout),
        .mb_tx_pattern_setup(reversalmb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(reversalmb_tx_data_pattern_sel),
        .mb_rx_compare_setup(reversalmb_rx_compare_setup),
        .mb_tx_pattern_en(reversalmb_tx_pattern_en),
        .mb_rx_compare_en(reversalmb_rx_compare_en),
        .mb_rx_perlane_err(reversalmb_rx_perlane_err),
        .mb_rx_compare_done(reversalmb_rx_compare_done),
        .mb_lane_reversal_req(mb_lane_reversal_req),
        .mb_x8_mode_req(mb_x8_mode_req),
        .clear_error_req(clear_error_req),
        .mb_tx_valid_status(rev_tx_valid_s),
        .mb_tx_track_status(rev_tx_track_s),
        .mb_tx_clk_status(rev_tx_clk_s),
        .mb_tx_data_status(rev_tx_data_s),
        .mb_rx_valid_status(rev_rx_valid_s),
        .mb_rx_track_status(rev_rx_track_s),
        .mb_rx_clk_status(rev_rx_clk_s),
        .mb_rx_data_status(rev_rx_data_s)
    );

    // S6: REPAIRMB
    MBINIT_REPAIRMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairmb (
        .clk(clk),
        .rst_n(rst_n),
        .cap_if(cap_if),
        .d2c_test_if(d2c_test_if),
        .mb_repairmb_enable(repairmb_enable),
        .mb_repairmb_done(repairmb_done),
        .mb_repairmb_error(repairmb_error),
        .mb_repairmb_rx_valid(mb_rx_valid),
        .mb_repairmb_rx_msg_id(mb_rx_msg_id),
        .mb_repairmb_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_repairmb_rx_data_Field(mb_rx_data_Field),
        .mb_repairmb_tx_valid(repairmb_tx_valid),
        .mb_repairmb_tx_msg_id(repairmb_tx_msg_id),
        .mb_repairmb_tx_MsgInfo(repairmb_tx_MsgInfo),
        .mb_repairmb_tx_data_Field(repairmb_tx_data_Field),
        .timeout_error(repairmb_timeout),
        .mb_tx_valid_status(rmb_tx_valid_s),
        .mb_tx_track_status(rmb_tx_track_s),
        .mb_tx_clk_status(rmb_tx_clk_s),
        .mb_tx_data_status(rmb_tx_data_s),
        .mb_rx_valid_status(rmb_rx_valid_s),
        .mb_rx_track_status(rmb_rx_track_s),
        .mb_rx_clk_status(rmb_rx_clk_s),
        .mb_rx_data_status(rmb_rx_data_s)
    );

endmodule
