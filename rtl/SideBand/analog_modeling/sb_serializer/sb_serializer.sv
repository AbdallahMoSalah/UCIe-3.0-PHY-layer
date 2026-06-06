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
    output logic                  tx_rdy,

    // Serial output
    output logic TXDATASB,

    // Forwarded clock
    output logic TXCKSB
);

////////////////////////////////////////////////////////////
// PARALLEL DOMAIN (1-entry skid buffer)
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] parallel_reg;
logic buf_full;

// toggle sync from serial → parallel
logic pop_toggle_serial;
logic pop_sync1, pop_sync2;
logic pop_seen;
logic pop_event;

always_ff @(posedge clk_parallel or negedge rst_n) begin
    if(!rst_n) begin
        pop_sync1 <= 0;
        pop_sync2 <= 0;
    end else begin
        pop_sync1 <= pop_toggle_serial;
        pop_sync2 <= pop_sync1;
    end
end

assign pop_event = (pop_sync2 != pop_seen);

always_ff @(posedge clk_parallel or negedge rst_n) begin
    if(!rst_n)
        pop_seen <= 0;
    else if(pop_event)
        pop_seen <= pop_sync2;
end

// buffer control
always_ff @(posedge clk_parallel or negedge rst_n) begin
    if(!rst_n) begin
        parallel_reg <= '0;
        buf_full     <= 0;
    end
    else begin
        if(tx_data_valid && tx_rdy) begin
            parallel_reg <= tx_parallel_data;
            buf_full     <= 1;
        end
        else if(pop_event) begin
            buf_full <= 0;
        end
    end
end

assign tx_rdy = !buf_full;

////////////////////////////////////////////////////////////
// SYNC: buf_full → SERIAL DOMAIN
////////////////////////////////////////////////////////////

logic full_sync1, full_sync2;

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n) begin
        full_sync1 <= 0;
        full_sync2 <= 0;
    end else begin
        full_sync1 <= buf_full;
        full_sync2 <= full_sync1;
    end
end

////////////////////////////////////////////////////////////
// SERIAL DOMAIN FSM
////////////////////////////////////////////////////////////

typedef enum logic [1:0] {
    S_IDLE,
    S_SHIFT,
    S_GAP
} state_t;

state_t state, next_state;

logic [DATA_WIDTH-1:0] shift_reg;
localparam BIT_CNT_WIDTH = $clog2(DATA_WIDTH);
localparam GAP_CNT_WIDTH = $clog2(GAP_WIDTH);

logic [BIT_CNT_WIDTH-1:0] bit_cnt;
logic [GAP_CNT_WIDTH-1:0]  gap_cnt;

////////////////////////////////////////////////////////////
// STATE REGISTER
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        state <= S_IDLE;
    else
        state <= next_state;
end

////////////////////////////////////////////////////////////
// NEXT STATE
////////////////////////////////////////////////////////////

