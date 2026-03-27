`timescale 1ns/1ps

module MB_SERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   mb_clk,
    input  wire                   PLL_clk,
    input  wire                   i_rst_n,
    input  wire                   Ser_en,
    input  wire [DATA_WIDTH-1:0]  in_data,
    output wire                   SER_out
);

// ======================================================
// Internal signals
// ======================================================
reg [7:0]            ser_counter;
reg [DATA_WIDTH-1:0] data_reg;
reg [DATA_WIDTH-1:0] load_reg;
reg                  load_en;
reg                  Ser_en_reg;

wire rising_ser_en;
assign rising_ser_en = Ser_en & ~Ser_en_reg;

// ======================================================
// Latch input data when Ser_en goes high
// ======================================================
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        load_reg   <= 0;
        Ser_en_reg <= 0;
    end else begin
        Ser_en_reg <= Ser_en;
        if (Ser_en)
            load_reg <= in_data;
    end
end

// ======================================================
// Serializer logic (LSB first)
// ======================================================
always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_reg <= 0;
        load_en  <= 0;
    end else begin
        load_en <= 0;
        if (rising_ser_en)
            load_en <= 1;

        if (load_en || ser_counter == DATA_WIDTH-1)
            data_reg <= load_reg;        // ✅ load
        else
            data_reg <= data_reg >> 1;   // ✅ shift right (LSB first)
    end
end

// ======================================================
// Serialized output (LSB first)
// ======================================================
assign SER_out = (load_en || ser_counter == DATA_WIDTH) ? 1'b0 : data_reg[0]; // ✅ bit[0]

// ======================================================
// Serialization counter
// ======================================================
always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        ser_counter <= 0;
    else if (ser_counter == DATA_WIDTH-1 || load_en)
        ser_counter <= 0;
    else
        ser_counter <= ser_counter + 1;
end

endmodule