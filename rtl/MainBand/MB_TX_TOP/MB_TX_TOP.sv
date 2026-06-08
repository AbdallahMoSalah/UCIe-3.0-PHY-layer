// =============================================================================
// Module  : MB_TX_TOP
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Top-level wrapper for the Main-Band Transmit (TX) datapath.
//
//  Instantiated sub-modules
//  -------------------------
//  1. Mapper             – maps the parallel protocol data onto 16 physical lanes
//  2. LFSR_TX            – scrambles / patterns each lane and generates valid_frame_en
//  3. VALID_TX           – generates the 32-bit valid-lane word (TVLD)
//  4. MB_SERIALIZER      – one instance per data lane  (lanes 0-15, 16 total)
//  5. MB_SERIALIZER      – one instance for the valid lane
//  6. MB_PLL             – generates high-speed PLL clock
//  7. CLK_PATTERN_GEN_TX – generates differential clock pattern (o_clk_p/n)
//                          controlled by clk_pattern_en / clk_embedded_en
//
//  Clock domains
//  -------------
//  o_mb_clk              : Main-band functional clock  (used by Mapper, LFSR_TX, VALID_TX
//                and the slow side of every serializer)
//  o_clk_p     : Differential clock from CLK_PATTERN_GEN_TX → feeds MB_PLL
//  o_pll_clk   : High-speed PLL output clock (used by the fast side of every
//                serializer – DDR serialization)
// =============================================================================

