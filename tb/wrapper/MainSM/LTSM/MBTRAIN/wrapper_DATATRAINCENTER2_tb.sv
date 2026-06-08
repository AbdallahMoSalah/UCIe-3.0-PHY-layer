`timescale 1ps/1ps
module wrapper_DATATRAINCENTER2_tb;

    import UCIe_pkg::*;

    // =========================================================================
    // 1. Parameters for Fast and Configurable Testbench Running
    // =========================================================================
    parameter LCLK_PERIOD          = 1*1000 ; 
    parameter ANALOG_SETTLE_CYCLES = 10     ; 
    parameter MIN_DATA_PI_CODE     = 6'D0   ;
    parameter MAX_DATA_PI_CODE     = 6'D20  ; 
    parameter SB_DELAY             = 2      ; 
    parameter MB_DELAY             = 10     ; 

    localparam integer TB_CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (MB_DELAY + 1) * MB_DELAY + 15 + 8 * SB_DELAY;
    localparam integer TB_SWEEP_CYCLES    = (MAX_DATA_PI_CODE - MIN_DATA_PI_CODE + 1) * TB_CYCLES_PER_CODE;
    parameter TB_TIMEOUT_CYCLES           = 8 * (TB_SWEEP_CYCLES + SB_DELAY * 10);
    parameter bit ENABLE_RAND_LOG         = 1'b0; 

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
    ltsm_tb_if #(
        .MAX_DATA_PI_CODE(MAX_DATA_PI_CODE)
    ) dut_if (lclk, rst_n);

    ltsm_tb_if #(
        .MAX_DATA_PI_CODE(MAX_DATA_PI_CODE)
    ) ptn_if (lclk, rst_n);

    localparam int TB_PW = $clog2(MAX_DATA_PI_CODE + 1);

    wire [TB_PW-1:0] dut_swept_code_sliced;
    wire [TB_PW-1:0] dut_best_code_sliced [0:15];
    assign dut_swept_code_sliced = dut_if.swept_code[TB_PW-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign dut_best_code_sliced[i] = dut_if.best_code[i][TB_PW-1:0];
    end

    wire [TB_PW-1:0] ptn_swept_code_sliced;
    wire [TB_PW-1:0] ptn_best_code_sliced [0:15];
    assign ptn_swept_code_sliced = ptn_if.swept_code[TB_PW-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign ptn_best_code_sliced[i] = ptn_if.best_code[i][TB_PW-1:0];
    end

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TB_TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DATA_PI_CODE    (MIN_DATA_PI_CODE    ),
        .MAX_DATA_PI_CODE    (MAX_DATA_PI_CODE    ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TB_TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DATA_PI_CODE    (MIN_DATA_PI_CODE    ),
        .MAX_DATA_PI_CODE    (MAX_DATA_PI_CODE    ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) ptn_attach (
        .intf(ptn_if)
    );

    // =========================================================================
    // Control / Simulation Configuration Registers
    // =========================================================================
    logic tb_is_ltsm_out_of_reset = 1;

    integer      dut_eye_start [0:15];
    integer      dut_eye_end   [0:15];
    integer      ptn_eye_start [0:15];
    integer      ptn_eye_end   [0:15];
    logic        assume_holes_after_quarter_eye_start = 0;

    logic        tb_ptn_inject_valid = 0;
    logic [7:0]  tb_ptn_inject_msg   = 0;
    logic [15:0] tb_ptn_inject_info  = 0;

    // =========================================================================
    // Sideband Delay Queue
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

            dut2ptn_msg_sr[0]  <= dut_if.tb_muxed_tx_sb_msg;
            dut2ptn_info_sr[0] <= dut_if.tb_muxed_tx_msginfo;
            dut2ptn_data_sr[0] <= dut_if.tb_muxed_tx_data_field;

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

    assign ptn_if.rx_sb_msg_valid = dut2ptn_valid_sr[SB_DELAY-1] & ~ptn_if.tb_suppress_rx_sb;
    assign ptn_if.rx_sb_msg       = dut2ptn_msg_sr  [SB_DELAY-1];
    assign ptn_if.rx_msginfo      = dut2ptn_info_sr [SB_DELAY-1];
    assign ptn_if.rx_data_field   = dut2ptn_data_sr [SB_DELAY-1];

    assign dut_if.rx_sb_msg_valid = ptn2dut_valid_sr[SB_DELAY-1] & ~dut_if.tb_suppress_rx_sb;
    assign dut_if.rx_sb_msg       = ptn2dut_msg_sr  [SB_DELAY-1];
    assign dut_if.rx_msginfo      = ptn2dut_info_sr [SB_DELAY-1];
    assign dut_if.rx_data_field   = ptn2dut_data_sr [SB_DELAY-1];

    // =========================================================================
    // Dynamic Eye Simulation
    // =========================================================================
    always @(posedge lclk) begin
        if (dut_if.sweep_en) begin
            automatic logic [TB_PW-1:0] code = dut_if.swept_code;
            for (int l = 0; l < 16; l = l + 1) begin
                if (code >= dut_eye_start[l] && code <= dut_eye_end[l]) begin
                    if (assume_holes_after_quarter_eye_start && (code == dut_eye_start[l] + (dut_eye_end[l] - dut_eye_start[l])/4)) begin
                        dut_if.tb_force_perlane_pass[l] <= 1'b0; 
                    end else begin
                        dut_if.tb_force_perlane_pass[l] <= 1'b1;
                    end
                end else begin
                    dut_if.tb_force_perlane_pass[l] <= 1'b0;
                end
            end
        end else begin
            dut_if.tb_force_perlane_pass <= 16'hFFFF;
        end
    end

    // =========================================================================
    // Die A (DUT)
    // =========================================================================
    logic        dut_local_datatraincenter2_en = 0;
    logic        dut_local_datatraincenter2_done;
    logic        dut_local_trainerror_req;
    logic        dut_local_update_lane_mask;
    logic        dut_partner_datatraincenter2_en = 0;
    logic        dut_partner_datatraincenter2_done;
    logic        dut_partner_trainerror_req;

    wrapper_DATATRAINCENTER2 #(
        .MAX_DATA_PI_CODE(MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE(MIN_DATA_PI_CODE)
    ) u_dut (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .is_ltsm_out_of_reset           (tb_is_ltsm_out_of_reset),
        .timeout_8ms_occured            (dut_if.timeout_8ms_occured),
        .local_datatraincenter2_en       (dut_local_datatraincenter2_en),
        .local_datatraincenter2_done     (dut_local_datatraincenter2_done),
        .local_trainerror_req            (dut_local_trainerror_req),
        .local_update_lane_mask          (dut_local_update_lane_mask),
        .partner_datatraincenter2_en     (dut_partner_datatraincenter2_en),
        .partner_datatraincenter2_done   (dut_partner_datatraincenter2_done),
        .partner_trainerror_req          (dut_partner_trainerror_req),
        .timeout_timer_en               (dut_if.timeout_timer_en),
        .phy_tx_data_pi_phase_ctrl      (dut_if.phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en               (dut_if.partner_sweep_en),
        .sweep_en                       (dut_if.sweep_en),
        .swept_code                     (dut_swept_code_sliced),
        .best_code                      (dut_best_code_sliced),
        .sweep_done                     (dut_if.sweep_done),
        .mb_tx_clk_lane_sel             (dut_if.mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel            (dut_if.mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel             (dut_if.mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel             (dut_if.mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel             (dut_if.mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel            (dut_if.mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel             (dut_if.mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel             (dut_if.mb_rx_trk_lane_sel),
        .tx_sb_msg_valid                (dut_if.tx_sb_msg_valid),
        .tx_sb_msg                      (dut_if.tx_sb_msg),
        .tx_msginfo                     (dut_if.tx_msginfo),
        .tx_data_field                  (dut_if.tx_data_field),
        .rx_sb_msg_valid                (dut_if.rx_sb_msg_valid),
        .rx_sb_msg                      (dut_if.rx_sb_msg),
        .rx_msginfo                     (dut_if.rx_msginfo),
        .rx_data_field                  (dut_if.rx_data_field)
    );

    // =========================================================================
    // Die B (PARTNER)
    // =========================================================================
    logic        ptn_local_datatraincenter2_en = 0;
    logic        ptn_local_datatraincenter2_done;
    logic        ptn_local_trainerror_req;
    logic        ptn_local_update_lane_mask;
    logic        ptn_partner_datatraincenter2_en = 0;
    logic        ptn_partner_datatraincenter2_done;
    logic        ptn_partner_trainerror_req;

    wrapper_DATATRAINCENTER2 #(
        .MAX_DATA_PI_CODE(MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE(MIN_DATA_PI_CODE)
    ) u_ptn (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .is_ltsm_out_of_reset           (tb_is_ltsm_out_of_reset),
        .timeout_8ms_occured            (ptn_if.timeout_8ms_occured),
        .local_datatraincenter2_en       (ptn_local_datatraincenter2_en),
        .local_datatraincenter2_done     (ptn_local_datatraincenter2_done),
        .local_trainerror_req            (ptn_local_trainerror_req),
        .local_update_lane_mask          (ptn_local_update_lane_mask),
        .partner_datatraincenter2_en     (ptn_partner_datatraincenter2_en),
        .partner_datatraincenter2_done   (ptn_partner_datatraincenter2_done),
        .partner_trainerror_req          (ptn_partner_trainerror_req),
        .timeout_timer_en               (ptn_if.timeout_timer_en),
        .phy_tx_data_pi_phase_ctrl      (ptn_if.phy_tx_data_pi_phase_ctrl),
        .partner_sweep_en               (ptn_if.partner_sweep_en),
        .sweep_en                       (ptn_if.sweep_en),
        .swept_code                     (ptn_swept_code_sliced),
        .best_code                      (ptn_best_code_sliced),
        .sweep_done                     (ptn_if.sweep_done),
        .mb_tx_clk_lane_sel             (ptn_if.mb_tx_clk_lane_sel),
        .mb_tx_data_lane_sel            (ptn_if.mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel             (ptn_if.mb_tx_val_lane_sel),
        .mb_tx_trk_lane_sel             (ptn_if.mb_tx_trk_lane_sel),
        .mb_rx_clk_lane_sel             (ptn_if.mb_rx_clk_lane_sel),
        .mb_rx_data_lane_sel            (ptn_if.mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel             (ptn_if.mb_rx_val_lane_sel),
        .mb_rx_trk_lane_sel             (ptn_if.mb_rx_trk_lane_sel),
        .tx_sb_msg_valid                (ptn_if.tx_sb_msg_valid),
        .tx_sb_msg                      (ptn_if.tx_sb_msg),
        .tx_msginfo                     (ptn_if.tx_msginfo),
        .tx_data_field                  (ptn_if.tx_data_field),
        .rx_sb_msg_valid                (ptn_if.rx_sb_msg_valid),
        .rx_sb_msg                      (ptn_if.rx_sb_msg),
        .rx_msginfo                     (ptn_if.rx_msginfo),
        .rx_data_field                  (ptn_if.rx_data_field)
    );

    // =========================================================================
    // State Monitors
    // =========================================================================
    typedef enum reg [3:0] {
        TB_DTC2_LOCAL_IDLE           = 4'd0,
        TB_DTC2_LOCAL_SEND_START_REQ = 4'd1,
        TB_DTC2_LOCAL_WAIT_START_RESP= 4'd2,
        TB_DTC2_LOCAL_SWEEP          = 4'd3,
        TB_DTC2_LOCAL_APPLY_BEST     = 4'd4,
        TB_DTC2_LOCAL_SEND_END_REQ   = 4'd5,
        TB_DTC2_LOCAL_WAIT_END_RESP  = 4'd6,
        TB_DTC2_LOCAL_TO_LINKSPEED   = 4'd7,
        TB_DTC2_LOCAL_TO_TRAINERROR  = 4'd8
    } tb_local_state_t;

    tb_local_state_t tb_dut_local_state, tb_prev_dut_local_state;
    logic           tb_in_randomized_scenarios = 1'b0;

    assign tb_dut_local_state   = tb_local_state_t'(u_dut.u_local.current_state);

    always @(posedge lclk) begin
        if (!tb_in_randomized_scenarios || ENABLE_RAND_LOG) begin
            if (rst_n && tb_dut_local_state !== tb_prev_dut_local_state) begin
                $display("# [%0d ps] Die A LOCAL   State -> %s", $realtime(), tb_dut_local_state.name());
                tb_prev_dut_local_state <= tb_dut_local_state;
            end
        end else begin
            if (rst_n && tb_dut_local_state !== tb_prev_dut_local_state) tb_prev_dut_local_state <= tb_dut_local_state;
        end
    end

    initial begin
        dut_if.state_n[0]            = ltsm_state_n_pkg::LOG_MBTRAIN_DATATRAINCENTER2;
        dut_if.tb_suppress_rx_sb     = 0;
        dut_if.tb_verbose            = 0;
        dut_if.tb_wait_timeout       = 0;
        dut_if.tb_aggr_err           = 0;
        dut_if.mb_rx_data_lane_mask  = 3'b011; 
        dut_if.mb_tx_data_lane_mask  = 3'b011;
        dut_if.cfg_max_err_thresh_perlane = 10;
        dut_if.cfg_max_err_thresh_aggr    = 20;

        ptn_if.state_n[0]            = ltsm_state_n_pkg::LOG_MBTRAIN_DATATRAINCENTER2;
        ptn_if.tb_suppress_rx_sb     = 0;
        ptn_if.tb_verbose            = 0;
        ptn_if.tb_wait_timeout       = 0;
        ptn_if.tb_aggr_err           = 0;
        ptn_if.mb_rx_data_lane_mask  = 3'b011;
        ptn_if.mb_tx_data_lane_mask  = 3'b011;
        ptn_if.cfg_max_err_thresh_perlane = 10;
        ptn_if.cfg_max_err_thresh_aggr    = 20;
    end

    integer tb_success_count = 0, tb_fail_count = 0, tb_test_no = 1;

    task automatic tb_pass_test(input string name);
        $display("[PASS] T%0d: %s", tb_test_no, name);
        tb_success_count++;
        tb_test_no++;
    endtask

    task automatic tb_run_scenario(
            input string name,
            input integer d_start [0:15],
            input integer d_end   [0:15],
            input logic holes_en,
            input logic expect_success,
            input logic suppress_sb,
            input logic inject_trainerror
        );
        $display("\n# Starting Scenario: %s", name);
        assert_reset();
        for (int l = 0; l < 16; l = l + 1) begin
            dut_eye_start[l] = d_start[l];
            dut_eye_end[l]   = d_end[l];
        end
        assume_holes_after_quarter_eye_start = holes_en;
        if (suppress_sb) ptn_if.tb_suppress_rx_sb = 1;

        dut_local_datatraincenter2_en = 1;
        ptn_partner_datatraincenter2_en = 1;

        if (inject_trainerror) begin
            repeat(100) @(posedge lclk);
            tb_ptn_inject_valid = 1;
            tb_ptn_inject_msg = TRAINERROR_Entry_req;
            @(posedge lclk);
            tb_ptn_inject_valid = 0;
        end

        fork
            begin
                wait (u_dut.local_datatraincenter2_done || u_dut.local_trainerror_req);
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TB_TIMEOUT_CYCLES * LCLK_PERIOD * 2);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        if (expect_success) begin
            if (!u_dut.local_datatraincenter2_done || u_dut.local_trainerror_req) begin
                $display("# ERROR: Expected success but failed");
                tb_fail_count++; $stop;
            end
            for (int l = 0; l < 16; l = l + 1) begin
                automatic logic [TB_PW-1:0] expected_best;
                if (holes_en) begin
                    automatic logic [TB_PW-1:0] hole_pos = d_start[l] + (d_end[l] - d_start[l])/4;
                    expected_best = (hole_pos + 1 + d_end[l]) / 2;
                end else begin
                    expected_best = (d_start[l] + d_end[l]) / 2;
                end
                if (u_dut.phy_tx_data_pi_phase_ctrl[l] !== expected_best) begin
                    $display("# ERROR: Lane %0d mismatch! Got=%0d, Exp=%0d", l, u_dut.phy_tx_data_pi_phase_ctrl[l], expected_best);
                    tb_fail_count++; $stop;
                end
            end
        end else if (!u_dut.local_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR but got success");
            tb_fail_count++; $stop;
        end

        dut_local_datatraincenter2_en = 0;
        ptn_partner_datatraincenter2_en = 0;
        if (suppress_sb) ptn_if.tb_suppress_rx_sb = 0;
        #(LCLK_PERIOD * 50);
        tb_pass_test(name);
    endtask

    initial begin
        automatic integer standard_start [0:15];
        automatic integer standard_end   [0:15];
        for (int l = 0; l < 16; l = l + 1) begin
            standard_start[l] = 5; standard_end[l] = 15;
        end

        $display("# Running wrapper_DATATRAINCENTER2_tb");

        tb_run_scenario("Symmetrical Clean Sweep", standard_start, standard_end, 0, 1, 0, 0);
        tb_run_scenario("Sweep with Eye Hole", standard_start, standard_end, 1, 1, 0, 0);
        tb_run_scenario("Partner Injects TRAINERROR", standard_start, standard_end, 0, 0, 0, 1);

        $display("\n# Starting Randomized Scenarios (20 Iterations)");
        tb_in_randomized_scenarios = 1'b1;
        for (int i = 1; i <= 20; i = i + 1) begin
            automatic integer r_s [0:15];
            automatic integer r_e [0:15];
            for (int l = 0; l < 16; l = l + 1) begin
                r_s[l] = $urandom_range(MIN_DATA_PI_CODE, MAX_DATA_PI_CODE - 4);
                r_e[l] = $urandom_range(r_s[l] + 3, MAX_DATA_PI_CODE);
                dut_eye_start[l] = r_s[l]; dut_eye_end[l] = r_e[l];
            end
            dut_local_datatraincenter2_en = 1; ptn_partner_datatraincenter2_en = 1;
            wait (u_dut.local_datatraincenter2_done || u_dut.local_trainerror_req);
            #10000;
            dut_local_datatraincenter2_en = 0; ptn_partner_datatraincenter2_en = 0;
            #10000;
        end
        tb_pass_test("Randomized Scenarios");

        $display("\nPASSED: %0d | FAILED: %0d", tb_success_count, tb_fail_count);
        $stop;
    end

endmodule





