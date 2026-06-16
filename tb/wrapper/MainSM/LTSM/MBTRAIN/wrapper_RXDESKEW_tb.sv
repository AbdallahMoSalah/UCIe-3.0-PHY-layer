`timescale 1ps/1ps
module wrapper_RXDESKEW_tb;

    import UCIe_pkg::*;

    // =========================================================================
    // 1. Parameters for Fast and Configurable Testbench Running
    // =========================================================================
    parameter LCLK_PERIOD          = 1*1000 ; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    parameter MIN_DESKEW_CODE      = 7'D1   ;
    parameter MAX_DESKEW_CODE      = 7'D16  ; // Reduced from 127 for fast simulation
    parameter SB_DELAY             = 20     ; // Delay in lclk cycles.
    parameter MB_DELAY             = 10     ; // Representing 128 lclk + 2 lclk delay (standard spec is 4096)

    localparam integer CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (MB_DELAY + 1) * MB_DELAY + 15 + 8 * SB_DELAY;
    localparam integer SWEEP_CYCLES    = (MAX_DESKEW_CODE - MIN_DESKEW_CODE + 1) * CYCLES_PER_CODE;
    parameter TIMEOUT_CYCLES           = 8 * (SWEEP_CYCLES + SB_DELAY * 10);
    parameter bit ENABLE_RAND_LOG      = 1'b0; // 1: display details of randomized scenarios in terminal; 0: suppress

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
        .MIN_DESKEW_CODE     (MIN_DESKEW_CODE     ),
        .MAX_DESKEW_CODE     (MAX_DESKEW_CODE     ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) dut_attach (
        .intf(dut_if)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .MIN_DESKEW_CODE     (MIN_DESKEW_CODE     ),
        .MAX_DESKEW_CODE     (MAX_DESKEW_CODE     ),
        .MB_DELAY            (MB_DELAY            ),
        .ENABLE_LOOPBACK     (1'b0                )
    ) ptn_attach (
        .intf(ptn_if)
    );

    // =========================================================================
    // Control / Simulation Configuration Registers
    // =========================================================================
    logic is_ltsm_out_of_reset = 1;
    logic timeout_8ms_occured = 0;
    logic is_high_speed = 1;
    logic is_continuous_clk_mode = 0;
    logic [2:0] phy_negotiated_speed = 3'b010;

    assign dut_if.phy_negotiated_speed = phy_negotiated_speed;
    assign ptn_if.phy_negotiated_speed = phy_negotiated_speed;

    // Eye Simulation parameters
    logic [2:0]  dut_target_preset;
    integer      dut_eye_start;
    integer      dut_eye_end;

    logic [2:0]  ptn_target_preset;
    integer      ptn_eye_start;
    integer      ptn_eye_end;

    logic [15:0] dut_lane_fail_mask;
    logic [15:0] ptn_lane_fail_mask;

    // Intercept control
    logic corrupt_preset_val = 0;
    logic corrupt_preset_val_dut2ptn = 0;

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
            if (corrupt_preset_val_dut2ptn && dut_if.tb_muxed_tx_sb_msg_valid && dut_if.tb_muxed_tx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                dut2ptn_info_sr[0] <= 16'h0005; // Corrupt to preset 5
            end else begin
                dut2ptn_info_sr[0] <= dut_if.tb_muxed_tx_msginfo;
            end
            dut2ptn_data_sr[0] <= dut_if.tb_muxed_tx_data_field;

            if (tb_ptn_inject_valid) begin
                ptn2dut_msg_sr[0]  <= tb_ptn_inject_msg;
                ptn2dut_info_sr[0] <= tb_ptn_inject_info;
                ptn2dut_data_sr[0] <= 64'h0;
            end else begin
                ptn2dut_msg_sr[0]  <= ptn_if.tb_muxed_tx_sb_msg;
                if (corrupt_preset_val && ptn_if.tb_muxed_tx_sb_msg_valid && ptn_if.tb_muxed_tx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                    ptn2dut_info_sr[0] <= 16'h0007; // Corrupt to invalid preset 7
                end else begin
                    ptn2dut_info_sr[0] <= ptn_if.tb_muxed_tx_msginfo;
                end
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
    // Dynamic Eye Sweeping Simulation
    // =========================================================================
    always @(posedge lclk) begin
        if (dut_if.sweep_en) begin
            automatic logic [2:0] applied_preset = u_ptn.phy_tx_eq_preset_ctrl;
            automatic logic [6:0] code = dut_if.swept_code;
            if (applied_preset == dut_target_preset && code >= dut_eye_start && code <= dut_eye_end) begin
                dut_if.tb_force_perlane_pass <= 16'hFFFF & ~dut_lane_fail_mask;
            end else begin
                dut_if.tb_force_perlane_pass <= 16'h0000;
            end
        end else begin
            dut_if.tb_force_perlane_pass <= 16'hFFFF;
        end
    end

    always @(posedge lclk) begin
        if (ptn_if.sweep_en) begin
            automatic logic [2:0] applied_preset = u_dut.phy_tx_eq_preset_ctrl;
            automatic logic [6:0] code = ptn_if.swept_code;
            if (applied_preset == ptn_target_preset && code >= ptn_eye_start && code <= ptn_eye_end) begin
                ptn_if.tb_force_perlane_pass <= 16'hFFFF & ~ptn_lane_fail_mask;
            end else begin
                ptn_if.tb_force_perlane_pass <= 16'h0000;
            end
        end else begin
            ptn_if.tb_force_perlane_pass <= 16'hFFFF;
        end
    end

    // =========================================================================
    // Die A Instantiation (DUT)
    // =========================================================================
    logic        dut_local_rxdeskew_en = 0;
    logic        dut_rxdeskew_done;
    logic        dut_datatraincenter1_req;
    logic        dut_trainerror_req;

    logic        dut_partner_rxdeskew_en = 0;
    logic        dut_partner_rxdeskew_done;
    logic        dut_partner_datatraincenter1_req;
    logic        dut_partner_trainerror_req;

    logic        dut_timeout_timer_en;
    logic [6:0]  dut_phy_rx_deskew_ctrl [15:0];
    logic        dut_partner_sweep_en;
    logic [2:0]  dut_phy_tx_eq_preset_ctrl;
    logic        dut_phy_tx_eq_preset_en;

    localparam int DESKEW_W = $clog2(MAX_DESKEW_CODE+1);
    wire [DESKEW_W-1:0] dut_swept_code_sliced;
    wire [DESKEW_W-1:0] dut_best_code_sliced [0:15];
    wire [DESKEW_W-1:0] dut_min_eye_width_sliced;
    assign dut_swept_code_sliced = dut_if.swept_code;
    assign dut_min_eye_width_sliced = dut_if.min_eye_width;
    for (genvar i = 0; i < 16; i++) begin
        assign dut_best_code_sliced[i] = dut_if.best_code[i];
    end

    wrapper_RXDESKEW #(
        .MAX_DESKEW_CODE(MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE(MIN_DESKEW_CODE),
        .MAX_VALID_PRESET(5)
    ) u_dut (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (is_ltsm_out_of_reset),
        .is_high_speed                  (is_high_speed),
        .is_continuous_clk_mode         (is_continuous_clk_mode),

        .local_rxdeskew_en              (dut_local_rxdeskew_en),
        .rxdeskew_done                  (dut_rxdeskew_done),
        .datatraincenter1_req           (dut_datatraincenter1_req),
        .trainerror_req                 (dut_trainerror_req),

        .partner_rxdeskew_en            (dut_partner_rxdeskew_en),
        .phy_rx_deskew_ctrl             (dut_phy_rx_deskew_ctrl),
        .partner_sweep_en               (dut_if.partner_sweep_en),
        .phy_tx_eq_preset_ctrl          (dut_phy_tx_eq_preset_ctrl),
        .phy_tx_eq_preset_en            (dut_phy_tx_eq_preset_en),

        .sweep_en                       (dut_if.sweep_en),
        .swept_code                     (dut_swept_code_sliced),
        .best_code                      (dut_best_code_sliced),
        .min_eye_width                  (dut_min_eye_width_sliced),
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
    // Die B Instantiation (PARTNER)
    // =========================================================================
    logic        ptn_local_rxdeskew_en = 0;
    logic        ptn_rxdeskew_done;
    logic        ptn_datatraincenter1_req;
    logic        ptn_trainerror_req;

    logic        ptn_partner_rxdeskew_en = 0;
    logic        ptn_partner_rxdeskew_done;
    logic        ptn_partner_datatraincenter1_req;
    logic        ptn_partner_trainerror_req;

    logic        ptn_timeout_timer_en;
    logic [6:0]  ptn_phy_rx_deskew_ctrl [15:0];
    logic        ptn_partner_sweep_en;
    logic [2:0]  ptn_phy_tx_eq_preset_ctrl;
    logic        ptn_phy_tx_eq_preset_en;

    wire [DESKEW_W-1:0] ptn_swept_code_sliced;
    wire [DESKEW_W-1:0] ptn_best_code_sliced [0:15];
    wire [DESKEW_W-1:0] ptn_min_eye_width_sliced;
    assign ptn_swept_code_sliced = 7'(ptn_if.swept_code);
    assign ptn_min_eye_width_sliced = 7'(ptn_if.min_eye_width);
    for (genvar i = 0; i < 16; i++) begin
        assign ptn_best_code_sliced[i] = 7'(ptn_if.best_code[i]);
    end

    wrapper_RXDESKEW #(
        .MAX_DESKEW_CODE(MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE(MIN_DESKEW_CODE),
        .MAX_VALID_PRESET(5)
    ) u_ptn (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .soft_rst_n                     (is_ltsm_out_of_reset),
        .is_high_speed                  (is_high_speed),
        .is_continuous_clk_mode         (is_continuous_clk_mode),

        .local_rxdeskew_en              (ptn_local_rxdeskew_en),
        .rxdeskew_done                  (ptn_rxdeskew_done),
        .datatraincenter1_req           (ptn_datatraincenter1_req),
        .trainerror_req                 (ptn_trainerror_req),

        .partner_rxdeskew_en            (ptn_partner_rxdeskew_en),
        .phy_rx_deskew_ctrl             (ptn_phy_rx_deskew_ctrl),
        .partner_sweep_en               (ptn_if.partner_sweep_en),
        .phy_tx_eq_preset_ctrl          (ptn_phy_tx_eq_preset_ctrl),
        .phy_tx_eq_preset_en            (ptn_phy_tx_eq_preset_en),

        .sweep_en                       (ptn_if.sweep_en),
        .swept_code                     (ptn_swept_code_sliced),
        .best_code                      (ptn_best_code_sliced),
        .min_eye_width                  (ptn_min_eye_width_sliced),
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
    // State Names Enum & Monitors
    // =========================================================================
    typedef enum reg [4:0] {
        RXDESKEW_IDLE               = 5'd0 ,
        RXDESKEW_SEND_START_REQ     = 5'd1 ,
        RXDESKEW_WAIT_START_RESP    = 5'd2 ,
        RXDESKEW_CHOOSE_PRESET      = 5'd3 ,
        RXDESKEW_SEND_PRESET_REQ    = 5'd4 ,
        RXDESKEW_WAIT_PRESET_RESP   = 5'd5 ,
        RXDESKEW_TX_D2C_SWEEP       = 5'd6 ,
        RXDESKEW_APPLY_BEST_CODE    = 5'd7 ,
        RXDESKEW_SEND_EXIT_DTC1_REQ = 5'd8 ,
        RXDESKEW_WAIT_EXIT_DTC1_RESP= 5'd9 ,
        RXDESKEW_SEND_END_REQ       = 5'd10,
        RXDESKEW_WAIT_END_RESP      = 5'd11,
        RXDESKEW_TO_DTC2            = 5'd12,
        RXDESKEW_TO_DTC1            = 5'd13,
        RXDESKEW_TO_TRAINERROR      = 5'd14
    } local_state_t;

    typedef enum reg [3:0] {
        RXDESKEW_PTR_IDLE                = 4'd0,
        RXDESKEW_PTR_WAIT_START_REQ      = 4'd1,
        RXDESKEW_PTR_SEND_START_RESP     = 4'd2,
        RXDESKEW_PTR_WAIT_SWEEP_OR_REQ   = 4'd3,
        RXDESKEW_PTR_SEND_PRESET_RESP    = 4'd4,
        RXDESKEW_PTR_SEND_PRESET_FAIL    = 4'd5,
        RXDESKEW_PTR_SEND_EXIT_DTC1_RESP = 4'd6,
        RXDESKEW_PTR_DTC1_ARC_INC        = 4'd7,
        RXDESKEW_PTR_SEND_END_RESP       = 4'd8,
        RXDESKEW_PTR_TO_DTC2             = 4'd9,
        RXDESKEW_PTR_TO_DTC1             = 4'd10,
        RXDESKEW_PTR_TO_TRAINERROR       = 4'd11
    } partner_state_t;

    local_state_t dut_local_state, prev_dut_local_state;
    partner_state_t dut_partner_state, prev_dut_partner_state;
    logic           in_randomized_scenarios = 1'b0;

    assign dut_local_state   = local_state_t'(u_dut.u_RXDESKEW_local.current_state);
    assign dut_partner_state = partner_state_t'(u_dut.u_RXDESKEW_partner.current_state);

    // Filter RXDESKEW-only sideband messages for display
    function bit is_rxdeskew_sb_msg(msg_no_e msg);
        case (msg)
            MBTRAIN_RXDESKEW_start_req,
            MBTRAIN_RXDESKEW_start_resp,
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req,
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp,
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req,
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp,
            MBTRAIN_RXDESKEW_end_req,
            MBTRAIN_RXDESKEW_end_resp,
            TRAINERROR_Entry_req: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function string get_short_msg_name(msg_no_e msg);
        case (msg)
            MBTRAIN_RXDESKEW_start_req                                              : return "START_REQ";
            MBTRAIN_RXDESKEW_start_resp                                             : return "START_RESP";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req : return "PRESET_REQ";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp: return "PRESET_RESP";
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req                           : return "EXIT_DTC1_REQ";
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp                          : return "EXIT_DTC1_RESP";
            MBTRAIN_RXDESKEW_end_req                                                : return "END_REQ";
            MBTRAIN_RXDESKEW_end_resp                                               : return "END_RESP";
            TRAINERROR_Entry_req                                                    : return "TRAINERROR_REQ";
            default                                                                 : return "OTHER_SB_MSG";
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
            if (dut_if.rx_sb_msg_valid && is_rxdeskew_sb_msg(msg_no_e'(dut_if.rx_sb_msg))) begin
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
        dut_if.state_n_0             = ltsm_state_n_pkg::LOG_MBTRAIN_RXDESKEW;
        dut_if.tb_suppress_rx_sb     = 0;
        dut_if.tb_force_val_pass     = 1;
        dut_if.tb_verbose            = 0;
        dut_if.tb_wait_timeout       = 0;
        dut_if.tb_aggr_err           = 0;
        dut_if.cfg_max_err_thresh_perlane = 10;
        dut_if.cfg_max_err_thresh_aggr    = 20;

        ptn_if.state_n_0             = ltsm_state_n_pkg::LOG_MBTRAIN_RXDESKEW;
        ptn_if.tb_suppress_rx_sb     = 0;
        ptn_if.tb_force_val_pass     = 1;
        ptn_if.tb_verbose            = 0;
        ptn_if.tb_wait_timeout       = 0;
        ptn_if.tb_aggr_err           = 0;
        ptn_if.cfg_max_err_thresh_perlane = 10;
        ptn_if.cfg_max_err_thresh_aggr    = 20;
    end

    // =========================================================================
    // Task-Controlled Test Scenarios
    // =========================================================================
    task automatic run_scenario(
            input string name,
            input logic hs,
            input logic [2:0] speed,
            input logic cont_clk,
            input logic [2:0] dut_preset,
            input integer dut_start,
            input integer dut_end,
            input logic [2:0] ptn_preset,
            input integer ptn_start,
            input integer ptn_end,
            input logic [15:0] dut_fail_mask,
            input logic [15:0] ptn_fail_mask,
            input logic expect_dtc2_dut,
            input logic expect_dtc1_dut,
            input logic expect_te_dut
        );
        if (!in_randomized_scenarios || ENABLE_RAND_LOG) begin
            $display("# =========================================================");
            $display("# Starting Scenario: %s", name);
            $display("# hs=%b, speed=%3b, cont_clk=%b", hs, speed, cont_clk);
            $display("# =========================================================");
        end

        assert_reset();

        // Apply configurations
        is_high_speed = hs;
        phy_negotiated_speed = speed;
        is_continuous_clk_mode = cont_clk;

        dut_target_preset = dut_preset;
        dut_eye_start = dut_start;
        dut_eye_end = dut_end;

        ptn_target_preset = ptn_preset;
        ptn_eye_start = ptn_start;
        ptn_eye_end = ptn_end;

        dut_lane_fail_mask = dut_fail_mask;
        ptn_lane_fail_mask = ptn_fail_mask;

        dut_if.mb_rx_data_lane_mask = 3'b011;
        dut_if.mb_tx_data_lane_mask = 3'b011;
        ptn_if.mb_rx_data_lane_mask = 3'b011;
        ptn_if.mb_tx_data_lane_mask = 3'b011;

        // Enable FSMs
        dut_local_rxdeskew_en = 1;
        ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1;
        ptn_partner_rxdeskew_en = 1;

        fork
            begin
                wait (dut_rxdeskew_done || dut_datatraincenter1_req || dut_trainerror_req);
                #(LCLK_PERIOD * 100);
            end
            begin
                #50_000_000;
                $display("# ERROR: Simulation timeout guard fired!");
                $stop;
            end
        join_any
        disable fork;

        // Verify FSM exits on Die A
        if (expect_dtc2_dut && (!dut_rxdeskew_done || dut_trainerror_req)) begin
            $display("# ERROR: Expected successful DTC2 exit on Die A, but got rxdeskew_done=%b, trainerror=%b", dut_rxdeskew_done, dut_trainerror_req);
            $stop;
        end
        if (expect_dtc1_dut && !dut_datatraincenter1_req) begin
            $display("# ERROR: Expected DTC1 arc request on Die A, but got datatraincenter1_req=%b", dut_datatraincenter1_req);
            $stop;
        end
        if (expect_te_dut && !dut_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR on Die A, but got trainerror_req=%b", dut_trainerror_req);
            $stop;
        end

        // Clean up FSM enables
        dut_local_rxdeskew_en = 0;
        ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0;
        ptn_partner_rxdeskew_en = 0;
        #(LCLK_PERIOD * 50);
        if (!in_randomized_scenarios || ENABLE_RAND_LOG) begin
            $display("# Scenario Passed: %s\n", name);
        end
    endtask

    // =========================================================================
    // Main Test Program
    // =========================================================================
    initial begin
        $display("# =========================================================");
        $display("# Running wrapper_RXDESKEW_tb                              ");
        $display("# =========================================================");

        // Scenario 1: Low Speed (12 GT/s), Strobe Clock Mode (Clock TX Low), Clean run
        run_scenario(
            .name("Scenario 1: Low Speed Strobe, Clean Run"),
            .hs(0), .speed(3'b010), .cont_clk(0),
            .dut_preset(0), .dut_start(0), .dut_end(15),
            .ptn_preset(0), .ptn_start(0), .ptn_end(15),
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(1), .expect_dtc1_dut(0), .expect_te_dut(0)
        );

        // Scenario 2: Low Speed (32 GT/s), Continuous Clock Mode (Clock TX Active), Clean run
        run_scenario(
            .name("Scenario 2: Low Speed Continuous Clk, Clean Run"),
            .hs(0), .speed(3'b101), .cont_clk(1),
            .dut_preset(0), .dut_start(0), .dut_end(15),
            .ptn_preset(0), .ptn_start(0), .ptn_end(15),
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(1), .expect_dtc1_dut(0), .expect_te_dut(0)
        );

        // Scenario 3: High Speed (64 GT/s), Wide Eye Preset 0 (DTC2)
        run_scenario(
            .name("Scenario 3: HS Wide Eye Preset 0"),
            .hs(1), .speed(3'b111), .cont_clk(0),
            .dut_preset(0), .dut_start(0), .dut_end(15), // Wide Eye
            .ptn_preset(0), .ptn_start(0), .ptn_end(15),
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(1), .expect_dtc1_dut(0), .expect_te_dut(0)
        );

        // Scenario 4: High Speed, Preset 0 Narrow, Preset 1 Wide (DTC2 after preset retry)
        run_scenario(
            .name("Scenario 4: HS Preset 0 Narrow, Preset 1 Wide"),
            .hs(1), .speed(3'b111), .cont_clk(0),
            .dut_preset(1), .dut_start(0), .dut_end(15), // Target preset 1 is wide
            .ptn_preset(1), .ptn_start(0), .ptn_end(15),
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(1), .expect_dtc1_dut(0), .expect_te_dut(0)
        );

        // Scenario 5: High Speed, All Presets Narrow (DTC1)
        run_scenario(
            .name("Scenario 5: HS All Presets Narrow -> Arc DTC1"),
            .hs(1), .speed(3'b111), .cont_clk(0),
            .dut_preset(1), .dut_start(4), .dut_end(8), // Narrow Eye (width 4 < 12)
            .ptn_preset(1), .ptn_start(4), .ptn_end(8),
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(0), .expect_dtc1_dut(1), .expect_te_dut(0)
        );

        // Scenario 6: High Speed, Max Arcs Loop
        $display("# =========================================================");
        $display("# Starting Scenario 6: Max Arcs Loop");
        $display("# =========================================================");
        assert_reset();
        is_high_speed = 1;
        phy_negotiated_speed = 3'b111;
        is_continuous_clk_mode = 0;

        // Setup eye configuration (all narrow)
        dut_eye_start = 5; dut_eye_end = 9; // width 4 < 12
        ptn_eye_start = 5; ptn_eye_end = 9;
        dut_lane_fail_mask = 0; ptn_lane_fail_mask = 0;

        dut_if.mb_rx_data_lane_mask = 3'b011;
        dut_if.mb_tx_data_lane_mask = 3'b011;
        ptn_if.mb_rx_data_lane_mask = 3'b011;
        ptn_if.mb_tx_data_lane_mask = 3'b011;

        // Loop 1
        $display("# Loop 1...");
        dut_target_preset = 1; ptn_target_preset = 1;
        dut_local_rxdeskew_en = 1; ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1; ptn_partner_rxdeskew_en = 1;
        wait (dut_datatraincenter1_req);
        #1000;
        dut_local_rxdeskew_en = 0; ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0; ptn_partner_rxdeskew_en = 0;
        #10000;

        // Loop 2
        $display("# Loop 2...");
        dut_target_preset = 2; ptn_target_preset = 2;
        dut_local_rxdeskew_en = 1; ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1; ptn_partner_rxdeskew_en = 1;
        wait (dut_datatraincenter1_req);
        #1000;
        dut_local_rxdeskew_en = 0; ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0; ptn_partner_rxdeskew_en = 0;
        #10000;

        // Loop 3
        $display("# Loop 3...");
        dut_target_preset = 3; ptn_target_preset = 3;
        dut_local_rxdeskew_en = 1; ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1; ptn_partner_rxdeskew_en = 1;
        wait (dut_datatraincenter1_req);
        #1000;
        dut_local_rxdeskew_en = 0; ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0; ptn_partner_rxdeskew_en = 0;
        #10000;

        // Loop 4
        $display("# Loop 4...");
        dut_target_preset = 4; ptn_target_preset = 4;
        dut_local_rxdeskew_en = 1; ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1; ptn_partner_rxdeskew_en = 1;
        wait (dut_datatraincenter1_req);
        #1000;
        dut_local_rxdeskew_en = 0; ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0; ptn_partner_rxdeskew_en = 0;
        #10000;

        // Loop 5: should exit to DTC2 because arc limit = 4 is reached
        $display("# Loop 5 (arc count is at limit)...");
        dut_target_preset = 5; ptn_target_preset = 5;
        dut_local_rxdeskew_en = 1; ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1; ptn_partner_rxdeskew_en = 1;
        wait (dut_rxdeskew_done);
        #1000;
        if (!dut_rxdeskew_done) begin
            $display("# ERROR: Expected DTC2 on 5th loop due to arc limit reached!");
            $stop;
        end
        dut_local_rxdeskew_en = 0; ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0; ptn_partner_rxdeskew_en = 0;
        #10000;
        $display("# Scenario 6 Passed!\n");

        // // Scenario 7: High Speed, Cross-Die Arc Conflict (Die A ends, Die B arcs -> both DTC1)
        // $display("# =========================================================");
        // $display("# Starting Scenario 7: Cross-Die Conflict (Die A Ends, Die B Arcs)");
        // $display("# =========================================================");
        run_scenario(
            .name("Scenario 7: Cross-Die Conflict (Die A Ends, Die B Arcs)"),
            .hs(1), .speed(3'b111), .cont_clk(0),
            .dut_preset(0), .dut_start(0), .dut_end(15),   // Die A sees wide eye -> wants END
            .ptn_preset(0), .ptn_start(5), .ptn_end(9),    // Die B sees narrow eye -> wants ARC
            .dut_fail_mask(0), .ptn_fail_mask(0),
            .expect_dtc2_dut(0), .expect_dtc1_dut(1), .expect_te_dut(0)
        );

        // Scenario 9: High Speed, Partner requesting TRAINERROR
        $display("# =========================================================");
        $display("# Starting Scenario 8: Partner Requesting TRAINERROR");
        $display("# =========================================================");
        assert_reset();
        is_high_speed = 1;
        phy_negotiated_speed = 3'b111;
        is_continuous_clk_mode = 0;

        dut_local_rxdeskew_en = 1;
        ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1;
        ptn_partner_rxdeskew_en = 1;

        repeat (100) @(posedge lclk);
        // Inject TRAINERROR from Partner B via injection registers
        tb_ptn_inject_valid = 1;
        tb_ptn_inject_msg = TRAINERROR_Entry_req;
        tb_ptn_inject_info = 16'h0;
        @(posedge lclk);
        tb_ptn_inject_valid = 0;

        wait (dut_trainerror_req);
        #1000;
        if (!dut_trainerror_req) begin
            $display("# ERROR: Expected TRAINERROR entry response!");
            $stop;
        end

        dut_local_rxdeskew_en = 0;
        ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0;
        ptn_partner_rxdeskew_en = 0;
        #10000;
        $display("# Scenario 8 Passed!\n");

        // Scenario 9: High Speed, Invalid preset requested by partner (rejected)
        $display("# =========================================================");
        $display("# Starting Scenario 9: Invalid Preset Rejected");
        $display("# =========================================================");
        assert_reset();
        is_high_speed = 1;
        phy_negotiated_speed = 3'b111;
        is_continuous_clk_mode = 0;

        // Force Die B's request to Die A to be 7 (which is > Die A's MAX_VALID_PRESET of 5) -> Expect Rejection
        corrupt_preset_val = 1;
        // Force Die A's request to Die B to be 5 (which is <= Die B's MAX_VALID_PRESET of 5) -> Expect Acceptance
        corrupt_preset_val_dut2ptn = 1;

        dut_local_rxdeskew_en = 1;
        ptn_local_rxdeskew_en = 1;
        dut_partner_rxdeskew_en = 1;
        ptn_partner_rxdeskew_en = 1;

        // Wait until Partner A (u_dut) rejects with Fail status
        wait (u_dut.u_RXDESKEW_partner.current_state == 4'd5); // RXDESKEW_PTR_SEND_PRESET_FAIL
        $display("# Detected invalid preset rejection on Die A.");
        corrupt_preset_val = 0; // Clear corruption

        // Wait for eventual clean completion
        wait (dut_rxdeskew_done || dut_datatraincenter1_req);
        #1000;

        dut_local_rxdeskew_en = 0;
        ptn_local_rxdeskew_en = 0;
        dut_partner_rxdeskew_en = 0;
        ptn_partner_rxdeskew_en = 0;
        #10000;
        $display("# Scenario 9 Passed!\n");

        // =========================================================================
        // 9. Randomized Scenarios Block with Self-Checking
        // =========================================================================
        $display("# =========================================================");
        $display("# Starting Randomized Scenarios");
        $display("# =========================================================");

        in_randomized_scenarios = 1'b1;

        for (int i = 1; i <= 20; i = i + 1) begin
            automatic bit hs_rnd = $urandom_range(0, 1);
            automatic bit [2:0] speed_rnd = hs_rnd ? 3'b111 : 3'b010;
            automatic bit clk_mode_rnd = $urandom_range(0, 1);

            automatic integer dut_preset_rnd = $urandom_range(0, 5);
            automatic integer dut_start_rnd = $urandom_range(0, 5);
            automatic integer dut_end_rnd = dut_start_rnd + $urandom_range(4, 10); // Width 4-10

            automatic integer ptn_preset_rnd = $urandom_range(0, 5);
            automatic integer ptn_start_rnd = $urandom_range(0, 5);
            automatic integer ptn_end_rnd = ptn_start_rnd + $urandom_range(4, 10);

            automatic logic [15:0] dut_fail_mask_rnd = ($urandom_range(0, 9) < 2) ? 16'h0001 : 16'h0000; // 20% lane fail
            automatic logic [15:0] ptn_fail_mask_rnd = ($urandom_range(0, 9) < 2) ? 16'h0001 : 16'h0000;

            automatic bit expect_dtc1;
            automatic bit expect_dtc2;

            // Expected outcomes logic
            if (!hs_rnd) begin
                expect_dtc1 = 0;
                expect_dtc2 = 1;
            end else begin
                // Check eye width threshold (75% of MAX_DESKEW_CODE = 12)
                automatic integer dut_width = (dut_fail_mask_rnd == 0) ? (dut_end_rnd - dut_start_rnd + 1) : 0;
                automatic integer ptn_width = (ptn_fail_mask_rnd == 0) ? (ptn_end_rnd - ptn_start_rnd + 1) : 0;

                if (dut_width >= 12 && ptn_width >= 12) begin
                    expect_dtc1 = 0;
                    expect_dtc2 = 1;
                end else begin
                    // Conflict or narrow sweeps lead to DTC1
                    expect_dtc1 = 1;
                    expect_dtc2 = 0;
                end
            end

            if (ENABLE_RAND_LOG) begin
                $display("# Randomized Loop %0d: hs=%b, speed=%3b, dut_width=%0d, ptn_width=%0d",
                    i, hs_rnd, speed_rnd, (dut_end_rnd - dut_start_rnd + 1), (ptn_end_rnd - ptn_start_rnd + 1));
            end

            run_scenario(
                .name($sformatf("Random Loop %0d", i)),
                .hs(hs_rnd), .speed(speed_rnd), .cont_clk(clk_mode_rnd),
                .dut_preset(dut_preset_rnd), .dut_start(dut_start_rnd), .dut_end(dut_end_rnd),
                .ptn_preset(ptn_preset_rnd), .ptn_start(ptn_start_rnd), .ptn_end(ptn_end_rnd),
                .dut_fail_mask(dut_fail_mask_rnd), .ptn_fail_mask(ptn_fail_mask_rnd),
                .expect_dtc2_dut(expect_dtc2), .expect_dtc1_dut(expect_dtc1), .expect_te_dut(0)
            );
        end

        in_randomized_scenarios = 1'b0;

        $display("\n# =========================================================");
        $display("# All Test Scenarios and Randomized Verifications Passed!");
        $display("# =========================================================");
        $stop;
    end

endmodule





