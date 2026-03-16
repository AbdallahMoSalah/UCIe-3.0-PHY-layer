module sb_pattern_engine (

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
    output logic        mapper_ready,

    // serializer handshake
    input  logic        ser_ready,

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

    if(!rst_n)
        iter_cnt <= 0;

    else if(pattern_mode && send_4_iter && ser_ready && ser_valid && (iter_cnt != 4))
        iter_cnt <= iter_cnt + 1;

    else if(iter_cnt == 4)
        iter_cnt <= 0;

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
// Mapper ready
////////////////////////////////////////////////////////////

assign mapper_ready = (!pattern_mode) && (!start_pat_req) && ser_ready;

endmodule