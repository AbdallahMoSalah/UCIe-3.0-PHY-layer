`timescale 1ns/1ps

// =====================================================================================
// Module: MB_RX_TOP
// Description: MainBand Receiver Top Module. Integrates all sub-modules for 
//              receiving, deserializing, evaluating (LFSR/Valid checks), and demapping
//              MainBand data.
// =====================================================================================

module MB_RX_TOP #(
    parameter DATA_WIDTH = 32,
    parameter N_BYTES = 64
)(
    /*-------------------------------------------------------------------------
     * Clocks and Reset
     *------------------------------------------------------------------------*/
    input  logic                   MB_clk,          // Main system clock for receiver logic
    input  logic                   pll_clk,         // Fast PLL clock for deserializers
    input  logic                   i_rst_n,         // Active-low asynchronous reset

    /*-------------------------------------------------------------------------
     * Serial VALID Input (from analog/pad)
     * No external enable needed – mb_des_valid auto-detects frame start
     *------------------------------------------------------------------------*/
    input  logic                   SER_out,         // Valid Lane Serial Input (free-running)

    /*-------------------------------------------------------------------------
     * Serial Data Inputs (from analog/pad)
     * No external enable needed – mb_deserializer is free-running
     *------------------------------------------------------------------------*/
    input  logic [15:0]            ser_data_in,     // 16 Data Lanes Serial Inputs

    /*-------------------------------------------------------------------------
     * Clock Pattern Detector Inputs
     *------------------------------------------------------------------------*/
    input  logic                   clk_detector_en, // Enable clock pattern detector
    input  logic                   clk_p,
    input  logic                   clk_n,
    input  logic                   track,

    /*-------------------------------------------------------------------------
     * LTSM & Control Inputs (from Link Training and Status State Machine)
     *------------------------------------------------------------------------*/
    // LFSR RX Controls
    input  logic [2:0]             i_state,
    input  logic [2:0]             i_width_deg_lfsr,
    input  logic                   i_active_state_entered,
    input  logic                   i_descramble_en,
    input  logic                   i_enable_buffer,
    
    // Valid RX Controls
    input  logic [11:0]            i_max_error_threshold_valid,
    input  logic                   i_enable_cons,
    input  logic                   i_enable_128,
    input  logic                   i_enable_detector,

    // Pattern Comparator Controls
    input  logic [1:0]             i_type_of_com,
    input  logic [15:0]            i_max_error_threshold_per_lane_ID,
    input  logic [15:0]            i_max_error_threshold_aggergate,

    // Pattern Comparator Width Degradation
    input  logic [2:0]             i_width_deg_comp,

    // Demapper Controls
    input  logic                   demapper_en,
    input  logic                   rx_data_valid,
    input  logic [2:0]             i_width_deg_demap,

    /*-------------------------------------------------------------------------
     * Outputs to Protocol/Adapter/LTSM Layers
     *------------------------------------------------------------------------*/
     // Valid Detector Status DESERIALIZER
     output logic de_ser_done , 
     // data Detector Status DESERIALIZER
     output logic de_ser_done_data_0 ,
     output logic de_ser_done_data_1 ,
     output logic de_ser_done_data_2 ,
     output logic de_ser_done_data_3 ,
     output logic de_ser_done_data_4 ,
     output logic de_ser_done_data_5 ,
     output logic de_ser_done_data_6 ,
     output logic de_ser_done_data_7 ,
     output logic de_ser_done_data_8 ,
     output logic de_ser_done_data_9 ,
     output logic de_ser_done_data_10 ,
     output logic de_ser_done_data_11 ,
     output logic de_ser_done_data_12 ,
     output logic de_ser_done_data_13 ,
     output logic de_ser_done_data_14 ,
     output logic de_ser_done_data_15 ,
    // VALID Detector Status
    output logic                   detection_result,
    output logic                   o_valid_frame_detect,

    // Pattern Comparator Status
    output logic [15:0]            o_per_lane_error,
    output logic [31:0]            o_error_counter,
    output logic                   o_error_done,

    // Clock Pattern Detector Status
    output logic                   clk_p_pattern_pass,
    output logic                   clk_n_pattern_pass,
    output logic                   track_pattern_pass,

    // Demapped Parallel Data Out
    output logic                   pl_valid,
    output logic [8*N_BYTES-1:0]   o_out_data
);

    // =========================================================================
    // Internal Wires Declaration
    // =========================================================================
    logic                    enable_des_valid_frame_w; // From Valid_Deserializer – 1 when F0F0F0F0/0F0F0F0F seen
    logic [DATA_WIDTH-1:0]   valid_par_data_w;         // 32-bit output of Valid_Deserializer

    logic [DATA_WIDTH-1:0]   deser_data_w [0:15];     // 32-bit output from 16 data lanes
    logic [DATA_WIDTH-1:0]   lfsr_data_w  [0:15];     // output from LFSR_RX (descrambled/training)
    logic [DATA_WIDTH-1:0]   lfsr_gen_w   [0:15];     // LFSR locally generated patterns (for compare)
    logic                    pattern_comp_en_w;

    logic [DATA_WIDTH-1:0]   comp_data_w  [0:15];     // pass-through data from pattern comparator

    // -------------------------------------------------------------------------
    // LFSR-buffer gating: only latch LFSR output when a new data word arrives.
    // In training states (010/011) we gate on de_ser_done (valid-lane pulse).
    // In all other states we let i_enable_buffer pass through unmodified.
    // -------------------------------------------------------------------------
    reg [2:0] i_state_delayed;
    always @(posedge MB_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            i_state_delayed <= 3'b000;
        end else begin
            i_state_delayed <= i_state;
        end
    end

    wire gated_enable_buffer = i_enable_buffer && (
        (i_state == 3'b010 || i_state == 3'b011) ? de_ser_done : 1'b1
    );

    // =========================================================================
    // Block 1: Valid Lane Deserializer (MB_DES_VALID)
    // -------------------------------------------------------------------------
    // Edge-detection DDR deserializer. No external enable needed.
    // Detects the rising edge of the valid serial stream to align the frame
    // boundary, then counts 16 PLL cycles to capture a 32-bit word.
    //
    // KEY OUTPUTS:
    //   enable_des_valid_frame_w — MB_clk domain flag (non-sticky).
    //                              1 when the last received frame == 0x0F0F0F0F.
    //                              Delivered to all 16 data DESERs as output gate.
    //   de_ser_done              — MB_clk 1-cycle pulse per received frame.
    // =========================================================================
    MB_DESERIALIZER_VALID #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_MB_DES_VALID (
        .MB_clk(MB_clk),
        .pll_clk(pll_clk),
        .i_rst_n(i_rst_n),
        .ser_data_in(SER_out),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .par_data_out(valid_par_data_w),
        .de_ser_done(de_ser_done)
    );

    // =========================================================================
    // Block 2: Data Lanes Deserializers (MB_DeSerializer)
    // -------------------------------------------------------------------------
    // Free-running DDR deserializer × 16. No external enable needed.
    // All instances share pll_clk + i_rst_n so their 16-cycle counters stay
    // frame-aligned with the valid deserializer.
    //
    // Output (par_data_out / de_ser_done) is gated by enable_des_valid_frame_w:
    // data only passes downstream once the valid pattern is confirmed.
    // =========================================================================
    // Lane 0
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_0 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[0]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[0]), .de_ser_done(de_ser_done_data_0)
    );

    // Lane 1
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_1 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[1]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[1]), .de_ser_done(de_ser_done_data_1)
    );

    // Lane 2
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_2 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[2]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[2]), .de_ser_done(de_ser_done_data_2)
    );

    // Lane 3
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_3 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[3]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[3]), .de_ser_done(de_ser_done_data_3)
    );

    // Lane 4
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_4 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[4]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[4]), .de_ser_done(de_ser_done_data_4)
    );

    // Lane 5
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_5 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[5]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[5]), .de_ser_done(de_ser_done_data_5)
    );

    // Lane 6
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_6 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[6]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[6]), .de_ser_done(de_ser_done_data_6)
    );

    // Lane 7
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_7 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[7]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[7]), .de_ser_done(de_ser_done_data_7)
    );

    // Lane 8
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_8 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[8]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[8]), .de_ser_done(de_ser_done_data_8)
    );

    // Lane 9
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_9 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[9]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[9]), .de_ser_done(de_ser_done_data_9)
    );

    // Lane 10
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_10 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[10]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[10]), .de_ser_done(de_ser_done_data_10)
    );

    // Lane 11
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_11 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[11]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[11]), .de_ser_done(de_ser_done_data_11)
    );

    // Lane 12
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_12 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[12]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[12]), .de_ser_done(de_ser_done_data_12)
    );

    // Lane 13
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_13 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[13]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[13]), .de_ser_done(de_ser_done_data_13)
    );

    // Lane 14
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_14 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[14]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[14]), .de_ser_done(de_ser_done_data_14)
    );

    // Lane 15
    MB_DESERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_MB_DeSerializer_15 (
        .MB_clk(MB_clk), .pll_clk(pll_clk), .i_rst_n(i_rst_n),
        .ser_data_in(ser_data_in[15]),
        .enable_des_valid_frame(enable_des_valid_frame_w),
        .valid_ser_in(SER_out),
        .par_data_out(deser_data_w[15]), .de_ser_done(de_ser_done_data_15)
    );

    // =========================================================================
    // Block 3: Valid Pattern Detector (VALID_RX)
    // -------------------------------------------------------------------------
    // Analyzes the 32-bit parallel valid frame. Checks for the specific
    // valid patterns over 16 consecutive or 128 iterations. Evaluates error 
    // thresholds and outputs detection success flags.
    // =========================================================================
    VALID_DETECTOR u_VALID_RX (
        .i_clk(MB_clk),
        .i_rst_n(i_rst_n),
        .RVLD_L(valid_par_data_w),
        .i_max_error_threshold(i_max_error_threshold_valid),
        .i_enable_cons(i_enable_cons),
        .i_enable_128(i_enable_128),
        .i_enable_detector(i_enable_detector),
        .detection_result(detection_result),
        .o_valid_frame_detect(o_valid_frame_detect)
    );

    // =========================================================================
    // Block 4: Linear Feedback Shift Register - RX (LFSR_RX)
    // -------------------------------------------------------------------------
    // Evaluates incoming data through per-lane LFSR logic. Performs descrambling 
    // when active, or generates local reference patterns during training. Outputs 
    // either descrambled/raw data along with generated reference patterns.
    // =========================================================================
    LFSR_RX #(
        .WIDTH(DATA_WIDTH)
    ) u_LFSR_RX (
        .i_clk(MB_clk),
        .i_rst_n(i_rst_n),
        .i_state(i_state),
        .i_width_deg_lfsr(i_width_deg_lfsr),
        .i_active_state_entered(i_active_state_entered),
        .i_descramble_en(i_descramble_en),
        .i_enable_buffer(gated_enable_buffer),
        .i_data_in(deser_data_w),
        .o_Data_by(lfsr_data_w),
        .o_final_gene(lfsr_gen_w),
        .pattern_comp_en(pattern_comp_en_w)
    );

    // =========================================================================
    // Block 5: Pattern Comparator (MB_Pattern_comparator)
    // =========================================================================
    PATTERN_COMPARATOR #(
        .WIDTH(DATA_WIDTH)
    ) u_MB_Pattern_comparator (
        .i_clk(MB_clk),
        .i_rst_n(i_rst_n),
        .i_active(i_active_state_entered),
        .i_width_deg_comp(i_width_deg_comp),
        .i_type_of_com(i_type_of_com),
        .i_enable_pattern_com(pattern_comp_en_w),
        .i_max_error_threshold_per_lane_ID(i_max_error_threshold_per_lane_ID),
        .i_max_error_threshold_aggergate(i_max_error_threshold_aggergate),

        .i_local_gen_0 (lfsr_gen_w[0]),
        .i_local_gen_1 (lfsr_gen_w[1]),
        .i_local_gen_2 (lfsr_gen_w[2]),
        .i_local_gen_3 (lfsr_gen_w[3]),
        .i_local_gen_4 (lfsr_gen_w[4]),
        .i_local_gen_5 (lfsr_gen_w[5]),
        .i_local_gen_6 (lfsr_gen_w[6]),
        .i_local_gen_7 (lfsr_gen_w[7]),
        .i_local_gen_8 (lfsr_gen_w[8]),
        .i_local_gen_9 (lfsr_gen_w[9]),
        .i_local_gen_10(lfsr_gen_w[10]),
        .i_local_gen_11(lfsr_gen_w[11]),
        .i_local_gen_12(lfsr_gen_w[12]),
        .i_local_gen_13(lfsr_gen_w[13]),
        .i_local_gen_14(lfsr_gen_w[14]),
        .i_local_gen_15(lfsr_gen_w[15]),

        .i_data_0 (lfsr_data_w[0]),
        .i_data_1 (lfsr_data_w[1]),
        .i_data_2 (lfsr_data_w[2]),
        .i_data_3 (lfsr_data_w[3]),
        .i_data_4 (lfsr_data_w[4]),
        .i_data_5 (lfsr_data_w[5]),
        .i_data_6 (lfsr_data_w[6]),
        .i_data_7 (lfsr_data_w[7]),
        .i_data_8 (lfsr_data_w[8]),
        .i_data_9 (lfsr_data_w[9]),
        .i_data_10(lfsr_data_w[10]),
        .i_data_11(lfsr_data_w[11]),
        .i_data_12(lfsr_data_w[12]),
        .i_data_13(lfsr_data_w[13]),
        .i_data_14(lfsr_data_w[14]),
        .i_data_15(lfsr_data_w[15]),

        .o_per_lane_error(o_per_lane_error),
        .o_error_counter(o_error_counter),
        .o_error_done(o_error_done),

        .o_data_0 (comp_data_w[0]),
        .o_data_1 (comp_data_w[1]),
        .o_data_2 (comp_data_w[2]),
        .o_data_3 (comp_data_w[3]),
        .o_data_4 (comp_data_w[4]),
        .o_data_5 (comp_data_w[5]),
        .o_data_6 (comp_data_w[6]),
        .o_data_7 (comp_data_w[7]),
        .o_data_8 (comp_data_w[8]),
        .o_data_9 (comp_data_w[9]),
        .o_data_10(comp_data_w[10]),
        .o_data_11(comp_data_w[11]),
        .o_data_12(comp_data_w[12]),
        .o_data_13(comp_data_w[13]),
        .o_data_14(comp_data_w[14]),
        .o_data_15(comp_data_w[15])
    );

    // =========================================================================
    // Block 6: Demapper (DEMAPPER)
    // =========================================================================
    Demapper #(
        .N_BYTES(N_BYTES),
        .NUM_LANES(16),
        .WIDTH(DATA_WIDTH)
    ) u_DEMAPPER (
        .i_clk(MB_clk),
        .i_rst_n(i_rst_n),
        .i_lane_0 (comp_data_w[0]),
        .i_lane_1 (comp_data_w[1]),
        .i_lane_2 (comp_data_w[2]),
        .i_lane_3 (comp_data_w[3]),
        .i_lane_4 (comp_data_w[4]),
        .i_lane_5 (comp_data_w[5]),
        .i_lane_6 (comp_data_w[6]),
        .i_lane_7 (comp_data_w[7]),
        .i_lane_8 (comp_data_w[8]),
        .i_lane_9 (comp_data_w[9]),
        .i_lane_10(comp_data_w[10]),
        .i_lane_11(comp_data_w[11]),
        .i_lane_12(comp_data_w[12]),
        .i_lane_13(comp_data_w[13]),
        .i_lane_14(comp_data_w[14]),
        .i_lane_15(comp_data_w[15]),
        .demapper_en(demapper_en),
        .rx_data_valid(rx_data_valid),
        .i_width_deg_demap(i_width_deg_demap),
        .pl_valid(pl_valid),
        .o_out_data(o_out_data)
    );

    // =========================================================================
    // Block 7: Clock Pattern Detector RX (CLK_PATTERN_DETECTOR_RX)
    // =========================================================================
    CLK_PATTERN_DETECTOR_RX #(
        .TOGGLE(32),
        .ZERO(16)
    ) u_CLK_PATTERN_DETECTOR_RX (
        .i_clk(pll_clk),
        .i_rst_n(i_rst_n),
        .clk_detector_en(clk_detector_en),
        .clk_p(clk_p),
        .clk_n(clk_n),
        .track(track),
        .clk_p_pattern_pass(clk_p_pattern_pass),
        .clk_n_pattern_pass(clk_n_pattern_pass),
        .track_pattern_pass(track_pattern_pass)
    );

endmodule 