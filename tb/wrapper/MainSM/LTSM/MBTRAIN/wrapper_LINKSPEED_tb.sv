`timescale 1ps/1ps
module wrapper_LINKSPEED_tb;

    import UCIe_pkg::*;

    // =========================================================================
    // 1. Parameters for Fast and Configurable Testbench Running
    // =========================================================================
    parameter LCLK_PERIOD          = 1*1000 ; // That means lclk period = 1ns (1GHz)
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait the analog circuits in the MB to settle.
    parameter SB_DELAY             = 20     ; // Delay in lclk cycles.
    parameter MB_DELAY             = 10     ; // Representing 128 lclk + 2 lclk delay
    parameter TIMEOUT_CYCLES       = 1_000_000;
    parameter bit ENABLE_RAND_LOG  = 1'b0; // 1: display details of randomized scenarios in terminal; 0: suppress

    // =========================================================================
    // Clock and Reset Signals
    // =========================================================================
    logic lclk = 0;
    logic rst_n = 0;

    always #(LCLK_PERIOD/2) lclk = ~lclk;

    task automatic assert_reset();
        rst_n = 0;
        #(LCLK_PERIOD * 5);
        rst_n = 1;
        #(LCLK_PERIOD * 5);
    endtask

    // =========================================================================
    // Interfaces & Attachments
    // =========================================================================
    ltsm_tb_if dut_if (lclk, rst_n);
    ltsm_tb_if ptn_if (lclk, rst_n);

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .ENABLE_LOOPBACK     (1'b0)
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .ENABLE_LOOPBACK     (1'b0)
    ) ptn_attach (
        .intf(ptn_if)
    );

    // =========================================================================
    // Control / Simulation Configuration Registers
    // =========================================================================
    logic is_ltsm_out_of_reset = 1;
    logic is_high_speed = 1;
    logic is_continuous_clk_mode = 0;

    logic [15:0] dut_active_rx_lanes = 16'hFFFF;
    logic [3:0]  dut_rf_ctrl_target_link_width = 4'h2;
    logic        dut_rf_cap_SPMW = 1'b0;
    logic        dut_PHY_IN_RETRAIN = 0;
    logic        dut_params_changed = 0;
    logic [15:0] dut_linkspeed_success_lanes;

    logic [15:0] ptn_active_rx_lanes = 16'hFFFF;
    logic [3:0]  ptn_rf_ctrl_target_link_width = 4'h2;
    logic        ptn_rf_cap_SPMW = 1'b0;
    logic        ptn_PHY_IN_RETRAIN = 0;
    logic        ptn_params_changed = 0;
    logic [15:0] ptn_linkspeed_success_lanes;

    // Testbench sideband injection for Die B (Partner)
    logic        tb_ptn_inject_valid = 0;
    logic [7:0]  tb_ptn_inject_msg   = 0;
    logic [15:0] tb_ptn_inject_info  = 0;

    logic        tb_dut_inject_valid = 0;
    logic [7:0]  tb_dut_inject_msg   = 0;
    logic [15:0] tb_dut_inject_info  = 0;

    // =========================================================================
    // Sideband Delay Queue (Connecting Die A and Die B with SB_DELAY)
    // =========================================================================
    reg [SB_DELAY-1:0] dut2ptn_valid_sr = 0;
    reg [7:0]  dut2ptn_msg_sr  [0:SB_DELAY-1];
    reg [15:0] dut2ptn_info_sr [0:SB_DELAY-1];
    reg [63:0] dut2ptn_data_sr [0:SB_DELAY-1];

    reg [SB_DELAY-1:0] ptn2dut_valid_sr = 0;
    reg [7:0]  ptn2dut_msg_sr  [0:SB_DELAY-1];
    reg [15:0] ptn2dut_info_sr [0:SB_DELAY-1];
    reg [63:0] ptn2dut_data_sr [0:SB_DELAY-1];

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            dut2ptn_valid_sr <= 0;
            ptn2dut_valid_sr <= 0;
            for (pi = 0; pi < SB_DELAY; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= 0;
                dut2ptn_info_sr[pi] <= 0;
                dut2ptn_data_sr[pi] <= 0;
                ptn2dut_msg_sr[pi]  <= 0;
                ptn2dut_info_sr[pi] <= 0;
                ptn2dut_data_sr[pi] <= 0;
            end
        end else begin
            // Shift queue
            dut2ptn_valid_sr <= {dut2ptn_valid_sr[SB_DELAY-2:0], dut_if.tb_muxed_tx_sb_msg_valid | tb_dut_inject_valid};
            ptn2dut_valid_sr <= {ptn2dut_valid_sr[SB_DELAY-2:0], ptn_if.tb_muxed_tx_sb_msg_valid | tb_ptn_inject_valid};

            for (pi = 1; pi < SB_DELAY; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= dut2ptn_msg_sr[pi-1];
                dut2ptn_info_sr[pi] <= dut2ptn_info_sr[pi-1];
                dut2ptn_data_sr[pi] <= dut2ptn_data_sr[pi-1];
                ptn2dut_msg_sr[pi]  <= ptn2dut_msg_sr[pi-1];
                ptn2dut_info_sr[pi] <= ptn2dut_info_sr[pi-1];
                ptn2dut_data_sr[pi] <= ptn2dut_data_sr[pi-1];
            end

            // Insert new inputs
            if (tb_dut_inject_valid) begin
                dut2ptn_msg_sr[0]  <= tb_dut_inject_msg;
                dut2ptn_info_sr[0] <= tb_dut_inject_info;
                dut2ptn_data_sr[0] <= 64'h0;
            end else begin
                dut2ptn_msg_sr[0]  <= dut_if.tb_muxed_tx_sb_msg;
                dut2ptn_info_sr[0] <= dut_if.tb_muxed_tx_msginfo;
                dut2ptn_data_sr[0] <= dut_if.tb_muxed_tx_data_field;
            end

            if (tb_ptn_inject_valid) begin
                ptn2dut_msg_sr[0]  <= tb_ptn_inject_msg;
                ptn2dut_info_sr[0] <= tb_ptn_inject_info;
                ptn2dut_data_sr[0] <= 64'h0;
            end else begin
                ptn2dut_msg_sr[0]  <= ptn_if.tb_muxed_tx_sb_msg;
                ptn2dut_info_sr[0] <= ptn_if.tb_muxed_tx_msginfo;
                ptn2dut_data_sr[0] <= ptn_if.tb_muxed_tx_data_field;
            end
        end
    end

    // Direct cross-connections
    assign ptn_if.rx_sb_msg_valid = dut2ptn_valid_sr[SB_DELAY-1] & ~ptn_if.tb_suppress_rx_sb;
    assign ptn_if.rx_sb_msg       = dut2ptn_msg_sr  [SB_DELAY-1];
    assign ptn_if.rx_msginfo      = dut2ptn_info_sr [SB_DELAY-1];
    assign ptn_if.rx_data_field   = dut2ptn_data_sr [SB_DELAY-1];

    assign dut_if.rx_sb_msg_valid = ptn2dut_valid_sr[SB_DELAY-1] & ~dut_if.tb_suppress_rx_sb;
    assign dut_if.rx_sb_msg       = ptn2dut_msg_sr  [SB_DELAY-1];
    assign dut_if.rx_msginfo      = ptn2dut_info_sr [SB_DELAY-1];
    assign dut_if.rx_data_field   = ptn2dut_data_sr [SB_DELAY-1];

    // =========================================================================
    // Die A Instantiation (DUT)
    // =========================================================================
    logic        dut_local_linkspeed_en = 0;
    logic        dut_linkspeed_done;
    logic        dut_linkspeed_linkinit_req;
    logic        dut_linkspeed_speedidle_req;
    logic        dut_linkspeed_repair_req;
    logic        dut_linkspeed_phyretrain_req;
    logic        dut_trainerror_req = 1'b0;

    logic        dut_partner_linkspeed_en = 0;

    logic        dut_PHY_IN_RETRAIN_rst;
    logic        dut_busy_bit_rst;

    // Connect RF and param signals to interfaces for u_negotiated_lanes in ltsm_tb_attachments
    assign dut_if.rf_cap_SPMW               = dut_rf_cap_SPMW;
    assign dut_if.rf_ctrl_target_link_width = dut_rf_ctrl_target_link_width;
    assign dut_if.param_UCIe_S_x8           = 1'b0;
    assign dut_if.linkspeed_success_lanes   = dut_if.d2c_perlane_pass & dut_active_rx_lanes;

    assign ptn_if.rf_cap_SPMW               = ptn_rf_cap_SPMW;
    assign ptn_if.rf_ctrl_target_link_width = ptn_rf_ctrl_target_link_width;
    assign ptn_if.param_UCIe_S_x8           = 1'b0;
    assign ptn_if.linkspeed_success_lanes   = ptn_if.d2c_perlane_pass & ptn_active_rx_lanes;


    wrapper_LINKSPEED u_dut (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (is_ltsm_out_of_reset),

        .linkspeed_en                   (dut_partner_linkspeed_en || dut_local_linkspeed_en),
        // .local_linkspeed_en             (dut_local_linkspeed_en),
        // .partner_linkspeed_en           (dut_partner_linkspeed_en),

        .linkspeed_done                 (dut_linkspeed_done),
        // .trainerror_req                 (),

        .linkspeed_linkinit_req         (dut_linkspeed_linkinit_req),
        .linkspeed_speedidle_req        (dut_linkspeed_speedidle_req),
        .linkspeed_repair_req           (dut_linkspeed_repair_req),
        .linkspeed_phyretrain_req       (dut_linkspeed_phyretrain_req),

        .active_rx_lanes                (dut_active_rx_lanes),
        .width_degrade_feasible         (dut_if.degrade_feasible),

        .PHY_IN_RETRAIN                 (dut_PHY_IN_RETRAIN),
        .params_changed                 (dut_params_changed),
        .PHY_IN_RETRAIN_rst             (dut_PHY_IN_RETRAIN_rst),
        .busy_bit_rst                   (dut_busy_bit_rst),

        .local_sweep_en                 (dut_if.sweep_en),
        .partner_sweep_en               (dut_if.partner_sweep_en),
        .d2c_perlane_pass               (dut_if.d2c_perlane_pass),
        .local_sweep_done               (dut_if.sweep_done),

        .linkspeed_success_lanes        (dut_linkspeed_success_lanes),
        .lcl_tx_elec_idle               (),
        .ptr_rx_elec_idle               (),

        .tx_sb_msg_valid                (dut_if.tx_sb_msg_valid),
        .tx_sb_msg                      (dut_if.tx_sb_msg),
        .tx_msginfo                     (dut_if.tx_msginfo),
        .tx_data_field                  (dut_if.tx_data_field),

        .rx_sb_msg_valid                (dut_if.rx_sb_msg_valid),
        .rx_sb_msg                      (dut_if.rx_sb_msg)
        // .rx_msginfo                     (dut_if.rx_msginfo),
        // .rx_data_field                  (dut_if.rx_data_field)
    );

    // =========================================================================
    // Die B Instantiation (PARTNER)
    // =========================================================================
    logic        ptn_local_linkspeed_en = 0;
    logic        ptn_linkspeed_done;
    logic        ptn_linkspeed_linkinit_req;
    logic        ptn_linkspeed_speedidle_req;
    logic        ptn_linkspeed_repair_req;
    logic        ptn_linkspeed_phyretrain_req;
    logic        ptn_trainerror_req = 1'b0;

    logic        ptn_partner_linkspeed_en = 0;

    logic        ptn_PHY_IN_RETRAIN_rst;
    logic        ptn_busy_bit_rst;

    wrapper_LINKSPEED u_ptn (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (is_ltsm_out_of_reset),

        .linkspeed_en                   (ptn_partner_linkspeed_en || ptn_local_linkspeed_en),
        // .local_linkspeed_en             (ptn_local_linkspeed_en),
        // .partner_linkspeed_en           (ptn_partner_linkspeed_en),

        .linkspeed_done                 (ptn_linkspeed_done),
        // .trainerror_req                 (),

        .linkspeed_linkinit_req         (ptn_linkspeed_linkinit_req),
        .linkspeed_speedidle_req        (ptn_linkspeed_speedidle_req),
        .linkspeed_repair_req           (ptn_linkspeed_repair_req),
        .linkspeed_phyretrain_req       (ptn_linkspeed_phyretrain_req),

        .active_rx_lanes                (ptn_active_rx_lanes),
        .width_degrade_feasible         (ptn_if.degrade_feasible),
        .PHY_IN_RETRAIN                 (ptn_PHY_IN_RETRAIN),
        .params_changed                 (ptn_params_changed),
        .PHY_IN_RETRAIN_rst             (ptn_PHY_IN_RETRAIN_rst),
        .busy_bit_rst                   (ptn_busy_bit_rst),

        .local_sweep_en                 (ptn_if.sweep_en),
        .partner_sweep_en               (ptn_if.partner_sweep_en),
        .d2c_perlane_pass               (ptn_if.d2c_perlane_pass),
        .local_sweep_done               (ptn_if.sweep_done),

        .linkspeed_success_lanes        (ptn_linkspeed_success_lanes),
        .lcl_tx_elec_idle               (),
        .ptr_rx_elec_idle               (),

        .tx_sb_msg_valid                (ptn_if.tx_sb_msg_valid),
        .tx_sb_msg                      (ptn_if.tx_sb_msg),
        .tx_msginfo                     (ptn_if.tx_msginfo),
        .tx_data_field                  (ptn_if.tx_data_field),

        .rx_sb_msg_valid                (ptn_if.rx_sb_msg_valid),
        .rx_sb_msg                      (ptn_if.rx_sb_msg)
        // .rx_msginfo                     (ptn_if.rx_msginfo),
        // .rx_data_field                  (ptn_if.rx_data_field)
    );

    assign dut_if.timeout_timer_en          = dut_local_linkspeed_en | dut_partner_linkspeed_en;
    assign ptn_if.timeout_timer_en          = ptn_local_linkspeed_en | ptn_partner_linkspeed_en;

    // =========================================================================
    // State Names Enum & Monitors
    // =========================================================================
    typedef enum logic [4:0] {
        LCL_IDLE=0,LCL_SEND_START_REQ=1,LCL_WAIT_START_RESP=2,LCL_TX_D2C_PT=3,
        LCL_EVAL_RESULT=4,LCL_SEND_PHY_RETRAIN_REQ=5,LCL_WAIT_PHY_RETRAIN_RESP=6,
        LCL_SEND_DONE_REQ=7,LCL_WAIT_DONE_RESP=8,LCL_SEND_ERROR_REQ=9,
        LCL_WAIT_ERROR_RESP=10,LCL_RECOVERY_DECISION=11,LCL_SEND_REPAIR_REQ=12,
        LCL_WAIT_REPAIR_RESP=13,LCL_SEND_SPEED_DEGRADE_REQ=14,LCL_WAIT_SPEED_DEGRADE_RESP=15,
        LCL_WAIT_RECOVERY_REQ=16,LCL_TO_LINKINIT=17,LCL_TO_REPAIR=18,
        LCL_TO_SPEEDIDLE=19,LCL_TO_PHYRETRAIN=20,LCL_TO_TRAINERROR=21
    } lcl_state_t;

    typedef enum logic [3:0] {
        PTR_IDLE=0,PTR_WAIT_START_REQ=1,PTR_SEND_START_RESP=2,PTR_WAIT_POST_D2C_REQ=3,
        PTR_SEND_DONE_RESP=4,PTR_SEND_ERROR_RESP=5,PTR_WAIT_RECOVERY_REQ=6,
        PTR_SEND_REPAIR_RESP=7,PTR_SEND_SPEED_DEGRADE_RESP=8,PTR_SEND_PHY_RETRAIN_RESP=9,
        PTR_TO_LINKINIT=10,PTR_TO_REPAIR=11,PTR_TO_SPEEDIDLE=12,
        PTR_TO_PHYRETRAIN=13,PTR_TO_TRAINERROR=14
    } ptr_state_t;

    lcl_state_t dut_local_state, prev_dut_local_state;
    ptr_state_t dut_partner_state, prev_dut_partner_state;
    logic       in_randomized_scenarios = 1'b0;

    assign dut_local_state   = lcl_state_t'(u_dut.u_LINKSPEED_local.current_state);
    assign dut_partner_state = ptr_state_t'(u_dut.u_LINKSPEED_partner.current_state);

    function string get_short_msg_name(msg_no_e msg);
        case (msg)
            MBTRAIN_LINKSPEED_start_req                         : return "START_REQ";
            MBTRAIN_LINKSPEED_start_resp                        : return "START_RESP";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req: return "PHY_RETRAIN_REQ";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp: return "PHY_RETRAIN_RESP";
            MBTRAIN_LINKSPEED_done_req                          : return "DONE_REQ";
            MBTRAIN_LINKSPEED_done_resp                         : return "DONE_RESP";
            MBTRAIN_LINKSPEED_error_req                         : return "ERROR_REQ";
            MBTRAIN_LINKSPEED_error_resp                        : return "ERROR_RESP";
            MBTRAIN_LINKSPEED_exit_to_repair_req                : return "REPAIR_REQ";
            MBTRAIN_LINKSPEED_exit_to_repair_resp               : return "REPAIR_RESP";
            MBTRAIN_LINKSPEED_exit_to_speed_degrade_req         : return "SPEED_DEGRADE_REQ";
            MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp        : return "SPEED_DEGRADE_RESP";
            TRAINERROR_Entry_req                                : return "TRAINERROR_REQ";
            default                                             : return "OTHER_SB_MSG";
        endcase
    endfunction

    // Print monitors
    always @(posedge lclk) begin
        if (!in_randomized_scenarios || ENABLE_RAND_LOG) begin
            if (rst_n && dut_local_state !== prev_dut_local_state) begin
                $display("# [%0d ps] Die A LOCAL   State -> %s", $realtime(), dut_local_state.name());
                prev_dut_local_state <= dut_local_state;
            end
            if (rst_n && dut_partner_state !== prev_dut_partner_state) begin
                $display("# [%0d ps] Die A PARTNER State -> %s", $realtime(), dut_partner_state.name());
                prev_dut_partner_state <= dut_partner_state;
            end
            if (dut_if.rx_sb_msg_valid) begin
                $display("# [%0d ps] DEBUG: Die A RX SB Msg from Die B: %s (MsgCode: 8'h%h, MsgInfo: 16'h%h)",
                    $realtime(), get_short_msg_name(msg_no_e'(dut_if.rx_sb_msg)), dut_if.rx_sb_msg, dut_if.rx_msginfo);
            end
        end else begin
            // Still update the state transition trackers to avoid spurious transition logs later
            if (rst_n && dut_local_state !== prev_dut_local_state) begin
                prev_dut_local_state <= dut_local_state;
            end
            if (rst_n && dut_partner_state !== prev_dut_partner_state) begin
                prev_dut_partner_state <= dut_partner_state;
            end
        end
    end

    // Default parameters setup
    initial begin
        dut_if.state_n_0             = ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED;
        dut_if.tb_suppress_rx_sb     = 0;
        dut_if.tb_force_val_pass     = 1;
        dut_if.tb_verbose            = 0;
        dut_if.tb_wait_timeout       = 0;
        dut_if.tb_aggr_err           = 0;
        dut_if.cfg_max_err_thresh_perlane = 10;
        dut_if.cfg_max_err_thresh_aggr    = 20;

        ptn_if.state_n_0             = ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED;
        ptn_if.tb_suppress_rx_sb     = 0;
        ptn_if.tb_force_val_pass     = 1;
        ptn_if.tb_verbose            = 0;
        ptn_if.tb_wait_timeout       = 0;
        ptn_if.tb_aggr_err           = 0;
        ptn_if.cfg_max_err_thresh_perlane = 10;
        ptn_if.cfg_max_err_thresh_aggr    = 20;
    end

    // Test infrastructure
    integer success_count = 0, fail_count = 0, test_no = 1;

    task automatic pass_test(input string name);
        $display("[PASS] T%0d: %s (ok=%0d, fail=%0d)", test_no, name, success_count+1, fail_count);
        success_count++;
        test_no++;
    endtask

    // =========================================================================
    // Task-Controlled Test Scenarios
    // =========================================================================
    task automatic run_scenario(
            input string name,
            input logic hs,
            input logic cont_clk,
            input logic [15:0] d2c_pass_mask,
            input logic phy_in_retrain,
            input logic params_changed,
            input logic [15:0] active_rx_lanes,
            input logic expect_linkinit,
            input logic expect_repair,
            input logic expect_speedidle,
            input logic expect_phyretrain,
            input logic expect_trainerror,
            input logic suppress_sb,
            input logic inject_trainerror
        );
        $display("\n\n# =========================================================");
        $display("# Starting Scenario: %s", name);
        $display("# Config  : hs=%b, cont_clk=%b, d2c_pass_mask=%h, phy_in_retrain=%b, params_changed=%b, active_rx_lanes=%h",
            hs, cont_clk, d2c_pass_mask, phy_in_retrain, params_changed, active_rx_lanes);
        $display("# Expected: linkinit=%b, repair=%b, speedidle=%b, phyretrain=%b, trainerror=%b",
            expect_linkinit, expect_repair, expect_speedidle, expect_phyretrain, expect_trainerror);
        $display("# =========================================================");

        assert_reset();

        // Apply configurations
        is_high_speed = hs;
        is_continuous_clk_mode = cont_clk;

        dut_PHY_IN_RETRAIN = phy_in_retrain;
        dut_params_changed = params_changed;
        dut_active_rx_lanes = active_rx_lanes;
        dut_rf_ctrl_target_link_width = 4'h2;
        dut_rf_cap_SPMW = 1'b0;

        dut_if.tb_force_perlane_pass = d2c_pass_mask;
        ptn_if.tb_force_perlane_pass = 16'hFFFF;

        if (suppress_sb) begin
            ptn_if.tb_suppress_rx_sb = 1;
            fork
                begin
                    wait (dut_if.timeout_timer_en == 1);
                    repeat(200) @(posedge lclk);
                    tb_ptn_inject_valid = 1;
                    tb_ptn_inject_msg = TRAINERROR_Entry_req;
                    tb_ptn_inject_info = 16'h0;
                    @(posedge lclk);
                    tb_ptn_inject_valid = 0;
                end
            join_none
        end

        // Enable FSMs
        dut_local_linkspeed_en = 1;
        ptn_local_linkspeed_en = 1;
        dut_partner_linkspeed_en = 1;
        ptn_partner_linkspeed_en = 1;

        if (inject_trainerror) begin
            repeat(100) @(posedge lclk);
            tb_ptn_inject_valid = 1;
            tb_ptn_inject_msg = TRAINERROR_Entry_req;
            tb_ptn_inject_info = 16'h0;
            @(posedge lclk);
            tb_ptn_inject_valid = 0;
        end

        fork
            begin
                wait (dut_linkspeed_done || dut_trainerror_req);
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        // Verify FSM exits on Die A
        if (expect_linkinit && (!u_dut.local_linkinit_req || !dut_linkspeed_done)) begin
            $display("# ERROR: Expected LINKINIT exit on Die A, but got linkinit_req=%b, done=%b", u_dut.local_linkinit_req, dut_linkspeed_done);
            fail_count++; $stop;
        end
        if (expect_repair && (!u_dut.local_repair_req || !dut_linkspeed_done)) begin
            $display("# ERROR: Expected REPAIR exit on Die A, but got repair_req=%b, done=%b", u_dut.local_repair_req, dut_linkspeed_done);
            fail_count++; $stop;
        end
        if (expect_speedidle && (!u_dut.local_speedidle_req || !dut_linkspeed_done)) begin
            $display("# ERROR: Expected SPEEDIDLE exit on Die A, but got speedidle_req=%b, done=%b", u_dut.local_speedidle_req, dut_linkspeed_done);
            fail_count++; $stop;
        end
        if (expect_phyretrain && (!u_dut.local_phyretrain_req || !dut_linkspeed_done)) begin
            $display("# ERROR: Expected PHYRETRAIN exit on Die A, but got phyretrain_req=%b, done=%b", u_dut.local_phyretrain_req, dut_linkspeed_done);
            fail_count++; $stop;
        end
        if (expect_trainerror && !dut_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR on Die A, but got trainerror_req=%b", dut_trainerror_req);
            fail_count++; $stop;
        end

        // Clean up FSM enables
        dut_local_linkspeed_en = 0;
        ptn_local_linkspeed_en = 0;
        dut_partner_linkspeed_en = 0;
        ptn_partner_linkspeed_en = 0;
        if (suppress_sb) ptn_if.tb_suppress_rx_sb = 0;

        #(LCLK_PERIOD * 50);
        pass_test(name);
    endtask

    // =========================================================================
    // Main Test Program
    // =========================================================================
    initial begin
        $display("# =========================================================");
        $display("# Running wrapper_LINKSPEED_tb                              ");
        $display("# =========================================================");

        // ------------------------------------------------------------------
        // T1: Happy path — both succeed → LINKINIT
        // ------------------------------------------------------------------
        run_scenario(
            .name("Scenario 1: Happy path -> LINKINIT"),
            .hs(1), .cont_clk(0), .d2c_pass_mask(16'hFFFF),
            .phy_in_retrain(0), .params_changed(0), .active_rx_lanes(16'hFFFF),
            .expect_linkinit(1), .expect_repair(0), .expect_speedidle(0), .expect_phyretrain(0), .expect_trainerror(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // ------------------------------------------------------------------
        // T2: Error path → REPAIR (degrade feasible)
        // ------------------------------------------------------------------
        run_scenario(
            .name("Scenario 2: Error -> REPAIR (degrade feasible)"),
            .hs(1), .cont_clk(0), .d2c_pass_mask(16'h00FF), // Low half passes
            .phy_in_retrain(0), .params_changed(0), .active_rx_lanes(16'hFFFF),
            .expect_linkinit(0), .expect_repair(1), .expect_speedidle(0), .expect_phyretrain(0), .expect_trainerror(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // ------------------------------------------------------------------
        // T3: Error path → SPEEDIDLE (degrade not feasible)
        // ------------------------------------------------------------------
        run_scenario(
            .name("Scenario 3: Error -> SPEEDIDLE (degrade not feasible)"),
            .hs(1), .cont_clk(0), .d2c_pass_mask(16'h0F0F), // Both halves failing
            .phy_in_retrain(0), .params_changed(0), .active_rx_lanes(16'hFFFF),
            .expect_linkinit(0), .expect_repair(0), .expect_speedidle(1), .expect_phyretrain(0), .expect_trainerror(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // ------------------------------------------------------------------
        // T4: PHY retrain — LOCAL initiates
        // ------------------------------------------------------------------
        run_scenario(
            .name("Scenario 4: PHY retrain - LOCAL initiates"),
            .hs(1), .cont_clk(0), .d2c_pass_mask(16'hFFFF),
            .phy_in_retrain(1), .params_changed(1), .active_rx_lanes(16'hFFFF),
            .expect_linkinit(0), .expect_repair(0), .expect_speedidle(0), .expect_phyretrain(1), .expect_trainerror(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // ------------------------------------------------------------------
        // T5: PHY retrain, no params change → LINKINIT
        // ------------------------------------------------------------------
        run_scenario(
            .name("Scenario 5: PHY retrain (no params change) -> LINKINIT"),
            .hs(1), .cont_clk(0), .d2c_pass_mask(16'hFFFF),
            .phy_in_retrain(1), .params_changed(0), .active_rx_lanes(16'hFFFF),
            .expect_linkinit(1), .expect_repair(0), .expect_speedidle(0), .expect_phyretrain(0), .expect_trainerror(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // // ------------------------------------------------------------------
        // // T6: 8 ms timeout → TRAINERROR
        // // ------------------------------------------------------------------
        // run_scenario(
        //     .name("Scenario 6: Watchdog 8ms Timeout -> TRAINERROR"),
        //     .hs(1), .cont_clk(0), .d2c_pass_mask(16'hFFFF),
        //     .phy_in_retrain(0), .params_changed(0), .active_rx_lanes(16'hFFFF),
        //     .expect_linkinit(0), .expect_repair(0), .expect_speedidle(0), .expect_phyretrain(0), .expect_trainerror(1),
        //     .suppress_sb(1), .inject_trainerror(0) // Suppress SB to force timeout
        // );
        //
        // // ------------------------------------------------------------------
        // // T7: TRAINERROR_Entry_req → TRAINERROR
        // // ------------------------------------------------------------------
        // run_scenario(
        //     .name("Scenario 7: TRAINERROR_Entry_req received -> TRAINERROR"),
        //     .hs(1), .cont_clk(0), .d2c_pass_mask(16'hFFFF),
        //     .phy_in_retrain(0), .params_changed(0), .active_rx_lanes(16'hFFFF),
        //     .expect_linkinit(0), .expect_repair(0), .expect_speedidle(0), .expect_phyretrain(0), .expect_trainerror(1),
        //     .suppress_sb(0), .inject_trainerror(1) // Inject TRAINERROR_Entry_req
        // );

        // ------------------------------------------------------------------
        // T8: Cross-die abandon (LOCAL succeeds, PARTNER errors)
        // ------------------------------------------------------------------
        $display("\n\n# =========================================================");
        $display("# Starting Scenario 8: Cross-die abandon -> REPAIR");
        $display("# Config  : hs=1, cont_clk=0, dut_d2c_pass=ffff, ptn_d2c_pass=00ff, phy_in_retrain=0, params_changed=0, active_rx_lanes=ffff");
        $display("# Expected: local_repair_req=1");
        $display("# =========================================================");
        assert_reset();
        is_high_speed = 1; is_continuous_clk_mode = 0;
        dut_PHY_IN_RETRAIN = 0; dut_params_changed = 0;

        // DUT passes (success path), PTN fails partially (error path -> repair)
        dut_if.tb_force_perlane_pass = 16'hFFFF;
        ptn_if.tb_force_perlane_pass = 16'h00FF; // Degrade feasible -> REPAIR

        dut_local_linkspeed_en = 1; ptn_local_linkspeed_en = 1;
        dut_partner_linkspeed_en = 1; ptn_partner_linkspeed_en = 1;

        fork : t8_fork
            begin wait(u_dut.local_repair_req); disable t8_fork; end
            begin repeat(TIMEOUT_CYCLES) @(posedge lclk); $display("[FAIL] T8: watchdog"); fail_count++; disable t8_fork; end
        join

        dut_local_linkspeed_en = 0; ptn_local_linkspeed_en = 0;
        dut_partner_linkspeed_en = 0; ptn_partner_linkspeed_en = 0;
        #(LCLK_PERIOD * 10);
        pass_test("Scenario 8: Cross-die abandon -> REPAIR");

        // ------------------------------------------------------------------
        // T9: Speed degrade overrides repair
        // ------------------------------------------------------------------
        $display("\n\n# =========================================================");
        $display("# Starting Scenario 9: Speed degrade overrides repair");
        $display("# Config  : hs=1, cont_clk=0, dut_d2c_pass=0000, ptn_d2c_pass=00ff, phy_in_retrain=0, params_changed=0, active_rx_lanes=ffff");
        $display("# Expected: local_speedidle_req=1");
        $display("# =========================================================");
        assert_reset();
        is_high_speed = 1; is_continuous_clk_mode = 0;
        dut_PHY_IN_RETRAIN = 0; dut_params_changed = 0;

        // DUT has degrade feasible, PTN has degrade not feasible (REPAIR)
        // Wait, spec says: if speed degrade req is received, abandon repair.
        // So PTN should request SPEED DEGRADE, and DUT should request REPAIR.
        // PTN: degrade feasible. DUT: degrade not feasible (REPAIR).
        dut_if.tb_force_perlane_pass = 16'h0000; // Degrade NOT feasible -> REPAIR
        ptn_if.tb_force_perlane_pass = 16'h00FF; // Degrade feasible -> SPEED DEGRADE

        dut_local_linkspeed_en = 1; ptn_local_linkspeed_en = 1;
        dut_partner_linkspeed_en = 1; ptn_partner_linkspeed_en = 1;

        fork : t9_fork
            begin wait(u_dut.local_speedidle_req); disable t9_fork; end
            begin repeat(TIMEOUT_CYCLES) @(posedge lclk); $display("[FAIL] T9: watchdog"); fail_count++; disable t9_fork; end
        join

        dut_local_linkspeed_en = 0; ptn_local_linkspeed_en = 0;
        dut_partner_linkspeed_en = 0; ptn_partner_linkspeed_en = 0;
        #(LCLK_PERIOD * 10);
        pass_test("Scenario 9: Speed degrade overrides repair");


        // =========================================================================
        // 9. Randomized Scenarios Block with Self-Checking
        // =========================================================================
        in_randomized_scenarios = 1'b1;
        $display("\n\n# =========================================================");
        $display("# Starting Randomized Scenarios (200 Iterations without reset)");
        $display("# =========================================================");

        assert_reset(); // Initial reset before the loop

        for (int i = 1; i <= 200; i = i + 1) begin
            automatic bit hs_rnd = $urandom_range(0, 1);
            automatic bit clk_mode_rnd = $urandom_range(0, 1);
            automatic bit rand_errors = $urandom_range(0, 1);
            automatic bit rand_phy_retrain = $urandom_range(0, 1);
            automatic bit rand_params_changed = $urandom_range(0, 1);
            automatic bit rand_degrade_feasible = $urandom_range(0, 1);
            automatic logic [15:0] rand_pass_mask = 16'hFFFF;

            if (rand_errors == 0) begin
                rand_pass_mask = 16'hFFFF;
            end else if (rand_degrade_feasible == 1) begin
                rand_pass_mask = 16'h00FF; // Degrade feasible
            end else begin
                rand_pass_mask = 16'h0F0F; // Degrade not feasible
            end

            if (ENABLE_RAND_LOG) begin
                $display("\n\n# =========================================================");
                $display("# Starting Randomized Scenario Iteration %0d", i);
                $display("# Config  : hs=%b, cont_clk=%b, d2c_pass_mask=%h, phy_in_retrain=%b, params_changed=%b, active_rx_lanes=%h",
                    hs_rnd, clk_mode_rnd, rand_pass_mask, rand_phy_retrain, rand_params_changed, 16'hFFFF);
                $display("# Expected: linkinit=%b, repair=%b, speedidle=%b, phyretrain=%b, trainerror=0",
                    (!(rand_phy_retrain && rand_params_changed) && !rand_errors),
                    (!(rand_phy_retrain && rand_params_changed) && rand_errors && rand_degrade_feasible),
                    (!(rand_phy_retrain && rand_params_changed) && rand_errors && !rand_degrade_feasible),
                    (rand_phy_retrain && rand_params_changed));
                $display("# =========================================================");
            end

            is_high_speed = hs_rnd;
            is_continuous_clk_mode = clk_mode_rnd;

            dut_PHY_IN_RETRAIN = rand_phy_retrain;
            dut_params_changed = rand_params_changed;
            dut_active_rx_lanes = 16'hFFFF;
            dut_rf_ctrl_target_link_width = 4'h2;
            dut_rf_cap_SPMW = 1'b0;

            dut_if.tb_force_perlane_pass = rand_pass_mask;
            ptn_if.tb_force_perlane_pass = 16'hFFFF;

            // Enable FSMs
            dut_local_linkspeed_en = 1;
            ptn_local_linkspeed_en = 1;
            dut_partner_linkspeed_en = 1;
            ptn_partner_linkspeed_en = 1;

            fork
                begin
                    wait (dut_linkspeed_done || dut_trainerror_req);
                    #(LCLK_PERIOD * 10);
                end
                begin
                    #(TIMEOUT_CYCLES * LCLK_PERIOD);
                    $display("# ERROR: Simulation timeout guard fired in randomized test %0d!", i);
                    $stop;
                end
            join_any
            disable fork;

            // Verify FSM exits on Die A
            if (rand_phy_retrain && rand_params_changed) begin
                if (!u_dut.local_phyretrain_req) begin
                    $display("# ERROR: Expected PHYRETRAIN in random test %0d", i); fail_count++; $stop;
                end
            end else if (!rand_errors) begin
                if (!u_dut.local_linkinit_req) begin
                    $display("# ERROR: Expected LINKINIT in random test %0d", i); fail_count++; $stop;
                end
            end else if (rand_degrade_feasible) begin
                if (!u_dut.local_repair_req) begin
                    $display("# ERROR: Expected REPAIR in random test %0d", i); fail_count++; $stop;
                end
            end else begin
                if (!u_dut.local_speedidle_req) begin
                    $display("# ERROR: Expected SPEEDIDLE in random test %0d", i); fail_count++; $stop;
                end
            end

            // Clean up FSM enables
            dut_local_linkspeed_en = 0;
            ptn_local_linkspeed_en = 0;
            dut_partner_linkspeed_en = 0;
            ptn_partner_linkspeed_en = 0;

            #(LCLK_PERIOD * 50); // Wait between cycles WITHOUT reset
        end

        in_randomized_scenarios = 1'b0;
        pass_test("200 Randomized Scenarios");

        $display("\n=========================================================");
        $display(" LINKSPEED TB COMPLETE");
        $display(" PASSED: %0d | FAILED: %0d | TOTAL: %0d", success_count, fail_count,
            success_count+fail_count);
        $display("=========================================================");
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("MBTRAIN_TB_RESULT: SUCCESS");
        end else begin
            $display("*** %0d TEST(S) FAILED ***", fail_count);
            $display("MBTRAIN_TB_RESULT: FAILURE");
        end
        $finish;
    end

    // =====================================================================
    // Absolute simulation watchdog
    // =====================================================================
    initial begin
        repeat (TIMEOUT_CYCLES * 10) @(posedge lclk);
        $display("[FATAL] Absolute simulation watchdog expired! Forcing finish.");
        $display("MBTRAIN_TB_RESULT: FAILURE");
        $finish;
    end

endmodule





