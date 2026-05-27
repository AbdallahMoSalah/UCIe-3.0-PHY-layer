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
    
    // FIFO handshake & SPMW Strap
    input  logic ltsm_rdy,
    input  logic SPMW,

    // =========================================================================
    // Capability interface (Discrete Normal Ports)
    // =========================================================================
    // Local Inputs (from registers)
    input  logic        local_is_x8,
    input  logic [3:0]  local_max_speed,
    input  logic        local_sbfe,
    input  logic        local_tarr,
    input  logic        local_l2spd,
    input  logic        local_pspt,
    input  logic        local_so,
    input  logic        local_pmo,
    input  logic        local_mtp,

    // Partner Outputs (to registers)
    output logic        partner_is_x8,
    output logic [3:0]  partner_max_speed,
    output logic        partner_sbfe,
    output logic        partner_tarr,
    output logic        partner_l2spd,
    output logic        partner_pspt,
    output logic        partner_so,
    output logic        partner_pmo,
    output logic        partner_mtp,

    // Negotiated Outputs (to registers / consumed by others)
    output logic        use_x8_mode,
    output logic [3:0]  negotiated_speed,
    output logic        negotiated_sbfe,
    output logic        negotiated_tarr,
    output logic        negotiated_l2spd,
    output logic        negotiated_pspt,
    output logic        negotiated_so,
    output logic        negotiated_pmo,
    output logic        negotiated_mtp,

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
    // REVERSALMB / REPAIRMB pattern / compare (Shared)
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

    // Watchdog Timer Handshakes
    logic param_timer_enable,      param_timeout_expired;
    logic cal_timer_enable,        cal_timeout_expired;
    logic repairclk_timer_enable,  repairclk_timeout_expired;
    logic repairval_timer_enable,  repairval_timeout_expired;
    logic reversalmb_timer_enable, reversalmb_timeout_expired;
    logic repairmb_timer_enable,   repairmb_timeout_expired;

    // Mux outputs
    logic reversal_tx_data_pattern_sel_w;
    logic reversal_rx_compare_setup_w;
    logic reversal_tx_data_pattern_en;
    logic reversal_rx_data_compare_en;
    logic reversal_clear_error_req;

    logic repair_tx_data_pattern_sel_w;
    logic repair_rx_compare_setup_w;
    logic repair_tx_data_pattern_en;
    logic repair_rx_data_compare_en;
    logic repair_clear_error_req;

    // Width negotiation signals
    logic [3:0] link_width_enable_status_w;
    logic reg_x8_mode_req_w;
    assign reg_x8_mode_req_w = (link_width_enable_status_w == 4'h1);

    // Hardcoded Pattern Setup Outputs
    assign repairclk_tx_pattern_setup   = 3'b100; // 100b: Clock Pattern
    assign repairclk_tx_clk_pattern_sel = 2'b01;  // clock pattern select
    assign repairclk_rx_compare_setup   = 2'b01;  // clock compare setup

    assign reversalmb_tx_pattern_setup  = 3'b001; // 001b: Data Pattern

    assign repairval_tx_pattern_setup   = 3'b010; // 010b: Valid Pattern
    assign repairval_tx_val_pattern_sel = 1'b1;   // valid pattern select
    assign repairval_rx_compare_setup   = 2'b01;  // valid compare setup

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

        // Mainband Muxed Outputs
        .mb_tx_valid(mb_tx_valid),
        .mb_tx_msg_id(mb_tx_msg_id),
        .mb_tx_MsgInfo(mb_tx_MsgInfo),
        .mb_tx_data_Field(mb_tx_data_Field),

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

        // REPAIRVAL
        .repairval_enable(repairval_enable),
        .repairval_done(repairval_done),
        .repairval_error(repairval_error),
        .repairval_tx_valid(repairval_tx_valid),
        .repairval_tx_msg_id(repairval_tx_msg_id),
        .repairval_tx_MsgInfo(repairval_tx_MsgInfo),
        .repairval_tx_data_Field(repairval_tx_data_Field),

        // REVERSALMB
        .reversalmb_enable(reversalmb_enable),
        .reversalmb_done(reversalmb_done),
        .reversalmb_error(reversalmb_error),
        .reversalmb_tx_valid(reversalmb_tx_valid),
        .reversalmb_tx_msg_id(reversalmb_tx_msg_id),
        .reversalmb_tx_MsgInfo(reversalmb_tx_MsgInfo),
        .reversalmb_tx_data_Field(reversalmb_tx_data_Field),

        // REPAIRMB
        .repairmb_enable(repairmb_enable),
        .repairmb_done(repairmb_done),
        .repairmb_error(repairmb_error),
        .repairmb_tx_valid(repairmb_tx_valid),
        .repairmb_tx_msg_id(repairmb_tx_msg_id),
        .repairmb_tx_MsgInfo(repairmb_tx_MsgInfo),
        .repairmb_tx_data_Field(repairmb_tx_data_Field)
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
        
        .mb_param_rx_valid(mb_rx_valid),
        .mb_param_rx_msg_id(mb_rx_msg_id),
        .mb_param_rx_MsgInfo(mb_rx_MsgInfo),
        .mb_param_rx_data_Field(mb_rx_data_Field),
        
        .mb_param_tx_valid(param_tx_valid),
        .mb_param_tx_msg_id(param_tx_msg_id),
        .mb_param_tx_MsgInfo(param_tx_MsgInfo),
        .mb_param_tx_data_Field(param_tx_data_Field),
        
        .Supported_TX_Vswing(5'b00000),
        .so(1'b0),
        .mtp(1'b0),
        .Module_ID(2'b00),
        
        .TARR_support_local_cap(local_tarr),
        .Clock_Phase_cap(2'b00),
        .Clock_mode_cap(2'b00),
        .L2SPD_support_local_cap(local_l2spd),
        .PSPT_support_local_cap(local_pspt),
        .PMO_support_local_cap(local_pmo),
        .Max_Link_Width_cap(local_is_x8 ? 3'h1 : 3'h2),
        .Max_Link_Speed_cap(local_max_speed),
        
        .TARR_support_local_ctrl(local_tarr),
        .phy_x8_mode_ctrl(local_is_x8),
        .SPMW(SPMW),
        .Clock_Phase_ctrl(1'b0),
        .Clock_mode_ctrl(1'b0),
        
        .L2SPD_support_local_ctrl(local_l2spd),
        .PSPT_support_local_ctrl(local_pspt),
        .PMO_support_local_ctrl(local_pmo),
        .Target_Link_Width_ctrl(local_is_x8 ? 4'h1 : 4'h2),
        .Target_Link_Speed_ctrl(local_max_speed),
        
        .Clock_Phase_enable_status(),
        .Clock_mode_enable_status(),
        .TARR_enable_status(negotiated_tarr),
        .Link_Width_enable_status(link_width_enable_status_w),
        .Link_Speed_enable_status(negotiated_speed),
        .PMO_enable_status(negotiated_pmo),
        .L2SPD_enable_status(negotiated_l2spd),
        .PSPT_enable_status(negotiated_pspt),
        
        .ltsm_rdy(ltsm_rdy),
        .mb_param_timer_enable(param_timer_enable),
        .mb_param_timeout_expired(param_timeout_expired)
    );

    // Map Partner capability registers directly using hierarchical paths
    assign partner_is_x8       = u_param.partner_UCIE_x8_sel;
    assign partner_max_speed   = u_param.partner_link_speed_sel;
    assign partner_sbfe        = u_param.partner_SFES_sel;
    assign partner_tarr        = u_param.partner_TARR_sel;
    assign partner_l2spd       = u_param.partner_l2spd;
    assign partner_pspt        = u_param.partner_pspt;
    assign partner_so          = u_param.partner_so;
    assign partner_pmo         = u_param.partner_pmo;
    assign partner_mtp         = u_param.partner_mtp;

    // Map Negotiated capability outputs
    assign use_x8_mode         = reg_x8_mode_req_w;
    assign negotiated_sbfe     = u_param.local_SFES_negotiated;
    assign negotiated_so       = u_param.local_so_negotiated;
    assign negotiated_mtp      = u_param.local_mtp_negotiated;

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
        .ltsm_rdy(ltsm_rdy),
        .timeout_cal_enable(cal_timer_enable),
        .timeout_cal_expired(cal_timeout_expired)
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
        .mb_tx_pattern_en(repairclk_tx_pattern_en),
        .mb_rx_compare_en(repairclk_rx_compare_en),
        .rtrk_pass(repairclk_rtrk_pass),
        .rckn_pass(repairclk_rckn_pass),
        .rckp_pass(repairclk_rckp_pass),
        .mb_tx_pattern_count_done(repairclk_rx_compare_done),
        .ltsm_rdy(ltsm_rdy),
        .timeout_repairclk_expired(repairclk_timeout_expired),
        .timeout_repairclk_enable(repairclk_timer_enable)
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
        .mb_tx_pattern_en(repairval_tx_pattern_en),
        .mb_rx_compare_en(repairval_rx_compare_en),
        .mb_rx_val_pass(repairval_RVLD_L_pass),
        .mb_tx_pattern_count_done(repairval_rx_compare_done),
        .ltsm_rdy(ltsm_rdy),
        .timer_enable(repairval_timer_enable),
        .timeout_expired(repairval_timeout_expired)
    );

    // S5: REVERSALMB
    MBINIT_REVERSALMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_reversalmb (
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
        .Link_Width_enable_status(link_width_enable_status_w),
        .mb_tx_data_pattern_sel(reversal_tx_data_pattern_sel_w),
        .mb_rx_compare_setup(reversal_rx_compare_setup_w),
        .mb_tx_pattern_en(reversal_tx_data_pattern_en),
        .mb_rx_compare_en(reversal_rx_data_compare_en),
        .mb_rx_perlane_pass(~reversalmb_rx_perlane_err),
        .mb_tx_pattern_count_done(reversalmb_rx_compare_done),
        .mb_lane_reversal_req(mb_lane_reversal_req),
        .clear_error_req(reversal_clear_error_req),
        .ltsm_rdy(ltsm_rdy),
        .timeout_reversal_expired(reversalmb_timeout_expired),
        .timeout_reversal_enable(reversalmb_timer_enable)
    );

    // S6: REPAIRMB
    MBINIT_REPAIRMB #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) u_repairmb (
        .clk(clk),
        .rst_n(rst_n),
        .Link_Width_enable_status(link_width_enable_status_w),
        .SPMW(SPMW),
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
        .timeout_repair_expired(repairmb_timeout_expired),
        .timeout_repair_enable(repairmb_timer_enable),
        .ltsm_rdy(ltsm_rdy),
        .tx_pt_en(d2c_test_if.tx_pt_en),
        .d2c_pattern_setup(d2c_test_if.d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_test_if.d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_test_if.d2c_pattern_mode),
        .d2c_compare_setup(d2c_test_if.d2c_compare_setup),
        .d2c_perlane_pass(d2c_test_if.mb_rx_perlane_pass),
        .test_d2c_done(d2c_test_if.test_d2c_done),
        .clear_error_req(repair_clear_error_req),
        .mbinit_rx_data_lane_mask(d2c_test_if.mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(d2c_test_if.mbinit_tx_data_lane_mask)
    );

    // =========================================================================
    // DYNAMIC PATTERN / COMPARE MULTIPLEXERS
    // =========================================================================
    always_comb begin
        if (repairmb_enable) begin
            reversalmb_tx_data_pattern_sel = {1'b0, repair_tx_data_pattern_sel_w};
            reversalmb_rx_compare_setup    = {1'b0, repair_rx_compare_setup_w};
            reversalmb_tx_pattern_en       = repair_tx_data_pattern_en;
            reversalmb_rx_compare_en       = repair_rx_data_compare_en;
            clear_error_req                = repair_clear_error_req;
        end else begin
            // Default to reversalmb's outputs
            reversalmb_tx_data_pattern_sel = {1'b0, reversal_tx_data_pattern_sel_w};
            reversalmb_rx_compare_setup    = {1'b0, reversal_rx_compare_setup_w};
            reversalmb_tx_pattern_en       = reversal_tx_data_pattern_en;
            reversalmb_rx_compare_en       = reversal_rx_data_compare_en;
            clear_error_req                = reversal_clear_error_req;
        end
    end

    assign mb_x8_mode_req = reg_x8_mode_req_w;

    // =========================================================================
    // SHARED SINGLE WATCHDOG TIMER WITH AUTO-RESET ON STATE CHANGE
    // =========================================================================
    logic [3:0] prev_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_state <= 4'h0;
        else
            prev_state <= u_controller.current_state;
    end
    
    logic state_changed;
    assign state_changed = (prev_state != u_controller.current_state);
    
    logic timer_rst_n;
    assign timer_rst_n = rst_n && !state_changed;

    logic timer_enable;
    logic timer_timeout_expired;
    
    assign timer_enable = param_timer_enable || 
                          cal_timer_enable || 
                          repairclk_timer_enable || 
                          repairval_timer_enable || 
                          reversalmb_timer_enable || 
                          repairmb_timer_enable;

    timeout_counter #(.CLK_FRQ_HZ(CLK_FRQ_HZ), .TIME_OUT(8)) u_shared_timer (
        .clk(clk),
        .timeout_rst_n(timer_rst_n),
        .enable_timeout(timer_enable),
        .timeout_expired(timer_timeout_expired)
    );

    assign param_timeout_expired      = timer_timeout_expired;
    assign cal_timeout_expired        = timer_timeout_expired;
    assign repairclk_timeout_expired  = timer_timeout_expired;
    assign repairval_timeout_expired  = timer_timeout_expired;
    assign reversalmb_timeout_expired = timer_timeout_expired;
    assign repairmb_timeout_expired   = timer_timeout_expired;

    assign timeout_error = timer_timeout_expired;

// =============================================================================
// SYSTEMVERILOG ASSERTIONS (SVA) FOR WRAPPER INTEGRITY
// =============================================================================
`ifdef SIMULATION
    // 1. Safety Check: Done and Error are mutually exclusive
    assert_wrapper_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mbinit_done && mbinit_error)
    );

    // 2. Protocol Rule: Sideband TX stability until ltsm_rdy asserts
    property p_wrapper_tx_stability;
        @(posedge clk) disable iff (!rst_n || !mbinit_enable)
        (mb_tx_valid && !ltsm_rdy) |-> 
        ##1 (mb_tx_valid && 
             $stable(mb_tx_msg_id) && 
             $stable(mb_tx_MsgInfo) && 
             $stable(mb_tx_data_Field));
    endproperty
    assert_wrapper_tx_stability: assert property(p_wrapper_tx_stability);

    // 3. Error Check: Watchdog timeout assertion leading to top error
    property p_wrapper_timeout_leads_to_error;
        @(posedge clk) disable iff (!rst_n)
        timeout_error |-> ##[1:5] mbinit_error;
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
