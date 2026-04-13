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

// CDC Synchronizer registers for PLL_clk domain
reg ser_en_pll_sync1;
reg ser_en_pll_sync2;
reg ser_en_pll_dl;

wire rising_ser_en_pll;

// ======================================================
// Latch input data when Ser_en goes high (mb_clk domain)
// ======================================================
// Note: Normally we want in_data to be stable when Ser_en goes high
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        load_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        if (Ser_en) begin
            load_reg <= in_data;
        end
    end
end

// ======================================================
// CDC: Synchronize Ser_en into PLL_clk domain
// ======================================================
always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        ser_en_pll_sync1 <= 1'b0;
        ser_en_pll_sync2 <= 1'b0;
        ser_en_pll_dl    <= 1'b0;
    end else begin
        ser_en_pll_sync1 <= Ser_en;           // 1st sync flop
        ser_en_pll_sync2 <= ser_en_pll_sync1; // 2nd sync flop
        ser_en_pll_dl    <= ser_en_pll_sync2; // Delay for edge detection
    end
end

// Pulse strictly localized to 1 cycle of PLL_clk
assign rising_ser_en_pll = ser_en_pll_sync2 & ~ser_en_pll_dl;

// ======================================================
// Serializer logic (LSB first) & Counter
// ======================================================
wire load_condition = (rising_ser_en_pll || ser_counter == DATA_WIDTH-1);

always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_reg    <= {DATA_WIDTH{1'b0}};
        ser_counter <= 8'd0;
    end else begin
        if (load_condition) begin
            data_reg    <= load_reg;      // ✅ load
            ser_counter <= 8'd0;          // reset counter
        end else begin
            data_reg    <= {1'b0, data_reg[DATA_WIDTH-1:1]}; // ✅ logical shift right
            ser_counter <= ser_counter + 1'b1;
        end
    end
end 

// ======================================================
// Serialized output (LSB first)
// ======================================================
// Drive 0 when loading/resetting, otherwise drive bit 0
assign SER_out = load_condition ? 1'b0 : data_reg[0]; 

endmodule
