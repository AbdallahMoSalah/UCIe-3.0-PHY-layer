module MB_SERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   i_clk,
    input  wire                   i_rst_n,
    input  wire                   Ser_en,
    input  wire [DATA_WIDTH-1:0]  in_data,
    output reg                    SER_out
);

// counter width = log2(DATA_WIDTH)
reg [$clog2(DATA_WIDTH)-1:0] ser_counter;

// register to hold data during serialization
reg [DATA_WIDTH-1:0] data_reg;

// ======================================================
// Serializer Logic
// ======================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        SER_out     <= 1'b0;
        ser_counter <= 0;
        data_reg    <= 0;
    end
    
    else if (Ser_en) begin
        
        // latch data only at start of serialization
        if (ser_counter == 0)
            data_reg <= in_data;

        // output serialized bit (LSB first)
        SER_out <= data_reg[ser_counter];

        // increment counter
        if (ser_counter == DATA_WIDTH-1)
            ser_counter <= 0;
        else
            ser_counter <= ser_counter + 1;
    end

    else begin
        ser_counter <= 0;
        SER_out     <= 0;
    end
end

endmodule