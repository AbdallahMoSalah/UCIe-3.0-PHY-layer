module sb_pattern_engine (

    input  logic        clk,
    input  logic        rst_n,

    // control from LTSM
    input  logic        pattern_mode,
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

localparam logic [63:0] CLOCK_PATTERN = 64'hAAAAAAAAAAAAAAAA;

////////////////////////////////////////////////////////////
// Iteration Counter
////////////////////////////////////////////////////////////

logic [2:0] iter_cnt;
logic counting;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        counting <= 0;
    else if(send_4_iter)
        counting <= 1;
    else if(four_iter_done)
        counting <= 0;
end

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n)
        iter_cnt <= 0;

    else if(!counting)
        iter_cnt <= 0;

    else if(ser_ready && ser_valid)
        iter_cnt <= iter_cnt + 1;

end

assign four_iter_done = counting && (iter_cnt == 4);

////////////////////////////////////////////////////////////
// Sequential valid generation
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n)
        ser_valid <= 0;

    else if(pattern_mode)
        ser_valid <= 1;

    else
        ser_valid <= mapper_valid;

end

////////////////////////////////////////////////////////////
// Data path
////////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin

    if(!rst_n)
        ser_data <= '0;

    else if(pattern_mode)
        ser_data <= CLOCK_PATTERN;

    else if(mapper_valid && ser_ready)
        ser_data <= mapper_data;

end

////////////////////////////////////////////////////////////
// Mapper ready
////////////////////////////////////////////////////////////

assign mapper_ready = (!pattern_mode) && ser_ready;

endmodule