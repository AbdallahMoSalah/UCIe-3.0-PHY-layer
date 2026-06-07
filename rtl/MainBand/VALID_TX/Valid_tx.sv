module VALID_TX (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        valid_pattern_en,
    input  wire        valid_frame_en,

    // Outputs
    output reg         ser_en_o,
    output reg         O_done,
    output reg [31:0]  o_TVLD_L
);

// ============================================================
// Local Parameters
// ============================================================

localparam VALID_8B = 8'b11110000; // Base 8-bit pattern: 4 ones, 4 zeros
localparam VALID_PATTERN_CODE = {VALID_8B, VALID_8B, VALID_8B, VALID_8B};

localparam MAX_COUNT = 31; // 0 to 31 count gives exactly 32 cycles of VALID_PATTERN

localparam [1:0]
    IDLE          = 2'b00,
    VALID_FRAME   = 2'b01,
    VALID_PATTERN = 2'b11;

// ============================================================
// Internal Registers
// ============================================================

reg [7:0] COUNTER;
reg [1:0] current_state;

// ============================================================
// FSM - State Transition Logic
// ============================================================

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
                if (O_done)
                    current_state <= IDLE;
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
        o_TVLD_L <= 32'b0;
        O_done   <= 1'b0;
        COUNTER  <= 8'd0;
        ser_en_o <= 1'b0;
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
                ser_en_o <= 1'b0;
            end

            // -------------------------
            // VALID_FRAME (continuous)
            // -------------------------
            VALID_FRAME: begin
                o_TVLD_L <= VALID_PATTERN_CODE;
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
                ser_en_o <= 1'b1; 
            end

            // -------------------------
            // VALID_PATTERN
            // -------------------------
            VALID_PATTERN: begin
                COUNTER <= COUNTER + 1'b1;  
                
                if (COUNTER < MAX_COUNT) begin
                    o_TVLD_L <= VALID_PATTERN_CODE;
                    O_done   <= 1'b0;
                    ser_en_o <= 1'b1;               // was zero and i made it 1                                      
                end
                else begin // COUNTER == MAX_COUNT
                    o_TVLD_L <= VALID_PATTERN_CODE;
                    O_done   <= 1'b1;
                    ser_en_o <= 1'b1;
                end
            end

            default: begin
                o_TVLD_L <= 32'b0;
                O_done   <= 1'b0;
                COUNTER  <= 8'd0;
                ser_en_o <= 1'b0; 
            end

        endcase
    end
end

endmodule