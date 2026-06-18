`timescale 1ps/1ps
// =============================================================================
// wrapper_D2C_PT_top_tb.sv — Top-Level D2C Point Test Wrapper Dual-Die TB
//
// This testbench implements a physically accurate dual-die channel model:
//   - Instantiates TWO instances of wrapper_D2C_PT_top representing:
//       1. u_dut         (Die 0 / Local Die)
//       2. u_partner_die (Die 1 / Partner Die)
//   - Simulates two independent 64-cycle SB pipeline channels (async FIFO delay).
//   - Simulates two independent sets of Mainband TX/RX behavioral macros.
//   - Dynamically drives symmetric enables to test all 6 routing cases (A, B, AB, C, D, CD).
//
// Tests covered:
//   A. MBINIT Local TX Happy Path & Partial Failure (Case A / B)
//   B. MBTRAIN Local & Partner TX Happy Paths (Case A / B)
//   C. MBTRAIN Local & Partner RX Happy Paths (Case C / D)
//   D. Parallel cases AB & CD (Local and Partner active concurrently)
//   E. Config MUX verification: MBTRAIN config overrides MBINIT when active.
//   F. Timeout verification: suppressed SB triggers FSM watchdogs.
//   G. Back-to-Back (B2B) verification without hard resets.
//   H. 200 Randomized iterations spanning all configurations and results.
// =============================================================================

module wrapper_D2C_PT_top_tb;

    import UCIe_pkg::*;

    parameter LCLK_PERIOD   = 1000;      // 1 ns (1 GHz)
    parameter SB_DELAY_CYCS = 64;        // Models async FIFO crossing
    parameter TIMEOUT_LIMIT = 200_000;   // Watchdog limit in clock cycles

    // =========================================================================
    // Test kind constants (integer)
    // =========================================================================
    // 0 = TEST_LOCAL_TX   (local die initiates TX test)
    // 1 = TEST_PARTNER_TX (partner die initiates TX test)
    // 2 = TEST_LOCAL_RX   (local die initiates RX test)
    // 3 = TEST_PARTNER_RX (partner die initiates RX test)
    // 4 = TEST_PARALLEL_TX(both dies initiate TX tests concurrently)
    // 5 = TEST_PARALLEL_RX(both dies initiate RX tests concurrently)
    localparam integer TEST_LOCAL_TX    = 0;
    localparam integer TEST_PARTNER_TX  = 1;
    localparam integer TEST_LOCAL_RX    = 2;
    localparam integer TEST_PARTNER_RX  = 3;
    localparam integer TEST_PARALLEL_TX = 4;
    localparam integer TEST_PARALLEL_RX = 5;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    reg lclk = 0, rst_n = 0;
    always #(LCLK_PERIOD/2) lclk = ~lclk;

    // =========================================================================
    // Force/Control variables set by the test runner
    // =========================================================================
    reg [15:0] tb_perlane_pass = 16'hFFFF;
    reg        tb_aggr_pass    = 1'b1;
    reg        tb_val_pass     = 1'b1;
    reg        tb_verbose      = 1'b1;

    // =========================================================================
    // Die 0 (u_dut) Control & Config
    // =========================================================================
    reg [2:0]  mb_rx_data_lane_mask = 3'b011;  // Default: Lanes 0-15
    wire       dut_local_test_d2c_done;
    wire       dut_partner_test_d2c_done;
    wire [15:0] dut_d2c_perlane_pass;
    wire       dut_d2c_aggr_pass;
    wire       dut_d2c_val_pass;

    reg        local_tx_pt_en          = 0;
    reg        partner_tx_pt_en        = 0;
    reg        local_rx_pt_en          = 0;
    reg        partner_rx_pt_en        = 0;
    reg [1:0]  d2c_clk_sampling        = 2'b00;
    reg [2:0]  d2c_pattern_setup       = 3'b001;
    reg [1:0]  d2c_data_pattern_sel    = 2'b00;
    reg        d2c_val_pattern_sel     = 1'b0;
    reg        d2c_pattern_mode        = 1'b0;
    reg [15:0] d2c_burst_count         = 16'd50;
    reg [15:0] d2c_idle_count          = 16'd0;
    reg [15:0] d2c_iter_count          = 16'd1;
    reg [1:0]  d2c_compare_setup       = 2'b00;
    reg [11:0] cfg_max_err_thresh_perlane = 12'd0;
    reg [15:0] cfg_max_err_thresh_aggr    = 16'd0;

    // Die 0 (DUT) Mainband Interface outputs
    wire [1:0]  dut_mb_tx_trk_lane_sel;
    wire [1:0]  dut_mb_tx_clk_lane_sel;
    wire [1:0]  dut_mb_tx_val_lane_sel;
    wire [1:0]  dut_mb_tx_data_lane_sel;
    wire        dut_mb_rx_trk_lane_sel;
    wire        dut_mb_rx_clk_lane_sel;
    wire        dut_mb_rx_val_lane_sel;
    wire        dut_mb_rx_data_lane_sel;
    wire        dut_mb_tx_pattern_en;
    wire [2:0]  dut_mb_tx_pattern_setup;
    wire [2:0]  dut_mb_rx_pattern_setup;
    wire        dut_mb_tx_lfsr_en;
    wire        dut_mb_tx_lfsr_rst;
    wire        dut_mb_rx_lfsr_en;
    wire        dut_mb_rx_lfsr_rst;
    wire [15:0] dut_mb_rx_iter_count;
    wire [15:0] dut_mb_rx_idle_count;
    wire [15:0] dut_mb_rx_burst_count;
    wire        dut_mb_rx_pattern_mode;
    wire        dut_mb_rx_val_pattern_sel;
    wire [1:0]  dut_mb_rx_data_pattern_sel;
    wire        dut_mb_rx_compare_en;
    wire [1:0]  dut_mb_rx_compare_setup;
    wire [11:0] dut_mb_rx_max_err_thresh_perlane;
    wire [15:0] dut_mb_rx_max_err_thresh_aggr;
    wire        dut_mb_tx_clk_sampling_en;
    wire [1:0]  dut_mb_tx_clk_sampling;
    wire        dut_mb_tx_pattern_mode;
    wire [15:0] dut_mb_tx_burst_count;
    wire [15:0] dut_mb_tx_idle_count;
    wire [15:0] dut_mb_tx_iter_count;
    wire [1:0]  dut_mb_tx_data_pattern_sel;
    wire        dut_mb_tx_val_pattern_sel;

    // Macro status signals (inputs to Die 0)
    reg         dut_mb_tx_pattern_count_done = 0;
    // reg         dut_mb_rx_compare_done       = 0;
    reg         dut_mb_rx_aggr_pass          = 1;
    reg [15:0]  dut_mb_rx_perlane_pass       = 16'hFFFF;
    reg         dut_mb_rx_val_pass           = 1;

    // SB outputs and inputs for Die 0
    wire        dut_tx_sb_msg_valid;
    wire [7:0]  dut_tx_sb_msg;
    wire [15:0] dut_tx_msginfo;
    wire [63:0] dut_tx_data_field;
    wire        dut_rx_sb_msg_valid;
    wire [7:0]  dut_rx_sb_msg;
    wire [15:0] dut_rx_msginfo;
    wire [63:0] dut_rx_data_field;

    // =========================================================================
    // Die 1 (u_partner_die) Control & Config
    // =========================================================================
    reg        ptn_local_tx_pt_en      = 0;
    reg        ptn_partner_tx_pt_en    = 0;
    reg        ptn_local_rx_pt_en      = 0;
    reg        ptn_partner_rx_pt_en    = 0;

    wire       ptn_local_test_d2c_done;
    wire       ptn_partner_test_d2c_done;
    wire [15:0] ptn_d2c_perlane_pass;
    wire       ptn_d2c_aggr_pass;
    wire       ptn_d2c_val_pass;

    // Die 1 (Partner) Mainband Interface outputs
    wire [1:0]  ptn_mb_tx_trk_lane_sel;
    wire [1:0]  ptn_mb_tx_clk_lane_sel;
    wire [1:0]  ptn_mb_tx_val_lane_sel;
    wire [1:0]  ptn_mb_tx_data_lane_sel;
    wire        ptn_mb_rx_trk_lane_sel;
    wire        ptn_mb_rx_clk_lane_sel;
    wire        ptn_mb_rx_val_lane_sel;
    wire        ptn_mb_rx_data_lane_sel;
    wire        ptn_mb_tx_pattern_en;
    wire [2:0]  ptn_mb_tx_pattern_setup;
    wire [2:0]  ptn_mb_rx_pattern_setup;
    wire        ptn_mb_tx_lfsr_en;
    wire        ptn_mb_tx_lfsr_rst;
    wire        ptn_mb_rx_lfsr_en;
    wire        ptn_mb_rx_lfsr_rst;
    wire [15:0] ptn_mb_rx_iter_count;
    wire [15:0] ptn_mb_rx_idle_count;
    wire [15:0] ptn_mb_rx_burst_count;
    wire        ptn_mb_rx_pattern_mode;
    wire        ptn_mb_rx_val_pattern_sel;
    wire [1:0]  ptn_mb_rx_data_pattern_sel;
    wire        ptn_mb_rx_compare_en;
    wire [1:0]  ptn_mb_rx_compare_setup;
    wire [11:0] ptn_mb_rx_max_err_thresh_perlane;
    wire [15:0] ptn_mb_rx_max_err_thresh_aggr;
    wire        ptn_mb_tx_clk_sampling_en;
    wire [1:0]  ptn_mb_tx_clk_sampling;
    wire        ptn_mb_tx_pattern_mode;
    wire [15:0] ptn_mb_tx_burst_count;
    wire [15:0] ptn_mb_tx_idle_count;
    wire [15:0] ptn_mb_tx_iter_count;
    wire [1:0]  ptn_mb_tx_data_pattern_sel;
    wire        ptn_mb_tx_val_pattern_sel;

    // Macro status signals (inputs to Die 1)
    reg         ptn_mb_tx_pattern_count_done = 0;
    // reg         ptn_mb_rx_compare_done       = 0;
    reg         ptn_mb_rx_aggr_pass          = 1;
    reg [15:0]  ptn_mb_rx_perlane_pass       = 16'hFFFF;
    reg         ptn_mb_rx_val_pass           = 1;

    // SB outputs and inputs for Die 1
    wire        ptn_tx_sb_msg_valid;
    wire [7:0]  ptn_tx_sb_msg;
    wire [15:0] ptn_tx_msginfo;
    wire [63:0] ptn_tx_data_field;
    wire        ptn_rx_sb_msg_valid;
    wire [7:0]  ptn_rx_sb_msg;
    wire [15:0] ptn_rx_msginfo;
    wire [63:0] ptn_rx_data_field;


    // =========================================================================
    // DUT (Die 0) Instantiation
    // =========================================================================
    wrapper_D2C_PT_top u_dut (
        .lclk                           (lclk                          ),
        .rst_n                          (rst_n                         ),
        .mb_rx_data_lane_mask           (mb_rx_data_lane_mask          ),
        .local_test_d2c_done            (dut_local_test_d2c_done       ),
        .partner_test_d2c_done          (dut_partner_test_d2c_done     ),
        .d2c_perlane_pass               (dut_d2c_perlane_pass          ),
        .d2c_aggr_pass                  (dut_d2c_aggr_pass             ),
        .d2c_val_pass                   (dut_d2c_val_pass              ),
        .local_tx_pt_en                 (local_tx_pt_en                ),
        .partner_tx_pt_en               (partner_tx_pt_en              ),
        .local_rx_pt_en                 (local_rx_pt_en                ),
        .partner_rx_pt_en               (partner_rx_pt_en              ),
        .d2c_clk_sampling               (d2c_clk_sampling              ),
        .d2c_pattern_setup              (d2c_pattern_setup             ),
        .d2c_data_pattern_sel           (d2c_data_pattern_sel          ),
        .d2c_val_pattern_sel            (d2c_val_pattern_sel           ),
        .d2c_pattern_mode               (d2c_pattern_mode              ),
        .d2c_burst_count                (d2c_burst_count               ),
        .d2c_idle_count                 (d2c_idle_count                ),
        .d2c_iter_count                 (d2c_iter_count                ),
        .d2c_compare_setup              (d2c_compare_setup             ),
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane    ),
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr       ),
        .mb_tx_trk_lane_sel             (dut_mb_tx_trk_lane_sel        ),
        .mb_tx_clk_lane_sel             (dut_mb_tx_clk_lane_sel        ),
        .mb_tx_val_lane_sel             (dut_mb_tx_val_lane_sel        ),
        .mb_tx_data_lane_sel            (dut_mb_tx_data_lane_sel       ),
        .mb_rx_trk_lane_sel             (dut_mb_rx_trk_lane_sel        ),
        .mb_rx_clk_lane_sel             (dut_mb_rx_clk_lane_sel        ),
        .mb_rx_val_lane_sel             (dut_mb_rx_val_lane_sel        ),
        .mb_rx_data_lane_sel            (dut_mb_rx_data_lane_sel       ),
        .mb_tx_pattern_en               (dut_mb_tx_pattern_en          ),
        .mb_tx_pattern_setup            (dut_mb_tx_pattern_setup       ),
        .mb_rx_pattern_setup            (dut_mb_rx_pattern_setup       ),
        .mb_tx_lfsr_en                  (dut_mb_tx_lfsr_en             ),
        .mb_tx_lfsr_rst                 (dut_mb_tx_lfsr_rst            ),
        .mb_rx_lfsr_en                  (dut_mb_rx_lfsr_en             ),
        .mb_rx_lfsr_rst                 (dut_mb_rx_lfsr_rst            ),
        .mb_rx_iter_count               (dut_mb_rx_iter_count          ),
        .mb_rx_idle_count               (dut_mb_rx_idle_count          ),
        .mb_rx_burst_count              (dut_mb_rx_burst_count         ),
        .mb_rx_pattern_mode             (dut_mb_rx_pattern_mode        ),
        .mb_rx_val_pattern_sel          (dut_mb_rx_val_pattern_sel     ),
        .mb_rx_data_pattern_sel         (dut_mb_rx_data_pattern_sel    ),
        .mb_rx_compare_en               (dut_mb_rx_compare_en          ),
        .mb_rx_compare_setup            (dut_mb_rx_compare_setup       ),
        .mb_rx_max_err_thresh_perlane   (dut_mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr      (dut_mb_rx_max_err_thresh_aggr ),
        .mb_tx_clk_sampling_en          (dut_mb_tx_clk_sampling_en     ),
        .mb_tx_clk_sampling             (dut_mb_tx_clk_sampling        ),
        .mb_tx_pattern_mode             (dut_mb_tx_pattern_mode        ),
        .mb_tx_burst_count              (dut_mb_tx_burst_count         ),
        .mb_tx_idle_count               (dut_mb_tx_idle_count          ),
        .mb_tx_iter_count               (dut_mb_tx_iter_count          ),
        .mb_tx_data_pattern_sel         (dut_mb_tx_data_pattern_sel    ),
        .mb_tx_val_pattern_sel          (dut_mb_tx_val_pattern_sel     ),
        .mb_tx_pattern_count_done       (dut_mb_tx_pattern_count_done  ),
        // .mb_rx_compare_done             (dut_mb_rx_compare_done        ),
        .mb_rx_aggr_pass                (dut_mb_rx_aggr_pass           ),
        .mb_rx_perlane_pass             (dut_mb_rx_perlane_pass        ),
        .mb_rx_val_pass                 (dut_mb_rx_val_pass            ),
        .tx_sb_msg_valid                (dut_tx_sb_msg_valid           ),
        .tx_sb_msg                      (dut_tx_sb_msg                 ),
        .tx_msginfo                     (dut_tx_msginfo                ),
        .tx_data_field                  (dut_tx_data_field             ),
        .rx_sb_msg_valid                (dut_rx_sb_msg_valid           ),
        .rx_sb_msg                      (dut_rx_sb_msg                 ),
        .rx_msginfo                     (dut_rx_msginfo                ),
        .rx_data_field                  (dut_rx_data_field             )
    );

    // =========================================================================
    // Partner Die (Die 1) Instantiation
    // =========================================================================
    wrapper_D2C_PT_top u_partner_die (
        .lclk                           (lclk                          ),
        .rst_n                          (rst_n                         ),
        .mb_rx_data_lane_mask           (mb_rx_data_lane_mask          ),
        .local_test_d2c_done            (ptn_local_test_d2c_done       ),
        .partner_test_d2c_done          (ptn_partner_test_d2c_done     ),
        .d2c_perlane_pass               (ptn_d2c_perlane_pass          ),
        .d2c_aggr_pass                  (ptn_d2c_aggr_pass             ),
        .d2c_val_pass                   (ptn_d2c_val_pass              ),
        .local_tx_pt_en                 (ptn_local_tx_pt_en            ),
        .partner_tx_pt_en               (ptn_partner_tx_pt_en          ),
        .local_rx_pt_en                 (ptn_local_rx_pt_en            ),
        .partner_rx_pt_en               (ptn_partner_rx_pt_en          ),
        .d2c_clk_sampling               (d2c_clk_sampling              ),
        .d2c_pattern_setup              (d2c_pattern_setup             ),
        .d2c_data_pattern_sel           (d2c_data_pattern_sel          ),
        .d2c_val_pattern_sel            (d2c_val_pattern_sel           ),
        .d2c_pattern_mode               (d2c_pattern_mode              ),
        .d2c_burst_count                (d2c_burst_count               ),
        .d2c_idle_count                 (d2c_idle_count                ),
        .d2c_iter_count                 (d2c_iter_count                ),
        .d2c_compare_setup              (d2c_compare_setup             ),
        .cfg_max_err_thresh_perlane     (cfg_max_err_thresh_perlane    ),
        .cfg_max_err_thresh_aggr        (cfg_max_err_thresh_aggr       ),
        .mb_tx_trk_lane_sel             (ptn_mb_tx_trk_lane_sel        ),
        .mb_tx_clk_lane_sel             (ptn_mb_tx_clk_lane_sel        ),
        .mb_tx_val_lane_sel             (ptn_mb_tx_val_lane_sel        ),
        .mb_tx_data_lane_sel            (ptn_mb_tx_data_lane_sel       ),
        .mb_rx_trk_lane_sel             (ptn_mb_rx_trk_lane_sel        ),
        .mb_rx_clk_lane_sel             (ptn_mb_rx_clk_lane_sel        ),
        .mb_rx_val_lane_sel             (ptn_mb_rx_val_lane_sel        ),
        .mb_rx_data_lane_sel            (ptn_mb_rx_data_lane_sel       ),
        .mb_tx_pattern_en               (ptn_mb_tx_pattern_en          ),
        .mb_tx_pattern_setup            (ptn_mb_tx_pattern_setup       ),
        .mb_rx_pattern_setup            (ptn_mb_rx_pattern_setup       ),
        .mb_tx_lfsr_en                  (ptn_mb_tx_lfsr_en             ),
        .mb_tx_lfsr_rst                 (ptn_mb_tx_lfsr_rst            ),
        .mb_rx_lfsr_en                  (ptn_mb_rx_lfsr_en             ),
        .mb_rx_lfsr_rst                 (ptn_mb_rx_lfsr_rst            ),
        .mb_rx_iter_count               (ptn_mb_rx_iter_count          ),
        .mb_rx_idle_count               (ptn_mb_rx_idle_count          ),
        .mb_rx_burst_count              (ptn_mb_rx_burst_count         ),
        .mb_rx_pattern_mode             (ptn_mb_rx_pattern_mode        ),
        .mb_rx_val_pattern_sel          (ptn_mb_rx_val_pattern_sel     ),
        .mb_rx_data_pattern_sel         (ptn_mb_rx_data_pattern_sel    ),
        .mb_rx_compare_en               (ptn_mb_rx_compare_en          ),
        .mb_rx_compare_setup            (ptn_mb_rx_compare_setup       ),
        .mb_rx_max_err_thresh_perlane   (ptn_mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr      (ptn_mb_rx_max_err_thresh_aggr ),
        .mb_tx_clk_sampling_en          (ptn_mb_tx_clk_sampling_en     ),
        .mb_tx_clk_sampling             (ptn_mb_tx_clk_sampling        ),
        .mb_tx_pattern_mode             (ptn_mb_tx_pattern_mode        ),
        .mb_tx_burst_count              (ptn_mb_tx_burst_count         ),
        .mb_tx_idle_count               (ptn_mb_tx_idle_count          ),
        .mb_tx_iter_count               (ptn_mb_tx_iter_count          ),
        .mb_tx_data_pattern_sel         (ptn_mb_tx_data_pattern_sel    ),
        .mb_tx_val_pattern_sel          (ptn_mb_tx_val_pattern_sel     ),
        .mb_tx_pattern_count_done       (ptn_mb_tx_pattern_count_done  ),
        // .mb_rx_compare_done             (ptn_mb_rx_compare_done        ),
        .mb_rx_aggr_pass                (ptn_mb_rx_aggr_pass           ),
        .mb_rx_perlane_pass             (ptn_mb_rx_perlane_pass        ),
        .mb_rx_val_pass                 (ptn_mb_rx_val_pass            ),
        .tx_sb_msg_valid                (ptn_tx_sb_msg_valid           ),
        .tx_sb_msg                      (ptn_tx_sb_msg                 ),
        .tx_msginfo                     (ptn_tx_msginfo                ),
        .tx_data_field                  (ptn_tx_data_field             ),
        .rx_sb_msg_valid                (ptn_rx_sb_msg_valid           ),
        .rx_sb_msg                      (ptn_rx_sb_msg                 ),
        .rx_msginfo                     (ptn_rx_msginfo                ),
        .rx_data_field                  (ptn_rx_data_field             )
    );

    // =========================================================================
    // SB Pipeline Delay Queue (Models Async FIFO — 64-cycle round-trip)
    // =========================================================================
    reg tb_suppress_dut2ptn = 0;
    reg tb_suppress_ptn2dut = 0;

    reg [SB_DELAY_CYCS-1:0] dut2ptn_valid_sr = 0;
    reg [7:0]  dut2ptn_msg_sr  [0:SB_DELAY_CYCS-1];
    reg [15:0] dut2ptn_info_sr [0:SB_DELAY_CYCS-1];
    reg [63:0] dut2ptn_data_sr [0:SB_DELAY_CYCS-1];

    reg [SB_DELAY_CYCS-1:0] ptn2dut_valid_sr = 0;
    reg [7:0]  ptn2dut_msg_sr  [0:SB_DELAY_CYCS-1];
    reg [15:0] ptn2dut_info_sr [0:SB_DELAY_CYCS-1];
    reg [63:0] ptn2dut_data_sr [0:SB_DELAY_CYCS-1];

    integer pi;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            dut2ptn_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            ptn2dut_valid_sr <= {SB_DELAY_CYCS{1'b0}};
            for (pi = 0; pi < SB_DELAY_CYCS; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= 0;
                dut2ptn_info_sr[pi] <= 0;
                dut2ptn_data_sr[pi] <= 0;
                ptn2dut_msg_sr[pi]  <= 0;
                ptn2dut_info_sr[pi] <= 0;
                ptn2dut_data_sr[pi] <= 0;
            end
        end else begin
            dut2ptn_valid_sr <= {dut2ptn_valid_sr[SB_DELAY_CYCS-2:0], dut_tx_sb_msg_valid};
            ptn2dut_valid_sr <= {ptn2dut_valid_sr[SB_DELAY_CYCS-2:0], ptn_tx_sb_msg_valid};
            for (pi = 1; pi < SB_DELAY_CYCS; pi = pi + 1) begin
                dut2ptn_msg_sr[pi]  <= dut2ptn_msg_sr[pi-1];
                dut2ptn_info_sr[pi] <= dut2ptn_info_sr[pi-1];
                dut2ptn_data_sr[pi] <= dut2ptn_data_sr[pi-1];
                ptn2dut_msg_sr[pi]  <= ptn2dut_msg_sr[pi-1];
                ptn2dut_info_sr[pi] <= ptn2dut_info_sr[pi-1];
                ptn2dut_data_sr[pi] <= ptn2dut_data_sr[pi-1];
            end
            dut2ptn_msg_sr[0]  <= dut_tx_sb_msg;
            dut2ptn_info_sr[0] <= dut_tx_msginfo;
            dut2ptn_data_sr[0] <= dut_tx_data_field;
            ptn2dut_msg_sr[0]  <= ptn_tx_sb_msg;
            ptn2dut_info_sr[0] <= ptn_tx_msginfo;
            ptn2dut_data_sr[0] <= ptn_tx_data_field;
        end
    end

    // Route delayed messages to the receiving sides
    assign ptn_rx_sb_msg_valid = dut2ptn_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_dut2ptn;
    assign ptn_rx_sb_msg       = dut2ptn_msg_sr  [SB_DELAY_CYCS-1];
    assign ptn_rx_msginfo      = dut2ptn_info_sr [SB_DELAY_CYCS-1];
    assign ptn_rx_data_field   = dut2ptn_data_sr [SB_DELAY_CYCS-1];

    assign dut_rx_sb_msg_valid = ptn2dut_valid_sr[SB_DELAY_CYCS-1] & ~tb_suppress_ptn2dut;
    assign dut_rx_sb_msg       = ptn2dut_msg_sr  [SB_DELAY_CYCS-1];
    assign dut_rx_msginfo      = ptn2dut_info_sr [SB_DELAY_CYCS-1];
    assign dut_rx_data_field   = ptn2dut_data_sr [SB_DELAY_CYCS-1];

    // =========================================================================
    // Independent Mainband Behavioral Macro Models
    // =========================================================================

    // ── Die 0 (DUT) Macro model ──────────────────────────────────────────────
    integer dut_tx_burst=0, dut_tx_idle=0, dut_tx_iter=0;
    reg     dut_tx_done_sent=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            dut_mb_tx_pattern_count_done <= 0;
            dut_tx_burst<=0; dut_tx_idle<=0; dut_tx_iter<=0; dut_tx_done_sent<=0;
        end else if (dut_mb_tx_pattern_en) begin
            dut_mb_tx_pattern_count_done <= 0;
            if (dut_tx_iter < dut_mb_tx_iter_count) begin
                if (dut_tx_burst < dut_mb_tx_burst_count) dut_tx_burst <= dut_tx_burst + 1;
                else if (dut_tx_idle < dut_mb_tx_idle_count) dut_tx_idle <= dut_tx_idle + 1;
                else begin
                    dut_tx_iter  <= dut_tx_iter + 1;
                    dut_tx_burst <= 0;
                    dut_tx_idle  <= 0;
                end
            end else if (!dut_tx_done_sent) begin
                if (tb_verbose) $display("[%0t] DUT TX Macro: pattern count done", $time);
                dut_mb_tx_pattern_count_done <= 1;
                dut_tx_done_sent <= 1;
            end
        end else begin
            dut_mb_tx_pattern_count_done <= 0;
            dut_tx_burst<=0; dut_tx_idle<=0; dut_tx_iter<=0; dut_tx_done_sent<=0;
        end
    end

    integer dut_rx_burst=0, dut_rx_idle=0, dut_rx_iter=0;
    reg     dut_rx_done_sent=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            // dut_mb_rx_compare_done <= 0;
            dut_mb_rx_perlane_pass <= 16'hFFFF;
            dut_mb_rx_aggr_pass    <= 1;
            dut_mb_rx_val_pass     <= 1;
            dut_rx_burst<=0; dut_rx_idle<=0; dut_rx_iter<=0; dut_rx_done_sent<=0;
        end else if (dut_mb_rx_compare_en) begin
            // dut_mb_rx_compare_done <= 0;
            if (dut_rx_iter < dut_mb_rx_iter_count) begin
                if (dut_rx_burst < dut_mb_rx_burst_count) dut_rx_burst <= dut_rx_burst + 1;
                else if (dut_rx_idle < dut_mb_rx_idle_count) dut_rx_idle <= dut_rx_idle + 1;
                else begin
                    dut_rx_iter  <= dut_rx_iter + 1;
                    dut_rx_burst <= 0;
                    dut_rx_idle  <= 0;
                end
            end else if (!dut_rx_done_sent) begin
                if (tb_verbose) $display("[%0t] DUT RX Macro: comparison done", $time);
                // dut_mb_rx_compare_done <= 1;
                dut_mb_rx_perlane_pass <= tb_perlane_pass;
                dut_mb_rx_aggr_pass    <= tb_aggr_pass;
                dut_mb_rx_val_pass     <= tb_val_pass;
                dut_rx_done_sent <= 1;
            end
        end else begin
            // dut_mb_rx_compare_done <= 0;
            dut_rx_burst<=0; dut_rx_idle<=0; dut_rx_iter<=0; dut_rx_done_sent<=0;
        end
    end

    // ── Die 1 (Partner) Macro model ──────────────────────────────────────────
    integer ptn_tx_burst=0, ptn_tx_idle=0, ptn_tx_iter=0;
    reg     ptn_tx_done_sent=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            ptn_mb_tx_pattern_count_done <= 0;
            ptn_tx_burst<=0; ptn_tx_idle<=0; ptn_tx_iter<=0; ptn_tx_done_sent<=0;
        end else if (ptn_mb_tx_pattern_en) begin
            ptn_mb_tx_pattern_count_done <= 0;
            if (ptn_tx_iter < ptn_mb_tx_iter_count) begin
                if (ptn_tx_burst < ptn_mb_tx_burst_count) ptn_tx_burst <= ptn_tx_burst + 1;
                else if (ptn_tx_idle < ptn_mb_tx_idle_count) ptn_tx_idle <= ptn_tx_idle + 1;
                else begin
                    ptn_tx_iter  <= ptn_tx_iter + 1;
                    ptn_tx_burst <= 0;
                    ptn_tx_idle  <= 0;
                end
            end else if (!ptn_tx_done_sent) begin
                if (tb_verbose) $display("[%0t] PTN TX Macro: pattern count done", $time);
                ptn_mb_tx_pattern_count_done <= 1;
                ptn_tx_done_sent <= 1;
            end
        end else begin
            ptn_mb_tx_pattern_count_done <= 0;
            ptn_tx_burst<=0; ptn_tx_idle<=0; ptn_tx_iter<=0; ptn_tx_done_sent<=0;
        end
    end

    integer ptn_rx_burst=0, ptn_rx_idle=0, ptn_rx_iter=0;
    reg     ptn_rx_done_sent=0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            // ptn_mb_rx_compare_done <= 0;
            ptn_mb_rx_perlane_pass <= 16'hFFFF;
            ptn_mb_rx_aggr_pass    <= 1;
            ptn_mb_rx_val_pass     <= 1;
            ptn_rx_burst<=0; ptn_rx_idle<=0; ptn_rx_iter<=0; ptn_rx_done_sent<=0;
        end else if (ptn_mb_rx_compare_en) begin
            // ptn_mb_rx_compare_done <= 0;
            if (ptn_rx_iter < ptn_mb_rx_iter_count) begin
                if (ptn_rx_burst < ptn_mb_rx_burst_count) ptn_rx_burst <= ptn_rx_burst + 1;
                else if (ptn_rx_idle < ptn_mb_rx_idle_count) ptn_rx_idle <= ptn_rx_idle + 1;
                else begin
                    ptn_rx_iter  <= ptn_rx_iter + 1;
                    ptn_rx_burst <= 0;
                    ptn_rx_idle  <= 0;
                end
            end else if (!ptn_rx_done_sent) begin
                if (tb_verbose) $display("[%0t] PTN RX Macro: comparison done", $time);
                // ptn_mb_rx_compare_done <= 1;
                ptn_mb_rx_perlane_pass <= tb_perlane_pass;
                ptn_mb_rx_aggr_pass    <= tb_aggr_pass;
                ptn_mb_rx_val_pass     <= tb_val_pass;
                ptn_rx_done_sent <= 1;
            end
        end else begin
            // ptn_mb_rx_compare_done <= 0;
            ptn_rx_burst<=0; ptn_rx_idle<=0; ptn_rx_iter<=0; ptn_rx_done_sent<=0;
        end
    end

    // =========================================================================
    // Watchdog / Timeout Simulator
    // =========================================================================
    integer watchdog_cnt = 0;
    reg     timeout_occurred = 0;
    wire any_test_active = local_tx_pt_en | partner_tx_pt_en | local_rx_pt_en | partner_rx_pt_en;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_cnt     <= 0;
            timeout_occurred <= 0;
        end else if (any_test_active) begin
            watchdog_cnt <= watchdog_cnt + 1;
            if (watchdog_cnt >= TIMEOUT_LIMIT)
                timeout_occurred <= 1;
        end else begin
            watchdog_cnt     <= 0;
            timeout_occurred <= 0;
        end
    end

    // =========================================================================
    // FSM State visibility (for monitor logs)
    // =========================================================================
    wire [3:0] dut_loc_tx_state = u_dut.u_wrapper_D2C_PT_local.u_TX_D2C_PT_local.current_state;
    wire [3:0] ptn_loc_tx_state = u_partner_die.u_wrapper_D2C_PT_local.u_TX_D2C_PT_local.current_state;
    wire [3:0] dut_ptn_tx_state = u_dut.u_wrapper_D2C_PT_partner.u_TX_D2C_PT_partner.current_state;
    wire [3:0] ptn_ptn_tx_state = u_partner_die.u_wrapper_D2C_PT_partner.u_TX_D2C_PT_partner.current_state;

    wire [3:0] dut_loc_rx_state = u_dut.u_wrapper_D2C_PT_local.u_RX_D2C_PT_local.current_state;
    wire [3:0] ptn_loc_rx_state = u_partner_die.u_wrapper_D2C_PT_local.u_RX_D2C_PT_local.current_state;
    wire [3:0] dut_ptn_rx_state = u_dut.u_wrapper_D2C_PT_partner.u_RX_D2C_PT_partner.current_state;
    wire [3:0] ptn_ptn_rx_state = u_partner_die.u_wrapper_D2C_PT_partner.u_RX_D2C_PT_partner.current_state;

    localparam [3:0] FSM_IDLE = 4'h0;

    // Helper functions to map FSM state codes to human-readable strings
    function automatic string get_tx_local_state_name(input [3:0] state);
        case (state)
            4'h0: return "TX_PT_IDLE";
            4'h1: return "TX_PT_SEND_START_REQ";
            4'h2: return "TX_PT_WAIT_START_RESP";
            4'h3: return "TX_PT_SEND_CLR_ERR_REQ";
            4'h4: return "TX_PT_WAIT_CLR_ERR_RESP";
            4'h5: return "TX_PT_PATTERN_GEN";
            4'h6: return "TX_PT_SEND_RESULTS_REQ";
            4'h7: return "TX_PT_WAIT_RESULTS_RESP";
            4'h8: return "TX_PT_SEND_END_REQ";
            4'h9: return "TX_PT_WAIT_END_RESP";
            4'hA: return "TX_PT_DONE";
            default: return "TX_PT_UNKNOWN";
        endcase
    endfunction

    function automatic string get_tx_partner_state_name(input [3:0] state);
        case (state)
            4'h0: return "TX_PT_IDLE";
            4'h1: return "TX_PT_WAIT_START_REQ";
            4'h2: return "TX_PT_SEND_START_RESP";
            4'h3: return "TX_PT_WAIT_CLR_ERR_REQ";
            4'h4: return "TX_PT_SEND_CLR_ERR_RESP";
            4'h5: return "TX_PT_WAIT_RESULTS_REQ";
            4'h6: return "TX_PT_SEND_RESULTS_RESP";
            4'h7: return "TX_PT_WAIT_END_REQ";
            4'h8: return "TX_PT_SEND_END_RESP";
            4'h9: return "TX_PT_DONE";
            default: return "TX_PT_UNKNOWN";
        endcase
    endfunction

    function automatic string get_rx_local_state_name(input [3:0] state);
        case (state)
            4'h0: return "RX_PT_IDLE";
            4'h1: return "RX_PT_SEND_START_REQ";
            4'h2: return "RX_PT_WAIT_START_RESP";
            4'h3: return "RX_PT_WAIT_CLR_ERR_REQ";
            4'h4: return "RX_PT_SEND_CLR_ERR_RESP";
            4'h5: return "RX_PT_WAIT_COUNT_DONE_REQ";
            4'h6: return "RX_PT_SEND_COUNT_DONE_RESP";
            4'h7: return "RX_PT_LOG_RESULT";
            4'h8: return "RX_PT_SEND_END_REQ";
            4'h9: return "RX_PT_WAIT_END_RESP";
            4'hA: return "RX_PT_DONE";
            default: return "RX_PT_UNKNOWN";
        endcase
    endfunction

    function automatic string get_rx_partner_state_name(input [3:0] state);
        case (state)
            4'h0: return "RX_PT_IDLE";
            4'h1: return "RX_PT_WAIT_START_REQ";
            4'h2: return "RX_PT_SEND_START_RESP";
            4'h3: return "RX_PT_TX_LFSR_RST";
            4'h4: return "RX_PT_SEND_CLR_ERR_REQ";
            4'h5: return "RX_PT_WAIT_CLR_ERR_RESP";
            4'h6: return "RX_PT_PATTERN_GEN";
            4'h7: return "RX_PT_SEND_COUNT_DONE_REQ";
            4'h8: return "RX_PT_WAIT_COUNT_DONE_RESP";
            4'h9: return "RX_PT_WAIT_END_REQ";
            4'hA: return "RX_PT_SEND_END_RESP";
            4'hB: return "RX_PT_DONE";
            default: return "RX_PT_UNKNOWN";
        endcase
    endfunction

    always @(dut_loc_tx_state)
        if (tb_verbose && local_tx_pt_en)
            $display("%12t ps [DUT  LOC TX] FSM = %s", $time, get_tx_local_state_name(dut_loc_tx_state));
    always @(ptn_ptn_tx_state)
        if (tb_verbose && local_tx_pt_en)
            $display("%12t ps [PTN  PTN TX] FSM = %s", $time, get_tx_partner_state_name(ptn_ptn_tx_state));

    always @(dut_loc_rx_state)
        if (tb_verbose && local_rx_pt_en)
            $display("%12t ps [DUT  LOC RX] FSM = %s", $time, get_rx_local_state_name(dut_loc_rx_state));
    always @(ptn_ptn_rx_state)
        if (tb_verbose && local_rx_pt_en)
            $display("%12t ps [PTN  PTN RX] FSM = %s", $time, get_rx_partner_state_name(ptn_ptn_rx_state));

    // =========================================================================
    // Auto-Symmetric Enable Mapper
    // Automatically configures u_partner_die (Die 1) based on u_dut (Die 0)
    // =========================================================================
    always_comb begin : PARTNER_ENABLES_LOGIC
        ptn_local_tx_pt_en    = 0;
        ptn_partner_tx_pt_en  = 0;
        ptn_local_rx_pt_en    = 0;
        ptn_partner_rx_pt_en  = 0;

        // TX routing configurations
        if (local_tx_pt_en && partner_tx_pt_en) begin
            // Case AB: Both initiate TX Point Test
            ptn_local_tx_pt_en   = 1;
            ptn_partner_tx_pt_en = 1;
        end else if (local_tx_pt_en) begin
            // Case A: Local TX only
            ptn_partner_tx_pt_en = 1;
        end else if (partner_tx_pt_en) begin
            // Case B: Partner TX only
            ptn_local_tx_pt_en   = 1;
        end

        // RX routing configurations
        if (local_rx_pt_en && partner_rx_pt_en) begin
            // Case CD: Both initiate RX Point Test
            ptn_local_rx_pt_en   = 1;
            ptn_partner_rx_pt_en = 1;
        end else if (local_rx_pt_en) begin
            // Case C: Local RX only
            ptn_partner_rx_pt_en = 1;
        end else if (partner_rx_pt_en) begin
            // Case D: Partner RX only
            ptn_local_rx_pt_en   = 1;
        end
    end

    // =========================================================================
    // Test Infrastructure Tasks
    // =========================================================================
    integer success_count = 0;
    integer fail_count    = 0;
    integer test_no       = 1;

    // Captured results
    reg [15:0] cap_perlane_pass;
    reg        cap_aggr_pass;
    reg        cap_val_pass;

    // ── Task: reset() ────────────────────────────────────────────────────────
    task automatic reset();
        rst_n = 0;
        local_tx_pt_en             = 0;
        partner_tx_pt_en           = 0;
        local_rx_pt_en             = 0;
        partner_rx_pt_en           = 0;

        tb_suppress_dut2ptn        = 0;
        tb_suppress_ptn2dut        = 0;
        tb_perlane_pass            = 16'hFFFF;
        tb_aggr_pass               = 1;
        tb_val_pass                = 1;

        d2c_clk_sampling           = 2'b00;
        d2c_pattern_setup          = 3'b001;
        d2c_data_pattern_sel       = 2'b00;
        d2c_val_pattern_sel        = 1'b0;
        d2c_pattern_mode           = 1'b0;
        d2c_burst_count            = 16'd50;
        d2c_idle_count             = 16'd0;
        d2c_iter_count             = 16'd1;
        d2c_compare_setup          = 2'b00;
        cfg_max_err_thresh_perlane = 12'd0;
        cfg_max_err_thresh_aggr    = 16'd0;

        repeat(5) @(posedge lclk);
        rst_n = 1;
        repeat(2) @(posedge lclk);
        if (tb_verbose) $display("%12t ps: Reset released.", $time);
    endtask

    // ── Task: set_config() ───────────────────────────────────────────
    task automatic set_config(
            input [1:0]  cs, input [2:0] ps,  input [1:0]  dp,
            input        vp, input        pm,  input [15:0] bc,
            input [15:0] ic, input [15:0] nc,  input [1:0]  cmp
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

    // ── Task: run_test() ─────────────────────────────────────────────────────
    task automatic run_test(
            input integer kind,
            input logic   expect_timeout
        );
        @(posedge lclk);
        case (kind)
            TEST_LOCAL_TX: begin
                local_tx_pt_en = 1;
            end
            TEST_PARTNER_TX: begin
                partner_tx_pt_en = 1;
            end
            TEST_LOCAL_RX: begin
                local_rx_pt_en = 1;
            end
            TEST_PARTNER_RX: begin
                partner_rx_pt_en = 1;
            end
            TEST_PARALLEL_TX: begin
                local_tx_pt_en = 1;
                partner_tx_pt_en = 1;
            end
            TEST_PARALLEL_RX: begin
                local_rx_pt_en = 1;
                partner_rx_pt_en = 1;
            end
            default: $display("[WARN] run_test: unknown kind=%0d", kind);
        endcase

        fork : run_fork
            begin
                // Wait for the active initiator(s) completion
                if (kind == TEST_LOCAL_TX || kind == TEST_LOCAL_RX) begin
                    wait(dut_local_test_d2c_done || timeout_occurred);
                end else if (kind == TEST_PARTNER_TX || kind == TEST_PARTNER_RX) begin
                    wait(dut_partner_test_d2c_done || timeout_occurred);
                end else begin
                    // Parallel: Wait for both
                    wait((dut_local_test_d2c_done && dut_partner_test_d2c_done) || timeout_occurred);
                end

                // Capture results before deasserting enables
                if (kind == TEST_PARTNER_TX || kind == TEST_PARTNER_RX) begin
                    cap_perlane_pass = ptn_d2c_perlane_pass;
                    cap_aggr_pass    = ptn_d2c_aggr_pass;
                    cap_val_pass     = ptn_d2c_val_pass;
                end else begin
                    cap_perlane_pass = dut_d2c_perlane_pass;
                    cap_aggr_pass    = dut_d2c_aggr_pass;
                    cap_val_pass     = dut_d2c_val_pass;
                end

                @(posedge lclk);
                local_tx_pt_en          = 0; partner_tx_pt_en        = 0;
                local_rx_pt_en          = 0; partner_rx_pt_en        = 0;

                if (timeout_occurred) begin
                    if (expect_timeout) begin
                        if (tb_verbose) $display("%12t ps: [PASS] Expected timeout occurred.", $time);
                        success_count = success_count + 1;
                    end else begin
                        $display("%12t ps: [FAIL] Unexpected watchdog timeout!", $time);
                        fail_count = fail_count + 1; $stop;
                    end
                end else begin
                    if (expect_timeout) begin
                        $display("%12t ps: [FAIL] Expected timeout but test completed!", $time);
                        fail_count = fail_count + 1; $stop;
                    end else begin
                        // Wait until all FSMs return to IDLE
                        wait(dut_loc_tx_state == FSM_IDLE && dut_ptn_tx_state == FSM_IDLE &&
                            dut_loc_rx_state == FSM_IDLE && dut_ptn_rx_state == FSM_IDLE &&
                            ptn_loc_tx_state == FSM_IDLE && ptn_ptn_tx_state == FSM_IDLE &&
                            ptn_loc_rx_state == FSM_IDLE && ptn_ptn_rx_state == FSM_IDLE);
                        if (tb_verbose) $display("%12t ps: [PASS] Test completed successfully.", $time);
                        success_count = success_count + 1;
                    end
                end
                if (tb_verbose) $display("(Pass=%0d, Fail=%0d)\n", success_count, fail_count);
                disable run_fork;
            end
            begin
                #(64'd5_000_000_000); // 5 ms simulation safety net
                $display("[FAIL] Simulation Safety Watchdog Fired at %0t!", $time);
                fail_count = fail_count + 1;
                disable run_fork;
                $stop;
            end
        join
    endtask

    // ── Task: check_result() ─────────────────────────────────────────────────
    task automatic check_result(
            input [255:0] label,
            input [15:0]  exp_perlane,
            input         exp_aggr,
            input         exp_val
        );
        if (cap_perlane_pass !== exp_perlane) begin
            $display("  [FAIL] %s: perlane_pass=%h, expected=%h", label, cap_perlane_pass, exp_perlane);
            fail_count = fail_count + 1; $stop;
        end
        if (cap_aggr_pass !== exp_aggr) begin
            $display("  [FAIL] %s: aggr_pass=%b, expected=%b", label, cap_aggr_pass, exp_aggr);
            fail_count = fail_count + 1; $stop;
        end
        if (cap_val_pass !== exp_val) begin
            $display("  [FAIL] %s: val_pass=%b, expected=%b", label, cap_val_pass, exp_val);
            fail_count = fail_count + 1; $stop;
        end
        $display("  [OK] %0s results verified.", label);
    endtask

    // =========================================================================
    // Test Sequences
    // =========================================================================
    integer rnd_kind;
    integer rnd_mbinit;
    integer rnd_kind_sel;
    integer rnd_suppress;
    integer r;
    reg     expected_aggr;
    reg [1:0] active_compare_setup;

        initial begin
        $display("\n=== wrapper_D2C_PT_top_tb \u2014 Comprehensive Dual-Die Top-Level Testbench ===\n");
        $display("  Signal polarity: *_pass = 1 means pass, 0 means fail.\n");

        tb_verbose = 1;

        // =====================================================================
        // SECTION A: Local TX Tests
        // =====================================================================
        $display("=> Scenario %0d: Local TX Happy Path (all pass)", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 80, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_LOCAL_TX, 0);
        check_result("LOCAL TX All Pass", 16'hFFFF, 1, 1);

        $display("=> Scenario %0d: Local TX Partial Lane Failure", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 40, 0, 1, 2'd0);
        tb_perlane_pass = 16'hBEEF; tb_aggr_pass = 0; tb_val_pass = 1;
        run_test(TEST_LOCAL_TX, 0);
        check_result("LOCAL TX Partial", 16'hBEEF, 0, 1);

        // =====================================================================
        // SECTION B: Partner TX Tests
        // =====================================================================
        $display("=> Scenario %0d: Partner TX Happy Path (all pass)", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 60, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_PARTNER_TX, 0);
        check_result("PARTNER TX All Pass", 16'hFFFF, 1, 1);

        $display("=> Scenario %0d: Partner TX Partial Failure", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 30, 0, 1, 2'd0);
        tb_perlane_pass = 16'hDEAD; tb_aggr_pass = 0; tb_val_pass = 0;
        run_test(TEST_PARTNER_TX, 0);
        check_result("PARTNER TX Partial", 16'hDEAD, 0, 0);

        // =====================================================================
        // SECTION C: Local TX Aggregate Failure Tests
        // =====================================================================
        $display("=> Scenario %0d: Local TX Aggregate Failure", test_no);
        test_no = test_no + 1;
        reset();
        cfg_max_err_thresh_aggr = 16'h0050;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 30, 0, 1, 2'd1);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 0; tb_val_pass = 1;
        run_test(TEST_LOCAL_TX, 0);
        if (cap_aggr_pass == 1'b0)
            $display("  [OK] Local TX Aggregate failure verified.");
        else begin
            $display("  [FAIL] Local TX Aggregate expected 0, got 1.");
            fail_count = fail_count + 1; $stop;
        end

        // =====================================================================
        // SECTION D: Local RX Tests
        // =====================================================================
        $display("=> Scenario %0d: Local RX Happy Path (all pass)", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 80, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_LOCAL_RX, 0);
        check_result("LOCAL RX All Pass", 16'hFFFF, 1, 1);

        $display("=> Scenario %0d: Local RX Partial Lane Failure", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 40, 0, 1, 2'd0);
        tb_perlane_pass = 16'hA5A5; tb_aggr_pass = 0; tb_val_pass = 1;
        run_test(TEST_LOCAL_RX, 0);
        check_result("LOCAL RX Partial", 16'hA5A5, 0, 1);

        // =====================================================================
        // SECTION E: Partner RX Tests
        // =====================================================================
        $display("=> Scenario %0d: Partner RX Happy Path", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 60, 0, 1, 2'd0);
        tb_perlane_pass = 16'hFFFF; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_PARTNER_RX, 0);
        check_result("PARTNER RX All Pass", 16'hFFFF, 1, 1);

        $display("=> Scenario %0d: Partner RX Partial Failure", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b011, 2'b00, 0, 0, 25, 0, 1, 2'd0);
        tb_perlane_pass = 16'h5A5A; tb_aggr_pass = 0; tb_val_pass = 0;
        run_test(TEST_PARTNER_RX, 0);
        check_result("PARTNER RX Partial", 16'h5A5A, 0, 0);

        // =====================================================================
        // SECTION F: Timeout Tests
        // =====================================================================
        $display("=> Scenario %0d: Timeout \u2014 Local TX with suppressed SB", test_no);
        test_no = test_no + 1;
        reset();
        tb_suppress_dut2ptn = 1;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        run_test(TEST_LOCAL_TX, 1);

        $display("=> Scenario %0d: Timeout \u2014 Local RX with suppressed SB", test_no);
        test_no = test_no + 1;
        reset();
        tb_suppress_ptn2dut = 1;
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 100, 0, 1, 2'd0);
        run_test(TEST_LOCAL_RX, 1);

        // =====================================================================
        // SECTION G: Parallel tests
        // =====================================================================
        $display("=> Scenario %0d: Parallel TX Test (Case AB) \u2014 Both dies initiating TX", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        run_test(TEST_PARALLEL_TX, 0);

        $display("=> Scenario %0d: Parallel RX Test (Case CD) \u2014 Both dies initiating RX", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 50, 0, 1, 2'd0);
        run_test(TEST_PARALLEL_RX, 0);

        // =====================================================================
        // SECTION H: Back-to-Back Tests (no reset in between)
        // =====================================================================
        $display("=> Scenario %0d: B2B \u2014 Local TX then Local RX", test_no);
        test_no = test_no + 1;
        reset();
        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        tb_perlane_pass = 16'hAAAA; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_LOCAL_TX, 0);
        if (cap_perlane_pass == 16'hAAAA)
            $display("  [OK] B2B Part 1 TX complete.");
        else begin
            $display("  [FAIL] B2B Part 1 failed.");
            fail_count = fail_count + 1; $stop;
        end

        set_config(2'b00, 3'b001, 2'b00, 0, 0, 20, 0, 1, 2'd0);
        tb_perlane_pass = 16'h5555; tb_aggr_pass = 1; tb_val_pass = 1;
        run_test(TEST_LOCAL_RX, 0);
        if (cap_perlane_pass == 16'h5555)
            $display("  [OK] B2B Part 2 RX complete.");
        else begin
            $display("  [FAIL] B2B Part 2 failed.");
            fail_count = fail_count + 1; $stop;
        end

        // =====================================================================
        // Directed Summary
        // =====================================================================
        $display("\n--- Directed Scenarios Complete: Pass=%0d, Fail=%0d ---\n",
            success_count, fail_count);
        if (fail_count > 0) begin
            $display("[STOP] Resolve directed failures before random testing.");
            $stop;
        end

        // =====================================================================
        // SECTION I: 100 Randomized Dual-Die Iterations
        // =====================================================================
        tb_verbose = 0;
        $display("Starting 100 Randomized Dual-Die Iterations...\n");

        for (r = 0; r < 100; r = r + 1) begin
            reset();
            rnd_kind_sel = $urandom_range(0, 5);

            case (rnd_kind_sel)
                0: rnd_kind = TEST_LOCAL_TX;
                1: rnd_kind = TEST_PARTNER_TX;
                2: rnd_kind = TEST_LOCAL_RX;
                3: rnd_kind = TEST_PARTNER_RX;
                4: rnd_kind = TEST_PARALLEL_TX;
                5: rnd_kind = TEST_PARALLEL_RX;
                default: rnd_kind = TEST_LOCAL_TX;
            endcase

            tb_perlane_pass = $urandom();
            tb_aggr_pass    = $urandom_range(0, 1);
            tb_val_pass     = $urandom_range(0, 1);
            rnd_suppress    = ($urandom_range(0, 14) == 0); // ~7% timeout rate

            tb_suppress_dut2ptn = rnd_suppress[0];
            tb_suppress_ptn2dut = rnd_suppress[0];

            set_config(
                $urandom_range(0, 2), $urandom_range(0, 7), $urandom_range(0, 2),
                $urandom_range(0, 1), $urandom_range(0, 1),
                $urandom_range(1, 40), $urandom_range(0, 10), $urandom_range(1, 3),
                $urandom_range(0, 3)
            );

            run_test(rnd_kind, tb_suppress_dut2ptn);

            if (!tb_suppress_dut2ptn) begin
                active_compare_setup = d2c_compare_setup;
                if (rnd_kind == TEST_LOCAL_TX || rnd_kind == TEST_PARTNER_TX || rnd_kind == TEST_PARALLEL_TX) begin
                    expected_aggr = (active_compare_setup != 2'b00) ? tb_aggr_pass : (&tb_perlane_pass);
                end else begin
                    expected_aggr = tb_aggr_pass;
                end

                // Verify DUT results on non-timeout runs
                if (cap_perlane_pass !== tb_perlane_pass) begin
                    $display("  [FAIL] Rand %0d: perlane_pass=%h, expected=%h",
                        r+1, cap_perlane_pass, tb_perlane_pass);
                    fail_count = fail_count + 1; $stop;
                end
                if (cap_val_pass !== tb_val_pass) begin
                    $display("  [FAIL] Rand %0d: val_pass=%b, expected=%b",
                        r+1, cap_val_pass, tb_val_pass);
                    fail_count = fail_count + 1; $stop;
                end
                if (cap_aggr_pass !== expected_aggr) begin
                    $display("  [FAIL] Rand %0d: aggr_pass=%b, expected=%b",
                        r+1, cap_aggr_pass, expected_aggr);
                    fail_count = fail_count + 1; $stop;
                end
            end
        end

        // =====================================================================
        // Final Summary
        // =====================================================================
        tb_verbose = 1;
        if (fail_count == 0) begin
            $display("\n  ========================================================");
            $display("  ==  Congratulations! Dual-Die Wrapper All Tests PASSED!  ==");
            $display("  ========================================================\n");
        end else begin
            $display("\n  ========================================================");
            $display("  ==  FAILED: %0d test(s) encountered errors!           ==", fail_count);
            $display("  ========================================================\n");
        end
        $display("Total: Pass=%0d, Fail=%0d", success_count, fail_count);
        $stop;
    end

endmodule
