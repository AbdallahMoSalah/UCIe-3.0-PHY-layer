module sb_serializer #(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
) (
    input  logic clk_parallel,
    input  logic clk_serial,
    input  logic rst_n,

    // control
    input  logic pmo_en,

    // Parallel interface
    input  logic [DATA_WIDTH-1:0] tx_parallel_data,
    input  logic                  tx_data_valid,
    output logic                  tx_ready,

    // Serial output
    output logic tx_serial_out,

    // Forwarded sideband clock
    output logic TXCKSB
);

////////////////////////////////////////////////////////////
// STATE MACHINE
////////////////////////////////////////////////////////////

typedef enum logic [1:0] {
    S_IDLE,
    S_SHIFT,
    S_GAP
} state_t;

state_t state, next_state;

////////////////////////////////////////////////////////////
// REGISTERS
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] shift_reg;
logic [DATA_WIDTH-1:0] parallel_reg;
logic data_vld_reg;

logic [$clog2(DATA_WIDTH)-1:0] bit_cnt;
logic [$clog2(GAP_WIDTH)-1:0]  gap_cnt;


////////////////////////////////////////////////////////////
// PARALLEL DOMAIN REGISTER (100 MHz)
////////////////////////////////////////////////////////////

always_ff @(posedge clk_parallel or negedge rst_n) begin
    if(!rst_n) begin
        parallel_reg <= '0;
        data_vld_reg <= '0;
    end

    else if(tx_data_valid && tx_ready) begin
        parallel_reg <= tx_parallel_data;
        data_vld_reg <= 1;
    end

end

////////////////////////////////////////////////////////////
// STATE REGISTER (SERIAL DOMAIN)
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        state <= S_IDLE;
    else
        state <= next_state;
end

////////////////////////////////////////////////////////////
// NEXT STATE LOGIC
////////////////////////////////////////////////////////////

always_comb begin

    next_state = state;

    case(state)

        S_IDLE:
            if(data_vld_reg)
                next_state = S_SHIFT;

        S_SHIFT:
            if(bit_cnt == DATA_WIDTH-1) begin
                if(pmo_en) begin
                    if(data_vld_reg)
                        next_state = S_SHIFT;
                    else
                        next_state = S_IDLE;
                end
                else
                    next_state = S_GAP;
            end

        S_GAP:
            if(gap_cnt == GAP_WIDTH-1) begin
                if(data_vld_reg)
                    next_state = S_SHIFT;
                else
                    next_state = S_IDLE;
            end

    endcase

end

////////////////////////////////////////////////////////////
// SHIFT REGISTER (SERIAL DOMAIN)
////////////////////////////////////////////////////////////

logic load_condition;

assign load_condition =
       (state == S_IDLE && data_vld_reg)
    || (state == S_SHIFT && bit_cnt == DATA_WIDTH-1 && pmo_en && data_vld_reg)
    || (state == S_GAP  && gap_cnt == GAP_WIDTH-1 && data_vld_reg);

always_ff @(posedge clk_serial or negedge rst_n) begin

    if(!rst_n) begin
        shift_reg <= '0;
    end

    else begin

        if(load_condition) begin
            shift_reg <= parallel_reg;
            data_vld_reg <= 0;
        end

        else if(state == S_SHIFT) begin
            shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]}; // LSB first
            
        end

    end

end

////////////////////////////////////////////////////////////
// BIT COUNTER
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin

    if(!rst_n)
        bit_cnt <= 0;

    else if(state == S_SHIFT) begin

        if(bit_cnt == DATA_WIDTH-1)
            bit_cnt <= 0;
        else
            bit_cnt <= bit_cnt + 1;

    end
    else
        bit_cnt <= 0;

end

////////////////////////////////////////////////////////////
// GAP COUNTER
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin

    if(!rst_n)
        gap_cnt <= 0;

    else if(state == S_GAP) begin

        if(gap_cnt == GAP_WIDTH-1)
            gap_cnt <= 0;
        else
            gap_cnt <= gap_cnt + 1;

    end
    else
        gap_cnt <= 0;

end

////////////////////////////////////////////////////////////
// SERIAL OUTPUT
////////////////////////////////////////////////////////////

assign tx_serial_out = (state == S_SHIFT) ? shift_reg[0] : 1'b0;

////////////////////////////////////////////////////////////
// READY SIGNAL (EXTERNAL BEHAVIOR SAME AS ORIGINAL)
////////////////////////////////////////////////////////////

assign tx_ready = !(data_vld_reg);


////////////////////////////////////////////////////////////
// FORWARDED CLOCK
////////////////////////////////////////////////////////////

logic shift_active;

assign shift_active = (next_state == S_SHIFT);

CLK_GATE forward_clock(
    .CLK(clk_serial),
    .CLK_EN(shift_active),
    .GATED_CLK(TXCKSB)
);

endmodule