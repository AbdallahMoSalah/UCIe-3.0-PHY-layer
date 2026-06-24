module unit_valid_tx (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        valid_pattern_en,
    input  wire        ser_en_lfsr_i,

    // Outputs
    output reg         ser_en_o,
    output reg         O_done,
    output reg [31:0]  o_TVLD_L
);
// ============================================================
// L
// ============================================================
typedef enum logic {
    VALID_PATTERN,
    VALID_FRAME
} state_t;
// ============================================================
// Internal Registers
// ============================================================
reg [7:0] COUNTER;
state_t current_state;
state_t next_state;
reg ser_en_internal;
// ============================================================
// FSM - State Register (Sequential)
// ============================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        current_state <= VALID_FRAME;
    else
        current_state <= next_state;
end
// ============================================================
// FSM - Next State Logic (Combinational)
// ============================================================
always @(*) begin
    next_state = current_state;
    case (current_state)
        VALID_PATTERN: begin
            if (!valid_pattern_en)
                next_state = VALID_FRAME;
        end
        VALID_FRAME: begin
            if (valid_pattern_en)
                next_state = VALID_PATTERN;
        end
    endcase
end
// ============================================================
// Counter Logic (Sequential)
// ============================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        COUNTER  <= 8'd0;
    end
    else begin
        case (current_state)
            VALID_PATTERN: begin
                if (COUNTER < 32) begin
                    COUNTER <= COUNTER + 1;
                end
                if (!valid_pattern_en) begin
                    COUNTER <= 8'd0;
                end
            end
            VALID_FRAME: begin
                COUNTER  <= 8'd0;
            end
        endcase
    end
end
// ============================================================
// Output Logic (Combinational)
// ============================================================
always_comb begin
    O_done = 1'b0;
    ser_en_internal = 1'b0;
    case (current_state)
        VALID_PATTERN: begin
            ser_en_internal = 1'b1;
            if (COUNTER == 32) begin
                O_done = 1'b1;
                ser_en_internal = 1'b0;
            end
        end
        VALID_FRAME: begin
            O_done = 1'b0;
            ser_en_internal = 1'b0;
        end
    endcase
end
assign o_TVLD_L = 32'h0F0F0F0F;
assign ser_en_o = (current_state == VALID_FRAME) ? ser_en_lfsr_i : ser_en_internal;
endmodule
