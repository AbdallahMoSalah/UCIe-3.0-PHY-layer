module sb_pattern_engine (

    input  logic        clk,
    input  logic        rst_n,

    // control
    input  logic        pattern_mode,
    input  logic        start_pat_req,
    input  logic        send_4_iter,

    output logic        four_iter_done,

    // mapper
    input  logic [63:0] mapper_data,
    input  logic        mapper_valid,
    output logic        mapper_rdy,

    // serializer
    input  logic        ser_rdy,

    output logic [63:0] ser_data,
    output logic        ser_valid
);

////////////////////////////////////////////////////////////
// Pattern
////////////////////////////////////////////////////////////

localparam logic [63:0] CLOCK_PATTERN = 64'h5555_5555_5555_5555;

////////////////////////////////////////////////////////////
// FSM
////////////////////////////////////////////////////////////

typedef enum logic [2:0] {
    MAPPER,
    IDLE,
    SEND_PATTERN,
    COUNT_4,
    DONE_HOLD
} state_t;

state_t state, next_state;

////////////////////////////////////////////////////////////
// Counter
////////////////////////////////////////////////////////////

logic [2:0] iter_cnt;

////////////////////////////////////////////////////////////
// State register
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

////////////////////////////////////////////////////////////
// Next state logic
////////////////////////////////////////////////////////////

always_comb begin
    next_state = state;

    case(state)

        ////////////////////////////////////////////////////
        MAPPER:
        ////////////////////////////////////////////////////
        begin
            if(pattern_mode)
                next_state = IDLE;
        end

        ////////////////////////////////////////////////////
        IDLE:
        ////////////////////////////////////////////////////
        begin
            if(!pattern_mode)
                next_state = MAPPER;

            else if(start_pat_req)
                next_state = SEND_PATTERN;
        end

        ////////////////////////////////////////////////////
        SEND_PATTERN:
        ////////////////////////////////////////////////////
        begin
            if(!pattern_mode)
                next_state = MAPPER;

            else if(send_4_iter)
                next_state = COUNT_4;
        end

        ////////////////////////////////////////////////////
        COUNT_4:
        ////////////////////////////////////////////////////
        begin
            if(!pattern_mode)
                next_state = MAPPER;

            else if((iter_cnt == 3) && ser_valid && ser_rdy)
                next_state = DONE_HOLD;
        end

        ////////////////////////////////////////////////////
        DONE_HOLD:
        ////////////////////////////////////////////////////
        begin
            if(!pattern_mode)
                next_state = MAPPER;
        end

        default:
            next_state = IDLE;

    endcase
end

////////////////////////////////////////////////////////////
// Counter (4 iterations)
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        iter_cnt <= 0;

    else if(state == COUNT_4) begin
        if(ser_valid && ser_rdy) begin
            if(iter_cnt == 3)
                iter_cnt <= 0;
            else
                iter_cnt <= iter_cnt + 1;
        end
    end
    else begin
        iter_cnt <= 0;
    end
end

////////////////////////////////////////////////////////////
// ser_valid
////////////////////////////////////////////////////////////

always_comb begin
    if(!rst_n)
        ser_valid = 0;

    else begin
        case(state)

            MAPPER:
                ser_valid = mapper_valid;

            IDLE:
                ser_valid = 0;

            SEND_PATTERN:
                ser_valid = start_pat_req;

            COUNT_4:
                ser_valid = (iter_cnt < 4);

            DONE_HOLD:
                ser_valid = 0;

            default:
                ser_valid = 0;

        endcase
    end
end

////////////////////////////////////////////////////////////
// ser_data
////////////////////////////////////////////////////////////

always_comb begin
    if(!rst_n)
        ser_data = '0;

    else begin
        case(state)

            MAPPER:
                ser_data = mapper_data;

            SEND_PATTERN,
            COUNT_4:
                ser_data = CLOCK_PATTERN;

            default:
                ser_data = '0;

        endcase
    end
end

////////////////////////////////////////////////////////////
// mapper_rdy
////////////////////////////////////////////////////////////

assign mapper_rdy = (state == MAPPER) && ser_rdy;

////////////////////////////////////////////////////////////
// done signal (latched by state)
////////////////////////////////////////////////////////////

always_comb begin
    if(!rst_n)
        four_iter_done = 0;

    else if(!pattern_mode)
        four_iter_done = 0;

    else if(state == DONE_HOLD)
        four_iter_done = 1;

    else
        four_iter_done = 0;

end

endmodule





















/* module sb_pattern_engine (

    input  logic        clk,
    input  logic        rst_n,

    // control from LTSM
    input  logic        pattern_mode,
    input  logic        start_pat_req,
    input  logic        send_4_iter,

    output logic        four_iter_done,

    // mapper interface
    input  logic [63:0] mapper_data,
    input  logic        mapper_valid,
    output logic        mapper_rdy,

    // serializer handshake
    input  logic        ser_rdy,

    // serializer interface
    output logic [63:0] ser_data,
    output logic        ser_valid
);

////////////////////////////////////////////////////////////
// Pattern constant
////////////////////////////////////////////////////////////

localparam logic [63:0] CLOCK_PATTERN = 64'h5555_5555_5555_5555;

////////////////////////////////////////////////////////////
// Iteration Counter
////////////////////////////////////////////////////////////

logic [2:0] iter_cnt;

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin
        iter_cnt <= 0;
    end
    else begin

        if(pattern_mode && send_4_iter && ser_rdy && ser_valid && (iter_cnt != 4)) begin
            iter_cnt <= iter_cnt + 1;
        end

        else if(iter_cnt == 4) begin
            iter_cnt <= 0;
        end
    end

end

assign four_iter_done = (iter_cnt == 4);

////////////////////////////////////////////////////////////
// Sequential valid generation
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n)
        ser_valid <= 0;

    else if(pattern_mode && start_pat_req)
        ser_valid <= 1;

    else if(!pattern_mode)
        ser_valid <= mapper_valid;
    else begin
        ser_valid <= 0;
    end

end

////////////////////////////////////////////////////////////
// Data path
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n)
        ser_data <= '0;

    else if(pattern_mode && start_pat_req)
        ser_data <= CLOCK_PATTERN;

    else if(!pattern_mode)
        ser_data <= mapper_data;

end

////////////////////////////////////////////////////////////
// Mapper rdy
////////////////////////////////////////////////////////////

assign mapper_rdy = (!pattern_mode) && (!start_pat_req) && ser_rdy;

endmodule */