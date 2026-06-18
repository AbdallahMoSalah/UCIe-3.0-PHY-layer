`timescale 1ps/1ps
module wrapper_SPEEDIDLE_tb;

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ;
    parameter ANALOG_SETTLE_CYCLES = 10     ;
    parameter SB_DELAY             = 20     ;
    parameter TIMEOUT_CYCLES       = 1000   ;

    // Clock and Reset Signals
    logic lclk = 0;
    logic rst_n = 0;

    always #(LCLK_PERIOD/2) lclk = ~lclk;

    task automatic assert_reset();
        rst_n = 0;
        #(LCLK_PERIOD * 5);
        rst_n = 1;
        #(LCLK_PERIOD * 5);
    endtask

    // Interfaces & Attachments
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

    // Control registers
    logic soft_rst_n = 1;
    logic tb_ptn_inject_valid = 0;
    logic [7:0] tb_ptn_inject_msg = 0;

    // Configurations
    state_n_e state_n_1;
    logic [2:0] param_negotiated_max_speed = 3'b010;

    // Sideband Delay Queue (Connecting Die A and Die B with SB_DELAY)
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
            dut2ptn_valid_sr <= {dut2ptn_valid_sr[SB_DELAY-2:0], dut_if.tb_muxed_tx_sb_msg_valid};
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
            dut2ptn_msg_sr[0]  <= dut_if.tb_muxed_tx_sb_msg;
            dut2ptn_info_sr[0] <= dut_if.tb_muxed_tx_msginfo;
            dut2ptn_data_sr[0] <= dut_if.tb_muxed_tx_data_field;

            if (tb_ptn_inject_valid) begin
                ptn2dut_msg_sr[0]  <= tb_ptn_inject_msg;
                ptn2dut_info_sr[0] <= 16'h0;
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

    // DUT Wrapper Signals
    logic        dut_local_speedidle_en = 0;
    logic        dut_partner_speedidle_en = 0;
    logic        dut_speedidle_done;
    logic        dut_trainerror_req;
    logic [2:0]  dut_phy_negotiated_speed;

    wrapper_SPEEDIDLE u_dut (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .soft_rst_n             (soft_rst_n),
        .speedidle_en           (dut_local_speedidle_en),
        .speedidle_done         (dut_speedidle_done),
        .trainerror_req         (dut_trainerror_req),
        .analog_settle_timer_en (dut_if.analog_settle_timer_en),
        .analog_settle_time_done(dut_if.analog_settle_time_done),
        .state_n_1              (state_n_1),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .phy_negotiated_speed   (dut_phy_negotiated_speed),
        .mb_tx_clk_lane_sel     (dut_if.mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel    (dut_if.mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel     (dut_if.mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel     (dut_if.mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel     (dut_if.mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel    (dut_if.mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (dut_if.mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel     (dut_if.mb_rx_trk_lane_sel),
        .tx_sb_msg_valid        (dut_if.tx_sb_msg_valid),
        .tx_sb_msg              (dut_if.tx_sb_msg),
        .tx_msginfo             (dut_if.tx_msginfo),
        .tx_data_field          (dut_if.tx_data_field),
        .rx_sb_msg_valid        (dut_if.rx_sb_msg_valid),
        .rx_sb_msg              (dut_if.rx_sb_msg)
    );

    // Partner Wrapper Signals
    logic        ptn_local_speedidle_en = 0;
    logic        ptn_partner_speedidle_en = 0;
    logic        ptn_speedidle_done;
    logic        ptn_trainerror_req;
    logic [2:0]  ptn_phy_negotiated_speed;

    wrapper_SPEEDIDLE u_ptn (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .soft_rst_n             (soft_rst_n),
        .speedidle_en           (ptn_local_speedidle_en),
        .speedidle_done         (ptn_speedidle_done),
        .trainerror_req         (ptn_trainerror_req),
        .analog_settle_timer_en (ptn_if.analog_settle_timer_en),
        .analog_settle_time_done(ptn_if.analog_settle_time_done),
        .state_n_1              (state_n_1),
        .param_negotiated_max_speed(param_negotiated_max_speed),
        .phy_negotiated_speed   (ptn_phy_negotiated_speed),
        .mb_tx_clk_lane_sel     (ptn_if.mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel    (ptn_if.mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel     (ptn_if.mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel     (ptn_if.mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel     (ptn_if.mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel    (ptn_if.mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (ptn_if.mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel     (ptn_if.mb_rx_trk_lane_sel),
        .tx_sb_msg_valid        (ptn_if.tx_sb_msg_valid),
        .tx_sb_msg              (ptn_if.tx_sb_msg),
        .tx_msginfo             (ptn_if.tx_msginfo),
        .tx_data_field          (ptn_if.tx_data_field),
        .rx_sb_msg_valid        (ptn_if.rx_sb_msg_valid),
        .rx_sb_msg              (ptn_if.rx_sb_msg)
    );

    integer test_no = 1;
    integer success_count = 0;
    integer fail_count = 0;

    task automatic pass_test(input string name);
        $display("[PASS] T%0d: %s (ok=%0d, fail=%0d)", test_no, name, success_count+1, fail_count);
        success_count++;
        test_no++;
    endtask

    task automatic run_scenario(
            input string name,
            input state_n_e prev_state,
            input logic [2:0] max_speed,
            input logic [2:0] expected_speed,
            input logic expect_trainerror,
            input logic reset_before = 1'b1
        );
        if (reset_before) assert_reset();

        state_n_1 = prev_state;
        param_negotiated_max_speed = max_speed;

        dut_local_speedidle_en = 1;
        ptn_partner_speedidle_en = 1;
        dut_partner_speedidle_en = 1;
        ptn_local_speedidle_en = 1;

        fork
            begin
                if (expect_trainerror) begin
                    wait(dut_trainerror_req);
                end else begin
                    wait(dut_speedidle_done && ptn_speedidle_done);
                end
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        if (expect_trainerror) begin
            if (!dut_trainerror_req) begin
                $display("# ERROR: Expected trainerror but did not see it!");
                $stop;
            end
        end else begin
            if (dut_phy_negotiated_speed !== expected_speed) begin
                $display("# ERROR: Speed mismatch! Got %0d, expected %0d", dut_phy_negotiated_speed, expected_speed);
                $stop;
            end
        end

        dut_local_speedidle_en = 0;
        ptn_partner_speedidle_en = 0;
        dut_partner_speedidle_en = 0;
        ptn_local_speedidle_en = 0;
        #(LCLK_PERIOD * 10);
        pass_test(name);
    endtask

    initial begin
        $display("# =========================================================");
        $display("# Running wrapper_SPEEDIDLE_tb                             ");
        $display("# =========================================================");

        dut_if.tb_suppress_rx_sb = 0;
        ptn_if.tb_suppress_rx_sb = 0;

        // Scenario 1: Entry from DATAVREF -> sets to max speed (3'b010)
        run_scenario("Scenario 1: From DATAVREF", LOG_MBTRAIN_DATAVREF, 3'b010, 3'b010, 0, 1'b1);

        // Scenario 2: Entry from L1_L2 -> keeps speed (last speed is 3'b010 from Scenario 1)
        run_scenario("Scenario 2: From L1_L2", LOG_L1, 3'b010, 3'b010, 0, 1'b0);

        // Scenario 3: Entry from LINKSPEED -> decrements speed by 1 (3'b010 -> 3'b001)
        run_scenario("Scenario 3: From LINKSPEED", LOG_MBTRAIN_LINKSPEED, 3'b010, 3'b001, 0, 1'b0);

        // Scenario 4: Degrade speed from 3'b000 should cause trainerror
        run_scenario("Scenario 4: From LINKSPEED at min speed -> trainerror", LOG_MBTRAIN_LINKSPEED, 3'b000, 3'b000, 1, 1'b1);

        // Scenario 5: Watchdog timeout (Commented out because sub-FSM watchdogs were removed)
        /*
         assert_reset();
         dut_local_speedidle_en = 1;
         ptn_if.tb_suppress_rx_sb = 1;
         fork
         begin
         wait(dut_trainerror_req);
         #(LCLK_PERIOD * 5);
         end
         begin
         #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
         $display("# ERROR: Watchdog timeout failed!");
         $stop;
         end
         join_any
         disable fork;
         ptn_if.tb_suppress_rx_sb = 0;
         dut_local_speedidle_en = 0;
         pass_test("Scenario 5: Watchdog Timeout");
         */

        // Scenario 6: 50+ Randomized iterations
        $display("# Starting 60 Randomized iterations...");
        for (int i = 0; i < 60; i++) begin
            automatic bit [1:0] state_sel = $urandom_range(0, 2);
            automatic state_n_e prev = (state_sel == 0) ? LOG_MBTRAIN_DATAVREF :
                (state_sel == 1) ? LOG_L1 : LOG_MBTRAIN_LINKSPEED;
            automatic bit [2:0] max_sp = $urandom_range(1, 4);
            // Just test clean entry-exit for speedidle
            run_scenario($sformatf("Randomized Iteration %0d", i), LOG_MBTRAIN_DATAVREF, max_sp, max_sp, 0);
        end

        $display("# All wrapper_SPEEDIDLE_tb tests PASSED");
        if (fail_count == 0) begin
            $display("MBTRAIN_TB_RESULT: SUCCESS");
        end else begin
            $display("MBTRAIN_TB_RESULT: FAILURE");
        end
        $finish;
    end

endmodule
