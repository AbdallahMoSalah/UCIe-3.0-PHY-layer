module sb_deserializer
#(
    parameter DATA_WIDTH = 64
)
(
    input  logic rst_n,

    input  logic rx_serial_in,
    input logic pmo_en,
    input  logic RXCKSB,

    output logic [DATA_WIDTH-1:0] rx_parallel_data,
    output logic rx_data_valid
);

logic [DATA_WIDTH-1:0] shift_reg;
logic [$clog2(DATA_WIDTH):0] bit_cnt;

logic finish;

////////////////////////////////////////////////////////
// shift + counter
////////////////////////////////////////////////////////

always_ff @(posedge RXCKSB or negedge rst_n) begin

    if(!rst_n) begin
        bit_cnt <= 0;
        shift_reg <= 0;
        rx_data_valid <= 0;
    end
    else begin

        if(pmo_en)begin

            shift_reg <= {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};

            if(bit_cnt == DATA_WIDTH-1) begin
                rx_parallel_data <= {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};
                rx_data_valid <= 1;
                finish <=1;
            end
            else if(rx_data_valid)begin
                rx_data_valid <= 0;
            end

            if(finish)begin
                finish <= 0;
                bit_cnt <= 1;
            end
            else begin
                bit_cnt <= bit_cnt + 1;
            end
        end
        else begin
            shift_reg <= {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};

            if(bit_cnt == DATA_WIDTH-1) begin
                rx_parallel_data <= {rx_serial_in, shift_reg[DATA_WIDTH-1:1]};
                rx_data_valid <= 1;
                bit_cnt <= 0;
            end
            else if(bit_cnt == 0 && rx_data_valid) begin
                rx_data_valid <= 0;
            end
            else begin
                bit_cnt <= bit_cnt + 1;
                rx_data_valid <= 0;
            end
        end


    end

end

endmodule