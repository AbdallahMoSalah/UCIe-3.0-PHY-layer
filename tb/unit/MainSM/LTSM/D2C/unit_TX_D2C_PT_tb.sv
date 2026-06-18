`timescale 1ps/1ps
// unit_TX_D2C_PT_tb.sv — Dual-die TB for unit_TX_D2C_PT_local + unit_TX_D2C_PT_partner
// Comprehensive testbench: verifies ALL interface signals at EVERY FSM state.
module unit_TX_D2C_PT_tb;
    import UCIe_pkg::*;
    parameter LCLK_PERIOD   = 1000;
    parameter SB_DELAY_CYCS = 64;
    parameter TIMEOUT_LIMIT = 200_000;

    reg lclk=0, rst_n=0;
    always #(LCLK_PERIOD/2) lclk = ~lclk;

    //======================================================================
    // LOCAL die (unit_TX_D2C_PT_local) inputs
    //======================================================================
    reg        tx_pt_en=0;
    reg [1:0]  d2c_clk_sampling=0;               // 00: Eye Center, 01: Left Edge, 10: Right Edge
    reg [2:0]  d2c_pattern_setup=3'b001;          // Bit0: Data, Bit1: Valid, Bit2: Clock
    reg [1:0]  d2c_data_pattern_sel=0;            // 00: LFSR, 01: Per-Lane ID, 10: All Zeros
    reg        d2c_val_pattern_sel=0;             // 0: VALTRAIN, 1: Held Low
    reg        d2c_pattern_mode=0;                // 0: Continuous, 1: Burst
    reg [15:0] d2c_burst_count=100;               // Burst duration in UI
    reg [15:0] d2c_idle_count=0;                  // Idle duration in UI
    reg [15:0] d2c_iter_count=1;                  // Iteration count
    reg [1:0]  d2c_compare_setup=0;               // 00: Per-Lane, 01: Aggregate, 10: Valid, 11: Clock
    reg [11:0] cfg_max_err_thresh_perlane=0;      // Per-lane max error threshold
    reg [15:0] cfg_max_err_thresh_aggr=0;         // Aggregate max error threshold
    reg        loc_mb_tx_pattern_count_done=0;    // 0: TX transmitting, 1: TX pattern complete

    //======================================================================
    // PARTNER die (unit_TX_D2C_PT_partner) inputs
    //======================================================================
    reg        part_tx_pt_en=0;
    reg [2:0]  part_mb_rx_data_lane_mask=3'b011; // 011: Lanes 0-15
    // reg        part_mb_rx_compare_done=0;         // 0: Comparison in progress, 1: Comparison complete
    reg        part_mb_rx_aggr_pass=0;            // 1: Aggregate passed, 0: Failed
    reg [15:0] part_mb_rx_perlane_pass=0;         // Per-lane pass/fail bits
    reg        part_mb_rx_val_pass=0;             // 1: Valid matched, 0: Valid mismatch

    //======================================================================
    // LOCAL die (unit_TX_D2C_PT_local) outputs
    //======================================================================
    wire        loc_test_d2c_done;                // 0: In progress, 1: Test complete
    wire [15:0] loc_d2c_perlane_pass;             // 16-bit: each bit = 1 means that lane passed
    wire        loc_d2c_aggr_pass;                // 1-bit cumulative aggregate pass result
    wire        loc_d2c_val_pass;                 // Valid Lane pass result
    wire        loc_tx_sb_valid;                  // SB TX valid pulse
    wire [7:0]  loc_tx_sb_msg;                    // SB TX message code
    wire [15:0] loc_tx_msginfo;                   // SB TX MsgInfo payload
    wire [63:0] loc_tx_data_field;                // SB TX 64-bit data payload
    wire        loc_mb_tx_clk_sampling_en_w;      // 0: Unchanged, 1: Update TX clock phase
    wire [1:0]  loc_mb_tx_clk_sampling_w;         // 00: Eye Center, 01: Left Edge, 10: Right Edge
    wire        loc_mb_tx_pattern_en_w;            // 0: Idle, 1: Drive training pattern
    wire [2:0]  loc_mb_tx_pattern_setup_w;         // Bit0: Data, Bit1: Valid, Bit2: Clock
    wire        loc_mb_tx_lfsr_en_w;               // 0: Disable, 1: Enable TX LFSR
    wire        loc_mb_tx_lfsr_rst_w;              // 0: Normal, 1: Reset TX LFSR
    wire        loc_mb_tx_pattern_mode_w;           // 0: Continuous, 1: Burst
    wire [15:0] loc_mb_tx_burst_count_w;            // TX burst count pass-through
    wire [15:0] loc_mb_tx_idle_count_w;             // TX idle count pass-through
    wire [15:0] loc_mb_tx_iter_count_w;             // TX iteration count pass-through
    wire [1:0]  loc_mb_tx_data_pattern_sel_w;       // 00: LFSR, 01: Per-Lane ID
    wire        loc_mb_tx_val_pattern_sel_w;         // 0: VALTRAIN, 1: Held Low
    wire [1:0]  loc_mb_tx_trk_lane_sel_w;            // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  loc_mb_tx_clk_lane_sel_w;            // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  loc_mb_tx_val_lane_sel_w;            // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  loc_mb_tx_data_lane_sel_w;           // 00: Low, 01: Active, 1x: Tri-stated

    //======================================================================
    // PARTNER die (unit_TX_D2C_PT_partner) outputs
    //======================================================================
    wire        part_test_d2c_done;                // 0: In progress, 1: Test complete
    wire        part_tx_sb_valid;                  // SB TX valid pulse
    wire [7:0]  part_tx_sb_msg;                    // SB TX message code
    wire [15:0] part_tx_msginfo;                   // SB TX MsgInfo payload
    wire [63:0] part_tx_data_field;                // SB TX 64-bit data payload
    wire        part_mb_rx_trk_lane_sel_w;          // 0: Disabled, 1: Enabled
    wire        part_mb_rx_clk_lane_sel_w;          // 0: Disabled, 1: Enabled
    wire        part_mb_rx_val_lane_sel_w;          // 0: Disabled, 1: Enabled
    wire        part_mb_rx_data_lane_sel_w;         // 0: Disabled, 1: Enabled
    wire [2:0]  part_mb_rx_pattern_setup_w;         // 001: Data, 010: Valid, 100: Clock
    wire        part_mb_rx_lfsr_en_w;               // 0: Disable, 1: Enable RX LFSR
    wire        part_mb_rx_lfsr_rst_w;              // 0: Normal, 1: Reset RX LFSR
    wire [15:0] part_mb_rx_iter_count_w;            // RX iteration count (decoded from SB)
    wire [15:0] part_mb_rx_idle_count_w;            // RX idle count (decoded from SB)
    wire [15:0] part_mb_rx_burst_count_w;           // RX burst count (decoded from SB)
    wire        part_mb_rx_pattern_mode_w;          // 0: Continuous, 1: Burst
    wire        part_mb_rx_val_pattern_sel_w;       // 0: VALTRAIN, 1: Held Low
    wire [1:0]  part_mb_rx_data_pattern_sel_w;      // 00: LFSR, 01: Per-Lane ID, 10: All Zeros
    wire        part_mb_rx_compare_en_w;            // 0: Disable, 1: Enable RX comparison
    wire [1:0]  part_mb_rx_compare_setup_w;         // 00: Per-Lane, 01: Aggregate
    wire [11:0] part_mb_rx_max_err_thresh_perlane_w; // Per-lane threshold (decoded from SB)
    wire [15:0] part_mb_rx_max_err_thresh_aggr_w;   // Aggregate threshold (decoded from SB)

    //======================================================================
    // SB pipeline delay (models async FIFO crossing)
    //======================================================================
    reg tb_suppress_sb = 0;
    reg [SB_DELAY_CYCS-1:0] loc2part_valid_sr, part2loc_valid_sr;
    reg [7:0]  loc2part_msg_sr  [SB_DELAY_CYCS-1:0], part2loc_msg_sr  [SB_DELAY_CYCS-1:0];
    reg [15:0] loc2part_info_sr [SB_DELAY_CYCS-1:0], part2loc_info_sr [SB_DELAY_CYCS-1:0];
    reg [63:0] loc2part_data_sr [SB_DELAY_CYCS-1:0], part2loc_data_sr [SB_DELAY_CYCS-1:0];

    wire loc_rx_sb_valid_w   = part2loc_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  loc_rx_sb_msg_w    = part2loc_msg_sr  [SB_DELAY_CYCS-1];
    wire [15:0] loc_rx_msginfo_w   = part2loc_info_sr [SB_DELAY_CYCS-1];
    wire [63:0] loc_rx_data_field_w= part2loc_data_sr [SB_DELAY_CYCS-1];

    wire part_rx_sb_valid_w  = loc2part_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  part_rx_sb_msg_w    = loc2part_msg_sr  [SB_DELAY_CYCS-1];
    wire [15:0] part_rx_msginfo_w   = loc2part_info_sr [SB_DELAY_CYCS-1];
    wire [63:0] part_rx_data_field_w= loc2part_data_sr [SB_DELAY_CYCS-1];

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            loc2part_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            part2loc_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            for (pi=0; pi<SB_DELAY_CYCS; pi=pi+1) begin
                loc2part_msg_sr[pi]<=0; loc2part_info_sr[pi]<=0; loc2part_data_sr[pi]<=0;
                part2loc_msg_sr[pi]<=0; part2loc_info_sr[pi]<=0; part2loc_data_sr[pi]<=0;
            end
        end else begin
            loc2part_valid_sr <= {loc2part_valid_sr[SB_DELAY_CYCS-2:0], loc_tx_sb_valid};
            part2loc_valid_sr <= {part2loc_valid_sr[SB_DELAY_CYCS-2:0], part_tx_sb_valid};
            for (pi=1; pi<SB_DELAY_CYCS; pi=pi+1) begin
                loc2part_msg_sr[pi]  <= loc2part_msg_sr[pi-1];
                loc2part_info_sr[pi] <= loc2part_info_sr[pi-1];
                loc2part_data_sr[pi] <= loc2part_data_sr[pi-1];
                part2loc_msg_sr[pi]  <= part2loc_msg_sr[pi-1];
                part2loc_info_sr[pi] <= part2loc_info_sr[pi-1];
                part2loc_data_sr[pi] <= part2loc_data_sr[pi-1];
            end
            loc2part_msg_sr[0]  <= loc_tx_sb_msg;
            loc2part_info_sr[0] <= loc_tx_msginfo;
            loc2part_data_sr[0] <= loc_tx_data_field;
            part2loc_msg_sr[0]  <= part_tx_sb_msg;
            part2loc_info_sr[0] <= part_tx_msginfo;
            part2loc_data_sr[0] <= part_tx_data_field;
        end
    end

    //======================================================================
    // DUT: LOCAL die (unit_TX_D2C_PT_local)
    //======================================================================
    unit_TX_D2C_PT_local loc_die (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .tx_pt_en                       (tx_pt_en),
        .test_d2c_done                  (loc_test_d2c_done),
        .d2c_clk_sampling               (d2c_clk_sampling),
        .d2c_pattern_setup              (d2c_pattern_setup),
        .d2c_data_pattern_sel           (d2c_data_pattern_sel),
        .d2c_val_pattern_sel            (d2c_val_pattern_sel),
        .d2c_pattern_mode               (d2c_pattern_mode),
        .d2c_burst_count                (d2c_burst_count),
        .d2c_idle_count                 (d2c_idle_count),
        .d2c_iter_count                 (d2c_iter_count),
        .d2c_compare_setup              (d2c_compare_setup),
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr),
        .d2c_perlane_pass               (loc_d2c_perlane_pass),
        .d2c_aggr_pass                  (loc_d2c_aggr_pass),
        .d2c_val_pass                   (loc_d2c_val_pass),
        .mb_tx_clk_sampling_en          (loc_mb_tx_clk_sampling_en_w),
        .mb_tx_clk_sampling             (loc_mb_tx_clk_sampling_w),
        .mb_tx_pattern_en               (loc_mb_tx_pattern_en_w),
        .mb_tx_pattern_setup            (loc_mb_tx_pattern_setup_w),
        .mb_tx_lfsr_en                  (loc_mb_tx_lfsr_en_w),
        .mb_tx_lfsr_rst                 (loc_mb_tx_lfsr_rst_w),
        .mb_tx_pattern_mode             (loc_mb_tx_pattern_mode_w),
        .mb_tx_burst_count              (loc_mb_tx_burst_count_w),
        .mb_tx_idle_count               (loc_mb_tx_idle_count_w),
        .mb_tx_iter_count               (loc_mb_tx_iter_count_w),
        .mb_tx_data_pattern_sel         (loc_mb_tx_data_pattern_sel_w),
        .mb_tx_val_pattern_sel          (loc_mb_tx_val_pattern_sel_w),
        .mb_tx_pattern_count_done       (loc_mb_tx_pattern_count_done),
        .mb_tx_trk_lane_sel             (loc_mb_tx_trk_lane_sel_w),
        .mb_tx_clk_lane_sel             (loc_mb_tx_clk_lane_sel_w),
        .mb_tx_val_lane_sel             (loc_mb_tx_val_lane_sel_w),
        .mb_tx_data_lane_sel            (loc_mb_tx_data_lane_sel_w),
        .tx_sb_msg_valid                (loc_tx_sb_valid),
        .tx_sb_msg                      (loc_tx_sb_msg),
        .tx_msginfo                     (loc_tx_msginfo),
        .tx_data_field                  (loc_tx_data_field),
        .rx_sb_msg_valid                (loc_rx_sb_valid_w),
        .rx_sb_msg                      (loc_rx_sb_msg_w),
        .rx_msginfo                     (loc_rx_msginfo_w),
        .rx_data_field                  (loc_rx_data_field_w)
    );

    //======================================================================
    // DUT: PARTNER die (unit_TX_D2C_PT_partner)
    //======================================================================
    unit_TX_D2C_PT_partner part_die (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .tx_pt_en                       (part_tx_pt_en),
        .test_d2c_done                  (part_test_d2c_done),
        .mb_rx_trk_lane_sel             (part_mb_rx_trk_lane_sel_w),
        .mb_rx_clk_lane_sel             (part_mb_rx_clk_lane_sel_w),
        .mb_rx_val_lane_sel             (part_mb_rx_val_lane_sel_w),
        .mb_rx_data_lane_sel            (part_mb_rx_data_lane_sel_w),
        .mb_rx_pattern_setup            (part_mb_rx_pattern_setup_w),
        .mb_rx_lfsr_en                  (part_mb_rx_lfsr_en_w),
        .mb_rx_lfsr_rst                 (part_mb_rx_lfsr_rst_w),
        .mb_rx_iter_count               (part_mb_rx_iter_count_w),
        .mb_rx_idle_count               (part_mb_rx_idle_count_w),
        .mb_rx_burst_count              (part_mb_rx_burst_count_w),
        .mb_rx_pattern_mode             (part_mb_rx_pattern_mode_w),
        .mb_rx_val_pattern_sel          (part_mb_rx_val_pattern_sel_w),
        .mb_rx_data_pattern_sel         (part_mb_rx_data_pattern_sel_w),
        .mb_rx_compare_en               (part_mb_rx_compare_en_w),
        .mb_rx_compare_setup            (part_mb_rx_compare_setup_w),
        .mb_rx_max_err_thresh_perlane   (part_mb_rx_max_err_thresh_perlane_w),
        .mb_rx_max_err_thresh_aggr      (part_mb_rx_max_err_thresh_aggr_w),
        .mb_rx_data_lane_mask           (part_mb_rx_data_lane_mask),
        // .mb_rx_compare_done             (part_mb_rx_compare_done),
        .mb_rx_aggr_pass                (part_mb_rx_aggr_pass),
        .mb_rx_perlane_pass             (part_mb_rx_perlane_pass),
        .mb_rx_val_pass                 (part_mb_rx_val_pass),
        .tx_sb_msg_valid                (part_tx_sb_valid),
        .tx_sb_msg                      (part_tx_sb_msg),
        .tx_msginfo                     (part_tx_msginfo),
        .tx_data_field                  (part_tx_data_field),
        .rx_sb_msg_valid                (part_rx_sb_valid_w),
        .rx_sb_msg                      (part_rx_sb_msg_w),
        .rx_msginfo                     (part_rx_msginfo_w),
        .rx_data_field                  (part_rx_data_field_w)
    );

    //======================================================================
    // FSM State Monitors
    //======================================================================
    // LOCAL FSM (unit_TX_D2C_PT_local):
    //   IDLE(0) SEND_START_REQ(1) WAIT_START_RESP(2) SEND_CLR_ERR_REQ(3)
    //   WAIT_CLR_ERR_RESP(4) PATTERN_GEN(5) SEND_RESULTS_REQ(6)
    //   WAIT_RESULTS_RESP(7) SEND_END_REQ(8) WAIT_END_RESP(9) DONE(A)
    typedef enum reg [3:0] {
        TX_PT_IDLE_L               = 4'h0,
        TX_PT_SEND_START_REQ_L     = 4'h1,
        TX_PT_WAIT_START_RESP_L    = 4'h2,
        TX_PT_SEND_CLR_ERR_REQ_L  = 4'h3,
        TX_PT_WAIT_CLR_ERR_RESP_L = 4'h4,
        TX_PT_PATTERN_GEN_L       = 4'h5,
        TX_PT_SEND_RESULTS_REQ_L  = 4'h6,
        TX_PT_WAIT_RESULTS_RESP_L = 4'h7,
        TX_PT_SEND_END_REQ_L      = 4'h8,
        TX_PT_WAIT_END_RESP_L     = 4'h9,
        TX_PT_DONE_L              = 4'hA
    } loc_fsm_t;

    // PARTNER FSM (unit_TX_D2C_PT_partner):
    //   IDLE(0) WAIT_START_REQ(1) SEND_START_RESP(2) WAIT_CLR_ERR_REQ(3)
    //   SEND_CLR_ERR_RESP(4) WAIT_RESULTS_REQ(5) SEND_RESULTS_RESP(6)
    //   WAIT_END_REQ(7) SEND_END_RESP(8) DONE(9)
    typedef enum reg [3:0] {
        TX_PT_IDLE_P               = 4'h0,
        TX_PT_WAIT_START_REQ_P     = 4'h1,
        TX_PT_SEND_START_RESP_P    = 4'h2,
        TX_PT_WAIT_CLR_ERR_REQ_P  = 4'h3,
        TX_PT_SEND_CLR_ERR_RESP_P = 4'h4,
        TX_PT_WAIT_RESULTS_REQ_P  = 4'h5,
        TX_PT_SEND_RESULTS_RESP_P = 4'h6,
        TX_PT_WAIT_END_REQ_P      = 4'h7,
        TX_PT_SEND_END_RESP_P     = 4'h8,
        TX_PT_DONE_P              = 4'h9
    } part_fsm_t;

    loc_fsm_t  loc_state;
    part_fsm_t part_state;
    assign loc_state  = loc_fsm_t'(loc_die.current_state);
    assign part_state = part_fsm_t'(part_die.current_state);
    always @(loc_state)  $display("%12t ps [LOCAL  ] FSM = %s", $time, loc_state.name());
    always @(part_state) $display("%12t ps [PARTNER] FSM = %s", $time, part_state.name());

    //======================================================================
    // MB Model — LOCAL die (TX pattern generator model)
    // Counts burst/idle/iter and fires pattern_count_done for 1 cycle.
    //======================================================================
    integer loc_burst=0, loc_idle=0, loc_iter=0;
    reg     loc_done_sent=0;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            loc_mb_tx_pattern_count_done <= 0;
            loc_burst<=0; loc_idle<=0; loc_iter<=0; loc_done_sent<=0;
        end else if (loc_mb_tx_pattern_en_w) begin
            loc_mb_tx_pattern_count_done <= 0;
            if (loc_iter < d2c_iter_count) begin
                if (loc_burst < d2c_burst_count) loc_burst <= loc_burst+1;
                else if (loc_idle < d2c_idle_count) loc_idle <= loc_idle+1;
                else begin loc_iter<=loc_iter+1; loc_burst<=0; loc_idle<=0; end
            end else if (!loc_done_sent) begin
                $display("[%0t] LOCAL TB: pattern done", $time);
                loc_mb_tx_pattern_count_done <= 1;
                loc_done_sent <= 1;
            end
        end else begin
            loc_mb_tx_pattern_count_done <= 0;
            loc_burst<=0; loc_idle<=0; loc_iter<=0; loc_done_sent<=0;
        end
    end

    //======================================================================
    // MB Model — PARTNER die (RX comparison model)
    // Counts burst/idle/iter and fires compare_done for 1 cycle.
    //======================================================================
    integer part_burst_cnt=0, part_idle_cnt=0, part_iter_cnt=0;
    reg     part_compare_done_sent=0;
    reg [15:0] tb_part_perlane_pass=16'hFFFF; // default: all lanes pass
    reg        tb_part_aggr_pass=1'b1;        // default: aggregate pass
    reg        tb_part_val_pass=1'b1;         // default: valid lane pass

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            // part_mb_rx_compare_done <= 0;
            part_burst_cnt<=0; part_idle_cnt<=0; part_iter_cnt<=0;
            part_compare_done_sent <= 0;
        end else if (part_mb_rx_compare_en_w) begin
            // part_mb_rx_compare_done <= 0;
            if (part_iter_cnt < part_mb_rx_iter_count_w) begin
                if (part_burst_cnt < part_mb_rx_burst_count_w) part_burst_cnt <= part_burst_cnt+1;
                else if (part_idle_cnt < part_mb_rx_idle_count_w) part_idle_cnt <= part_idle_cnt+1;
                else begin part_iter_cnt<=part_iter_cnt+1; part_burst_cnt<=0; part_idle_cnt<=0; end
            end else if (!part_compare_done_sent) begin
                $display("[%0t] PARTNER TB: compare done, perlane_pass=%h", $time, tb_part_perlane_pass);
                // part_mb_rx_compare_done <= 1;
                part_mb_rx_perlane_pass <= tb_part_perlane_pass;
                part_mb_rx_aggr_pass    <= tb_part_aggr_pass;
                part_mb_rx_val_pass     <= tb_part_val_pass;
                part_compare_done_sent  <= 1;
            end
        end else begin
            // part_mb_rx_compare_done <= 0;
            part_burst_cnt<=0; part_idle_cnt<=0; part_iter_cnt<=0;
            part_compare_done_sent <= 0;
        end
    end

    //======================================================================
    // Timeout watchdog
    //======================================================================
    integer loc_timeout_cnt=0;
    reg timeout_occurred=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin loc_timeout_cnt<=0; timeout_occurred<=0; end
        else if (loc_state!=TX_PT_IDLE_L && loc_state!=TX_PT_DONE_L) begin
            loc_timeout_cnt <= loc_timeout_cnt+1;
            if (loc_timeout_cnt >= TIMEOUT_LIMIT) timeout_occurred <= 1;
        end else begin loc_timeout_cnt<=0; timeout_occurred<=0; end
    end

    //======================================================================
    // Test infrastructure
    //======================================================================
    integer success_count=0, fail_count=0, test_no=1;

    task automatic reset();
        rst_n=0; tx_pt_en=0; part_tx_pt_en=0; tb_suppress_sb=0;
        cfg_max_err_thresh_perlane=0; cfg_max_err_thresh_aggr=0;
        tb_part_perlane_pass=16'hFFFF; tb_part_aggr_pass=1; tb_part_val_pass=1;
        part_mb_rx_data_lane_mask=3'b011;
        d2c_clk_sampling=0; d2c_pattern_setup=3'b001; d2c_data_pattern_sel=0;
        d2c_val_pattern_sel=0; d2c_pattern_mode=0;
        d2c_burst_count=100; d2c_idle_count=0; d2c_iter_count=1; d2c_compare_setup=0;
        repeat(5) @(posedge lclk); rst_n=1; repeat(2) @(posedge lclk);
        $display("%12t ps: Reset released.", $time);
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

    task automatic start_test(input logic expect_timeout);
        @(posedge lclk); tx_pt_en=1; part_tx_pt_en=1;
        fork : tf
            begin
                wait(loc_test_d2c_done || timeout_occurred);
                @(posedge lclk); tx_pt_en=0; part_tx_pt_en=0;
                if (timeout_occurred) begin
                    if (expect_timeout) begin
                        $display("%12t ps: [PASS] Expected timeout.", $time); success_count++;
                    end else begin
                        $display("%12t ps: [FAIL] Unexpected timeout!", $time); fail_count++; $stop;
                    end
                end else begin
                    if (expect_timeout) begin
                        $display("%12t ps: [FAIL] Expected TO but done!", $time); fail_count++; $stop;
                    end else begin
                        wait(loc_state==TX_PT_IDLE_L);
                        $display("%12t ps: [PASS] Done.", $time); success_count++;
                    end
                end
                $display("(Pass=%0d, Fail=%0d)\n", success_count, fail_count);
                disable tf;
            end
            begin #(64'd5_000_000_000); $display("[FAIL] Watchdog!"); fail_count++; disable tf; end
        join
    endtask

    //======================================================================
    // Signal Verification Tasks
    //======================================================================

    // Check LOCAL die MB TX signals in a given state
    task automatic check_loc_mb_tx_signals(
            input string context_str,
            input logic  exp_pattern_en,
            input logic  exp_lfsr_en,
            input logic  exp_lfsr_rst,
            input logic  exp_clk_sampling_en,
            input [1:0]  exp_trk_sel,
            input [1:0]  exp_clk_sel,
            input [1:0]  exp_val_sel,
            input [1:0]  exp_data_sel
        );
        if (loc_mb_tx_pattern_en_w !== exp_pattern_en) begin
            $display("  [FAIL] %s: mb_tx_pattern_en=%b, expected=%b", context_str, loc_mb_tx_pattern_en_w, exp_pattern_en);
            fail_count++; $stop;
        end
        if (loc_mb_tx_lfsr_en_w !== exp_lfsr_en) begin
            $display("  [FAIL] %s: mb_tx_lfsr_en=%b, expected=%b", context_str, loc_mb_tx_lfsr_en_w, exp_lfsr_en);
            fail_count++; $stop;
        end
        if (loc_mb_tx_lfsr_rst_w !== exp_lfsr_rst) begin
            $display("  [FAIL] %s: mb_tx_lfsr_rst=%b, expected=%b", context_str, loc_mb_tx_lfsr_rst_w, exp_lfsr_rst);
            fail_count++; $stop;
        end
        if (loc_mb_tx_clk_sampling_en_w !== exp_clk_sampling_en) begin
            $display("  [FAIL] %s: mb_tx_clk_sampling_en=%b, expected=%b", context_str, loc_mb_tx_clk_sampling_en_w, exp_clk_sampling_en);
            fail_count++; $stop;
        end
        if (loc_mb_tx_trk_lane_sel_w !== exp_trk_sel) begin
            $display("  [FAIL] %s: mb_tx_trk_lane_sel=%b, expected=%b", context_str, loc_mb_tx_trk_lane_sel_w, exp_trk_sel);
            fail_count++; $stop;
        end
        if (loc_mb_tx_clk_lane_sel_w !== exp_clk_sel) begin
            $display("  [FAIL] %s: mb_tx_clk_lane_sel=%b, expected=%b", context_str, loc_mb_tx_clk_lane_sel_w, exp_clk_sel);
            fail_count++; $stop;
        end
        if (loc_mb_tx_val_lane_sel_w !== exp_val_sel) begin
            $display("  [FAIL] %s: mb_tx_val_lane_sel=%b, expected=%b", context_str, loc_mb_tx_val_lane_sel_w, exp_val_sel);
            fail_count++; $stop;
        end
        if (loc_mb_tx_data_lane_sel_w !== exp_data_sel) begin
            $display("  [FAIL] %s: mb_tx_data_lane_sel=%b, expected=%b", context_str, loc_mb_tx_data_lane_sel_w, exp_data_sel);
            fail_count++; $stop;
        end
    endtask

    // Check LOCAL die TX config pass-through signals
    task automatic check_loc_tx_config_passthrough(input string context_str);
        if (loc_mb_tx_clk_sampling_w !== d2c_clk_sampling) begin
            $display("  [FAIL] %s: mb_tx_clk_sampling=%b, expected=%b", context_str, loc_mb_tx_clk_sampling_w, d2c_clk_sampling);
            fail_count++; $stop;
        end
        if (loc_mb_tx_pattern_setup_w !== d2c_pattern_setup) begin
            $display("  [FAIL] %s: mb_tx_pattern_setup=%b, expected=%b", context_str, loc_mb_tx_pattern_setup_w, d2c_pattern_setup);
            fail_count++; $stop;
        end
        if (loc_mb_tx_pattern_mode_w !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: mb_tx_pattern_mode=%b, expected=%b", context_str, loc_mb_tx_pattern_mode_w, d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (loc_mb_tx_burst_count_w !== d2c_burst_count) begin
            $display("  [FAIL] %s: mb_tx_burst_count=%h, expected=%h", context_str, loc_mb_tx_burst_count_w, d2c_burst_count);
            fail_count++; $stop;
        end
        if (loc_mb_tx_idle_count_w !== d2c_idle_count) begin
            $display("  [FAIL] %s: mb_tx_idle_count=%h, expected=%h", context_str, loc_mb_tx_idle_count_w, d2c_idle_count);
            fail_count++; $stop;
        end
        if (loc_mb_tx_iter_count_w !== d2c_iter_count) begin
            $display("  [FAIL] %s: mb_tx_iter_count=%h, expected=%h", context_str, loc_mb_tx_iter_count_w, d2c_iter_count);
            fail_count++; $stop;
        end
        if (loc_mb_tx_data_pattern_sel_w !== d2c_data_pattern_sel) begin
            $display("  [FAIL] %s: mb_tx_data_pattern_sel=%b, expected=%b", context_str, loc_mb_tx_data_pattern_sel_w, d2c_data_pattern_sel);
            fail_count++; $stop;
        end
        if (loc_mb_tx_val_pattern_sel_w !== d2c_val_pattern_sel) begin
            $display("  [FAIL] %s: mb_tx_val_pattern_sel=%b, expected=%b", context_str, loc_mb_tx_val_pattern_sel_w, d2c_val_pattern_sel);
            fail_count++; $stop;
        end
    endtask

    // Check PARTNER die decoded config from SB data field
    task automatic check_part_decoded_config(input string context_str);
        if (part_mb_rx_iter_count_w !== d2c_iter_count) begin
            $display("  [FAIL] %s: part iter_count=%h, expected=%h", context_str, part_mb_rx_iter_count_w, d2c_iter_count);
            fail_count++; $stop;
        end
        if (part_mb_rx_idle_count_w !== d2c_idle_count) begin
            $display("  [FAIL] %s: part idle_count=%h, expected=%h", context_str, part_mb_rx_idle_count_w, d2c_idle_count);
            fail_count++; $stop;
        end
        if (part_mb_rx_burst_count_w !== d2c_burst_count) begin
            $display("  [FAIL] %s: part burst_count=%h, expected=%h", context_str, part_mb_rx_burst_count_w, d2c_burst_count);
            fail_count++; $stop;
        end
        if (part_mb_rx_pattern_mode_w !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: part pattern_mode=%b, expected=%b", context_str, part_mb_rx_pattern_mode_w, d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (part_mb_rx_data_pattern_sel_w !== d2c_data_pattern_sel) begin
            $display("  [FAIL] %s: part data_pattern_sel=%b, expected=%b", context_str, part_mb_rx_data_pattern_sel_w, d2c_data_pattern_sel);
            fail_count++; $stop;
        end
    endtask

    // Check PARTNER die MB RX lane selection
    task automatic check_part_rx_lane_sel(
            input string context_str,
            input logic  exp_trk,
            input logic  exp_clk,
            input logic  exp_val,
            input logic  exp_data
        );
        if (part_mb_rx_trk_lane_sel_w !== exp_trk) begin
            $display("  [FAIL] %s: mb_rx_trk_lane_sel=%b, expected=%b", context_str, part_mb_rx_trk_lane_sel_w, exp_trk);
            fail_count++; $stop;
        end
        if (part_mb_rx_clk_lane_sel_w !== exp_clk) begin
            $display("  [FAIL] %s: mb_rx_clk_lane_sel=%b, expected=%b", context_str, part_mb_rx_clk_lane_sel_w, exp_clk);
            fail_count++; $stop;
        end
        if (part_mb_rx_val_lane_sel_w !== exp_val) begin
            $display("  [FAIL] %s: mb_rx_val_lane_sel=%b, expected=%b", context_str, part_mb_rx_val_lane_sel_w, exp_val);
            fail_count++; $stop;
        end
        if (part_mb_rx_data_lane_sel_w !== exp_data) begin
            $display("  [FAIL] %s: mb_rx_data_lane_sel=%b, expected=%b", context_str, part_mb_rx_data_lane_sel_w, exp_data);
            fail_count++; $stop;
        end
    endtask

    // Check SB data field encoding for Start REQ message from LOCAL die
    task automatic check_start_req_sb_encoding(input string context_str);
        reg [63:0] cap_data;
        reg [15:0] cap_info;
        wait(loc_tx_sb_valid && loc_tx_sb_msg == Start_Tx_Init_D_to_C_point_test_req);
        @(negedge lclk);
        cap_data = loc_tx_data_field;
        cap_info = loc_tx_msginfo;
        if (cap_data[63:60] !== 4'b0) begin
            $display("  [FAIL] %s: data_field[63:60]=%b, expected=0000", context_str, cap_data[63:60]);
            fail_count++; $stop;
        end
        if (cap_data[59] !== (d2c_compare_setup != 2'd0)) begin
            $display("  [FAIL] %s: data_field[59]=%b, expected=%b", context_str, cap_data[59], (d2c_compare_setup != 2'd0));
            fail_count++; $stop;
        end
        if (cap_data[58:43] !== d2c_iter_count) begin
            $display("  [FAIL] %s: iter_count=%h, expected=%h", context_str, cap_data[58:43], d2c_iter_count);
            fail_count++; $stop;
        end
        if (cap_data[42:27] !== d2c_idle_count) begin
            $display("  [FAIL] %s: idle_count=%h, expected=%h", context_str, cap_data[42:27], d2c_idle_count);
            fail_count++; $stop;
        end
        if (cap_data[26:11] !== d2c_burst_count) begin
            $display("  [FAIL] %s: burst_count=%h, expected=%h", context_str, cap_data[26:11], d2c_burst_count);
            fail_count++; $stop;
        end
        if (cap_data[10] !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: pattern_mode=%b, expected=%b", context_str, cap_data[10], d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (cap_data[9:6] !== {2'b0, d2c_clk_sampling}) begin
            $display("  [FAIL] %s: clk_sampling=%b, expected=%b", context_str, cap_data[9:6], {2'b0, d2c_clk_sampling});
            fail_count++; $stop;
        end
        if (cap_data[5:3] !== {2'b0, d2c_val_pattern_sel}) begin
            $display("  [FAIL] %s: val_pattern=%b, expected=%b", context_str, cap_data[5:3], {2'b0, d2c_val_pattern_sel});
            fail_count++; $stop;
        end
        if (cap_data[2:0] !== {1'b0, d2c_data_pattern_sel}) begin
            $display("  [FAIL] %s: data_pattern=%b, expected=%b", context_str, cap_data[2:0], {1'b0, d2c_data_pattern_sel});
            fail_count++; $stop;
        end
        $display("  [OK] %s: SB Start REQ encoding correct", context_str);
    endtask

    // Check PARTNER results response MsgInfo content
    task automatic check_part_results_resp_msginfo(
            input string context_str,
            input logic  exp_val_pass,
            input logic  exp_data_pass_bit
        );
        reg [15:0] cap_info;
        reg [63:0] cap_data;
        wait(part_tx_sb_valid && part_tx_sb_msg == Tx_Init_D_to_C_results_resp);
        @(negedge lclk);
        cap_info = part_tx_msginfo;
        cap_data = part_tx_data_field;
        if (cap_info[15:6] !== 10'b0) begin
            $display("  [FAIL] %s: msginfo[15:6]=%b, expected=0", context_str, cap_info[15:6]);
            fail_count++; $stop;
        end
        if (cap_info[5] !== exp_val_pass) begin
            $display("  [FAIL] %s: msginfo[5] val_pass=%b, expected=%b", context_str, cap_info[5], exp_val_pass);
            fail_count++; $stop;
        end
        if (cap_info[4] !== exp_data_pass_bit) begin
            $display("  [FAIL] %s: msginfo[4] data_pass=%b, expected=%b", context_str, cap_info[4], exp_data_pass_bit);
            fail_count++; $stop;
        end
        if (cap_info[3:0] !== 4'b0) begin
            $display("  [FAIL] %s: msginfo[3:0]=%b, expected=0", context_str, cap_info[3:0]);
            fail_count++; $stop;
        end
        if (cap_data[63:16] !== 48'b0) begin
            $display("  [FAIL] %s: data_field[63:16]=%h, expected=0", context_str, cap_data[63:16]);
            fail_count++; $stop;
        end
        if (cap_data[15:0] !== tb_part_perlane_pass) begin
            $display("  [FAIL] %s: data_field[15:0]=%h, expected=%h", context_str, cap_data[15:0], tb_part_perlane_pass);
            fail_count++; $stop;
        end
        $display("  [OK] %s: Results RESP MsgInfo verified (val=%b, data_pass=%b)", context_str, exp_val_pass, exp_data_pass_bit);
    endtask

    //======================================================================
    // Comprehensive happy-path verification task (per-state signal checks)
    //======================================================================
    task automatic run_verified_happy_path(input string scenario_name);
        logic exp_lfsr_en;
        logic [1:0] exp_clk_sel, exp_val_sel, exp_data_sel;
        exp_lfsr_en = (d2c_data_pattern_sel == 2'b0 && d2c_pattern_setup[0] == 1'b1);

        // LOCAL: SEND_START_REQ — clk_sampling_en=1, pattern off, all lanes low
        wait(loc_state == TX_PT_SEND_START_REQ_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC SEND_START_REQ", 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 2'b00, 2'b00, 2'b00);
        check_loc_tx_config_passthrough("LOC SEND_START_REQ");
        if (loc_tx_sb_valid !== 1'b1) begin
            $display("  [FAIL] SEND_START_REQ: tx_sb_msg_valid=%b, expected=1", loc_tx_sb_valid);
            fail_count++; $stop;
        end
        if (loc_tx_sb_msg !== Start_Tx_Init_D_to_C_point_test_req) begin
            $display("  [FAIL] SEND_START_REQ: msg=%h", loc_tx_sb_msg); fail_count++; $stop;
        end

        // LOCAL: WAIT_START_RESP — all off, valid=0
        wait(loc_state == TX_PT_WAIT_START_RESP_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC WAIT_START_RESP", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] WAIT_START_RESP: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: SEND_START_RESP — sends resp, RX lanes enabled
        wait(part_state == TX_PT_SEND_START_RESP_P);
        @(negedge lclk);
        if (part_tx_sb_valid !== 1'b1 || part_tx_sb_msg !== Start_Tx_Init_D_to_C_point_test_resp) begin
            $display("  [FAIL] PART SEND_START_RESP: valid=%b msg=%h", part_tx_sb_valid, part_tx_sb_msg);
            fail_count++; $stop;
        end
        check_part_rx_lane_sel("PART SEND_START_RESP", 1'b0, 1'b1, 1'b1, 1'b1);

        // PARTNER: WAIT_CLR_ERR_REQ — compare disabled, SB=0
        wait(part_state == TX_PT_WAIT_CLR_ERR_REQ_P);
        @(negedge lclk);
        check_part_decoded_config("PART after START decode");
        if (part_mb_rx_compare_en_w !== 1'b0) begin
            $display("  [FAIL] PART WAIT_CLR_ERR_REQ: compare_en should be 0"); fail_count++; $stop;
        end
        if (part_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] PART WAIT_CLR_ERR_REQ: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end
        check_part_rx_lane_sel("PART WAIT_CLR_ERR_REQ", 1'b0, 1'b1, 1'b1, 1'b1);

        // LOCAL: SEND_CLR_ERR_REQ — lfsr_rst=1, sends LFSR clear req
        wait(loc_state == TX_PT_SEND_CLR_ERR_REQ_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC SEND_CLR_ERR_REQ", 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b1 || loc_tx_sb_msg !== LFSR_clear_error_req) begin
            $display("  [FAIL] SEND_CLR_ERR_REQ: msg mismatch"); fail_count++; $stop;
        end

        // LOCAL: WAIT_CLR_ERR_RESP — lfsr_rst still 1, SB=0
        wait(loc_state == TX_PT_WAIT_CLR_ERR_RESP_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC WAIT_CLR_ERR_RESP", 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] WAIT_CLR_ERR_RESP: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: SEND_CLR_ERR_RESP — lfsr_rst=1, sends CLR resp
        wait(part_state == TX_PT_SEND_CLR_ERR_RESP_P);
        @(negedge lclk);
        if (part_tx_sb_valid !== 1'b1 || part_tx_sb_msg !== LFSR_clear_error_resp) begin
            $display("  [FAIL] PART SEND_CLR_ERR_RESP: msg mismatch"); fail_count++; $stop;
        end
        if (part_mb_rx_lfsr_rst_w !== 1'b1) begin
            $display("  [FAIL] PART SEND_CLR_ERR_RESP: mb_rx_lfsr_rst should be 1"); fail_count++; $stop;
        end
        check_part_rx_lane_sel("PART SEND_CLR_ERR_RESP", 1'b0, 1'b1, 1'b1, 1'b1);

        // LOCAL: PATTERN_GEN — TX pattern active, correct lane selects
        wait(loc_state == TX_PT_PATTERN_GEN_L);
        @(negedge lclk);
        exp_clk_sel  = d2c_pattern_setup[2] ? 2'b01 : 2'b00;
        exp_val_sel  = d2c_pattern_setup[1] ? 2'b01 : 2'b00;
        exp_data_sel = d2c_pattern_setup[0] ? 2'b01 : 2'b00;
        check_loc_mb_tx_signals("LOC PATTERN_GEN", 1'b1, exp_lfsr_en, 1'b0, 1'b0,
            2'b00, exp_clk_sel, exp_val_sel, exp_data_sel);
        if (loc_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] LOC PATTERN_GEN: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: WAIT_RESULTS_REQ — compare_en=1, lfsr_en matches pattern
        wait(part_state == TX_PT_WAIT_RESULTS_REQ_P);
        @(negedge lclk);
        if (part_mb_rx_compare_en_w !== 1'b1) begin
            $display("  [FAIL] PART WAIT_RESULTS_REQ: compare_en should be 1"); fail_count++; $stop;
        end
        if (part_mb_rx_lfsr_en_w !== exp_lfsr_en) begin
            $display("  [FAIL] PART WAIT_RESULTS_REQ: lfsr_en=%b, expected=%b", part_mb_rx_lfsr_en_w, exp_lfsr_en);
            fail_count++; $stop;
        end
        if (part_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] PART WAIT_RESULTS_REQ: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end
        check_part_rx_lane_sel("PART WAIT_RESULTS_REQ", 1'b0, 1'b1, 1'b1, 1'b1);

        // LOCAL: SEND_RESULTS_REQ
        wait(loc_state == TX_PT_SEND_RESULTS_REQ_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC SEND_RESULTS_REQ", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b1 || loc_tx_sb_msg !== Tx_Init_D_to_C_results_req) begin
            $display("  [FAIL] SEND_RESULTS_REQ: msg mismatch"); fail_count++; $stop;
        end

        // LOCAL: WAIT_RESULTS_RESP
        wait(loc_state == TX_PT_WAIT_RESULTS_RESP_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC WAIT_RESULTS_RESP", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] WAIT_RESULTS_RESP: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: SEND_RESULTS_RESP — sends logged results
        wait(part_state == TX_PT_SEND_RESULTS_RESP_P);
        @(negedge lclk);
        if (part_tx_sb_valid !== 1'b1 || part_tx_sb_msg !== Tx_Init_D_to_C_results_resp) begin
            $display("  [FAIL] PART SEND_RESULTS_RESP: msg mismatch"); fail_count++; $stop;
        end
        if (part_mb_rx_compare_en_w !== 1'b1) begin
            $display("  [FAIL] PART SEND_RESULTS_RESP: compare_en should still be 1 (during send)"); fail_count++; $stop;
        end
        check_part_rx_lane_sel("PART SEND_RESULTS_RESP", 1'b0, 1'b1, 1'b1, 1'b1);

        // LOCAL: SEND_END_REQ
        wait(loc_state == TX_PT_SEND_END_REQ_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC SEND_END_REQ", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b1 || loc_tx_sb_msg !== End_Tx_Init_D_to_C_point_test_req) begin
            $display("  [FAIL] SEND_END_REQ: msg mismatch"); fail_count++; $stop;
        end

        // LOCAL: WAIT_END_RESP
        wait(loc_state == TX_PT_WAIT_END_RESP_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC WAIT_END_RESP", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] WAIT_END_RESP: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: WAIT_END_REQ — compare disabled
        wait(part_state == TX_PT_WAIT_END_REQ_P);
        @(negedge lclk);
        if (part_mb_rx_compare_en_w !== 1'b0) begin
            $display("  [FAIL] PART WAIT_END_REQ: compare_en should be 0 (test phase done)"); fail_count++; $stop;
        end
        if (part_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] PART WAIT_END_REQ: tx_sb_msg_valid should be 0"); fail_count++; $stop;
        end

        // PARTNER: SEND_END_RESP
        wait(part_state == TX_PT_SEND_END_RESP_P);
        @(negedge lclk);
        if (part_tx_sb_valid !== 1'b1 || part_tx_sb_msg !== End_Tx_Init_D_to_C_point_test_resp) begin
            $display("  [FAIL] PART SEND_END_RESP: msg mismatch"); fail_count++; $stop;
        end

        // LOCAL: DONE — test_d2c_done=1, all MB off
        wait(loc_state == TX_PT_DONE_L);
        @(negedge lclk);
        check_loc_mb_tx_signals("LOC DONE", 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 2'b00, 2'b00);
        if (loc_test_d2c_done !== 1'b1) begin
            $display("  [FAIL] LOCAL DONE: test_d2c_done=%b, expected=1", loc_test_d2c_done);
            fail_count++; $stop;
        end

        // PARTNER: DONE — test_d2c_done=1
        wait(part_state == TX_PT_DONE_P);
        @(negedge lclk);
        if (part_test_d2c_done !== 1'b1) begin
            $display("  [FAIL] PARTNER DONE: test_d2c_done=%b, expected=1", part_test_d2c_done);
            fail_count++; $stop;
        end
        if (part_mb_rx_compare_en_w !== 1'b0) begin
            $display("  [FAIL] PARTNER DONE: compare_en should be 0"); fail_count++; $stop;
        end

        $display("  [OK] %s: All per-state signal checks passed", scenario_name);
    endtask

    //======================================================================
    // Main Test Sequence
    //======================================================================
    initial begin
        $display("\n=== unit_TX_D2C_PT Dual-Die Testbench (Comprehensive) ===\n");

        //------------------------------------------------------------------
        // Scenario 1: Happy path — per-lane LFSR, no errors, full signal check
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Happy Path (per-lane LFSR, no errors, FULL signal check)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        fork
            run_verified_happy_path("Scenario 1");
            check_start_req_sb_encoding("Scenario 1");
            check_part_results_resp_msginfo("Scenario 1", 1'b1, 1'b1);
        join_none
        start_test(0);
        // All lanes passed → perlane vector should be all 1s (16'hFFFF, since reset() sets tb_part_perlane_pass=16'hFFFF)
        if (loc_d2c_perlane_pass == 16'hFFFF)
            $display("  MATCH: perlane pass=16'hFFFF (all lanes passed)");
        else begin $display("  FAIL: perlane mismatch %h, expected=FFFF", loc_d2c_perlane_pass); fail_count++; $stop; end
        if (loc_d2c_val_pass == 1'b1)
            $display("  MATCH: d2c_val_pass=1 (partner reported val_pass=1)");

        //------------------------------------------------------------------
        // Scenario 2: Happy path — aggregate mode
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Happy Path (aggregate mode)", test_no++);
        reset();
        cfg_max_err_thresh_aggr = 16'h1000;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd1);
        tb_part_aggr_pass = 1'b1;
        fork
            check_start_req_sb_encoding("Scenario 2");
            check_part_results_resp_msginfo("Scenario 2", 1'b1, 1'b1);
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 3: Timeout — SB suppressed
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Timeout (SB suppressed)", test_no++);
        reset(); tb_suppress_sb=1;
        start_test(1);

        //------------------------------------------------------------------
        // Scenario 4: Partner reports all per-lane failures (0x0000)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Partner All Lanes Fail (perlane_pass=0x0000)", test_no++);
        reset();
        tb_part_perlane_pass = 16'h0000;
        tb_part_aggr_pass    = 1'b0;
        tb_part_val_pass     = 1'b0;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            check_part_results_resp_msginfo("Scenario 4", 1'b0, 1'b0);
        join_none
        start_test(0);
        if (loc_d2c_val_pass == 1'b0)
            $display("  MATCH: val_pass=0 (val_pass=0 from partner)");

        //------------------------------------------------------------------
        // Scenario 5: Partner reports partial per-lane (0xDEAD)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Partner Partial Per-Lane (0xDEAD)", test_no++);
        reset();
        tb_part_perlane_pass = 16'hDEAD;
        tb_part_aggr_pass    = 1'b0;
        tb_part_val_pass     = 1'b1;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            check_part_results_resp_msginfo("Scenario 5", 1'b1, 1'b0);
        join_none
        start_test(0);
        // 16-bit perlane_pass should carry the full vector 16'hDEAD sent by the partner
        if (loc_d2c_perlane_pass == 16'hDEAD)
            $display("  MATCH: d2c_perlane_pass=16'hDEAD (partial per-lane result preserved correctly)");
        else begin $display("  FAIL: perlane mismatch %h, expected=DEAD", loc_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 6: Valid Lane fail
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Valid Lane Fail", test_no++);
        reset();
        tb_part_perlane_pass = 16'hFFFF;
        tb_part_val_pass     = 1'b0;
        set_config(2'b00, 3'b011, 2'b00, 1, 0, 30, 0, 1, 2'd0);
        fork
            check_part_results_resp_msginfo("Scenario 6", 1'b0, 1'b1);
        join_none
        start_test(0);
        if (loc_d2c_val_pass == 1'b0)
            $display("  MATCH: d2c_val_pass=0 (val_pass=0 → no val pass)");

        //------------------------------------------------------------------
        // Scenario 7: Valid Lane pass (val_pass=1)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Valid Lane Pass", test_no++);
        reset();
        tb_part_val_pass = 1'b1;
        set_config(2'b00, 3'b011, 2'b00, 1, 0, 30, 0, 1, 2'd0);
        start_test(0);
        if (loc_d2c_val_pass == 1'b1)
            $display("  MATCH: d2c_val_pass=1 (val_pass=1 from partner)");
        else begin $display("  FAIL: d2c_val_pass should be 1 when val_pass=1"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 8: Burst mode (iter=3, burst=20, idle=10)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Burst Mode (iter=3, burst=20, idle=10)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 1, 20, 10, 3, 2'd0);
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 9: Clock sampling Left Edge
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Clock Sampling Left Edge", test_no++);
        reset();
        set_config(2'b01, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            begin
                wait(loc_state == TX_PT_SEND_START_REQ_L);
                @(negedge lclk);
                if (loc_mb_tx_clk_sampling_w !== 2'b01) begin
                    $display("  [FAIL] clk_sampling=%b, expected=01", loc_mb_tx_clk_sampling_w);
                    fail_count++; $stop;
                end else $display("  [OK] clk_sampling=01 (Left Edge)");
                if (loc_mb_tx_clk_sampling_en_w !== 1'b1) begin
                    $display("  [FAIL] clk_sampling_en=%b, expected=1", loc_mb_tx_clk_sampling_en_w);
                    fail_count++; $stop;
                end else $display("  [OK] clk_sampling_en=1 in SEND_START_REQ");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 10: Clock sampling Right Edge
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Clock Sampling Right Edge", test_no++);
        reset();
        set_config(2'b10, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            begin
                wait(loc_state == TX_PT_SEND_START_REQ_L);
                @(negedge lclk);
                if (loc_mb_tx_clk_sampling_w !== 2'b10) begin
                    $display("  [FAIL] clk_sampling=%b, expected=10", loc_mb_tx_clk_sampling_w);
                    fail_count++; $stop;
                end else $display("  [OK] clk_sampling=10 (Right Edge)");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 11: Per-Lane ID pattern (LFSR disabled everywhere)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Per-Lane ID Pattern (lfsr disabled at TX and RX)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b01, 0, 0, 30, 0, 1, 2'd0);
        fork
            begin
                wait(loc_state == TX_PT_PATTERN_GEN_L);
                @(negedge lclk);
                if (loc_mb_tx_lfsr_en_w !== 1'b0) begin
                    $display("  [FAIL] LOC PATTERN_GEN: lfsr_en=%b, expected=0", loc_mb_tx_lfsr_en_w);
                    fail_count++; $stop;
                end else $display("  [OK] Local TX lfsr_en=0 (Per-Lane ID)");
                wait(part_state == TX_PT_WAIT_RESULTS_REQ_P);
                @(negedge lclk);
                if (part_mb_rx_lfsr_en_w !== 1'b0) begin
                    $display("  [FAIL] PART lfsr_en=%b, expected=0", part_mb_rx_lfsr_en_w);
                    fail_count++; $stop;
                end else $display("  [OK] Partner RX lfsr_en=0 (Per-Lane ID decoded from SB)");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 12: Aggregate MsgInfo threshold encoding
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Aggregate MsgInfo Threshold Encoding", test_no++);
        reset();
        cfg_max_err_thresh_aggr = 16'hABCD;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd1);
        fork
            begin
                wait(loc_tx_sb_valid && loc_tx_sb_msg == Start_Tx_Init_D_to_C_point_test_req);
                @(negedge lclk);
                if (loc_tx_msginfo !== 16'hABCD) begin
                    $display("  [FAIL] MsgInfo=%h, expected=ABCD", loc_tx_msginfo);
                    fail_count++; $stop;
                end else $display("  [OK] MsgInfo=0xABCD (aggregate threshold)");
                if (loc_tx_data_field[59] !== 1'b1) begin
                    $display("  [FAIL] data_field[59]=%b, expected=1 (aggregate)", loc_tx_data_field[59]);
                    fail_count++; $stop;
                end else $display("  [OK] data_field[59]=1 (aggregate mode)");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 13: Per-Lane MsgInfo threshold encoding
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Per-Lane MsgInfo Threshold Encoding", test_no++);
        reset();
        cfg_max_err_thresh_perlane = 12'hABC;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        fork
            begin
                wait(loc_tx_sb_valid && loc_tx_sb_msg == Start_Tx_Init_D_to_C_point_test_req);
                @(negedge lclk);
                if (loc_tx_msginfo !== {4'b0, 12'hABC}) begin
                    $display("  [FAIL] MsgInfo=%h, expected=0ABC", loc_tx_msginfo);
                    fail_count++; $stop;
                end else $display("  [OK] MsgInfo=0x0ABC (per-lane threshold)");
                if (loc_tx_data_field[59] !== 1'b0) begin
                    $display("  [FAIL] data_field[59]=%b, expected=0 (per-lane)", loc_tx_data_field[59]);
                    fail_count++; $stop;
                end else $display("  [OK] data_field[59]=0 (per-lane mode)");
            end
        join_none
        start_test(0);
        if (part_mb_rx_max_err_thresh_perlane_w === 12'hABC)
            $display("  MATCH: partner decoded perlane_thresh=0xABC");
        else begin $display("  FAIL: partner perlane_thresh=%h, expected=0ABC", part_mb_rx_max_err_thresh_perlane_w); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 14: Partner compare_setup decoded (per-lane→00)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Partner compare_setup decoded (per-lane→00)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        start_test(0);
        if (part_mb_rx_compare_setup_w === 2'b00)
            $display("  MATCH: part compare_setup=00 (per-lane)");
        else begin $display("  FAIL: compare_setup=%b expected=00", part_mb_rx_compare_setup_w); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 15: Partner compare_setup decoded (aggregate→01)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Partner compare_setup decoded (aggregate→01)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd1);
        start_test(0);
        if (part_mb_rx_compare_setup_w === 2'b01)
            $display("  MATCH: part compare_setup=01 (aggregate)");
        else begin $display("  FAIL: compare_setup=%b expected=01", part_mb_rx_compare_setup_w); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 16: Data lane mask 001 (Lanes 0-7)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Data Lane Mask 001 (Lanes 0-7)", test_no++);
        reset();
        part_mb_rx_data_lane_mask = 3'b001;
        tb_part_perlane_pass      = 16'h00FF;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        start_test(0);
        // 16-bit perlane_pass should carry the full vector 16'h00FF (only lanes 0-7 pass)
        if (loc_d2c_perlane_pass == 16'h00FF)
            $display("  MATCH: perlane_pass=16'h00FF (lower 8 lanes pass, upper 8 fail)");
        else begin $display("  FAIL: perlane=%h, expected=00FF", loc_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 17: Clock pattern only (pattern_setup=100)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Clock Pattern Only (pattern_setup=100)", test_no++);
        reset();
        set_config(2'b00, 3'b100, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        fork
            begin
                wait(loc_state == TX_PT_PATTERN_GEN_L);
                @(negedge lclk);
                if (loc_mb_tx_clk_lane_sel_w !== 2'b01) begin
                    $display("  [FAIL] clk_lane_sel=%b, expected=01", loc_mb_tx_clk_lane_sel_w);
                    fail_count++; $stop;
                end
                if (loc_mb_tx_data_lane_sel_w !== 2'b00) begin
                    $display("  [FAIL] data_lane_sel=%b, expected=00 (clock only)", loc_mb_tx_data_lane_sel_w);
                    fail_count++; $stop;
                end
                if (loc_mb_tx_val_lane_sel_w !== 2'b00) begin
                    $display("  [FAIL] val_lane_sel=%b, expected=00 (clock only)", loc_mb_tx_val_lane_sel_w);
                    fail_count++; $stop;
                end
                $display("  [OK] Clock-only pattern: clk=01, data=00, val=00");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 18: Back-to-back #1
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Back-to-Back Test #1", test_no++);
        tb_part_perlane_pass = 16'h1111;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0);
        // 16-bit perlane_pass should carry the full vector 16'h1111
        if (loc_d2c_perlane_pass == 16'h1111)
            $display("  MATCH: B2B #1 perlane=16'h1111");
        else begin $display("  FAIL: B2B #1 perlane=%h, expected=1111", loc_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 19: Back-to-back #2
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Back-to-Back Test #2", test_no++);
        tb_part_perlane_pass = 16'h2222;
        set_config(2'b10, 3'b001, 2'b01, 0, 0, 5, 0, 2, 2'd0);
        start_test(0);
        // 16-bit perlane_pass should carry the full vector 16'h2222
        if (loc_d2c_perlane_pass == 16'h2222)
            $display("  MATCH: B2B #2 perlane=16'h2222");
        else begin $display("  FAIL: B2B #2 perlane=%h, expected=2222", loc_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 20: Large iter count (iter=8)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Large Iter Count (iter=8)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 8, 2'd0);
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 21: All patterns enabled (pattern_setup=111)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: All Patterns Enabled (pattern_setup=111)", test_no++);
        reset();
        set_config(2'b00, 3'b111, 2'b00, 1, 0, 20, 0, 1, 2'd0);
        fork
            begin
                wait(loc_state == TX_PT_PATTERN_GEN_L);
                @(negedge lclk);
                if (loc_mb_tx_clk_lane_sel_w !== 2'b01) begin
                    $display("  [FAIL] all pattern: clk_sel=%b, expected=01", loc_mb_tx_clk_lane_sel_w);
                    fail_count++; $stop;
                end
                if (loc_mb_tx_data_lane_sel_w !== 2'b01) begin
                    $display("  [FAIL] all pattern: data_sel=%b, expected=01", loc_mb_tx_data_lane_sel_w);
                    fail_count++; $stop;
                end
                if (loc_mb_tx_val_lane_sel_w !== 2'b01) begin
                    $display("  [FAIL] all pattern: val_sel=%b, expected=01", loc_mb_tx_val_lane_sel_w);
                    fail_count++; $stop;
                end
                $display("  [OK] All patterns: clk=01, data=01, val=01");
            end
        join_none
        start_test(0);

        // ============== Happy path summary ==============
        $display("\n--- Happy Path Scenarios Complete: Pass=%0d, Fail=%0d ---\n", success_count, fail_count);
        if (fail_count > 0) begin
            $display("[STOP] Fix happy path failures before running randomized tests.");
            $stop;
        end

        //------------------------------------------------------------------
        // 200 Randomized Iterations
        //------------------------------------------------------------------
        $display("\nStarting 200 Randomized Iterations...\n");
        for (int r=0; r<200; r++) begin
            $display("=> Scenario %0d: Randomized [%0d/200]", test_no++, r+1);
            reset();
            tb_part_perlane_pass       = $urandom();
            tb_part_aggr_pass          = $urandom_range(0,1);
            tb_part_val_pass           = $urandom_range(0,1);
            cfg_max_err_thresh_perlane = $urandom() & 12'hFFF;
            cfg_max_err_thresh_aggr    = $urandom();
            tb_suppress_sb = ($urandom_range(0,9)==0); // 10% timeout
            set_config(
                $urandom_range(0,2), $urandom_range(0,7),
                $urandom_range(0,2), $urandom_range(0,1),
                $urandom_range(0,1), $urandom_range(1,100), $urandom_range(0,50),
                $urandom_range(1,8), $urandom_range(0,3)
            );
            start_test(tb_suppress_sb);
            if (!tb_suppress_sb) begin
                // partner sends perlane_pass in tx_data_field[15:0], local stores as d2c_perlane_pass [15:0] (full 16-bit vector)
                if (loc_d2c_perlane_pass !== tb_part_perlane_pass) begin
                    $display("  [FAIL] Random: d2c_perlane_pass=%h, expected=%h",
                        loc_d2c_perlane_pass, tb_part_perlane_pass);
                    fail_count++; $stop;
                end
                // partner sends val_pass in tx_msginfo[5], local stores as d2c_val_pass
                if (loc_d2c_val_pass !== tb_part_val_pass) begin
                    $display("  [FAIL] Random: d2c_val_pass=%b, expected=%b",
                        loc_d2c_val_pass, tb_part_val_pass);
                    fail_count++; $stop;
                end
                // partner sends aggr_pass in tx_msginfo[4], local stores as d2c_aggr_pass (1-bit)
                begin
                    logic [15:0] neg_lanes;
                    logic        exp_aggr_pass;
                    case (part_mb_rx_data_lane_mask)
                        3'b000:  neg_lanes = 16'h0000;
                        3'b001:  neg_lanes = 16'h00FF;
                        3'b010:  neg_lanes = 16'hFF00;
                        3'b011:  neg_lanes = 16'hFFFF;
                        3'b100:  neg_lanes = 16'h000F;
                        3'b101:  neg_lanes = 16'h00F0;
                        default: neg_lanes = 16'h0000;
                    endcase
                    exp_aggr_pass = (d2c_compare_setup != 2'b00) ? tb_part_aggr_pass :
                        (&(tb_part_perlane_pass | ~neg_lanes));
                    if (loc_d2c_aggr_pass !== exp_aggr_pass) begin  // 1-bit comparison (no [0] subscript needed)
                        $display("  [FAIL] Random: d2c_aggr_pass=%b, expected=%b",
                            loc_d2c_aggr_pass, exp_aggr_pass);
                        fail_count++; $stop;
                    end
                end
            end
        end

        //------------------------------------------------------------------
        // Final Summary
        //------------------------------------------------------------------
        if (fail_count==0) begin
            $display("\n  ============================================");
            $display("  ==  Congratulations! All Tests PASSED!  ==");
            $display("  ============================================\n");
        end else begin
            $display("\n  ============================================");
            $display("  ==   FAILED: %0d test(s) had errors!    ==", fail_count);
            $display("  ============================================\n");
        end
        $display("Total: Pass=%0d, Fail=%0d", success_count, fail_count);
        $stop;
    end

endmodule





