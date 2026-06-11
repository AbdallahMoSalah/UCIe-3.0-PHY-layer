/*==============================================================================
 * Golden Model for LFSR_TX
 * ============================================================================
 * This is a pure behavioral reference model written in SystemVerilog.
 * It mirrors every feature of the RTL exactly:
 *   - FSM: IDLE → CLEAR_LFSR / PATTERN_LFSR / PER_LANE_IDE
 *   - 23-bit LFSR per lane with precomputed 9-bit extension (bits[31:23])
 *   - Scrambler mode  (scramble_en_g=1): XOR LFSR output with input lanes
 *   - Pattern mode    (scramble_en_g=0): output raw LFSR, count 128 cycles
 *   - Per-Lane-ID mode: replicate LANE_ID 64 cycles
 *   - Lane reversal   (reversal_en_g latched in IDLE)
 *   - All 6 degrade/width modes
 *   - o_Lfsr_tx_done_g and valid_frame_en_g flags
 *============================================================================*/

module LFSR_TX_GOLD #(
    parameter WIDTH = 32
)(
    input  logic        i_clk_g,
    input  logic        i_rst_n_g,
    input  logic [1:0]  i_state_g,
    input  logic        scramble_en_g,
    input  logic [2:0]  i_width_deg_lfsr_g,
    input  logic        reversal_en_g,

    // 16 input lanes
    input  logic [WIDTH-1:0] i_lane_0_g,  input  logic [WIDTH-1:0] i_lane_1_g,
    input  logic [WIDTH-1:0] i_lane_2_g,  input  logic [WIDTH-1:0] i_lane_3_g,
    input  logic [WIDTH-1:0] i_lane_4_g,  input  logic [WIDTH-1:0] i_lane_5_g,
    input  logic [WIDTH-1:0] i_lane_6_g,  input  logic [WIDTH-1:0] i_lane_7_g,
    input  logic [WIDTH-1:0] i_lane_8_g,  input  logic [WIDTH-1:0] i_lane_9_g,
    input  logic [WIDTH-1:0] i_lane_10_g, input  logic [WIDTH-1:0] i_lane_11_g,
    input  logic [WIDTH-1:0] i_lane_12_g, input  logic [WIDTH-1:0] i_lane_13_g,
    input  logic [WIDTH-1:0] i_lane_14_g, input  logic [WIDTH-1:0] i_lane_15_g,
    // 16 output lanes
    output logic [WIDTH-1:0] o_lane_0_g,  output logic [WIDTH-1:0] o_lane_1_g,
    output logic [WIDTH-1:0] o_lane_2_g,  output logic [WIDTH-1:0] o_lane_3_g,
    output logic [WIDTH-1:0] o_lane_4_g,  output logic [WIDTH-1:0] o_lane_5_g,
    output logic [WIDTH-1:0] o_lane_6_g,  output logic [WIDTH-1:0] o_lane_7_g,
    output logic [WIDTH-1:0] o_lane_8_g,  output logic [WIDTH-1:0] o_lane_9_g,
    output logic [WIDTH-1:0] o_lane_10_g, output logic [WIDTH-1:0] o_lane_11_g,
    output logic [WIDTH-1:0] o_lane_12_g, output logic [WIDTH-1:0] o_lane_13_g,
    output logic [WIDTH-1:0] o_lane_14_g, output logic [WIDTH-1:0] o_lane_15_g,

    output logic o_Lfsr_tx_done_g,
    output logic  valid_frame_en_g
);

    /*--------------------------------------------------------------------------
     * State / degrade encoding (must match RTL exactly)
     *------------------------------------------------------------------------*/
    localparam IDLE         = 2'b00;
    localparam CLEAR_LFSR   = 2'b01;
    localparam PATTERN_LFSR = 2'b10;
    localparam PER_LANE_IDE = 2'b11;

    localparam NONE_DEGRADE          = 3'b000;
    localparam DEGRADE_LANES_0_TO_7  = 3'b001;
    localparam DEGRADE_LANES_8_TO_15 = 3'b010;
    localparam DEGRADE_LANES_0_TO_15 = 3'b011;
    localparam DEGRADE_LANES_0_TO_3  = 3'b100;
    localparam DEGRADE_LANES_4_TO_7  = 3'b101;

    /*--------------------------------------------------------------------------
     * Lane IDs (16-bit: 1010_<8-bit index>_1010)
     *------------------------------------------------------------------------*/
    localparam [15:0] LANE_ID_0  = 16'b1010_00000000_1010;
    localparam [15:0] LANE_ID_1  = 16'b1010_00000001_1010;
    localparam [15:0] LANE_ID_2  = 16'b1010_00000010_1010;
    localparam [15:0] LANE_ID_3  = 16'b1010_00000011_1010;
    localparam [15:0] LANE_ID_4  = 16'b1010_00000100_1010;
    localparam [15:0] LANE_ID_5  = 16'b1010_00000101_1010;
    localparam [15:0] LANE_ID_6  = 16'b1010_00000110_1010;
    localparam [15:0] LANE_ID_7  = 16'b1010_00000111_1010;
    localparam [15:0] LANE_ID_8  = 16'b1010_00001000_1010;
    localparam [15:0] LANE_ID_9  = 16'b1010_00001001_1010;
    localparam [15:0] LANE_ID_10 = 16'b1010_00001010_1010;
    localparam [15:0] LANE_ID_11 = 16'b1010_00001011_1010;
    localparam [15:0] LANE_ID_12 = 16'b1010_00001100_1010;
    localparam [15:0] LANE_ID_13 = 16'b1010_00001101_1010;
    localparam [15:0] LANE_ID_14 = 16'b1010_00001110_1010;
    localparam [15:0] LANE_ID_15 = 16'b1010_00001111_1010;

    /*--------------------------------------------------------------------------
     * Seeds (fixed, identical to RTL)
     *------------------------------------------------------------------------*/
    localparam [22:0] SEED_0 = 23'h1DBFBC;
    localparam [22:0] SEED_1 = 23'h0607BB;
    localparam [22:0] SEED_2 = 23'h1EC760;
    localparam [22:0] SEED_3 = 23'h18C0DB;
    localparam [22:0] SEED_4 = 23'h010F12;
    localparam [22:0] SEED_5 = 23'h19CFC9;
    localparam [22:0] SEED_6 = 23'h0277CE;
    localparam [22:0] SEED_7 = 23'h1BB807;

    /*--------------------------------------------------------------------------
     * Internal registers
     *------------------------------------------------------------------------*/
    logic [1:0]  current_state;
    logic [1:0]  i_state_g_reg;
    logic        i_state_g_changed;

    logic [6:0]  counter_lfsr;
    logic [5:0]  counter_per_lane;
    logic        lane_reversal_en_gabled;

    // Per-lane 23-bit LFSR state registers
    logic [22:0] tx_lfsr [0:7];

    // Per-lane 9-bit upper output (bits [31:23] of the 32-bit next_state)
    logic [8:0]  o_lane_23 [0:7];

    /*--------------------------------------------------------------------------
     * next_lfsr_state function
     * Computes the full 32-bit next output from a 23-bit current LFSR state.
     * Bits [22:0]  → next LFSR register value
     * Bits [31:23] → 9 extra scrambled bits (o_lane_N_23 in RTL)
     *------------------------------------------------------------------------*/
    function automatic [31:0] next_lfsr_state (input [22:0] cs);
        logic [31:0] ns;
        begin
            // ---- bits 0-22: standard linear recurrence ---------
            ns[0]  = cs[1]^cs[2]^cs[3]^cs[4]^cs[7]^cs[8]^cs[10]^cs[14]^cs[15]^cs[17]^cs[18]^cs[19]^cs[20]^cs[22];
            ns[1]  = cs[0]^cs[3]^cs[4]^cs[9]^cs[11]^cs[15]^cs[18]^cs[19]^cs[20];
            ns[2]  = cs[1]^cs[4]^cs[5]^cs[10]^cs[12]^cs[16]^cs[19]^cs[20]^cs[21];
            ns[3]  = cs[2]^cs[5]^cs[6]^cs[11]^cs[13]^cs[17]^cs[20]^cs[21]^cs[22];
            ns[4]  = cs[0]^cs[2]^cs[3]^cs[5]^cs[6]^cs[7]^cs[8]^cs[12]^cs[14]^cs[16]^cs[18]^cs[22];
            ns[5]  = cs[0]^cs[1]^cs[2]^cs[3]^cs[4]^cs[5]^cs[6]^cs[7]^cs[9]^cs[13]^cs[15]^cs[16]^cs[17]^cs[19]^cs[21];
            ns[6]  = cs[1]^cs[2]^cs[3]^cs[4]^cs[5]^cs[6]^cs[7]^cs[8]^cs[10]^cs[14]^cs[16]^cs[17]^cs[18]^cs[20]^cs[22];
            ns[7]  = cs[0]^cs[3]^cs[4]^cs[6]^cs[7]^cs[9]^cs[11]^cs[15]^cs[16]^cs[17]^cs[18]^cs[19];
            ns[8]  = cs[1]^cs[4]^cs[5]^cs[7]^cs[8]^cs[10]^cs[12]^cs[16]^cs[17]^cs[18]^cs[19]^cs[20];
            ns[9]  = cs[2]^cs[5]^cs[6]^cs[8]^cs[9]^cs[11]^cs[13]^cs[17]^cs[18]^cs[19]^cs[20]^cs[21];
            ns[10] = cs[3]^cs[6]^cs[7]^cs[9]^cs[10]^cs[12]^cs[14]^cs[18]^cs[19]^cs[20]^cs[21]^cs[22];
            ns[11] = cs[0]^cs[2]^cs[4]^cs[5]^cs[7]^cs[10]^cs[11]^cs[13]^cs[15]^cs[16]^cs[19]^cs[20]^cs[22];
            ns[12] = cs[0]^cs[1]^cs[2]^cs[3]^cs[6]^cs[11]^cs[12]^cs[14]^cs[17]^cs[20];
            ns[13] = cs[1]^cs[2]^cs[3]^cs[4]^cs[7]^cs[12]^cs[13]^cs[15]^cs[18]^cs[21];
            ns[14] = cs[2]^cs[3]^cs[4]^cs[5]^cs[8]^cs[13]^cs[14]^cs[16]^cs[19]^cs[22];
            ns[15] = cs[0]^cs[2]^cs[3]^cs[4]^cs[6]^cs[8]^cs[9]^cs[14]^cs[15]^cs[16]^cs[17]^cs[20]^cs[21];
            ns[16] = cs[1]^cs[3]^cs[4]^cs[5]^cs[7]^cs[9]^cs[10]^cs[15]^cs[16]^cs[17]^cs[18]^cs[21]^cs[22];
            ns[17] = cs[0]^cs[4]^cs[6]^cs[10]^cs[11]^cs[17]^cs[18]^cs[19]^cs[21]^cs[22];
            ns[18] = cs[0]^cs[1]^cs[2]^cs[7]^cs[8]^cs[11]^cs[12]^cs[16]^cs[18]^cs[19]^cs[20]^cs[21]^cs[22];
            ns[19] = cs[0]^cs[1]^cs[3]^cs[5]^cs[9]^cs[12]^cs[13]^cs[16]^cs[17]^cs[19]^cs[20]^cs[22];
            ns[20] = cs[0]^cs[1]^cs[4]^cs[5]^cs[6]^cs[8]^cs[10]^cs[13]^cs[14]^cs[16]^cs[17]^cs[18]^cs[20];
            ns[21] = cs[1]^cs[2]^cs[5]^cs[6]^cs[7]^cs[9]^cs[11]^cs[14]^cs[15]^cs[17]^cs[18]^cs[19]^cs[21];
            ns[22] = cs[2]^cs[3]^cs[6]^cs[7]^cs[8]^cs[10]^cs[12]^cs[15]^cs[16]^cs[18]^cs[19]^cs[20]^cs[22];
            // ---- bits 23-31: second-level XOR of the ns values above --------
            ns[23] = ns[0]^ns[2]^ns[3]^ns[4]^ns[5]^ns[7]^ns[9]^ns[11]^ns[13]^ns[17]^ns[19]^ns[20];
            ns[24] = ns[1]^ns[3]^ns[4]^ns[5]^ns[6]^ns[8]^ns[10]^ns[12]^ns[14]^ns[18]^ns[20]^ns[21];
            ns[25] = ns[2]^ns[4]^ns[5]^ns[6]^ns[7]^ns[9]^ns[11]^ns[13]^ns[15]^ns[19]^ns[21]^ns[22];
            ns[26] = ns[0]^ns[2]^ns[3]^ns[6]^ns[7]^ns[10]^ns[12]^ns[14]^ns[20]^ns[21]^ns[22];
            ns[27] = ns[0]^ns[1]^ns[2]^ns[3]^ns[4]^ns[5]^ns[7]^ns[11]^ns[13]^ns[15]^ns[16]^ns[22];
            ns[28] = ns[0]^ns[1]^ns[3]^ns[4]^ns[6]^ns[12]^ns[14]^ns[17]^ns[21];
            ns[29] = ns[1]^ns[2]^ns[4]^ns[5]^ns[7]^ns[13]^ns[15]^ns[18]^ns[22];
            ns[30] = ns[0]^ns[3]^ns[6]^ns[14]^ns[19]^ns[21];
            ns[31] = ns[1]^ns[4]^ns[7]^ns[15]^ns[20]^ns[22];
            next_lfsr_state = ns;
        end
    endfunction

    /*--------------------------------------------------------------------------
     * Helper function: compute o_lane_N_23 (9 bits) from a seed value.
     * This replicates the identical large XOR tree in both the reset block
     * and the CLEAR_LFSR state of the RTL.
     *------------------------------------------------------------------------*/
    function automatic [8:0] compute_lane_23_from_seed (input [22:0] s);
        logic [8:0] r;
        begin
            r[8] = s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            r[7] = s[21]^s[19]^s[14]^s[6]^s[3]^s[0];
            r[6] = s[20]^s[18]^s[13]^s[5]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            r[5] = s[19]^s[17]^s[12]^s[4]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3]^s[0];
            r[4] = s[18]^s[16]^s[11]^s[3]^s[0]^s[20]^s[18]^s[13]^s[5]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            r[3] = s[17]^s[15]^s[10]^s[0]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1]^s[19]^s[17]^s[12]^s[4]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3];
            r[2] = s[16]^s[14]^s[9]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3]^s[0]^s[18]^s[16]^s[11]^s[3]^s[0]^s[20]^s[18]^s[13]^s[5]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            r[1] = s[15]^s[13]^s[8]^s[0]^s[0]^s[20]^s[18]^s[13]^s[5]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1]^s[17]^s[15]^s[10]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1]^s[19]^s[17]^s[12]^s[4]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3];
            r[0] = s[14]^s[12]^s[7]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1]^s[19]^s[17]^s[12]^s[4]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3]^s[0]^s[16]^s[14]^s[9]^s[1]^s[21]^s[19]^s[14]^s[6]^s[3]^s[0]^s[18]^s[16]^s[11]^s[3]^s[0]^s[20]^s[18]^s[13]^s[5]^s[2]^s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            compute_lane_23_from_seed = r;
        end
    endfunction

    /*--------------------------------------------------------------------------
     * Helper task: reset all LFSR state to seeds + precompute o_lane_23
     *------------------------------------------------------------------------*/
    task automatic load_seeds();
        tx_lfsr[0] = SEED_0; tx_lfsr[1] = SEED_1;
        tx_lfsr[2] = SEED_2; tx_lfsr[3] = SEED_3;
        tx_lfsr[4] = SEED_4; tx_lfsr[5] = SEED_5;
        tx_lfsr[6] = SEED_6; tx_lfsr[7] = SEED_7;
        o_lane_23[0] = compute_lane_23_from_seed(SEED_0);
        o_lane_23[1] = compute_lane_23_from_seed(SEED_1);
        o_lane_23[2] = compute_lane_23_from_seed(SEED_2);
        o_lane_23[3] = compute_lane_23_from_seed(SEED_3);
        o_lane_23[4] = compute_lane_23_from_seed(SEED_4);
        o_lane_23[5] = compute_lane_23_from_seed(SEED_5);
        o_lane_23[6] = compute_lane_23_from_seed(SEED_6);
        o_lane_23[7] = compute_lane_23_from_seed(SEED_7);
    endtask

    /*--------------------------------------------------------------------------
     * Helper function: build full 32-bit LFSR word for lane k
     * (concatenation that RTL does: {tx_lfsr_lane_k, o_lane_k_23})
     *------------------------------------------------------------------------*/
    function automatic [WIDTH-1:0] lfsr_word(input int k);
        lfsr_word = {tx_lfsr[k], o_lane_23[k]};
    endfunction

    /*--------------------------------------------------------------------------
     * Helper function: assemble LANE_ID word ({LANE_ID_x, LANE_ID_x})
     *------------------------------------------------------------------------*/
    function automatic [WIDTH-1:0] lane_id_word(input int physical_lane);
        logic [15:0] id;
        case (physical_lane)
            0:  id = LANE_ID_0;  1:  id = LANE_ID_1;
            2:  id = LANE_ID_2;  3:  id = LANE_ID_3;
            4:  id = LANE_ID_4;  5:  id = LANE_ID_5;
            6:  id = LANE_ID_6;  7:  id = LANE_ID_7;
            8:  id = LANE_ID_8;  9:  id = LANE_ID_9;
            10: id = LANE_ID_10; 11: id = LANE_ID_11;
            12: id = LANE_ID_12; 13: id = LANE_ID_13;
            14: id = LANE_ID_14; 15: id = LANE_ID_15;
            default: id = 16'h0;
        endcase
        lane_id_word = {id, id};
    endfunction

    /*--------------------------------------------------------------------------
     * FSM  (first always block — state register only)
     *------------------------------------------------------------------------*/
    assign i_state_g_changed = (i_state_g_reg != i_state_g);

    always_ff @(posedge i_clk_g or negedge i_rst_n_g) begin
        if (!i_rst_n_g) begin
            current_state <= IDLE;
            i_state_g_reg   <= 2'b00;
        end else begin
            i_state_g_reg <= i_state_g;
            case (current_state)
                IDLE: begin
                    if      (i_state_g_changed && i_state_g == 2'b01) current_state <= CLEAR_LFSR;
                    else if (i_state_g_changed && i_state_g == 2'b10) current_state <= PATTERN_LFSR;
                    else if (i_state_g_changed && i_state_g == 2'b11) current_state <= PER_LANE_IDE;
                    else                                           current_state <= IDLE;
                end
                CLEAR_LFSR:   current_state <= IDLE;
                PATTERN_LFSR: current_state <= (&counter_lfsr)     ? IDLE : PATTERN_LFSR;
                PER_LANE_IDE: current_state <= (&counter_per_lane)  ? IDLE : PER_LANE_IDE;
                default:      current_state <= IDLE;
            endcase
        end
    end

    /*--------------------------------------------------------------------------
     * Datapath (second always block)
     *------------------------------------------------------------------------*/
    always_ff @(posedge i_clk_g or negedge i_rst_n_g) begin : datapath

        // ------------------------------------------------------------------ //
        //  RESET
        // ------------------------------------------------------------------ //
        if (!i_rst_n_g) begin
            counter_lfsr         <= 7'd0;
            counter_per_lane     <= 6'd0;
            o_Lfsr_tx_done_g       <= 1'b0;
            valid_frame_en_g       <= 1'b0;
            lane_reversal_en_gabled<= 1'b0;

            // Clear all output lanes
            o_lane_0_g <= '0; o_lane_1_g <= '0; o_lane_2_g <= '0; o_lane_3_g <= '0;
            o_lane_4_g <= '0; o_lane_5_g <= '0; o_lane_6_g <= '0; o_lane_7_g <= '0;
            o_lane_8_g <= '0; o_lane_9_g <= '0; o_lane_10_g<= '0; o_lane_11_g<= '0;
            o_lane_12_g<= '0; o_lane_13_g<= '0; o_lane_14_g<= '0; o_lane_15_g<= '0;

            // Load seeds and precomputed 9-bit extensions
            load_seeds();

        // ------------------------------------------------------------------ //
        //  NORMAL OPERATION
        // ------------------------------------------------------------------ //
        end else begin

            // Default: clear all output lanes each cycle (RTL does this at top
            // of the else branch before the case statement)
            o_lane_0_g <= '0; o_lane_1_g <= '0; o_lane_2_g <= '0; o_lane_3_g <= '0;
            o_lane_4_g <= '0; o_lane_5_g <= '0; o_lane_6_g <= '0; o_lane_7_g <= '0;
            o_lane_8_g <= '0; o_lane_9_g <= '0; o_lane_10_g<= '0; o_lane_11_g<= '0;
            o_lane_12_g<= '0; o_lane_13_g<= '0; o_lane_14_g<= '0; o_lane_15_g<= '0;

            case (current_state)

                // ---------------------------------------------------------- //
                //  IDLE
                // ---------------------------------------------------------- //
                IDLE: begin
                    counter_lfsr     <= 7'd0;
                    counter_per_lane <= 6'd0;
                    valid_frame_en_g   <= 1'b0;
                    if (reversal_en_g) begin
                        lane_reversal_en_gabled <= 1'b1;
                        o_Lfsr_tx_done_g        <= 1'b1;
                    end else begin
                        o_Lfsr_tx_done_g <= 1'b0;
                    end
                end

                // ---------------------------------------------------------- //
                //  CLEAR_LFSR  — reload seeds, stay one cycle
                // ---------------------------------------------------------- //
                CLEAR_LFSR: begin
                    load_seeds();
                end

                // ---------------------------------------------------------- //
                //  PATTERN_LFSR  — advance all 8 LFSRs, drive outputs
                // ---------------------------------------------------------- //
                PATTERN_LFSR: begin
                    // Advance all 8 LFSRs and capture the 9-bit extension
                    begin
                        automatic logic [31:0] ns [0:7];
                        for (int k = 0; k < 8; k++) begin
                            ns[k]        = next_lfsr_state(tx_lfsr[k]);
                            tx_lfsr[k]   = ns[k][22:0];
                            o_lane_23[k] = ns[k][31:23];
                        end
                    end

                    // ---- scrambler mode: XOR with input lanes --------------
                    if (scramble_en_g) begin
                        valid_frame_en_g <= 1'b1;
                        case (i_width_deg_lfsr_g)

                            DEGRADE_LANES_0_TO_7: begin
                                if (lane_reversal_en_gabled) begin
                                    o_lane_0_g <= lfsr_word(7) ^ i_lane_7_g;
                                    o_lane_1_g <= lfsr_word(6) ^ i_lane_6_g;
                                    o_lane_2_g <= lfsr_word(5) ^ i_lane_5_g;
                                    o_lane_3_g <= lfsr_word(4) ^ i_lane_4_g;
                                    o_lane_4_g <= lfsr_word(3) ^ i_lane_3_g;
                                    o_lane_5_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_6_g<= lfsr_word(1)  ^ i_lane_1_g;
                                    o_lane_7_g<= lfsr_word(0)  ^ i_lane_0_g;
                                end else begin
                                    o_lane_0_g <= lfsr_word(0) ^ i_lane_0_g;
                                    o_lane_1_g <= lfsr_word(1) ^ i_lane_1_g;
                                    o_lane_2_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_3_g <= lfsr_word(3) ^ i_lane_3_g;
                                    o_lane_4_g <= lfsr_word(4) ^ i_lane_4_g;
                                    o_lane_5_g <= lfsr_word(5) ^ i_lane_5_g;
                                    o_lane_6_g <= lfsr_word(6) ^ i_lane_6_g;
                                    o_lane_7_g <= lfsr_word(7) ^ i_lane_7_g;
                                end
                            end

                            DEGRADE_LANES_8_TO_15: begin
                                if (lane_reversal_en_gabled) begin
                                    o_lane_8_g  <= lfsr_word(7) ^ i_lane_7_g;
                                    o_lane_9_g  <= lfsr_word(6) ^ i_lane_6_g;
                                    o_lane_10_g <= lfsr_word(5) ^ i_lane_5_g;
                                    o_lane_11_g <= lfsr_word(4) ^ i_lane_4_g;
                                    o_lane_12_g <= lfsr_word(3) ^ i_lane_3_g;
                                    o_lane_13_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_14_g <= lfsr_word(1) ^ i_lane_1_g;
                                    o_lane_15_g <= lfsr_word(0) ^ i_lane_0_g;
                                end else begin
                                    o_lane_8_g  <= lfsr_word(0) ^ i_lane_8_g;
                                    o_lane_9_g  <= lfsr_word(1) ^ i_lane_9_g;
                                    o_lane_10_g <= lfsr_word(2) ^ i_lane_10_g;
                                    o_lane_11_g <= lfsr_word(3) ^ i_lane_11_g;
                                    o_lane_12_g <= lfsr_word(4) ^ i_lane_12_g;
                                    o_lane_13_g <= lfsr_word(5) ^ i_lane_13_g;
                                    o_lane_14_g <= lfsr_word(6) ^ i_lane_14_g;
                                    o_lane_15_g <= lfsr_word(7) ^ i_lane_15_g;
                                end
                            end

                            DEGRADE_LANES_0_TO_3: begin
                                if (lane_reversal_en_gabled) begin
                                    o_lane_0_g <= lfsr_word(7) ^ i_lane_7_g;
                                    o_lane_1_g <= lfsr_word(6) ^ i_lane_6_g;
                                    o_lane_2_g <= lfsr_word(5) ^ i_lane_5_g;
                                    o_lane_3_g <= lfsr_word(4) ^ i_lane_4_g;
                                end else begin
                                    o_lane_0_g <= lfsr_word(0) ^ i_lane_0_g;
                                    o_lane_1_g <= lfsr_word(1) ^ i_lane_1_g;
                                    o_lane_2_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_3_g <= lfsr_word(3) ^ i_lane_3_g;
                                end
                            end

                            DEGRADE_LANES_4_TO_7: begin
                                if (lane_reversal_en_gabled) begin
                                    o_lane_4_g <= lfsr_word(3) ^ i_lane_3_g;
                                    o_lane_5_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_6_g <= lfsr_word(1) ^ i_lane_1_g;
                                    o_lane_7_g <= lfsr_word(0) ^ i_lane_0_g;
                                end else begin
                                    o_lane_4_g <= lfsr_word(0) ^ i_lane_4_g;
                                    o_lane_5_g <= lfsr_word(1) ^ i_lane_5_g;
                                    o_lane_6_g <= lfsr_word(2) ^ i_lane_6_g;
                                    o_lane_7_g <= lfsr_word(3) ^ i_lane_7_g;
                                end
                            end

                            DEGRADE_LANES_0_TO_15: begin
                                if (lane_reversal_en_gabled) begin
                                    o_lane_0_g <= lfsr_word(7) ^ i_lane_15_g;
                                    o_lane_1_g <= lfsr_word(6) ^ i_lane_14_g;
                                    o_lane_2_g <= lfsr_word(5) ^ i_lane_13_g;
                                    o_lane_3_g <= lfsr_word(4) ^ i_lane_12_g;
                                    o_lane_4_g <= lfsr_word(3) ^ i_lane_11_g;
                                    o_lane_5_g <= lfsr_word(2) ^ i_lane_10_g;
                                    o_lane_6_g <= lfsr_word(1) ^ i_lane_9_g;
                                    o_lane_7_g <= lfsr_word(0) ^ i_lane_8_g;
                                    o_lane_8_g <= lfsr_word(7) ^ i_lane_7_g;
                                    o_lane_9_g <= lfsr_word(6) ^ i_lane_6_g;
                                    o_lane_10_g <= lfsr_word(5) ^ i_lane_5_g;
                                    o_lane_11_g <= lfsr_word(4) ^ i_lane_4_g;
                                    o_lane_12_g <= lfsr_word(3) ^ i_lane_3_g;
                                    o_lane_13_g <= lfsr_word(2) ^ i_lane_2_g;
                                    o_lane_14_g <= lfsr_word(1) ^ i_lane_1_g;
                                    o_lane_15_g <= lfsr_word(0) ^ i_lane_0_g;
                                end else begin
                                    o_lane_0_g <= lfsr_word(0)  ^   i_lane_0_g;
                                    o_lane_1_g  <= lfsr_word(1) ^   i_lane_1_g;
                                    o_lane_2_g <= lfsr_word(2)  ^   i_lane_2_g;
                                    o_lane_3_g <= lfsr_word(3)  ^   i_lane_3_g;
                                    o_lane_4_g <= lfsr_word(4)  ^   i_lane_4_g;
                                    o_lane_5_g <= lfsr_word(5)  ^   i_lane_5_g;
                                    o_lane_6_g <= lfsr_word(6)  ^   i_lane_6_g;
                                    o_lane_7_g <= lfsr_word(7)  ^   i_lane_7_g;
                                    o_lane_8_g <= lfsr_word(0)  ^   i_lane_8_g;
                                    o_lane_9_g <= lfsr_word(1)  ^   i_lane_9_g;
                                    o_lane_10_g <= lfsr_word(2) ^   i_lane_10_g;
                                    o_lane_11_g <= lfsr_word(3) ^   i_lane_11_g;
                                    o_lane_12_g <= lfsr_word(4) ^   i_lane_12_g;
                                    o_lane_13_g <= lfsr_word(5) ^   i_lane_13_g;
                                    o_lane_14_g <= lfsr_word(6) ^   i_lane_14_g;
                                    o_lane_15_g <= lfsr_word(7) ^   i_lane_15_g;
                                end
                            end

                            default: ; // NONE_DEGRADE: no output driven
                        endcase

                    // ---- pattern mode: raw LFSR output, count 128 cycles ---
                    end else begin
                        case (i_width_deg_lfsr_g)

                            DEGRADE_LANES_0_TO_7,
                            DEGRADE_LANES_8_TO_15,
                            DEGRADE_LANES_0_TO_3,
                            DEGRADE_LANES_4_TO_7,
                            DEGRADE_LANES_0_TO_15: begin

                                if (counter_lfsr == 7'd127) begin
                                    counter_lfsr   <= 7'd0;
                                    o_Lfsr_tx_done_g <= 1'b1;
                                    valid_frame_en_g <= 1'b0;
                                end else begin
                                    counter_lfsr   <= counter_lfsr + 7'd1;
                                    o_Lfsr_tx_done_g <= 1'b0;
                                    valid_frame_en_g <= 1'b1;

                                    case (i_width_deg_lfsr_g)

                                        DEGRADE_LANES_0_TO_7: begin
                                            if (lane_reversal_en_gabled) begin
                                                o_lane_0_g <= lfsr_word(7);
                                                o_lane_1_g <= lfsr_word(6);
                                                o_lane_2_g <= lfsr_word(5);
                                                o_lane_3_g <= lfsr_word(4);
                                                o_lane_4_g <= lfsr_word(3);
                                                o_lane_5_g <= lfsr_word(2);
                                                o_lane_6_g <= lfsr_word(1);
                                                o_lane_7_g <= lfsr_word(0);
                                            end else begin
                                                o_lane_0_g <= lfsr_word(0);
                                                o_lane_1_g <= lfsr_word(1);
                                                o_lane_2_g <= lfsr_word(2);
                                                o_lane_3_g <= lfsr_word(3);
                                                o_lane_4_g <= lfsr_word(4);
                                                o_lane_5_g <= lfsr_word(5);
                                                o_lane_6_g <= lfsr_word(6);
                                                o_lane_7_g <= lfsr_word(7);
                                            end
                                        end

                                        DEGRADE_LANES_8_TO_15: begin
                                            if (lane_reversal_en_gabled) begin
                                                o_lane_8_g <= lfsr_word(7);
                                                o_lane_9_g <= lfsr_word(6);
                                                o_lane_10_g <= lfsr_word(5);
                                                o_lane_11_g <= lfsr_word(4);
                                                o_lane_12_g <= lfsr_word(3);
                                                o_lane_13_g <= lfsr_word(2);
                                                o_lane_14_g <= lfsr_word(1);
                                                o_lane_15_g <= lfsr_word(0);
                                            end else begin
                                                o_lane_8_g  <= lfsr_word(0);
                                                o_lane_9_g  <= lfsr_word(1);
                                                o_lane_10_g <= lfsr_word(2);
                                                o_lane_11_g <= lfsr_word(3);
                                                o_lane_12_g <= lfsr_word(4);
                                                o_lane_13_g <= lfsr_word(5);
                                                o_lane_14_g <= lfsr_word(6);
                                                o_lane_15_g <= lfsr_word(7);
                                            end
                                        end

                                        DEGRADE_LANES_0_TO_3: begin
                                            if (lane_reversal_en_gabled) begin
                                                o_lane_0_g <= lfsr_word(7);
                                                o_lane_1_g <= lfsr_word(6);
                                                o_lane_2_g <= lfsr_word(5);
                                                o_lane_3_g <= lfsr_word(4);
                                            end else begin
                                                o_lane_0_g <= lfsr_word(0);
                                                o_lane_1_g <= lfsr_word(1);
                                                o_lane_2_g <= lfsr_word(2);
                                                o_lane_3_g <= lfsr_word(3);
                                            end
                                        end

                                        DEGRADE_LANES_4_TO_7: begin
                                            if (lane_reversal_en_gabled) begin
                                                o_lane_4_g <= lfsr_word(3);
                                                o_lane_5_g <= lfsr_word(2);
                                                o_lane_6_g <= lfsr_word(1);
                                                o_lane_7_g <= lfsr_word(0);
                                            end else begin
                                                o_lane_4_g <= lfsr_word(4);
                                                o_lane_5_g <= lfsr_word(5);
                                                o_lane_6_g <= lfsr_word(6);
                                                o_lane_7_g <= lfsr_word(7);
                                            end
                                        end

                                        DEGRADE_LANES_0_TO_15: begin
                                            if (lane_reversal_en_gabled) begin
                                                o_lane_0_g <= lfsr_word(7);
                                                o_lane_1_g <= lfsr_word(6);
                                                o_lane_2_g <= lfsr_word(5);
                                                o_lane_3_g <= lfsr_word(4);
                                                o_lane_4_g <= lfsr_word(3);
                                                o_lane_5_g <= lfsr_word(2);
                                                o_lane_6_g <= lfsr_word(1);
                                                o_lane_7_g <= lfsr_word(0);
                                                o_lane_8_g <= lfsr_word(7);
                                                o_lane_9_g <= lfsr_word(6);
                                                o_lane_10_g <= lfsr_word(5);
                                                o_lane_11_g <= lfsr_word(4);
                                                o_lane_12_g <= lfsr_word(3);
                                                o_lane_13_g <= lfsr_word(2);
                                                o_lane_14_g <= lfsr_word(1);
                                                o_lane_15_g <= lfsr_word(0);
                                            end else begin
                                                o_lane_0_g <= lfsr_word(0);
                                                o_lane_1_g <= lfsr_word(1);
                                                o_lane_2_g <= lfsr_word(2);
                                                o_lane_3_g <= lfsr_word(3);
                                                o_lane_4_g <= lfsr_word(4);
                                                o_lane_5_g <= lfsr_word(5);
                                                o_lane_6_g <= lfsr_word(6);
                                                o_lane_7_g <= lfsr_word(7);
                                                o_lane_8_g <= lfsr_word(0);
                                                o_lane_9_g <= lfsr_word(1);
                                                o_lane_10_g <= lfsr_word(2);
                                                o_lane_11_g <= lfsr_word(3);
                                                o_lane_12_g <= lfsr_word(4);
                                                o_lane_13_g <= lfsr_word(5);
                                                o_lane_14_g <= lfsr_word(6);
                                                o_lane_15_g <= lfsr_word(7);
                                            end
                                        end

                                        default: ;
                                    endcase
                                end // counter != 127
                            end // case group

                            default: ; // NONE_DEGRADE
                        endcase
                    end // pattern mode
                end // PATTERN_LFSR

                // ---------------------------------------------------------- //
                //  PER_LANE_IDE  — broadcast Lane-ID word for 64 cycles
                // ---------------------------------------------------------- //
                PER_LANE_IDE: begin
                    case (i_width_deg_lfsr_g)

                        DEGRADE_LANES_0_TO_7,
                        DEGRADE_LANES_8_TO_15,
                        DEGRADE_LANES_0_TO_3,
                        DEGRADE_LANES_4_TO_7,
                        DEGRADE_LANES_0_TO_15: begin

                            if (counter_per_lane == 6'd63) begin
                                counter_per_lane <= 6'd0;
                                o_Lfsr_tx_done_g   <= 1'b1;
                                valid_frame_en_g   <= 1'b0;
                            end else begin
                                counter_per_lane <= counter_per_lane + 6'd1;
                                o_Lfsr_tx_done_g   <= 1'b0;
                                valid_frame_en_g   <= 1'b1;

                                case (i_width_deg_lfsr_g)

                                    DEGRADE_LANES_0_TO_7: begin
                                        if (lane_reversal_en_gabled) begin
                                            o_lane_0_g <= lane_id_word(15);
                                            o_lane_1_g <= lane_id_word(14);
                                            o_lane_2_g <= lane_id_word(13);
                                            o_lane_3_g <= lane_id_word(12);
                                            o_lane_4_g <= lane_id_word(11);
                                            o_lane_5_g <= lane_id_word(10);
                                            o_lane_6_g <= lane_id_word(9);
                                            o_lane_7_g <= lane_id_word(8);
                                        end else begin
                                            o_lane_0_g <= lane_id_word(0);
                                            o_lane_1_g <= lane_id_word(1);
                                            o_lane_2_g <= lane_id_word(2);
                                            o_lane_3_g <= lane_id_word(3);
                                            o_lane_4_g <= lane_id_word(4);
                                            o_lane_5_g <= lane_id_word(5);
                                            o_lane_6_g <= lane_id_word(6);
                                            o_lane_7_g <= lane_id_word(7);
                                        end
                                    end

                                    DEGRADE_LANES_8_TO_15: begin
                                        if (lane_reversal_en_gabled) begin
                                            o_lane_8_g  <= lane_id_word(7);
                                            o_lane_9_g  <= lane_id_word(6);
                                            o_lane_10_g <= lane_id_word(5);
                                            o_lane_11_g <= lane_id_word(4);
                                            o_lane_12_g <= lane_id_word(3);
                                            o_lane_13_g <= lane_id_word(2);
                                            o_lane_14_g <= lane_id_word(1);
                                            o_lane_15_g <= lane_id_word(0);
                                        end else begin
                                            o_lane_8_g  <= lane_id_word(8);
                                            o_lane_9_g  <= lane_id_word(9);
                                            o_lane_10_g <= lane_id_word(10);
                                            o_lane_11_g <= lane_id_word(11);
                                            o_lane_12_g <= lane_id_word(12);
                                            o_lane_13_g <= lane_id_word(13);
                                            o_lane_14_g <= lane_id_word(14);
                                            o_lane_15_g <= lane_id_word(15);
                                        end
                                    end

                                    DEGRADE_LANES_0_TO_3: begin
                                        if (lane_reversal_en_gabled) begin
                                            o_lane_0_g <= lane_id_word(7);
                                            o_lane_1_g <= lane_id_word(6);
                                            o_lane_2_g <= lane_id_word(5);
                                            o_lane_3_g <= lane_id_word(4);
                                        end else begin
                                            o_lane_0_g <= lane_id_word(0);
                                            o_lane_1_g <= lane_id_word(1);
                                            o_lane_2_g <= lane_id_word(2);
                                            o_lane_3_g <= lane_id_word(3);
                                        end
                                    end

                                    DEGRADE_LANES_4_TO_7: begin
                                        if (lane_reversal_en_gabled) begin
                                            o_lane_4_g <= lane_id_word(3);
                                            o_lane_5_g <= lane_id_word(2);
                                            o_lane_6_g <= lane_id_word(1);
                                            o_lane_7_g <= lane_id_word(0);
                                        end else begin
                                            o_lane_4_g <= lane_id_word(4);
                                            o_lane_5_g <= lane_id_word(5);
                                            o_lane_6_g <= lane_id_word(6);
                                            o_lane_7_g <= lane_id_word(7);
                                        end
                                    end

                                    DEGRADE_LANES_0_TO_15: begin
                                        if (lane_reversal_en_gabled) begin
                                            o_lane_0_g <= lane_id_word(15);
                                            o_lane_1_g <= lane_id_word(14);
                                            o_lane_2_g <= lane_id_word(13);
                                            o_lane_3_g <= lane_id_word(12);
                                            o_lane_4_g <= lane_id_word(11);
                                            o_lane_5_g <= lane_id_word(10);
                                            o_lane_6_g  <= lane_id_word(9);
                                            o_lane_7_g  <= lane_id_word(8);
                                            o_lane_8_g  <= lane_id_word(7);
                                            o_lane_9_g  <= lane_id_word(6);
                                            o_lane_10_g <= lane_id_word(5);
                                            o_lane_11_g <= lane_id_word(4);
                                            o_lane_12_g <= lane_id_word(3);
                                            o_lane_13_g <= lane_id_word(2);
                                            o_lane_14_g <= lane_id_word(1);
                                            o_lane_15_g <= lane_id_word(0);
                                        end else begin
                                            o_lane_0_g <= lane_id_word(0);
                                            o_lane_1_g <= lane_id_word(1);
                                            o_lane_2_g <= lane_id_word(2);
                                            o_lane_3_g <= lane_id_word(3);
                                            o_lane_4_g <= lane_id_word(4);
                                            o_lane_5_g <= lane_id_word(5);
                                            o_lane_6_g <= lane_id_word(6);
                                            o_lane_7_g <= lane_id_word(7);
                                            o_lane_8_g <= lane_id_word(8);
                                            o_lane_9_g <= lane_id_word(9);
                                            o_lane_10_g <= lane_id_word(10);
                                            o_lane_11_g <= lane_id_word(11);
                                            o_lane_12_g <= lane_id_word(12);
                                            o_lane_13_g <= lane_id_word(13);
                                            o_lane_14_g <= lane_id_word(14);
                                            o_lane_15_g <= lane_id_word(15);
                                        end
                                    end

                                    default: ;
                                endcase
                            end // counter != 63
                        end // case group

                        default: ; // NONE_DEGRADE
                    endcase
                end // PER_LANE_IDE

            endcase
        end // normal operation
    end : datapath

endmodule
