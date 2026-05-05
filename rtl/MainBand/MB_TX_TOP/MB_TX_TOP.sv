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
//  i_mb_clk    : Main-band functional clock  (used by Mapper, LFSR_TX, VALID_TX
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
    input  wire                    i_mb_clk,          // Main-band clock
    input  wire                    i_rst_n,           // Active-low synchronous reset
    output wire                    o_pll_clk,         // High-speed PLL clock (DDR)

    // -------------------------------------------------------------------------
    // Mapper inputs  (from protocol / adapter layer)
    // -------------------------------------------------------------------------
    input  wire [8*N_BYTES-1:0]    i_raw_data,        // Raw protocol data bus
    input  wire                    i_mapper_en,       // Enable the mapper
    input  wire [2:0]              i_width_deg,       // Lane-width degradation code
    input  wire                    i_lp_irdy,         // Adapter: data is ready
    input  wire                    i_lp_valid,        // Adapter: data is valid

    // -------------------------------------------------------------------------
    // LFSR_TX control inputs  (from Main-Band controller / state machine)
    // -------------------------------------------------------------------------
    input  wire [2:0]              i_lfsr_state,           // Requested LFSR state
    input  wire                    i_reversal_en,          // Physical lane reversal
    input  wire                    i_active_state_entered, // Pulse: DATA_TRANSFER entered

    // -------------------------------------------------------------------------
    // VALID_TX control inputs
    // -------------------------------------------------------------------------
    input  wire                    i_valid_pattern_en, // Trigger 32-cycle TVLD pattern

    // -------------------------------------------------------------------------
    // Serialized TX outputs (one bit per lane, DDR)
    // -------------------------------------------------------------------------
    output wire [NUM_LANES-1:0]    o_tx_data,         // Serialized data lanes 0-15
    output wire                    o_tx_valid,        // Serialized valid lane

    // -------------------------------------------------------------------------
    // MB_PLL control inputs
    // -------------------------------------------------------------------------
    input  wire                    i_pll_en,          // Enable the PLL
    input  wire [1:0]              i_pll_speed_sel,   // PLL speed select (00=2G, 01=4G, 10=8G, 11=16G)

    // -------------------------------------------------------------------------
    // CLK_PATTERN_GEN_TX control inputs
    // -------------------------------------------------------------------------
    input  wire                    i_clk_pattern_en,  // Trigger the 128-UI clock pattern burst
    input  wire                    i_clk_embedded_en, // Enable continuous embedded-clock mode

    // -------------------------------------------------------------------------
    // CLK_PATTERN_GEN_TX outputs
    // -------------------------------------------------------------------------
    output wire                    o_clk_p,           // Differential clock + (also → MB_PLL ref)
    output wire                    o_clk_n,           // Differential clock −  (phase_delay of o_clk_p)
    output wire                    o_clk_track,       // Debug / tracking signal
    output wire                    o_clk_done,        // Pulse: clock-pattern burst complete

    // -------------------------------------------------------------------------
    // Status / handshake outputs
    // -------------------------------------------------------------------------
    output wire                    o_mapper_ready,    // Mapper accepted data (pl_trdy)
    output wire                    o_lfsr_tx_done,    // LFSR / ID phase complete pulse
    output wire                    o_valid_done       // VALID_TX pattern-done pulse
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // ----------- Mapper → LFSR_TX (16 parallel lane words) ------------------
    wire [DATA_WIDTH-1:0] mapper_lane [0:15];

    // Flatten the individual Mapper output ports into the array expected by
    // LFSR_TX.  (Mapper uses flat port names; LFSR_TX uses an unpacked array.)
    wire [DATA_WIDTH-1:0] mapper_lane_0,  mapper_lane_1,  mapper_lane_2,  mapper_lane_3;
    wire [DATA_WIDTH-1:0] mapper_lane_4,  mapper_lane_5,  mapper_lane_6,  mapper_lane_7;
    wire [DATA_WIDTH-1:0] mapper_lane_8,  mapper_lane_9,  mapper_lane_10, mapper_lane_11;
    wire [DATA_WIDTH-1:0] mapper_lane_12, mapper_lane_13, mapper_lane_14, mapper_lane_15;

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
    wire        mapper_scramble_en; // Mapper → LFSR_TX: enable scrambling

    // ----------- LFSR_TX → Serializers (scrambled lane words) ---------------
    wire [DATA_WIDTH-1:0] lfsr_lane [0:15];

    // valid_frame_en: LFSR_TX → VALID_TX (indicates active frame period)
    wire        lfsr_valid_frame_en;

    // ----------- VALID_TX → Valid-lane serializer ----------------------------
    wire [31:0] valid_word;        // 32-bit TVLD pattern word

    // =========================================================================
    // 0a. CLK_PATTERN_GEN_TX  (must come first – generates the PLL reference clock)
    // =========================================================================
    CLK_PATTERN_GEN_TX u_clk_pattern_gen (
        .i_clk           (i_mb_clk),
        .i_rst_n         (i_rst_n),
        .clk_pattern_en  (i_clk_pattern_en),
        .clk_embedded_en (i_clk_embedded_en),
        .o_clk_p         (o_clk_p),          // → top-level output AND → MB_PLL ref
        .o_clk_n         (o_clk_n),
        .track           (o_clk_track),
        .o_done          (o_clk_done)
    );

    // =========================================================================
    // 0b. MB_PLL  (reference = o_clk_p from CLK_PATTERN_GEN_TX)
    // =========================================================================
    MB_PLL u_mb_pll (
        .i_ref_clk (o_clk_p),        // differential clock pattern as PLL reference
        .en        (i_pll_en),
        .speed_sel (i_pll_speed_sel),
        .clk       (o_pll_clk)
        // .period is left unconnected (informational output)
    );

    // =========================================================================
    // 1.  Mapper
    // =========================================================================
    Mapper #(
        .WIDTH     (DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) u_mapper (
        .i_clk           (i_mb_clk),
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
        .i_clk                  (i_mb_clk),
        .i_rst_n                (i_rst_n),
        .i_state                (i_lfsr_state),
        .i_scramble_en          (mapper_scramble_en),
        .i_width_deg_lfsr       (i_width_deg),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),

        .i_lane                 (mapper_lane),
        .o_lane                 (lfsr_lane),

        .o_Lfsr_tx_done         (o_lfsr_tx_done),
        .o_valid_frame_en       (lfsr_valid_frame_en)
    );

    // =========================================================================
    // 3.  VALID_TX
    // =========================================================================
    VALID_TX u_valid_tx (
        .i_clk            (i_mb_clk),
        .i_rst_n          (i_rst_n),
        .valid_pattern_en (i_valid_pattern_en),
        .valid_frame_en   (lfsr_valid_frame_en),

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
                .mb_clk  (i_mb_clk),
                .PLL_clk (o_pll_clk),
                .i_rst_n (i_rst_n),
                .Ser_en  (lfsr_valid_frame_en),
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
        .mb_clk  (i_mb_clk),
        .PLL_clk (o_pll_clk),
        .i_rst_n (i_rst_n),
        .Ser_en  (lfsr_valid_frame_en),  // same enable as data lanes
        .in_data (valid_word),
        .SER_out (o_tx_valid)
    );

endmodule
