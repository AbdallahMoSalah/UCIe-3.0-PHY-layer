import UCIe_pkg::*;

module MBINIT
#(
    parameter int CLK_FRQ_HZ = 800000000
)
(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // From / To LTSM
    // =========================================================================
    input  logic mbinit_enable,
    output logic mbinit_done,
    output logic mbinit_error,
    
    // SPMW Strap
 
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
    output logic            tx_pt_en,
    output logic [2:0]      d2c_pattern_setup,// 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    output logic [1:0]      d2c_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    output logic            d2c_pattern_mode,// 0: Continuous Pattern Mode, 1: Burst Pattern Mode. 
    output logic [1:0]      d2c_compare_setup, // 0: Per-Lane, 1: Aggregate,  2: Valid Lane, 3: Clock Lane Comparison.

    input logic [15:0] d2c_perlane_pass, // The Per-Lane Errors (Each bit represents one pass Data Lane).

    input logic test_d2c_done,


    // =========================================================================
    // RX / TX sideband message bus
    // =========================================================================
    input  logic        sb_rx_valid,
    input  msg_no_e     sb_rx_msg_id,
    input  logic [15:0] sb_rx_MsgInfo,
    input  logic [63:0] sb_rx_data_Field,

    output logic        sb_tx_valid,
    input  logic        sb_ltsm_rdy,
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
    // External Watchdog Timer Interface
    // =========================================================================
    output logic timer_enable,
    output logic timer_rst_n,
    input  logic timer_timeout_expired
    
);


    MBINIT_WRAPPER u_mbinit_wrapper(
        .clk(clk),
        .rst_n(rst_n),
    
        // =========================================================================
        // From / To LTSM
        // =========================================================================
        .mbinit_enable(mbinit_enable),
        .mbinit_done(mbinit_done),
        .mbinit_error(mbinit_error),

        // SPMW Strap
        
        .SPMW(SPMW),
    
        // =========================================================================
        // Capability interface (Discrete Normal Ports)
        // =========================================================================
        // Local Inputs (from registers)
        .reg_phy_x8_mode_ctrl(reg_phy_x8_mode_ctrl),
        .local_max_speed(local_max_speed),
        .local_sbfe(local_sbfe),
        .reg_TARR_support_local_cap(reg_TARR_support_local_cap),
        .reg_L2SPD_support_local_cap(reg_L2SPD_support_local_cap),
        .reg_PSPT_support_local_cap(reg_PSPT_support_local_cap),
        .local_so(local_so),
        .reg_PMO_support_local_cap(reg_PMO_support_local_cap),
        .reg_Max_Link_Width_cap(reg_Max_Link_Width_cap),
        .reg_Max_Link_Speed_cap(reg_Max_Link_Speed_cap),
        .local_mtp(local_mtp),
    
        .reg_Supported_TX_Vswing(reg_Supported_TX_Vswing),
        .reg_so(reg_so),
        .reg_mtp(reg_mtp),
        .reg_Module_ID(reg_Module_ID),
        .reg_Clock_Phase_cap(reg_Clock_Phase_cap),
        .reg_Clock_mode_cap(reg_Clock_mode_cap),
        .reg_TARR_support_local_ctrl(reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl(reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl(reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl(reg_Clock_mode_ctrl),
    
        // From Link
        .reg_L2SPD_support_local_ctrl(reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl(reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl(reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl(reg_Target_Link_Speed_ctrl),
    
    
        // -------------------------------
        // --------- STATUS REG ----------
        // -------------------------------
        // From Phy 
        .reg_Clock_Phase_enable_status(reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status(reg_Clock_mode_enable_status),
        .reg_TARR_enable_status(reg_TARR_enable_status),
        // From Link
        .reg_Link_Width_enable_status(reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status(reg_Link_Speed_enable_status),
        .reg_PMO_enable_status(reg_PMO_enable_status),
        .reg_L2SPD_enable_status(reg_L2SPD_enable_status),
        .reg_PSPT_enable_status(reg_PSPT_enable_status),
    
        // =========================================================================
        // D2C point-test interface (for MBINIT_REPAIRMB)
        // =========================================================================
            // d2cptest interface
        .tx_pt_en(tx_pt_en),
        .d2c_pattern_setup(d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_pattern_mode),
        .d2c_compare_setup(d2c_compare_setup),
    
        .d2c_perlane_pass(d2c_perlane_pass), // The Per-Lane Errors (Each bit represents one pass Data Lane).
    
        .test_d2c_done(test_d2c_done),
    
    
        // =========================================================================
        // RX / TX sideband message bus
        // =========================================================================
        .sb_rx_valid(sb_rx_valid),
        .sb_rx_msg_id(sb_rx_msg_id),
        .sb_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_rx_data_Field(sb_rx_data_Field),
    
        .sb_tx_valid(sb_tx_valid),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .sb_tx_msg_id(sb_tx_msg_id),
        .sb_tx_MsgInfo(sb_tx_MsgInfo),
        .sb_tx_data_Field(sb_tx_data_Field),
    
        // =========================================================================
        // Unified Mainband Outputs (Muxed / Latched)
        // =========================================================================
        .mb_tx_pattern_en(mb_tx_pattern_en),
        .mb_tx_pattern_setup(mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel(mb_tx_val_pattern_sel),
        .mb_rx_compare_en(mb_rx_compare_en),
        .mb_rx_compare_setup(mb_rx_compare_setup),
        .clear_error_req(clear_error_req),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
    
        // =========================================================================
        // Unified Mainband Inputs
        // =========================================================================
        .mb_rx_perlane_pass(mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),
    
        // =========================================================================
        // Substate Discrete Outputs/Inputs
        // =========================================================================
        .mb_lane_reversal_req(mb_lane_reversal_req),
        .repairclk_rtrk_pass(repairclk_rtrk_pass),
        .repairclk_rckn_pass(repairclk_rckn_pass),
        .repairclk_rckp_pass(repairclk_rckp_pass),
        .repairval_RVLD_L_pass(repairval_RVLD_L_pass),
    
        // =========================================================================
        // External Watchdog Timer Interface
        // =========================================================================
        .timer_enable(timer_enable),
        .timer_rst_n(timer_rst_n),
        .timer_timeout_expired(timer_timeout_expired)
    );

    

endmodule