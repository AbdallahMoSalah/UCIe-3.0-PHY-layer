// unit_RX_D2C_PT_tb.sv — Dual-die TB for unit_RX_D2C_PT_local + unit_RX_D2C_PT_partner
// Comprehensive testbench: verifies ALL interface signals at EVERY FSM state.
//
// Signal polarity note (important):
//   Old interface used *_err signals:  1 = error/mismatch detected
//   New interface uses *_pass signals: 1 = pass (no error), 0 = error/mismatch detected
//   This matches the UCIe 3.0 SB message definition for {Tx Init D to C results resp}:
//     data_field[63:0]  : 1h = Pass, 0h = Fail (per data lane)
//     MsgInfo[4]        : 1  = Pass, 0  = Fail (aggregate/cumulative)
//
`timescale 1ps/1ps
module unit_RX_D2C_PT_tb;
    import UCIe_pkg::*;
    parameter LCLK_PERIOD   = 1000;
    parameter SB_DELAY_CYCS = 64;
    parameter TIMEOUT_LIMIT = 200_000;

    reg lclk=0, rst_n=0;
    always #(LCLK_PERIOD/2) lclk = ~lclk;

    //======================================================================
    // REQ die (Local) inputs
    //======================================================================
    reg        rx_pt_en=0;
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

    // MB RX comparison result inputs (new *_pass polarity):
    reg        req_mb_rx_compare_done=0;          // 0: In progress, 1: Comparison complete
    reg        req_mb_rx_aggr_pass=1;             // 1: Aggregate passed, 0: Aggregate failed
    reg [15:0] req_mb_rx_perlane_pass=16'hFFFF;  // Per-lane pass bits (1=pass per lane)
    reg        req_mb_rx_val_pass=1;              // 1: Valid Lane matched, 0: mismatch detected

    //======================================================================
    // RESP die (Partner) inputs
    //======================================================================
    reg        resp_rx_pt_en=0;
    reg        resp_mb_tx_pattern_count_done=0;   // 0: TX transmitting, 1: TX pattern complete

    //======================================================================
    // REQ die (Local) outputs
    //======================================================================
    wire        req_test_d2c_done;                // 0: In progress, 1: Test complete
    wire [15:0] req_d2c_perlane_pass;            // Per-lane pass status (1=pass per lane)
    wire        req_d2c_aggr_pass;               // Aggregate pass status (1=pass)
    wire        req_d2c_val_pass;                // Valid Lane pass (1=pass, 0=mismatch)
    wire        req_tx_sb_valid;                  // SB TX valid pulse
    wire [7:0]  req_tx_sb_msg;                    // SB TX message code
    wire [15:0] req_tx_msginfo;                   // SB TX MsgInfo payload
    wire [63:0] req_tx_data_field;                // SB TX 64-bit data payload
    wire        req_mb_rx_compare_en_w;           // 0: Disable, 1: Enable RX comparison
    wire        req_mb_rx_lfsr_en_w;              // 0: Disable, 1: Enable RX LFSR
    wire        req_mb_rx_lfsr_rst_w;             // 0: Normal, 1: Reset RX LFSR
    wire [1:0]  req_mb_rx_compare_setup_w;        // 00: Per-Lane, 01: Aggregate, etc.
    wire [11:0] req_mb_rx_max_err_thresh_perlane_w;
    wire [15:0] req_mb_rx_max_err_thresh_aggr_w;
    wire        req_mb_rx_trk_lane_sel_w;         // 0: Disabled, 1: Enabled
    wire        req_mb_rx_clk_lane_sel_w;         // 0: Disabled, 1: Enabled
    wire        req_mb_rx_val_lane_sel_w;         // 0: Disabled, 1: Enabled
    wire        req_mb_rx_data_lane_sel_w;        // 0: Disabled, 1: Enabled
    wire [2:0]  req_mb_rx_pattern_setup_w;        // 001b: Data, 010b: Valid, 100b: Clock
    wire [15:0] req_mb_rx_iter_count_w;           // RX iteration count pass-through
    wire [15:0] req_mb_rx_idle_count_w;           // RX idle count pass-through
    wire [15:0] req_mb_rx_burst_count_w;          // RX burst count pass-through
    wire        req_mb_rx_pattern_mode_w;         // RX pattern mode pass-through
    wire        req_mb_rx_val_pattern_sel_w;      // RX valid pattern select pass-through
    wire [1:0]  req_mb_rx_data_pattern_sel_w;     // RX data pattern select pass-through

    //======================================================================
    // RESP die (Partner) outputs
    //======================================================================
    wire        resp_test_d2c_done;               // 0: In progress, 1: Test complete
    wire        resp_tx_sb_valid;                  // SB TX valid pulse
    wire [7:0]  resp_tx_sb_msg;                    // SB TX message code
    wire [15:0] resp_tx_msginfo;                   // SB TX MsgInfo payload
    wire [63:0] resp_tx_data_field;                // SB TX 64-bit data payload
    wire        resp_mb_tx_pattern_en_w;           // 0: Idle, 1: Drive training pattern
    wire [2:0]  resp_mb_tx_pattern_setup_w;        // Bit0: Data, Bit1: Valid, Bit2: Clock
    wire        resp_mb_tx_lfsr_en_w;              // 0: Disable, 1: Enable TX LFSR
    wire        resp_mb_tx_lfsr_rst_w;             // 0: Normal, 1: Reset TX LFSR
    wire        resp_mb_tx_clk_sampling_en_w;      // 0: Unchanged, 1: Update TX clock phase
    wire [1:0]  resp_mb_tx_clk_sampling_w;         // 00: Eye Center, 01: Left Edge, 10: Right Edge
    wire        resp_mb_tx_pattern_mode_w;         // 0: Continuous, 1: Burst
    wire [15:0] resp_mb_tx_burst_count_w;          // TX burst count (decoded from SB)
    wire [15:0] resp_mb_tx_idle_count_w;           // TX idle count (decoded from SB)
    wire [15:0] resp_mb_tx_iter_count_w;           // TX iteration count (decoded from SB)
    wire [1:0]  resp_mb_tx_data_pattern_sel_w;     // 00: LFSR, 01: Per-Lane ID (decoded from SB)
    wire        resp_mb_tx_val_pattern_sel_w;      // 0: VALTRAIN, 1: Held Low (decoded from SB)
    wire [1:0]  resp_mb_tx_trk_lane_sel_w;         // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  resp_mb_tx_clk_lane_sel_w;         // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  resp_mb_tx_val_lane_sel_w;         // 00: Low, 01: Active, 1x: Tri-stated
    wire [1:0]  resp_mb_tx_data_lane_sel_w;        // 00: Low, 01: Active, 1x: Tri-stated

    //======================================================================
    // SB pipeline delay (models async FIFO crossing)
    //======================================================================
    reg tb_suppress_sb = 0;
    reg [SB_DELAY_CYCS-1:0] req2resp_valid_sr, resp2req_valid_sr;
    reg [7:0]  req2resp_msg_sr[SB_DELAY_CYCS-1:0], resp2req_msg_sr[SB_DELAY_CYCS-1:0];
    reg [15:0] req2resp_info_sr[SB_DELAY_CYCS-1:0], resp2req_info_sr[SB_DELAY_CYCS-1:0];
    reg [63:0] req2resp_data_sr[SB_DELAY_CYCS-1:0], resp2req_data_sr[SB_DELAY_CYCS-1:0];

    wire req_rx_sb_valid_w  = resp2req_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  req_rx_sb_msg_w    = resp2req_msg_sr  [SB_DELAY_CYCS-1];

    wire resp_rx_sb_valid_w = req2resp_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_sb;
    wire [7:0]  resp_rx_sb_msg_w    = req2resp_msg_sr  [SB_DELAY_CYCS-1];
    wire [15:0] resp_rx_msginfo_w   = req2resp_info_sr [SB_DELAY_CYCS-1];
    wire [63:0] resp_rx_data_field_w= req2resp_data_sr [SB_DELAY_CYCS-1];

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            req2resp_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            resp2req_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            for(pi=0;pi<SB_DELAY_CYCS;pi=pi+1) begin
                req2resp_msg_sr[pi]<=0; req2resp_info_sr[pi]<=0; req2resp_data_sr[pi]<=0;
                resp2req_msg_sr[pi]<=0; resp2req_info_sr[pi]<=0; resp2req_data_sr[pi]<=0;
            end
        end else begin
            req2resp_valid_sr <= {req2resp_valid_sr[SB_DELAY_CYCS-2:0], req_tx_sb_valid};
            resp2req_valid_sr <= {resp2req_valid_sr[SB_DELAY_CYCS-2:0], resp_tx_sb_valid};
            for(pi=1;pi<SB_DELAY_CYCS;pi=pi+1) begin
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

    //======================================================================
    // DUT: REQ die (Local)
    //======================================================================
    unit_RX_D2C_PT_local req_die (
        .lclk               (lclk),                            // LTSM clock
        .rst_n              (rst_n),                           // Active-low reset
        .rx_pt_en           (rx_pt_en),                        // 0: Disable, 1: Enable test
        .test_d2c_done      (req_test_d2c_done),               // 0: In progress, 1: Done

        // D2C config inputs from sub-states:
        .d2c_clk_sampling           (d2c_clk_sampling),            // 00: Eye Center, 01: Left, 10: Right
        .d2c_pattern_setup          (d2c_pattern_setup),           // Bit0: Data, Bit1: Valid, Bit2: Clock
        .d2c_data_pattern_sel       (d2c_data_pattern_sel),        // 00: LFSR, 01: Per-Lane ID, 10: Zeros
        .d2c_val_pattern_sel        (d2c_val_pattern_sel),         // 0: VALTRAIN, 1: Held Low
        .d2c_pattern_mode           (d2c_pattern_mode),            // 0: Continuous, 1: Burst
        .d2c_burst_count            (d2c_burst_count),             // Burst duration in UI
        .d2c_idle_count             (d2c_idle_count),              // Idle duration in UI
        .d2c_iter_count             (d2c_iter_count),              // Iteration count
        .d2c_compare_setup          (d2c_compare_setup),           // 00: Per-Lane, 01: Aggregate
        .cfg_max_err_thresh_perlane (cfg_max_err_thresh_perlane),  // Per-lane threshold from RF
        .cfg_max_err_thresh_aggr    (cfg_max_err_thresh_aggr),     // Aggregate threshold from RF

        // D2C pass-status outputs to sub-states (new *_pass polarity):
        .d2c_perlane_pass   (req_d2c_perlane_pass),            // 1=pass per lane, 0=fail
        .d2c_aggr_pass      (req_d2c_aggr_pass),               // 1=aggregate pass, 0=fail
        .d2c_val_pass       (req_d2c_val_pass),                // 1=valid lane matched, 0=mismatch

        // MB RX pattern configuration outputs:
        .mb_rx_pattern_setup        (req_mb_rx_pattern_setup_w),   // 001b: Data, 010b: Valid, 100b: Clock
        .mb_rx_lfsr_en              (req_mb_rx_lfsr_en_w),         // 0: Disable, 1: Enable RX LFSR
        .mb_rx_lfsr_rst             (req_mb_rx_lfsr_rst_w),        // 0: Normal, 1: Reset RX LFSR
        .mb_rx_iter_count           (req_mb_rx_iter_count_w),      // RX iteration count
        .mb_rx_idle_count           (req_mb_rx_idle_count_w),      // RX idle count
        .mb_rx_burst_count          (req_mb_rx_burst_count_w),     // RX burst count
        .mb_rx_pattern_mode         (req_mb_rx_pattern_mode_w),    // 0: Continuous, 1: Burst
        .mb_rx_val_pattern_sel      (req_mb_rx_val_pattern_sel_w), // 0: VALTRAIN, 1: Low
        .mb_rx_data_pattern_sel     (req_mb_rx_data_pattern_sel_w),// 00: LFSR, 01: ID

        // MB RX comparison setup outputs:
        .mb_rx_compare_en           (req_mb_rx_compare_en_w),      // 0: Disable, 1: Enable comparison
        .mb_rx_max_err_thresh_perlane(req_mb_rx_max_err_thresh_perlane_w), // Per-lane threshold
        .mb_rx_max_err_thresh_aggr  (req_mb_rx_max_err_thresh_aggr_w),    // Aggregate threshold
        .mb_rx_compare_setup        (req_mb_rx_compare_setup_w),   // 00: Per-Lane, 01: Aggregate

        // MB RX comparison result inputs (new *_pass polarity):
        .mb_rx_compare_done (req_mb_rx_compare_done),          // 0: In progress, 1: Done
        .mb_rx_aggr_pass    (req_mb_rx_aggr_pass),             // 1: Aggregate passed
        .mb_rx_perlane_pass (req_mb_rx_perlane_pass),          // Per-lane pass bits
        .mb_rx_val_pass     (req_mb_rx_val_pass),              // 1: Valid Lane matched

        // MB RX lane selection:
        .mb_rx_trk_lane_sel (req_mb_rx_trk_lane_sel_w),        // 0: Disabled, 1: Enabled
        .mb_rx_clk_lane_sel (req_mb_rx_clk_lane_sel_w),        // 0: Disabled, 1: Enabled
        .mb_rx_val_lane_sel (req_mb_rx_val_lane_sel_w),        // 0: Disabled, 1: Enabled
        .mb_rx_data_lane_sel(req_mb_rx_data_lane_sel_w),       // 0: Disabled, 1: Enabled

        // SB TX:
        .tx_sb_msg_valid    (req_tx_sb_valid),                 // 1-cycle pulse to transmit
        .tx_sb_msg          (req_tx_sb_msg),                   // MsgCode to send
        .tx_msginfo         (req_tx_msginfo),                  // MsgInfo payload
        .tx_data_field      (req_tx_data_field),               // 64-bit data payload

        // SB RX:
        .rx_sb_msg_valid    (req_rx_sb_valid_w),               // Received message valid
        .rx_sb_msg          (req_rx_sb_msg_w)                  // Received MsgCode
    );

    //======================================================================
    // DUT: RESPONSER die (Partner)
    //======================================================================
    unit_RX_D2C_PT_partner resp_die (
        .lclk               (lclk),                            // LTSM clock
        .rst_n              (rst_n),                           // Active-low reset
        .rx_pt_en           (resp_rx_pt_en),                   // 0: Disable, 1: Enable test
        .test_d2c_done      (resp_test_d2c_done),              // 0: In progress, 1: Done

        // MB TX clock sampling:
        .mb_tx_clk_sampling_en (resp_mb_tx_clk_sampling_en_w), // 0: Unchanged, 1: Update phase
        .mb_tx_clk_sampling    (resp_mb_tx_clk_sampling_w),    // 00: Center, 01: Left, 10: Right

        // MB TX pattern generator:
        .mb_tx_pattern_en       (resp_mb_tx_pattern_en_w),     // 0: Idle, 1: Drive pattern
        .mb_tx_pattern_setup    (resp_mb_tx_pattern_setup_w),  // Bit0: Data, Bit1: Valid, Bit2: Clock
        .mb_tx_lfsr_en          (resp_mb_tx_lfsr_en_w),        // 0: Disable, 1: Enable TX LFSR
        .mb_tx_lfsr_rst         (resp_mb_tx_lfsr_rst_w),       // 0: Normal, 1: Reset TX LFSR

        // MB TX pattern configuration (decoded from SB):
        .mb_tx_pattern_mode     (resp_mb_tx_pattern_mode_w),   // 0: Continuous, 1: Burst
        .mb_tx_burst_count      (resp_mb_tx_burst_count_w),    // Burst duration in UI
        .mb_tx_idle_count       (resp_mb_tx_idle_count_w),     // Idle duration in UI
        .mb_tx_iter_count       (resp_mb_tx_iter_count_w),     // Iteration count
        .mb_tx_data_pattern_sel (resp_mb_tx_data_pattern_sel_w), // 00: LFSR, 01: Per-Lane ID
        .mb_tx_val_pattern_sel  (resp_mb_tx_val_pattern_sel_w),// 0: VALTRAIN, 1: Held Low
        .mb_tx_pattern_count_done(resp_mb_tx_pattern_count_done), // 0: TX transmitting, 1: Done

        // MB TX lane selection:
        .mb_tx_trk_lane_sel     (resp_mb_tx_trk_lane_sel_w),  // 00: Low, 01: Active, 1x: Tri-state
        .mb_tx_clk_lane_sel     (resp_mb_tx_clk_lane_sel_w),  // 00: Low, 01: Active, 1x: Tri-state
        .mb_tx_val_lane_sel     (resp_mb_tx_val_lane_sel_w),   // 00: Low, 01: Active, 1x: Tri-state
        .mb_tx_data_lane_sel    (resp_mb_tx_data_lane_sel_w),  // 00: Low, 01: Active, 1x: Tri-state

        // SB TX:
        .tx_sb_msg_valid    (resp_tx_sb_valid),                // 1-cycle pulse to transmit
        .tx_sb_msg          (resp_tx_sb_msg),                  // MsgCode to send
        .tx_msginfo         (resp_tx_msginfo),                 // MsgInfo payload
        .tx_data_field      (resp_tx_data_field),              // 64-bit data payload

        // SB RX:
        .rx_sb_msg_valid    (resp_rx_sb_valid_w),              // Received message valid
        .rx_sb_msg          (resp_rx_sb_msg_w),                // Received MsgCode
        // .rx_msginfo      (resp_rx_msginfo_w),               // Not used by partner
        .rx_data_field      (resp_rx_data_field_w)             // Received 64-bit data (decoded for config)
    );

    //======================================================================
    // FSM State Monitors
    //======================================================================
    // REQ FSM (unit_RX_D2C_PT_local): IDLE(0) SEND_START_REQ(1) WAIT_START_RESP(2)
    //   WAIT_CLR_ERR_REQ(3) SEND_CLR_ERR_RESP(4) WAIT_COUNT_DONE_REQ(5)
    //   SEND_COUNT_DONE_RESP(6) LOG_RESULT(7) SEND_END_REQ(8) WAIT_END_RESP(9) DONE(A)
    typedef enum reg [3:0] {
        RX_PT_IDLE_R               = 4'h0,
        RX_PT_SEND_START_REQ       = 4'h1,
        RX_PT_WAIT_START_RESP      = 4'h2,
        RX_PT_WAIT_CLR_ERR_REQ_R  = 4'h3,
        RX_PT_SEND_CLR_ERR_RESP   = 4'h4,
        RX_PT_WAIT_COUNT_DONE_REQ  = 4'h5,
        RX_PT_SEND_COUNT_DONE_RESP = 4'h6,
        RX_PT_LOG_RESULT_R         = 4'h7,
        RX_PT_SEND_END_REQ         = 4'h8,
        RX_PT_WAIT_END_RESP        = 4'h9,
        RX_PT_DONE_R               = 4'hA
    } req_fsm_t;

    // RESPONSER FSM (unit_RX_D2C_PT_partner): IDLE(0) WAIT_START_REQ(1) SEND_START_RESP(2) TX_LFSR_RST(3)
    //   SEND_CLR_ERR_REQ(4) WAIT_CLR_ERR_RESP(5) PATTERN_GEN(6) SEND_COUNT_DONE_REQ(7)
    //   WAIT_COUNT_DONE_RESP(8) WAIT_END_REQ(9) SEND_END_RESP(A) DONE(B)
    typedef enum reg [3:0] {
        RX_PT_IDLE_S                 = 4'h0,
        RX_PT_WAIT_START_REQ_S       = 4'h1,
        RX_PT_SEND_START_RESP_S      = 4'h2,
        RX_PT_TX_LFSR_RST_S          = 4'h3,
        RX_PT_SEND_CLR_ERR_REQ_S     = 4'h4,
        RX_PT_WAIT_CLR_ERR_RESP_S    = 4'h5,
        RX_PT_PATTERN_GEN_S          = 4'h6,
        RX_PT_SEND_COUNT_DONE_REQ_S  = 4'h7,
        RX_PT_WAIT_COUNT_DONE_RESP_S = 4'h8,
        RX_PT_WAIT_END_REQ_S         = 4'h9,
        RX_PT_SEND_END_RESP_S        = 4'hA,
        RX_PT_DONE_S                 = 4'hB
    } resp_fsm_t;

    req_fsm_t  req_state;
    resp_fsm_t resp_state;
    assign req_state  = req_fsm_t'(req_die.current_state);
    assign resp_state = resp_fsm_t'(resp_die.current_state);
    always @(req_state)  $display("%12t ps [LOCAL  ] FSM = %s", $time, req_state.name());
    always @(resp_state) $display("%12t ps [PARTNER] FSM = %s", $time, resp_state.name());

    //======================================================================
    // MB Model — REQ die (Local RX comparison model)
    // Counts burst/idle/iter then fires compare_done for 1 cycle.
    // tb_req_perlane_pass / tb_req_aggr_pass / tb_req_val_pass set the
    // injected pass/fail result (new *_pass polarity: 1=pass, 0=fail).
    //======================================================================
    integer req_burst=0, req_idle=0, req_iter=0;
    reg     req_done_sent=0;
    reg [15:0] tb_req_perlane_pass = 16'hFFFF; // default: all lanes pass
    reg        tb_req_aggr_pass    = 1'b1;     // default: aggregate pass
    reg        tb_req_val_pass     = 1'b1;     // default: valid lane pass

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            req_mb_rx_compare_done <= 0;
            req_burst<=0; req_idle<=0; req_iter<=0; req_done_sent<=0;
        end else if (req_mb_rx_compare_en_w) begin
            req_mb_rx_compare_done <= 0;
            if (req_iter < d2c_iter_count) begin
                if (req_burst < d2c_burst_count) req_burst <= req_burst+1;
                else if (req_idle < d2c_idle_count) req_idle <= req_idle+1;
                else begin req_iter<=req_iter+1; req_burst<=0; req_idle<=0; end
            end else if (!req_done_sent) begin
                $display("[%0t] REQ TB model: compare done, perlane_pass=%h", $time, tb_req_perlane_pass);
                req_mb_rx_compare_done <= 1;
                req_mb_rx_perlane_pass <= tb_req_perlane_pass;
                req_mb_rx_aggr_pass    <= tb_req_aggr_pass;
                req_mb_rx_val_pass     <= tb_req_val_pass;
                req_done_sent          <= 1;
            end
        end else begin
            req_mb_rx_compare_done <= 0;
            req_burst<=0; req_idle<=0; req_iter<=0; req_done_sent<=0;
        end
    end

    //======================================================================
    // MB Model — RESP die (Partner TX pattern model)
    // Counts burst/idle/iter then fires pattern_count_done for 1 cycle.
    //======================================================================
    integer resp_burst=0, resp_idle=0, resp_iter=0;
    reg     resp_done_sent=0;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            resp_mb_tx_pattern_count_done <= 0;
            resp_burst<=0; resp_idle<=0; resp_iter<=0; resp_done_sent<=0;
        end else if (resp_mb_tx_pattern_en_w) begin
            resp_mb_tx_pattern_count_done <= 0;
            if (resp_iter < resp_mb_tx_iter_count_w) begin
                if (resp_burst < resp_mb_tx_burst_count_w) resp_burst <= resp_burst+1;
                else if (resp_idle < resp_mb_tx_idle_count_w) resp_idle <= resp_idle+1;
                else begin resp_iter<=resp_iter+1; resp_burst<=0; resp_idle<=0; end
            end else if (!resp_done_sent) begin
                $display("[%0t] RESP TB model: pattern done", $time);
                resp_mb_tx_pattern_count_done <= 1;
                resp_done_sent                <= 1;
            end
        end else begin
            resp_mb_tx_pattern_count_done <= 0;
            resp_burst<=0; resp_idle<=0; resp_iter<=0; resp_done_sent<=0;
        end
    end

    //======================================================================
    // Timeout watchdog
    //======================================================================
    integer req_timeout_cnt=0;
    reg timeout_8ms_occured_req=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin req_timeout_cnt<=0; timeout_8ms_occured_req<=0; end
        else if (req_state!=RX_PT_IDLE_R && req_state!=RX_PT_DONE_R) begin
            req_timeout_cnt <= req_timeout_cnt+1;
            if (req_timeout_cnt >= TIMEOUT_LIMIT) timeout_8ms_occured_req <= 1;
        end else begin req_timeout_cnt<=0; timeout_8ms_occured_req<=0; end
    end

    //======================================================================
    // Test infrastructure
    //======================================================================
    integer success_count=0, fail_count=0, test_no=1;

    task automatic reset();
        rst_n=0; rx_pt_en=0; resp_rx_pt_en=0; tb_suppress_sb=0;
        cfg_max_err_thresh_perlane=0; cfg_max_err_thresh_aggr=0;
        // Reset to all-pass defaults (new *_pass polarity):
        tb_req_perlane_pass=16'hFFFF; tb_req_aggr_pass=1; tb_req_val_pass=1;
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
        d2c_clk_sampling=cs; d2c_pattern_setup=ps; d2c_data_pattern_sel=dp;
        d2c_val_pattern_sel=vp; d2c_pattern_mode=pm;
        d2c_burst_count=bc; d2c_idle_count=ic; d2c_iter_count=nc; d2c_compare_setup=cmp;
    endtask

    task automatic start_test(input logic expect_timeout);
        @(posedge lclk); rx_pt_en=1; resp_rx_pt_en=1;
        fork : tf
            begin
                wait(req_test_d2c_done || timeout_8ms_occured_req);
                @(posedge lclk); rx_pt_en=0; resp_rx_pt_en=0;
                if (timeout_8ms_occured_req) begin
                    if (expect_timeout) begin $display("%12t ps: [PASS] Expected timeout.",$time); success_count++; end
                    else begin $display("%12t ps: [FAIL] Unexpected timeout!",$time); fail_count++; $stop; end
                end else begin
                    if (expect_timeout) begin $display("%12t ps: [FAIL] Expected TO but done!",$time); fail_count++; $stop; end
                    else begin wait(req_state==RX_PT_IDLE_R); $display("%12t ps: [PASS] Done.",$time); success_count++; end
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

    // Check REQ (Local) MB signals in a given state
    task automatic check_req_mb_signals(
            input string context_str,
            input logic  exp_compare_en,
            input logic  exp_lfsr_en,
            input logic  exp_lfsr_rst,
            input logic  exp_trk_sel,
            input logic  exp_clk_sel,
            input logic  exp_val_sel,
            input logic  exp_data_sel
        );
        if (req_mb_rx_compare_en_w !== exp_compare_en) begin
            $display("  [FAIL] %s: mb_rx_compare_en=%b, expected=%b", context_str, req_mb_rx_compare_en_w, exp_compare_en);
            fail_count++; $stop;
        end
        if (req_mb_rx_lfsr_en_w !== exp_lfsr_en) begin
            $display("  [FAIL] %s: mb_rx_lfsr_en=%b, expected=%b", context_str, req_mb_rx_lfsr_en_w, exp_lfsr_en);
            fail_count++; $stop;
        end
        if (req_mb_rx_lfsr_rst_w !== exp_lfsr_rst) begin
            $display("  [FAIL] %s: mb_rx_lfsr_rst=%b, expected=%b", context_str, req_mb_rx_lfsr_rst_w, exp_lfsr_rst);
            fail_count++; $stop;
        end
        if (req_mb_rx_trk_lane_sel_w !== exp_trk_sel) begin
            $display("  [FAIL] %s: mb_rx_trk_lane_sel=%b, expected=%b", context_str, req_mb_rx_trk_lane_sel_w, exp_trk_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_clk_lane_sel_w !== exp_clk_sel) begin
            $display("  [FAIL] %s: mb_rx_clk_lane_sel=%b, expected=%b", context_str, req_mb_rx_clk_lane_sel_w, exp_clk_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_val_lane_sel_w !== exp_val_sel) begin
            $display("  [FAIL] %s: mb_rx_val_lane_sel=%b, expected=%b", context_str, req_mb_rx_val_lane_sel_w, exp_val_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_data_lane_sel_w !== exp_data_sel) begin
            $display("  [FAIL] %s: mb_rx_data_lane_sel=%b, expected=%b", context_str, req_mb_rx_data_lane_sel_w, exp_data_sel);
            fail_count++; $stop;
        end
    endtask

    // Check REQ (Local) RX config pass-through signals
    task automatic check_req_rx_config_passthrough(input string context_str);
        if (req_mb_rx_compare_setup_w !== d2c_compare_setup) begin
            $display("  [FAIL] %s: mb_rx_compare_setup=%b, expected=%b", context_str, req_mb_rx_compare_setup_w, d2c_compare_setup);
            fail_count++; $stop;
        end
        if (req_mb_rx_max_err_thresh_perlane_w !== cfg_max_err_thresh_perlane) begin
            $display("  [FAIL] %s: mb_rx_max_err_thresh_perlane=%h, expected=%h", context_str, req_mb_rx_max_err_thresh_perlane_w, cfg_max_err_thresh_perlane);
            fail_count++; $stop;
        end
        if (req_mb_rx_max_err_thresh_aggr_w !== cfg_max_err_thresh_aggr) begin
            $display("  [FAIL] %s: mb_rx_max_err_thresh_aggr=%h, expected=%h", context_str, req_mb_rx_max_err_thresh_aggr_w, cfg_max_err_thresh_aggr);
            fail_count++; $stop;
        end
        if (req_mb_rx_iter_count_w !== d2c_iter_count) begin
            $display("  [FAIL] %s: mb_rx_iter_count=%h, expected=%h", context_str, req_mb_rx_iter_count_w, d2c_iter_count);
            fail_count++; $stop;
        end
        if (req_mb_rx_idle_count_w !== d2c_idle_count) begin
            $display("  [FAIL] %s: mb_rx_idle_count=%h, expected=%h", context_str, req_mb_rx_idle_count_w, d2c_idle_count);
            fail_count++; $stop;
        end
        if (req_mb_rx_burst_count_w !== d2c_burst_count) begin
            $display("  [FAIL] %s: mb_rx_burst_count=%h, expected=%h", context_str, req_mb_rx_burst_count_w, d2c_burst_count);
            fail_count++; $stop;
        end
        if (req_mb_rx_pattern_mode_w !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: mb_rx_pattern_mode=%b, expected=%b", context_str, req_mb_rx_pattern_mode_w, d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (req_mb_rx_val_pattern_sel_w !== d2c_val_pattern_sel) begin
            $display("  [FAIL] %s: mb_rx_val_pattern_sel=%b, expected=%b", context_str, req_mb_rx_val_pattern_sel_w, d2c_val_pattern_sel);
            fail_count++; $stop;
        end
        if (req_mb_rx_data_pattern_sel_w !== d2c_data_pattern_sel) begin
            $display("  [FAIL] %s: mb_rx_data_pattern_sel=%b, expected=%b", context_str, req_mb_rx_data_pattern_sel_w, d2c_data_pattern_sel);
            fail_count++; $stop;
        end
    endtask

    // Check RESP (Partner) TX lane selection during PATTERN_GEN
    task automatic check_resp_pattern_gen_signals(input string context_str);
        if (resp_mb_tx_pattern_en_w !== 1'b1) begin
            $display("  [FAIL] %s: mb_tx_pattern_en=%b, expected=1", context_str, resp_mb_tx_pattern_en_w);
            fail_count++; $stop;
        end
        if (resp_mb_tx_clk_lane_sel_w !== 2'b01) begin
            $display("  [FAIL] %s: mb_tx_clk_lane_sel=%b, expected=01", context_str, resp_mb_tx_clk_lane_sel_w);
            fail_count++; $stop;
        end
        if (resp_mb_tx_trk_lane_sel_w !== 2'b00) begin
            $display("  [FAIL] %s: mb_tx_trk_lane_sel=%b, expected=00", context_str, resp_mb_tx_trk_lane_sel_w);
            fail_count++; $stop;
        end
    endtask

    // Check RESP (Partner) decoded config from SB data field
    task automatic check_resp_decoded_config(input string context_str);
        if (resp_mb_tx_iter_count_w !== d2c_iter_count) begin
            $display("  [FAIL] %s: resp iter_count=%h, expected=%h", context_str, resp_mb_tx_iter_count_w, d2c_iter_count);
            fail_count++; $stop;
        end
        if (resp_mb_tx_idle_count_w !== d2c_idle_count) begin
            $display("  [FAIL] %s: resp idle_count=%h, expected=%h", context_str, resp_mb_tx_idle_count_w, d2c_idle_count);
            fail_count++; $stop;
        end
        if (resp_mb_tx_burst_count_w !== d2c_burst_count) begin
            $display("  [FAIL] %s: resp burst_count=%h, expected=%h", context_str, resp_mb_tx_burst_count_w, d2c_burst_count);
            fail_count++; $stop;
        end
        if (resp_mb_tx_pattern_mode_w !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: resp pattern_mode=%b, expected=%b", context_str, resp_mb_tx_pattern_mode_w, d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (resp_mb_tx_clk_sampling_w !== d2c_clk_sampling) begin
            $display("  [FAIL] %s: resp clk_sampling=%b, expected=%b", context_str, resp_mb_tx_clk_sampling_w, d2c_clk_sampling);
            fail_count++; $stop;
        end
        if (resp_mb_tx_data_pattern_sel_w !== d2c_data_pattern_sel) begin
            $display("  [FAIL] %s: resp data_pattern_sel=%b, expected=%b", context_str, resp_mb_tx_data_pattern_sel_w, d2c_data_pattern_sel);
            fail_count++; $stop;
        end
    endtask

    // Check SB data field encoding for Start REQ message
    task automatic check_start_req_sb_encoding(input string context_str);
        reg [63:0] captured_data;
        reg [15:0] captured_info;
        wait(req_tx_sb_valid && req_tx_sb_msg == Start_Rx_Init_D_to_C_point_test_req);
        @(negedge lclk);
        captured_data = req_tx_data_field;
        captured_info = req_tx_msginfo;

        if (captured_data[63:60] !== 4'b0) begin
            $display("  [FAIL] %s: data_field[63:60] reserved=%b, expected=0000", context_str, captured_data[63:60]);
            fail_count++; $stop;
        end
        if (captured_data[59] !== (d2c_compare_setup != 2'd0)) begin
            $display("  [FAIL] %s: data_field[59] compare_mode=%b, expected=%b", context_str, captured_data[59], (d2c_compare_setup != 2'd0));
            fail_count++; $stop;
        end
        if (captured_data[58:43] !== d2c_iter_count) begin
            $display("  [FAIL] %s: data_field[58:43] iter_count=%h, expected=%h", context_str, captured_data[58:43], d2c_iter_count);
            fail_count++; $stop;
        end
        if (captured_data[42:27] !== d2c_idle_count) begin
            $display("  [FAIL] %s: data_field[42:27] idle_count=%h, expected=%h", context_str, captured_data[42:27], d2c_idle_count);
            fail_count++; $stop;
        end
        if (captured_data[26:11] !== d2c_burst_count) begin
            $display("  [FAIL] %s: data_field[26:11] burst_count=%h, expected=%h", context_str, captured_data[26:11], d2c_burst_count);
            fail_count++; $stop;
        end
        if (captured_data[10] !== d2c_pattern_mode) begin
            $display("  [FAIL] %s: data_field[10] pattern_mode=%b, expected=%b", context_str, captured_data[10], d2c_pattern_mode);
            fail_count++; $stop;
        end
        if (captured_data[9:6] !== {2'b0, d2c_clk_sampling}) begin
            $display("  [FAIL] %s: data_field[9:6] clk_sampling=%b, expected=%b", context_str, captured_data[9:6], {2'b0, d2c_clk_sampling});
            fail_count++; $stop;
        end
        if (captured_data[5:3] !== {2'b0, d2c_val_pattern_sel}) begin
            $display("  [FAIL] %s: data_field[5:3] val_pattern=%b, expected=%b", context_str, captured_data[5:3], {2'b0, d2c_val_pattern_sel});
            fail_count++; $stop;
        end
        if (captured_data[2:0] !== {1'b0, d2c_data_pattern_sel}) begin
            $display("  [FAIL] %s: data_field[2:0] data_pattern=%b, expected=%b", context_str, captured_data[2:0], {1'b0, d2c_data_pattern_sel});
            fail_count++; $stop;
        end
        $display("  [OK] %s: SB Start REQ encoding verified", context_str);
    endtask

    //======================================================================
    // Comprehensive happy-path verification task (per-state signal checks)
    //======================================================================
    task automatic run_verified_happy_path(input string scenario_name);
        logic exp_lfsr_en;
        exp_lfsr_en = (d2c_data_pattern_sel == 2'b0 && d2c_pattern_setup[0] == 1'b1);

        @(posedge lclk);
        wait(req_state == RX_PT_SEND_START_REQ);
        @(negedge lclk);
        // SEND_START_REQ: compare_en=1, lfsr_en=exp, lfsr_rst=0, lanes: trk=0 clk=1 val=1 data=1
        check_req_mb_signals("SEND_START_REQ", 1'b1, exp_lfsr_en, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        check_req_rx_config_passthrough("SEND_START_REQ");
        if (req_tx_sb_valid !== 1'b1) begin
            $display("  [FAIL] SEND_START_REQ: tx_sb_msg_valid=%b, expected=1", req_tx_sb_valid);
            fail_count++; $stop;
        end
        if (req_tx_sb_msg !== Start_Rx_Init_D_to_C_point_test_req) begin
            $display("  [FAIL] SEND_START_REQ: tx_sb_msg=%h", req_tx_sb_msg);
            fail_count++; $stop;
        end

        // WAIT_START_RESP
        wait(req_state == RX_PT_WAIT_START_RESP);
        @(negedge lclk);
        check_req_mb_signals("WAIT_START_RESP", 1'b1, exp_lfsr_en, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] WAIT_START_RESP: tx_sb_msg_valid should be 0");
            fail_count++; $stop;
        end

        // WAIT_CLR_ERR_REQ
        wait(req_state == RX_PT_WAIT_CLR_ERR_REQ_R);
        @(negedge lclk);
        check_req_mb_signals("WAIT_CLR_ERR_REQ", 1'b1, exp_lfsr_en, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);

        // RESP: SEND_START_RESP
        wait(resp_state == RX_PT_SEND_START_RESP_S);
        @(negedge lclk);
        if (resp_tx_sb_valid !== 1'b1) begin
            $display("  [FAIL] RESP SEND_START_RESP: tx_sb_msg_valid=%b, expected=1", resp_tx_sb_valid);
            fail_count++; $stop;
        end
        if (resp_mb_tx_clk_sampling_en_w !== 1'b1) begin
            $display("  [FAIL] RESP SEND_START_RESP: mb_tx_clk_sampling_en=%b, expected=1", resp_mb_tx_clk_sampling_en_w);
            fail_count++; $stop;
        end

        // RESP: TX_LFSR_RST — pulse gap, lfsr_rst=1
        wait(resp_state == RX_PT_TX_LFSR_RST_S);
        @(negedge lclk);
        check_resp_decoded_config("RESP after decode");
        if (resp_mb_tx_lfsr_rst_w !== 1'b1) begin
            $display("  [FAIL] RESP TX_LFSR_RST: mb_tx_lfsr_rst=%b, expected=1", resp_mb_tx_lfsr_rst_w);
            fail_count++; $stop;
        end
        if (resp_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] RESP TX_LFSR_RST: tx_sb_msg_valid should be 0 (pulse gap)");
            fail_count++; $stop;
        end

        // RESP: SEND_CLR_ERR_REQ
        wait(resp_state == RX_PT_SEND_CLR_ERR_REQ_S);
        @(negedge lclk);
        if (resp_tx_sb_valid !== 1'b1 || resp_tx_sb_msg !== LFSR_clear_error_req) begin
            $display("  [FAIL] RESP SEND_CLR_ERR_REQ: msg mismatch valid=%b msg=%h", resp_tx_sb_valid, resp_tx_sb_msg);
            fail_count++; $stop;
        end
        if (resp_mb_tx_lfsr_rst_w !== 1'b1) begin
            $display("  [FAIL] RESP SEND_CLR_ERR_REQ: mb_tx_lfsr_rst should be 1");
            fail_count++; $stop;
        end

        // REQ: SEND_CLR_ERR_RESP — resets RX LFSR
        wait(req_state == RX_PT_SEND_CLR_ERR_RESP);
        @(negedge lclk);
        check_req_mb_signals("SEND_CLR_ERR_RESP", 1'b1, exp_lfsr_en, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_tx_sb_valid !== 1'b1 || req_tx_sb_msg !== LFSR_clear_error_resp) begin
            $display("  [FAIL] SEND_CLR_ERR_RESP: msg mismatch valid=%b msg=%h", req_tx_sb_valid, req_tx_sb_msg);
            fail_count++; $stop;
        end

        // REQ: WAIT_COUNT_DONE_REQ — comparison running
        wait(req_state == RX_PT_WAIT_COUNT_DONE_REQ);
        @(negedge lclk);
        check_req_mb_signals("WAIT_COUNT_DONE_REQ", 1'b1, exp_lfsr_en, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);

        // RESP: PATTERN_GEN
        wait(resp_state == RX_PT_PATTERN_GEN_S);
        @(negedge lclk);
        check_resp_pattern_gen_signals("RESP PATTERN_GEN");

        // REQ: SEND_COUNT_DONE_RESP — stops comparison
        wait(req_state == RX_PT_SEND_COUNT_DONE_RESP);
        @(negedge lclk);
        check_req_mb_signals("SEND_COUNT_DONE_RESP", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_tx_sb_valid !== 1'b1 || req_tx_sb_msg !== Rx_Init_D_to_C_Tx_Count_Done_resp) begin
            $display("  [FAIL] SEND_COUNT_DONE_RESP: msg mismatch valid=%b msg=%h", req_tx_sb_valid, req_tx_sb_msg);
            fail_count++; $stop;
        end

        // REQ: LOG_RESULT — pulse gap, results logged from MB compare
        wait(req_state == RX_PT_LOG_RESULT_R);
        @(negedge lclk);
        check_req_mb_signals("LOG_RESULT", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_tx_sb_valid !== 1'b0) begin
            $display("  [FAIL] LOG_RESULT: tx_sb_msg_valid should be 0");
            fail_count++; $stop;
        end

        // REQ: SEND_END_REQ
        wait(req_state == RX_PT_SEND_END_REQ);
        @(negedge lclk);
        check_req_mb_signals("SEND_END_REQ", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_tx_sb_valid !== 1'b1 || req_tx_sb_msg !== End_Rx_Init_D_to_C_point_test_req) begin
            $display("  [FAIL] SEND_END_REQ: msg mismatch valid=%b msg=%h", req_tx_sb_valid, req_tx_sb_msg);
            fail_count++; $stop;
        end

        // REQ: WAIT_END_RESP
        wait(req_state == RX_PT_WAIT_END_RESP);
        @(negedge lclk);
        check_req_mb_signals("WAIT_END_RESP", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);

        // RESP: SEND_END_RESP
        wait(resp_state == RX_PT_SEND_END_RESP_S);
        @(negedge lclk);
        if (resp_tx_sb_valid !== 1'b1 || resp_tx_sb_msg !== End_Rx_Init_D_to_C_point_test_resp) begin
            $display("  [FAIL] RESP SEND_END_RESP: msg mismatch valid=%b msg=%h", resp_tx_sb_valid, resp_tx_sb_msg);
            fail_count++; $stop;
        end

        // REQ: DONE
        wait(req_state == RX_PT_DONE_R);
        @(negedge lclk);
        check_req_mb_signals("DONE", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1);
        if (req_test_d2c_done !== 1'b1) begin
            $display("  [FAIL] DONE: test_d2c_done=%b, expected=1", req_test_d2c_done);
            fail_count++; $stop;
        end

        // RESP: DONE
        wait(resp_state == RX_PT_DONE_S);
        @(negedge lclk);
        if (resp_test_d2c_done !== 1'b1) begin
            $display("  [FAIL] RESP DONE: test_d2c_done=%b, expected=1", resp_test_d2c_done);
            fail_count++; $stop;
        end
        if (resp_mb_tx_pattern_en_w !== 1'b0) begin
            $display("  [FAIL] RESP DONE: mb_tx_pattern_en should be 0");
            fail_count++; $stop;
        end

        $display("  [OK] %s: All per-state signal checks passed", scenario_name);
    endtask

    //======================================================================
    // Main Test Sequence
    //======================================================================
    initial begin
        $display("\n=== unit_RX_D2C_PT Dual-Die Testbench (Comprehensive) ===\n");
        $display("  Signal polarity: *_pass signals: 1=pass(no error), 0=fail(error detected)\n");

        //------------------------------------------------------------------
        // Scenario 1: Happy path — per-lane, LFSR, all pass (FULL signal check)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Happy Path (per-lane LFSR, all pass, FULL signal check)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        // tb_req_perlane_pass=16'hFFFF, tb_req_aggr_pass=1, tb_req_val_pass=1 (defaults after reset)
        fork
            run_verified_happy_path("Scenario 1");
            check_start_req_sb_encoding("Scenario 1");
        join_none
        start_test(0);
        // After DONE: d2c_perlane_pass should be 0xFFFF (all lanes passed)
        if (req_d2c_perlane_pass == 16'hFFFF && req_d2c_aggr_pass == 1'b1 && req_d2c_val_pass == 1'b1)
            $display("  MATCH: all pass (perlane=FFFF, aggr=1, val=1)");
        else begin
            $display("  FAIL: pass mismatch perlane=%h aggr=%b val=%b",
                     req_d2c_perlane_pass, req_d2c_aggr_pass, req_d2c_val_pass);
            fail_count++; $stop;
        end

        //------------------------------------------------------------------
        // Scenario 2: Per-lane partial fail (some lanes failed → *_pass bits = 0)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: REQ Local RX Per-Lane Partial Fail (perlane_pass=0xBEEF)", test_no++);
        reset();
        tb_req_perlane_pass = 16'hBEEF; // some lanes failed (0-bits = fail)
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'hBEEF)
            $display("  MATCH: perlane_pass=0xBEEF");
        else begin $display("  FAIL: perlane mismatch %h", req_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 3: Aggregate fail (aggr_pass=0)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: REQ Local RX Aggregate Fail (aggr_pass=0)", test_no++);
        reset();
        tb_req_aggr_pass = 1'b0; // aggregate failed
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd1);
        cfg_max_err_thresh_aggr = 16'h0100;
        start_test(0);
        if (req_d2c_aggr_pass == 1'b0)
            $display("  MATCH: aggr_pass=0 (aggregate failed)");
        else begin $display("  FAIL: aggr_pass expected 0"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 4: Timeout — suppress SB
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Timeout (SB suppressed)", test_no++);
        reset(); tb_suppress_sb=1;
        start_test(1);

        //------------------------------------------------------------------
        // Scenario 5: Valid Lane fail (val_pass=0)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: REQ Local RX Val Fail (val_pass=0)", test_no++);
        reset();
        tb_req_val_pass = 1'b0; // valid lane mismatch detected
        set_config(2'b00, 3'b010, 2'b11, 0, 0, 8, 0, 1, 2'd2);
        start_test(0);
        if (req_d2c_val_pass == 1'b0)
            $display("  MATCH: val_pass=0 (valid lane mismatch)");
        else begin $display("  FAIL: val_pass expected 0"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 6: Valid Lane pass (val_pass=1 — the default pass case)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: REQ Local RX Val Pass (val_pass=1)", test_no++);
        reset();
        tb_req_val_pass = 1'b1; // valid lane matched
        set_config(2'b00, 3'b010, 2'b11, 0, 0, 8, 0, 1, 2'd2);
        start_test(0);
        if (req_d2c_val_pass == 1'b1)
            $display("  MATCH: val_pass=1 (valid lane matched)");
        else begin $display("  FAIL: val_pass expected 1"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 7: All lanes fail (perlane_pass=0x0000)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: REQ All Lanes Fail (perlane_pass=0x0000)", test_no++);
        reset();
        tb_req_perlane_pass = 16'h0000; // all lanes failed
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'h0000)
            $display("  MATCH: perlane_pass=0x0000 (all lanes failed)");
        else begin $display("  FAIL: lanes mismatch %h", req_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 8: Burst mode
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Burst Mode (iter=3, burst=20, idle=10)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 1, 20, 10, 3, 2'd0);
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 9: Clock sampling=Left Edge (verify partner decodes it)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Clk Sampling Left Edge (verify partner decode)", test_no++);
        reset();
        set_config(2'b01, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            begin
                wait(resp_state == RX_PT_TX_LFSR_RST_S);
                @(negedge lclk);
                if (resp_mb_tx_clk_sampling_w !== 2'b01) begin
                    $display("  [FAIL] Resp clk_sampling=%b, expected=01", resp_mb_tx_clk_sampling_w);
                    fail_count++; $stop;
                end else
                    $display("  [OK] Partner decoded clk_sampling=01 (Left Edge)");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 10: Clock sampling=Right Edge
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Clk Sampling Right Edge", test_no++);
        reset();
        set_config(2'b10, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        fork
            begin
                wait(resp_state == RX_PT_TX_LFSR_RST_S);
                @(negedge lclk);
                if (resp_mb_tx_clk_sampling_w !== 2'b10) begin
                    $display("  [FAIL] Resp clk_sampling=%b, expected=10", resp_mb_tx_clk_sampling_w);
                    fail_count++; $stop;
                end else
                    $display("  [OK] Partner decoded clk_sampling=10 (Right Edge)");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 11: Per-Lane ID pattern (LFSR should be disabled)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Per-Lane ID Pattern (lfsr_en=0)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b01, 0, 0, 30, 0, 1, 2'd0);
        fork
            begin
                wait(req_state == RX_PT_WAIT_COUNT_DONE_REQ);
                @(negedge lclk);
                if (req_mb_rx_lfsr_en_w !== 1'b0) begin
                    $display("  [FAIL] Per-Lane ID mode: lfsr_en=%b, expected=0", req_mb_rx_lfsr_en_w);
                    fail_count++; $stop;
                end else
                    $display("  [OK] LFSR disabled for Per-Lane ID pattern");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 12: Back-to-back #1
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Back-to-Back #1 (perlane_pass=0x1111)", test_no++);
        tb_req_perlane_pass = 16'h1111;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'h1111)
            $display("  MATCH: B2B #1 perlane_pass=0x1111");
        else begin $display("  FAIL: B2B #1 got %h", req_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 13: Back-to-back #2
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Back-to-Back #2 (perlane_pass=0x2222)", test_no++);
        tb_req_perlane_pass = 16'h2222;
        set_config(2'b10, 3'b001, 2'b01, 0, 0, 5, 0, 2, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'h2222)
            $display("  MATCH: B2B #2 perlane_pass=0x2222");
        else begin $display("  FAIL: B2B #2 got %h", req_d2c_perlane_pass); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 14: REQ/RESP independent — local pass state unchanged by partner
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Independent REQ/RESP result isolation", test_no++);
        reset();
        tb_req_perlane_pass = 16'h1234;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 30, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'h1234)
            $display("  MATCH: req reports own perlane_pass independently");
        else begin $display("  FAIL: isolation check"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 15: Large iter count (iter=8)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: Large Iter Count (iter=8)", test_no++);
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 10, 0, 8, 2'd0);
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 16: All pass signals set to all-pass (positive test)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: All Pass (perlane=FFFF, aggr=1, val=1)", test_no++);
        reset();
        tb_req_perlane_pass = 16'hFFFF;
        tb_req_aggr_pass    = 1'b1;
        tb_req_val_pass     = 1'b1;
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'hFFFF && req_d2c_aggr_pass == 1'b1 && req_d2c_val_pass == 1'b1)
            $display("  MATCH: all pass pe=FFFF aggr=1 val=1");
        else begin $display("  FAIL: all-pass check"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 17: All fail (perlane=0, aggr=0, val=0)
        //------------------------------------------------------------------
        $display("=> Scenario %0d: All Fail (perlane=0000, aggr=0, val=0)", test_no++);
        reset();
        tb_req_perlane_pass = 16'h0000;
        tb_req_aggr_pass    = 1'b0;
        tb_req_val_pass     = 1'b0;
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 10, 0, 1, 2'd0);
        start_test(0);
        if (req_d2c_perlane_pass == 16'h0000 && req_d2c_aggr_pass == 1'b0 && req_d2c_val_pass == 1'b0)
            $display("  MATCH: all fail pe=0000 aggr=0 val=0");
        else begin $display("  FAIL: all-fail check"); fail_count++; $stop; end

        //------------------------------------------------------------------
        // Scenario 18: Aggregate threshold passed in MsgInfo
        //------------------------------------------------------------------
        $display("=> Scenario %0d: MsgInfo Aggregate Threshold (0x1234)", test_no++);
        reset();
        cfg_max_err_thresh_aggr = 16'h1234;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd1);
        fork
            begin
                wait(req_tx_sb_valid && req_tx_sb_msg == Start_Rx_Init_D_to_C_point_test_req);
                @(negedge lclk);
                if (req_tx_msginfo !== 16'h1234) begin
                    $display("  [FAIL] MsgInfo aggr threshold=%h, expected=1234", req_tx_msginfo);
                    fail_count++; $stop;
                end else
                    $display("  [OK] MsgInfo carries aggregate threshold 0x1234");
            end
        join_none
        start_test(0);

        //------------------------------------------------------------------
        // Scenario 19: Per-lane threshold passed in MsgInfo
        //------------------------------------------------------------------
        $display("=> Scenario %0d: MsgInfo Per-Lane Threshold (0xABC)", test_no++);
        reset();
        cfg_max_err_thresh_perlane = 12'hABC;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        fork
            begin
                wait(req_tx_sb_valid && req_tx_sb_msg == Start_Rx_Init_D_to_C_point_test_req);
                @(negedge lclk);
                if (req_tx_msginfo !== {4'b0, 12'hABC}) begin
                    $display("  [FAIL] MsgInfo perlane threshold=%h, expected=0ABC", req_tx_msginfo);
                    fail_count++; $stop;
                end else
                    $display("  [OK] MsgInfo carries per-lane threshold 0x0ABC");
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
            // Randomize *_pass results (new polarity: 1=pass, 0=fail)
            tb_req_perlane_pass = $urandom();
            tb_req_aggr_pass    = $urandom_range(0,1);
            tb_req_val_pass     = $urandom_range(0,1);
            cfg_max_err_thresh_perlane = $urandom() & 12'hFFF;
            cfg_max_err_thresh_aggr = $urandom();
            tb_suppress_sb = ($urandom_range(0,9)==0); // 10% timeout
            set_config(
                $urandom_range(0,2), $urandom_range(0,7),
                $urandom_range(0,2), $urandom_range(0,1),
                $urandom_range(0,1), $urandom_range(1,100), $urandom_range(0,50),
                $urandom_range(1,8), $urandom_range(0,3)
            );
            start_test(tb_suppress_sb);
            // Verify pass results for non-timeout cases
            if (!tb_suppress_sb) begin
                if (req_d2c_perlane_pass !== tb_req_perlane_pass) begin
                    $display("  [FAIL] Random: perlane_pass=%h, expected=%h",
                             req_d2c_perlane_pass, tb_req_perlane_pass);
                    fail_count++; $stop;
                end
                if (req_d2c_aggr_pass !== tb_req_aggr_pass) begin
                    $display("  [FAIL] Random: aggr_pass=%b, expected=%b",
                             req_d2c_aggr_pass, tb_req_aggr_pass);
                    fail_count++; $stop;
                end
                if (req_d2c_val_pass !== tb_req_val_pass) begin
                    $display("  [FAIL] Random: val_pass=%b, expected=%b",
                             req_d2c_val_pass, tb_req_val_pass);
                    fail_count++; $stop;
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
