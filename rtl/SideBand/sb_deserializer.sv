module sb_deserializer
#(
    parameter DATA_WIDTH = 64
)
(
    input  logic                     RXCKSB,
    input  logic                     rst_n,

    input  logic                     rx_serial_in,

    // registered outputs
    output logic [DATA_WIDTH-1:0]    rx_parallel_data,
    output logic                     rx_data_valid,

    // FIFO interface (combinational)
    output logic [DATA_WIDTH-1:0]    packet_data,
    output logic                     packet_done
);

////////////////////////////////////////////////////////////
// Registers
////////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] shift_reg;
logic [$clog2(DATA_WIDTH):0] bit_cnt;

logic [DATA_WIDTH-1:0] next_shift;

////////////////////////////////////////////////////////////
// Shift calculation (combinational)
////////////////////////////////////////////////////////////

assign next_shift = {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};

////////////////////////////////////////////////////////////
// Packet done detection
////////////////////////////////////////////////////////////

assign packet_done = (bit_cnt == DATA_WIDTH-1);

////////////////////////////////////////////////////////////
// Data ready for FIFO (same cycle)
////////////////////////////////////////////////////////////

assign packet_data = next_shift;

////////////////////////////////////////////////////////////
// Deserializer sequential logic
////////////////////////////////////////////////////////////

always_ff @(posedge RXCKSB or negedge rst_n) begin

    if(!rst_n) begin
        shift_reg        <= '0;
        rx_parallel_data <= '0;
        bit_cnt          <= '0;
        rx_data_valid    <= 1'b0;
    end

    else begin

        ////////////////////////////////////////////////
        // shift register
        ////////////////////////////////////////////////

        shift_reg <= next_shift;

        ////////////////////////////////////////////////
        // counter
        ////////////////////////////////////////////////

        if(packet_done)
            bit_cnt <= '0;
        else
            bit_cnt <= bit_cnt + 1;

        ////////////////////////////////////////////////
        // registered outputs
        ////////////////////////////////////////////////

        if(packet_done)
            rx_parallel_data <= next_shift;

        rx_data_valid <= packet_done;

    end

end

endmodule