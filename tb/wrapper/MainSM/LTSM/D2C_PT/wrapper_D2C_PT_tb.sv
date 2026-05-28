// =============================================================================
// wrapper_D2C_PT_tb.sv — Wrapper Level Comprehensive Testbench
// Instantiates BOTH wrapper_D2C_PT_local and wrapper_D2C_PT_partner.
// Tests happy paths for TX and RX Point Tests, followed by 200 randomized runs.
// =============================================================================
`timescale 1ps/1ps

module wrapper_D2C_PT_tb;

    import UCIe_pkg::*;

    parameter LCLK_PERIOD   = 1000;  // 1 ns (1 GHz)
    parameter SB_DELAY_CYCS = 64;    // models async FIFO crossing
    parameter TIMEOUT_LIMIT = 200_000;

    reg lclk=0, rst_n=0;
    always #(LCLK_PERIOD/2) lclk = ~lclk;

    // =========================================================================
    // Shared Config & Controls (Broadcast to wrappers)
    // =========================================================================
    reg        tx_pt_en = 0;                     // Enable TX point test
    reg        rx_pt_en = 0;                     // Enable RX point test
    reg [1:0]  d2c_clk_sampling = 0;             // Sampling phase (00: Center, 01: Left, 10: Right)
    reg [2:0]  d2c_pattern_setup = 3'b001;       // Components (Bit0: Data, Bit1: Valid, Bit2: Clock)
    reg [1:0]  d2c_data_pattern_sel = 0;         // Data pattern (00: LFSR, 01: Per-Lane ID, 10: All Zeros)
    reg        d2c_val_pattern_sel = 0;          // Valid pattern (0: VALTRAIN, 1: Held Low)
    reg        d2c_pattern_mode = 0;             // Mode (0: Continuous, 1: Burst)
    reg [15:0] d2c_burst_count = 100;
    reg [15:0] d2c_idle_count = 0;
    reg [15:0] d2c_iter_count = 1;
    reg [1:0]  d2c_compare_setup = 0;            // Target (00: Per-Lane, 01: Aggregate, 10: Valid, 11: Clock)
    reg [11:0] cfg_max_err_thresh_perlane = 0;
    reg [15:0] cfg_max_err_thresh_aggr = 0;
    wire [2:0] mb_rx_data_lane_mask = d2c_pattern_setup; // Cast from pattern setup

    // =========================================================================
    // Local Wrapper Wires
    // =========================================================================
    wire        req_test_done;
    wire [15:0] req_d2c_perlane_pass;
    wire        req_d2c_aggr_pass;
    wire        req_d2c_val_pass;
    wire        req_tx_sb_msg_valid;
    wire [7:0]  req_tx_sb_msg;
    wire [15:0] req_tx_msginfo;
    wire [63:0] req_tx_data_field;

    wire        req_rx_sb_msg_valid;
    wire [7:0]  req_rx_sb_msg;
    wire [15:0] req_rx_msginfo;
    wire [63:0] req_rx_data_field;

    wire [1:0]  req_mb_tx_clk_lane_sel, req_mb_tx_data_lane_sel, req_mb_tx_val_lane_sel, req_mb_tx_trk_lane_sel;
    wire        req_mb_rx_clk_lane_sel, req_mb_rx_data_lane_sel, req_mb_rx_val_lane_sel, req_mb_rx_trk_lane_sel;
    wire        req_mb_tx_pattern_en;
    wire [2:0]  req_mb_tx_pattern_setup;
    wire [2:0]  req_mb_rx_pattern_setup;
    wire        req_mb_tx_lfsr_en, req_mb_tx_lfsr_rst, req_mb_rx_lfsr_en, req_mb_rx_lfsr_rst, req_mb_rx_compare_en;
    wire [1:0]  req_mb_rx_compare_setup;
    wire [11:0] req_mb_rx_max_err_thresh_perlane;
    wire [15:0] req_mb_rx_max_err_thresh_aggr;
    wire [15:0] req_mb_rx_iter_count, req_mb_rx_idle_count, req_mb_rx_burst_count;
    wire        req_mb_rx_pattern_mode, req_mb_rx_val_pattern_sel;
    wire [1:0]  req_mb_rx_data_pattern_sel;
    wire        req_mb_tx_clk_sampling_en;
    wire [1:0]  req_mb_tx_clk_sampling;
    wire        req_mb_tx_pattern_mode;
    wire [15:0] req_mb_tx_burst_count, req_mb_tx_idle_count, req_mb_tx_iter_count;
    wire [1:0]  req_mb_tx_data_pattern_sel;
    wire        req_mb_tx_val_pattern_sel;

    reg         req_mb_tx_pattern_count_done = 0;
    reg         req_mb_rx_compare_done = 0;
    reg         req_mb_rx_aggr_pass = 1;
    reg [15:0]  req_mb_rx_perlane_pass = 16'hFFFF;
    reg         req_mb_rx_val_pass = 1;

    // =========================================================================
    // Partner Wrapper Wires
    // =========================================================================
    wire        resp_test_done;
    wire [15:0] resp_d2c_perlane_pass;
    wire        resp_d2c_aggr_pass;
    wire        resp_d2c_val_pass;
    wire        resp_tx_sb_msg_valid;
    wire [7:0]  resp_tx_sb_msg;
    wire [15:0] resp_tx_msginfo;
    wire [63:0] resp_tx_data_field;

    wire        resp_rx_sb_msg_valid;
    wire [7:0]  resp_rx_sb_msg;
    wire [15:0] resp_rx_msginfo;
    wire [63:0] resp_rx_data_field;

    wire [1:0]  resp_mb_tx_clk_lane_sel, resp_mb_tx_data_lane_sel, resp_mb_tx_val_lane_sel, resp_mb_tx_trk_lane_sel;
    wire        resp_mb_rx_clk_lane_sel, resp_mb_rx_data_lane_sel, resp_mb_rx_val_lane_sel, resp_mb_rx_trk_lane_sel;
    wire        resp_mb_tx_pattern_en;
    wire [2:0]  resp_mb_tx_pattern_setup;
    wire [2:0]  resp_mb_rx_pattern_setup;
    wire        resp_mb_tx_lfsr_en, resp_mb_tx_lfsr_rst, resp_mb_rx_lfsr_en, resp_mb_rx_lfsr_rst, resp_mb_rx_compare_en;
    wire [1:0]  resp_mb_rx_compare_setup;
    wire [11:0] resp_mb_rx_max_err_thresh_perlane;
    wire [15:0] resp_mb_rx_max_err_thresh_aggr;
    wire [15:0] resp_mb_rx_iter_count, resp_mb_rx_idle_count, resp_mb_rx_burst_count;
    wire        resp_mb_rx_pattern_mode, resp_mb_rx_val_pattern_sel;
    wire [1:0]  resp_mb_rx_data_pattern_sel;
    wire        resp_mb_tx_clk_sampling_en;
    wire [1:0]  resp_mb_tx_clk_sampling;
    wire        resp_mb_tx_pattern_mode;
    wire [15:0] resp_mb_tx_burst_count, resp_mb_tx_idle_count, resp_mb_tx_iter_count;
    wire [1:0]  resp_mb_tx_data_pattern_sel;
    wire        resp_mb_tx_val_pattern_sel;

    reg         resp_mb_tx_pattern_count_done = 0;
    reg         resp_mb_rx_compare_done = 0;
    reg         resp_mb_rx_aggr_pass = 1;
    reg [15:0]  resp_mb_rx_perlane_pass = 16'hFFFF;
    reg         resp_mb_rx_val_pass = 1;

    // =========================================================================
    // Watchdog and Timeout wires
    // =========================================================================
    wire        timeout_8ms_occured;

    // =========================================================================
    // Local Wrapper Instantiation
    // =========================================================================
    wrapper_D2C_PT_local u_req (
        .lclk                           (lclk                           ), // LTSM clock
        .rst_n                          (rst_n                          ), // Active-low reset
        .tx_pt_en                       (tx_pt_en                       ), // TX Point Test trigger
        .rx_pt_en                       (rx_pt_en                       ), // RX Point Test trigger
        .test_d2c_done                  (req_test_done                  ), // Completed status output
        .d2c_clk_sampling               (d2c_clk_sampling               ), // Clock sampling config input
        .d2c_pattern_setup              (d2c_pattern_setup              ), // Pattern setup components input
        .d2c_data_pattern_sel           (d2c_data_pattern_sel           ), // Data pattern selection input
        .d2c_val_pattern_sel            (d2c_val_pattern_sel            ), // Valid pattern selection input
        .d2c_pattern_mode               (d2c_pattern_mode               ), // Continuous vs Burst mode
        .d2c_burst_count                (d2c_burst_count                ), // Burst count duration in UI
        .d2c_idle_count                 (d2c_idle_count                 ), // Idle count duration in UI
        .d2c_iter_count                 (d2c_iter_count                 ), // Iteration count loops to run
        .d2c_compare_setup              (d2c_compare_setup              ), // Comparison setup target mode
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane     ), // Max error threshold per lane
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr        ), // Max aggregate error threshold
        .d2c_perlane_pass               (req_d2c_perlane_pass           ), // Output per-lane pass status
        .d2c_aggr_pass                  (req_d2c_aggr_pass              ), // Output aggregate pass status
        .d2c_val_pass                   (req_d2c_val_pass               ), // Output Valid lane pass status
        .mb_tx_clk_lane_sel             (req_mb_tx_clk_lane_sel         ), // MB Tx Clock Lane mode select
        .mb_tx_data_lane_sel            (req_mb_tx_data_lane_sel        ), // MB Tx Data Lanes mode select
        .mb_tx_val_lane_sel             (req_mb_tx_val_lane_sel         ), // MB Tx Valid Lane mode select
        .mb_tx_trk_lane_sel             (req_mb_tx_trk_lane_sel         ), // MB Tx Tracking Lane mode select
        .mb_rx_clk_lane_sel             (req_mb_rx_clk_lane_sel         ), // MB Rx Clock Lane enable select
        .mb_rx_data_lane_sel            (req_mb_rx_data_lane_sel        ), // MB Rx Data Lanes enable select
        .mb_rx_val_lane_sel             (req_mb_rx_val_lane_sel         ), // MB Rx Valid Lane enable select
        .mb_rx_trk_lane_sel             (req_mb_rx_trk_lane_sel         ), // MB Rx Tracking Lane enable select
        .mb_tx_pattern_en               (req_mb_tx_pattern_en           ), // MB Tx pattern drive enable
        .mb_tx_pattern_setup            (req_mb_tx_pattern_setup        ), // MB Tx pattern config setup
        .mb_tx_lfsr_en                  (req_mb_tx_lfsr_en              ), // MB Tx LFSR scrambler enable
        .mb_tx_lfsr_rst                 (req_mb_tx_lfsr_rst             ), // MB Tx LFSR scrambler reset
        .mb_rx_lfsr_en                  (req_mb_rx_lfsr_en              ), // MB Rx LFSR descrambler enable
        .mb_rx_lfsr_rst                 (req_mb_rx_lfsr_rst             ), // MB Rx LFSR descrambler reset
        .mb_rx_compare_en               (req_mb_rx_compare_en           ), // MB Rx active comparison enable
        .mb_rx_compare_setup            (req_mb_rx_compare_setup        ), // MB Rx comparison setup mode
        .mb_rx_max_err_thresh_perlane   (req_mb_rx_max_err_thresh_perlane), // MB Rx max per-lane threshold
        .mb_rx_max_err_thresh_aggr      (req_mb_rx_max_err_thresh_aggr   ), // MB Rx max aggregate threshold
        .mb_tx_clk_sampling_en          (req_mb_tx_clk_sampling_en      ), // MB Tx clock phase update enable
        .mb_tx_clk_sampling             (req_mb_tx_clk_sampling         ), // MB Tx clock phase sampling setup
        .mb_tx_pattern_mode             (req_mb_tx_pattern_mode         ), // MB Tx pattern generator mode
        .mb_tx_burst_count              (req_mb_tx_burst_count          ), // MB Tx burst active duration count
        .mb_tx_idle_count               (req_mb_tx_idle_count           ), // MB Tx idle low duration count
        .mb_tx_iter_count               (req_mb_tx_iter_count           ), // MB Tx iterations loops count
        .mb_tx_data_pattern_sel         (req_mb_tx_data_pattern_sel     ), // MB Tx data pattern select setup
        .mb_tx_val_pattern_sel          (req_mb_tx_val_pattern_sel      ), // MB Tx Valid pattern select setup
        .mb_tx_pattern_count_done       (req_mb_tx_pattern_count_done   ), // Input transmitter done status
        .mb_rx_compare_done             (req_mb_rx_compare_done         ), // Input comparison complete status
        .mb_rx_pattern_setup            (req_mb_rx_pattern_setup        ),
        .mb_rx_iter_count               (req_mb_rx_iter_count           ),
        .mb_rx_idle_count               (req_mb_rx_idle_count           ),
        .mb_rx_burst_count              (req_mb_rx_burst_count          ),
        .mb_rx_pattern_mode             (req_mb_rx_pattern_mode         ),
        .mb_rx_val_pattern_sel          (req_mb_rx_val_pattern_sel      ),
        .mb_rx_data_pattern_sel         (req_mb_rx_data_pattern_sel     ),
        .mb_rx_aggr_pass                (req_mb_rx_aggr_pass            ), // Input aggregate comparison status
        .mb_rx_perlane_pass             (req_mb_rx_perlane_pass         ), // Input per-lane comparison pass vector
        .mb_rx_val_pass                 (req_mb_rx_val_pass             ), // Input Valid lane comparison status
        .tx_sb_msg_valid                (req_tx_sb_msg_valid            ), // Sideband transmit request strobe
        .tx_sb_msg                      (req_tx_sb_msg                  ), // Transmitted Sideband MsgCode
        .tx_msginfo                     (req_tx_msginfo                 ), // Transmitted Sideband msginfo payload
        .tx_data_field                  (req_tx_data_field              ), // Transmitted Sideband data payload
        .rx_sb_msg_valid                (req_rx_sb_msg_valid            ), // Received Sideband strobe pulse
        .rx_sb_msg                      (req_rx_sb_msg                  ), // Received Sideband MsgCode
        .rx_msginfo                     (req_rx_msginfo                 ), // Received Sideband msginfo payload
        .rx_data_field                  (req_rx_data_field              )  // Received Sideband data payload
    );

    // =========================================================================
    // Partner Wrapper Instantiation
    // =========================================================================
    wrapper_D2C_PT_partner u_resp (
        .lclk                           (lclk                           ), // LTSM clock
        .rst_n                          (rst_n                          ), // Active-low reset
        .tx_pt_en                       (tx_pt_en                       ), // TX Point Test trigger
        .rx_pt_en                       (rx_pt_en                       ), // RX Point Test trigger
        .mb_rx_data_lane_mask           (mb_rx_data_lane_mask           ), // Input negotiated lanes mask
        .test_d2c_done                  (resp_test_done                 ), // Completed status output
        .mb_tx_clk_lane_sel             (resp_mb_tx_clk_lane_sel        ), // MB Tx Clock Lane mode select
        .mb_tx_data_lane_sel            (resp_mb_tx_data_lane_sel       ), // MB Tx Data Lanes mode select
        .mb_tx_val_lane_sel             (resp_mb_tx_val_lane_sel        ), // MB Tx Valid Lane mode select
        .mb_tx_trk_lane_sel             (resp_mb_tx_trk_lane_sel        ), // MB Tx Tracking Lane mode select
        .mb_rx_clk_lane_sel             (resp_mb_rx_clk_lane_sel        ), // MB Rx Clock Lane enable select
        .mb_rx_data_lane_sel            (resp_mb_rx_data_lane_sel       ), // MB Rx Data Lanes enable select
        .mb_rx_val_lane_sel             (resp_mb_rx_val_lane_sel        ), // MB Rx Valid Lane enable select
        .mb_rx_trk_lane_sel             (resp_mb_rx_trk_lane_sel        ), // MB Rx Tracking Lane enable select
        .mb_tx_pattern_en               (resp_mb_tx_pattern_en          ), // MB Tx pattern drive enable
        .mb_tx_pattern_setup            (resp_mb_tx_pattern_setup       ), // MB Tx pattern config setup
        .mb_tx_lfsr_en                  (resp_mb_tx_lfsr_en             ), // MB Tx LFSR scrambler enable
        .mb_tx_lfsr_rst                 (resp_mb_tx_lfsr_rst            ), // MB Tx LFSR scrambler reset
        .mb_rx_lfsr_en                  (resp_mb_rx_lfsr_en             ), // MB Rx LFSR descrambler enable
        .mb_rx_lfsr_rst                 (resp_mb_rx_lfsr_rst            ), // MB Rx LFSR descrambler reset
        .mb_rx_compare_en               (resp_mb_rx_compare_en          ), // MB Rx active comparison enable
        .mb_rx_compare_setup            (resp_mb_rx_compare_setup       ), // MB Rx comparison setup mode
        .mb_rx_max_err_thresh_perlane   (resp_mb_rx_max_err_thresh_perlane), // MB Rx max per-lane threshold
        .mb_rx_max_err_thresh_aggr      (resp_mb_rx_max_err_thresh_aggr   ), // MB Rx max aggregate threshold
        .mb_tx_clk_sampling_en          (resp_mb_tx_clk_sampling_en      ), // MB Tx clock phase update enable
        .mb_tx_clk_sampling             (resp_mb_tx_clk_sampling         ), // MB Tx clock phase sampling setup
        .mb_tx_pattern_mode             (resp_mb_tx_pattern_mode         ), // MB Tx pattern generator mode
        .mb_tx_burst_count              (resp_mb_tx_burst_count          ), // MB Tx burst active duration count
        .mb_tx_idle_count               (resp_mb_tx_idle_count           ), // MB Tx idle low duration count
        .mb_tx_iter_count               (resp_mb_tx_iter_count           ), // MB Tx iterations loops count
        .mb_tx_data_pattern_sel         (resp_mb_tx_data_pattern_sel     ), // MB Tx data pattern select setup
        .mb_tx_val_pattern_sel          (resp_mb_tx_val_pattern_sel      ), // MB Tx Valid pattern select setup
        .mb_tx_pattern_count_done       (resp_mb_tx_pattern_count_done  ), // Input transmitter done status
        .mb_rx_compare_done             (resp_mb_rx_compare_done        ), // Input comparison complete status
        .mb_rx_pattern_setup            (resp_mb_rx_pattern_setup       ),
        .mb_rx_iter_count               (resp_mb_rx_iter_count          ),
        .mb_rx_idle_count               (resp_mb_rx_idle_count          ),
        .mb_rx_burst_count              (resp_mb_rx_burst_count         ),
        .mb_rx_pattern_mode             (resp_mb_rx_pattern_mode        ),
        .mb_rx_val_pattern_sel          (resp_mb_rx_val_pattern_sel     ),
        .mb_rx_data_pattern_sel         (resp_mb_rx_data_pattern_sel    ),
        .mb_rx_aggr_pass                (resp_mb_rx_aggr_pass            ), // Input aggregate comparison status
        .mb_rx_perlane_pass             (resp_mb_rx_perlane_pass         ), // Input per-lane comparison pass vector
        .mb_rx_val_pass                 (resp_mb_rx_val_pass             ), // Input Valid lane comparison status
        .tx_sb_msg_valid                (resp_tx_sb_msg_valid           ), // Sideband transmit request strobe
        .tx_sb_msg                      (resp_tx_sb_msg                 ), // Transmitted Sideband MsgCode
        .tx_msginfo                     (resp_tx_msginfo                ), // Transmitted Sideband msginfo payload
        .tx_data_field                  (resp_tx_data_field             ), // Transmitted Sideband data payload
        .rx_sb_msg_valid                (resp_rx_sb_msg_valid           ), // Received Sideband strobe pulse
        .rx_sb_msg                      (resp_rx_sb_msg                 ), // Received Sideband MsgCode
        .rx_msginfo                     (resp_rx_msginfo                ), // Received Sideband msginfo payload
        .rx_data_field                  (resp_rx_data_field             )  // Received Sideband data payload
    );

    // =========================================================================
    // SB Pipeline Delay crossing queue (Models Async FIFO)
    // =========================================================================
    reg tb_suppress_sb = 0;

    reg [SB_DELAY_CYCS-1:0] req2resp_valid_sr = 0;
    reg [SB_DELAY_CYCS-1:0] resp2req_valid_sr = 0;
    reg [7:0]  req2resp_msg_sr [SB_DELAY_CYCS-1:0];
    reg [7:0]  resp2req_msg_sr [SB_DELAY_CYCS-1:0];
    reg [15:0] req2resp_info_sr[SB_DELAY_CYCS-1:0];
    reg [15:0] resp2req_info_sr[SB_DELAY_CYCS-1:0];
    reg [63:0] req2resp_data_sr[SB_DELAY_CYCS-1:0];
    reg [63:0] resp2req_data_sr[SB_DELAY_CYCS-1:0];

    wire req_rx_sb_msg_valid_w  = resp2req_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  req_rx_sb_msg_w    = resp2req_msg_sr  [SB_DELAY_CYCS-1];
    wire [15:0] req_rx_msginfo_w   = resp2req_info_sr [SB_DELAY_CYCS-1];
    wire [63:0] req_rx_data_field_w= resp2req_data_sr [SB_DELAY_CYCS-1];

    wire resp_rx_sb_msg_valid_w = req2resp_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  resp_rx_sb_msg_w    = req2resp_msg_sr  [SB_DELAY_CYCS-1];
    wire [15:0] resp_rx_msginfo_w   = req2resp_info_sr [SB_DELAY_CYCS-1];
    wire [63:0] resp_rx_data_field_w= req2resp_data_sr [SB_DELAY_CYCS-1];

    // SB loop connections
    assign req_rx_sb_msg_valid = req_rx_sb_msg_valid_w;
    assign req_rx_sb_msg       = req_rx_sb_msg_w;
    assign req_rx_msginfo      = req_rx_msginfo_w;
    assign req_rx_data_field   = req_rx_data_field_w;

    assign resp_rx_sb_msg_valid = resp_rx_sb_msg_valid_w;
    assign resp_rx_sb_msg       = resp_rx_sb_msg_w;
    assign resp_rx_msginfo      = resp_rx_msginfo_w;
    assign resp_rx_data_field   = resp_rx_data_field_w;

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            req2resp_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            resp2req_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            for (pi=0; pi<SB_DELAY_CYCS; pi=pi+1) begin
                req2resp_msg_sr[pi]  <= 0; req2resp_info_sr[pi]  <= 0; req2resp_data_sr[pi]  <= 0;
                resp2req_msg_sr[pi]  <= 0; resp2req_info_sr[pi]  <= 0; resp2req_data_sr[pi]  <= 0;
            end
        end else begin
            req2resp_valid_sr <= {req2resp_valid_sr[SB_DELAY_CYCS-2:0], req_tx_sb_msg_valid};
            resp2req_valid_sr <= {resp2req_valid_sr[SB_DELAY_CYCS-2:0], resp_tx_sb_msg_valid};
            for (pi=1; pi<SB_DELAY_CYCS; pi=pi+1) begin
                req2resp_msg_sr[pi]  <= req2resp_msg_sr[pi-1];
                req2resp_info_sr[pi] <= req2resp_info_sr[pi-1];
                req2resp_data_sr[pi] <= req2resp_data_sr[pi-1];
                resp2req_msg_sr[pi]  <= resp2req_msg_sr[pi-1];
                resp2req_info_sr[pi] <= resp2req_info_sr[pi-1];
                resp2req_data_sr[pi] <= resp2req_data_sr[pi-1];
            end
            req2resp_msg_sr[0]  <= req_tx_sb_msg;
            req2resp_info_sr[0] <= req_tx_msginfo;
            req2resp_data_sr[0] <= req_tx_data_field;
            resp2req_msg_sr[0]  <= resp_tx_sb_msg;
            resp2req_info_sr[0] <= resp_tx_msginfo;
            resp2req_data_sr[0] <= resp_tx_data_field;
        end
    end

    // =========================================================================
    // Unified Mainband Model
    // =========================================================================
    integer tx_mb_burst=0, tx_mb_idle=0, tx_mb_iter=0;
    integer rx_mb_burst=0, rx_mb_idle=0, rx_mb_iter=0;
    reg     tx_done_sent=0, rx_done_sent=0;

    reg [15:0] tb_perlane_pass = 16'hFFFF;
    reg        tb_aggr_pass    = 1'b1;
    reg        tb_val_pass     = 1'b1;
    reg        tb_verbose      = 1;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            req_mb_tx_pattern_count_done  <= 0;
            resp_mb_rx_compare_done       <= 0;
            tx_mb_burst<=0; tx_mb_idle<=0; tx_mb_iter<=0; tx_done_sent<=0;
        end else if (tx_pt_en) begin
            req_mb_tx_pattern_count_done  <= 0;
            resp_mb_rx_compare_done       <= 0;
            if (req_mb_tx_pattern_en && resp_mb_rx_compare_en) begin
                if (tx_mb_iter < d2c_iter_count) begin
                    if (tx_mb_burst < d2c_burst_count) tx_mb_burst <= tx_mb_burst + 1;
                    else if (tx_mb_idle < d2c_idle_count) tx_mb_idle <= tx_mb_idle + 1;
                    else begin
                        tx_mb_iter  <= tx_mb_iter + 1;
                        tx_mb_burst <= 0;
                        tx_mb_idle  <= 0;
                    end
                end else if (!tx_done_sent) begin
                    if (tb_verbose) $display("[%0t] TX PT MB Model complete: perlane_pass=%h, aggr_pass=%b, val_pass=%b", $time, tb_perlane_pass, tb_aggr_pass, tb_val_pass);
                    req_mb_tx_pattern_count_done  <= 1; // 1-cycle pulse to Local
                    resp_mb_rx_compare_done       <= 1; // 1-cycle pulse to Partner
                    resp_mb_rx_perlane_pass       <= tb_perlane_pass;
                    resp_mb_rx_aggr_pass          <= tb_aggr_pass;
                    resp_mb_rx_val_pass           <= tb_val_pass;
                    tx_done_sent                  <= 1;
                end
            end else begin
                tx_mb_burst<=0; tx_mb_idle<=0; tx_mb_iter<=0; tx_done_sent<=0;
            end
        end else begin
            req_mb_tx_pattern_count_done  <= 0;
            resp_mb_rx_compare_done       <= 0;
            tx_mb_burst<=0; tx_mb_idle<=0; tx_mb_iter<=0; tx_done_sent<=0;
        end
    end

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            resp_mb_tx_pattern_count_done <= 0;
            req_mb_rx_compare_done        <= 0;
            rx_mb_burst<=0; rx_mb_idle<=0; rx_mb_iter<=0; rx_done_sent<=0;
        end else if (rx_pt_en) begin
            resp_mb_tx_pattern_count_done <= 0;
            req_mb_rx_compare_done        <= 0;
            if (resp_mb_tx_pattern_en && req_mb_rx_compare_en) begin
                if (rx_mb_iter < d2c_iter_count) begin
                    if (rx_mb_burst < d2c_burst_count) rx_mb_burst <= rx_mb_burst + 1;
                    else if (rx_mb_idle < d2c_idle_count) rx_mb_idle <= rx_mb_idle + 1;
                    else begin
                        rx_mb_iter  <= rx_mb_iter + 1;
                        rx_mb_burst <= 0;
                        rx_mb_idle  <= 0;
                    end
                end else if (!rx_done_sent) begin
                    if (tb_verbose) $display("[%0t] RX PT MB Model complete: perlane_pass=%h, aggr_pass=%b, val_pass=%b", $time, tb_perlane_pass, tb_aggr_pass, tb_val_pass);
                    resp_mb_tx_pattern_count_done <= 1; // 1-cycle pulse to Partner
                    req_mb_rx_compare_done        <= 1; // 1-cycle pulse to Local
                    req_mb_rx_perlane_pass        <= tb_perlane_pass;
                    req_mb_rx_aggr_pass           <= tb_aggr_pass;
                    req_mb_rx_val_pass            <= tb_val_pass;
                    rx_done_sent                  <= 1;
                end
            end else begin
                rx_mb_burst<=0; rx_mb_idle<=0; rx_mb_iter<=0; rx_done_sent<=0;
            end
        end else begin
            resp_mb_tx_pattern_count_done <= 0;
            req_mb_rx_compare_done        <= 0;
            rx_mb_burst<=0; rx_mb_idle<=0; rx_mb_iter<=0; rx_done_sent<=0;
        end
    end

    // =========================================================================
    // Watchdog / Timeout simulator
    // =========================================================================
    integer watchdog_cnt=0;
    reg timeout_8ms_occured_tb=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_cnt <= 0;
            timeout_8ms_occured_tb <= 0;
        end else if (tx_pt_en || rx_pt_en) begin
            watchdog_cnt <= watchdog_cnt + 1;
            if (watchdog_cnt >= TIMEOUT_LIMIT) begin
                timeout_8ms_occured_tb <= 1;
            end
        end else begin
            watchdog_cnt <= 0;
            timeout_8ms_occured_tb <= 0;
        end
    end
    assign timeout_8ms_occured = timeout_8ms_occured_tb;

    // =========================================================================
    // FSM state mappings for debugging and happy paths (no repetitive print!)
    // =========================================================================
    typedef enum reg [3:0] {
        TX_PT_IDLE                 = 4'h0,
        TX_PT_SEND_START_REQ       = 4'h1,
        TX_PT_WAIT_START_RESP      = 4'h2,
        TX_PT_SEND_CLR_ERR_REQ     = 4'h3,
        TX_PT_WAIT_CLR_ERR_RESP    = 4'h4,
        TX_PT_PATTERN_GEN          = 4'h5,
        TX_PT_SEND_RESULTS_REQ     = 4'h6,
        TX_PT_WAIT_RESULTS_RESP    = 4'h7,
        TX_PT_SEND_END_REQ         = 4'h8,
        TX_PT_WAIT_END_RESP        = 4'h9,
        TX_PT_DONE                 = 4'hA
    } tx_req_fsm_t;

    typedef enum reg [3:0] {
        TX_PT_IDLE_P                = 4'h0,
        TX_PT_WAIT_START_REQ_P      = 4'h1,
        TX_PT_SEND_START_RESP_P     = 4'h2,
        TX_PT_WAIT_CLR_ERR_REQ_P    = 4'h3,
        TX_PT_SEND_CLR_ERR_RESP_P   = 4'h4,
        TX_PT_WAIT_RESULTS_REQ_P    = 4'h5,
        TX_PT_SEND_RESULTS_RESP_P   = 4'h6,
        TX_PT_WAIT_END_REQ_P        = 4'h7,
        TX_PT_SEND_END_RESP_P       = 4'h8,
        TX_PT_DONE_P                = 4'h9
    } tx_resp_fsm_t;

    typedef enum reg [3:0] {
        RX_PT_IDLE                 = 4'h0,
        RX_PT_SEND_START_REQ       = 4'h1,
        RX_PT_WAIT_START_RESP      = 4'h2,
        RX_PT_WAIT_CLR_ERR_REQ     = 4'h3,
        RX_PT_SEND_CLR_ERR_RESP    = 4'h4,
        RX_PT_WAIT_COUNT_DONE_REQ  = 4'h5,
        RX_PT_SEND_COUNT_DONE_RESP = 4'h6,
        RX_PT_LOG_RESULT           = 4'h7,
        RX_PT_SEND_END_REQ         = 4'h8,
        RX_PT_WAIT_END_RESP        = 4'h9,
        RX_PT_DONE                 = 4'hA
    } rx_req_fsm_t;

    typedef enum reg [3:0] {
        RX_PT_IDLE_P                 = 4'h0,
        RX_PT_WAIT_START_REQ_P       = 4'h1,
        RX_PT_SEND_START_RESP_P      = 4'h2,
        RX_PT_TX_LFSR_RST_P          = 4'h3,
        RX_PT_SEND_CLR_ERR_REQ_P     = 4'h4,
        RX_PT_WAIT_CLR_ERR_RESP_P    = 4'h5,
        RX_PT_PATTERN_GEN_P          = 4'h6,
        RX_PT_SEND_COUNT_DONE_REQ_P  = 4'h7,
        RX_PT_WAIT_COUNT_DONE_RESP_P = 4'h8,
        RX_PT_WAIT_END_REQ_P         = 4'h9,
        RX_PT_SEND_END_RESP_P        = 4'hA,
        RX_PT_DONE_P                 = 4'hB
    } rx_resp_fsm_t;

    tx_req_fsm_t  tx_req_state;
    tx_resp_fsm_t tx_resp_state;
    rx_req_fsm_t  rx_req_state;
    rx_resp_fsm_t rx_resp_state;

    assign tx_req_state  = tx_req_fsm_t'(u_req.u_TX_D2C_PT_local.current_state);
    assign tx_resp_state = tx_resp_fsm_t'(u_resp.u_TX_D2C_PT_partner.current_state);
    assign rx_req_state  = rx_req_fsm_t'(u_req.u_RX_D2C_PT_local.current_state);
    assign rx_resp_state = rx_resp_fsm_t'(u_resp.u_RX_D2C_PT_partner.current_state);

    always @(tx_req_state)  if (tb_verbose && tx_pt_en) $display("%12t ps [LOCAL   TX] FSM = %s", $time, tx_req_state.name());
    always @(tx_resp_state) if (tb_verbose && tx_pt_en) $display("%12t ps [PARTNER TX] FSM = %s", $time, tx_resp_state.name());
    always @(rx_req_state)  if (tb_verbose && rx_pt_en) $display("%12t ps [LOCAL   RX] FSM = %s", $time, rx_req_state.name());
    always @(rx_resp_state) if (tb_verbose && rx_pt_en) $display("%12t ps [PARTNER RX] FSM = %s", $time, rx_resp_state.name());

    // =========================================================================
    // Test Infrastructure Tasks
    // =========================================================================
    integer success_count = 0;
    integer fail_count = 0;
    integer test_no = 1;

    task automatic reset();
        rst_n = 0;
        tx_pt_en = 0;
        rx_pt_en = 0;
        tb_suppress_sb = 0;
        cfg_max_err_thresh_perlane = 0;
        cfg_max_err_thresh_aggr = 0;
        tb_perlane_pass = 16'hFFFF;
        tb_aggr_pass = 1;
        tb_val_pass = 1;
        d2c_clk_sampling = 0;
        d2c_pattern_setup = 3'b001;
        d2c_data_pattern_sel = 0;
        d2c_val_pattern_sel = 0;
        d2c_pattern_mode = 0;
        d2c_burst_count = 100;
        d2c_idle_count = 0;
        d2c_iter_count = 1;
        d2c_compare_setup = 0;
        repeat(5) @(posedge lclk);
        rst_n = 1;
        repeat(2) @(posedge lclk);
        if (tb_verbose) $display("%12t ps: Reset released.", $time);
    endtask

    task automatic set_config(
            input [1:0]  cs,
            input [2:0]  ps,
            input [1:0]  dp,
            input        vp,
            input        pm,
            input [15:0] bc,
            input [15:0] ic,
            input [15:0] nc,
            input [1:0]  cmp
        );
        d2c_clk_sampling     = cs;
        d2c_pattern_setup    = ps;
        d2c_data_pattern_sel = dp;
        d2c_val_pattern_sel  = vp;
        d2c_pattern_mode     = pm;
        d2c_burst_count      = bc;
        d2c_idle_count       = ic;
        d2c_iter_count       = nc;
        d2c_compare_setup    = cmp;
    endtask

    reg [15:0] captured_d2c_perlane_pass;
    reg        captured_d2c_aggr_pass;
    reg        captured_d2c_val_pass;

    task automatic start_test(input logic expect_timeout, input logic is_tx);
        @(posedge lclk);
        if (is_tx) tx_pt_en = 1;
        else       rx_pt_en = 1;

        fork : tf
            begin
                wait(req_test_done || timeout_8ms_occured_tb);
                // Capture active-state combinational outputs before deasserting en signals
                captured_d2c_perlane_pass = req_d2c_perlane_pass;
                captured_d2c_aggr_pass    = req_d2c_aggr_pass;
                captured_d2c_val_pass     = req_d2c_val_pass;
                @(posedge lclk);
                tx_pt_en = 0;
                rx_pt_en = 0;
                if (timeout_8ms_occured_tb) begin
                    if (expect_timeout) begin
                        if (tb_verbose) $display("%12t ps: [PASS] Expected timeout occurred.", $time);
                        success_count++;
                    end else begin
                        $display("%12t ps: [FAIL] Unexpected watchdog timeout!", $time);
                        fail_count++;
                        $stop;
                    end
                end else begin
                    if (expect_timeout) begin
                        $display("%12t ps: [FAIL] Expected timeout but test completed successfully!", $time);
                        fail_count++;
                        $stop;
                    end else begin
                        if (is_tx) begin
                            wait(tx_req_state == TX_PT_IDLE);
                        end else begin
                            wait(rx_req_state == RX_PT_IDLE);
                        end
                        if (tb_verbose) $display("%12t ps: [PASS] Test completed successfully.", $time);
                        success_count++;
                    end
                end
                if (tb_verbose) $display("(Pass=%0d, Fail=%0d)\n", success_count, fail_count);
                disable tf;
            end
            begin
                #(64'd5_000_000_000); // 5ms absolute safety timeout
                $display("[FAIL] Simulation Watchdog Safety Fired!");
                fail_count++;
                disable tf;
                $stop;
            end
        join
    endtask

    // =========================================================================
    // Interface check tasks for happy paths
    // =========================================================================
    task automatic check_tx_mb_signals(
            input string context_str,
            input logic  exp_mb_tx_pattern_en,
            input logic [2:0] exp_mb_tx_pattern_setup,
            input logic  exp_mb_tx_lfsr_en,
            input logic  exp_mb_tx_lfsr_rst,
            input logic [1:0] exp_mb_tx_clk_lane_sel,
            input logic [1:0] exp_mb_tx_val_lane_sel,
            input logic [1:0] exp_mb_tx_data_lane_sel
        );
        if (req_mb_tx_pattern_en !== exp_mb_tx_pattern_en) begin
            $display("  [FAIL] %s: mb_tx_pattern_en=%b, expected=%b", context_str, req_mb_tx_pattern_en, exp_mb_tx_pattern_en);
            fail_count++; $stop;
        end
        if (req_mb_tx_pattern_setup !== exp_mb_tx_pattern_setup) begin
            $display("  [FAIL] %s: mb_tx_pattern_setup=%b, expected=%b", context_str, req_mb_tx_pattern_setup, exp_mb_tx_pattern_setup);
            fail_count++; $stop;
        end
        if (req_mb_tx_lfsr_en !== exp_mb_tx_lfsr_en) begin
            $display("  [FAIL] %s: mb_tx_lfsr_en=%b, expected=%b", context_str, req_mb_tx_lfsr_en, exp_mb_tx_lfsr_en);
            fail_count++; $stop;
        end
        if (req_mb_tx_lfsr_rst !== exp_mb_tx_lfsr_rst) begin
            $display("  [FAIL] %s: mb_tx_lfsr_rst=%b, expected=%b", context_str, req_mb_tx_lfsr_rst, exp_mb_tx_lfsr_rst);
            fail_count++; $stop;
        end
        if (req_mb_tx_clk_lane_sel !== exp_mb_tx_clk_lane_sel) begin
            $display("  [FAIL] %s: mb_tx_clk_lane_sel=%b, expected=%b", context_str, req_mb_tx_clk_lane_sel, exp_mb_tx_clk_lane_sel);
            fail_count++; $stop;
        end
        if (req_mb_tx_val_lane_sel !== exp_mb_tx_val_lane_sel) begin
            $display("  [FAIL] %s: mb_tx_val_lane_sel=%b, expected=%b", context_str, req_mb_tx_val_lane_sel, exp_mb_tx_val_lane_sel);
            fail_count++; $stop;
        end
        if (req_mb_tx_data_lane_sel !== exp_mb_tx_data_lane_sel) begin
            $display("  [FAIL] %s: mb_tx_data_lane_sel=%b, expected=%b", context_str, req_mb_tx_data_lane_sel, exp_mb_tx_data_lane_sel);
            fail_count++; $stop;
        end
    endtask

    task automatic check_rx_mb_signals(
            input string context_str,
            input logic  exp_mb_rx_compare_en,
            input logic  exp_mb_rx_lfsr_en,
            input logic  exp_mb_rx_lfsr_rst,
            input logic  exp_mb_rx_clk_lane_sel,
            input logic  exp_mb_rx_val_lane_sel,
            input logic  exp_mb_rx_data_lane_sel
        );
        if (req_mb_rx_compare_en !== exp_mb_rx_compare_en) begin
            $display("  [FAIL] %s: mb_rx_compare_en=%b, expected=%b", context_str, req_mb_rx_compare_en, exp_mb_rx_compare_en);
            fail_count++; $stop;
        end
        if (req_mb_rx_lfsr_en !== exp_mb_rx_lfsr_en) begin
            $display("  [FAIL] %s: mb_rx_lfsr_en=%b, expected=%b", context_str, req_mb_rx_lfsr_en, exp_mb_rx_lfsr_en);
            fail_count++; $stop;
        end
        if (req_mb_rx_lfsr_rst !== exp_mb_rx_lfsr_rst) begin
            $display("  [FAIL] %s: mb_rx_lfsr_rst=%b, expected=%b", context_str, req_mb_rx_lfsr_rst, exp_mb_rx_lfsr_rst);
            fail_count++; $stop;
        end
        if (req_mb_rx_clk_lane_sel !== exp_mb_rx_clk_lane_sel) begin
            $display("  [FAIL] %s: mb_rx_clk_lane_sel=%b, expected=%b", context_str, req_mb_rx_clk_lane_sel, exp_mb_rx_clk_lane_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_val_lane_sel !== exp_mb_rx_val_lane_sel) begin
            $display("  [FAIL] %s: mb_rx_val_lane_sel=%b, expected=%b", context_str, req_mb_rx_val_lane_sel, exp_mb_rx_val_lane_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_data_lane_sel !== exp_mb_rx_data_lane_sel) begin
            $display("  [FAIL] %s: mb_rx_data_lane_sel=%b, expected=%b", context_str, req_mb_rx_data_lane_sel, exp_mb_rx_data_lane_sel);
            fail_count++; $stop;
        end
    endtask

    // =========================================================================
    // Verification loop for happy paths
    // =========================================================================
    task automatic run_verified_tx_happy_path(input string scenario_name);
        logic exp_lfsr_en;
        exp_lfsr_en = (d2c_data_pattern_sel == 2'b00 && d2c_pattern_setup[0] == 1'b1);

        wait(tx_req_state == TX_PT_SEND_START_REQ);
        @(negedge lclk);
        check_tx_mb_signals("SEND_START_REQ", 1'b0, d2c_pattern_setup, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00);

        wait(tx_req_state == TX_PT_SEND_CLR_ERR_REQ);
        @(negedge lclk);
        check_tx_mb_signals("SEND_CLR_ERR_REQ", 1'b0, d2c_pattern_setup, 1'b0, 1'b1, 2'b00, 2'b00, 2'b00);

        wait(tx_req_state == TX_PT_PATTERN_GEN);
        @(negedge lclk);
        check_tx_mb_signals("PATTERN_GEN", 1'b1, d2c_pattern_setup, exp_lfsr_en, 1'b0,
            d2c_pattern_setup[2] ? 2'b01 : 2'b00,
            d2c_pattern_setup[1] ? 2'b01 : 2'b00,
            d2c_pattern_setup[0] ? 2'b01 : 2'b00);

        wait(tx_req_state == TX_PT_DONE);
        @(negedge lclk);
        if (req_test_done !== 1'b1) begin
            $display("  [FAIL] TX PT: Done state not reached or test_done was low.");
            fail_count++; $stop;
        end
    endtask

    task automatic run_verified_rx_happy_path(input string scenario_name);
        logic exp_lfsr_en;
        exp_lfsr_en = (d2c_data_pattern_sel == 2'b00 && d2c_pattern_setup[0] == 1'b1);

        wait(rx_req_state == RX_PT_SEND_START_REQ);
        @(negedge lclk);
        check_rx_mb_signals("SEND_START_REQ", 1'b1, exp_lfsr_en, 1'b0, 1'b1, 1'b1, 1'b1);

        wait(rx_req_state == RX_PT_SEND_CLR_ERR_RESP);
        @(negedge lclk);
        check_rx_mb_signals("SEND_CLR_ERR_RESP", 1'b1, exp_lfsr_en, 1'b1, 1'b1, 1'b1, 1'b1);

        wait(rx_req_state == RX_PT_WAIT_COUNT_DONE_REQ);
        @(negedge lclk);
        check_rx_mb_signals("WAIT_COUNT_DONE_REQ", 1'b1, exp_lfsr_en, 1'b0, 1'b1, 1'b1, 1'b1);

        wait(rx_req_state == RX_PT_SEND_COUNT_DONE_RESP);
        @(negedge lclk);
        check_rx_mb_signals("SEND_COUNT_DONE_RESP", 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);

        wait(rx_req_state == RX_PT_DONE);
        @(negedge lclk);
        if (req_test_done !== 1'b1) begin
            $display("  [FAIL] RX PT: Done state not reached or test_done was low.");
            fail_count++; $stop;
        end
    endtask

    // =========================================================================
    // Test Sequences
    // =========================================================================
    initial begin
        $display("\n=== wrapper_D2C_PT Comprehensive Wrapper-level Testbench ===\n");
        $display("  Signal polarity: *_pass signals: 1=pass, 0=fail\n");

        tb_verbose = 1; // enable transition logs during first happy paths

        // ---------------------------------------------------------------------
        // Scenario 1: TX Happy Path - LFSR, All Pass (Full signal verification)
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: TX Happy Path (Per-Lane LFSR, All Pass)", test_no++);
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 80, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        fork
            run_verified_tx_happy_path("Scenario 1");
        join_none
        start_test(0, 1);
        if (captured_d2c_perlane_pass == 16'hFFFF && captured_d2c_aggr_pass == 1'b1 && captured_d2c_val_pass == 1'b1)
            $display("  [OK] Happy Path TX match.");
        else begin
            $display("  [FAIL] Happy Path TX results mismatch: perlane=%h aggr=%b val=%b", captured_d2c_perlane_pass, captured_d2c_aggr_pass, captured_d2c_val_pass);
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 2: TX Partial Lane failure
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: TX Partial Failure (perlane_pass=0xBEEF)", test_no++);
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 40, 0, 1, 2'd0);
        tb_perlane_pass = 16'hBEEF; tb_aggr_pass = 0; tb_val_pass = 1;
        start_test(0, 1);
        if (captured_d2c_perlane_pass == 16'hBEEF)
            $display("  [OK] Partial TX mismatch log verified.");
        else begin
            $display("  [FAIL] TX Partial failed: got %h expected BEEF", captured_d2c_perlane_pass);
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 3: TX Aggregate failure mode
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: TX Aggregate mode failure", test_no++);
        reset();
        cfg_max_err_thresh_aggr = 16'h0050;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 30, 0, 1, 2'd1);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 0; tb_val_pass = 1;
        start_test(0, 1);
        if (captured_d2c_aggr_pass == 1'b0)
            $display("  [OK] Aggregate mode failure verified.");
        else begin
            $display("  [FAIL] TX Aggregate fail check mismatch.");
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 4: TX Valid Lane failure mode
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: TX Valid Lane Failure mode", test_no++);
        reset();
        set_config(2'b00, 3'b010, 2'b00, 0, 0, 15, 0, 1, 2'd2);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 0;
        start_test(0, 1);
        if (captured_d2c_val_pass == 1'b0)
            $display("  [OK] Valid lane mode failure verified.");
        else begin
            $display("  [FAIL] TX Valid Lane fail check mismatch.");
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 5: RX Happy Path - LFSR, All Pass (Full signal verification)
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: RX Happy Path (Per-Lane LFSR, All Pass)", test_no++);
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 80, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        fork
            run_verified_rx_happy_path("Scenario 5");
        join_none
        start_test(0, 0);
        if (captured_d2c_perlane_pass == 16'hFFFF && captured_d2c_aggr_pass == 1'b1 && captured_d2c_val_pass == 1'b1)
            $display("  [OK] Happy Path RX match.");
        else begin
            $display("  [FAIL] Happy Path RX results mismatch.");
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 6: RX Partial Failure
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: RX Partial Failure (perlane_pass=0xDEAD)", test_no++);
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 25, 0, 1, 2'd0);
        tb_perlane_pass = 16'hDEAD; tb_aggr_pass = 0; tb_val_pass = 1;
        start_test(0, 0);
        if (captured_d2c_perlane_pass == 16'hDEAD)
            $display("  [OK] Partial RX mismatch logged correctly.");
        else begin
            $display("  [FAIL] RX Partial failed: got %h expected DEAD", captured_d2c_perlane_pass);
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 7: RX Aggregate failure mode
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: RX Aggregate mode failure", test_no++);
        reset();
        cfg_max_err_thresh_aggr = 16'h00A0;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd1);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 0; tb_val_pass = 1;
        start_test(0, 0);
        if (captured_d2c_aggr_pass == 1'b0)
            $display("  [OK] Aggregate mode failure verified.");
        else begin
            $display("  [FAIL] RX Aggregate fail check mismatch.");
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 8: RX Valid Lane failure mode
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: RX Valid Lane Failure mode", test_no++);
        reset();
        set_config(2'b00, 3'b010, 2'b00, 0, 0, 12, 0, 1, 2'd2);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 0;
        start_test(0, 0);
        if (captured_d2c_val_pass == 1'b0)
            $display("  [OK] Valid lane mode failure verified.");
        else begin
            $display("  [FAIL] RX Valid Lane fail check mismatch.");
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 9: Timeout Simulator on TX PT
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Watchdog Timeout on TX Point Test (SB Suppressed)", test_no++);
        reset();
        tb_suppress_sb = 1;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        start_test(1, 1);

        // ---------------------------------------------------------------------
        // Scenario 10: Timeout Simulator on RX PT
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Watchdog Timeout on RX Point Test (SB Suppressed)", test_no++);
        reset();
        tb_suppress_sb = 1;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        start_test(1, 0);

        // ---------------------------------------------------------------------
        // Scenario 11: Burst Mode Check
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Burst Mode (iter=3, burst=40, idle=20)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 1, 40, 20, 3, 2'd0);
        start_test(0, 1);

        // ---------------------------------------------------------------------
        // Scenario 12: Clock phase sampling edge check
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Clock Sampling Left & Right edges", test_no++);
        reset();
        set_config(2'b01, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0); // Left Edge
        start_test(0, 1);
        reset();
        set_config(2'b10, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0); // Right Edge
        start_test(0, 1);

        // ---------------------------------------------------------------------
        // Scenario 13: Per-lane ID pattern (scrambler LFSR disabled)
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Per-lane ID Pattern (lfsr scrambler disabled)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b01, 0, 0, 30, 0, 1, 2'd0);
        fork
            begin
                wait(tx_req_state == TX_PT_PATTERN_GEN);
                @(negedge lclk);
                if (req_mb_tx_lfsr_en !== 1'b0) begin
                    $display("  [FAIL] scrambler should be disabled in Per-Lane ID pattern.");
                    fail_count++; $stop;
                end
            end
        join_none
        start_test(0, 1);

        // ---------------------------------------------------------------------
        // Scenario 14: All Lanes Fail
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: All Lanes Fail", test_no++);
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        tb_perlane_pass = 16'h0000; tb_aggr_pass = 0; tb_val_pass = 0;
        start_test(0, 1);
        if (captured_d2c_perlane_pass == 16'h0000 && captured_d2c_aggr_pass == 1'b0 && captured_d2c_val_pass == 1'b0)
            $display("  [OK] All fail results matched successfully.");
        else begin
            $display("  [FAIL] All fail results check mismatch: %h %b %b", captured_d2c_perlane_pass, captured_d2c_aggr_pass, captured_d2c_val_pass);
            fail_count++; $stop;
        end

        // ---------------------------------------------------------------------
        // Scenario 15: Back-to-Back TX followed by RX Point Test
        // ---------------------------------------------------------------------
        $display("=> Scenario %0d: Back-to-Back TX then RX point tests", test_no++);
        reset();
        tb_perlane_pass = 16'hAAAA;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0, 1); // Run TX
        if (captured_d2c_perlane_pass == 16'hAAAA)
            $display("  [OK] B2B Part 1 TX complete.");
        else begin
            $display("  [FAIL] B2B Part 1 failed.");
            fail_count++; $stop;
        end

        tb_perlane_pass = 16'h5555;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0, 0); // Run RX directly
        if (captured_d2c_perlane_pass == 16'h5555)
            $display("  [OK] B2B Part 2 RX complete.");
        else begin
            $display("  [FAIL] B2B Part 2 failed: %h", captured_d2c_perlane_pass);
            fail_count++; $stop;
        end

        // =====================================================================
        // Happy Path Scenarios Verification Complete
        // =====================================================================
        $display("\n--- Happy Path Scenarios Complete: Pass=%0d, Fail=%0d ---\n", success_count, fail_count);
        if (fail_count > 0) begin
            $display("[STOP] Please resolve Happy Path failures first.");
            $stop;
        end

        // ---------------------------------------------------------------------
        // 200 Randomized Iterations (Silent log, no repetitive display!)
        // ---------------------------------------------------------------------
        tb_verbose = 0; // completely silent state changes and periodic displays!

        $display("Starting 200 Randomized Iterations...\n");
        for (int r = 0; r < 200; r++) begin
            logic is_tx_rand;
            is_tx_rand = $urandom_range(0, 1);
            reset();

            // Randomize pass result configurations
            tb_perlane_pass            = $urandom();
            tb_aggr_pass               = $urandom_range(0, 1);
            tb_val_pass                = $urandom_range(0, 1);
            cfg_max_err_thresh_perlane = $urandom() & 12'hFFF;
            cfg_max_err_thresh_aggr    = $urandom();
            tb_suppress_sb             = ($urandom_range(0, 9) == 0); // 10% timeout risk

            set_config(
                $urandom_range(0, 2),     // clk sampling (0-2)
                $urandom_range(0, 7),     // pattern setup components (0-7)
                $urandom_range(0, 2),     // data pattern select (0-2)
                $urandom_range(0, 1),     // val pattern select (0-1)
                $urandom_range(0, 1),     // pattern mode (0-1)
                $urandom_range(1, 100),   // burst count (1-100)
                $urandom_range(0, 50),    // idle count (0-50)
                $urandom_range(1, 8),     // iter count (1-8)
                $urandom_range(0, 3)      // compare setup target (0-3)
            );

            start_test(tb_suppress_sb, is_tx_rand);

            // Assert output consistency in non-timeout runs
            if (!tb_suppress_sb) begin
                if (is_tx_rand) begin
                    logic [15:0] exp_negotiated_data_lanes;
                    logic        exp_tx_accumulative_perlane_pass;
                    logic        expected_tx_aggr_pass;

                    case (d2c_pattern_setup)
                        3'b000:  exp_negotiated_data_lanes = 16'h0000;
                        3'b001:  exp_negotiated_data_lanes = 16'h00FF;
                        3'b010:  exp_negotiated_data_lanes = 16'hFF00;
                        3'b011:  exp_negotiated_data_lanes = 16'hFFFF;
                        3'b100:  exp_negotiated_data_lanes = 16'h000F;
                        3'b101:  exp_negotiated_data_lanes = 16'h00F0;
                        default: exp_negotiated_data_lanes = 16'h0000;
                    endcase

                    exp_tx_accumulative_perlane_pass = &(tb_perlane_pass | ~exp_negotiated_data_lanes);
                    expected_tx_aggr_pass = (d2c_compare_setup != 2'b00) ? tb_aggr_pass : exp_tx_accumulative_perlane_pass;

                    if (captured_d2c_perlane_pass !== tb_perlane_pass) begin
                        $display("  [FAIL] Rand Iter %0d (TX): perlane_pass=%h, expected=%h", r+1, captured_d2c_perlane_pass, tb_perlane_pass);
                        fail_count++; $stop;
                    end
                    if (captured_d2c_aggr_pass !== expected_tx_aggr_pass) begin
                        $display("  [FAIL] Rand Iter %0d (TX): aggr_pass=%b, expected=%b", r+1, captured_d2c_aggr_pass, expected_tx_aggr_pass);
                        $display("         d2c_compare_setup=%b", d2c_compare_setup);
                        $display("         d2c_pattern_setup=%b", d2c_pattern_setup);
                        $display("         tb_perlane_pass=%h", tb_perlane_pass);
                        $display("         tb_aggr_pass=%b", tb_aggr_pass);
                        $display("         exp_negotiated_data_lanes=%h", exp_negotiated_data_lanes);
                        $display("         exp_tx_accumulative_perlane_pass=%b", exp_tx_accumulative_perlane_pass);
                        $display("         captured_d2c_perlane_pass=%h", captured_d2c_perlane_pass);
                        fail_count++; $stop;
                    end
                    if (captured_d2c_val_pass !== tb_val_pass) begin
                        $display("  [FAIL] Rand Iter %0d (TX): val_pass=%b, expected=%b", r+1, captured_d2c_val_pass, tb_val_pass);
                        fail_count++; $stop;
                    end
                end else begin
                    if (captured_d2c_perlane_pass !== tb_perlane_pass) begin
                        $display("  [FAIL] Rand Iter %0d (RX): perlane_pass=%h, expected=%h", r+1, captured_d2c_perlane_pass, tb_perlane_pass);
                        fail_count++; $stop;
                    end
                    if (captured_d2c_aggr_pass !== tb_aggr_pass) begin
                        $display("  [FAIL] Rand Iter %0d (RX): aggr_pass=%b, expected=%b", r+1, captured_d2c_aggr_pass, tb_aggr_pass);
                        fail_count++; $stop;
                    end
                    if (captured_d2c_val_pass !== tb_val_pass) begin
                        $display("  [FAIL] Rand Iter %0d (RX): val_pass=%b, expected=%b", r+1, captured_d2c_val_pass, tb_val_pass);
                        fail_count++; $stop;
                    end
                end
            end
        end

        // =====================================================================
        // Final Summary
        // =====================================================================
        if (fail_count == 0) begin
            $display("\n  ========================================================");
            $display("  ==  Congratulations! Wrapper Level All Tests PASSED!  ==");
            $display("  ========================================================\n");
        end else begin
            $display("\n  ========================================================");
            $display("  ==       FAILED: %0d test runs had error failures!    ==", fail_count);
            $display("  ========================================================\n");
        end
        $display("Total: Pass=%0d, Fail=%0d", success_count, fail_count);
        $stop;
    end

endmodule
