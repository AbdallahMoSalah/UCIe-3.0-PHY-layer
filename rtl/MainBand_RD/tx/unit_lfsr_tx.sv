

module LFSR_TX #(
    parameter WIDTH = 32
)(
    input  logic        i_clk,                        // Clock signal
    input  logic        i_rst_n,                      // Active-low synchronous reset
    input  logic [2:0]  i_state,                      // Requested state from controller
    input  logic        i_scramble_en, // 1: scramble data, 0: pass pattern only
    input  logic [2:0]  i_width_deg_lfsr,        // Lane group selection
    input  logic        i_reversal_en,            // Enable physical lane reversal
    input  logic        i_active_state_entered,       // Pulse: active (DATA_TRANSFER) state entered

    // -------------------------------------------------------------------------
    // 16 input data lanes (indexed 0-15)
    // -------------------------------------------------------------------------
    input  logic [WIDTH-1:0] i_lane [0:15],

    // -------------------------------------------------------------------------
    // 16 output data lanes (indexed 0-15)
    // -------------------------------------------------------------------------
    output logic  [WIDTH-1:0] o_lane [0:15],
    output logic  o_ser_en_lfsr,
    output logic  o_Lfsr_tx_done,   // Pulses high when current LFSR/ID phase completes
    output logic  o_valid_frame_en    // High while frames are actively being transmitted
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam IDLE          = 3'b000;
    localparam CLEAR_LFSR    = 3'b001;
    localparam PATTERN_LFSR  = 3'b010;
    localparam PER_LANE_IDE  = 3'b011;
    localparam DATA_TRANSFER = 3'b100;

    // =========================================================================
    // Lane group encoding for i_width_deg_lfsr
    // =========================================================================
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    // =========================================================================
    // Counter limits
    // =========================================================================
    localparam COUNT_LFSR     = 128; // PATTERN_LFSR runs for 128 cycles
    localparam COUNT_PER_LANE = 64;  // PER_LANE_IDE runs for 64 cycles

    // =========================================================================
    // Lane ID constants: format = 1010_<8-bit lane index>_1010
    // =========================================================================
    localparam [15:0] LANE_ID [0:15] = '{
        16'b1010_00000000_1010, // Lane  0
        16'b1010_00000001_1010, // Lane  1
        16'b1010_00000010_1010, // Lane  2
        16'b1010_00000011_1010, // Lane  3
        16'b1010_00000100_1010, // Lane  4
        16'b1010_00000101_1010, // Lane  5
        16'b1010_00000110_1010, // Lane  6
        16'b1010_00000111_1010, // Lane  7
        16'b1010_00001000_1010, // Lane  8
        16'b1010_00001001_1010, // Lane  9
        16'b1010_00001010_1010, // Lane 10
        16'b1010_00001011_1010, // Lane 11
        16'b1010_00001100_1010, // Lane 12
        16'b1010_00001101_1010, // Lane 13
        16'b1010_00001110_1010, // Lane 14
        16'b1010_00001111_1010  // Lane 15
    };

    // =========================================================================
    // LFSR seed values per lane (lanes 0-7; lanes 8-15 share the same LFSRs)
    // =========================================================================
    logic [22:0] SEED [0:7];
    assign SEED[0] = 23'h1DBFBC;
    assign SEED[1] = 23'h0607BB;
    assign SEED[2] = 23'h1EC760;
    assign SEED[3] = 23'h18C0DB;
    assign SEED[4] = 23'h010F12;
    assign SEED[5] = 23'h19CFC9;
    assign SEED[6] = 23'h0277CE;
    assign SEED[7] = 23'h1BB807;

    // =========================================================================
    // Internal logicisters
    // =========================================================================
    logic [2:0] current_state;          // Active FSM state
    logic [2:0] i_state_reg;            // logicistered copy of i_state for edge detection
    logic [7:0] counter_lfsr;           // Counts PATTERN_LFSR cycles  (0-127)
    logic [6:0] counter_per_lane;       // Counts PER_LANE_IDE cycles  (0-63)
    logic       lane_reversal_enabled;  // Latched reversal flag

    // LFSR state logicisters for each of the 8 logical lanes
    logic [22:0] tx_lfsr [0:7];

    // Upper 9-bit portion of the 32-bit LFSR output (bit 23 through bit 31)
    logic [8:0]  o_lane_23 [0:7];

    // Detect a change on the external state request input
    logic i_state_changed;
    assign i_state_changed = (i_state_reg != i_state) ? 1'b1 : 1'b0;

    // =========================================================================
    // Helper function: compute initial o_lane_23 from a given seed.
    // Bit positions correspond to the combinational unrolling of the LFSR
    // feedback polynomial for 9 additional steps beyond bit 22.
    // =========================================================================
    function [8:0] compute_initial_23;
        input [22:0] s; // seed
        begin
            compute_initial_23[8] = s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            compute_initial_23[7] = s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3]  ^ s[0];
            compute_initial_23[6] = s[20] ^ s[18] ^ s[13] ^ s[5]  ^ s[2]  ^ s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1];
            compute_initial_23[5] = s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6] ^ s[3] ^ s[0];
            compute_initial_23[4] = s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5] ^ s[2]
                                  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            compute_initial_23[3] = s[17] ^ s[15] ^ s[10] ^ s[0]  ^ s[2]  ^ s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1]
                                  ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6] ^ s[3];
            compute_initial_23[2] = s[16] ^ s[14] ^ s[9]  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3] ^ s[0]
                                  ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5] ^ s[2]
                                  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
            compute_initial_23[1] = s[15] ^ s[13] ^ s[8]  ^ s[0]  ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5] ^ s[2]
                                  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]  ^ s[17] ^ s[15] ^ s[10] ^ s[2]
                                  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]  ^ s[19] ^ s[17] ^ s[12] ^ s[4]
                                  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3];
            compute_initial_23[0] = s[14] ^ s[12] ^ s[7]  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1]
                                  ^ s[19] ^ s[17] ^ s[12] ^ s[4]  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6] ^ s[3] ^ s[0]
                                  ^ s[16] ^ s[14] ^ s[9]  ^ s[1]  ^ s[21] ^ s[19] ^ s[14] ^ s[6]  ^ s[3] ^ s[0]
                                  ^ s[18] ^ s[16] ^ s[11] ^ s[3]  ^ s[0]  ^ s[20] ^ s[18] ^ s[13] ^ s[5] ^ s[2]
                                  ^ s[22] ^ s[20] ^ s[15] ^ s[7]  ^ s[4]  ^ s[1];
        end
    endfunction

    // =========================================================================
    // next_lfsr_state function 
    // Computes the next 32-bit LFSR output from the current 23-bit state.
    // Bits [22:0]  → next LFSR logicister value
    // Bits [31:23] → scrambled output bits for this clock cycle
    // =========================================================================
    function [31:0] next_lfsr_state;
        input [22:0] current_state;
        logic [31:0] next_state;
        begin
            next_state[0]  = current_state[1]  ^ current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[7]  ^ current_state[8]  ^ current_state[10] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[1]  = current_state[0]  ^ current_state[3]  ^ current_state[4]  ^ current_state[9]  ^ current_state[11] ^ current_state[15] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[2]  = current_state[1]  ^ current_state[4]  ^ current_state[5]  ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[3]  = current_state[2]  ^ current_state[5]  ^ current_state[6]  ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[4]  = current_state[0]  ^ current_state[2]  ^ current_state[3]  ^ current_state[5]  ^ current_state[6]  ^ current_state[7]  ^ current_state[8]  ^ current_state[12] ^ current_state[14] ^ current_state[16] ^ current_state[18] ^ current_state[22];
            next_state[5]  = current_state[0]  ^ current_state[1]  ^ current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[5]  ^ current_state[6]  ^ current_state[7]  ^ current_state[9]  ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[21];
            next_state[6]  = current_state[1]  ^ current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[5]  ^ current_state[6]  ^ current_state[7]  ^ current_state[8]  ^ current_state[10] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20] ^ current_state[22];
            next_state[7]  = current_state[0]  ^ current_state[3]  ^ current_state[4]  ^ current_state[6]  ^ current_state[7]  ^ current_state[9]  ^ current_state[11] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19];
            next_state[8]  = current_state[1]  ^ current_state[4]  ^ current_state[5]  ^ current_state[7]  ^ current_state[8]  ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[9]  = current_state[2]  ^ current_state[5]  ^ current_state[6]  ^ current_state[8]  ^ current_state[9]  ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[10] = current_state[3]  ^ current_state[6]  ^ current_state[7]  ^ current_state[9]  ^ current_state[10] ^ current_state[12] ^ current_state[14] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[11] = current_state[0]  ^ current_state[2]  ^ current_state[4]  ^ current_state[5]  ^ current_state[7]  ^ current_state[10] ^ current_state[11] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[12] = current_state[0]  ^ current_state[1]  ^ current_state[2]  ^ current_state[3]  ^ current_state[6]  ^ current_state[11] ^ current_state[12] ^ current_state[14] ^ current_state[17] ^ current_state[20];
            next_state[13] = current_state[1]  ^ current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[7]  ^ current_state[12] ^ current_state[13] ^ current_state[15] ^ current_state[18] ^ current_state[21];
            next_state[14] = current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[5]  ^ current_state[8]  ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[19] ^ current_state[22];
            next_state[15] = current_state[0]  ^ current_state[2]  ^ current_state[3]  ^ current_state[4]  ^ current_state[6]  ^ current_state[8]  ^ current_state[9]  ^ current_state[14] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[20] ^ current_state[21];
            next_state[16] = current_state[1]  ^ current_state[3]  ^ current_state[4]  ^ current_state[5]  ^ current_state[7]  ^ current_state[9]  ^ current_state[10] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[21] ^ current_state[22];
            next_state[17] = current_state[0]  ^ current_state[4]  ^ current_state[6]  ^ current_state[10] ^ current_state[11] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21] ^ current_state[22];
            next_state[18] = current_state[0]  ^ current_state[1]  ^ current_state[2]  ^ current_state[7]  ^ current_state[8]  ^ current_state[11] ^ current_state[12] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[19] = current_state[0]  ^ current_state[1]  ^ current_state[3]  ^ current_state[5]  ^ current_state[9]  ^ current_state[12] ^ current_state[13] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[20] = current_state[0]  ^ current_state[1]  ^ current_state[4]  ^ current_state[5]  ^ current_state[6]  ^ current_state[8]  ^ current_state[10] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20];
            next_state[21] = current_state[1]  ^ current_state[2]  ^ current_state[5]  ^ current_state[6]  ^ current_state[7]  ^ current_state[9]  ^ current_state[11] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21];
            next_state[22] = current_state[2]  ^ current_state[3]  ^ current_state[6]  ^ current_state[7]  ^ current_state[8]  ^ current_state[10] ^ current_state[12] ^ current_state[15] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
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

    // =========================================================================
    // Genvar / integer for array loops
    // =========================================================================
    integer i;

    // =========================================================================
    // FSM — State logicister update
    // Transitions are driven by i_state changes (edge detection) or by internal
    // counter completion. The DATA_TRANSFER state is entered/exited via the
    // i_active_state_entered flag.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            current_state <= IDLE;
            i_state_reg   <= IDLE;
        end else begin
            i_state_reg <= i_state; // logicister for next-cycle edge detection

            case (current_state)

                // ------------------------------------------------------------------
                // IDLE: wait for external state change or active-state entry
                // ------------------------------------------------------------------
                IDLE: begin
                    if (i_active_state_entered)
                        current_state <= DATA_TRANSFER;
                    else if (i_state_changed && i_state == CLEAR_LFSR)
                        current_state <= CLEAR_LFSR;
                    else if (i_state_changed && i_state == PATTERN_LFSR)
                        current_state <= PATTERN_LFSR;
                    else if (i_state_changed && i_state == PER_LANE_IDE)
                        current_state <= PER_LANE_IDE;
                    // else remain in IDLE
                end

                // ------------------------------------------------------------------
                // CLEAR_LFSR: single-cycle reset of LFSR seeds, then back to IDLE
                // ------------------------------------------------------------------
                CLEAR_LFSR: begin
                    current_state <= IDLE;
                end 

                // ------------------------------------------------------------------
                // PATTERN_LFSR: transmit 128 LFSR frames, then return to IDLE
                // ------------------------------------------------------------------
                PATTERN_LFSR: begin
                    if (counter_lfsr == COUNT_LFSR) begin       // counter_lfsr == 128
                        current_state <= IDLE;
                    end
                    // else stay in PATTERN_LFSR
                end

                // ------------------------------------------------------------------
                // PER_LANE_IDE: transmit 64 lane-ID frames, then return to IDLE
                // ------------------------------------------------------------------
                PER_LANE_IDE: begin
                    if (counter_per_lane == COUNT_PER_LANE) begin  // counter_per_lane == 64
                        current_state <= IDLE;
                    end
                    // else stay in PER_LANE_IDE
                end

                // ------------------------------------------------------------------
                // DATA_TRANSFER: stay while i_active_state_entered is asserted
                // ------------------------------------------------------------------
                DATA_TRANSFER: begin
                    if (!i_active_state_entered) begin
                        current_state <= IDLE;
                    end
                    // else stay in DATA_TRANSFER
                end

                default: begin
                    current_state <= IDLE;
                end

            endcase
        end
    end

    // =========================================================================
    // Datapath — output and LFSR update logic
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin

        // ----------------------------------------------------------------------
        // Reset: restore seed values, zero all outputs and counters
        // ----------------------------------------------------------------------
        if (!i_rst_n) begin
            counter_lfsr         <= 0;
            counter_per_lane     <= 0;
            o_Lfsr_tx_done       <= 0;
            o_ser_en_lfsr       <= 0;
            o_valid_frame_en       <= 0;
            lane_reversal_enabled <= 0;

            // Zero all output lanes
            for (i = 0; i < 16; i = i + 1)
                o_lane[i] <= 0;

            // Restore LFSR logicisters to their seeds
            for (i = 0; i < 8; i = i + 1) begin
                tx_lfsr[i]    <= SEED[i];
                o_lane_23[i]  <= compute_initial_23(SEED[i]);
            end

        end else begin

            // Default: clear all output lanes each cycle unless a state drives them
            for (i = 0; i < 16; i = i + 1)
                o_lane[i] <= 0;

            case (current_state)

                // ==============================================================
                // IDLE
                // ==============================================================
                IDLE: begin
                    counter_lfsr     <= 0;
                    o_ser_en_lfsr       <= 0;
                    counter_per_lane <= 0;
                    o_valid_frame_en   <= 0;

                    
                    lane_reversal_enabled <= i_reversal_en;
                   
                end

                // ==============================================================
                // CLEAR_LFSR: reset all LFSR logicisters and precompute bit-23 values
                // ==============================================================
                CLEAR_LFSR: begin
                    for (i = 0; i < 8; i = i + 1) begin
                        tx_lfsr[i]   <= SEED[i];
                        o_lane_23[i] <= compute_initial_23(SEED[i]);
                    end
                end

                // ==============================================================
                // PATTERN_LFSR: advance all LFSRs and output scrambled pattern
                // ==============================================================
                PATTERN_LFSR: begin
                    // Advance every LFSR one step
                    for (i = 0; i < 8; i = i + 1)
                        {o_lane_23[i], tx_lfsr[i]} <= next_lfsr_state(tx_lfsr[i]);

                    if (counter_lfsr == COUNT_LFSR) begin
                        // Phase complete
                        counter_lfsr   <= 0;
                        o_ser_en_lfsr <= 0;
                        o_Lfsr_tx_done <= 1;
                        o_valid_frame_en <= 0;
                    end else begin
                        // Drive the appropriate lane group with LFSR data
                        o_ser_en_lfsr <= 1;
                        o_valid_frame_en <= 1;
                        o_Lfsr_tx_done <= 0;
                        counter_lfsr   <= counter_lfsr + 1;

                        case (i_width_deg_lfsr)

                            DEGRADE_LANES_0_TO_7: begin
                                if (lane_reversal_enabled)
                                    // Reversed: physical lane N gets LFSR (7-N)
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[7-i], o_lane_23[7-i]};
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[i], o_lane_23[i]};
                            end

                            DEGRADE_LANES_8_TO_15: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[7-i], o_lane_23[7-i]};
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[i], o_lane_23[i]};
                            end

                            DEGRADE_LANES_0_TO_3: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[3-i], o_lane_23[3-i]};
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[i], o_lane_23[i]};
                            end

                            DEGRADE_LANES_4_TO_7: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {tx_lfsr[3-i], o_lane_23[3-i]};
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {tx_lfsr[i], o_lane_23[i]};
                            end

                            DEGRADE_LANES_0_TO_15: begin
                                if (lane_reversal_enabled) begin
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i]   <= {tx_lfsr[7-i], o_lane_23[7-i]};
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[7-i], o_lane_23[7-i]};
                                end else begin
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i]   <= {tx_lfsr[i], o_lane_23[i]};
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[i], o_lane_23[i]};
                                end
                            end

                        endcase
                    end
                end

                // ==============================================================
                // PER_LANE_IDE: output each lane's unique ID pattern
                // ==============================================================
                PER_LANE_IDE: begin
                    if (counter_per_lane == COUNT_PER_LANE) begin
                        counter_per_lane <= 0;
                        o_ser_en_lfsr <= 0;
                        o_Lfsr_tx_done   <= 1;
                        o_valid_frame_en   <= 0;
                    end else begin
                        o_ser_en_lfsr <= 1;
                        o_valid_frame_en   <= 1;
                        o_Lfsr_tx_done   <= 0;
                        counter_per_lane <= counter_per_lane + 1;

                        case (i_width_deg_lfsr)

                            DEGRADE_LANES_0_TO_7: begin
                                if (lane_reversal_enabled)
                                    // Reversed: physical lane 0 gets ID of logical lane 15, etc.
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {LANE_ID[15-i], LANE_ID[15-i]};
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {LANE_ID[i], LANE_ID[i]};
                            end

                            DEGRADE_LANES_8_TO_15: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {LANE_ID[7-i], LANE_ID[7-i]};
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {LANE_ID[8+i], LANE_ID[8+i]};
                            end 

                            DEGRADE_LANES_0_TO_3: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {LANE_ID[7-i], LANE_ID[7-i]};
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {LANE_ID[i], LANE_ID[i]};
                            end

                            DEGRADE_LANES_4_TO_7: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {LANE_ID[3-i], LANE_ID[3-i]};
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {LANE_ID[4+i], LANE_ID[4+i]};
                            end


                            DEGRADE_LANES_0_TO_15: begin
                                if (lane_reversal_enabled) begin
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i]   <= {LANE_ID[15-i], LANE_ID[15-i]};
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {LANE_ID[7-i],  LANE_ID[7-i]};
                                end else begin
                                    for (i = 0; i < 16; i = i + 1)
                                        o_lane[i]   <= {LANE_ID[i], LANE_ID[i]};
                                end
                            end

                        endcase
                    end
                end

                // ==============================================================
                // DATA_TRANSFER: continuous data scrambling and forwarding
                // ==============================================================
                DATA_TRANSFER: begin
                    // Advance every LFSR one step
                    for (i = 0; i < 8; i = i + 1)
                        {o_lane_23[i], tx_lfsr[i]} <= next_lfsr_state(tx_lfsr[i]);

                    if (i_scramble_en) begin
                        // Scrambling enabled: XOR input data with LFSR stream
                        o_valid_frame_en <= 1;
                        o_ser_en_lfsr <= 1;

                        case (i_width_deg_lfsr)

                            DEGRADE_LANES_0_TO_7: begin
                                if (lane_reversal_enabled)
                                    // Reversed: output lane N = LFSR(7-N) XOR input lane (15-N)
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[7-i], o_lane_23[7-i]} ^ i_lane[15-i];
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[i];
                            end

                            DEGRADE_LANES_8_TO_15: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[7-i], o_lane_23[7-i]} ^ i_lane[7-i];
                                else
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[8+i];
                            end

                            DEGRADE_LANES_0_TO_3: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[3-i], o_lane_23[3-i]} ^ i_lane[7-i];
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[i] <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[i];
                            end

                            DEGRADE_LANES_4_TO_7: begin
                                if (lane_reversal_enabled)
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {tx_lfsr[3-i], o_lane_23[3-i]} ^ i_lane[3-i];
                                else
                                    for (i = 0; i < 4; i = i + 1)
                                        o_lane[4+i] <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[4+i];
                            end

                            DEGRADE_LANES_0_TO_15: begin
                                if (lane_reversal_enabled) begin
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i]   <= {tx_lfsr[7-i], o_lane_23[7-i]} ^ i_lane[15-i];
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[7-i], o_lane_23[7-i]} ^ i_lane[7-i];
                                end else begin
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[i]   <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[i];
                                    for (i = 0; i < 8; i = i + 1)
                                        o_lane[8+i] <= {tx_lfsr[i], o_lane_23[i]} ^ i_lane[8+i];
                                end
                            end

                        endcase

                    end else begin
                        // Scrambling disabled — no frame output
                        o_valid_frame_en <= 0;
                        o_ser_en_lfsr <= 0;
                    end
                end

            endcase
        end
    end

endmodule