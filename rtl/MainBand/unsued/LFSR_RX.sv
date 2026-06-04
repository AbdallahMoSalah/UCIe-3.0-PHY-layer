// =============================================================================
// Module : LFSR_RX  (SPEC-FIXED COPY — kept in unsued/ as the reference fix)
//
// Fixes the scrambler-word packing bug present in
//   rtl/MainBand/LFSR_RX/LFSR_RX.sv
//
// The production RX built each 32-bit reference / descramble word as
//   {rx_lfsr_lane[22:0], o_lane_23[8:0]}   // raw 23-bit state + 9 feedback bits
// which is NOT the UCIe scrambler output. That packing leaks the raw LFSR
// state into the top 23 bits and only carries 9 PRBS bits, so it never matches
// the 32 *consecutive* Data_Out bits the TX actually transmits. Verified: for
// lane 0 (seed 0x1DBFBC) the old RX emits 0x3B7F7874 while the spec window-0
// word is 0x3158E25C — a mismatch on every lane → descrambling/comparison fail.
//
// This copy generates the word the same way the fixed TX does
// (rtl/MainBand/unsued/LFSR_TX.sv): a leap-by-32 of the spec recurrence
//   G(X)=X^23+X^21+X^16+X^8+X^5+X^2+1, taps {22,20,15,7,4,1}
//   prbs32(s)[k] = f_k  (32 consecutive Data_Out bits, LSB = earliest)
//   nextstate32(s)      = state after 32 shifts
// Both functions are BM-verified bit-for-bit against lfsr_serial.sv.
//
// Every cycle the lane state advances via nextstate32(); the reference /
// descramble word is prbs32(state) of the *current* (pre-advance) state, so it
// aligns cycle-for-cycle with the fixed TX (which does exactly the same).
// FSM, ports, seeds, lane-ID tokens and the degrade/lane-reversal handling are
// unchanged from the production RX.
// =============================================================================