always_comb begin
    next_state = state;

    case(state)

        S_IDLE:
            if(full_sync2)
                next_state = S_SHIFT;

        S_SHIFT:
            if(bit_cnt == BIT_CNT_WIDTH'(DATA_WIDTH-1)) begin
                if(pmo_en) begin
                    if(full_sync2)
                        next_state = S_SHIFT;
                    else
                        next_state = S_IDLE;
                end else begin
                    next_state = S_GAP;
                end
            end

        S_GAP:
            if(gap_cnt == GAP_CNT_WIDTH'(GAP_WIDTH-1)) begin
                if(full_sync2)
                    next_state = S_SHIFT;
                else
                    next_state = S_IDLE;
            end

        default:
            next_state = S_IDLE;

    endcase
end

////////////////////////////////////////////////////////////
// LOAD CONDITION
////////////////////////////////////////////////////////////

logic load_condition;

assign load_condition =
       (state == S_IDLE  && full_sync2)
    || (state == S_SHIFT && bit_cnt == BIT_CNT_WIDTH'(DATA_WIDTH-1) && pmo_en && full_sync2)
    || (state == S_GAP  && gap_cnt == GAP_CNT_WIDTH'(GAP_WIDTH-1) && full_sync2);

////////////////////////////////////////////////////////////
// SHIFT REGISTER
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        shift_reg <= '0;

    else begin
        if(load_condition)
            shift_reg <= parallel_reg;   // assume stable بسبب skid buffer

        else if(state == S_SHIFT)
            shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]};
    end
end

////////////////////////////////////////////////////////////
// COUNTERS
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        bit_cnt <= 0;
    else if(state == S_SHIFT) begin
        if(bit_cnt == BIT_CNT_WIDTH'(DATA_WIDTH-1))
            bit_cnt <= 0;
        else
            bit_cnt <= bit_cnt + 1;
    end else
        bit_cnt <= 0;
end

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        gap_cnt <= 0;
    else if(state == S_GAP) begin
        if(gap_cnt == GAP_CNT_WIDTH'(GAP_WIDTH-1))
            gap_cnt <= 0;
        else
            gap_cnt <= gap_cnt + 1;
    end else
        gap_cnt <= 0;
end

////////////////////////////////////////////////////////////
// TOGGLE POP GENERATION (IMPORTANT FIX)
////////////////////////////////////////////////////////////

always_ff @(posedge clk_serial or negedge rst_n) begin
    if(!rst_n)
        pop_toggle_serial <= 0;
    else if(load_condition)
        pop_toggle_serial <= ~pop_toggle_serial;
end

////////////////////////////////////////////////////////////
// OUTPUT
////////////////////////////////////////////////////////////

assign TXDATASB = (state == S_SHIFT) ? shift_reg[0] : 1'b0;

////////////////////////////////////////////////////////////
// FORWARDED CLOCK
////////////////////////////////////////////////////////////

logic shift_active;

// Generate forwarded clock only when we will be shifting in the current/next cycle.
// This perfectly aligns the 64 clock pulses with the valid data on TXDATASB.
assign shift_active = (next_state == S_SHIFT);

unit_clk_gate forward_clock(
    .CLK(clk_serial),
    .CLK_EN(shift_active),
    .GATED_CLK(TXCKSB)
);

`ifdef SIMULATION
    always_ff @(posedge clk_parallel) begin
        if (tx_data_valid && tx_rdy)
            $display("[%0t] [SER %m] PARALLEL LOADED: data=%h", $time, tx_parallel_data);
        if (pop_event)
            $display("[%0t] [SER %m] POP EVENT: buf_full->0", $time);
    end

    always_ff @(posedge clk_serial) begin
        if (state != next_state)
            $display("[%0t] [SER %m] STATE TRANSITION: %0s -> %0s | full_sync2=%b pmo_en=%b", $time, state.name(), next_state.name(), full_sync2, pmo_en);
        if (load_condition)
            $display("[%0t] [SER %m] LOAD CONDITION TRUE: state=%0s full_sync2=%b bit_cnt=%0d", $time, state.name(), full_sync2, bit_cnt);
    end
`endif

endmodule























/* module sb_serializer #(
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
    output logic                  tx_rdy,

    // Serial output
    output logic TXDATASB,

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

    else if(tx_data_valid && tx_rdy) begin
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

assign TXDATASB = (state == S_SHIFT) ? shift_reg[0] : 1'b0;

////////////////////////////////////////////////////////////
// READY SIGNAL
////////////////////////////////////////////////////////////

assign tx_rdy = !(data_vld_reg);


////////////////////////////////////////////////////////////
// FORWARDED CLOCK
////////////////////////////////////////////////////////////

logic shift_active;

assign shift_active = (next_state == S_SHIFT);

unit_clk_gate forward_clock(
    .CLK(clk_serial),
    .CLK_EN(shift_active),
    .GATED_CLK(TXCKSB)
);

endmodule */