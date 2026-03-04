
module sb_serializer
#(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)
(
    input  logic                     clk,
    input  logic                     rst_n,

    // Parallel interface
    input  logic [DATA_WIDTH-1:0]    tx_parallel_data,
    input  logic                     tx_data_valid,
    output logic                     tx_ready,

    // Serial output
    output logic                     tx_serial_out,

    // Forwarded sideband clock
    output logic                     TXCKSB
);

////////////////////////////////////////////////////////////
// State Machine
////////////////////////////////////////////////////////////

typedef enum logic [1:0] {
    IDLE,
    SHIFT,
    GAP
} state_t;

state_t state, next_state;

////////////////////////////////////////////////////////////
// Registers
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] shift_reg;
logic [$clog2(DATA_WIDTH):0] bit_cnt;

////////////////////////////////////////////////////////////
// State Register
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

////////////////////////////////////////////////////////////
// Next State Logic
////////////////////////////////////////////////////////////

always_comb begin

    next_state = state;

    case(state)

        IDLE:
            if (tx_data_valid)
                next_state = SHIFT;

        SHIFT:
            if (bit_cnt == DATA_WIDTH-1)
                next_state = GAP;

        GAP:
            if (bit_cnt == GAP_WIDTH-1)
                next_state = IDLE;

        default:
            next_state = IDLE;

    endcase

end

////////////////////////////////////////////////////////////
// Counter
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n)
        bit_cnt <= '0;

    else begin

        if (state != next_state)
            bit_cnt <= '0;
        else if (state != IDLE)
            bit_cnt <= bit_cnt + 1'b1;

    end

end

////////////////////////////////////////////////////////////
// Shift Register
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n)
        shift_reg <= '0;

    else begin

        if (state == IDLE && tx_data_valid )
            shift_reg <= tx_parallel_data;

        else if (state == SHIFT)
            shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1 : 1]};

    end

end

////////////////////////////////////////////////////////////
// Serial Output
////////////////////////////////////////////////////////////

always_comb begin

    if (state == SHIFT)
        tx_serial_out = shift_reg[0];
    else
        tx_serial_out = 1'b0;

end

////////////////////////////////////////////////////////////
// Ready Signal
////////////////////////////////////////////////////////////

assign tx_ready = (state == IDLE);

////////////////////////////////////////////////////////////
// Forwarded Clock (TXCKSB)
//
// Forward clock only during data transmission
////////////////////////////////////////////////////////////

always_comb begin

    if (state == SHIFT)
        TXCKSB = clk;
    else
        TXCKSB = 1'b0;

end

endmodule