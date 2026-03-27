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

// rising edge detect
reg  Ser_en_reg;
wire rising_ser_en;

assign rising_ser_en = Ser_en & ~Ser_en_reg;

// ======================================================
// Data Latch (load once when serialization starts)
// ======================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_reg   <= 0;
        Ser_en_reg <= 0;
    end 
    else begin
        Ser_en_reg <= Ser_en;

        if (rising_ser_en)
            data_reg <= in_data;
    end
end

// ======================================================
// Serializer Logic
// ======================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        ser_counter <= 0;
        SER_out     <= 0;
    end
    
    else if (Ser_en) begin

        // LSB first
        SER_out <= data_reg[ser_counter];

        ser_counter <= ser_counter + 1;

    end

    else begin
        ser_counter <= 0;
        SER_out     <= 0;
    end
end

endmodule