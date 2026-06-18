`timescale 1ps/1ps
module wrapper_DATAVREF_tb;

    import UCIe_pkg::*;

    // =========================================================================
    // 1. Parameters for Fast and Configurable Testbench Running
    // =========================================================================
    parameter LCLK_PERIOD          = 1*1000 ; // lclk period = 1ns (1GHz)
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait for settling
    parameter MIN_DATA_VREF_CODE   = 7'D1   ;
    parameter MAX_DATA_VREF_CODE   = 7'D16  ; // Spec-compliant range: 1..16
    parameter SB_DELAY             = 20     ; // Delay in lclk cycles.
    parameter MB_DELAY             = 10     ; // Speed knob: reduce iteration time

    // CYCLES_PER_CODE: cycles per swept code point (per-lane D2C).
    //   = MB iter cycles: MB_DELAY iters x ~MB_DELAY burst cycles
    //   + 6 D2C SB handshake round-trips x 2 x SB_DELAY
    //   + FSM overhead
    localparam integer CYCLES_PER_CODE = MB_DELAY * MB_DELAY + 12 * SB_DELAY + 30;
    localparam integer SWEEP_CYCLES    = (MAX_DATA_VREF_CODE - MIN_DATA_VREF_CODE + 1) * CYCLES_PER_CODE;
    parameter TIMEOUT_CYCLES           = 8 * (SWEEP_CYCLES + SB_DELAY * 20);
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
    ltsm_tb_if #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE)
    ) dut_if (lclk, rst_n);

    ltsm_tb_if #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE)
    ) ptn_if (lclk, rst_n);

    localparam int DATA_W = $clog2(MAX_DATA_VREF_CODE + 1);

    wire [DATA_W-1:0] dut_swept_code_sliced;
    wire [DATA_W-1:0] dut_best_code_sliced [0:15];
    assign dut_swept_code_sliced = dut_if.swept_code[DATA_W-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign dut_best_code_sliced[i] = dut_if.best_code[i][DATA_W-1:0];
    end

    wire [DATA_W-1:0] ptn_swept_code_sliced;
    wire [DATA_W-1:0] ptn_best_code_sliced [0:15];
    assign ptn_swept_code_sliced = ptn_if.swept_code[DATA_W-1:0];
    for (genvar i = 0; i < 16; i++) begin
        assign ptn_best_code_sliced[i] = ptn_if.best_code[i][DATA_W-1:0];
    end

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DATA_VREF_CODE  (MIN_DATA_VREF_CODE  ),
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE  ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DATA_VREF_CODE  (MIN_DATA_VREF_CODE  ),
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE  ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) ptn_attach (
        .intf(ptn_if)
    );

    // =========================================================================
    // Control / Simulation Configuration Registers
    // =========================================================================
    logic soft_rst_n = 1;

    // Eye Simulation parameters (Per-lane)
    integer      dut_eye_start [0:15];
    integer      dut_eye_end   [0:15];

    integer      ptn_eye_start [0:15];
    integer      ptn_eye_end   [0:15];

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
    // Dynamic Vref Sweeping Eye Simulation (Per-lane)
    // =========================================================================
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            dut_if.tb_force_perlane_pass <= 16'hFFFF;
        end else begin
            if (dut_if.sweep_en) begin
                automatic logic [6:0] code = dut_if.swept_code;
                for (int l = 0; l < 16; l = l + 1) begin
                    if (code >= dut_eye_start[l] && code <= dut_eye_end[l]) begin
                        if (assume_holes_after_quarter_eye_start && (code == dut_eye_start[l] + (dut_eye_end[l] - dut_eye_start[l])/4)) begin
                            dut_if.tb_force_perlane_pass[l] <= 1'b0; // Mock fail (hole)
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
    end

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            ptn_if.tb_force_perlane_pass <= 16'hFFFF;
        end else begin
            if (ptn_if.sweep_en) begin
                automatic logic [6:0] code = ptn_if.swept_code;
                for (int l = 0; l < 16; l = l + 1) begin
                    if (code >= ptn_eye_start[l] && code <= ptn_eye_end[l]) begin
                        if (assume_holes_after_quarter_eye_start && (code == ptn_eye_start[l] + (ptn_eye_end[l] - ptn_eye_start[l])/4)) begin
                            ptn_if.tb_force_perlane_pass[l] <= 1'b0; // Mock fail (hole)
                        end else begin
                            ptn_if.tb_force_perlane_pass[l] <= 1'b1;
                        end
                    end else begin
                        ptn_if.tb_force_perlane_pass[l] <= 1'b0;
                    end
                end
            end else begin
                ptn_if.tb_force_perlane_pass <= 16'hFFFF;
            end
        end
    end

    // =========================================================================
    // Die A Instantiation (DUT)
    // =========================================================================
    logic        dut_local_datavref_en = 0;
    logic        dut_local_update_lane_mask;
    logic        dut_partner_datavref_en = 0;

    logic        dut_datavref_done;
    logic        dut_trainerror_req;
    assign       dut_trainerror_req = 1'b0;

    wrapper_DATAVREF #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE)
    ) u_dut (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (soft_rst_n),
        .datavref_en                    (dut_local_datavref_en),

        .datavref_done                  (dut_datavref_done),
        .phy_rx_datavref_ctrl           (dut_if.phy_rx_datavref_ctrl),
        .partner_sweep_en               (dut_if.partner_sweep_en),

        .local_sweep_en                 (dut_if.sweep_en),
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
        .rx_sb_msg                      (dut_if.rx_sb_msg)
    );

    // =========================================================================
    // Die B Instantiation (PARTNER)
    // =========================================================================
    logic        ptn_local_datavref_en = 0;
    logic        ptn_partner_datavref_en = 0;

    logic        ptn_datavref_done;

    wrapper_DATAVREF #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE)
    ) u_ptn (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (soft_rst_n),
        .datavref_en                    (ptn_local_datavref_en),

        .datavref_done                  (ptn_datavref_done),
        .phy_rx_datavref_ctrl           (ptn_if.phy_rx_datavref_ctrl),
        .partner_sweep_en               (ptn_if.partner_sweep_en),

        .local_sweep_en                 (ptn_if.sweep_en),
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
        .rx_sb_msg                      (ptn_if.rx_sb_msg)
    );

    // =========================================================================
    // State Monitors
    // =========================================================================
    typedef enum reg [3:0] {
        DATAVREF_LCL_IDLE           = 4'd0,
        DATAVREF_LCL_SEND_START_REQ = 4'd1,
        DATAVREF_LCL_WAIT_START_RESP= 4'd2,
        DATAVREF_LCL_SWEEP          = 4'd3,
        DATAVREF_LCL_APPLY_BEST     = 4'd4,
        DATAVREF_LCL_SEND_END_REQ   = 4'd5,
        DATAVREF_LCL_WAIT_END_RESP  = 4'd6,
        DATAVREF_LCL_TO_SPEEDIDLE   = 4'd7,
        DATAVREF_LCL_TO_TRAINERROR  = 4'd8
    } local_state_t;

    typedef enum reg [3:0] {
        DATAVREF_PTR_IDLE            = 4'd0,
        DATAVREF_PTR_WAIT_START_REQ  = 4'd1,
        DATAVREF_PTR_SEND_START_RESP = 4'd2,
        DATAVREF_PTR_WAIT_END_REQ    = 4'd3,
        DATAVREF_PTR_SEND_END_RESP   = 4'd4,
        DATAVREF_PTR_TO_SPEEDIDLE    = 4'd5,
        DATAVREF_PTR_TO_TRAINERROR   = 4'd6
    } partner_state_t;

    local_state_t dut_local_state, prev_dut_local_state;
    partner_state_t dut_partner_state, prev_dut_partner_state;
    logic           in_randomized_scenarios = 1'b0;

    assign dut_local_state   = local_state_t'(u_dut.u_DATAVREF_local.current_state);
    assign dut_partner_state = partner_state_t'(u_dut.u_DATAVREF_partner.current_state);

    function string get_short_msg_name(msg_no_e msg);
        case (msg)
            MBTRAIN_DATAVREF_start_req  : return "START_REQ";
            MBTRAIN_DATAVREF_start_resp : return "START_RESP";
            MBTRAIN_DATAVREF_end_req    : return "END_REQ";
            MBTRAIN_DATAVREF_end_resp   : return "END_RESP";
            TRAINERROR_Entry_req        : return "TRAINERROR_REQ";
            default                     : return "OTHER_SB_MSG";
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
        dut_if.state_n_0            = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        dut_if.tb_suppress_rx_sb     = 0;
        dut_if.tb_verbose            = 0;
        dut_if.tb_wait_timeout       = 0;
        dut_if.tb_aggr_err           = 0;
        dut_if.mb_rx_data_lane_mask  = 3'b011; // 16 lanes active
        dut_if.mb_tx_data_lane_mask  = 3'b011;
        dut_if.cfg_max_err_thresh_perlane = 10;
        dut_if.cfg_max_err_thresh_aggr    = 20;

        ptn_if.state_n_0            = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        ptn_if.tb_suppress_rx_sb     = 0;
        ptn_if.tb_verbose            = 0;
        ptn_if.tb_wait_timeout       = 0;
        ptn_if.tb_aggr_err           = 0;
        ptn_if.mb_rx_data_lane_mask  = 3'b011;
        ptn_if.mb_tx_data_lane_mask  = 3'b011;
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
            input integer d_start [0:15],
            input integer d_end   [0:15],
            input integer p_start [0:15],
            input integer p_end   [0:15],
            input logic holes_en,
            input logic expect_speedidle_dut,
            input logic expect_te_dut,
            input logic suppress_sb,
            input logic inject_trainerror
        );
        $display("\n\n# =========================================================");
        $display("# Starting Scenario: %s", name);
        $display("# =========================================================");

        assert_reset();

        for (int l = 0; l < 16; l = l + 1) begin
            dut_eye_start[l] = d_start[l];
            dut_eye_end[l]   = d_end[l];
            ptn_eye_start[l] = p_start[l];
            ptn_eye_end[l]   = p_end[l];
        end
        assume_holes_after_quarter_eye_start = holes_en;

        if (suppress_sb) begin
            ptn_if.tb_suppress_rx_sb = 1;
            fork
                begin
                    repeat(200) @(posedge lclk);
                    @(posedge lclk);
                end
            join_none
        end

        // Enable FSMs
        dut_local_datavref_en = 1;
        ptn_local_datavref_en = 1;
        dut_partner_datavref_en = 1;
        ptn_partner_datavref_en = 1;

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
                wait (dut_datavref_done || dut_trainerror_req);
                #(LCLK_PERIOD * 10);
            end
            begin
                #(TIMEOUT_CYCLES * LCLK_PERIOD);
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        // Verify FSM exits and calibrated midpoint codes
        if (expect_speedidle_dut) begin
            if (!dut_datavref_done || dut_trainerror_req) begin
                $display("# ERROR: Expected successful SPEEDIDLE exit, but got datavref_done=%b, trainerror=%b", dut_datavref_done, dut_trainerror_req);
                fail_count++; $stop;
            end

            // Check calibrated Vref code for each lane
            for (int l = 0; l < 16; l = l + 1) begin
                automatic logic [6:0] expected_best;
                if (holes_en) begin
                    automatic logic [6:0] hole_pos = d_start[l] + (d_end[l] - d_start[l])/4;
                    expected_best = (hole_pos + 1 + d_end[l]) / 2;
                end else begin
                    expected_best = (d_start[l] + d_end[l]) / 2;
                end
                if (u_dut.phy_rx_datavref_ctrl[l] !== expected_best) begin
                    $display("# ERROR: Lane %0d calibrated midpoint mismatch! Obtained=%0d, Expected=%0d", l, u_dut.phy_rx_datavref_ctrl[l], expected_best);
                    fail_count++; $stop;
                end
            end
        end

        if (expect_te_dut && !dut_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR on Die A, but got trainerror_req=%b", dut_trainerror_req);
            fail_count++; $stop;
        end

        // Clean up FSM enables
        dut_local_datavref_en = 0;
        ptn_local_datavref_en = 0;
        dut_partner_datavref_en = 0;
        ptn_partner_datavref_en = 0;
        if (suppress_sb) ptn_if.tb_suppress_rx_sb = 0;

        #(LCLK_PERIOD * 50);
        pass_test(name);
    endtask

    // =========================================================================
    // Main Test Program
    // =========================================================================
    initial begin
        automatic integer standard_start [0:15];
        automatic integer standard_end   [0:15];
        for (int l = 0; l < 16; l = l + 1) begin
            standard_start[l] = 3;
            standard_end[l]   = 13;
        end

        dut_if.state_n_0 = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        ptn_if.state_n_0 = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;

        $display("# =========================================================");
        $display("# Running wrapper_DATAVREF_tb                              ");
        $display("# =========================================================");

        // Scenario 1: Happy symmetric sweep
        run_scenario(
            .name("Scenario 1: Symmetrical Clean Sweep"),
            .d_start(standard_start), .d_end(standard_end),
            .p_start(standard_start), .p_end(standard_end),
            .holes_en(0),
            .expect_speedidle_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 2: Asymmetric sweep (DUT narrower eye)
        begin
            automatic integer d_s [0:15];
            automatic integer d_e [0:15];
            for (int l = 0; l < 16; l = l + 1) begin
                d_s[l] = 5;
                d_e[l] = 11;
            end
            run_scenario(
                .name("Scenario 2: Asymmetric Sweep (DUT narrower eye)"),
                .d_start(d_s), .d_end(d_e),
                .p_start(standard_start), .p_end(standard_end),
                .holes_en(0),
                .expect_speedidle_dut(1), .expect_te_dut(0),
                .suppress_sb(0), .inject_trainerror(0)
            );
        end

        // Scenario 3: Asymmetric sweep (DUT wider eye)
        begin
            automatic integer p_s [0:15];
            automatic integer p_e [0:15];
            for (int l = 0; l < 16; l = l + 1) begin
                p_s[l] = 5;
                p_e[l] = 11;
            end
            run_scenario(
                .name("Scenario 3: Asymmetric Sweep (DUT wider eye)"),
                .d_start(standard_start), .d_end(standard_end),
                .p_start(p_s), .p_end(p_e),
                .holes_en(0),
                .expect_speedidle_dut(1), .expect_te_dut(0),
                .suppress_sb(0), .inject_trainerror(0)
            );
        end

        // Scenario 4: Sweep with Hole in passing window
        run_scenario(
            .name("Scenario 4: Sweep with Eye Hole"),
            .d_start(standard_start), .d_end(standard_end),
            .p_start(standard_start), .p_end(standard_end),
            .holes_en(1),
            .expect_speedidle_dut(1), .expect_te_dut(0),
            .suppress_sb(0), .inject_trainerror(0)
        );

        // Scenario 5: Multi-run without reset
        $display("\n\n# =========================================================");
        $display("# Starting Scenario 5: Multi-run without Reset");
        $display("# =========================================================");
        for (int l = 0; l < 16; l = l + 1) begin
            dut_eye_start[l] = 3; dut_eye_end[l] = 13; ptn_eye_start[l] = 3; ptn_eye_end[l] = 13;
        end
        assume_holes_after_quarter_eye_start = 0;
        dut_local_datavref_en = 1; ptn_local_datavref_en = 1;
        dut_partner_datavref_en = 1; ptn_partner_datavref_en = 1;
        wait (dut_datavref_done);       // Then wait for sweep+handshake to complete
        #1000;
        dut_local_datavref_en = 0; ptn_local_datavref_en = 0;
        dut_partner_datavref_en = 0; ptn_partner_datavref_en = 0;
        #10000;

        // Run 2
        for (int l = 0; l < 16; l = l + 1) begin
            dut_eye_start[l] = 6; dut_eye_end[l] = 12; ptn_eye_start[l] = 6; ptn_eye_end[l] = 12;
        end
        dut_local_datavref_en = 1; ptn_local_datavref_en = 1;
        dut_partner_datavref_en = 1; ptn_partner_datavref_en = 1;
        wait (dut_datavref_done);       // Then wait for sweep+handshake to complete
        #1000;
        for (int l = 0; l < 16; l = l + 1) begin
            if (u_dut.phy_rx_datavref_ctrl[l] !== 7'd9) begin
                $display("# ERROR: Lane %0d Multi-run 2 Vref value mismatch! Got %0d, expected 9", l, u_dut.phy_rx_datavref_ctrl[l]);
                $stop;
            end
        end
        dut_local_datavref_en = 0; ptn_local_datavref_en = 0;
        dut_partner_datavref_en = 0; ptn_partner_datavref_en = 0;
        #10000;
        pass_test("Scenario 5: Multi-run without Reset");

        // Scenario 6: 8ms watchdog timeout -> TRAINERROR
        /*
         run_scenario(
         .name("Scenario 6: Watchdog Timeout -> TRAINERROR"),
         .d_start(standard_start), .d_end(standard_end),
         .p_start(standard_start), .p_end(standard_end),
         .holes_en(0),
         .expect_speedidle_dut(0), .expect_te_dut(1),
         .suppress_sb(1), .inject_trainerror(0)
         );


         */        // Scenario 7: Injected TRAINERROR from partner
        // (Commented out because DATAVREF removes global trainerror check and does not support trainerror)
        /*
        run_scenario(
            .name("Scenario 7: Partner Injects TRAINERROR"),
            .d_start(standard_start), .d_end(standard_end),
            .p_start(standard_start), .p_end(standard_end),
            .holes_en(0),
            .expect_speedidle_dut(0), .expect_te_dut(1),
            .suppress_sb(0), .inject_trainerror(1)
        );
        */

        // =========================================================================
        // 8. Randomized Scenarios Block with Self-Checking
        // =========================================================================
        in_randomized_scenarios = 1'b1;
        $display("\n\n# =========================================================");
        $display("# Starting Randomized Scenarios (100 Iterations without reset)");
        $display("# =========================================================");

        assert_reset();

        for (int i = 1; i <= 100; i = i + 1) begin
            automatic integer r_s [0:15];
            automatic integer r_e [0:15];
            automatic bit holes_rnd = $urandom_range(0, 1);

            for (int l = 0; l < 16; l = l + 1) begin
                r_s[l] = $urandom_range(MIN_DATA_VREF_CODE, MAX_DATA_VREF_CODE - 4);
                r_e[l] = $urandom_range(r_s[l] + 3, MAX_DATA_VREF_CODE);
                dut_eye_start[l] = r_s[l];
                dut_eye_end[l]   = r_e[l];
                ptn_eye_start[l] = r_s[l];
                ptn_eye_end[l]   = r_e[l];
            end
            assume_holes_after_quarter_eye_start = holes_rnd;

            if (ENABLE_RAND_LOG) begin
                $display("Rand scenario %0d: holes=%b", i, holes_rnd);
            end

            // Enable FSMs
            dut_local_datavref_en = 1;
            ptn_local_datavref_en = 1;
            dut_partner_datavref_en = 1;
            ptn_partner_datavref_en = 1;

            fork
                begin
                    wait (dut_datavref_done || dut_trainerror_req);
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
            if (dut_trainerror_req) begin
                $display("# ERROR: Unexpected TRAINERROR in randomized test %0d!", i);
                $stop;
            end

            for (int l = 0; l < 16; l = l + 1) begin
                automatic logic [6:0] expected_best;
                if (holes_rnd) begin
                    automatic logic [6:0] hole_pos = r_s[l] + (r_e[l] - r_s[l])/4;
                    expected_best = (hole_pos + 1 + r_e[l]) / 2;
                end else begin
                    expected_best = (r_s[l] + r_e[l]) / 2;
                end
                if (u_dut.phy_rx_datavref_ctrl[l] !== expected_best) begin
                    $display("# ERROR: Randomized test %0d lane %0d midpoint mismatch! Obtained=%0d, Expected=%0d", i, l, u_dut.phy_rx_datavref_ctrl[l], expected_best);
                    $stop;
                end
            end

            // Disable FSMs
            dut_local_datavref_en = 0;
            ptn_local_datavref_en = 0;
            dut_partner_datavref_en = 0;
            ptn_partner_datavref_en = 0;
            #(LCLK_PERIOD * 30);
        end

        in_randomized_scenarios = 1'b0;
        pass_test("100 Randomized Scenarios");

        $display("\n=========================================================");
        $display(" DATAVREF WRAPPER TB COMPLETE");
        $display(" PASSED: %0d | FAILED: %0d | TOTAL: %0d", success_count, fail_count,
            success_count+fail_count);
        $display("=========================================================\n");
        if (fail_count == 0) begin
            $display("MBTRAIN_TB_RESULT: SUCCESS");
        end else begin
            $display("MBTRAIN_TB_RESULT: FAILURE");
        end
        $stop;
    end

endmodule





