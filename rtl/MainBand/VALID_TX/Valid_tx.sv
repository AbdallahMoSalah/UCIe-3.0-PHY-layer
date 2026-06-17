module VALID_TX (
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic        valid_pattern_en,
    input  logic        valid_frame_en,

    // Outputs
    output logic         valid_ser_en,
    output logic         O_done,
    output logic [31:0]  o_TVLD_L
);

// ============================================================
// Local Parameters
// ============================================================

localparam VALID_8B = 8'b00001111; // Base 8-bit pattern: 4 ones, 4 zeros
localparam VALID_PATTERN_CODE = {VALID_8B, VALID_8B, VALID_8B, VALID_8B};

localparam MAX_COUNT = 32; // 0 to 31 count gives exactly 32 cycles of VALID_PATTERN

localparam [1:0]
    IDLE          = 2'b00,
    VALID_FRAME   = 2'b01,
    VALID_PATTERN = 2'b11;

// ============================================================
// Internal logicisters
// ============================================================
logic ser_en_reg;

logic [7:0] COUNTER;
logic [1:0] current_state;

// ============================================================
// FSM - State Transition Logic
// ============================================================
assign valid_ser_en = (current_state == (VALID_PATTERN))? ser_en_reg: valid_frame_en;
assign o_TVLD_L = VALID_PATTERN_CODE;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        current_state <= IDLE;
    else begin
        case (current_state)

            IDLE: begin
                if (valid_pattern_en)
                    current_state <= VALID_PATTERN;
                else if (valid_frame_en)
                    current_state <= VALID_FRAME;
                else
                    current_state <= IDLE;
            end

            VALID_PATTERN: begin
                if (O_done) begin
                    if (valid_pattern_en)
                        current_state <= VALID_PATTERN;
                    else
                        current_state <= IDLE;
                end
                else
                    current_state <= VALID_PATTERN;
            end

            VALID_FRAME: begin
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
        O_done   <= 1'b0;
        COUNTER  <= 8'd0;
        ser_en_reg <= 1'b0;
    end
    else begin
        case (current_state)

            // -------------------------
            // IDLE
            // -------------------------
            IDLE: begin
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
                ser_en_reg <= 1'b0;
            end

            // -------------------------
            // VALID_FRAME (continuous)
            // -------------------------
            VALID_FRAME: begin
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
                ser_en_reg <= 1'b1; 
            end

            // -------------------------
            // VALID_PATTERN
            // -------------------------
            VALID_PATTERN: begin
                if (COUNTER < MAX_COUNT) begin
                    COUNTER <= COUNTER + 1'b1;
                    O_done   <= 1'b0;
                    ser_en_reg <= 1'b1;
                end
                else begin // COUNTER == MAX_COUNT
                    O_done   <= 1'b1;
                    if (valid_pattern_en) begin
                        COUNTER <= 8'd0;
                        ser_en_reg <= 1'b1; // keep enabled for next pattern block
                    end else begin
                        ser_en_reg <= 1'b0;
                    end
                end
            end

            default: begin
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
                ser_en_reg <= 1'b0; 
            end

        endcase
    end
end

endmodule