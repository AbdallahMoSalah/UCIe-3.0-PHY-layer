`timescale 1ps/1ps
module wrapper_VALTRAINCENTER_tb;

    import UCIe_pkg::*;

    // =========================================================================
    // 1. Parameters for Fast and Configurable Testbench Running
    // =========================================================================
    parameter LCLK_PERIOD          = 1*1000 ; // lclk period = 1ns (1GHz)
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait for settling
    parameter MIN_VAL_PI_CODE      = 7'D1   ;
    parameter MAX_VAL_PI_CODE      = 7'D16  ;
    parameter SB_DELAY             = 20     ; // Delay in lclk cycles.
    parameter MB_DELAY             = 10     ; // Speed knob: reduce iteration time

    localparam integer CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (MB_DELAY + 1) * MB_DELAY + 15 + 8 * SB_DELAY;
    localparam integer SWEEP_CYCLES    = (MAX_VAL_PI_CODE - MIN_VAL_PI_CODE + 1) * CYCLES_PER_CODE;
    parameter TIMEOUT_CYCLES           = 8 * (SWEEP_CYCLES + SB_DELAY * 10);
    parameter bit ENABLE_RAND_LOG      = 1'b0; // 1: display details of randomized scenarios in terminal

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
    // Instantiate with default MAX parameter values set to 16
    ltsm_tb_if #(
        .MAX_VAL_PI_CODE(MAX_VAL_PI_CODE)
    ) dut_if (lclk, rst_n);

    ltsm_tb_if #(
        .MAX_VAL_PI_CODE(MAX_VAL_PI_CODE)
    ) ptn_if (lclk, rst_n);

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DESKEW_CODE     (MIN_VAL_PI_CODE     ), // Map PI code range to deskew parameter for D2C PT config
        .MAX_DESKEW_CODE     (MAX_VAL_PI_CODE     ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DESKEW_CODE     (MIN_VAL_PI_CODE     ),
        .MAX_DESKEW_CODE     (MAX_VAL_PI_CODE     ),
        .MB_DELAY            (MB_DELAY            )
    ) ptn_attach (
        .intf(ptn_if)
    );

    // =========================================================================
    // Control / Simulation Configuration Registers
    // =========================================================================
    logic is_ltsm_out_of_reset = 1;
    logic timeout_8ms_occured = 0;

    // Eye Simulation parameters
    integer      dut_eye_start;
    integer      dut_eye_end;

    integer      ptn_eye_start;
    integer      ptn_eye_end;

    logic        assume_holes_after_quarter_eye_start = 0;

    // Testbench sideband injection for Die B (Partner)
    logic        tb_ptn_inject_valid = 0;
    logic [7:0]  tb_ptn_inject_msg   = 0;
    logic [15:0] tb_ptn_inject_info  = 0;

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
            automatic logic [6:0] code = dut_if.swept_code;
            if (code >= dut_eye_start && code <= dut_eye_end) begin
                if (assume_holes_after_quarter_eye_start && (code == dut_eye_start + (dut_eye_end - dut_eye_start)/4)) begin
                    dut_if.tb_force_val_pass <= 1'b0;
                end else begin
                    dut_if.tb_force_val_pass <= 1'b1;
                end
            end else begin
                dut_if.tb_force_val_pass <= 1'b0;
            end
        end else begin
            dut_if.tb_force_val_pass <= 1'b1;
        end
    end

    always @(posedge lclk) begin
        if (ptn_if.sweep_en) begin
            automatic logic [6:0] code = ptn_if.swept_code;
            if (code >= ptn_eye_start && code <= ptn_eye_end) begin
                if (assume_holes_after_quarter_eye_start && (code == ptn_eye_start + (ptn_eye_end - ptn_eye_start)/4)) begin
                    ptn_if.tb_force_val_pass <= 1'b0;
                end else begin
                    ptn_if.tb_force_val_pass <= 1'b1;
                end
            end else begin
                ptn_if.tb_force_val_pass <= 1'b0;
            end
        end else begin
            ptn_if.tb_force_val_pass <= 1'b1;
        end
    end

    // =========================================================================
    // Sliced connections to avoid port size mismatch with unpacked arrays / parameters
    // =========================================================================
    localparam int PI_W = $clog2(MAX_VAL_PI_CODE + 1);

    wire [PI_W-1:0] dut_swept_code_sliced;
    wire [PI_W-1:0] dut_best_code_sliced [0:15];
    assign dut_swept_code_sliced = dut_if.swept_code[PI_W-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign dut_best_code_sliced[i] = dut_if.best_code[i][PI_W-1:0];
    end

    wire [PI_W-1:0] ptn_swept_code_sliced;
    wire [PI_W-1:0] ptn_best_code_sliced [0:15];
    assign ptn_swept_code_sliced = ptn_if.swept_code[PI_W-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign ptn_best_code_sliced[i] = ptn_if.best_code[i][PI_W-1:0];
    end

    // =========================================================================
    // Die A Instantiation (DUT)
    // =========================================================================
    logic        dut_local_en = 0;
    logic        dut_local_done;
    logic        dut_local_trainerror_req;
    logic        dut_local_update_lane_mask;

    logic        dut_partner_en = 0;
    logic        dut_partner_done;
    logic        dut_partner_trainerror_req;

    wrapper_VALTRAINCENTER #(
        .MAX_VAL_PI_CODE(MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE(MIN_VAL_PI_CODE)
    ) u_dut (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset),
        .timeout_8ms_occured            (dut_if.timeout_8ms_occured),

        .local_valtraincenter_en        (dut_local_en),
        .local_valtraincenter_done      (dut_local_done),
        .local_trainerror_req           (dut_local_trainerror_req),
        .local_update_lane_mask         (dut_local_update_lane_mask),

        .partner_valtraincenter_en      (dut_partner_en),
        .partner_valtraincenter_done    (dut_partner_done),
        .partner_trainerror_req         (dut_partner_trainerror_req),

        .timeout_timer_en               (dut_if.timeout_timer_en),
        .phy_tx_val_pi_phase_ctrl       (dut_if.phy_tx_val_pi_phase_ctrl),
        .partner_sweep_en               (dut_if.partner_sweep_en),

        .sweep_en                       (dut_if.sweep_en),
        .swept_code                     (dut_swept_code_sliced),
        .best_code                      (dut_best_code_sliced),
        .sweep_done                     (dut_if.sweep_done),

        .mb_tx_continuous_or_strobe_clk(1'b0),
        .phy_negotiated_speed          (3'b101), // SPEED_32G

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
    // Die B Instantiation (PARTNER)
    // =========================================================================
    logic        ptn_local_en = 0;
    logic        ptn_local_done;
    logic        ptn_local_trainerror_req;
    logic        ptn_local_update_lane_mask;

    logic        ptn_partner_en = 0;
    logic        ptn_partner_done;
    logic        ptn_partner_trainerror_req;

    wrapper_VALTRAINCENTER #(
        .MAX_VAL_PI_CODE(MAX_VAL_PI_CODE),
        .MIN_VAL_PI_CODE(MIN_VAL_PI_CODE)
    ) u_ptn (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .is_ltsm_out_of_reset           (is_ltsm_out_of_reset),
        .timeout_8ms_occured            (ptn_if.timeout_8ms_occured),

        .local_valtraincenter_en        (ptn_local_en),
        .local_valtraincenter_done      (ptn_local_done),
        .local_trainerror_req           (ptn_local_trainerror_req),
        .local_update_lane_mask         (ptn_local_update_lane_mask),

        .partner_valtraincenter_en      (ptn_partner_en),
        .partner_valtraincenter_done    (ptn_partner_done),
        .partner_trainerror_req         (ptn_partner_trainerror_req),

        .timeout_timer_en               (ptn_if.timeout_timer_en),
        .phy_tx_val_pi_phase_ctrl       (ptn_if.phy_tx_val_pi_phase_ctrl),
        .partner_sweep_en               (ptn_if.partner_sweep_en),

        .sweep_en                       (ptn_if.sweep_en),
        .swept_code                     (ptn_swept_code_sliced),
        .best_code                      (ptn_best_code_sliced),
        .sweep_done                     (ptn_if.sweep_done),

        .mb_tx_continuous_or_strobe_clk(1'b0),
        .phy_negotiated_speed          (3'b101), // SPEED_32G

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
        VALTRAINCENTER_LOCAL_IDLE           = 4'd0,
        VALTRAINCENTER_LOCAL_SEND_START_REQ = 4'd1,
        VALTRAINCENTER_LOCAL_WAIT_START_RESP= 4'd2,
        VALTRAINCENTER_LOCAL_SWEEP          = 4'd3,
        VALTRAINCENTER_LOCAL_APPLY_BEST     = 4'd4,
        VALTRAINCENTER_LOCAL_SEND_DONE_REQ  = 4'd5,
        VALTRAINCENTER_LOCAL_WAIT_DONE_RESP = 4'd6,
        VALTRAINCENTER_LOCAL_TO_VALTRAINVREF= 4'd7,
        VALTRAINCENTER_LOCAL_TO_TRAINERROR  = 4'd8
    } local_state_t;

    typedef enum reg [3:0] {
        VALTRAINCENTER_PTR_IDLE            = 4'd0,
        VALTRAINCENTER_PTR_WAIT_START_REQ  = 4'd1,
        VALTRAINCENTER_PTR_SEND_START_RESP = 4'd2,
        VALTRAINCENTER_PTR_WAIT_DONE_REQ   = 4'd3,
        VALTRAINCENTER_PTR_SEND_DONE_RESP  = 4'd4,
        VALTRAINCENTER_PTR_TO_VALTRAINVREF = 4'd5,
        VALTRAINCENTER_PTR_TO_TRAINERROR   = 4'd6
    } partner_state_t;

    local_state_t dut_local_state, prev_dut_local_state;
    partner_state_t dut_partner_state, prev_dut_partner_state;
    logic           in_randomized_scenarios = 1'b0;

    assign dut_local_state   = local_state_t'(u_dut.u_local.current_state);
    assign dut_partner_state = partner_state_t'(u_dut.u_partner.current_state);

    function string get_short_msg_name(msg_no_e msg);
        case (msg)
            MBTRAIN_VALTRAINCENTER_start_req  : return "START_REQ";
            MBTRAIN_VALTRAINCENTER_start_resp : return "START_RESP";
            MBTRAIN_VALTRAINCENTER_done_req   : return "DONE_REQ";
            MBTRAIN_VALTRAINCENTER_done_resp  : return "DONE_RESP";
            TRAINERROR_Entry_req              : return "TRAINERROR_REQ";
            default                           : return "OTHER_SB_MSG";
        endcase
    endfunction

    // Print monitors with OTHER_SB_MSG suppressed
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
                automatic string name = get_short_msg_name(msg_no_e'(dut_if.rx_sb_msg));
                if (name != "OTHER_SB_MSG") begin
                    $display("# [%0d ps] DEBUG: Die A RX SB Msg from Die B: %s (MsgCode: 8'h%h, MsgInfo: 16'h%h)",
                        $realtime(), name, dut_if.rx_sb_msg, dut_if.rx_msginfo);
                end
            end
        end else begin
            if (rst_n && dut_local_state !== prev_dut_local_state) prev_dut_local_state <= dut_local_state;
            if (rst_n && dut_partner_state !== prev_dut_partner_state) prev_dut_partner_state <= dut_partner_state;
        end
    end

    // Default parameters setup
    initial begin
        dut_if.state_n[0]            = ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINCENTER;
        dut_if.tb_suppress_rx_sb     = 0;
        dut_if.tb_force_val_pass     = 1;
        dut_if.tb_verbose            = 0;
        dut_if.tb_wait_timeout       = 0;
        dut_if.tb_aggr_err           = 0;
        dut_if.cfg_max_err_thresh_perlane = 10;
        dut_if.cfg_max_err_thresh_aggr    = 20;

        ptn_if.state_n[0]            = ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINCENTER;
        ptn_if.tb_suppress_rx_sb     = 0;
        ptn_if.tb_force_val_pass     = 1;
        ptn_if.tb_verbose            = 0;
        ptn_if.tb_wait_timeout       = 0;
        ptn_if.tb_aggr_err           = 0;
        ptn_if.cfg_max_err_thresh_perlane = 10;
        ptn_if.cfg_max_err_thresh_aggr    = 20;
    end

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
            input integer d_start,
            input integer d_end,
            input integer p_start,
            input integer p_end,
            input logic holes_en,
            input logic expect_done_dut,
            input logic expect_te_dut,
            input logic suppress_sb,
            input logic inject_trainerror
        );
        $display("\n\n# =========================================================");
        $display("# Starting Scenario: %s", name);
        $display("# Config  : dut_eye=[%0d,%0d], ptn_eye=[%0d,%0d], holes=%b", d_start, d_end, p_start, p_end, holes_en);
        $display("# =========================================================");

        assert_reset();

        dut_eye_start = d_start;
        dut_eye_end   = d_end;
        ptn_eye_start = p_start;
        ptn_eye_end   = p_end;
        assume_holes_after_quarter_eye_start = holes_en;

        if (suppress_sb) begin
            ptn_if.tb_suppress_rx_sb = 1;
            fork
                begin
                    wait (dut_if.timeout_timer_en == 1);
                    repeat(200) @(posedge lclk);
                    force dut_if.timeout_8ms_occured = 1;
                    @(posedge lclk);
                    release dut_if.timeout_8ms_occured;
                end
            join_none
        end

        // Enable FSMs
        dut_local_en = 1;
        ptn_local_en = 1;
        dut_partner_en = 1;
        ptn_partner_en = 1;

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
                wait (u_dut.local_valtraincenter_done || u_dut.local_trainerror_req);
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        // Verify FSM exits and calibrated midpoint code
        if (expect_done_dut) begin
            if (!u_dut.local_valtraincenter_done || u_dut.local_trainerror_req) begin
                $display("# ERROR: Expected successful VALTRAINCENTER exit, but got local_done=%b, trainerror=%b", u_dut.local_valtraincenter_done, u_dut.local_trainerror_req);
                fail_count++; $stop;
            end
            
            // Check calibrated PI code
            begin
                automatic logic [PI_W-1:0] expected_best;
                if (holes_en) begin
                    automatic logic [PI_W-1:0] hole_pos = d_start + (d_end - d_start)/4;
                    expected_best = (hole_pos + 1 + d_end) / 2;
                end else begin
                    expected_best = (d_start + d_end) / 2;
                end
                if (u_dut.phy_tx_val_pi_phase_ctrl !== expected_best) begin
                    $display("# ERROR: Calibrated midpoint mismatch! Obtained=%0d, Expected=%0d", u_dut.phy_tx_val_pi_phase_ctrl, expected_best);
                    fail_count++; $stop;
                end
            end
        end

        if (expect_te_dut && !u_dut.local_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR on Die A, but got trainerror_req=%b", u_dut.local_trainerror_req);
            fail_count++; $stop;
        end

        // Clean up FSM enables
        dut_local_en = 0;
        ptn_local_en = 0;
        dut_partner_en = 0;
        ptn_partner_en = 0;
        if (suppress_sb) ptn_if.tb_suppress_rx_sb = 0;

        #(LCLK_PERIOD * 50);
        pass_test(name);
    endtask

    // =========================================================================
    // Main Test Program
    // =========================================================================
    initial begin
        dut_if.state_n[0] = ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINCENTER;
        ptn_if.state_n[0] = ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINCENTER;
        $display("# =========================================================");
        $display("# Running wrapper_VALTRAINCENTER_tb                        ");
        $display("# =========================================================");

        // Scenario 1: Happy symmetric sweep
        run_scenario(
            .name("Scenario 1: Symmetrical Clean Sweep"),
            .d_start(3), .d_end(13),
            .p_start(3), .p_end(13),
            .holes_en(0),
            .expect_done_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 2: Asymmetric sweep (Die A finishes first)
        run_scenario(
            .name("Scenario 2: Asymmetric Sweep (DUT narrower eye)"),
            .d_start(5), .d_end(11),
            .p_start(2), .p_end(15),
            .holes_en(0),
            .expect_done_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 3: Asymmetric sweep (Die B finishes first / DUT wider eye)
        run_scenario(
            .name("Scenario 3: Asymmetric Sweep (DUT wider eye)"),
            .d_start(2), .d_end(15),
            .p_start(5), .p_end(11),
            .holes_en(0),
            .expect_done_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 4: Sweep with Hole in passing window
        run_scenario(
            .name("Scenario 4: Sweep with Eye Hole"),
            .d_start(2), .d_end(14),
            .p_start(2), .p_end(14),
            .holes_en(1),
            .expect_done_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 5: Multi-run without reset
        $display("\n\n# =========================================================");
        $display("# Starting Scenario 5: Multi-run without Reset");
        $display("# =========================================================");
        dut_eye_start = 3; dut_eye_end = 13; ptn_eye_start = 3; ptn_eye_end = 13;
        assume_holes_after_quarter_eye_start = 0;
        dut_local_en = 1; ptn_local_en = 1;
        dut_partner_en = 1; ptn_partner_en = 1;
        wait (u_dut.local_valtraincenter_done);
        #1000;
        dut_local_en = 0; ptn_local_en = 0;
        dut_partner_en = 0; ptn_partner_en = 0;
        #10000;

        // Run 2
        dut_eye_start = 6; dut_eye_end = 12; ptn_eye_start = 6; ptn_eye_end = 12;
        dut_local_en = 1; ptn_local_en = 1;
        dut_partner_en = 1; ptn_partner_en = 1;
        wait (u_dut.local_valtraincenter_done);
        #1000;
        if (u_dut.phy_tx_val_pi_phase_ctrl !== 7'd9) begin
            $display("# ERROR: Multi-run 2 Vref value mismatch! Got %0d, expected 9", u_dut.phy_tx_val_pi_phase_ctrl);
            $stop;
        end
        dut_local_en = 0; ptn_local_en = 0;
        dut_partner_en = 0; ptn_partner_en = 0;
        #10000;
        pass_test("Scenario 5: Multi-run without Reset");

        // Scenario 6: 8ms watchdog timeout -> TRAINERROR
        run_scenario(
            .name("Scenario 6: Watchdog Timeout -> TRAINERROR"),
            .d_start(2), .d_end(12),
            .p_start(2), .p_end(12),
            .holes_en(0),
            .expect_done_dut(0), .expect_te_dut(1),
            .suppress_sb(1), .inject_trainerror(0)
        );

        // Scenario 7: Injected TRAINERROR from partner
        run_scenario(
            .name("Scenario 7: Partner Injects TRAINERROR"),
            .d_start(2), .d_end(12),
            .p_start(2), .p_end(12),
            .holes_en(0),
            .expect_done_dut(0), .expect_te_dut(1),
            .suppress_sb(0), .inject_trainerror(1)
        );

        // =========================================================================
        // 8. Randomized Scenarios Block with Self-Checking
        // =========================================================================
        in_randomized_scenarios = 1'b1;
        $display("\n\n# =========================================================");
        $display("# Starting Randomized Scenarios (100 Iterations without reset)");
        $display("# =========================================================");

        assert_reset();

        for (int i = 1; i <= 100; i = i + 1) begin
            automatic integer start_rnd = $urandom_range(MIN_VAL_PI_CODE, MAX_VAL_PI_CODE - 4);
            automatic integer end_rnd   = $urandom_range(start_rnd + 3, MAX_VAL_PI_CODE);
            automatic bit holes_rnd     = $urandom_range(0, 1);

            if (ENABLE_RAND_LOG) begin
                $display("Rand scenario %0d: eye=[%0d,%0d] holes=%b", i, start_rnd, end_rnd, holes_rnd);
            end

            dut_eye_start = start_rnd;
            dut_eye_end   = end_rnd;
            ptn_eye_start = start_rnd;
            ptn_eye_end   = end_rnd;
            assume_holes_after_quarter_eye_start = holes_rnd;

            // Enable FSMs
            dut_local_en = 1;
            ptn_local_en = 1;
            dut_partner_en = 1;
            ptn_partner_en = 1;

            fork
                begin
                    wait (u_dut.local_valtraincenter_done || u_dut.local_trainerror_req);
                    #(LCLK_PERIOD * 10);
                end
                begin
                    #(TIMEOUT_CYCLES * LCLK_PERIOD);
                    $display("# ERROR: Simulation timeout guard fired in randomized test %0d!", i);
                    $stop;
                end
            join_any
            disable fork;

            // Verification
            if (u_dut.local_trainerror_req) begin
                $display("# ERROR: Unexpected TRAINERROR in randomized test %0d!", i);
                $stop;
            end

            begin
                automatic logic [PI_W-1:0] expected_best;
                if (holes_rnd) begin
                    automatic logic [PI_W-1:0] hole_pos = start_rnd + (end_rnd - start_rnd)/4;
                    expected_best = (hole_pos + 1 + end_rnd) / 2;
                end else begin
                    expected_best = (start_rnd + end_rnd) / 2;
                end
                if (u_dut.phy_tx_val_pi_phase_ctrl !== expected_best) begin
                    $display("# ERROR: Randomized test %0d midpoint mismatch! Obtained=%0d, Expected=%0d", i, u_dut.phy_tx_val_pi_phase_ctrl, expected_best);
                    $stop;
                end
            end

            // Disable FSMs
            dut_local_en = 0;
            ptn_local_en = 0;
            dut_partner_en = 0;
            ptn_partner_en = 0;
            #(LCLK_PERIOD * 30);
        end

        in_randomized_scenarios = 1'b0;
        pass_test("100 Randomized Scenarios");

        $display("\n=========================================================");
        $display(" VALTRAINCENTER WRAPPER TB COMPLETE");
        $display(" PASSED: %0d | FAILED: %0d | TOTAL: %0d", success_count, fail_count,
            success_count+fail_count);
        $display("=========================================================\n");
        $stop;
    end

endmodule