module MB_TX_TOP #(
    parameter DATA_WIDTH = 32,   // Width of each parallel lane word
    parameter NUM_LANES  = 16,   // Number of data lanes
    parameter N_BYTES    = 64    // Byte width of the raw protocol bus
)(
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
   
    input  logic                    i_rst_n,           // Active-low synchronous reset
    output logic                    o_pll_clk,         // High-speed PLL clock (DDR)
    output real                      period,
    // -------------------------------------------------------------------------
    // Mapper inputs  (from protocol / adapter layer)
    // -------------------------------------------------------------------------
    input  logic [8*N_BYTES-1:0]    i_raw_data,        // Raw protocol data bus
    input  logic                    i_mapper_en,       // Enable the mapper
    input  logic [2:0]              i_width_deg,       // Lane-width degradation code
    input  logic                    i_lp_irdy,         // Adapter: data is ready
    input  logic                    i_lp_valid,        // Adapter: data is valid

    // -------------------------------------------------------------------------
    // LFSR_TX control inputs  (from Main-Band controller / state machine)
    // -------------------------------------------------------------------------
    input  logic [2:0]              i_lfsr_state,           // Requested LFSR state
    input  logic                    i_reversal_en,          // Physical lane reversal
    input  logic                    i_active_state_entered, // Pulse: DATA_TRANSFER entered

    // -------------------------------------------------------------------------
    // VALID_TX control inputs
    // -------------------------------------------------------------------------
    input  logic                    i_valid_pattern_en, // Trigger 32-cycle TVLD pattern

    // -------------------------------------------------------------------------
    // Serialized TX outputs (one bit per lane, DDR)
    // -------------------------------------------------------------------------
    output logic [NUM_LANES-1:0]    o_tx_data,         // Serialized data lanes 0-15
    output logic                    o_tx_valid,        // Serialized valid lane

    // -------------------------------------------------------------------------
    // MB_PLL control inputs
    // -------------------------------------------------------------------------
    input  logic                    i_pll_en,          // Enable the PLL
    input  logic [1:0]              i_pll_speed_sel,   // PLL speed select (00=2G, 01=4G, 10=8G, 11=16G)

    // -------------------------------------------------------------------------
    // CLK_PATTERN_GEN_TX control inputs
    // -------------------------------------------------------------------------
    input  logic                    i_clk_pattern_en,  // Trigger the 128-UI clock pattern burst
    input  logic                    i_clk_embedded_en, // Enable continuous embedded-clock mode

    // -------------------------------------------------------------------------
    // CLK_PATTERN_GEN_TX outputs
    // -------------------------------------------------------------------------
    output logic                   o_mb_clk          ,          // Main-band clock
    output logic                    o_clk_p,           // Differential clock + (also → MB_PLL ref)
    output logic                    o_clk_n,           // Differential clock −  (phase_delay of o_clk_p)
    output logic                    o_clk_track,       // Debug / tracking signal
    output logic                    o_clk_done,        // Pulse: clock-pattern burst complete

    // -------------------------------------------------------------------------
    // Status / handshake outputs
    // -------------------------------------------------------------------------
    output logic                    o_mapper_ready,    // Mapper accepted data (pl_trdy)
    output logic                    o_lfsr_tx_done,    // LFSR / ID phase complete pulse
    output logic                    o_valid_done       // VALID_TX pattern-done pulse
);

    // =========================================================================
    // Internal logics
    // =========================================================================

    // ----------- Mapper → LFSR_TX (16 parallel lane words) ------------------
    logic [DATA_WIDTH-1:0] mapper_lane [0:15];

    // Flatten the individual Mapper output ports into the array expected by
    // LFSR_TX.  (Mapper uses flat port names; LFSR_TX uses an unpacked array.)
    logic [DATA_WIDTH-1:0] mapper_lane_0,  mapper_lane_1,  mapper_lane_2,  mapper_lane_3;
    logic [DATA_WIDTH-1:0] mapper_lane_4,  mapper_lane_5,  mapper_lane_6,  mapper_lane_7;
    logic [DATA_WIDTH-1:0] mapper_lane_8,  mapper_lane_9,  mapper_lane_10, mapper_lane_11;
    logic [DATA_WIDTH-1:0] mapper_lane_12, mapper_lane_13, mapper_lane_14, mapper_lane_15;

    assign mapper_lane[0]  = mapper_lane_0;
    assign mapper_lane[1]  = mapper_lane_1;
    assign mapper_lane[2]  = mapper_lane_2;
    assign mapper_lane[3]  = mapper_lane_3;
    assign mapper_lane[4]  = mapper_lane_4;
    assign mapper_lane[5]  = mapper_lane_5;
    assign mapper_lane[6]  = mapper_lane_6;
    assign mapper_lane[7]  = mapper_lane_7;
    assign mapper_lane[8]  = mapper_lane_8;
    assign mapper_lane[9]  = mapper_lane_9;
    assign mapper_lane[10] = mapper_lane_10;
    assign mapper_lane[11] = mapper_lane_11;
    assign mapper_lane[12] = mapper_lane_12;
    assign mapper_lane[13] = mapper_lane_13;
    assign mapper_lane[14] = mapper_lane_14;
    assign mapper_lane[15] = mapper_lane_15;

    // ----------- Mapper control outputs -------------------------------------
    logic        mapper_scramble_en; // Mapper → LFSR_TX: enable scrambling

    // ----------- LFSR_TX → Serializers (scrambled lane words) ---------------
    logic [DATA_WIDTH-1:0] lfsr_lane [0:15];

    // valid_frame_en: LFSR_TX → VALID_TX (indicates active frame period)
    logic        lfsr_valid_frame_en;

    // ----------- VALID_TX → Valid-lane serializer ----------------------------
    logic [31:0] valid_word;        // 32-bit TVLD pattern word

    // ----------- Serializer enables -----------------------------------------
    logic        lfsr_ser_en;      // LFSR_TX.o_ser_en_lfsr  → data-lane serializers
    logic        valid_ser_en;     // VALID_TX.ser_en_o       → valid-lane serializer

    // =========================================================================
    // 0a. MB_PLL  (reference = o_clk_p from CLK_PATTERN_GEN_TX)
    // =========================================================================
    MB_PLL u_mb_pll (        
        .en        (i_pll_en),
        .speed_sel (i_pll_speed_sel),
        .clk       (o_pll_clk),
        .period    (period)
    );

    ClkDiv #(
    .RangeWidth (8)
    ) u_ClkDiv  (
    .i_ref_clk (o_pll_clk),
    .i_rst_n   (i_rst_n),
    .i_clk_en  (1),
    .i_div_ratio (16),
    .o_div_clk (o_mb_clk          )
    );

    // =========================================================================
    // 0b. CLK_PATTERN_GEN_TX  (clocked by MB_PLL output)
    // =========================================================================
    CLK_PATTERN_GEN_TX u_clk_pattern_gen (
        .i_clk           (o_pll_clk),    // driven by MB_PLL high-speed output clock
        .i_rst_n         (i_rst_n),
        .clk_pattern_en  (i_clk_pattern_en),
        .clk_embedded_en (i_clk_embedded_en),
        .i_period        (period),        // MB_PLL period → half-period delay for o_clk_n
        .o_clk_p         (o_clk_p),      // → top-level output
        .o_clk_n         (o_clk_n),
        .track           (o_clk_track),
        .o_done          (o_clk_done)
    );

    // =========================================================================
    // 1.  Mapper
    // =========================================================================
    Mapper #(
        .WIDTH     (DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) u_mapper (
        .i_clk           (o_mb_clk), 
        .i_rst_n         (i_rst_n),
        .i_in_data       (i_raw_data),
        .mapper_en       (i_mapper_en),
        .i_width_deg_map (i_width_deg),
        .lp_irdy         (i_lp_irdy),
        .lp_valid        (i_lp_valid),

        .o_lane_0        (mapper_lane_0),
        .o_lane_1        (mapper_lane_1),
        .o_lane_2        (mapper_lane_2),
        .o_lane_3        (mapper_lane_3),
        .o_lane_4        (mapper_lane_4),
        .o_lane_5        (mapper_lane_5),
        .o_lane_6        (mapper_lane_6),
        .o_lane_7        (mapper_lane_7),
        .o_lane_8        (mapper_lane_8),
        .o_lane_9        (mapper_lane_9),
        .o_lane_10       (mapper_lane_10),
        .o_lane_11       (mapper_lane_11),
        .o_lane_12       (mapper_lane_12),
        .o_lane_13       (mapper_lane_13),
        .o_lane_14       (mapper_lane_14),
        .o_lane_15       (mapper_lane_15),

        .out_scramble_en (mapper_scramble_en),
        .mapper_ready    (o_mapper_ready)
    );

    // =========================================================================
    // 2.  LFSR_TX
    // =========================================================================
    LFSR_TX #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_tx (
        .i_clk                  (o_mb_clk), 
        .i_rst_n                (i_rst_n),
        .i_state                (i_lfsr_state),
        .i_scramble_en          (mapper_scramble_en),
        .i_width_deg_lfsr       (i_width_deg),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),

        .i_lane                 (mapper_lane),
        .o_lane                 (lfsr_lane),

        .o_ser_en_lfsr          (lfsr_ser_en),
        .o_Lfsr_tx_done         (o_lfsr_tx_done),
        .o_valid_frame_en       (lfsr_valid_frame_en)
    );

    // =========================================================================
    // 3.  VALID_TX
    // =========================================================================
    VALID_TX u_valid_tx (
        .i_clk            (o_mb_clk), 
        .i_rst_n          (i_rst_n),
        .valid_pattern_en (i_valid_pattern_en),
        .valid_frame_en   (lfsr_valid_frame_en),

        .valid_ser_en         (valid_ser_en),
        .O_done           (o_valid_done),
        .o_TVLD_L         (valid_word)
    );

    // =========================================================================
    // 4.  Data-lane serializers  (one MB_SERIALIZER per data lane, 16 total)
    // =========================================================================
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin : gen_data_ser
            MB_SERIALIZER #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_data_ser (
                .mb_clk  (o_mb_clk), 
                .PLL_clk (o_pll_clk),
                .i_rst_n (i_rst_n),
                .Ser_en  (lfsr_ser_en),       // enable from LFSR_TX
                .in_data (lfsr_lane[lane_idx]),
                .SER_out (o_tx_data[lane_idx])
            );
        end
    endgenerate

    // =========================================================================
    // 5.  Valid-lane serializer  (one MB_SERIALIZER for the TVLD lane)
    // =========================================================================
    MB_SERIALIZER #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_ser (
        .mb_clk  (o_mb_clk), 
        .PLL_clk (o_pll_clk),
        .i_rst_n (i_rst_n),
        .Ser_en  (valid_ser_en),          // enable from VALID_TX
        .in_data (valid_word),
        .SER_out (o_tx_valid)
    );

endmodule
