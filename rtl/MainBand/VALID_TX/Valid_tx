module VALID_TX (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        valid_pattern_en,
    input  wire        valid_frame_en,

    // Outputs
    output reg         O_done,
    output reg [31:0]  o_TVLD_L
);

// ============================================================
// Local Parameters
// ============================================================

// 8-bit valid pattern
localparam VALID_8B = 8'b11110000;          // 8'hF0

// 32-bit pattern = 4 × 8-bit pattern
localparam VALID_PATTERN_CODE = {VALID_8B, VALID_8B, VALID_8B, VALID_8B};

// Counter maximum value (generate pattern for 32 cycles)
localparam MAX_COUNT = 31;

// FSM States
localparam [1:0]
    IDLE          = 2'b00,
    VALID_PATTERN = 2'b01,
    VALID_FRAME   = 2'b10;

// ============================================================
// Internal Registers
// ============================================================

reg [7:0] COUNTER;          // Counter for VALID_PATTERN duration
reg [1:0] current_state;    // FSM current state

// ============================================================
// FSM - State Transition Logic
// ============================================================

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        current_state <= IDLE;
    end
    else begin
        case (current_state)

            // -------------------------
            // IDLE State
            // -------------------------
            IDLE: begin
                if (valid_pattern_en)
                    current_state <= VALID_PATTERN;
                else if (valid_frame_en)
                    current_state <= VALID_FRAME;
                else
                    current_state <= IDLE;
            end

            // -------------------------
            // VALID_PATTERN State
            // -------------------------
            VALID_PATTERN: begin
                // Return to IDLE after done pulse
                if (O_done)
                    current_state <= IDLE;
                else
                    current_state <= VALID_PATTERN;
            end

            // -------------------------
            // VALID_FRAME State
            // -------------------------
            VALID_FRAME: begin
                // Stay while frame enable is high
                if (!valid_frame_en)
                    current_state <= IDLE;
                else
                    current_state <= VALID_FRAME;
            end

            default: current_state <= IDLE;

        endcase
    end
end


// ============================================================
// Output & Counter Logic
// ============================================================

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_TVLD_L <= 32'b0;
        O_done   <= 1'b0;
        COUNTER  <= 8'd0;
    end
    else begin
        case (current_state)

            // -------------------------
            // IDLE
            // -------------------------
            IDLE: begin
                o_TVLD_L <= 32'b0;
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
            end

            // -------------------------
            // VALID_PATTERN
            // Generates pattern for 32 cycles
            // -------------------------
            VALID_PATTERN: begin
                o_TVLD_L <= VALID_PATTERN_CODE;

                if (COUNTER < MAX_COUNT) begin
                    COUNTER <= COUNTER + 1;
                    O_done  <= 1'b0;
                end
                else begin
                    COUNTER <= 8'd0;
                    O_done  <= 1'b1;   // Pulse done for 1 cycle
                end
            end

            // -------------------------
            // VALID_FRAME
            // Continuous valid output while enabled
            // -------------------------
            VALID_FRAME: begin
                o_TVLD_L <= VALID_PATTERN_CODE;
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
            end

            default: begin
                o_TVLD_L <= 32'b0;
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
            end

        endcase
    end
end

endmodule