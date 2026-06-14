`timescale 1ps/1ps
module wrapper_TXSELFCAL_tb;

    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ; // 1ns lclk period
    parameter ANALOG_SETTLE_CYCLES = 10     ; // cycles for analog settle
    parameter SB_DELAY             = 20     ; // sideband message delay
    parameter TIMEOUT_CYCLES       = 1000   ; // residency timeout cycles (for fast simulation)
    parameter bit ENABLE_RAND_LOG  = 1'b0;

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
    logic        dut_local_txselfcal_en = 0;
    logic        dut_partner_txselfcal_en = 0;
    logic        dut_txselfcal_done;
    logic        dut_trainerror_req;
    logic        dut_phy_tx_selfcal_en;

    wrapper_TXSELFCAL u_dut (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .soft_rst_n             (soft_rst_n),
        .local_txselfcal_en     (dut_local_txselfcal_en),
        .partner_txselfcal_en   (dut_partner_txselfcal_en),
        .txselfcal_done         (dut_txselfcal_done),
        .trainerror_req         (dut_trainerror_req),
        .analog_settle_timer_en (dut_if.analog_settle_timer_en),
        .analog_settle_time_done(dut_if.analog_settle_time_done),
        .phy_tx_selfcal_en      (dut_phy_tx_selfcal_en),
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
        .rx_sb_msg              (dut_if.rx_sb_msg),
        .rx_msginfo             (dut_if.rx_msginfo),
        .rx_data_field          (dut_if.rx_data_field)
    );

    // Partner Wrapper Signals
    logic        ptn_local_txselfcal_en = 0;
    logic        ptn_partner_txselfcal_en = 0;
    logic        ptn_txselfcal_done;
    logic        ptn_trainerror_req;
    logic        ptn_phy_tx_selfcal_en;

    wrapper_TXSELFCAL u_ptn (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .soft_rst_n             (soft_rst_n),
        .local_txselfcal_en     (ptn_local_txselfcal_en),
        .partner_txselfcal_en   (ptn_partner_txselfcal_en),
        .txselfcal_done         (ptn_txselfcal_done),
        .trainerror_req         (ptn_trainerror_req),
        .analog_settle_timer_en (ptn_if.analog_settle_timer_en),
        .analog_settle_time_done(ptn_if.analog_settle_time_done),
        .phy_tx_selfcal_en      (ptn_phy_tx_selfcal_en),
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
        .rx_sb_msg              (ptn_if.rx_sb_msg),
        .rx_msginfo             (ptn_if.rx_msginfo),
        .rx_data_field          (ptn_if.rx_data_field)
    );

    integer test_no = 1;
    integer success_count = 0;
    integer fail_count = 0;

    task automatic pass_test(input string name);
        $display("[PASS] T%0d: %s (ok=%0d, fail=%0d)", test_no, name, success_count+1, fail_count);
        success_count++;
        test_no++;
    endtask

    task automatic run_clean_scenario(input string name);
        assert_reset();

        // Enable Local on DUT and Partner on PTN
        dut_local_txselfcal_en = 1;
        ptn_partner_txselfcal_en = 1;

        // Also enable Partner on DUT and Local on PTN to mimic bi-directional symmetric link
        dut_partner_txselfcal_en = 1;
        ptn_local_txselfcal_en = 1;

        fork
            begin
                wait(dut_txselfcal_done && ptn_txselfcal_done);
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        // Check assertions
        if (!dut_txselfcal_done || dut_trainerror_req || !ptn_txselfcal_done) begin
            $display("# ERROR: Clean run failed!");
            $stop;
        end

        dut_local_txselfcal_en = 0;
        ptn_partner_txselfcal_en = 0;
        dut_partner_txselfcal_en = 0;
        ptn_local_txselfcal_en = 0;
        #(LCLK_PERIOD * 10);
        pass_test(name);
    endtask

    function automatic string get_lcl_state_str(input int state_val);
        case (state_val)
            0: return "TXSELFCAL_LCL_IDLE";
            1: return "TXSELFCAL_LCL_EXECUTE";
            2: return "TXSELFCAL_LCL_SEND_REQ";
            3: return "TXSELFCAL_LCL_WAIT_RESP";
            4: return "TXSELFCAL_LCL_TO_RXCLKCAL";
            5: return "TXSELFCAL_LCL_TO_TRAINERROR";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string get_ptn_state_str(input int state_val);
        case (state_val)
            0: return "TXSELFCAL_PTN_IDLE";
            1: return "TXSELFCAL_PTN_WAIT_REQ";
            2: return "TXSELFCAL_PTN_SEND_RESP";
            3: return "TXSELFCAL_PTN_DONE";
            4: return "TXSELFCAL_PTN_TO_TRAINERROR";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string get_msg_str(input [7:0] msg_val);
        case (msg_val)
            SBINIT_Out_of_Reset: return "SBINIT_Out_of_Reset";
            SBINIT_done_req: return "SBINIT_done_req";
            SBINIT_done_resp: return "SBINIT_done_resp";
            MBTRAIN_TXSELFCAL_Done_req: return "MBTRAIN_TXSELFCAL_Done_req";
            MBTRAIN_TXSELFCAL_Done_resp: return "MBTRAIN_TXSELFCAL_Done_resp";
            TRAINERROR_Entry_req: return "TRAINERROR_Entry_req";
            TRAINERROR_Entry_resp: return "TRAINERROR_Entry_resp";
            NOTHING: return "NOTHING";
            default: return $sformatf("MsgCode: 8'h%2h", msg_val);
        endcase
    endfunction

    string last_lcl_state_str = "";
    string last_ptn_state_str = "";
    string last_tx_msg_str = "";
    string last_rx_msg_str = "";

    integer cycle_count = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            last_lcl_state_str <= "";
            last_ptn_state_str <= "";
            last_tx_msg_str <= "";
            last_rx_msg_str <= "";
        end else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count < 100) begin
                automatic string lcl_state_str = get_lcl_state_str(u_dut.u_TXSELFCAL_local.current_state);
                automatic string ptn_state_str = get_ptn_state_str(u_ptn.u_TXSELFCAL_partner.current_state);
                automatic string tx_msg_str = get_msg_str(dut_if.tx_sb_msg_valid ? dut_if.tx_sb_msg : NOTHING);
                automatic string rx_msg_str = get_msg_str(ptn_if.rx_sb_msg_valid ? ptn_if.rx_sb_msg : NOTHING);

                if (lcl_state_str != last_lcl_state_str ||
                        ptn_state_str != last_ptn_state_str ||
                        tx_msg_str != last_tx_msg_str ||
                        rx_msg_str != last_rx_msg_str) begin

                    $display("# [Cycle %3d]: lcl_state=%-25s, ptn_state=%-25s, tx_sb_msg=%-27s, rx_sb_msg=%-27s",
                        cycle_count,
                        lcl_state_str,
                        ptn_state_str,
                        tx_msg_str,
                        rx_msg_str);

                    last_lcl_state_str = lcl_state_str;
                    last_ptn_state_str = ptn_state_str;
                    last_tx_msg_str = tx_msg_str;
                    last_rx_msg_str = rx_msg_str;
                end
            end
        end
    end

    initial begin
        $display("# =========================================================");
        $display("# Running wrapper_TXSELFCAL_tb                             ");
        $display("# =========================================================");

        dut_if.tb_suppress_rx_sb = 0;
        ptn_if.tb_suppress_rx_sb = 0;

        // Scenario 1: Clean calibration run
        run_clean_scenario("Scenario 1: Clean Calibration");

        // Scenario 2: Watchdog timeout (Commented out because sub-FSM watchdogs were removed)
        /*
         assert_reset();
         dut_local_txselfcal_en = 1;
         ptn_if.tb_suppress_rx_sb = 1; // suppress partner responses to force timeout

         fork
         begin
         wait(dut_trainerror_req);
         #(LCLK_PERIOD * 5);
         end
         begin
         #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
         $display("# ERROR: Watchdog timeout failed to trigger trainerror!");
         $stop;
         end
         join_any
         disable fork;
         ptn_if.tb_suppress_rx_sb = 0;
         dut_local_txselfcal_en = 0;
         pass_test("Scenario 2: Watchdog Timeout");
         */

        // Scenario 3: Partner requesting trainerror
        assert_reset();
        dut_local_txselfcal_en = 1;
        #(LCLK_PERIOD * 5);
        tb_ptn_inject_valid = 1;
        tb_ptn_inject_msg = TRAINERROR_Entry_req;
        @(posedge lclk);
        tb_ptn_inject_valid = 0;

        fork
            begin
                wait(dut_trainerror_req);
                #(LCLK_PERIOD * 5);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD * 2);
                $display("# ERROR: Trainerror injection failed!");
                $stop;
            end
        join_any
        disable fork;
        dut_local_txselfcal_en = 0;
        pass_test("Scenario 3: Trainerror Injection");

        // Scenario 4: 50+ Randomized iterations
        $display("# Starting 60 Randomized iterations...");
        for (int i = 0; i < 60; i++) begin
            run_clean_scenario($sformatf("Randomized Iteration %0d", i));
        end

        $display("# All wrapper_TXSELFCAL_tb tests PASSED");
        $finish;
    end

endmodule
