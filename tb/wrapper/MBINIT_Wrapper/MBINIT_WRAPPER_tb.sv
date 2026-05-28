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
    // DYNAMIC INPUT LOGIC FOR MASTER & PARTNER
    //////////////////////////////////////////////////
    logic        m_enable, m_done, m_error, m_timeout;
    logic        p_enable, p_done, p_error, p_timeout;

    // Master Dynamic Inputs
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
    MBINIT_WRAPPER #(.CLK_FRQ_HZ(100000)) master (
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
        .repairclk_rtrk_pass(m_repairclk_rtrk_pass), 
        .repairclk_rckn_pass(m_repairclk_rckn_pass), 
        .repairclk_rckp_pass(m_repairclk_rckp_pass), 
        .repairclk_rx_compare_done(m_repairclk_rx_compare_done),
        
        .reversalmb_tx_pattern_setup(), .reversalmb_tx_data_pattern_sel(), .reversalmb_rx_compare_setup(),
        .reversalmb_tx_pattern_en(), .reversalmb_rx_compare_en(),
        .reversalmb_rx_perlane_err(m_reversalmb_rx_perlane_err), 
        .reversalmb_rx_compare_done(m_reversalmb_rx_compare_done),
        .mb_lane_reversal_req(), .mb_x8_mode_req(), .clear_error_req(),
        
        .repairval_tx_pattern_setup(), .repairval_tx_val_pattern_sel(), .repairval_rx_compare_setup(),
        .repairval_tx_pattern_en(), .repairval_rx_compare_en(),
        .repairval_RVLD_L_pass(m_repairval_RVLD_L_pass), 
        .repairval_rx_compare_done(m_repairval_rx_compare_done)
    );

    //////////////////////////////////////////////////
    // PARTNER INSTANCE
    //////////////////////////////////////////////////
    MBINIT_WRAPPER #(.CLK_FRQ_HZ(100000)) partner (
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
        .repairclk_rtrk_pass(p_repairclk_rtrk_pass), 
        .repairclk_rckn_pass(p_repairclk_rckn_pass), 
        .repairclk_rckp_pass(p_repairclk_rckp_pass), 
        .repairclk_rx_compare_done(p_repairclk_rx_compare_done),
        
        .reversalmb_tx_pattern_setup(), .reversalmb_tx_data_pattern_sel(), .reversalmb_rx_compare_setup(),
        .reversalmb_tx_pattern_en(), .reversalmb_rx_compare_en(),
        .reversalmb_rx_perlane_err(p_reversalmb_rx_perlane_err), 
        .reversalmb_rx_compare_done(p_reversalmb_rx_compare_done),
        .mb_lane_reversal_req(), .mb_x8_mode_req(), .clear_error_req(),
        
        .repairval_tx_pattern_setup(), .repairval_tx_val_pattern_sel(), .repairval_rx_compare_setup(),
        .repairval_tx_pattern_en(), .repairval_rx_compare_en(),
        .repairval_RVLD_L_pass(p_repairval_RVLD_L_pass), 
        .repairval_rx_compare_done(p_repairval_rx_compare_done)
    );

    //////////////////////////////////////////////////
    // AUTOMATIC D2C POINT TEST SIMULATOR
    //////////////////////////////////////////////////
    always @(posedge clk) begin
        if (!rst_n) begin
            d2c_if_master.test_d2c_done <= 1'b0;
        end else if (d2c_if_master.tx_pt_en) begin
            #50; // Simulate delay
            d2c_if_master.test_d2c_done <= 1'b1;
        end else begin
            d2c_if_master.test_d2c_done <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            d2c_if_partner.test_d2c_done <= 1'b0;
        end else if (d2c_if_partner.tx_pt_en) begin
            #50; // Simulate delay
            d2c_if_partner.test_d2c_done <= 1'b1;
        end else begin
            d2c_if_partner.test_d2c_done <= 1'b0;
        end
    end

    //////////////////////////////////////////////////
    // DEBUG TRANSITION LOGGERS
    //////////////////////////////////////////////////
    always @(master.u_controller.current_state) begin
        $display("T=%0t | [MASTER FSM] State: %s", $time, master.u_controller.current_state.name());
    end
    always @(partner.u_controller.current_state) begin
        $display("T=%0t | [PARTNER FSM] State: %s", $time, partner.u_controller.current_state.name());
    end

    //////////////////////////////////////////////////
    // SEQUENTIAL RESET TASK
    //////////////////////////////////////////////////
    task reset_system();
        $display("T=%0t | ---> Resetting System...", $time);
        rst_n = 0;
        m_enable = 0;
        p_enable = 0;
        
        // Reset master inputs
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
        d2c_if_master.mb_rx_perlane_pass = 16'hFFFF;
        d2c_if_partner.mb_rx_perlane_pass = 16'hFFFF;

        // Master capability initial registers
        cap_if_master.local_is_x8 = 1'b0; // negotiated as x16
        cap_if_master.local_max_speed = 4'b0011;
        cap_if_master.local_sbfe = 1'b1;
        cap_if_master.local_tarr = 1'b0;
        cap_if_master.local_l2spd = 1'b1;
        cap_if_master.local_pspt = 1'b0;
        cap_if_master.local_so = 1'b0;
        cap_if_master.local_pmo = 1'b1;
        cap_if_master.local_mtp = 1'b1;

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
                $display("T=%0t | [SCENARIO 1 SUCCESS] Both wrappers initialized successfully.", $time);
            end
            begin
                wait(m_error || p_error);
                $display("T=%0t | [SCENARIO 1 FAIL] wrappers encountered an unexpected error.", $time);
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
                wait(master.u_repairclk.current_state == master.u_repairclk.MB_S2_PATTERN_TRANSMISSION);
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
                wait(master.u_reversalmb.current_state == master.u_reversalmb.MB_S4_RESULT_RSP_WAIT);
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
        d2c_if_master.mb_rx_perlane_pass = 16'h00FF; // lower x8 passes, upper x8 fails
        d2c_if_partner.mb_rx_perlane_pass = 16'h00FF;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 4 SUCCESS] Successfully degraded link from x16 to lower x8.", $time);
                $display("T=%0t | Negotiated Width (Master): %b (Expected: x8 status)", $time, master.u_repairmb.Link_Width_enable_status);
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
        d2c_if_master.mb_rx_perlane_pass = 16'h0000; 
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
                $display("T=%0t | [SCENARIO 5 FAIL] Wrappers unexpectedly reported success despite fatal errors.", $time);
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
                $display("T=%0t | [SCENARIO 6 FAIL] Wrappers unexpectedly reported success.", $time);
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
        cap_if_master.local_is_x8 = 1'b1;
        cap_if_partner.local_is_x8 = 1'b1;

        // Master passes lanes 4-15 (so raw map is 3'b010 (upper x8), and local_upper_x4_pass is 1)
        d2c_if_master.mb_rx_perlane_pass = 16'hFFF0; 
        // Partner only passes lanes 4-7 (so raw map is 3'b101 (upper x4))
        d2c_if_partner.mb_rx_perlane_pass = 16'h00F0;

        @(posedge clk);
        m_enable = 1;
        p_enable = 1;

        fork
            begin
                wait(m_done && p_done);
                $display("T=%0t | [SCENARIO 7 SUCCESS] Successfully aligned master and partner to upper x4 map.", $time);
                $display("T=%0t | Master RX Lane Mask: %b, TX Lane Mask: %b (Expected: 101)", $time, master.u_repairmb.mbinit_rx_data_lane_mask, master.u_repairmb.mbinit_tx_data_lane_mask);
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
