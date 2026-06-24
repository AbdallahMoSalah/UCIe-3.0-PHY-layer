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

    /*
     * Upper 9 bits of the 32-bit LFSR output word captured each cycle.
     * o_lane_xx_23[8:0] holds bits [31:23] of the generated word.
     */
    logic [8:0]  o_lane_23 [0:7];

    /* One-cycle pipeline buffer for the datapath outputs */
    logic [WIDTH-1:0] temp_Data_by [0:15];

    /*=====================================================================
     * next_lfsr_state() 
     * Computes the next 32-bit output word and the next 23-bit LFSR state
     * from the current 23-bit LFSR state.
     *====================================================================*/
    function [31:0] next_lfsr_state;
        input [22:0] current_state;
        logic [31:0] next_state;
        begin
            next_state[0]  = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[1]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[2]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[3]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[4]  = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[12] ^ current_state[14] ^ current_state[16] ^ current_state[18] ^ current_state[22];
            next_state[5]  = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[21];
            next_state[6]  = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20] ^ current_state[22];
            next_state[7]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19];
            next_state[8]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[9]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[10] = current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[12] ^ current_state[14] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[11] = current_state[0] ^ current_state[2] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[10] ^ current_state[11] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[12] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[11] ^ current_state[12] ^ current_state[14] ^ current_state[17] ^ current_state[20];
            next_state[13] = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[12] ^ current_state[13] ^ current_state[15] ^ current_state[18] ^ current_state[21];
            next_state[14] = current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[8] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[19] ^ current_state[22];
            next_state[15] = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[14] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[20] ^ current_state[21];
            next_state[16] = current_state[1] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[21] ^ current_state[22];
            next_state[17] = current_state[0] ^ current_state[4] ^ current_state[6] ^ current_state[10] ^ current_state[11] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21] ^ current_state[22];
            next_state[18] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[7] ^ current_state[8] ^ current_state[11] ^ current_state[12] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[19] = current_state[0] ^ current_state[1] ^ current_state[3] ^ current_state[5] ^ current_state[9] ^ current_state[12] ^ current_state[13] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[20] = current_state[0] ^ current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[10] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20];
            next_state[21] = current_state[1] ^ current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[11] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21];
            next_state[22] = current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[15] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[23] = next_state[0]  ^ next_state[2]  ^ next_state[3]  ^ next_state[4]  ^ next_state[5]  ^ next_state[7]  ^ next_state[9]  ^ next_state[11] ^ next_state[13] ^ next_state[17] ^ next_state[19] ^ next_state[20];
            next_state[24] = next_state[1]  ^ next_state[3]  ^ next_state[4]  ^ next_state[5]  ^ next_state[6]  ^ next_state[8]  ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[18] ^ next_state[20] ^ next_state[21];
            next_state[25] = next_state[2]  ^ next_state[4]  ^ next_state[5]  ^ next_state[6]  ^ next_state[7]  ^ next_state[9]  ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[19] ^ next_state[21] ^ next_state[22];
            next_state[26] = next_state[0]  ^ next_state[2]  ^ next_state[3]  ^ next_state[6]  ^ next_state[7]  ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[20] ^ next_state[21] ^ next_state[22];
            next_state[27] = next_state[0]  ^ next_state[1]  ^ next_state[2]  ^ next_state[3]  ^ next_state[4]  ^ next_state[5]  ^ next_state[7]  ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[16] ^ next_state[22];
            next_state[28] = next_state[0]  ^ next_state[1]  ^ next_state[3]  ^ next_state[4]  ^ next_state[6]  ^ next_state[12] ^ next_state[14] ^ next_state[17] ^ next_state[21];
            next_state[29] = next_state[1]  ^ next_state[2]  ^ next_state[4]  ^ next_state[5]  ^ next_state[7]  ^ next_state[13] ^ next_state[15] ^ next_state[18] ^ next_state[22];
            next_state[30] = next_state[0]  ^ next_state[3]  ^ next_state[6]  ^ next_state[14] ^ next_state[19] ^ next_state[21];
            next_state[31] = next_state[1]  ^ next_state[4]  ^ next_state[7]  ^ next_state[15] ^ next_state[20] ^ next_state[22];
            next_lfsr_state = next_state;
        end
    endfunction

    /*=====================================================================
     * Helper task: initialise o_lane_23[lane] from a seed value.
     *
     * The 9 output bits (bits [31:23] of the first generated word) are
     * computed directly from the 23-bit seed using the same combinational
     * relationships as the LFSR polynomial.
     *
     * NOTE: This task is called both at reset and in the CLEAR_LFSR state,
     *       keeping the two paths in one place and eliminating the large
     *       block of repeated code that existed in the original design.
     *====================================================================*/
    task automatic init_lane_23;
        input  [2:0]  lane;        // Lane index 0-7
        input  [22:0] s;           // Seed value for that lane
        begin
            o_lane_23[lane][8] <= s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];

            o_lane_23[lane][7] <= s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0];

            o_lane_23[lane][6] <= s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];

            o_lane_23[lane][5] <= s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0];

            o_lane_23[lane][4] <= s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]
                                ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];

            o_lane_23[lane][3] <= s[17] ^ s[15] ^ s[10] ^ s[0]
                                ^ s[2]  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]
                                ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3];

            o_lane_23[lane][2] <= s[16] ^ s[14] ^ s[9]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0]
                                ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]
                                ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];

            o_lane_23[lane][1] <= s[15] ^ s[13] ^ s[8]  ^ s[0]
                                ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]
                                ^ s[17] ^ s[15] ^ s[10] ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]
                                ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3];

            o_lane_23[lane][0] <= s[14] ^ s[12] ^ s[7]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]
                                ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0]
                                ^ s[16] ^ s[14] ^ s[9]  ^ s[1]
                                ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0]
                                ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]
                                ^ s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]
                                ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
        end
    endtask

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

            for (i = 0; i < 8; i = i + 1) begin
                rx_lfsr_lane[i] <= SEED[i];
                init_lane_23(i, SEED[i]);
            end

            pattern_comp_en <= 0;

        end else begin

            case (current_state)

                /*----------------------------------------------------------
                 * IDLE: flush all pipeline buffers to zero
                 *---------------------------------------------------------*/
                IDLE: begin
                    pattern_comp_en <= 1'b0; // editted by momen
                    for (i = 0; i < 16; i = i + 1) begin
                        temp_Data_by[i] <= {WIDTH{1'b0}};
                        o_final_gene[i] <= {WIDTH{1'b0}};
                    end
                end

                /*----------------------------------------------------------
                 * CLEAR_LFSR: reload every LFSR with its initial seed
                 *             and recompute the first 9-bit output slice
                 *---------------------------------------------------------*/
                CLEAR_LFSR: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        temp_Data_by[i] <= {WIDTH{1'b0}};
                        o_final_gene[i] <= {WIDTH{1'b0}};
                    end

                    for (i = 0; i < 8; i = i + 1) begin
                        rx_lfsr_lane[i] <= SEED[i];
                        init_lane_23(i, SEED[i]);
                    end
                end

                /*----------------------------------------------------------
                 * PATTERN_LFSR: advance LFSRs, capture incoming words, and
                 *               build the locally-generated reference output
                 *---------------------------------------------------------*/
                PATTERN_LFSR: begin
                    if (i_enable_buffer) begin
                        /* Advance all 8 LFSR states */
                        for (i = 0; i < 8; i = i + 1)
                            {o_lane_23[i], rx_lfsr_lane[i]} <= next_lfsr_state(rx_lfsr_lane[i]);

                        pattern_comp_en <= 1'b1;

                        /* Latch incoming raw data through the pipeline */
                        for (i = 0; i < 16; i = i + 1)
                            temp_Data_by[i] <= i_data_in[i];

                        /*
                         * Zero ALL lanes first to avoid stale values from prior
                         * width-degradation runs leaking into the comparator.
                         * Then write only the active lanes.
                         */
                        for (i = 0; i < 16; i = i + 1)
                            o_final_gene[i] <= {WIDTH{1'b0}};

                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i] <= {rx_lfsr_lane[i], o_lane_23[i]};
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                for (i = 0; i < 8; i = i + 1)
                                    o_final_gene[i + 8] <= {rx_lfsr_lane[i], o_lane_23[i]};
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[i] <= {rx_lfsr_lane[i], o_lane_23[i]};
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                for (i = 0; i < 4; i = i + 1)
                                    o_final_gene[4 + i] <= {rx_lfsr_lane[i], o_lane_23[i]};
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                for (i = 0; i < 8; i = i + 1) begin
                                    o_final_gene[i]     <= {rx_lfsr_lane[i], o_lane_23[i]};
                                    o_final_gene[i + 8] <= {rx_lfsr_lane[i], o_lane_23[i]};
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
                        $display("LFSR_RX %m at %t: PER_LANE_IDE i_enable_buffer=1, i_data_in[0]=%h, o_final_gene[0]=%h", $time, i_data_in[0], o_final_gene[0]);
                        pattern_comp_en <= 1'b1;

                        for (i = 0; i < 16; i = i + 1)
                            temp_Data_by[i] <= i_data_in[i];

                        /*
                         * Zero ALL lanes first so non-active lanes never carry
                         * stale lane-ID tokens from a different width-mode run.
                         */
                        for (i = 0; i < 16; i = i + 1)
                            o_final_gene[i] <= {WIDTH{1'b0}};

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
                 * DATA_TRANSFER: advance LFSRs and XOR with incoming data
                 *               to descramble if descrambling is enabled
                 *---------------------------------------------------------*/
                DATA_TRANSFER: begin
                    /* Always advance the LFSRs logicardless of descramble flag */
                    for (i = 0; i < 8; i = i + 1)
                        {o_lane_23[i], rx_lfsr_lane[i]} <= next_lfsr_state(rx_lfsr_lane[i]);

                    if (i_descramble_en) begin
                        pattern_comp_en <= 1'b0;

                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                for (i = 0; i < 8; i = i + 1)
                                    temp_Data_by[i] <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i];
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                for (i = 0; i < 8; i = i + 1)
                                    temp_Data_by[i + 8] <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i + 8];
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                for (i = 0; i < 4; i = i + 1)
                                    temp_Data_by[i] <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i];
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                for (i = 0; i < 4; i = i + 1)
                                    temp_Data_by[4 + i] <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i];
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                for (i = 0; i < 8; i = i + 1) begin
                                    temp_Data_by[i]     <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i];
                                    temp_Data_by[i + 8] <= {rx_lfsr_lane[i], o_lane_23[i]} ^ i_data_in[i + 8];
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