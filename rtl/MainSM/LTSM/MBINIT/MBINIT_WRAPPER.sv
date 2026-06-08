import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

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
    output state_n_e mbinit_state_n,
    
    // FIFO handshake & SPMW Strap
    input  logic sb_ltsm_rdy,
    input  logic SPMW,

    // =========================================================================
    // Capability interface (Discrete Normal Ports)
    // =========================================================================
    // Local Inputs (from registers)
    input  logic        reg_phy_x8_mode_ctrl,
    input  logic [3:0]  local_max_speed,
    input  logic        local_sbfe,
    input  logic        reg_TARR_support_local_cap,
    input  logic        reg_L2SPD_support_local_cap,
    input  logic        reg_PSPT_support_local_cap,
    input  logic        local_so,
    input  logic        reg_PMO_support_local_cap,
    input  logic [2:0]  reg_Max_Link_Width_cap,
    input  logic [3:0]  reg_Max_Link_Speed_cap,
    input  logic        local_mtp,

    input  logic [4:0]  reg_Supported_TX_Vswing,
    input  logic        reg_so,
    input  logic        reg_mtp,
    input  logic [1:0]  reg_Module_ID,
    input  logic [1:0]  reg_Clock_Phase_cap,
    input  logic [1:0]  reg_Clock_mode_cap,
    input  logic        reg_TARR_support_local_ctrl,
    input  logic        reg_PMO_support_local_ctrl,
    input  logic        reg_Clock_Phase_ctrl,
    input  logic        reg_Clock_mode_ctrl,

    // From Link
    input  logic        reg_L2SPD_support_local_ctrl,
    input  logic        reg_PSPT_support_local_ctrl,
    input  logic [3:0]  reg_Target_Link_Width_ctrl,
    input  logic [3:0]  reg_Target_Link_Speed_ctrl,


    // -------------------------------
    // --------- STATUS REG ----------
    // -------------------------------
    // From Phy 
    output logic        reg_Clock_Phase_enable_status,
    output logic        reg_Clock_mode_enable_status,
    output logic        reg_TARR_enable_status,
    // From Link
    output logic [3:0]  reg_Link_Width_enable_status,
    output logic [3:0]  reg_Link_Speed_enable_status,
    output logic        reg_PMO_enable_status,
    output logic        reg_L2SPD_enable_status,
    output logic        reg_PSPT_enable_status,

    // =========================================================================
    // D2C point-test interface (for MBINIT_REPAIRMB)
    // =========================================================================
        // d2cptest interface
    output logic            local_tx_pt_en,
    output logic            partner_tx_pt_en,
    output logic [2:0]      d2c_pattern_setup,// 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    output logic [1:0]      d2c_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    output logic            d2c_pattern_mode,// 0: Continuous Pattern Mode, 1: Burst Pattern Mode. 
    output logic [1:0]      d2c_compare_setup, // 0: Per-Lane, 1: Aggregate,  2: Valid Lane, 3: Clock Lane Comparison.

    input logic [15:0] d2c_perlane_pass, // The Per-Lane Errors (Each bit represents one pass Data Lane).

    input logic local_test_d2c_done,
    input logic partner_test_d2c_done,


    // =========================================================================
    // RX / TX sideband message bus
    // =========================================================================
    input  logic        sb_rx_valid,
    input  msg_no_e     sb_rx_msg_id,
    input  logic [15:0] sb_rx_MsgInfo,
    input  logic [63:0] sb_rx_data_Field,

    output logic        sb_tx_valid,
    output msg_no_e     sb_tx_msg_id,
    output logic [15:0] sb_tx_MsgInfo,
    output logic [63:0] sb_tx_data_Field,

    // =========================================================================
    // Unified Mainband Outputs (Muxed / Latched)
    // =========================================================================
    output logic       mb_tx_pattern_en,
    output logic [2:0] mb_tx_pattern_setup,
    output logic [1:0] mb_tx_data_pattern_sel,
    output logic       mb_tx_val_pattern_sel,
    output logic       mb_rx_compare_en,
    output logic [1:0] mb_rx_compare_setup,
    output logic       clear_error_req,
    output logic [2:0] mbinit_rx_data_lane_mask,
    output logic [2:0] mbinit_tx_data_lane_mask,

    // =========================================================================
    // Unified Mainband Inputs
    // =========================================================================
    input  logic [15:0] mb_rx_perlane_pass,
    input  logic        mb_tx_pattern_count_done,

    // =========================================================================
    // Substate Discrete Outputs/Inputs
    // =========================================================================
    output logic        mb_lane_reversal_req,
    input  logic        repairclk_rtrk_pass,
    input  logic        repairclk_rckn_pass,
    input  logic        repairclk_rckp_pass,
    input  logic        repairval_RVLD_L_pass,

    // =========================================================================
    // External Watchdog Timer / Global Error Interface
    // =========================================================================
    input  logic global_error
);

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    logic param_enable,      param_done,      param_error;
    logic repairclk_enable,  repairclk_done,  repairclk_error;
    logic reversalmb_enable, reversalmb_done, reversalmb_error;
    logic repairmb_enable,   repairmb_done,   repairmb_error;
    logic repairval_enable,  repairval_done,  repairval_error;
    logic cal_enable,        cal_done,        cal_error;

    // TX Buses
    logic        param_tx_valid;      msg_no_e param_tx_msg_id;      logic [15:0] param_tx_MsgInfo;      logic [63:0] param_tx_data_Field;
    logic        repairclk_tx_valid;  msg_no_e repairclk_tx_msg_id;  logic [15:0] repairclk_tx_MsgInfo;  logic [63:0] repairclk_tx_data_Field;
    logic        reversalmb_tx_valid; msg_no_e reversalmb_tx_msg_id; logic [15:0] reversalmb_tx_MsgInfo; logic [63:0] reversalmb_tx_data_Field;
    logic        repairmb_tx_valid;   msg_no_e repairmb_tx_msg_id;   logic [15:0] repairmb_tx_MsgInfo;   logic [63:0] repairmb_tx_data_Field;
    logic        repairval_tx_valid;  msg_no_e repairval_tx_msg_id;  logic [15:0] repairval_tx_MsgInfo;  logic [63:0] repairval_tx_data_Field;
    logic        cal_tx_valid;        msg_no_e cal_tx_msg_id;        logic [15:0] cal_tx_MsgInfo;        logic [63:0] cal_tx_data_Field;

    // Reversal request handshaking wire
    logic reversalmb_lane_reversal_req;

    // REPAIRCLK pattern / compare
    logic       repairclk_tx_pattern_en;
    logic [2:0] repairclk_tx_pattern_setup;
    logic       repairclk_rx_compare_en;
    logic [1:0] repairclk_rx_compare_setup;

    // REPAIRVAL pattern / compare
    logic       repairval_tx_pattern_en;
    logic [2:0] repairval_tx_pattern_setup;
    logic       repairval_tx_val_pattern_sel;
    logic       repairval_rx_compare_en;
    logic [1:0] repairval_rx_compare_setup;

    // REVERSALMB pattern / compare
    logic       reversalmb_tx_pattern_en;
    logic [2:0] reversalmb_tx_pattern_setup;
    logic [1:0] reversalmb_tx_data_pattern_sel;
    logic       reversalmb_rx_compare_en;
    logic [1:0] reversalmb_rx_compare_setup;
    logic       reversalmb_clear_error_req;

    // REPAIRMB pattern / compare
    logic       repairmb_clear_error_req;
    logic [2:0] repairmb_rx_data_lane_mask;
    logic [2:0] repairmb_tx_data_lane_mask;

    logic [3:0] param_Link_Width_enable_status;
    logic       param_Clock_Phase_enable_status;
    logic       param_Clock_mode_enable_status;
    logic       param_TARR_enable_status;
    logic [3:0] param_Link_Speed_enable_status;
    logic       param_PMO_enable_status;
    logic       param_L2SPD_enable_status;
    logic       param_PSPT_enable_status;

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
        .mbinit_state_n(mbinit_state_n),
        .global_error(global_error),

        // Sideband Muxed Outputs
        .sb_tx_valid(sb_tx_valid),
        .sb_tx_msg_id(sb_tx_msg_id),
        .sb_tx_MsgInfo(sb_tx_MsgInfo),
        .sb_tx_data_Field(sb_tx_data_Field),

        // Unified Mainband Outputs
        .mb_tx_pattern_en(mb_tx_pattern_en),
        .mb_tx_pattern_setup(mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel(mb_tx_val_pattern_sel),
        .mb_rx_compare_en(mb_rx_compare_en),
        .mb_rx_compare_setup(mb_rx_compare_setup),
        .clear_error_req(clear_error_req),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
        .mb_lane_reversal_req(mb_lane_reversal_req),

        // PARAM
        .param_enable(param_enable),
        .param_done(param_done),
        .param_error(param_error),
        .param_tx_valid(param_tx_valid),
        .param_tx_msg_id(param_tx_msg_id),
        .param_tx_MsgInfo(param_tx_MsgInfo),
        .param_tx_data_Field(param_tx_data_Field),

        // CAL
        .cal_enable(cal_enable),
        .cal_done(cal_done),
        .cal_error(cal_error),
        .cal_tx_valid(cal_tx_valid),
        .cal_tx_msg_id(cal_tx_msg_id),
        .cal_tx_MsgInfo(cal_tx_MsgInfo),
        .cal_tx_data_Field(cal_tx_data_Field),

        // REPAIRCLK
        .repairclk_enable(repairclk_enable),
        .repairclk_done(repairclk_done),
        .repairclk_error(repairclk_error),
        .repairclk_tx_valid(repairclk_tx_valid),
        .repairclk_tx_msg_id(repairclk_tx_msg_id),
        .repairclk_tx_MsgInfo(repairclk_tx_MsgInfo),
        .repairclk_tx_data_Field(repairclk_tx_data_Field),
        .repairclk_tx_pattern_en(repairclk_tx_pattern_en),
        .repairclk_tx_pattern_setup(repairclk_tx_pattern_setup),
        .repairclk_rx_compare_en(repairclk_rx_compare_en),
        .repairclk_rx_compare_setup(repairclk_rx_compare_setup),

        // REPAIRVAL
        .repairval_enable(repairval_enable),
        .repairval_done(repairval_done),
        .repairval_error(repairval_error),
        .repairval_tx_valid(repairval_tx_valid),
        .repairval_tx_msg_id(repairval_tx_msg_id),
        .repairval_tx_MsgInfo(repairval_tx_MsgInfo),
        .repairval_tx_data_Field(repairval_tx_data_Field),
        .repairval_tx_pattern_en(repairval_tx_pattern_en),
        .repairval_tx_pattern_setup(repairval_tx_pattern_setup),
        .repairval_tx_val_pattern_sel(repairval_tx_val_pattern_sel),
        .repairval_rx_compare_en(repairval_rx_compare_en),
        .repairval_rx_compare_setup(repairval_rx_compare_setup),

        // REVERSALMB
        .reversalmb_enable(reversalmb_enable),
        .reversalmb_done(reversalmb_done),
        .reversalmb_error(reversalmb_error),
        .reversalmb_tx_valid(reversalmb_tx_valid),
        .reversalmb_tx_msg_id(reversalmb_tx_msg_id),
        .reversalmb_tx_MsgInfo(reversalmb_tx_MsgInfo),
        .reversalmb_tx_data_Field(reversalmb_tx_data_Field),
        .reversalmb_tx_pattern_en(reversalmb_tx_pattern_en),
        .reversalmb_tx_pattern_setup(reversalmb_tx_pattern_setup),
        .reversalmb_tx_data_pattern_sel(reversalmb_tx_data_pattern_sel),
        .reversalmb_rx_compare_en(reversalmb_rx_compare_en),
        .reversalmb_rx_compare_setup(reversalmb_rx_compare_setup),
        .reversalmb_clear_error_req(reversalmb_clear_error_req),
        .reversalmb_lane_reversal_req(reversalmb_lane_reversal_req),

        // REPAIRMB
        .repairmb_enable(repairmb_enable),
        .repairmb_done(repairmb_done),
        .repairmb_error(repairmb_error),
        .repairmb_tx_valid(repairmb_tx_valid),
        .repairmb_tx_msg_id(repairmb_tx_msg_id),
        .repairmb_tx_MsgInfo(repairmb_tx_MsgInfo),
        .repairmb_tx_data_Field(repairmb_tx_data_Field),
        .repairmb_clear_error_req(repairmb_clear_error_req),
        .repairmb_rx_data_lane_mask(repairmb_rx_data_lane_mask),
        .repairmb_tx_data_lane_mask(repairmb_tx_data_lane_mask),

        .param_Link_Width_enable_status(param_Link_Width_enable_status),
        .reg_Link_Width_enable_status(reg_Link_Width_enable_status),

        .param_Clock_Phase_enable_status(param_Clock_Phase_enable_status),
        .reg_Clock_Phase_enable_status(reg_Clock_Phase_enable_status),

        .param_Clock_mode_enable_status(param_Clock_mode_enable_status),
        .reg_Clock_mode_enable_status(reg_Clock_mode_enable_status),

        .param_TARR_enable_status(param_TARR_enable_status),
        .reg_TARR_enable_status(reg_TARR_enable_status),

        .param_Link_Speed_enable_status(param_Link_Speed_enable_status),
        .reg_Link_Speed_enable_status(reg_Link_Speed_enable_status),

        .param_PMO_enable_status(param_PMO_enable_status),
        .reg_PMO_enable_status(reg_PMO_enable_status),

        .param_L2SPD_enable_status(param_L2SPD_enable_status),
        .reg_L2SPD_enable_status(reg_L2SPD_enable_status),

        .param_PSPT_enable_status(param_PSPT_enable_status),
        .reg_PSPT_enable_status(reg_PSPT_enable_status)
    );

    // =========================================================================
    // SUBMODULE INSTANTIATIONS
    // =========================================================================

    // S1: PARAM
    MBINIT_PARAM #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_param (
        .clk(clk),
        .rst_n(rst_n),
        .mb_param_enable(param_enable),
        .mb_param_done(param_done),
        .mb_param_error(param_error),
        
        .sb_param_rx_valid(sb_rx_valid),
        .sb_param_rx_msg_id(sb_rx_msg_id),
        .sb_param_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_param_rx_data_Field(sb_rx_data_Field),
        
        .sb_param_tx_valid(param_tx_valid),
        .sb_param_tx_msg_id(param_tx_msg_id),
        .sb_param_tx_MsgInfo(param_tx_MsgInfo),
        .sb_param_tx_data_Field(param_tx_data_Field),
        
        .Supported_TX_Vswing(reg_Supported_TX_Vswing),
        .so(reg_so),
        .mtp(reg_mtp),
        .Module_ID(reg_Module_ID),
        
        .TARR_support_local_cap(reg_TARR_support_local_cap),
        .Clock_Phase_cap(reg_Clock_Phase_cap),
        .Clock_mode_cap(reg_Clock_mode_cap),
        .L2SPD_support_local_cap(reg_L2SPD_support_local_cap),
        .PSPT_support_local_cap(reg_PSPT_support_local_cap),
        .PMO_support_local_cap(reg_PMO_support_local_cap),
        .Max_Link_Width_cap(reg_Max_Link_Width_cap),
        .Max_Link_Speed_cap(reg_Max_Link_Speed_cap),
        
        .TARR_support_local_ctrl(reg_TARR_support_local_ctrl),
        .phy_x8_mode_ctrl(reg_phy_x8_mode_ctrl),
        .SPMW(SPMW),
        .Clock_Phase_ctrl(reg_Clock_Phase_ctrl),
        .Clock_mode_ctrl(reg_Clock_mode_ctrl),
        
        .L2SPD_support_local_ctrl(reg_L2SPD_support_local_ctrl),
        .PSPT_support_local_ctrl(reg_PSPT_support_local_ctrl),
        .PMO_support_local_ctrl(reg_PMO_support_local_ctrl),
        .Target_Link_Width_ctrl(reg_Target_Link_Width_ctrl),
        .Target_Link_Speed_ctrl(reg_Target_Link_Speed_ctrl),
        
        .Clock_Phase_enable_status(param_Clock_Phase_enable_status),
        .Clock_mode_enable_status(param_Clock_mode_enable_status),
        .TARR_enable_status(param_TARR_enable_status),
        .Link_Width_enable_status(param_Link_Width_enable_status),
        .Link_Speed_enable_status(param_Link_Speed_enable_status),
        .PMO_enable_status(param_PMO_enable_status),
        .L2SPD_enable_status(param_L2SPD_enable_status),
        .PSPT_enable_status(param_PSPT_enable_status),
        
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .global_error(mbinit_error)
    );

 
    // S2: CAL
    MBINIT_CAL #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_cal (
        .clk(clk),
        .rst_n(rst_n),
        .mb_cal_enable(cal_enable),
        .mb_cal_done(cal_done),
        .mb_cal_error(cal_error),
        .sb_cal_rx_valid(sb_rx_valid),
        .sb_cal_rx_msg_id(sb_rx_msg_id),
        .sb_cal_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_cal_rx_data_Field(sb_rx_data_Field),
        .sb_cal_tx_valid(cal_tx_valid),
        .sb_cal_tx_msg_id(cal_tx_msg_id),
        .sb_cal_tx_MsgInfo(cal_tx_MsgInfo),
        .sb_cal_tx_data_Field(cal_tx_data_Field),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .global_error(mbinit_error)
    );

    // S3: REPAIRCLK
    MBINIT_REPAIRCLK #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairclk (
        .clk(clk),
        .rst_n(rst_n),
        .mb_repairclk_enable(repairclk_enable),
        .mb_repairclk_done(repairclk_done),
        .mb_repairclk_error(repairclk_error),
        .sb_repairclk_rx_valid(sb_rx_valid),
        .sb_repairclk_rx_msg_id(sb_rx_msg_id),
        .sb_repairclk_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_repairclk_rx_data_Field(sb_rx_data_Field),
        .sb_repairclk_tx_valid(repairclk_tx_valid),
        .sb_repairclk_tx_msg_id(repairclk_tx_msg_id),
        .sb_repairclk_tx_MsgInfo(repairclk_tx_MsgInfo),
        .sb_repairclk_tx_data_Field(repairclk_tx_data_Field),
        .mb_tx_pattern_en(repairclk_tx_pattern_en),
        .mb_tx_pattern_setup(repairclk_tx_pattern_setup),
        .mb_rx_compare_en(repairclk_rx_compare_en),
        .mb_rx_compare_setup(repairclk_rx_compare_setup),
        .rtrk_pass(repairclk_rtrk_pass),
        .rckn_pass(repairclk_rckn_pass),
        .rckp_pass(repairclk_rckp_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .global_error(mbinit_error)
    );

    // S4: REPAIRVAL
    MBINIT_REPAIRVAL #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairval (
        .clk(clk),
        .rst_n(rst_n),
        .mb_repairval_enable(repairval_enable),
        .mb_repairval_done(repairval_done),
        .mb_repairval_error(repairval_error),
        .sb_repairval_rx_valid(sb_rx_valid),
        .sb_repairval_rx_msg_id(sb_rx_msg_id),
        .sb_repairval_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_repairval_rx_data_Field(sb_rx_data_Field),
        .sb_repairval_tx_valid(repairval_tx_valid),
        .sb_repairval_tx_msg_id(repairval_tx_msg_id),
        .sb_repairval_tx_MsgInfo(repairval_tx_MsgInfo),
        .sb_repairval_tx_data_Field(repairval_tx_data_Field),
        .mb_tx_pattern_en(repairval_tx_pattern_en),
        .mb_tx_pattern_setup(repairval_tx_pattern_setup),
        .mb_tx_val_pattern_sel(repairval_tx_val_pattern_sel),
        .mb_rx_compare_en(repairval_rx_compare_en),
        .mb_rx_compare_setup(repairval_rx_compare_setup),
        .mb_rx_val_pass(repairval_RVLD_L_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .global_error(mbinit_error)
    );

    // S5: REVERSALMB
    MBINIT_REVERSALMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_reversalmb (
        .clk(clk),
        .rst_n(rst_n),
        .mb_reversal_enable(reversalmb_enable),
        .mb_reversal_done(reversalmb_done),
        .mb_reversal_error(reversalmb_error),
        .sb_reversal_rx_valid(sb_rx_valid),
        .sb_reversal_rx_msg_id(sb_rx_msg_id),
        .sb_reversal_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_reversal_rx_data_Field(sb_rx_data_Field),
        .sb_reversal_tx_valid(reversalmb_tx_valid),
        .sb_reversal_tx_msg_id(reversalmb_tx_msg_id),
        .sb_reversal_tx_MsgInfo(reversalmb_tx_MsgInfo),
        .sb_reversal_tx_data_Field(reversalmb_tx_data_Field),
        .Link_Width_enable_status(reg_Link_Width_enable_status),
        .mb_tx_data_pattern_sel(reversalmb_tx_data_pattern_sel),
        .mb_tx_pattern_setup(reversalmb_tx_pattern_setup),
        .mb_rx_compare_setup(reversalmb_rx_compare_setup),
        .mb_tx_pattern_en(reversalmb_tx_pattern_en),
        .mb_rx_compare_en(reversalmb_rx_compare_en),
        .mb_rx_perlane_pass(mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),
        .mb_lane_reversal_req(reversalmb_lane_reversal_req),
        .clear_error_req(reversalmb_clear_error_req),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .global_error(mbinit_error)
    );

    // S6: REPAIRMB
    MBINIT_REPAIRMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairmb (
        .clk(clk),
        .rst_n(rst_n),
        .Link_Width_enable_status(reg_Link_Width_enable_status),
        .SPMW(SPMW),
        .mb_repairmb_enable(repairmb_enable),
        .mb_repairmb_done(repairmb_done),
        .mb_repairmb_error(repairmb_error),
        .sb_repairmb_rx_valid(sb_rx_valid),
        .sb_repairmb_rx_msg_id(sb_rx_msg_id),
        .sb_repairmb_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_repairmb_rx_data_Field(sb_rx_data_Field),
        .sb_repairmb_tx_valid(repairmb_tx_valid),
        .sb_repairmb_tx_msg_id(repairmb_tx_msg_id),
        .sb_repairmb_tx_MsgInfo(repairmb_tx_MsgInfo),
        .sb_repairmb_tx_data_Field(repairmb_tx_data_Field),
        .global_error(mbinit_error),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .local_tx_pt_en(local_tx_pt_en),
        .partner_tx_pt_en(partner_tx_pt_en),
        .d2c_pattern_setup(d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_pattern_mode),
        .d2c_compare_setup(d2c_compare_setup),
        .d2c_perlane_pass(d2c_perlane_pass),
        .local_test_d2c_done(local_test_d2c_done),
        .partner_test_d2c_done(partner_test_d2c_done),
        .clear_error_req(repairmb_clear_error_req),
        .mbinit_rx_data_lane_mask(repairmb_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(repairmb_tx_data_lane_mask)
    );



// =============================================================================
// SYSTEMVERILOG ASSERTIONS (SVA) FOR WRAPPER INTEGRITY
// =============================================================================
`ifdef SIMULATION
    // 1. Safety Check: Done and Error are mutually exclusive
    assert_wrapper_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mbinit_done && mbinit_error)
    );

    // 2. Protocol Rule: Sideband TX stability until sb_ltsm_rdy asserts
    property p_wrapper_tx_stability;
        @(posedge clk) disable iff (!rst_n || !mbinit_enable)
        (sb_tx_valid && !sb_ltsm_rdy) |-> 
        ##1 (sb_tx_valid && 
             $stable(sb_tx_msg_id) && 
             $stable(sb_tx_MsgInfo) && 
             $stable(sb_tx_data_Field));
    endproperty
    assert_wrapper_tx_stability: assert property(p_wrapper_tx_stability);

    // 3. Error Check: Watchdog timeout assertion leading to top error
    property p_wrapper_timeout_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        global_error |-> ##[1:5] mbinit_error;
    endproperty
    assert_wrapper_timeout_leads_to_error: assert property(p_wrapper_timeout_leads_to_error);

    // 4. Safety Check: Substate errors properly trigger top level error FSM transition
    property p_wrapper_sub_error_leads_to_top_error;
        @(posedge clk) disable iff (!rst_n)
        (param_error || cal_error || repairclk_error || repairval_error || reversalmb_error || repairmb_error)
        |-> ##[1:5] (mbinit_error);
    endproperty
    assert_wrapper_sub_error_leads_to_top_error: assert property(p_wrapper_sub_error_leads_to_top_error);
`endif

endmodule