module LFSR_RX #(
    parameter WIDTH = 32        // Datapath width per lane (bits)
)(
    /*---------------------------------------------------------------------
     * Clock & Reset
     *--------------------------------------------------------------------*/
    input  logic              i_clk,
    input  logic              i_rst_n,

    /*---------------------------------------------------------------------
     * LTSM Interface
     *--------------------------------------------------------------------*/
    input  logic [2:0]        i_state,                   // Current LTSM state code
    input  logic [2:0]        i_width_deg_lfsr,     // Active-lane mapping code
    input  logic              i_active_state_entered,     // Pulse when LTSM enters Active

    /*---------------------------------------------------------------------
     * HM Interface
     *--------------------------------------------------------------------*/
    input  logic              i_descramble_en, // Enable descrambling
    input  logic              i_enable_buffer,                // Gate from buffer FOR TRAINING MODE(PATTERN LFSR & PER_LANE_ID)

    /*---------------------------------------------------------------------
     * Deserialiser Input  (16 lanes)
     *--------------------------------------------------------------------*/
    input  logic [WIDTH-1:0]  i_data_in [0:15],

    /*---------------------------------------------------------------------
     * LTSM Output – raw bypass words (16 lanes)
     *--------------------------------------------------------------------*/
    output logic  [WIDTH-1:0]  o_Data_by    [0:15],

    /*---------------------------------------------------------------------
     * LTSM Output – locally-generated reference words (16 lanes)
     *--------------------------------------------------------------------*/
    output logic  [WIDTH-1:0]  o_final_gene [0:15],

    /*---------------------------------------------------------------------
     * Comparator enable
     *--------------------------------------------------------------------*/
    output logic               pattern_comp_en
);

    /*=====================================================================
     * Local Parameters
     *====================================================================*/

    /* FSM states */
    localparam IDLE          = 3'b000;
    localparam CLEAR_LFSR    = 3'b001;
    localparam PATTERN_LFSR  = 3'b010;
    localparam PER_LANE_IDE  = 3'b011;
    localparam DATA_TRANSFER = 3'b100;

    /* Lane-mapping codes */
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    /*
     * Lane-ID tokens: format is  1010_<8-bit lane index>_1010
     * 16 constants, one per logical lane.
     */
    localparam [15:0] LANE_ID [0:15] = '{
        16'b1010_00000000_1010,   // Lane  0
        16'b1010_00000001_1010,   // Lane  1
        16'b1010_00000010_1010,   // Lane  2
        16'b1010_00000011_1010,   // Lane  3
        16'b1010_00000100_1010,   // Lane  4
        16'b1010_00000101_1010,   // Lane  5
        16'b1010_00000110_1010,   // Lane  6
        16'b1010_00000111_1010,   // Lane  7
        16'b1010_00001000_1010,   // Lane  8
        16'b1010_00001001_1010,   // Lane  9
        16'b1010_00001010_1010,   // Lane 10
        16'b1010_00001011_1010,   // Lane 11
        16'b1010_00001100_1010,   // Lane 12
        16'b1010_00001101_1010,   // Lane 13
        16'b1010_00001110_1010,   // Lane 14
        16'b1010_00001111_1010    // Lane 15
    };

    /*
     * Per-lane LFSR seeds (8 physical seeds; lanes 8-15 re-use seeds 0-7
     * when degraded to half-width operation).
     */
    localparam [22:0] SEED [0:7] = '{
        23'h1DBFBC,   // Seed for lane 0
        23'h0607BB,   // Seed for lane 1
        23'h1EC760,   // Seed for lane 2
        23'h18C0DB,   // Seed for lane 3
        23'h010F12,   // Seed for lane 4
        23'h19CFC9,   // Seed for lane 5
        23'h0277CE,   // Seed for lane 6
        23'h1BB807    // Seed for lane 7
    };

    /*=====================================================================
     * Internal logicisters / logics
     *====================================================================*/

    /* FSM state logicister and LTSM edge-detect helper */
    logic [2:0] current_state;
    logic [2:0] i_state_reg;
    logic      i_state_changed  ;

    assign i_state_changed = (i_state_reg != i_state)? 1'b1 : 1'b0;

    /*
     * Per-lane LFSR shift logicisters (23-bit running state).
     * Index [0:7] – only 8 physical LFSRs exist; upper 8 lanes share them
     * when the link degrades.
     */
    logic [22:0] rx_lfsr_lane [0:7];

    /* One-cycle pipeline buffer for the datapath outputs */
    logic [WIDTH-1:0] temp_Data_by [0:15];

    /*=====================================================================
     * Leap-by-32 of the spec scrambler G(X)=X^23+X^21+X^16+X^8+X^5+X^2+1.
     * Auto-generated from the bit-serial recurrence in lfsr_serial.sv:
     *   f = s[22]^s[20]^s[15]^s[7]^s[4]^s[1] ; s' = {s[21:0], f}
     * prbs32(s)[j] = f_j (32 consecutive Data_Out bits, LSB = earliest bit,
     *   bit-for-bit equal to lfsr_serial agg_word). nextstate32(s) = s after 32 shifts.
     *====================================================================*/
    function automatic logic [31:0] prbs32(input logic [22:0] s);
        begin
            prbs32[ 0] = s[1] ^ s[4] ^ s[7] ^ s[15] ^ s[20] ^ s[22];
            prbs32[ 1] = s[0] ^ s[3] ^ s[6] ^ s[14] ^ s[19] ^ s[21];
            prbs32[ 2] = s[1] ^ s[2] ^ s[4] ^ s[5] ^ s[7] ^ s[13] ^ s[15] ^ s[18] ^ s[22];
            prbs32[ 3] = s[0] ^ s[1] ^ s[3] ^ s[4] ^ s[6] ^ s[12] ^ s[14] ^ s[17] ^ s[21];
            prbs32[ 4] = s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[7] ^ s[11] ^ s[13] ^ s[15] ^ s[16] ^ s[22];
            prbs32[ 5] = s[0] ^ s[2] ^ s[3] ^ s[6] ^ s[7] ^ s[10] ^ s[12] ^ s[14] ^ s[20] ^ s[21] ^ s[22];
            prbs32[ 6] = s[2] ^ s[4] ^ s[5] ^ s[6] ^ s[7] ^ s[9] ^ s[11] ^ s[13] ^ s[15] ^ s[19] ^ s[21] ^ s[22];
            prbs32[ 7] = s[1] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[8] ^ s[10] ^ s[12] ^ s[14] ^ s[18] ^ s[20] ^ s[21];
            prbs32[ 8] = s[0] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[7] ^ s[9] ^ s[11] ^ s[13] ^ s[17] ^ s[19] ^ s[20];
            prbs32[ 9] = s[2] ^ s[3] ^ s[6] ^ s[7] ^ s[8] ^ s[10] ^ s[12] ^ s[15] ^ s[16] ^ s[18] ^ s[19] ^ s[20] ^ s[22];
            prbs32[10] = s[1] ^ s[2] ^ s[5] ^ s[6] ^ s[7] ^ s[9] ^ s[11] ^ s[14] ^ s[15] ^ s[17] ^ s[18] ^ s[19] ^ s[21];
            prbs32[11] = s[0] ^ s[1] ^ s[4] ^ s[5] ^ s[6] ^ s[8] ^ s[10] ^ s[13] ^ s[14] ^ s[16] ^ s[17] ^ s[18] ^ s[20];
            prbs32[12] = s[0] ^ s[1] ^ s[3] ^ s[5] ^ s[9] ^ s[12] ^ s[13] ^ s[16] ^ s[17] ^ s[19] ^ s[20] ^ s[22];
            prbs32[13] = s[0] ^ s[1] ^ s[2] ^ s[7] ^ s[8] ^ s[11] ^ s[12] ^ s[16] ^ s[18] ^ s[19] ^ s[20] ^ s[21] ^ s[22];
            prbs32[14] = s[0] ^ s[4] ^ s[6] ^ s[10] ^ s[11] ^ s[17] ^ s[18] ^ s[19] ^ s[21] ^ s[22];
            prbs32[15] = s[1] ^ s[3] ^ s[4] ^ s[5] ^ s[7] ^ s[9] ^ s[10] ^ s[15] ^ s[16] ^ s[17] ^ s[18] ^ s[21] ^ s[22];
            prbs32[16] = s[0] ^ s[2] ^ s[3] ^ s[4] ^ s[6] ^ s[8] ^ s[9] ^ s[14] ^ s[15] ^ s[16] ^ s[17] ^ s[20] ^ s[21];
            prbs32[17] = s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[8] ^ s[13] ^ s[14] ^ s[16] ^ s[19] ^ s[22];
            prbs32[18] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[7] ^ s[12] ^ s[13] ^ s[15] ^ s[18] ^ s[21];
            prbs32[19] = s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[6] ^ s[11] ^ s[12] ^ s[14] ^ s[17] ^ s[20];
            prbs32[20] = s[0] ^ s[2] ^ s[4] ^ s[5] ^ s[7] ^ s[10] ^ s[11] ^ s[13] ^ s[15] ^ s[16] ^ s[19] ^ s[20] ^ s[22];
            prbs32[21] = s[3] ^ s[6] ^ s[7] ^ s[9] ^ s[10] ^ s[12] ^ s[14] ^ s[18] ^ s[19] ^ s[20] ^ s[21] ^ s[22];
            prbs32[22] = s[2] ^ s[5] ^ s[6] ^ s[8] ^ s[9] ^ s[11] ^ s[13] ^ s[17] ^ s[18] ^ s[19] ^ s[20] ^ s[21];
            prbs32[23] = s[1] ^ s[4] ^ s[5] ^ s[7] ^ s[8] ^ s[10] ^ s[12] ^ s[16] ^ s[17] ^ s[18] ^ s[19] ^ s[20];
            prbs32[24] = s[0] ^ s[3] ^ s[4] ^ s[6] ^ s[7] ^ s[9] ^ s[11] ^ s[15] ^ s[16] ^ s[17] ^ s[18] ^ s[19];
            prbs32[25] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[7] ^ s[8] ^ s[10] ^ s[14] ^ s[16] ^ s[17] ^ s[18] ^ s[20] ^ s[22];
            prbs32[26] = s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[7] ^ s[9] ^ s[13] ^ s[15] ^ s[16] ^ s[17] ^ s[19] ^ s[21];
            prbs32[27] = s[0] ^ s[2] ^ s[3] ^ s[5] ^ s[6] ^ s[7] ^ s[8] ^ s[12] ^ s[14] ^ s[16] ^ s[18] ^ s[22];
            prbs32[28] = s[2] ^ s[5] ^ s[6] ^ s[11] ^ s[13] ^ s[17] ^ s[20] ^ s[21] ^ s[22];
            prbs32[29] = s[1] ^ s[4] ^ s[5] ^ s[10] ^ s[12] ^ s[16] ^ s[19] ^ s[20] ^ s[21];
            prbs32[30] = s[0] ^ s[3] ^ s[4] ^ s[9] ^ s[11] ^ s[15] ^ s[18] ^ s[19] ^ s[20];
            prbs32[31] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[7] ^ s[8] ^ s[10] ^ s[14] ^ s[15] ^ s[17] ^ s[18] ^ s[19] ^ s[20] ^ s[22];
        end
    endfunction

    function automatic logic [22:0] nextstate32(input logic [22:0] s);
        begin
            nextstate32[ 0] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[7] ^ s[8] ^ s[10] ^ s[14] ^ s[15] ^ s[17] ^ s[18] ^ s[19] ^ s[20] ^ s[22];
            nextstate32[ 1] = s[0] ^ s[3] ^ s[4] ^ s[9] ^ s[11] ^ s[15] ^ s[18] ^ s[19] ^ s[20];
            nextstate32[ 2] = s[1] ^ s[4] ^ s[5] ^ s[10] ^ s[12] ^ s[16] ^ s[19] ^ s[20] ^ s[21];
            nextstate32[ 3] = s[2] ^ s[5] ^ s[6] ^ s[11] ^ s[13] ^ s[17] ^ s[20] ^ s[21] ^ s[22];
            nextstate32[ 4] = s[0] ^ s[2] ^ s[3] ^ s[5] ^ s[6] ^ s[7] ^ s[8] ^ s[12] ^ s[14] ^ s[16] ^ s[18] ^ s[22];
            nextstate32[ 5] = s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[7] ^ s[9] ^ s[13] ^ s[15] ^ s[16] ^ s[17] ^ s[19] ^ s[21];
            nextstate32[ 6] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[7] ^ s[8] ^ s[10] ^ s[14] ^ s[16] ^ s[17] ^ s[18] ^ s[20] ^ s[22];
            nextstate32[ 7] = s[0] ^ s[3] ^ s[4] ^ s[6] ^ s[7] ^ s[9] ^ s[11] ^ s[15] ^ s[16] ^ s[17] ^ s[18] ^ s[19];
            nextstate32[ 8] = s[1] ^ s[4] ^ s[5] ^ s[7] ^ s[8] ^ s[10] ^ s[12] ^ s[16] ^ s[17] ^ s[18] ^ s[19] ^ s[20];
            nextstate32[ 9] = s[2] ^ s[5] ^ s[6] ^ s[8] ^ s[9] ^ s[11] ^ s[13] ^ s[17] ^ s[18] ^ s[19] ^ s[20] ^ s[21];
            nextstate32[10] = s[3] ^ s[6] ^ s[7] ^ s[9] ^ s[10] ^ s[12] ^ s[14] ^ s[18] ^ s[19] ^ s[20] ^ s[21] ^ s[22];
            nextstate32[11] = s[0] ^ s[2] ^ s[4] ^ s[5] ^ s[7] ^ s[10] ^ s[11] ^ s[13] ^ s[15] ^ s[16] ^ s[19] ^ s[20] ^ s[22];
            nextstate32[12] = s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[6] ^ s[11] ^ s[12] ^ s[14] ^ s[17] ^ s[20];
            nextstate32[13] = s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[7] ^ s[12] ^ s[13] ^ s[15] ^ s[18] ^ s[21];
            nextstate32[14] = s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[8] ^ s[13] ^ s[14] ^ s[16] ^ s[19] ^ s[22];
            nextstate32[15] = s[0] ^ s[2] ^ s[3] ^ s[4] ^ s[6] ^ s[8] ^ s[9] ^ s[14] ^ s[15] ^ s[16] ^ s[17] ^ s[20] ^ s[21];
            nextstate32[16] = s[1] ^ s[3] ^ s[4] ^ s[5] ^ s[7] ^ s[9] ^ s[10] ^ s[15] ^ s[16] ^ s[17] ^ s[18] ^ s[21] ^ s[22];
            nextstate32[17] = s[0] ^ s[4] ^ s[6] ^ s[10] ^ s[11] ^ s[17] ^ s[18] ^ s[19] ^ s[21] ^ s[22];
            nextstate32[18] = s[0] ^ s[1] ^ s[2] ^ s[7] ^ s[8] ^ s[11] ^ s[12] ^ s[16] ^ s[18] ^ s[19] ^ s[20] ^ s[21] ^ s[22];
            nextstate32[19] = s[0] ^ s[1] ^ s[3] ^ s[5] ^ s[9] ^ s[12] ^ s[13] ^ s[16] ^ s[17] ^ s[19] ^ s[20] ^ s[22];
            nextstate32[20] = s[0] ^ s[1] ^ s[4] ^ s[5] ^ s[6] ^ s[8] ^ s[10] ^ s[13] ^ s[14] ^ s[16] ^ s[17] ^ s[18] ^ s[20];
            nextstate32[21] = s[1] ^ s[2] ^ s[5] ^ s[6] ^ s[7] ^ s[9] ^ s[11] ^ s[14] ^ s[15] ^ s[17] ^ s[18] ^ s[19] ^ s[21];
            nextstate32[22] = s[2] ^ s[3] ^ s[6] ^ s[7] ^ s[8] ^ s[10] ^ s[12] ^ s[15] ^ s[16] ^ s[18] ^ s[19] ^ s[20] ^ s[22];
        end
    endfunction

    /*=====================================================================
     * FSM – State Transitions
     *====================================================================*/
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            current_state <= IDLE;
            i_state_reg   <= 3'b000;
        end else begin
            i_state_reg <= i_state;

            case (current_state)
                /*----------------------------------------------------------
                 * IDLE: wait for a valid LTSM transition or active-state flag
                 *---------------------------------------------------------*/
                IDLE: begin
                    if      (i_active_state_entered)                       current_state <= DATA_TRANSFER;
                    else if (i_state_changed && (i_state == CLEAR_LFSR))   current_state <= CLEAR_LFSR;
                    else if (i_state_changed && (i_state == PATTERN_LFSR)) current_state <= PATTERN_LFSR;
                    else if (i_state_changed && (i_state == PER_LANE_IDE)) current_state <= PER_LANE_IDE;
                    else                                                   current_state <= IDLE;
                end

                /*----------------------------------------------------------
                 * CLEAR_LFSR: single-cycle reset of seeds; return to IDLE
                 *---------------------------------------------------------*/
                CLEAR_LFSR: begin
                    current_state <= IDLE;
                end

                /*----------------------------------------------------------
                 * PATTERN_LFSR: stay until LTSM returns to idle (2'b00)
                 *---------------------------------------------------------*/
                PATTERN_LFSR: begin
                    current_state <= (i_state == IDLE) ? IDLE : PATTERN_LFSR;
                end

                /*----------------------------------------------------------
                 * PER_LANE_IDE: stay until LTSM returns to idle (2'b00)
                 *---------------------------------------------------------*/
                PER_LANE_IDE: begin
                    current_state <= (i_state == IDLE) ? IDLE : PER_LANE_IDE;
                end

                /*----------------------------------------------------------
                 * DATA_TRANSFER: stay while active-state flag is asserted
                 *---------------------------------------------------------*/
                DATA_TRANSFER: begin
                    current_state <= (i_active_state_entered) ? DATA_TRANSFER : IDLE;
                end

                default: current_state <= IDLE;
            endcase
        end
    end

    /*=====================================================================
     * Main Datapath – LFSR update, pattern generation, and descrambling
     *====================================================================*/
    integer i;  // Loop variable used across always blocks

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            /*--------------------------------------------------------------
             * Reset: zero all pipeline logicisters and reload LFSR seeds
             *------------------------------------------------------------*/
            for (i = 0; i < 16; i = i + 1) begin
                temp_Data_by[i]  <= {WIDTH{1'b0}};
                o_final_gene[i]  <= {WIDTH{1'b0}};
            end

            for (i = 0; i < 8; i = i + 1)
                rx_lfsr_lane[i] <= SEED[i];

            pattern_comp_en <= 0;

        end else begin

            case (current_state)

                /*----------------------------------------------------------
                 * IDLE: flush all pipeline buffers to zero
                 *---------------------------------------------------------*/
                IDLE: begin
                    pattern_comp_en <= 1'b0; // editted by momen
                    for (i = 0; i < 16; i = i + 1)
                        temp_Data_by[i] <= {WIDTH{1'b0}};
                end

                /*----------------------------------------------------------
                 * CLEAR_LFSR: reload every LFSR with its initial seed
                 *---------------------------------------------------------*/
                CLEAR_LFSR: begin
                    for (i = 0; i < 16; i = i + 1)
                        temp_Data_by[i] <= {WIDTH{1'b0}};

                    for (i = 0; i < 8; i = i + 1)
                        rx_lfsr_lane[i] <= SEED[i];
                end

                /*----------------------------------------------------------
                 * PATTERN_LFSR: advance LFSRs, capture incoming words, and
                 *               build the locally-generated reference output.
                 *               o_final_gene = prbs32(current state) so it
                 *               matches the TX-transmitted scrambler word.
                 *---------------------------------------------------------*/
                PATTERN_LFSR: begin
                    if (i_enable_buffer) begin
                        /* Advance all 8 LFSR states by 32 (one 32-bit word) */
                        for (i = 0; i < 8; i = i + 1)
                            rx_lfsr_lane[i] <= nextstate32(rx_lfsr_lane[i]);

                        pattern_comp_en <= 1'b1;

                        /* Latch incoming raw data through the pipeline */
                        for (i = 0; i < 16; i = i + 1)
                            temp_Data_by[i] <= i_data_in[i];

                        /*
                         * Build reference words.
                         * Lanes 8-15 mirror LFSR outputs 0-7 when active.
                         */
                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i] <= prbs32(rx_lfsr_lane[i]);
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i + 8] <= prbs32(rx_lfsr_lane[i]);
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[i] <= prbs32(rx_lfsr_lane[i]);
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[4 + i] <= prbs32(rx_lfsr_lane[i]);
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                for (i = 0; i < 8; i = i + 1) begin
                                    o_final_gene[i]     <= prbs32(rx_lfsr_lane[i]);
                                    o_final_gene[i + 8] <= prbs32(rx_lfsr_lane[i]);
                                end
                            end
                        endcase
                    end
                end

                /*----------------------------------------------------------
                 * PER_LANE_IDE: drive fixed Lane-ID tokens as reference words
                 *---------------------------------------------------------*/
                PER_LANE_IDE: begin
                    if (i_enable_buffer) begin
                        pattern_comp_en <= 1'b1;

                        for (i = 0; i < 16; i = i + 1)
                            temp_Data_by[i] <= i_data_in[i];

                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i] <= {LANE_ID[i], LANE_ID[i]};
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i + 8] <= {LANE_ID[i + 8], LANE_ID[i + 8]};
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[i] <= {LANE_ID[i], LANE_ID[i]};
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[4 + i] <= {LANE_ID[4 + i], LANE_ID[4 + i]};
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                for (i = 0; i < 16; i = i + 1)
                                    o_final_gene[i] <= {LANE_ID[i], LANE_ID[i]};
                            end
                        endcase
                    end
                end

                /*----------------------------------------------------------
                 * DATA_TRANSFER: advance LFSRs and XOR prbs32(current state)
                 *               with incoming data to descramble.
                 *---------------------------------------------------------*/
                DATA_TRANSFER: begin
                    /* Always advance the LFSRs logicardless of descramble flag */
                    for (i = 0; i < 8; i = i + 1)
                        rx_lfsr_lane[i] <= nextstate32(rx_lfsr_lane[i]);

                    if (i_descramble_en) begin
                        pattern_comp_en <= 1'b0;

                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                for (i = 0; i < 8; i = i + 1)
                                    temp_Data_by[i] <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[i];
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                for (i = 0; i < 8; i = i + 1)
                                    temp_Data_by[i + 8] <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[i + 8];
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                for (i = 0; i < 4; i = i + 1)
                                    temp_Data_by[i] <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[i];
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                // data arrives on physical lanes 4-7; descramble
                                // those (was reading i_data_in[i] = empty lanes 0-3).
                                for (i = 0; i < 4; i = i + 1)
                                    temp_Data_by[4 + i] <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[4 + i];
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                for (i = 0; i < 8; i = i + 1) begin
                                    temp_Data_by[i]     <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[i];
                                    temp_Data_by[i + 8] <= prbs32(rx_lfsr_lane[i]) ^ i_data_in[i + 8];
                                end
                            end
                        endcase
                    end
                end

            endcase
        end
    end

    /*=====================================================================
     * Output Pipeline – logicister temp_Data_by → o_Data_by
     *
     * Two output paths:
     *   1. Descrambled path : valid when descrambling is active AND the
     *                         link has entered the Active state.
     *   2. Raw bypass path  : valid when the buffer is enabled (training
     *                         phases that need to observe raw lane data).
     *====================================================================*/
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 16; i = i + 1)
                o_Data_by[i] <= {WIDTH{1'b0}};
        end else begin
            if (i_descramble_en && i_active_state_entered) begin
                /* Output the descrambled words computed this cycle */
                for (i = 0; i < 16; i = i + 1)
                    o_Data_by[i] <= temp_Data_by[i];
            end else if (i_enable_buffer) begin
                /* Pass raw deserialiser data straight through */
                for (i = 0; i < 16; i = i + 1)
                    o_Data_by[i] <= i_data_in[i];
            end
            /* Otherwise hold the last value (no explicit else needed) */
        end
    end

endmodule