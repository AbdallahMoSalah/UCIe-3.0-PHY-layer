module sb_deserializer
#(
    parameter DATA_WIDTH = 64
)
(
    input  logic                     RXCKSB,
    input  logic                     clk_parallel,
    input  logic                     rst_n,

    input  logic                     RXDATASB,

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

assign next_shift = {RXDATASB, shift_reg[DATA_WIDTH-1:1]};

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
        
        if(packet_done) begin
            bit_cnt <= '0;
            rx_parallel_data_serial <= next_shift;
            rx_data_vld_serial      <= ~rx_data_vld_serial;
            `ifdef SIMULATION
            $display("[%0t] [DES %m] PACKET_DONE: output=%h (last_rx=%b)", $time, next_shift, RXDATASB);
            `endif
        end else begin
            bit_cnt   <= bit_cnt + 1;
            shift_reg <= next_shift;
        end

    end
end

logic rx_data_vld_serial_sync1, rx_data_vld_serial_sync2, rx_data_vld_serial_sync3;
always_ff @(posedge clk_parallel or negedge rst_n) begin
    if(!rst_n) begin
        rx_data_vld_serial_sync1 <= 0;
        rx_data_vld_serial_sync2 <= 0;
        rx_data_vld_serial_sync3 <= 0;
    end else begin
        rx_data_vld_serial_sync1 <= rx_data_vld_serial;
        rx_data_vld_serial_sync2 <= rx_data_vld_serial_sync1;
        rx_data_vld_serial_sync3 <= rx_data_vld_serial_sync2;
    end
end


always_ff @(posedge clk_parallel or negedge rst_n) begin

    if(!rst_n) begin
        rx_parallel_data_out <= '0;
        rx_data_vld    <= 1'b0;
    end

    else begin
        if(rx_data_vld_serial_sync2 != rx_data_vld_serial_sync3) begin
            rx_data_vld <= 1;
            rx_parallel_data_out <= rx_parallel_data_serial;
        end
        else begin
            rx_data_vld <= 0;
        end
    end

end

endmodule