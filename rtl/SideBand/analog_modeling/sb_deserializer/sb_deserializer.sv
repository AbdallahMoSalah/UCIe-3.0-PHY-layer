module sb_deserializer
#(
    parameter DATA_WIDTH = 64
)
(
    input  logic                     RXCKSB,
    input  logic                     clk_parallel,
    input  logic                     rst_n,

    input  logic                     rx_serial_in,

    // registered outputs
    output logic [DATA_WIDTH-1:0]    rx_parallel_data_out,
    output logic                     rx_data_vld
);

////////////////////////////////////////////////////////////
// Registers
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] shift_reg;
logic [$clog2(DATA_WIDTH):0] bit_cnt;

logic [DATA_WIDTH-1:0] next_shift;

logic [DATA_WIDTH-1:0]    rx_parallel_data_serial;
logic                     rx_data_vld_serial;
logic                     packet_done;
////////////////////////////////////////////////////////////
// Shift calculation 
////////////////////////////////////////////////////////////

assign next_shift = {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};

////////////////////////////////////////////////////////////
// Packet done detection
////////////////////////////////////////////////////////////

assign packet_done = (bit_cnt == DATA_WIDTH-1);

////////////////////////////////////////////////////////////
// Deserializer sequential logic
////////////////////////////////////////////////////////////

always_ff @(posedge RXCKSB or negedge rst_n) begin

    if(!rst_n) begin
        shift_reg        <= '0;
        rx_parallel_data_serial <= '0;
        bit_cnt          <= '0;
        rx_data_vld_serial    <= 1'b0;
    end

    else begin
        

        ////////////////////////////////////////////////
        // counter
        ////////////////////////////////////////////////

        if(packet_done)
            bit_cnt <= '0;
        else begin
            ////////////////////////////////////////////////
            // shift register
            ////////////////////////////////////////////////

            bit_cnt <= bit_cnt + 1;
            shift_reg <= next_shift;
        end

        ////////////////////////////////////////////////
        // registered outputs
        ////////////////////////////////////////////////

        if(packet_done) begin
            rx_parallel_data_serial <= next_shift;
            rx_data_vld_serial <= 1;
        end

    end

end


always_ff @(posedge clk_parallel or negedge rst_n) begin

    if(!rst_n) begin
        rx_parallel_data_out <= '0;
        rx_data_vld    <= 1'b0;
    end

    else begin
        if(rx_data_vld_serial)begin
            rx_data_vld <= 1;
            rx_parallel_data_out <= rx_parallel_data_serial;
            rx_data_vld_serial <= 0;
        end
        else if(rx_data_vld)begin
            rx_data_vld <= 0;
        end
    end

end

endmodule