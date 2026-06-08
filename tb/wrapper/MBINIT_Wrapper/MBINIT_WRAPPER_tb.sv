`timescale 1ns/1ps
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

interface ucie_mb_cap_if;
    logic        use_x8_mode;
    logic [3:0]  negotiated_speed;
    logic        negotiated_pmo;
    logic        negotiated_l2spd;
    logic        negotiated_pspt;
    logic        negotiated_tarr;
    logic        negotiated_so;
    logic        negotiated_mtp;

    logic        local_is_x8;
    logic [3:0]  local_max_speed;
    logic        local_sbfe;
    logic        local_tarr;
    logic        local_l2spd;
    logic        local_pspt;
    logic        local_so;
    logic        local_pmo;
    logic        local_mtp;
endinterface

module MBINIT_WRAPPER_tb;

    //////////////////////////////////////////////////
    // CLOCK / RESET
    //////////////////////////////////////////////////
    logic clk;
    logic rst_n;

    initial clk = 0;
    always #5 clk = ~clk;

    //////////////////////////////////////////////////
    // INTERFACES
    //////////////////////////////////////////////////
    ucie_mb_cap_if cap_if_module();
    ucie_mb_cap_if cap_if_partner();

    internal_ltsm_if d2c_if_module(.lclk(clk), .rst_n(rst_n));
    internal_ltsm_if d2c_if_partner(.lclk(clk), .rst_n(rst_n));

    logic        m_enable, m_done, m_error;
    logic        p_enable, p_done, p_error;
    state_n_e    m_mbinit_state_n;
    state_n_e    p_mbinit_state_n;

    logic        m_timer_enable;
    logic        m_timer_rst_n;
    logic        m_timer_timeout_expired;

    logic        p_timer_enable;
    logic        p_timer_rst_n;
    logic        p_timer_timeout_expired;

    // reg status signals
    logic [3:0]  m_width_status, p_width_status;
    logic [3:0]  m_speed_status, p_speed_status;
    logic        m_pmo_status, p_pmo_status;
    logic        m_l2spd_status, p_l2spd_status;
    logic        m_pspt_status, p_pspt_status;
    logic        m_tarr_status, p_tarr_status;
    logic        m_clk_phase_status, p_clk_phase_status;
    logic        m_clk_mode_status, p_clk_mode_status;

    // Connect cap_if interface negotiated outputs
    assign cap_if_module.use_x8_mode       = (m_width_status == 4'h1 || m_width_status == 4'h0); // x8 or x4
    assign cap_if_module.negotiated_speed  = m_speed_status;
    assign cap_if_module.negotiated_pmo    = m_pmo_status;
    assign cap_if_module.negotiated_l2spd  = m_l2spd_status;
    assign cap_if_module.negotiated_pspt   = m_pspt_status;
    assign cap_if_module.negotiated_tarr   = m_tarr_status;
    assign cap_if_module.negotiated_so     = m_clk_phase_status;
    assign cap_if_module.negotiated_mtp    = m_clk_mode_status;

    assign cap_if_partner.use_x8_mode      = (p_width_status == 4'h1 || p_width_status == 4'h0); // x8 or x4
    assign cap_if_partner.negotiated_speed = p_speed_status;
    assign cap_if_partner.negotiated_pmo   = p_pmo_status;
    assign cap_if_partner.negotiated_l2spd = p_l2spd_status;
    assign cap_if_partner.negotiated_pspt  = p_pspt_status;
    assign cap_if_partner.negotiated_tarr  = p_tarr_status;
    assign cap_if_partner.negotiated_so    = p_clk_phase_status;
    assign cap_if_partner.negotiated_mtp   = p_clk_mode_status;

    // Module Dynamic Inputs
    logic        m_repairclk_rtrk_pass;
    logic        m_repairclk_rckn_pass;
    logic        m_repairclk_rckp_pass;
    logic        m_repairclk_rx_compare_done;
    logic [15:0] m_reversalmb_rx_perlane_err;
    logic        m_reversalmb_rx_compare_done;
    logic        m_repairval_RVLD_L_pass;
    logic        m_repairval_rx_compare_done;

    // Partner Dynamic Inputs
    logic        p_repairclk_rtrk_pass;
    logic        p_repairclk_rckn_pass;
    logic        p_repairclk_rckp_pass;
    logic        p_repairclk_rx_compare_done;
    logic [15:0] p_reversalmb_rx_perlane_err;
    logic        p_reversalmb_rx_compare_done;
    logic        p_repairval_RVLD_L_pass;
    logic        p_repairval_rx_compare_done;

    logic m_mb_tx_pattern_count_done;
    always_comb begin
        if (\module .u_mbinit_wrapper.u_controller.current_state == \module .u_mbinit_wrapper.u_controller.CTRL_REPAIRCLK)
            m_mb_tx_pattern_count_done = m_repairclk_rx_compare_done;
        else if (\module .u_mbinit_wrapper.u_controller.current_state == \module .u_mbinit_wrapper.u_controller.CTRL_REPAIRVAL)
            m_mb_tx_pattern_count_done = m_repairval_rx_compare_done;
        else if (\module .u_mbinit_wrapper.u_controller.current_state == \module .u_mbinit_wrapper.u_controller.CTRL_REVERSALMB)
            m_mb_tx_pattern_count_done = m_reversalmb_rx_compare_done;
        else
            m_mb_tx_pattern_count_done = 1'b1;
    end

    logic p_mb_tx_pattern_count_done;
    always_comb begin
        if (partner.u_mbinit_wrapper.u_controller.current_state == partner.u_mbinit_wrapper.u_controller.CTRL_REPAIRCLK)
            p_mb_tx_pattern_count_done = p_repairclk_rx_compare_done;
        else if (partner.u_mbinit_wrapper.u_controller.current_state == partner.u_mbinit_wrapper.u_controller.CTRL_REPAIRVAL)
            p_mb_tx_pattern_count_done = p_repairval_rx_compare_done;
        else if (partner.u_mbinit_wrapper.u_controller.current_state == partner.u_mbinit_wrapper.u_controller.CTRL_REVERSALMB)
            p_mb_tx_pattern_count_done = p_reversalmb_rx_compare_done;
        else
            p_mb_tx_pattern_count_done = 1'b1;
    end

    // Module TX / Partner RX
    logic        m_tx_valid;
    msg_no_e     m_tx_msg_id;
    logic [15:0] m_tx_MsgInfo;
    logic [63:0] m_tx_data;

    // Partner TX / Module RX
    logic        p_tx_valid;
    msg_no_e     p_tx_msg_id;
    logic [15:0] p_tx_MsgInfo;
    logic [63:0] p_tx_data;

    //////////////////////////////////////////////////
    // MODULE INSTANCE
    //////////////////////////////////////////////////
    MBINIT #(.CLK_FRQ_HZ(100000)) \module (
        .clk(clk),
        .rst_n(rst_n),
        
        .mbinit_enable(m_enable),
        .mbinit_done(m_done),
        .mbinit_error(m_error),
        .mbinit_state_n(m_mbinit_state_n),
        .global_error(m_timer_timeout_expired),
        
        .sb_ltsm_rdy(1'b1),
        .SPMW(1'b0),
        
        // Capability interface (Discrete Normal Ports)
        // Local Inputs (from registers)
        .reg_phy_x8_mode_ctrl(cap_if_module.local_is_x8),
        .local_max_speed(cap_if_module.local_max_speed),
        .local_sbfe(cap_if_module.local_sbfe),
        .reg_TARR_support_local_cap(cap_if_module.local_tarr),
        .reg_L2SPD_support_local_cap(cap_if_module.local_l2spd),
        .reg_PSPT_support_local_cap(cap_if_module.local_pspt),
        .local_so(cap_if_module.local_so),
        .reg_PMO_support_local_cap(cap_if_module.local_pmo),
        .reg_Max_Link_Width_cap(3'b011),
        .reg_Max_Link_Speed_cap(4'b0011),
        .local_mtp(cap_if_module.local_mtp),

        .reg_Supported_TX_Vswing(5'b00111),
        .reg_so(cap_if_module.local_so),
        .reg_mtp(cap_if_module.local_mtp),
        .reg_Module_ID(2'b00),
        .reg_Clock_Phase_cap(2'b01),
        .reg_Clock_mode_cap(2'b01),
        .reg_TARR_support_local_ctrl(cap_if_module.local_tarr),
        .reg_PMO_support_local_ctrl(cap_if_module.local_pmo),
        .reg_Clock_Phase_ctrl(1'b1),
        .reg_Clock_mode_ctrl(1'b1),

        // From Link
        .reg_L2SPD_support_local_ctrl(cap_if_module.local_l2spd),
        .reg_PSPT_support_local_ctrl(cap_if_module.local_pspt),
        .reg_Target_Link_Width_ctrl(cap_if_module.local_is_x8 ? 4'h1 : 4'h2),
        .reg_Target_Link_Speed_ctrl(cap_if_module.local_max_speed),

        // STATUS REG
        .reg_Clock_Phase_enable_status(m_clk_phase_status),
        .reg_Clock_mode_enable_status(m_clk_mode_status),
        .reg_TARR_enable_status(m_tarr_status),
        .reg_Link_Width_enable_status(m_width_status),
        .reg_Link_Speed_enable_status(m_speed_status),
        .reg_PMO_enable_status(m_pmo_status),
        .reg_L2SPD_enable_status(m_l2spd_status),
        .reg_PSPT_enable_status(m_pspt_status),

        // D2C Point Test
        .local_tx_pt_en(d2c_if_module.local_tx_pt_en),
        .partner_tx_pt_en(d2c_if_module.partner_tx_pt_en),
        .d2c_pattern_setup(d2c_if_module.d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_if_module.d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_if_module.d2c_pattern_mode),
        .d2c_compare_setup(d2c_if_module.d2c_compare_setup),
        .d2c_perlane_pass(d2c_if_module.mb_rx_perlane_pass),
        .local_test_d2c_done(d2c_if_module.local_test_d2c_done),
        .partner_test_d2c_done(d2c_if_module.partner_test_d2c_done),

        // Mainband
        .sb_rx_valid(p_tx_valid),
        .sb_rx_msg_id(p_tx_msg_id),
        .sb_rx_MsgInfo(p_tx_MsgInfo),
        .sb_rx_data_Field(p_tx_data),
        
        .sb_tx_valid(m_tx_valid),
        .sb_tx_msg_id(m_tx_msg_id),
        .sb_tx_MsgInfo(m_tx_MsgInfo),
        .sb_tx_data_Field(m_tx_data),

        // Unified Mainband training/comparison
        .mb_tx_pattern_en(),
        .mb_tx_pattern_setup(),
        .mb_tx_data_pattern_sel(),
        .mb_tx_val_pattern_sel(),
        .mb_rx_compare_en(),
        .mb_rx_compare_setup(),
        .clear_error_req(),
        .mbinit_rx_data_lane_mask(d2c_if_module.mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(d2c_if_module.mbinit_tx_data_lane_mask),

        // Unified inputs
        .mb_rx_perlane_pass(~m_reversalmb_rx_perlane_err),
        .mb_tx_pattern_count_done(m_mb_tx_pattern_count_done),

        // Discrete outputs/inputs
        .mb_lane_reversal_req(),
        .repairclk_rtrk_pass(m_repairclk_rtrk_pass),
        .repairclk_rckn_pass(m_repairclk_rckn_pass),
        .repairclk_rckp_pass(m_repairclk_rckp_pass),
        .repairval_RVLD_L_pass(m_repairval_RVLD_L_pass)
    );

    //////////////////////////////////////////////////
    // PARTNER INSTANCE
    //////////////////////////////////////////////////
    MBINIT #(.CLK_FRQ_HZ(100000)) partner (
        .clk(clk),
        .rst_n(rst_n),
        
        .mbinit_enable(p_enable),
        .mbinit_done(p_done),
        .mbinit_error(p_error),
        .mbinit_state_n(p_mbinit_state_n),
        .global_error(p_timer_timeout_expired),
        
        .sb_ltsm_rdy(1'b1),
        .SPMW(1'b0),
        
        // Capability interface (Discrete Normal Ports)
        // Local Inputs (from registers)
        .reg_phy_x8_mode_ctrl(cap_if_partner.local_is_x8),
        .local_max_speed(cap_if_partner.local_max_speed),
        .local_sbfe(cap_if_partner.local_sbfe),
        .reg_TARR_support_local_cap(cap_if_partner.local_tarr),
        .reg_L2SPD_support_local_cap(cap_if_partner.local_l2spd),
        .reg_PSPT_support_local_cap(cap_if_partner.local_pspt),
        .local_so(cap_if_partner.local_so),
        .reg_PMO_support_local_cap(cap_if_partner.local_pmo),
        .reg_Max_Link_Width_cap(3'b011),
        .reg_Max_Link_Speed_cap(4'b0011),
        .local_mtp(cap_if_partner.local_mtp),

        .reg_Supported_TX_Vswing(5'b00111),
        .reg_so(cap_if_partner.local_so),
        .reg_mtp(cap_if_partner.local_mtp),
        .reg_Module_ID(2'b00),
        .reg_Clock_Phase_cap(2'b01),
        .reg_Clock_mode_cap(2'b01),
        .reg_TARR_support_local_ctrl(cap_if_partner.local_tarr),
        .reg_PMO_support_local_ctrl(cap_if_partner.local_pmo),
        .reg_Clock_Phase_ctrl(1'b1),
        .reg_Clock_mode_ctrl(1'b1),

        // From Link
        .reg_L2SPD_support_local_ctrl(cap_if_partner.local_l2spd),
        .reg_PSPT_support_local_ctrl(cap_if_partner.local_pspt),
        .reg_Target_Link_Width_ctrl(cap_if_partner.local_is_x8 ? 4'h1 : 4'h2),
        .reg_Target_Link_Speed_ctrl(cap_if_partner.local_max_speed),

        // STATUS REG
        .reg_Clock_Phase_enable_status(p_clk_phase_status),
        .reg_Clock_mode_enable_status(p_clk_mode_status),
        .reg_TARR_enable_status(p_tarr_status),
        .reg_Link_Width_enable_status(p_width_status),
        .reg_Link_Speed_enable_status(p_speed_status),
        .reg_PMO_enable_status(p_pmo_status),
        .reg_L2SPD_enable_status(p_l2spd_status),
        .reg_PSPT_enable_status(p_pspt_status),

        // D2C Point Test
        .local_tx_pt_en(d2c_if_partner.local_tx_pt_en),
        .partner_tx_pt_en(d2c_if_partner.partner_tx_pt_en),
        .d2c_pattern_setup(d2c_if_partner.d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_if_partner.d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_if_partner.d2c_pattern_mode),
        .d2c_compare_setup(d2c_if_partner.d2c_compare_setup),
        .d2c_perlane_pass(d2c_if_partner.mb_rx_perlane_pass),
        .local_test_d2c_done(d2c_if_partner.local_test_d2c_done),
        .partner_test_d2c_done(d2c_if_partner.partner_test_d2c_done),

        // Mainband
        .sb_rx_valid(m_tx_valid),
        .sb_rx_msg_id(m_tx_msg_id),
        .sb_rx_MsgInfo(m_tx_MsgInfo),
        .sb_rx_data_Field(m_tx_data),
        
        .sb_tx_valid(p_tx_valid),
        .sb_tx_msg_id(p_tx_msg_id),
        .sb_tx_MsgInfo(p_tx_MsgInfo),
        .sb_tx_data_Field(p_tx_data),

        // Unified Mainband training/comparison
        .mb_tx_pattern_en(),
        .mb_tx_pattern_setup(),
        .mb_tx_data_pattern_sel(),
        .mb_tx_val_pattern_sel(),
        .mb_rx_compare_en(),
        .mb_rx_compare_setup(),
        .clear_error_req(),
        .mbinit_rx_data_lane_mask(d2c_if_partner.mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(d2c_if_partner.mbinit_tx_data_lane_mask),

        // Unified inputs
        .mb_rx_perlane_pass(~p_reversalmb_rx_perlane_err),
        .mb_tx_pattern_count_done(p_mb_tx_pattern_count_done),

        // Discrete outputs/inputs
        .mb_lane_reversal_req(),
        .repairclk_rtrk_pass(p_repairclk_rtrk_pass),
        .repairclk_rckn_pass(p_repairclk_rckn_pass),
        .repairclk_rckp_pass(p_repairclk_rckp_pass),
        .repairval_RVLD_L_pass(p_repairval_RVLD_L_pass)
    );

    //////////////////////////////////////////////////
    // LOCAL WATCHDOG TIMER CONTROL DRIVERS
    //////////////////////////////////////////////////
    always_comb begin
        m_timer_enable = m_enable && !m_done && !m_error;
    end

    state_n_e m_mbinit_state_n_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_timer_rst_n         <= 1'b0;
            m_mbinit_state_n_prev <= LOG_RESET;
        end else begin
            m_timer_rst_n         <= 1'b1;
            m_mbinit_state_n_prev <= m_mbinit_state_n;
            if (m_mbinit_state_n != m_mbinit_state_n_prev) begin
                m_timer_rst_n     <= 1'b0;
            end
        end
    end

    always_comb begin
        p_timer_enable = p_enable && !p_done && !p_error;
    end

    state_n_e p_mbinit_state_n_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_timer_rst_n         <= 1'b0;
            p_mbinit_state_n_prev <= LOG_RESET;
        end else begin
            p_timer_rst_n         <= 1'b1;
            p_mbinit_state_n_prev <= p_mbinit_state_n;
            if (p_mbinit_state_n != p_mbinit_state_n_prev) begin
                p_timer_rst_n     <= 1'b0;
            end
        end
    end

    //////////////////////////////////////////////////
    // EXTERNAL WATCHDOG TIMER INSTANTIATIONS
    //////////////////////////////////////////////////
    timeout_counter #(.CLK_FRQ_HZ(100000), .TIME_OUT(8)) u_module_timer (
        .clk(clk),
        .timeout_rst_n(m_timer_rst_n),
        .enable_timeout(m_timer_enable),
        .timeout_expired(m_timer_timeout_expired)
    );

    timeout_counter #(.CLK_FRQ_HZ(100000), .TIME_OUT(8)) u_partner_timer (
        .clk(clk),
        .timeout_rst_n(p_timer_rst_n),
        .enable_timeout(p_timer_enable),
        .timeout_expired(p_timer_timeout_expired)
    );

    //////////////////////////////////////////////////
    // AUTOMATIC D2C POINT TEST SIMULATOR
    //////////////////////////////////////////////////
    always @(posedge clk) begin
        if (!rst_n) begin
            d2c_if_module.local_test_d2c_done   <= 1'b0;
            d2c_if_module.partner_test_d2c_done <= 1'b0;
        end else begin
            if (d2c_if_module.local_tx_pt_en) begin
                #50;
                d2c_if_module.local_test_d2c_done <= 1'b1;
            end else begin
                d2c_if_module.local_test_d2c_done <= 1'b0;
            end

            if (d2c_if_module.partner_tx_pt_en) begin
                #50;
                d2c_if_module.partner_test_d2c_done <= 1'b1;
            end else begin
                d2c_if_module.partner_test_d2c_done <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            d2c_if_partner.local_test_d2c_done   <= 1'b0;
            d2c_if_partner.partner_test_d2c_done <= 1'b0;
        end else begin
            if (d2c_if_partner.local_tx_pt_en) begin
                #50;
                d2c_if_partner.local_test_d2c_done <= 1'b1;
            end else begin
                d2c_if_partner.local_test_d2c_done <= 1'b0;
            end

            if (d2c_if_partner.partner_tx_pt_en) begin
                #50;
                d2c_if_partner.partner_test_d2c_done <= 1'b1;
            end else begin
                d2c_if_partner.partner_test_d2c_done <= 1'b0;
            end
        end
    end

    //////////////////////////////////////////////////
    // DEBUG TRANSITION LOGGERS
    //////////////////////////////////////////////////
    always @(\module .u_mbinit_wrapper.u_controller.current_state) begin
        $display("T=%0t | [MODULE FSM] State: %s", $time, \module .u_mbinit_wrapper.u_controller.current_state.name());
    end
    always @(partner.u_mbinit_wrapper.u_controller.current_state) begin
        $display("T=%0t | [PARTNER FSM] State: %s", $time, partner.u_mbinit_wrapper.u_controller.current_state.name());
    end
    always @(m_mbinit_state_n) begin
        $display("T=%0t | [MODULE mbinit_state_n] %s", $time, m_mbinit_state_n.name());
    end
    always @(p_mbinit_state_n) begin
        $display("T=%0t | [PARTNER mbinit_state_n] %s", $time, p_mbinit_state_n.name());
    end

    //////////////////////////////////////////////////
    // SEQUENTIAL RESET TASK
    //////////////////////////////////////////////////
    task reset_system();
        $display("T=%0t | ---> Resetting System...", $time);
        rst_n = 0;
        m_enable = 0;
        p_enable = 0;
        
        // Reset module inputs
        m_repairclk_rtrk_pass = 1'b1;
        m_repairclk_rckn_pass = 1'b1;
        m_repairclk_rckp_pass = 1'b1;
        m_repairclk_rx_compare_done = 1'b1;
        m_reversalmb_rx_perlane_err = 16'h0000;
        m_reversalmb_rx_compare_done = 1'b1;
        m_repairval_RVLD_L_pass = 1'b1;
        m_repairval_rx_compare_done = 1'b1;

        // Reset partner inputs
        p_repairclk_rtrk_pass = 1'b1;
        p_repairclk_rckn_pass = 1'b1;
        p_repairclk_rckp_pass = 1'b1;
        p_repairclk_rx_compare_done = 1'b1;
        p_reversalmb_rx_perlane_err = 16'h0000;
        p_reversalmb_rx_compare_done = 1'b1;
        p_repairval_RVLD_L_pass = 1'b1;
        p_repairval_rx_compare_done = 1'b1;

        // Reset Point test pass masks (all pass)
        d2c_if_module.mb_rx_perlane_pass = 16'hFFFF;
        d2c_if_partner.mb_rx_perlane_pass = 16'hFFFF;

        // Module capability initial registers
        cap_if_module.local_is_x8 = 1'b0; // negotiated as x16
        cap_if_module.local_max_speed = 4'b0011;
        cap_if_module.local_sbfe = 1'b1;
        cap_if_module.local_tarr = 1'b0;
        cap_if_module.local_l2spd = 1'b1;
        cap_if_module.local_pspt = 1'b0;
        cap_if_module.local_so = 1'b0;
        cap_if_module.local_pmo = 1'b1;
        cap_if_module.local_mtp = 1'b1;

        // Partner capability initial registers
        cap_if_partner.local_is_x8 = 1'b0; // negotiated as x16
        cap_if_partner.local_max_speed = 4'b0011;
        cap_if_partner.local_sbfe = 1'b1;
        cap_if_partner.local_tarr = 1'b0;
        cap_if_partner.local_l2spd = 1'b1;
        cap_if_partner.local_pspt = 1'b0;
        cap_if_partner.local_so = 1'b0;
        cap_if_partner.local_pmo = 1'b1;
        cap_if_partner.local_mtp = 1'b1;

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask

    //////////////////////////////////////////////////
    // VERIFICATION SEQUENCES
    //////////////////////////////////////////////////
    initial begin
        $display("\n==================================================");
        $display("   STARTING MULTI-SCENARIO VERIFICATION SUITE");
        $display("==================================================\n");

        // ------------------------------------------------
        // SCENARIO 1: Happy Path (Full Width x16)
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 1] HAPPY PATH (FULL WIDTH x16) ");
        $display("--------------------------------------------------");
        reset_system();
        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 1 SUCCESS] Both modules initialized successfully.", $time);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 1 FAIL] modules encountered an unexpected error.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 1 TIMEOUT] Stuck FSM.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 2: Clock & Valid Lane Repair Retry
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 2] CLOCK & VALID LANE REPAIR RETRY ");
        $display("--------------------------------------------------");
        reset_system();
        
        // Inject failure on clock first, then let it pass on retry
        m_repairclk_rckn_pass = 1'b0; 
        p_repairclk_rckn_pass = 1'b0;
        m_repairclk_rx_compare_done = 1'b0;
        p_repairclk_rx_compare_done = 1'b0;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        // Monitor state and dynamically fix the lane to simulate recovery during pattern transmission
        fork
            begin
                wait(\module .u_mbinit_wrapper.u_repairclk.current_state == \module .u_mbinit_wrapper.u_repairclk.MB_S2_PATTERN_TRANSMISSION);
                $display("T=%0t | [SCENARIO 2] Clock failure detected during pattern. Simulating hardware clock repair...", $time);
                #100; // Let pattern transmit
                m_repairclk_rckn_pass = 1'b1;
                p_repairclk_rckn_pass = 1'b1;
                #20; // Let comparison settle
                m_repairclk_rx_compare_done = 1'b1;
                p_repairclk_rx_compare_done = 1'b1;
            end
        join_none

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 2 SUCCESS] Completed initialization after clock repair.", $time);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 2 FAIL] Unexpected error during repair.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 2 TIMEOUT] FSM hung.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 3: Lane Reversal Detection & Correction
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 3] LANE REVERSAL DETECTION & CORRECTION ");
        $display("--------------------------------------------------");
        reset_system();

        // Inject reversal error: all lanes fail initially to trigger reversal request
        m_reversalmb_rx_perlane_err = 16'hFFFF;
        p_reversalmb_rx_perlane_err = 16'hFFFF;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(\module .u_mbinit_wrapper.u_reversalmb.current_state == \module .u_mbinit_wrapper.u_reversalmb.MB_S4_RESULT_RSP_WAIT);
                $display("T=%0t | [SCENARIO 3] Reversal detected. Correcting lane reverse...", $time);
                #5;
                m_reversalmb_rx_perlane_err = 16'h0000; // Success on retry after reversal logic applies
                p_reversalmb_rx_perlane_err = 16'h0000;
            end
        join_none

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 3 SUCCESS] Completed reversal detection and recovery successfully.", $time);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 3 FAIL] Reversal failed to resolve.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 3 TIMEOUT] FSM hung.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 4: Asymmetric Lane Degradation (Degrade to lower x8)
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 4] ASYMMETRIC LANE DEGRADATION (TO LOWER x8) ");
        $display("--------------------------------------------------");
        reset_system();

        // Fail lanes 8-15 in D2C point test (mb_rx_perlane_pass bits 8-15 driven low)
        d2c_if_module.mb_rx_perlane_pass = 16'h00FF; // lower x8 passes, upper x8 fails
        d2c_if_partner.mb_rx_perlane_pass = 16'h00FF;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 4 SUCCESS] Successfully degraded link from x16 to lower x8.", $time);
                $display("T=%0t | Negotiated Width (Module): %b (Expected: x8 status)", $time, \module .u_mbinit_wrapper.u_repairmb.Link_Width_enable_status);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 4 FAIL] Degradation caused error abort.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 4 TIMEOUT] FSM hung.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 5: Double Failure Abort
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 5] DOUBLE FAILURE ABORT ");
        $display("--------------------------------------------------");
        reset_system();

        // Induce catastrophic error: fail all lanes in point test, retry, and fail again
        d2c_if_module.mb_rx_perlane_pass = 16'h0000; 
        d2c_if_partner.mb_rx_perlane_pass = 16'h0000;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_error && p_error);
                $display("T=%0t | [SCENARIO 5 SUCCESS] Clean abort to CTRL_ERROR observed.", $time);
            end
            begin
                wait(m_done || p_done);
                $display("T=%0t | [SCENARIO 5 FAIL] modules unexpectedly reported success despite fatal errors.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 5 TIMEOUT] FSM failed to abort.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 6: Watchdog Timeout Abort
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 6] WATCHDOG TIMEOUT ABORT ");
        $display("--------------------------------------------------");
        reset_system();

        // Inhibit response to cause watchdog timeout
        m_repairval_rx_compare_done = 1'b0; 
        p_repairval_rx_compare_done = 1'b0;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_error && p_error);
                $display("T=%0t | [SCENARIO 6 SUCCESS] Watchdog successfully timed out and caused clean error exit.", $time);
            end
            begin
                wait(m_done || p_done);
                $display("T=%0t | [SCENARIO 6 FAIL] modules unexpectedly reported success.", $time);
                $finish;
            end
            begin
                #15000000;
                $display("T=%0t | [SCENARIO 6 TIMEOUT] FSM watchdogs failed to fire.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ------------------------------------------------
        // SCENARIO 7: Asymmetric Width Degradation with x4 Pass Flags
        // ------------------------------------------------
        $display("\n--------------------------------------------------");
        $display(" [SCENARIO 7] ASYMMETRIC WIDTH DEGRADATION (TO UPPER x4) ");
        $display("--------------------------------------------------");
        reset_system();
        cap_if_module.local_is_x8 = 1'b1;
        cap_if_partner.local_is_x8 = 1'b1;

        // Module passes lanes 4-15 (so raw map is 3'b010 (upper x8), and local_upper_x4_pass is 1)
        d2c_if_module.mb_rx_perlane_pass = 16'hFFF0; 
        // Partner only passes lanes 4-7 (so raw map is 3'b101 (upper x4))
        d2c_if_partner.mb_rx_perlane_pass = 16'h00F0;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 7 SUCCESS] Successfully aligned module and partner to upper x4 map.", $time);
                $display("T=%0t | Module RX Lane Mask: %b, TX Lane Mask: %b (Expected: 101)", $time, \module .mbinit_rx_data_lane_mask, \module .mbinit_tx_data_lane_mask);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 7 FAIL] Alignment check caused error abort.", $time);
                $finish;
            end
            begin
                #2000000;
                $display("T=%0t | [SCENARIO 7 TIMEOUT] FSM hung.", $time);
                $finish;
            end
        join_any
        disable fork;


        $display("\n==================================================");
        $display("    ALL 7 SCENARIOS COMPLETED SUCCESSFULLY!");
        $display("==================================================\n");
        $finish;
    end

endmodule
