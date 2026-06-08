`timescale 1ps/1ps
module wrapper_REPAIR_tb;

    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ;
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
        .ENABLE_LOOPBACK     (1'b0)
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ENABLE_LOOPBACK     (1'b0)
    ) ptn_attach (
        .intf(ptn_if)
    );

    // Control registers
    logic is_ltsm_out_of_reset = 1;
    logic tb_ptn_inject_valid = 0;
    logic [7:0] tb_ptn_inject_msg = 0;

    // Configurations for REPAIR
    logic [2:0]  local_tx_lane_map_code = 3'b001; // default x8 low
    logic        width_degrade_feasible = 1;
    logic [2:0]  mbinit_rx_data_lane_mask = 3'b011; // default x16
    logic [2:0]  mbinit_tx_data_lane_mask = 3'b011; // default x16
    logic        update_lane_mask = 0;

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
    logic        dut_local_repair_en = 0;
    logic        dut_local_repair_done;
    logic        dut_local_txselfcal_req;
    logic        dut_local_trainerror_req;
    logic        dut_partner_repair_en = 0;
    logic        dut_partner_repair_done;
    logic        dut_partner_trainerror_req;
    logic [2:0]  dut_mb_rx_data_lane_mask;
    logic [2:0]  dut_mb_tx_data_lane_mask;

    wrapper_REPAIR u_dut (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset),
        .timeout_8ms_occured    (dut_if.timeout_8ms_occured),
        .local_repair_en        (dut_local_repair_en),
        .local_repair_done      (dut_local_repair_done),
        .local_txselfcal_req    (dut_local_txselfcal_req),
        .local_trainerror_req   (dut_local_trainerror_req),
        .partner_repair_en      (dut_partner_repair_en),
        .partner_repair_done    (dut_partner_repair_done),
        .partner_trainerror_req (dut_partner_trainerror_req),
        .timeout_timer_en       (dut_if.timeout_timer_en),
        .local_tx_lane_map_code (local_tx_lane_map_code),
        .width_degrade_feasible (width_degrade_feasible),
        .mb_rx_data_lane_mask   (dut_mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask   (dut_mb_tx_data_lane_mask),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
        .update_lane_mask       (update_lane_mask),
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
    logic        ptn_local_repair_en = 0;
    logic        ptn_local_repair_done;
    logic        ptn_local_txselfcal_req;
    logic        ptn_local_trainerror_req;
    logic        ptn_partner_repair_en = 0;
    logic        ptn_partner_repair_done;
    logic        ptn_partner_trainerror_req;
    logic [2:0]  ptn_mb_rx_data_lane_mask;
    logic [2:0]  ptn_mb_tx_data_lane_mask;

    wrapper_REPAIR u_ptn (
        .lclk                   (lclk),
        .rst_n                  (rst_n),
        .is_ltsm_out_of_reset   (is_ltsm_out_of_reset),
        .timeout_8ms_occured    (ptn_if.timeout_8ms_occured),
        .local_repair_en        (ptn_local_repair_en),
        .local_repair_done      (ptn_local_repair_done),
        .local_txselfcal_req    (ptn_local_txselfcal_req),
        .local_trainerror_req   (ptn_local_trainerror_req),
        .partner_repair_en      (ptn_partner_repair_en),
        .partner_repair_done    (ptn_partner_repair_done),
        .partner_trainerror_req (ptn_partner_trainerror_req),
        .timeout_timer_en       (ptn_if.timeout_timer_en),
        .local_tx_lane_map_code (local_tx_lane_map_code),
        .width_degrade_feasible (width_degrade_feasible),
        .mb_rx_data_lane_mask   (ptn_mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask   (ptn_mb_tx_data_lane_mask),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
        .update_lane_mask       (update_lane_mask),
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

    task automatic run_scenario(
            input string name,
            input logic [2:0] map_code,
            input logic feasible,
            input logic expect_trainerror
        );
        assert_reset();

        local_tx_lane_map_code = map_code;
        width_degrade_feasible = feasible;

        dut_local_repair_en = 1;
        ptn_partner_repair_en = 1;
        dut_partner_repair_en = 1;
        ptn_local_repair_en = 1;

        fork
            begin
                if (expect_trainerror) begin
                    wait(dut_local_trainerror_req);
                end else begin
                    wait(dut_local_repair_done && ptn_partner_repair_done);
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

        if (!expect_trainerror) begin
            // Verify correct lane masks registered
            if (dut_mb_tx_data_lane_mask !== map_code) begin
                $display("# ERROR: DUT Tx lane mask mismatch! Got %0d, expected %0d", dut_mb_tx_data_lane_mask, map_code);
                $stop;
            end
            if (ptn_mb_rx_data_lane_mask !== map_code) begin
                $display("# ERROR: PTN Rx lane mask mismatch! Got %0d, expected %0d", ptn_mb_rx_data_lane_mask, map_code);
                $stop;
            end
        end

        dut_local_repair_en = 0;
        ptn_partner_repair_en = 0;
        dut_partner_repair_en = 0;
        ptn_local_repair_en = 0;
        #(LCLK_PERIOD * 10);
        pass_test(name);
    endtask

    initial begin
        dut_if.tb_suppress_rx_sb = 0;
        ptn_if.tb_suppress_rx_sb = 0;
        $display("# =========================================================");
        $display("# Running wrapper_REPAIR_tb                                ");
        $display("# =========================================================");

        // Scenario 1: Clean degradation run (x8 low map)
        run_scenario("Scenario 1: Feasible Degrade x8 low", 3'b001, 1, 0);

        // Scenario 2: Clean degradation run (x8 high map)
        run_scenario("Scenario 2: Feasible Degrade x8 high", 3'b010, 1, 0);

        // Scenario 3: Degrade not feasible -> TRAINERROR
        run_scenario("Scenario 3: Degrade not feasible -> TRAINERROR", 3'b000, 0, 1);

        // Scenario 4: Watchdog timeout
        assert_reset();
        dut_local_repair_en = 1;
        ptn_if.tb_suppress_rx_sb = 1;
        fork
            begin
                wait(dut_local_trainerror_req);
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
        dut_local_repair_en = 0;
        pass_test("Scenario 4: Watchdog Timeout");

        // Scenario 5: 50+ Randomized iterations
        $display("# Starting 60 Randomized iterations...");
        for (int i = 0; i < 60; i++) begin
            automatic bit [2:0] map_code_rnd = $urandom_range(1, 5); // x8 low, x8 high, x16, x4 low, x4 high
            run_scenario($sformatf("Randomized Iteration %0d", i), map_code_rnd, 1, 0);
        end

        $display("# All wrapper_REPAIR_tb tests PASSED");
        $finish;
    end

endmodule
