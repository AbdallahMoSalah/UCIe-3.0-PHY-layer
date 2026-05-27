`timescale 1ns/1ps
import UCIe_pkg::*;

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
    ucie_mb_cap_if cap_if_master();
    ucie_mb_cap_if cap_if_partner();

    internal_ltsm_if d2c_if_master(.lclk(clk), .rst_n(rst_n));
    internal_ltsm_if d2c_if_partner(.lclk(clk), .rst_n(rst_n));

    //////////////////////////////////////////////////
    // SIGNALS
    //////////////////////////////////////////////////
    logic m_enable, m_done, m_error, m_timeout;
    logic p_enable, p_done, p_error, p_timeout;

    // Master TX / Partner RX
    logic        m_tx_valid;
    msg_no_e     m_tx_msg_id;
    logic [15:0] m_tx_MsgInfo;
    logic [63:0] m_tx_data;

    // Partner TX / Master RX
    logic        p_tx_valid;
    msg_no_e     p_tx_msg_id;
    logic [15:0] p_tx_MsgInfo;
    logic [63:0] p_tx_data;

    //////////////////////////////////////////////////
    // MASTER INSTANCE
    //////////////////////////////////////////////////
    MBINIT_WRAPPER master (
        .clk(clk),
        .rst_n(rst_n),
        
        .mbinit_enable(m_enable),
        .mbinit_done(m_done),
        .mbinit_error(m_error),
        .timeout_error(m_timeout),
        
        .ltsm_rdy(1'b1),
        .SPMW(1'b0),
        
        // Local Inputs
        .local_is_x8(cap_if_master.local_is_x8),
        .local_max_speed(cap_if_master.local_max_speed),
        .local_sbfe(cap_if_master.local_sbfe),
        .local_tarr(cap_if_master.local_tarr),
        .local_l2spd(cap_if_master.local_l2spd),
        .local_pspt(cap_if_master.local_pspt),
        .local_so(cap_if_master.local_so),
        .local_pmo(cap_if_master.local_pmo),
        .local_mtp(cap_if_master.local_mtp),
        
        // Partner Outputs
        .partner_is_x8(cap_if_master.partner_is_x8),
        .partner_max_speed(cap_if_master.partner_max_speed),
        .partner_sbfe(cap_if_master.partner_sbfe),
        .partner_tarr(cap_if_master.partner_tarr),
        .partner_l2spd(cap_if_master.partner_l2spd),
        .partner_pspt(cap_if_master.partner_pspt),
        .partner_so(cap_if_master.partner_so),
        .partner_pmo(cap_if_master.partner_pmo),
        .partner_mtp(cap_if_master.partner_mtp),
        
        // Negotiated Outputs
        .use_x8_mode(cap_if_master.use_x8_mode),
        .negotiated_speed(cap_if_master.negotiated_speed),
        .negotiated_sbfe(cap_if_master.negotiated_sbfe),
        .negotiated_tarr(cap_if_master.negotiated_tarr),
        .negotiated_l2spd(cap_if_master.negotiated_l2spd),
        .negotiated_pspt(cap_if_master.negotiated_pspt),
        .negotiated_so(cap_if_master.negotiated_so),
        .negotiated_pmo(cap_if_master.negotiated_pmo),
        .negotiated_mtp(cap_if_master.negotiated_mtp),
        
        .d2c_test_if(d2c_if_master),
        
        .mb_rx_valid(p_tx_valid),
        .mb_rx_msg_id(p_tx_msg_id),
        .mb_rx_MsgInfo(p_tx_MsgInfo),
        .mb_rx_data_Field(p_tx_data),
        
        .mb_tx_valid(m_tx_valid),
        .mb_tx_msg_id(m_tx_msg_id),
        .mb_tx_MsgInfo(m_tx_MsgInfo),
        .mb_tx_data_Field(m_tx_data),
        
        .repairclk_tx_pattern_setup(), .repairclk_tx_clk_pattern_sel(), .repairclk_rx_compare_setup(),
        .repairclk_tx_pattern_en(), .repairclk_rx_compare_en(),
        .repairclk_rtrk_pass(1'b1), .repairclk_rckn_pass(1'b1), .repairclk_rckp_pass(1'b1), .repairclk_rx_compare_done(1'b1),
        
        .reversalmb_tx_pattern_setup(), .reversalmb_tx_data_pattern_sel(), .reversalmb_rx_compare_setup(),
        .reversalmb_tx_pattern_en(), .reversalmb_rx_compare_en(),
        .reversalmb_rx_perlane_err(16'h0000), .reversalmb_rx_compare_done(1'b1),
        .mb_lane_reversal_req(), .mb_x8_mode_req(), .clear_error_req(),
        
        .repairval_tx_pattern_setup(), .repairval_tx_val_pattern_sel(), .repairval_rx_compare_setup(),
        .repairval_tx_pattern_en(), .repairval_rx_compare_en(),
        .repairval_RVLD_L_pass(1'b1), .repairval_rx_compare_done(1'b1)
    );

    //////////////////////////////////////////////////
    // PARTNER INSTANCE
    //////////////////////////////////////////////////
    MBINIT_WRAPPER partner (
        .clk(clk),
        .rst_n(rst_n),
        
        .mbinit_enable(p_enable),
        .mbinit_done(p_done),
        .mbinit_error(p_error),
        .timeout_error(p_timeout),
        
        .ltsm_rdy(1'b1),
        .SPMW(1'b0),
        
        // Local Inputs
        .local_is_x8(cap_if_partner.local_is_x8),
        .local_max_speed(cap_if_partner.local_max_speed),
        .local_sbfe(cap_if_partner.local_sbfe),
        .local_tarr(cap_if_partner.local_tarr),
        .local_l2spd(cap_if_partner.local_l2spd),
        .local_pspt(cap_if_partner.local_pspt),
        .local_so(cap_if_partner.local_so),
        .local_pmo(cap_if_partner.local_pmo),
        .local_mtp(cap_if_partner.local_mtp),
        
        // Partner Outputs
        .partner_is_x8(cap_if_partner.partner_is_x8),
        .partner_max_speed(cap_if_partner.partner_max_speed),
        .partner_sbfe(cap_if_partner.partner_sbfe),
        .partner_tarr(cap_if_partner.partner_tarr),
        .partner_l2spd(cap_if_partner.partner_l2spd),
        .partner_pspt(cap_if_partner.partner_pspt),
        .partner_so(cap_if_partner.partner_so),
        .partner_pmo(cap_if_partner.partner_pmo),
        .partner_mtp(cap_if_partner.partner_mtp),
        
        // Negotiated Outputs
        .use_x8_mode(cap_if_partner.use_x8_mode),
        .negotiated_speed(cap_if_partner.negotiated_speed),
        .negotiated_sbfe(cap_if_partner.negotiated_sbfe),
        .negotiated_tarr(cap_if_partner.negotiated_tarr),
        .negotiated_l2spd(cap_if_partner.negotiated_l2spd),
        .negotiated_pspt(cap_if_partner.negotiated_pspt),
        .negotiated_so(cap_if_partner.negotiated_so),
        .negotiated_pmo(cap_if_partner.negotiated_pmo),
        .negotiated_mtp(cap_if_partner.negotiated_mtp),
        
        .d2c_test_if(d2c_if_partner),
        
        .mb_rx_valid(m_tx_valid),
        .mb_rx_msg_id(m_tx_msg_id),
        .mb_rx_MsgInfo(m_tx_MsgInfo),
        .mb_rx_data_Field(m_tx_data),
        
        .mb_tx_valid(p_tx_valid),
        .mb_tx_msg_id(p_tx_msg_id),
        .mb_tx_MsgInfo(p_tx_MsgInfo),
        .mb_tx_data_Field(p_tx_data),
        
        .repairclk_tx_pattern_setup(), .repairclk_tx_clk_pattern_sel(), .repairclk_rx_compare_setup(),
        .repairclk_tx_pattern_en(), .repairclk_rx_compare_en(),
        .repairclk_rtrk_pass(1'b1), .repairclk_rckn_pass(1'b1), .repairclk_rckp_pass(1'b1), .repairclk_rx_compare_done(1'b1),
        
        .reversalmb_tx_pattern_setup(), .reversalmb_tx_data_pattern_sel(), .reversalmb_rx_compare_setup(),
        .reversalmb_tx_pattern_en(), .reversalmb_rx_compare_en(),
        .reversalmb_rx_perlane_err(16'h0000), .reversalmb_rx_compare_done(1'b1),
        .mb_lane_reversal_req(), .mb_x8_mode_req(), .clear_error_req(),
        
        .repairval_tx_pattern_setup(), .repairval_tx_val_pattern_sel(), .repairval_rx_compare_setup(),
        .repairval_tx_pattern_en(), .repairval_rx_compare_en(),
        .repairval_RVLD_L_pass(1'b1), .repairval_rx_compare_done(1'b1)
    );

    // =========================================================================
    // DEBUG TRANSITION LOGGERS
    // =========================================================================
    always @(master.u_controller.current_state) begin
        $display("T=%0t | [MASTER FSM] State: %s", $time, master.u_controller.current_state.name());
    end
    always @(partner.u_controller.current_state) begin
        $display("T=%0t | [PARTNER FSM] State: %s", $time, partner.u_controller.current_state.name());
    end

    always @(master.u_param.current_state) begin
        $display("T=%0t |   [MASTER PARAM] State: %s", $time, master.u_param.current_state.name());
    end
    always @(partner.u_param.current_state) begin
        $display("T=%0t |   [PARTNER PARAM] State: %s", $time, partner.u_param.current_state.name());
    end

    always @(master.u_cal.current_state) begin
        $display("T=%0t |   [MASTER CAL] State: %s", $time, master.u_cal.current_state.name());
    end
    always @(partner.u_cal.current_state) begin
        $display("T=%0t |   [PARTNER CAL] State: %s", $time, partner.u_cal.current_state.name());
    end

    always @(master.u_repairclk.current_state) begin
        $display("T=%0t |   [MASTER REPAIRCLK] State: %s", $time, master.u_repairclk.current_state.name());
    end
    always @(partner.u_repairclk.current_state) begin
        $display("T=%0t |   [PARTNER REPAIRCLK] State: %s", $time, partner.u_repairclk.current_state.name());
    end

    always @(master.u_reversalmb.current_state) begin
        $display("T=%0t |   [MASTER REVERSAL] State: %s", $time, master.u_reversalmb.current_state.name());
    end
    always @(partner.u_reversalmb.current_state) begin
        $display("T=%0t |   [PARTNER REVERSAL] State: %s", $time, partner.u_reversalmb.current_state.name());
    end

    always @(master.u_repairmb.current_state) begin
        $display("T=%0t |   [MASTER REPAIR] State: %s", $time, master.u_repairmb.current_state.name());
    end
    always @(partner.u_repairmb.current_state) begin
        $display("T=%0t |   [PARTNER REPAIR] State: %s", $time, partner.u_repairmb.current_state.name());
    end

    //////////////////////////////////////////////////
    // TEST SEQUENCE
    //////////////////////////////////////////////////
    initial begin
        rst_n = 0;
        m_enable = 0;
        p_enable = 0;
        
        // Drive d2c test interface for REPAIRMB
        // test_d2c_done=1 simulates instant D2C point test completion
        // d2c_perlane_err=0 means all lanes pass
        d2c_if_master.test_d2c_done = 1;
        d2c_if_master.d2c_perlane_err = 16'h0000;
        d2c_if_partner.test_d2c_done = 1;
        d2c_if_partner.d2c_perlane_err = 16'h0000;
        
        // Initialize Master capabilities
        cap_if_master.local_is_x8 = 1'b0;
        cap_if_master.local_max_speed = 4'b0011;
        cap_if_master.local_sbfe = 1'b1;
        cap_if_master.local_tarr = 1'b0;
        cap_if_master.local_l2spd = 1'b1;
        cap_if_master.local_pspt = 1'b0;
        cap_if_master.local_so = 1'b0;
        cap_if_master.local_pmo = 1'b1;
        cap_if_master.local_mtp = 1'b1;

        // Initialize Partner capabilities
        cap_if_partner.local_is_x8 = 1'b0;
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
        
        // Assert enable for both wrappers
        $display("T=%0t | Activating MBINIT Wrappers...", $time);
        @(posedge clk);
        m_enable = 1;
        p_enable = 1;
        
        // Wait for done or error
        fork
            begin
                wait((m_done && p_done) || (m_error || p_error));
                if (m_done && p_done)
                    $display("T=%0t | TEST PASSED! Both Wrappers completed initialization.", $time);
                else
                    $display("T=%0t | TEST FAILED! Wrappers hit an error state.", $time);
            end
            begin
                repeat(50000) @(posedge clk);
                $display("T=%0t | TEST TIMEOUT! State machine stuck.", $time);
            end
        join_any
        
        $finish;
    end

endmodule
